//
//  ChatService.swift
//  Envoy
//
//  Unified chat service supporting all LLM providers.
//  Handles provider selection, streaming responses, and stats tracking.
//

import AgentKit
import Foundation
import SwiftUI

// MARK: - Chat Service

/// Unified service for chat interactions with any LLM provider
/// Supports MLX, Ollama, OpenAI, Anthropic, and more
@MainActor
@Observable
public final class ChatService {
    public static let shared = ChatService()

    // MARK: - State

    /// Currently selected provider configuration
    public private(set) var selectedProvider: ProviderConfig?

    /// Currently loaded model ID (for MLX/Ollama)
    public private(set) var loadedModelId: String?

    /// Whether a model is currently loading
    public private(set) var isLoadingModel = false

    /// Whether inference is currently running
    public private(set) var isGenerating = false

    /// Last error message
    public private(set) var lastError: String?

    /// Model load progress (0-1) for MLX
    public private(set) var loadProgress: Double = 0

    /// Current generation stats
    public private(set) var generationStats: GenerationStats?

    // MARK: - Private

    private var mlxProvider: MLXProvider?
    private var activeProvider: (any LLMProvider)?
    private let providerManager = ProviderConfigManager.shared

    private init() {}

    // MARK: - Ready State

    /// Check if chat service is ready to send messages
    public var isReady: Bool {
        activeProvider != nil || mlxProvider != nil
    }

    /// Human-readable description of current provider
    public var providerDescription: String {
        if let modelId = loadedModelId {
            let shortName = modelId.components(separatedBy: "/").last ?? modelId
            return shortName
        }
        if let provider = selectedProvider {
            if let model = provider.selectedModel {
                return "\(provider.name): \(model)"
            }
            return provider.name
        }
        return "No provider"
    }

    // MARK: - Provider Selection

    /// Select a provider configuration
    public func selectProvider(_ config: ProviderConfig) async throws {
        selectedProvider = config
        loadedModelId = nil
        mlxProvider = nil
        activeProvider = nil

        switch config.type {
        case .appleFoundation:
            // Apple Foundation Models uses on-device inference
            activeProvider = FoundationModelsProvider()
            loadedModelId = "Apple Intelligence"

        case .mlx:
            // MLX requires explicit model loading
            break

        case .ollama:
            guard let urlString = config.serverURL,
                  let url = URL(string: urlString) else {
                throw ChatError.invalidConfiguration("Missing server URL")
            }
            let model = config.selectedModel ?? "llama3.2"
            activeProvider = OllamaProvider(baseURL: url, model: model)
            loadedModelId = model

        case .lmStudio:
            guard let urlString = config.serverURL,
                  let url = URL(string: urlString),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let host = components.host else {
                throw ChatError.invalidConfiguration("Missing server URL")
            }
            let port = components.port ?? 1234
            let model = config.selectedModel ?? "local-model"
            activeProvider = LMStudioProvider(host: host, port: port, defaultModel: model)
            loadedModelId = model

        case .anthropic:
            guard let apiKey = config.apiKey, !apiKey.isEmpty else {
                throw ChatError.invalidConfiguration("Missing API key")
            }
            let model = config.selectedModel ?? "claude-sonnet-4-5-20251101"
            activeProvider = AnthropicProvider(apiKey: apiKey, model: model)
            loadedModelId = model

        case .openai, .googleAI, .openRouter, .custom:
            // Use OpenAI-compatible provider for these
            guard let apiKey = config.apiKey, !apiKey.isEmpty else {
                throw ChatError.invalidConfiguration("Missing API key")
            }
            let baseURL = config.serverURL.flatMap { URL(string: $0) }
                ?? defaultBaseURL(for: config.type)
            let model = config.selectedModel ?? defaultModel(for: config.type)
            activeProvider = OpenAICompatibleProvider(
                baseURL: baseURL,
                apiKey: apiKey,
                defaultModel: model,
                name: config.name
            )
            loadedModelId = model
        }

        print("✅ ChatService: Selected provider - \(config.name)")
    }

