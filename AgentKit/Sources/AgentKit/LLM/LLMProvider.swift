import Foundation

// MARK: - LLM Provider Protocol

/// Protocol for LLM inference providers
///
/// Implementations:
/// - `OllamaProvider` - Local Ollama server
/// - `LMStudioProvider` - LM Studio OpenAI-compatible API
/// - `FoundationModelsProvider` - Apple Foundation Models (GMS/PCC)
/// - `OpenAIProvider` - OpenAI API
/// - `AnthropicProvider` - Anthropic Claude API
/// - `MockLLMProvider` - Testing
public protocol LLMProvider: Sendable {
    /// Provider identifier
    var id: String { get }

    /// Human-readable provider name
    var name: String { get }

    /// Whether this provider supports tool/function calling
    var supportsToolCalling: Bool { get }

    /// Whether this provider supports streaming
    var supportsStreaming: Bool { get }

    /// Generate a streaming completion from messages
    func complete(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error>

    /// Check if the provider is available/reachable
    func isAvailable() async -> Bool
}

// MARK: - Default Implementation

extension LLMProvider {
    public var supportsToolCalling: Bool { true }
    public var supportsStreaming: Bool { true }

    public func complete(_ messages: [Message]) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        try await complete(messages, tools: [], options: .default)
    }

    public func complete(
        _ messages: [Message],
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        try await complete(messages, tools: tools, options: .default)
    }

    public func isAvailable() async -> Bool { true }
}

// MARK: - Completion Options

/// Options for completion requests
public struct CompletionOptions: Sendable {
    /// Model identifier (provider-specific)
    public let model: String?

    /// Maximum tokens to generate
    public let maxTokens: Int?

    /// Temperature (0.0 - 2.0)
    public let temperature: Double?

    /// Top-p sampling
    public let topP: Double?

    /// Stop sequences
    public let stopSequences: [String]?

    /// System prompt override
    public let systemPrompt: String?

    /// Whether to stream responses
    public let stream: Bool

    public static let `default` = CompletionOptions()

    public init(
        model: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stopSequences: [String]? = nil,
        systemPrompt: String? = nil,
        stream: Bool = true
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stopSequences = stopSequences
        self.systemPrompt = systemPrompt
        self.stream = stream
    }
}

// MARK: - LLM Events

/// Events from LLM generation
public enum LLMEvent: Sendable {
    /// Text content delta
    case textDelta(String)

    /// Complete text (for non-streaming)
    case text(String)

    /// Tool call request
    case toolCall(LLMToolCall)

    /// Usage statistics
    case usage(LLMUsage)

    /// Generation complete
    case done

    /// Error during generation
    case error(LLMError)
}

public struct LLMToolCall: Sendable, Codable {
    public let id: String
    public let name: String
    public let input: ToolInput

    public init(id: String, name: String, input: ToolInput) {
        self.id = id
        self.name = name
        self.input = input
    }
}

public struct LLMUsage: Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = inputTokens + outputTokens
    }
}

public enum LLMError: Error, Sendable {
    case providerUnavailable(String)
    case modelNotFound(String)
    case rateLimited(retryAfter: TimeInterval?)
    case contextLengthExceeded(max: Int, requested: Int)
    case invalidRequest(String)
    case networkError(String)
    case authenticationFailed
    case unknown(String)
}

// MARK: - Tool Definition

/// Tool definition for LLM (subset of Tool for serialization)
public struct ToolDefinition: Sendable, Codable {
    public let name: String
    public let description: String
    public let inputSchema: ToolSchema

    public init(name: String, description: String, inputSchema: ToolSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public init(from tool: any Tool) {
        self.name = tool.name
        self.description = tool.description
        self.inputSchema = tool.inputSchema
    }
}

// MARK: - Provider Registry

/// Registry for available LLM providers
public actor ProviderRegistry {
    public static let shared = ProviderRegistry()

    private var providers: [String: any LLMProvider] = [:]
    private var defaultProviderId: String?

    private init() {}

    /// Register a provider
    public func register(_ provider: any LLMProvider) {
        providers[provider.id] = provider
        if defaultProviderId == nil {
            defaultProviderId = provider.id
        }
    }

    /// Get a provider by ID
    public func provider(id: String) -> (any LLMProvider)? {
        providers[id]
    }

    /// Get the default provider
    public func defaultProvider() -> (any LLMProvider)? {
        guard let id = defaultProviderId else { return nil }
        return providers[id]
    }

    /// Set the default provider
    public func setDefault(id: String) {
        if providers[id] != nil {
            defaultProviderId = id
        }
    }

    /// List all registered providers
    public func allProviders() -> [any LLMProvider] {
        Array(providers.values)
    }

    /// Find available providers
    public func availableProviders() async -> [any LLMProvider] {
        var available: [any LLMProvider] = []
        for provider in providers.values {
            if await provider.isAvailable() {
                available.append(provider)
            }
        }
        return available
    }
}

// MARK: - Mock Provider (for testing)

/// Mock LLM provider for testing
public actor MockLLMProvider: LLMProvider {
    public let id = "mock"
    public let name = "Mock Provider"
    public let supportsToolCalling = true
    public let supportsStreaming = true

    private var responses: [String]
    private var responseIndex = 0
    private var toolCallResponses: [LLMToolCall] = []

    public init(responses: [String] = ["Hello, I'm a mock assistant."]) {
        self.responses = responses
    }

    /// Add a tool call response
    public func addToolCallResponse(_ toolCall: LLMToolCall) {
        toolCallResponses.append(toolCall)
    }

    public func complete(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        let response = responses[responseIndex % responses.count]
        let toolCalls = toolCallResponses
        responseIndex += 1

        return AsyncThrowingStream { continuation in
            Task {
                // Emit any pending tool calls first
                for toolCall in toolCalls {
                    continuation.yield(.toolCall(toolCall))
                }

                // Simulate streaming by yielding words
                if options.stream {
                    let words = response.split(separator: " ")
                    for (index, word) in words.enumerated() {
                        let text = index == 0 ? String(word) : " " + String(word)
                        continuation.yield(.textDelta(text))
                        try? await Task.sleep(for: .milliseconds(10))
                    }
                } else {
                    continuation.yield(.text(response))
                }

                // Emit usage
                continuation.yield(.usage(LLMUsage(
                    inputTokens: messages.reduce(0) { $0 + ($1.textContent.count / 4) },
                    outputTokens: response.count / 4
                )))

                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    public func isAvailable() async -> Bool { true }
}

// MARK: - Legacy Compatibility

/// Legacy token type for backwards compatibility
@available(*, deprecated, renamed: "LLMEvent")
public typealias LLMToken = LLMEvent
