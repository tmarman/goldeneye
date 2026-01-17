import Foundation
import Testing
@testable import AgentKit

// MARK: - LLMProvider Tests

@Suite("LLMProvider Tests")
struct LLMProviderTests {

    // MARK: - CompletionOptions Tests

    @Test("Default completion options")
    func defaultOptions() {
        let options = CompletionOptions.default

        #expect(options.model == nil)
        #expect(options.maxTokens == nil)
        #expect(options.temperature == nil)
        #expect(options.stream == true)
    }

    @Test("Custom completion options")
    func customOptions() {
        let options = CompletionOptions(
            model: "gpt-4",
            maxTokens: 1000,
            temperature: 0.7,
            topP: 0.9,
            stopSequences: ["END"],
            systemPrompt: "You are helpful.",
            stream: false
        )

        #expect(options.model == "gpt-4")
        #expect(options.maxTokens == 1000)
        #expect(options.temperature == 0.7)
        #expect(options.topP == 0.9)
        #expect(options.stopSequences == ["END"])
        #expect(options.systemPrompt == "You are helpful.")
        #expect(options.stream == false)
    }

    // MARK: - LLMEvent Tests

    @Test("Text delta event")
    func textDeltaEvent() {
        let event = LLMEvent.textDelta("Hello")
        if case .textDelta(let text) = event {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected textDelta event")
        }
    }

    @Test("Tool call event")
    func toolCallEvent() {
        let toolCall = LLMToolCall(
            id: "call-123",
            name: "Read",
            input: makeInput(["file_path": "/test.txt"])
        )
        let event = LLMEvent.toolCall(toolCall)

        if case .toolCall(let tc) = event {
            #expect(tc.id == "call-123")
            #expect(tc.name == "Read")
        } else {
            Issue.record("Expected toolCall event")
        }
    }

    @Test("Usage event")
    func usageEvent() {
        let usage = LLMUsage(inputTokens: 100, outputTokens: 50)
        let event = LLMEvent.usage(usage)

        if case .usage(let u) = event {
            #expect(u.inputTokens == 100)
            #expect(u.outputTokens == 50)
            #expect(u.totalTokens == 150)
        } else {
            Issue.record("Expected usage event")
        }
    }

    // MARK: - LLMToolCall Tests

    @Test("Tool call encoding and decoding")
    func toolCallCodable() throws {
        let original = LLMToolCall(
            id: "call-abc",
            name: "Write",
            input: makeInput(["file_path": "/test.txt", "content": "Hello"])
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LLMToolCall.self, from: encoded)

        #expect(decoded.id == "call-abc")
        #expect(decoded.name == "Write")
        #expect(decoded.input.get("file_path", as: String.self) == "/test.txt")
    }

    // MARK: - LLMUsage Tests

    @Test("Usage total calculation")
    func usageTotal() {
        let usage = LLMUsage(inputTokens: 250, outputTokens: 750)
        #expect(usage.totalTokens == 1000)
    }

    // MARK: - LLMError Tests

    @Test("Provider unavailable error")
    func providerUnavailableError() {
        let error = LLMError.providerUnavailable("Ollama")
        if case .providerUnavailable(let name) = error {
            #expect(name == "Ollama")
        } else {
            Issue.record("Expected providerUnavailable error")
        }
    }

    @Test("Model not found error")
    func modelNotFoundError() {
        let error = LLMError.modelNotFound("gpt-5")
        if case .modelNotFound(let model) = error {
            #expect(model == "gpt-5")
        } else {
            Issue.record("Expected modelNotFound error")
        }
    }

    @Test("Rate limited error with retry")
    func rateLimitedError() {
        let error = LLMError.rateLimited(retryAfter: 30)
        if case .rateLimited(let retry) = error {
            #expect(retry == 30)
        } else {
            Issue.record("Expected rateLimited error")
        }
    }

    @Test("Context length exceeded error")
    func contextLengthError() {
        let error = LLMError.contextLengthExceeded(max: 8000, requested: 10000)
        if case .contextLengthExceeded(let max, let requested) = error {
            #expect(max == 8000)
            #expect(requested == 10000)
        } else {
            Issue.record("Expected contextLengthExceeded error")
        }
    }

    // MARK: - ToolDefinition Tests

    @Test("Tool definition from Tool")
    func toolDefinitionFromTool() {
        let tool = MockTool(
            name: "TestTool",
            description: "A test tool",
            schema: ToolSchema(
                properties: ["param": .init(type: "string")],
                required: ["param"]
            )
        )

        let def = ToolDefinition(from: tool)
        #expect(def.name == "TestTool")
        #expect(def.description == "A test tool")
        #expect(def.inputSchema.required.contains("param"))
    }

