import Foundation

// MARK: - LLM Provider Protocol

/// Protocol for LLM inference providers
public protocol LLMProvider: Sendable {
    /// Provider name (for logging/display)
    var name: String { get }

    /// Generate a completion from messages
    func complete(_ messages: [Message]) async throws -> AsyncThrowingStream<LLMToken, Error>

    /// Generate a completion with tool definitions
    func complete(
        _ messages: [Message],
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<LLMToken, Error>
}

// MARK: - Default Implementation

extension LLMProvider {
    public func complete(_ messages: [Message]) async throws -> AsyncThrowingStream<LLMToken, Error> {
        try await complete(messages, tools: [])
    }
}

// MARK: - LLM Token

/// Token types from LLM generation
public enum LLMToken: Sendable {
    /// Text content
    case text(String)

    /// Tool call request
    case toolCall(LLMToolCall)

    /// Generation complete
    case done
}

public struct LLMToolCall: Sendable {
    public let id: String
    public let name: String
    public let input: ToolInput

    public init(id: String, name: String, input: ToolInput) {
        self.id = id
        self.name = name
        self.input = input
    }
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

// MARK: - Mock Provider (for testing)

/// Mock LLM provider for testing
public actor MockLLMProvider: LLMProvider {
    public let name = "Mock"
    private var responses: [String]
    private var responseIndex = 0

    public init(responses: [String] = ["Hello, I'm a mock assistant."]) {
        self.responses = responses
    }

    public func complete(
        _ messages: [Message],
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<LLMToken, Error> {
        let response = responses[responseIndex % responses.count]
        responseIndex += 1

        return AsyncThrowingStream { continuation in
            // Simulate streaming by yielding words
            let words = response.split(separator: " ")
            for (index, word) in words.enumerated() {
                let text = index == 0 ? String(word) : " " + String(word)
                continuation.yield(.text(text))
            }
            continuation.yield(.done)
            continuation.finish()
        }
    }
}
