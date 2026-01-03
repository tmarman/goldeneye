import Foundation
import MLX
import MLXNN
import MLXLLM
import MLXLMCommon
import MLXRandom

// MARK: - MLX Provider

/// Native MLX-based LLM provider for Apple Silicon
///
/// Provides the fastest local inference on Apple Silicon using MLX.
/// Supports models from Hugging Face Hub (mlx-community).
///
/// Performance (M2 Ultra, 192GB):
/// - ~230 tok/s for 8B models
/// - ~45 tok/s for 70B models
///
/// Usage:
/// ```swift
/// // Load from Hugging Face Hub
/// let provider = try await MLXProvider(modelId: "mlx-community/Qwen2.5-72B-Instruct-4bit")
///
/// // Or from local path
/// let provider = try await MLXProvider(modelPath: URL(fileURLWithPath: "~/.cache/huggingface/..."))
///
/// // Lazy load (downloads on first use)
/// let provider = MLXProvider(modelId: "mlx-community/Qwen2.5-7B-Instruct-4bit", lazyLoad: true)
/// ```
public actor MLXProvider: LLMProvider {
    public let id: String
    public let name = "MLX"
    public let supportsToolCalling = true
    public let supportsStreaming = true

    private var modelContainer: ModelContainer?
    private let modelId: String
    private let configuration: MLXConfiguration
    private var isLoaded = false

    // MARK: - Initialization

    /// Initialize with a Hugging Face model ID (lazy load)
    public init(
        modelId: String,
        configuration: MLXConfiguration = .default,
        lazyLoad: Bool = true
    ) {
        self.modelId = modelId
        self.id = "mlx-\(modelId.split(separator: "/").last ?? Substring(modelId))"
        self.configuration = configuration
        self.isLoaded = false
    }

    /// Initialize with a local model path
    public init(
        modelPath: URL,
        configuration: MLXConfiguration = .default
    ) {
        self.modelId = modelPath.path
        self.id = "mlx-\(modelPath.lastPathComponent)"
        self.configuration = configuration
        self.isLoaded = false
    }

    // MARK: - Model Loading

    private func loadModel() async throws {
        guard !isLoaded else { return }

        // Determine if this is a local path or HF Hub ID
        let modelConfig: ModelConfiguration
        if modelId.hasPrefix("/") || modelId.hasPrefix("~") {
            // Local path
            let url = URL(fileURLWithPath: (modelId as NSString).expandingTildeInPath)
            modelConfig = ModelConfiguration(directory: url)
        } else {
            // Hugging Face Hub ID
            modelConfig = ModelConfiguration(id: modelId)
        }

        // Load model container from HF Hub or local path
        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: modelConfig
        ) { progress in
            // Progress callback for download
            let percent = Int(progress.fractionCompleted * 100)
            if percent % 10 == 0 && progress.fractionCompleted < 1.0 {
                print("[\(self.name)] Loading model: \(percent)%")
            }
        }

        self.modelContainer = container
        self.isLoaded = true
        print("[\(name)] Model loaded: \(modelId)")
    }

    private func ensureLoaded() async throws {
        if !isLoaded {
            try await loadModel()
        }
    }

    // MARK: - LLMProvider Protocol

    public func complete(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        try await ensureLoaded()

        guard let container = modelContainer else {
            throw LLMError.providerUnavailable("Model not loaded")
        }

        // Build prompt from messages using chat template
        let prompt = buildPrompt(from: messages, tools: tools)

        // Create generation parameters
        let maxTokens = options.maxTokens ?? configuration.maxTokens
        let temperature = options.temperature.map { Float($0) } ?? configuration.temperature
        let topP = options.topP.map { Float($0) } ?? configuration.topP
        let stopSequences = options.stopSequences

        let generateParams = GenerateParameters(
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            repetitionPenalty: configuration.repetitionPenalty
        )

        // Capture tools list for later parsing
        let capturedTools = tools

        // Thread-safe state for streaming using class with lock
        let streamState = StreamingState()

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Use MLX's streaming generation
                    try await container.perform { context in
                        // Prepare the prompt
                        let input = try await context.processor.prepare(
                            input: .init(prompt: prompt)
                        )
                        streamState.inputTokens = input.text.tokens.size

                        // Generate tokens with streaming
                        // The callback is synchronous, so we use a thread-safe class
                        let _ = try MLXLMCommon.generate(
                            input: input,
                            parameters: generateParams,
                            context: context
                        ) { tokens in
                            // Decode the current tokens
                            let newText = context.tokenizer.decode(tokens: tokens)
                            let currentLength = newText.count
                            let previousLength = streamState.textLength

                            // Find the new delta (what was just generated)
                            if currentLength > previousLength {
                                let delta = String(newText.dropFirst(previousLength))
                                streamState.appendText(delta)
                                streamState.outputTokens = tokens.count

                                // Yield the delta
                                continuation.yield(.textDelta(delta))
                            }

                            // Check for stop sequences
                            if let stops = stopSequences {
                                for stop in stops {
                                    if newText.contains(stop) {
                                        return .stop
                                    }
                                }
                            }

                            // Check max tokens
                            if tokens.count >= maxTokens {
                                return .stop
                            }

                            return .more
                        }
                    }

                    // Get final state
                    let finalText = streamState.text
                    let inputTokens = streamState.inputTokens
                    let outputTokens = streamState.outputTokens

                    // Parse for tool calls if tools were provided
                    if !capturedTools.isEmpty {
                        let toolCalls = parseToolCalls(from: finalText, tools: capturedTools)
                        for toolCall in toolCalls {
                            continuation.yield(.toolCall(toolCall))
                        }
                    }

                    // Emit usage
                    continuation.yield(.usage(LLMUsage(
                        inputTokens: inputTokens,
                        outputTokens: outputTokens
                    )))

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(.unknown(error.localizedDescription)))
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Streaming State (Thread-Safe Class)

    /// Thread-safe class for streaming state management
    /// Uses a lock for synchronization since MLX callbacks are synchronous
    private final class StreamingState: @unchecked Sendable {
        private let lock = NSLock()
        private var _text: String = ""
        private var _inputTokens: Int = 0
        private var _outputTokens: Int = 0

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return _text
        }

        var textLength: Int {
            lock.lock()
            defer { lock.unlock() }
            return _text.count
        }

        var inputTokens: Int {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _inputTokens
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _inputTokens = newValue
            }
        }

        var outputTokens: Int {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _outputTokens
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _outputTokens = newValue
            }
        }

        func appendText(_ delta: String) {
            lock.lock()
            defer { lock.unlock() }
            _text += delta
        }
    }

    public func isAvailable() async -> Bool {
        // If already loaded, definitely available
        if isLoaded {
            return true
        }

        // Check if this is a local path
        if modelId.hasPrefix("/") || modelId.hasPrefix("~") {
            let path = (modelId as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: path)
        }

        // For HF Hub models, assume available (will download on load)
        return true
    }

    // MARK: - Prompt Building

    private func buildPrompt(from messages: [Message], tools: [ToolDefinition]) -> String {
        var prompt = ""

        // Add tool definitions if present
        if !tools.isEmpty {
            prompt += buildToolPrompt(tools: tools)
        }

        // Build messages into prompt using ChatML format
        // (works with Qwen, Llama 3, Mistral, etc.)
        for message in messages {
            switch message.role {
            case .system:
                prompt += "<|im_start|>system\n\(message.textContent)<|im_end|>\n"
            case .user:
                // Check for tool results
                var content = message.textContent
                for part in message.content {
                    if case .toolResult(let result) = part {
                        content += "\n\nTool result for \(result.toolUseId):\n\(result.content)"
                    }
                }
                prompt += "<|im_start|>user\n\(content)<|im_end|>\n"
            case .assistant:
                // Check for tool uses
                var content = message.textContent
                for part in message.content {
                    if case .toolUse(let use) = part {
                        let argsJson = try? JSONSerialization.data(
                            withJSONObject: use.input.parameters.mapValues { $0.value }
                        )
                        let argsString = argsJson.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        content += "\n{\"name\": \"\(use.name)\", \"arguments\": \(argsString)}"
                    }
                }
                prompt += "<|im_start|>assistant\n\(content)<|im_end|>\n"
            }
        }

        // Start assistant turn
        prompt += "<|im_start|>assistant\n"

        return prompt
    }

    private func buildToolPrompt(tools: [ToolDefinition]) -> String {
        var toolsJson: [[String: Any]] = []

        for tool in tools {
            toolsJson.append([
                "name": tool.name,
                "description": tool.description,
                "parameters": [
                    "type": tool.inputSchema.type,
                    "properties": tool.inputSchema.properties.mapValues { prop in
                        var result: [String: Any] = ["type": prop.type]
                        if let desc = prop.description {
                            result["description"] = desc
                        }
                        if let enumValues = prop.enumValues {
                            result["enum"] = enumValues
                        }
                        return result
                    },
                    "required": tool.inputSchema.required
                ]
            ])
        }

        guard let data = try? JSONSerialization.data(withJSONObject: toolsJson, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        return """
            <|im_start|>system
            You have access to the following tools:
            \(json)

            When you need to use a tool, respond with a JSON object in this exact format:
            {"name": "tool_name", "arguments": {"arg1": "value1"}}

            You can call multiple tools by outputting multiple JSON objects on separate lines.
            After receiving tool results, continue with your response.
            <|im_end|>

            """
    }

    // MARK: - Tool Call Parsing

    private func parseToolCalls(from text: String, tools: [ToolDefinition]) -> [LLMToolCall] {
        var toolCalls: [LLMToolCall] = []

        // Look for JSON objects that look like tool calls
        // Pattern matches: {"name": "...", "arguments": {...}}
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{") && trimmed.contains("\"name\"") else { continue }

            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String,
                  let arguments = json["arguments"] as? [String: Any]
            else { continue }

            // Verify tool exists
            guard tools.contains(where: { $0.name == name }) else { continue }

            let params = arguments.mapValues { AnyCodable($0) }
            toolCalls.append(LLMToolCall(
                id: UUID().uuidString,
                name: name,
                input: ToolInput(parameters: params)
            ))
        }

        return toolCalls
    }

    // MARK: - Model Management

    /// Unload the model to free memory
    public func unload() {
        modelContainer = nil
        isLoaded = false
        print("[\(name)] Model unloaded")
    }

    /// Get the current GPU memory usage
    public func memoryUsage() -> (peak: Int, current: Int) {
        let stats = MLX.GPU.snapshot()
        return (peak: stats.peakMemory, current: stats.activeMemory)
    }

    /// Format memory size for display
    public static func formatMemory(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    /// List available MLX models in local cache
    public static func cachedModels(in directory: URL = defaultModelDirectory) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }

        return contents.filter { url in
            // MLX models are directories containing config.json
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue && FileManager.default.fileExists(
                atPath: url.appendingPathComponent("config.json").path
            )
        }
    }

    /// Default model cache directory
    public static var defaultModelDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
    }

    /// Recommended models from mlx-community
    public static let recommendedModels: [RecommendedModel] = [
        // Small (good for testing, 8GB+ RAM)
        RecommendedModel(
            id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            name: "Qwen 2.5 3B",
            size: "~2 GB",
            description: "Fast, good for testing"
        ),
        // Medium (good balance, 16GB+ RAM)
        RecommendedModel(
            id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            name: "Qwen 2.5 7B",
            size: "~4 GB",
            description: "Good balance of speed and quality"
        ),
        RecommendedModel(
            id: "mlx-community/Llama-3.2-8B-Instruct-4bit",
            name: "Llama 3.2 8B",
            size: "~5 GB",
            description: "Strong general purpose"
        ),
        // Large (high quality, 32GB+ RAM)
        RecommendedModel(
            id: "mlx-community/Qwen2.5-32B-Instruct-4bit",
            name: "Qwen 2.5 32B",
            size: "~18 GB",
            description: "Excellent for complex tasks"
        ),
        // Very Large (best quality, 64GB+ RAM)
        RecommendedModel(
            id: "mlx-community/Qwen2.5-72B-Instruct-4bit",
            name: "Qwen 2.5 72B",
            size: "~40 GB",
            description: "Top tier, requires 64GB+ RAM"
        ),
        RecommendedModel(
            id: "mlx-community/Llama-3.3-70B-Instruct-4bit",
            name: "Llama 3.3 70B",
            size: "~40 GB",
            description: "Meta's best, requires 64GB+ RAM"
        ),
    ]
}

// MARK: - Supporting Types

/// Recommended model info
public struct RecommendedModel: Sendable {
    public let id: String
    public let name: String
    public let size: String
    public let description: String
}

// MARK: - MLX Configuration

public struct MLXConfiguration: Sendable {
    /// Maximum tokens to generate
    public var maxTokens: Int

    /// Temperature for sampling (0.0 = deterministic, higher = more random)
    public var temperature: Float

    /// Top-p (nucleus) sampling
    public var topP: Float

    /// Repetition penalty
    public var repetitionPenalty: Float

    /// Context window size
    public var contextSize: Int

    public static let `default` = MLXConfiguration()

    public init(
        maxTokens: Int = 4096,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        repetitionPenalty: Float = 1.1,
        contextSize: Int = 8192
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.repetitionPenalty = repetitionPenalty
        self.contextSize = contextSize
    }
}