    @Test("Tool definition encoding")
    func toolDefinitionCodable() throws {
        let def = ToolDefinition(
            name: "Read",
            description: "Read a file",
            inputSchema: ToolSchema(
                properties: ["file_path": .init(type: "string", description: "Path")],
                required: ["file_path"]
            )
        )

        let encoded = try JSONEncoder().encode(def)
        let decoded = try JSONDecoder().decode(ToolDefinition.self, from: encoded)

        #expect(decoded.name == "Read")
        #expect(decoded.description == "Read a file")
    }

    // MARK: - MockLLMProvider Tests

    @Test("Mock provider basic completion")
    func mockProviderBasic() async throws {
        let provider = MockLLMProvider(responses: ["Hello, world!"])

        // Actor properties need await
        let id = await provider.id
        let name = await provider.name
        #expect(id == "mock")
        #expect(name == "Mock Provider")
        #expect(await provider.isAvailable() == true)

        let messages = [makeMessage(role: .user, text: "Hi")]
        let stream = try await provider.complete(messages, tools: [], options: .default)

        var text = ""
        for try await event in stream {
            if case .textDelta(let delta) = event {
                text += delta
            } else if case .text(let fullText) = event {
                text = fullText
            }
        }

        #expect(text.contains("Hello"))
    }

    @Test("Mock provider cycles through responses")
    func mockProviderMultipleResponses() async throws {
        let provider = MockLLMProvider(responses: ["First", "Second", "Third"])

        let messages = [makeMessage(role: .user, text: "Hi")]

        // First call
        var stream = try await provider.complete(messages)
        var text = await collectText(from: stream)
        #expect(text.contains("First"))

        // Second call
        stream = try await provider.complete(messages)
        text = await collectText(from: stream)
        #expect(text.contains("Second"))

        // Third call
        stream = try await provider.complete(messages)
        text = await collectText(from: stream)
        #expect(text.contains("Third"))

        // Fourth call wraps around
        stream = try await provider.complete(messages)
        text = await collectText(from: stream)
        #expect(text.contains("First"))
    }

    @Test("Mock provider emits done event")
    func mockProviderDoneEvent() async throws {
        let provider = MockLLMProvider(responses: ["Test"])
        let messages = [makeMessage(role: .user, text: "Hi")]

        let stream = try await provider.complete(messages)

        var gotDone = false
        for try await event in stream {
            if case .done = event {
                gotDone = true
            }
        }

        #expect(gotDone == true)
    }

    @Test("Mock provider emits usage event")
    func mockProviderUsage() async throws {
        let provider = MockLLMProvider(responses: ["Response"])
        let messages = [makeMessage(role: .user, text: "Hello there")]

        let stream = try await provider.complete(messages)

        var usage: LLMUsage?
        for try await event in stream {
            if case .usage(let u) = event {
                usage = u
            }
        }

        #expect(usage != nil)
        #expect(usage?.inputTokens ?? 0 > 0)
        #expect(usage?.outputTokens ?? 0 > 0)
    }

    @Test("Mock provider with tool calls")
    func mockProviderToolCalls() async throws {
        let provider = MockLLMProvider(responses: ["I'll read that file."])

        // Add a tool call response
        let toolCall = LLMToolCall(
            id: "call-1",
            name: "Read",
            input: makeInput(["file_path": "/test.txt"])
        )
        await provider.addToolCallResponse(toolCall)

        let messages = [makeMessage(role: .user, text: "Read the file")]
        let stream = try await provider.complete(messages)

        var foundToolCall = false
        for try await event in stream {
            if case .toolCall(let tc) = event {
                foundToolCall = true
                #expect(tc.name == "Read")
            }
        }

        #expect(foundToolCall == true)
    }

    // MARK: - ProviderRegistry Tests

    @Test("Provider registry registration")
    func registryRegistration() async {
        let registry = ProviderRegistry.shared

        // Register a mock provider
        let mock = MockLLMProvider(responses: ["Test"])
        await registry.register(mock)

        // Can retrieve by id
        let retrieved = await registry.provider(id: "mock")
        let retrievedId = await retrieved?.id
        #expect(retrievedId == "mock")
    }

    @Test("Provider registry lists all")
    func registryListAll() async {
        let registry = ProviderRegistry.shared

        let all = await registry.allProviders()
        #expect(all.count >= 1)  // At least the mock we registered
    }
}

// MARK: - Helper Functions

private func collectText(from stream: AsyncThrowingStream<LLMEvent, Error>) async -> String {
    var text = ""
    do {
        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                text += delta
            case .text(let fullText):
                text = fullText
            default:
                break
            }
        }
    } catch {
        // Ignore errors for this helper
    }
    return text
}
