import Foundation

// MARK: - Exo Cluster Provider

/// Provider for Exo distributed inference clusters
///
/// Exo allows running large models across multiple Apple Silicon devices
/// by partitioning the model layers. It exposes an OpenAI-compatible API.
///
/// Features:
/// - Automatic discovery of available models across the cluster
/// - OpenAI-compatible chat completions API
/// - Streaming support
/// - Tool calling (model-dependent)
///
/// Usage:
/// ```swift
/// // Default local cluster
/// let exo = ExoProvider()
///
/// // Custom endpoint (e.g., remote cluster)
/// let exo = ExoProvider(
///     baseURL: URL(string: "http://192.168.1.100:52415")!
/// )
///
/// // Check what models are available
/// let models = try await exo.listModels()
/// print("Available: \(models)")
/// ```
///
/// Exo Cluster Setup:
/// 1. Install on all nodes: `pip install exo`
/// 2. Start on each node: `exo` (auto-discovers peers)
/// 3. Access via any node at port 52415
///
/// Supported Models:
/// - Llama (3.x, 3.1, 3.2, 3.3)
/// - Mistral, Mixtral
/// - DeepSeek
/// - Qwen
/// - And more (see exo documentation)
public actor ExoProvider: LLMProvider {
    public let id: String = "exo-cluster"
    public let name: String = "Exo Cluster"
    public let supportsToolCalling: Bool = true
    public let supportsStreaming: Bool = true

    private let baseURL: URL
    private let defaultModel: String
    private let session: URLSession

    /// Default Exo port
    public static let defaultPort: Int = 52415

    /// Create an Exo provider
    /// - Parameters:
    ///   - baseURL: Exo API endpoint (default: http://localhost:52415)
    ///   - defaultModel: Model to use if none specified (default: llama-3.3-70b)
    public init(
        baseURL: URL? = nil,
        defaultModel: String = "llama-3.3-70b"
    ) {
        self.baseURL = baseURL ?? URL(string: "http://localhost:\(Self.defaultPort)")!
        self.defaultModel = defaultModel
        self.session = URLSession(configuration: .default)
    }

    /// Create provider from host and port
    public init(
        host: String = "localhost",
        port: Int = defaultPort,
        defaultModel: String = "llama-3.3-70b"
    ) {
        self.baseURL = URL(string: "http://\(host):\(port)")!
        self.defaultModel = defaultModel
        self.session = URLSession(configuration: .default)
    }

    public func complete(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        let model = options.model ?? defaultModel

        // Build request body (OpenAI format)
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { openAIMessage(from: $0) },
            "stream": options.stream
        ]

        if let maxTokens = options.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if let temperature = options.temperature {
            body["temperature"] = temperature
        }
        if let topP = options.topP {
            body["top_p"] = topP
        }
        if let stop = options.stopSequences, !stop.isEmpty {
            body["stop"] = stop
        }

        // Add tools if provided
        if !tools.isEmpty {
            body["tools"] = tools.map { openAITool(from: $0) }
            body["tool_choice"] = "auto"
        }

        let url = baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        if options.stream {
            return streamingComplete(request)
        } else {
            return nonStreamingComplete(request)
        }
    }

    private func streamingComplete(_ request: URLRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.yield(.error(.networkError("Invalid response")))
                        continuation.finish()
                        return
                    }

                    if httpResponse.statusCode != 200 {
                        let error = try await parseError(from: bytes, statusCode: httpResponse.statusCode)
                        continuation.yield(.error(error))
                        continuation.finish()
                        return
                    }

                    var pendingToolCalls: [String: PartialToolCall] = [:]

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))

                        if json == "[DONE]" {
                            for (_, partial) in pendingToolCalls {
                                if let toolCall = partial.complete() {
                                    continuation.yield(.toolCall(toolCall))
                                }
                            }
                            continuation.yield(.done)
                            break
                        }

                        guard let data = json.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data)
                        else { continue }

                        if let choice = chunk.choices.first {
                            if let content = choice.delta.content {
                                continuation.yield(.textDelta(content))
                            }

                            if let toolCallDeltas = choice.delta.tool_calls {
                                for delta in toolCallDeltas {
                                    let id = delta.id ?? String(delta.index)
                                    var partial = pendingToolCalls[id] ?? PartialToolCall()

                                    if let toolId = delta.id {
                                        partial.id = toolId
                                    }
                                    if let function = delta.function {
                                        if let name = function.name {
                                            partial.name = name
                                        }
                                        if let args = function.arguments {
                                            partial.arguments += args
                                        }
                                    }

                                    pendingToolCalls[id] = partial
                                }
                            }

                            if choice.finish_reason != nil {
                                for (_, partial) in pendingToolCalls {
                                    if let toolCall = partial.complete() {
                                        continuation.yield(.toolCall(toolCall))
                                    }
                                }
                                pendingToolCalls.removeAll()
                            }
                        }

                        if let usage = chunk.usage {
                            continuation.yield(.usage(LLMUsage(
                                inputTokens: usage.prompt_tokens,
                                outputTokens: usage.completion_tokens
                            )))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.yield(.error(.networkError(error.localizedDescription)))
                    continuation.finish()
                }
            }
        }
    }

    private func nonStreamingComplete(_ request: URLRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let (data, response) = try await session.data(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.yield(.error(.networkError("Invalid response")))
                        continuation.finish()
                        return
                    }

                    if httpResponse.statusCode != 200 {
                        let error = parseErrorFromData(data, statusCode: httpResponse.statusCode)
                        continuation.yield(.error(error))
                        continuation.finish()
                        return
                    }

                    let result = try JSONDecoder().decode(Completion.self, from: data)

                    if let choice = result.choices.first {
                        if let toolCalls = choice.message.tool_calls {
                            for toolCall in toolCalls {
                                let input = parseToolArguments(toolCall.function.arguments)
                                continuation.yield(.toolCall(LLMToolCall(
                                    id: toolCall.id,
                                    name: toolCall.function.name,
                                    input: input
                                )))
                            }
                        }

                        if let content = choice.message.content {
                            continuation.yield(.text(content))
                        }
                    }

                    if let usage = result.usage {
                        continuation.yield(.usage(LLMUsage(
                            inputTokens: usage.prompt_tokens,
                            outputTokens: usage.completion_tokens
                        )))
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(.networkError(error.localizedDescription)))
                    continuation.finish()
                }
            }
        }
    }

    public func isAvailable() async -> Bool {
        let url = baseURL.appendingPathComponent("v1/models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// List models available across the Exo cluster
    public func listModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("v1/models")
        let request = URLRequest(url: url)
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return response.data.map { $0.id }
    }

    /// Get cluster status information
    public func clusterStatus() async throws -> ClusterStatus {
        // Exo exposes cluster info at the root endpoint
        let request = URLRequest(url: baseURL)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw LLMError.providerUnavailable("Cluster not responding")
        }

        // Parse cluster info if available, otherwise return basic status
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let nodeCount = (json["nodes"] as? [[String: Any]])?.count ?? 1
            let modelLoaded = json["model"] as? String
            return ClusterStatus(
                isActive: true,
                nodeCount: nodeCount,
                currentModel: modelLoaded
            )
        }

        return ClusterStatus(isActive: true, nodeCount: 1, currentModel: nil)
    }

    // MARK: - Helpers

    private func openAIMessage(from message: Message) -> [String: Any] {
        for part in message.content {
            if case .toolResult(let toolResult) = part {
                return [
                    "role": "tool",
                    "tool_call_id": toolResult.toolUseId,
                    "content": toolResult.content
                ]
            }
        }

        var toolCalls: [[String: Any]] = []
        for part in message.content {
            if case .toolUse(let toolUse) = part {
                toolCalls.append([
                    "id": toolUse.id,
                    "type": "function",
                    "function": [
                        "name": toolUse.name,
                        "arguments": jsonString(from: toolUse.input.parameters)
                    ]
                ])
            }
        }

        if !toolCalls.isEmpty {
            return [
                "role": "assistant",
                "tool_calls": toolCalls
            ]
        }

        return [
            "role": message.role.rawValue,
            "content": message.textContent
        ]
    }

    private func jsonString(from parameters: [String: AnyCodable]) -> String {
        let dict = parameters.mapValues { $0.value }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    private func openAITool(from tool: ToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "function": [
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
            ]
        ]
    }

    private func parseToolArguments(_ jsonString: String) -> ToolInput {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ToolInput(parameters: [:])
        }

        let params = json.mapValues { AnyCodable($0) }
        return ToolInput(parameters: params)
    }

    private func parseError(from bytes: URLSession.AsyncBytes, statusCode: Int) async throws -> LLMError {
        var errorText = ""
        for try await line in bytes.lines {
            errorText += line
        }
        return parseErrorFromText(errorText, statusCode: statusCode)
    }

    private func parseErrorFromData(_ data: Data, statusCode: Int) -> LLMError {
        let text = String(data: data, encoding: .utf8) ?? ""
        return parseErrorFromText(text, statusCode: statusCode)
    }

    private func parseErrorFromText(_ text: String, statusCode: Int) -> LLMError {
        switch statusCode {
        case 404:
            return .modelNotFound(text)
        case 503:
            return .providerUnavailable("Cluster not ready: \(text)")
        default:
            return .providerUnavailable("HTTP \(statusCode): \(text)")
        }
    }
}