    private func defaultBaseURL(for type: ProviderType) -> URL {
        switch type {
        case .openai: return URL(string: "https://api.openai.com/v1")!
        case .googleAI: return URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1")!
        default: return URL(string: "https://api.openai.com/v1")!
        }
    }

    private func defaultModel(for type: ProviderType) -> String {
        switch type {
        case .openai: return "gpt-4o"
        case .googleAI: return "gemini-2.0-flash"
        case .openRouter: return "anthropic/claude-3.5-sonnet"
        default: return "gpt-4o"
        }
    }

    // MARK: - MLX Model Loading

    /// Load an MLX model for direct inference
    /// - Parameter modelId: HuggingFace model ID (e.g., "mlx-community/Qwen2.5-7B-Instruct-4bit")
    public func loadMLXModel(_ modelId: String) async throws {
        // Don't reload if already loaded
        guard loadedModelId != modelId else { return }

        isLoadingModel = true
        loadProgress = 0
        lastError = nil

        do {
            // Unload previous MLX model
            if let existing = mlxProvider {
                await existing.unload()
            }
            activeProvider = nil

            // Create new MLX provider (will download if needed)
            let newProvider = MLXProvider(modelId: modelId, lazyLoad: false)

            loadProgress = 0.1

            // Check availability (downloads model if needed)
            let available = await newProvider.isAvailable()
            guard available else {
                throw ChatError.modelNotAvailable(modelId)
            }

            loadProgress = 0.5

            // Warm up with a simple prompt to ensure weights are loaded
            let warmupMessages = [Message(role: .user, content: [.text("Hi")])]
            let stream = try await newProvider.complete(warmupMessages, tools: [], options: .init())

            // Consume the warmup stream
            for try await _ in stream {}

            loadProgress = 1.0
            mlxProvider = newProvider
            loadedModelId = modelId
            selectedProvider = ProviderConfig(type: .mlx, name: "MLX", selectedModel: modelId)
            isLoadingModel = false

            print("✅ ChatService: MLX model loaded - \(modelId)")
        } catch {
            isLoadingModel = false
            loadProgress = 0
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Unload the current model to free memory
    public func unloadModel() async {
        if let mlx = mlxProvider {
            await mlx.unload()
        }
        mlxProvider = nil
        activeProvider = nil
        loadedModelId = nil
        selectedProvider = nil
        generationStats = nil
    }

    // MARK: - Chat

    /// Send a message and get a streaming response
    /// - Parameters:
    ///   - prompt: The user's message
    ///   - systemPrompt: Optional system prompt for context
    ///   - history: Previous messages for context
    /// - Returns: AsyncStream of response text chunks
    public func chat(
        prompt: String,
        systemPrompt: String? = nil,
        history: [ChatMessage] = []
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get provider (prefer MLX if loaded, otherwise use activeProvider)
                    let provider: any LLMProvider
                    if let mlx = self.mlxProvider {
                        provider = mlx
                    } else if let active = self.activeProvider {
                        provider = active
                    } else {
                        throw ChatError.noProviderSelected
                    }

                    await MainActor.run {
                        self.isGenerating = true
                        self.lastError = nil
                        self.generationStats = nil
                    }

                    // Build messages array
                    var messages: [Message] = []

                    // Add system prompt if provided
                    if let system = systemPrompt {
                        messages.append(Message(role: .system, content: [.text(system)]))
                    } else {
                        messages.append(Message(
                            role: .system,
                            content: [.text("You are a helpful AI assistant. Be concise and direct in your responses.")]
                        ))
                    }

                    // Add history
                    for msg in history {
                        let role: Message.Role = msg.isUser ? .user : .assistant
                        messages.append(Message(role: role, content: [.text(msg.content)]))
                    }

                    // Add current prompt
                    messages.append(Message(role: .user, content: [.text(prompt)]))

                    // Track timing
                    let startTime = Date()
                    var totalTokens = 0
                    var firstTokenTime: Date?

                    // Generate response
                    let stream = try await provider.complete(
                        messages,
                        tools: [],
                        options: CompletionOptions(maxTokens: 2048, temperature: 0.7)
                    )

                    for try await event in stream {
                        switch event {
                        case .textDelta(let delta):
                            if firstTokenTime == nil {
                                firstTokenTime = Date()
                            }
                            continuation.yield(delta)

                        case .text(let text):
                            // Non-streaming response
                            continuation.yield(text)

                        case .usage(let usage):
                            totalTokens = usage.outputTokens

                        case .done:
                            let endTime = Date()
                            let totalDuration = endTime.timeIntervalSince(startTime)
                            let ttft = firstTokenTime?.timeIntervalSince(startTime) ?? 0

                            await MainActor.run {
                                self.generationStats = GenerationStats(
                                    tokensGenerated: totalTokens,
                                    totalDuration: totalDuration,
                                    timeToFirstToken: ttft,
                                    tokensPerSecond: totalDuration > 0 ? Double(totalTokens) / totalDuration : 0
                                )
                            }

                        case .error(let error):
                            throw ChatError.generationFailed(error.localizedDescription)

                        case .toolCall:
                            // Tool calls not handled in simple chat mode
                            break
                        }
                    }

                    await MainActor.run {
                        self.isGenerating = false
                    }
                    continuation.finish()

                } catch {
                    await MainActor.run {
                        self.isGenerating = false
                        self.lastError = error.localizedDescription
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Simple non-streaming chat (collects full response)
    public func chatSync(
        prompt: String,
        systemPrompt: String? = nil,
        history: [ChatMessage] = []
    ) async throws -> String {
        var response = ""
        let stream = chat(prompt: prompt, systemPrompt: systemPrompt, history: history)

        for try await chunk in stream {
            response += chunk
        }

        return response
    }

    // MARK: - Agentic Chat (with Tools)

    /// Chat event for streaming agentic interactions
    public enum AgenticChatEvent: Sendable {
        case textDelta(String)
        case toolCall(name: String, argumentsJSON: String)
        case toolResult(name: String, result: String, isError: Bool)
        case done
    }

    /// Send a message with tool support for agentic chat
    /// - Parameters:
    ///   - prompt: The user's message
    ///   - systemPrompt: Optional system prompt for context
    ///   - history: Previous messages for context
    ///   - tools: Available tools for the assistant to use
    ///   - toolExecutor: Closure to execute a tool and return result
    /// - Returns: AsyncStream of chat events including tool calls
    public func agenticChat(
        prompt: String,
        systemPrompt: String? = nil,
        history: [ChatMessage] = [],
        tools: [any Tool]
    ) -> AsyncThrowingStream<AgenticChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get provider
                    let provider: any LLMProvider
                    if let mlx = self.mlxProvider {
                        provider = mlx
                    } else if let active = self.activeProvider {
                        provider = active
                    } else {
                        throw ChatError.noProviderSelected
                    }

                    await MainActor.run {
                        self.isGenerating = true
                        self.lastError = nil
                    }

                    // Build messages array
                    var messages: [Message] = []

                    // Add system prompt
                    let system = systemPrompt ?? """
                        You are a helpful AI assistant with access to tools.
                        Use the available tools when appropriate to help the user.
                        Be concise and direct in your responses.
                        """
                    messages.append(Message(role: .system, content: [.text(system)]))

                    // Add history
                    for msg in history {
                        let role: Message.Role = msg.isUser ? .user : .assistant
                        messages.append(Message(role: role, content: [.text(msg.content)]))
                    }

                    // Add current prompt
                    messages.append(Message(role: .user, content: [.text(prompt)]))

                    // Convert tools to definitions
                    let toolDefinitions = tools.map { $0.toDefinition() }

                    // Create tool lookup for execution
                    let toolLookup = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

                    // Agentic loop - continue until no more tool calls
                    var maxIterations = 10
                    var iteration = 0

                    while iteration < maxIterations {
                        iteration += 1

                        let stream = try await provider.complete(
                            messages,
                            tools: toolDefinitions,
                            options: CompletionOptions(maxTokens: 4096, temperature: 0.7)
                        )

                        var pendingToolCalls: [(id: String, name: String, input: ToolInput)] = []
                        var textContent = ""

                        for try await event in stream {
                            switch event {
                            case .textDelta(let delta):
                                textContent += delta
                                continuation.yield(.textDelta(delta))

                            case .text(let text):
                                textContent += text
                                continuation.yield(.textDelta(text))

                            case .toolCall(let toolCall):
                                pendingToolCalls.append((toolCall.id, toolCall.name, toolCall.input))
                                // Serialize to JSON for the event
                                let args = toolCall.input.parameters.mapValues { $0.value }
                                let jsonData = try? JSONSerialization.data(withJSONObject: args)
                                let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                                continuation.yield(.toolCall(name: toolCall.name, argumentsJSON: jsonString))

                            case .done:
                                break

                            case .usage, .error:
                                break
                            }
                        }

                        // If no tool calls, we're done
                        if pendingToolCalls.isEmpty {
                            continuation.yield(.done)
                            break
                        }

                        // Execute tool calls and add results to messages
                        var toolResultContents: [MessageContent] = []

                        for toolCall in pendingToolCalls {
                            let result: ToolOutput

                            if let tool = toolLookup[toolCall.name] {
                                // Execute the tool
                                let context = ToolContext(
                                    session: Session(workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)),
                                    workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                                )
                                do {
                                    result = try await tool.execute(toolCall.input, context: context)
                                } catch {
                                    result = .error("Tool execution failed: \(error.localizedDescription)")
                                }
                            } else {
                                result = .error("Unknown tool: \(toolCall.name)")
                            }

                            continuation.yield(.toolResult(name: toolCall.name, result: result.content, isError: result.isError))

                            // Add tool result to message content
                            toolResultContents.append(.toolResult(ToolResult(
                                toolUseId: toolCall.id,
                                content: result.content,
                                isError: result.isError
                            )))
                        }

                        // Add assistant message with tool calls
                        if !textContent.isEmpty {
                            messages.append(Message(role: .assistant, content: [.text(textContent)]))
                        }

                        // Add tool results as user message
                        messages.append(Message(role: .user, content: toolResultContents))
                    }

                    await MainActor.run {
                        self.isGenerating = false
                    }
                    continuation.finish()

                } catch {
                    await MainActor.run {
                        self.isGenerating = false
                        self.lastError = error.localizedDescription
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Memory Info (MLX only)

    /// Get current GPU memory usage (MLX only)
    public func memoryUsage() async -> (peak: Int, current: Int)? {
        guard let mlx = mlxProvider else { return nil }
        return await mlx.memoryUsage()
    }

    /// Format memory for display
    public func formattedMemoryUsage() async -> String? {
        guard let usage = await memoryUsage() else { return nil }
        return "\(MLXProvider.formatMemory(usage.current)) / \(MLXProvider.formatMemory(usage.peak)) peak"
    }
}

// MARK: - Supporting Types

/// A simple chat message
public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public let content: String
    public let isUser: Bool
    public let timestamp: Date

    public init(content: String, isUser: Bool) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
    }
}

/// Statistics from a generation
public struct GenerationStats: Sendable {
    public let tokensGenerated: Int
    public let totalDuration: TimeInterval
    public let timeToFirstToken: TimeInterval
    public let tokensPerSecond: Double

    public var formattedTPS: String {
        String(format: "%.1f tok/s", tokensPerSecond)
    }

    public var formattedTTFT: String {
        String(format: "%.2fs", timeToFirstToken)
    }
}

/// Chat service errors
public enum ChatError: LocalizedError {
    case noProviderSelected
    case modelNotAvailable(String)
    case generationFailed(String)
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .noProviderSelected:
            return "No provider selected. Please select a model or provider first."
        case .modelNotAvailable(let id):
            return "Model not available: \(id)"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        }
    }
}
