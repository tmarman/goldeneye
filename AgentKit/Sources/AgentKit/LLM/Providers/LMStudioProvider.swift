import Foundation

// MARK: - LM Studio Provider

/// LLM provider for LM Studio local inference
///
/// LM Studio provides an OpenAI-compatible API at localhost:1234.
/// This is a convenience wrapper around OpenAICompatibleProvider.
///
/// Usage:
/// ```swift
/// let provider = LMStudioProvider()
/// // or with custom port
/// let provider = LMStudioProvider(port: 8080)
/// ```
public actor LMStudioProvider: LLMProvider {
    public let id = "lm-studio"
    public let name = "LM Studio"
    public let supportsToolCalling = true
    public let supportsStreaming = true

    private let provider: OpenAICompatibleProvider

    public init(
        host: String = "localhost",
        port: Int = 1234,
        defaultModel: String = "local-model"
    ) {
        let baseURL = URL(string: "http://\(host):\(port)/v1")!
        self.provider = OpenAICompatibleProvider(
            baseURL: baseURL,
            apiKey: nil,
            defaultModel: defaultModel,
            name: "LM Studio",
            supportsToolCalling: true,
            supportsStreaming: true
        )
    }

    public func complete(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        try await provider.complete(messages, tools: tools, options: options)
    }

    public func isAvailable() async -> Bool {
        await provider.isAvailable()
    }

    /// List models loaded in LM Studio
    public func listModels() async throws -> [String] {
        try await provider.listModels()
    }
}
