import Foundation

// MARK: - OpenAI Compatible Provider

/// Base provider for OpenAI-compatible APIs
///
/// This provider works with:
/// - LM Studio (local)
/// - vLLM (local/cloud)
/// - LocalAI (local)
/// - text-generation-webui (local)
/// - OpenRouter (cloud)
/// - Together.ai (cloud)
/// - Fireworks.ai (cloud)
/// - Any other OpenAI-compatible endpoint
///
/// Usage:
/// ```swift
/// // LM Studio
/// let lmStudio = OpenAICompatibleProvider(
///     baseURL: URL(string: "http://localhost:1234/v1")!,
///     name: "LM Studio"
/// )
///
/// // OpenRouter
/// let openRouter = OpenAICompatibleProvider(
///     baseURL: URL(string: "https://openrouter.ai/api/v1")!,
///     apiKey: "sk-or-...",
///     name: "OpenRouter"
/// )
/// ```
public actor OpenAICompatibleProvider: LLMProvider {
    public let id: String
    public let name: String
    public let supportsToolCalling: Bool
    public let supportsStreaming: Bool

    private let baseURL: URL
    private let apiKey: String?
    private let defaultModel: String
    private let session: URLSession
    private let organizationId: String?

    public init(
        baseURL: URL,
        apiKey: String? = nil,
        defaultModel: String = "gpt-3.5-turbo",
        name: String = "OpenAI Compatible",
        supportsToolCalling: Bool = true,
        supportsStreaming: Bool = true,
        organizationId: String? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.defaultModel = defaultModel
        self.name = name
        self.id = "openai-\(baseURL.host ?? "local")"
        self.supportsToolCalling = supportsToolCalling
        self.supportsStreaming = supportsStreaming
        self.organizationId = organizationId
        self.session = URLSession(configuration: .default)
    }

    public func complete(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        let model = options.model ?? defaultModel

        // Build request body
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

        // Add tools if provided and supported
        if !tools.isEmpty && supportsToolCalling {
            body["tools"] = tools.map { openAITool(from: $0) }
            body["tool_choice"] = "auto"
        }

        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if let orgId = organizationId {
            request.setValue(orgId, forHTTPHeaderField: "OpenAI-Organization")
        }

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
                            // Emit any completed tool calls
                            for (_, partial) in pendingToolCalls {
                                if let toolCall = partial.complete() {
                                    continuation.yield(.toolCall(toolCall))
                                }
                            }
                            continuation.yield(.done)
                            break
                        }

                        guard let data = json.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data)
                        else { continue }

                        if let choice = chunk.choices.first {
                            // Handle content delta
                            if let content = choice.delta.content {
                                continuation.yield(.textDelta(content))
                            }

                            // Handle tool call deltas
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

                            // Handle finish reason
                            if choice.finish_reason != nil {
                                // Emit tool calls if finish reason is tool_calls
                                for (_, partial) in pendingToolCalls {
                                    if let toolCall = partial.complete() {
                                        continuation.yield(.toolCall(toolCall))
                                    }
                                }
                                pendingToolCalls.removeAll()
                            }
                        }

                        // Handle usage
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

                    let result = try JSONDecoder().decode(OpenAICompletion.self, from: data)

                    if let choice = result.choices.first {
                        // Handle tool calls
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

                        // Handle text content
                        if let content = choice.message.content {
                            continuation.yield(.text(content))
                        }
                    }

                    // Handle usage
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
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// List available models
    public func listModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)

        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map(\.id)
    }

    // MARK: - Helpers

    private func openAIMessage(from message: Message) -> [String: Any] {
        // Check if this is a tool result message
        for part in message.content {
            if case .toolResult(let toolResult) = part {
                return [
                    "role": "tool",
                    "tool_call_id": toolResult.toolUseId,
                    "content": toolResult.content
                ]
            }
        }

        // Check if this is an assistant message with tool calls
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

        // Regular message
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
        case 401:
            return .authenticationFailed
        case 429:
            return .rateLimited(retryAfter: nil)
        case 404:
            return .modelNotFound(text)
        default:
            return .providerUnavailable("HTTP \(statusCode): \(text)")
        }
    }
}

// MARK: - Partial Tool Call Builder

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

// MARK: - OpenAI API Types

private struct OpenAIStreamChunk: Decodable {
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

private struct OpenAICompletion: Decodable {
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

private struct OpenAIModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}
