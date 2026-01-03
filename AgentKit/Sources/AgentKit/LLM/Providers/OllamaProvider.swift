import Foundation

// MARK: - Ollama Provider

/// LLM provider for Ollama (local inference server)
///
/// Ollama provides a simple API for running LLMs locally.
/// Supports streaming, tool calling (llama3.1+), and multiple models.
///
/// Usage:
/// ```swift
/// let provider = OllamaProvider(model: "llama3.1:70b")
/// let stream = try await provider.complete(messages)
/// ```
public actor OllamaProvider: LLMProvider {
    public let id: String
    public let name = "Ollama"
    public let supportsToolCalling = true
    public let supportsStreaming = true

    private let baseURL: URL
    private let defaultModel: String
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        model: String = "llama3.1"
    ) {
        self.baseURL = baseURL
        self.defaultModel = model
        self.id = "ollama-\(model)"
        self.session = URLSession(configuration: .default)
    }

    public func complete(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        let model = options.model ?? defaultModel

        // Build request
        let request = OllamaChatRequest(
            model: model,
            messages: messages.map { OllamaMessage(from: $0) },
            tools: tools.isEmpty ? nil : tools.map { OllamaTool(from: $0) },
            stream: options.stream,
            options: OllamaOptions(
                temperature: options.temperature,
                top_p: options.topP,
                num_predict: options.maxTokens,
                stop: options.stopSequences
            )
        )

        let url = baseURL.appendingPathComponent("/api/chat")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        if options.stream {
            return streamingComplete(urlRequest)
        } else {
            return nonStreamingComplete(urlRequest)
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

                    guard httpResponse.statusCode == 200 else {
                        continuation.yield(.error(.providerUnavailable("HTTP \(httpResponse.statusCode)")))
                        continuation.finish()
                        return
                    }

                    for try await line in bytes.lines {
                        guard !line.isEmpty else { continue }

                        if let data = line.data(using: .utf8),
                           let chunk = try? JSONDecoder().decode(OllamaChatResponse.self, from: data)
                        {
                            // Handle tool calls
                            if let toolCalls = chunk.message?.tool_calls {
                                for toolCall in toolCalls {
                                    continuation.yield(.toolCall(LLMToolCall(
                                        id: UUID().uuidString,
                                        name: toolCall.function.name,
                                        input: ToolInput(parameters: toolCall.function.arguments)
                                    )))
                                }
                            }

                            // Handle text content
                            if let content = chunk.message?.content, !content.isEmpty {
                                continuation.yield(.textDelta(content))
                            }

                            // Handle completion
                            if chunk.done == true {
                                if let evalCount = chunk.eval_count, let promptEvalCount = chunk.prompt_eval_count {
                                    continuation.yield(.usage(LLMUsage(
                                        inputTokens: promptEvalCount,
                                        outputTokens: evalCount
                                    )))
                                }
                                continuation.yield(.done)
                            }
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

                    guard httpResponse.statusCode == 200 else {
                        continuation.yield(.error(.providerUnavailable("HTTP \(httpResponse.statusCode)")))
                        continuation.finish()
                        return
                    }

                    let result = try JSONDecoder().decode(OllamaChatResponse.self, from: data)

                    // Handle tool calls
                    if let toolCalls = result.message?.tool_calls {
                        for toolCall in toolCalls {
                            continuation.yield(.toolCall(LLMToolCall(
                                id: UUID().uuidString,
                                name: toolCall.function.name,
                                input: ToolInput(parameters: toolCall.function.arguments)
                            )))
                        }
                    }

                    // Handle text
                    if let content = result.message?.content {
                        continuation.yield(.text(content))
                    }

                    // Usage
                    if let evalCount = result.eval_count, let promptEvalCount = result.prompt_eval_count {
                        continuation.yield(.usage(LLMUsage(
                            inputTokens: promptEvalCount,
                            outputTokens: evalCount
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
        let url = baseURL.appendingPathComponent("/api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// List available models
    public func listModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("/api/tags")
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return response.models.map(\.name)
    }
}

// MARK: - Ollama API Types

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let tools: [OllamaTool]?
    let stream: Bool
    let options: OllamaOptions?
}

private struct OllamaMessage: Codable {
    let role: String
    let content: String
    let tool_calls: [OllamaToolCall]?

    init(from message: Message) {
        self.role = message.role.rawValue
        self.content = message.textContent
        self.tool_calls = nil
    }
}

private struct OllamaTool: Encodable {
    let type: String
    let function: OllamaFunction

    init(from tool: ToolDefinition) {
        self.type = "function"
        self.function = OllamaFunction(
            name: tool.name,
            description: tool.description,
            parameters: tool.inputSchema
        )
    }
}

private struct OllamaFunction: Encodable {
    let name: String
    let description: String
    let parameters: ToolSchema
}

private struct OllamaOptions: Encodable {
    let temperature: Double?
    let top_p: Double?
    let num_predict: Int?
    let stop: [String]?
}

private struct OllamaChatResponse: Decodable {
    let model: String?
    let message: OllamaResponseMessage?
    let done: Bool?
    let eval_count: Int?
    let prompt_eval_count: Int?
}

private struct OllamaResponseMessage: Decodable {
    let role: String
    let content: String?
    let tool_calls: [OllamaToolCall]?
}

private struct OllamaToolCall: Codable {
    let function: OllamaToolCallFunction
}

private struct OllamaToolCallFunction: Codable {
    let name: String
    let arguments: [String: AnyCodable]
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]
}

private struct OllamaModel: Decodable {
    let name: String
    let size: Int64
    let modified_at: String
}
