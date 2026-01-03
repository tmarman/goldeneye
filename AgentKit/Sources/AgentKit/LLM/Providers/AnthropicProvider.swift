import Foundation

// MARK: - Anthropic Provider

/// LLM provider for Anthropic Claude API
///
/// Supports Claude 3.5 Sonnet, Claude 3 Opus, Haiku, and future models.
/// Implements streaming via SSE and tool calling.
///
/// Usage:
/// ```swift
/// let provider = AnthropicProvider(
///     apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]!
/// )
/// ```
public actor AnthropicProvider: LLMProvider {
    public let id: String
    public let name = "Anthropic"
    public let supportsToolCalling = true
    public let supportsStreaming = true

    private let apiKey: String
    private let baseURL: URL
    private let defaultModel: String
    private let session: URLSession
    private let apiVersion: String

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        model: String = "claude-sonnet-4-20250514",
        apiVersion: String = "2023-06-01"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultModel = model
        self.apiVersion = apiVersion
        self.id = "anthropic-\(model)"
        self.session = URLSession(configuration: .default)
    }

    public func complete(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        let model = options.model ?? defaultModel

        // Convert messages to Anthropic format
        let (system, anthropicMessages) = convertMessages(messages, systemPrompt: options.systemPrompt)

        // Build request body
        var body: [String: Any] = [
            "model": model,
            "messages": anthropicMessages,
            "max_tokens": options.maxTokens ?? 4096,
            "stream": options.stream
        ]

        if let system = system {
            body["system"] = system
        }
        if let temperature = options.temperature {
            body["temperature"] = temperature
        }
        if let topP = options.topP {
            body["top_p"] = topP
        }
        if let stop = options.stopSequences, !stop.isEmpty {
            body["stop_sequences"] = stop
        }

        // Add tools if provided
        if !tools.isEmpty {
            body["tools"] = tools.map { anthropicTool(from: $0) }
        }

        let url = baseURL.appendingPathComponent("v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

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

                    var currentToolUseId: String?
                    var currentToolName: String?
                    var currentToolArguments: String = ""
                    var inputUsage = 0
                    var outputUsage = 0

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))

                        guard let data = json.data(using: .utf8),
                              let event = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: data)
                        else { continue }

                        switch event.type {
                        case "message_start":
                            if let usage = event.message?.usage {
                                inputUsage = usage.input_tokens
                            }

                        case "content_block_start":
                            if let block = event.content_block {
                                switch block.type {
                                case "tool_use":
                                    currentToolUseId = block.id
                                    currentToolName = block.name
                                    currentToolArguments = ""
                                default:
                                    break
                                }
                            }

                        case "content_block_delta":
                            if let delta = event.delta {
                                switch delta.type {
                                case "text_delta":
                                    if let text = delta.text {
                                        continuation.yield(.textDelta(text))
                                    }
                                case "input_json_delta":
                                    if let partial = delta.partial_json {
                                        currentToolArguments += partial
                                    }
                                default:
                                    break
                                }
                            }

                        case "content_block_stop":
                            // Emit tool call if we were building one
                            if let toolId = currentToolUseId, let toolName = currentToolName {
                                let input = parseToolArguments(currentToolArguments)
                                continuation.yield(.toolCall(LLMToolCall(
                                    id: toolId,
                                    name: toolName,
                                    input: input
                                )))
                                currentToolUseId = nil
                                currentToolName = nil
                                currentToolArguments = ""
                            }

                        case "message_delta":
                            if let usage = event.usage {
                                outputUsage = usage.output_tokens
                            }

                        case "message_stop":
                            continuation.yield(.usage(LLMUsage(
                                inputTokens: inputUsage,
                                outputTokens: outputUsage
                            )))
                            continuation.yield(.done)

                        default:
                            break
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

                    let result = try JSONDecoder().decode(AnthropicResponse.self, from: data)

                    // Process content blocks
                    for block in result.content {
                        switch block {
                        case .text(let text):
                            continuation.yield(.text(text.text))
                        case .toolUse(let toolUse):
                            let input = ToolInput(parameters: toolUse.input.mapValues { AnyCodable($0) })
                            continuation.yield(.toolCall(LLMToolCall(
                                id: toolUse.id,
                                name: toolUse.name,
                                input: input
                            )))
                        }
                    }

                    // Usage
                    continuation.yield(.usage(LLMUsage(
                        inputTokens: result.usage.input_tokens,
                        outputTokens: result.usage.output_tokens
                    )))

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
        // Check by trying to access the models endpoint
        // For Anthropic, we just verify the API key format
        !apiKey.isEmpty && apiKey.hasPrefix("sk-ant-")
    }

    // MARK: - Helpers

    private func convertMessages(_ messages: [Message], systemPrompt: String?) -> (String?, [[String: Any]]) {
        var system: String? = systemPrompt
        var anthropicMessages: [[String: Any]] = []

        for message in messages {
            // Check for tool results first (these come as user messages in our model)
            var toolResults: [[String: Any]] = []
            for part in message.content {
                if case .toolResult(let toolResult) = part {
                    toolResults.append([
                        "type": "tool_result",
                        "tool_use_id": toolResult.toolUseId,
                        "content": toolResult.content
                    ])
                }
            }

            if !toolResults.isEmpty {
                anthropicMessages.append([
                    "role": "user",
                    "content": toolResults
                ])
                continue
            }

            switch message.role {
            case .system:
                system = message.textContent
            case .user:
                anthropicMessages.append([
                    "role": "user",
                    "content": message.textContent
                ])
            case .assistant:
                // Check for tool uses
                var content: [[String: Any]] = []
                var hasToolUse = false

                for part in message.content {
                    switch part {
                    case .text(let text):
                        if !text.isEmpty {
                            content.append([
                                "type": "text",
                                "text": text
                            ])
                        }
                    case .toolUse(let toolUse):
                        hasToolUse = true
                        content.append([
                            "type": "tool_use",
                            "id": toolUse.id,
                            "name": toolUse.name,
                            "input": toolUse.input.parameters.mapValues { $0.value }
                        ])
                    default:
                        break
                    }
                }

                if hasToolUse {
                    anthropicMessages.append([
                        "role": "assistant",
                        "content": content
                    ])
                } else {
                    anthropicMessages.append([
                        "role": "assistant",
                        "content": message.textContent
                    ])
                }
            }
        }

        return (system, anthropicMessages)
    }

    private func anthropicTool(from tool: ToolDefinition) -> [String: Any] {
        [
            "name": tool.name,
            "description": tool.description,
            "input_schema": [
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
        // Try to parse Anthropic error format
        if let data = text.data(using: .utf8),
           let json = try? JSONDecoder().decode(AnthropicError.self, from: data)
        {
            switch json.error.type {
            case "authentication_error":
                return .authenticationFailed
            case "rate_limit_error":
                return .rateLimited(retryAfter: nil)
            case "invalid_request_error":
                if json.error.message.contains("context length") {
                    return .contextLengthExceeded(max: 0, requested: 0)
                }
                return .invalidRequest(json.error.message)
            case "not_found_error":
                return .modelNotFound(json.error.message)
            default:
                return .providerUnavailable(json.error.message)
            }
        }

        return .providerUnavailable("HTTP \(statusCode): \(text)")
    }
}

// MARK: - Anthropic API Types

private struct AnthropicStreamEvent: Decodable {
    let type: String
    let message: MessageStart?
    let content_block: ContentBlock?
    let delta: ContentDelta?
    let usage: UsageInfo?

    struct MessageStart: Decodable {
        let usage: UsageInfo?
    }

    struct ContentBlock: Decodable {
        let type: String
        let id: String?
        let name: String?
    }

    struct ContentDelta: Decodable {
        let type: String
        let text: String?
        let partial_json: String?
    }

    struct UsageInfo: Decodable {
        let input_tokens: Int
        let output_tokens: Int
    }
}

private struct AnthropicResponse: Decodable {
    let id: String
    let type: String
    let role: String
    let content: [ContentBlock]
    let stop_reason: String?
    let usage: Usage

    enum ContentBlock: Decodable {
        case text(TextContent)
        case toolUse(ToolUseContent)

        struct TextContent: Decodable {
            let text: String
        }

        struct ToolUseContent: Decodable {
            let id: String
            let name: String
            let input: [String: Any]

            enum CodingKeys: String, CodingKey {
                case id, name, input
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                name = try container.decode(String.self, forKey: .name)

                // Decode input as generic JSON
                let inputContainer = try container.decode([String: AnyCodable].self, forKey: .input)
                input = inputContainer.mapValues { $0.value }
            }
        }

        enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "text":
                self = .text(try TextContent(from: decoder))
            case "tool_use":
                self = .toolUse(try ToolUseContent(from: decoder))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown content type: \(type)"
                )
            }
        }
    }

    struct Usage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
    }
}

private struct AnthropicError: Decodable {
    let type: String
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let type: String
        let message: String
    }
}