// MARK: - Cluster Status

extension ExoProvider {
    /// Status of the Exo cluster
    public struct ClusterStatus: Sendable {
        /// Whether the cluster is responding
        public let isActive: Bool
        /// Number of nodes in the cluster
        public let nodeCount: Int
        /// Currently loaded model (if any)
        public let currentModel: String?
    }
}

// MARK: - API Types

extension ExoProvider {
    private struct PartialToolCall {
        var id: String = ""
        var name: String = ""
        var arguments: String = ""

        func complete() -> LLMToolCall? {
            guard !id.isEmpty, !name.isEmpty else { return nil }

            let input: ToolInput
            if let data = arguments.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                let params = json.mapValues { AnyCodable($0) }
                input = ToolInput(parameters: params)
            } else {
                input = ToolInput(parameters: [:])
            }

            return LLMToolCall(id: id, name: name, input: input)
        }
    }

    private struct StreamChunk: Decodable {
        let id: String?
        let choices: [StreamChoice]
        let usage: Usage?

        struct StreamChoice: Decodable {
            let index: Int
            let delta: Delta
            let finish_reason: String?
        }

        struct Delta: Decodable {
            let role: String?
            let content: String?
            let tool_calls: [ToolCallDelta]?
        }

        struct ToolCallDelta: Decodable {
            let index: Int
            let id: String?
            let type: String?
            let function: FunctionDelta?
        }

        struct FunctionDelta: Decodable {
            let name: String?
            let arguments: String?
        }

        struct Usage: Decodable {
            let prompt_tokens: Int
            let completion_tokens: Int
        }
    }

    private struct Completion: Decodable {
        let id: String
        let choices: [Choice]
        let usage: Usage?

        struct Choice: Decodable {
            let index: Int
            let message: ResponseMessage
            let finish_reason: String?
        }

        struct ResponseMessage: Decodable {
            let role: String
            let content: String?
            let tool_calls: [ToolCall]?
        }

        struct ToolCall: Decodable {
            let id: String
            let type: String
            let function: FunctionCall
        }

        struct FunctionCall: Decodable {
            let name: String
            let arguments: String
        }

        struct Usage: Decodable {
            let prompt_tokens: Int
            let completion_tokens: Int
        }
    }

    private struct ModelsResponse: Decodable {
        let data: [Model]

        struct Model: Decodable {
            let id: String
        }
    }
}
