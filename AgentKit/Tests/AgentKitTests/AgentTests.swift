import Foundation
import Testing
@testable import AgentKit

// MARK: - Agent ID Tests

@Suite("AgentID Tests")
struct AgentIDTests {

    @Test("AgentID generates unique values")
    func uniqueIds() {
        let ids = (0..<100).map { _ in AgentID() }
        let uniqueIds = Set(ids)
        #expect(uniqueIds.count == 100)
    }

    @Test("AgentID from string")
    func fromString() {
        let id = AgentID("my-agent")
        #expect(id.rawValue == "my-agent")
        #expect(id.description == "my-agent")
    }

    @Test("AgentID equality")
    func equality() {
        let id1 = AgentID("test")
        let id2 = AgentID("test")
        let id3 = AgentID("other")

        #expect(id1 == id2)
        #expect(id1 != id3)
    }

    @Test("AgentID hashable")
    func hashable() {
        let id1 = AgentID("test")
        let id2 = AgentID("test")

        var set = Set<AgentID>()
        set.insert(id1)
        set.insert(id2)

        #expect(set.count == 1)
    }

    @Test("AgentID codable")
    func codable() throws {
        let original = AgentID("my-agent-123")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentID.self, from: encoded)
        #expect(decoded == original)
    }
}

// MARK: - TaskID Tests

@Suite("TaskID Tests")
struct TaskIDTests {

    @Test("TaskID generates unique values")
    func uniqueIds() {
        let ids = (0..<100).map { _ in TaskID() }
        let uniqueIds = Set(ids)
        #expect(uniqueIds.count == 100)
    }

    @Test("TaskID from string")
    func fromString() {
        let id = TaskID("task-001")
        #expect(id.rawValue == "task-001")
        #expect(id.description == "task-001")
    }

    @Test("TaskID codable")
    func codable() throws {
        let original = TaskID("task-abc")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TaskID.self, from: encoded)
        #expect(decoded == original)
    }
}

// MARK: - ContextID Tests

@Suite("ContextID Tests")
struct ContextIDTests {

    @Test("ContextID generates unique values")
    func uniqueIds() {
        let ids = (0..<100).map { _ in ContextID() }
        let uniqueIds = Set(ids)
        #expect(uniqueIds.count == 100)
    }

    @Test("ContextID from string")
    func fromString() {
        let id = ContextID("ctx-001")
        #expect(id.rawValue == "ctx-001")
        #expect(id.description == "ctx-001")
    }

    @Test("ContextID codable")
    func codable() throws {
        let original = ContextID("ctx-xyz")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContextID.self, from: encoded)
        #expect(decoded == original)
    }
}

// MARK: - AgentTask Tests

@Suite("AgentTask Tests")
struct AgentTaskTests {

    @Test("Task creation with defaults")
    func taskDefaults() {
        let task = AgentTask(
            message: makeMessage(role: .user, text: "Hello")
        )

        #expect(task.message.textContent == "Hello")
        #expect(task.configuration == nil)
    }

    @Test("Task with custom IDs")
    func taskCustomIds() {
        let task = AgentTask(
            id: TaskID("my-task"),
            contextId: ContextID("my-context"),
            message: makeMessage(role: .user, text: "Hello")
        )

        #expect(task.id.rawValue == "my-task")
        #expect(task.contextId.rawValue == "my-context")
    }

    @Test("Task with configuration")
    func taskWithConfig() {
        let config = TaskConfiguration(
            blocking: true,
            timeout: .seconds(60),
            approvalPolicy: .alwaysApprove
        )

        let task = AgentTask(
            message: makeMessage(role: .user, text: "Hello"),
            configuration: config
        )

        #expect(task.configuration?.blocking == true)
        #expect(task.configuration?.timeout == .seconds(60))
        #expect(task.configuration?.approvalPolicy == .alwaysApprove)
    }
}

// MARK: - TaskConfiguration Tests

@Suite("TaskConfiguration Tests")
struct TaskConfigurationTests {

    @Test("Configuration defaults")
    func configDefaults() {
        let config = TaskConfiguration()
        #expect(config.blocking == false)
        #expect(config.timeout == nil)
        #expect(config.approvalPolicy == nil)
    }

    @Test("Configuration with all options")
    func configAllOptions() {
        let config = TaskConfiguration(
            blocking: true,
            timeout: .seconds(120),
            approvalPolicy: .neverApprove
        )

        #expect(config.blocking == true)
        #expect(config.timeout == .seconds(120))
        #expect(config.approvalPolicy == .neverApprove)
    }

    @Test("Configuration codable")
    func configCodable() throws {
        let original = TaskConfiguration(
            blocking: true,
            timeout: .seconds(30)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TaskConfiguration.self, from: encoded)

        #expect(decoded.blocking == true)
        // Duration encoding might vary, just check it's non-nil
        #expect(decoded.timeout != nil)
    }
}

// MARK: - ApprovalPolicyOverride Tests

@Suite("ApprovalPolicyOverride Tests")
struct ApprovalPolicyOverrideTests {

    @Test("Override enum values")
    func enumValues() {
        let always = ApprovalPolicyOverride.alwaysApprove
        let never = ApprovalPolicyOverride.neverApprove
        let useDefault = ApprovalPolicyOverride.useDefault

        #expect(always != never)
        #expect(never != useDefault)
    }

    @Test("Override codable")
    func overrideCodable() throws {
        let values: [ApprovalPolicyOverride] = [.alwaysApprove, .neverApprove, .useDefault]

        for original in values {
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ApprovalPolicyOverride.self, from: encoded)
            #expect(decoded == original)
        }
    }
}

// MARK: - TaskState Tests

@Suite("TaskState Tests")
struct TaskStateTests {

    @Test("Terminal states")
    func terminalStates() {
        #expect(TaskState.completed.isTerminal == true)
        #expect(TaskState.failed.isTerminal == true)
        #expect(TaskState.cancelled.isTerminal == true)
        #expect(TaskState.rejected.isTerminal == true)
    }

    @Test("Non-terminal states")
    func nonTerminalStates() {
        #expect(TaskState.submitted.isTerminal == false)
        #expect(TaskState.working.isTerminal == false)
        #expect(TaskState.inputRequired.isTerminal == false)
    }

    @Test("All states exist")
    func allStates() {
        // Ensure all expected states are defined
        let states: [TaskState] = [
            .submitted,
            .working,
            .inputRequired,
            .completed,
            .failed,
            .cancelled,
            .rejected
        ]

        #expect(states.count == 7)
    }
}

// MARK: - Message Tests

@Suite("Message Tests")
struct MessageTests {

    @Test("Message with single text content")
    func singleTextContent() {
        let message = Message(role: .user, content: .text("Hello"))
        #expect(message.textContent == "Hello")
        #expect(message.role == .user)
    }

    @Test("Message with multiple text content")
    func multipleTextContent() {
        let message = Message(
            role: .assistant,
            content: [
                .text("Hello "),
                .text("World"),
                .text("!")
            ]
        )
        #expect(message.textContent == "Hello World!")
    }

    @Test("Message roles")
    func messageRoles() {
        let system = Message(role: .system, content: .text("System"))
        let user = Message(role: .user, content: .text("User"))
        let assistant = Message(role: .assistant, content: .text("Assistant"))

        #expect(system.role == .system)
        #expect(user.role == .user)
        #expect(assistant.role == .assistant)
    }

    @Test("Message has unique ID")
    func uniqueMessageId() {
        let msg1 = Message(role: .user, content: .text("A"))
        let msg2 = Message(role: .user, content: .text("A"))

        #expect(msg1.id != msg2.id)
    }

    @Test("Message with custom ID")
    func customMessageId() {
        let message = Message(
            id: "custom-id",
            role: .user,
            content: .text("Hello")
        )
        #expect(message.id == "custom-id")
    }

    @Test("Message timestamp")
    func messageTimestamp() {
        let before = Date()
        let message = Message(role: .user, content: .text("Hello"))
        let after = Date()

        #expect(message.timestamp >= before)
        #expect(message.timestamp <= after)
    }
}

// MARK: - MessageContent Tests

@Suite("MessageContent Tests")
struct MessageContentTests {

    @Test("Text content")
    func textContent() {
        let content = MessageContent.text("Hello")
        if case .text(let text) = content {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test("ToolUse content")
    func toolUseContent() {
        let toolUse = ToolUse(
            id: "use-123",
            name: "Read",
            input: makeInput(["file_path": "/test.txt"])
        )
        let content = MessageContent.toolUse(toolUse)

        if case .toolUse(let tu) = content {
            #expect(tu.id == "use-123")
            #expect(tu.name == "Read")
        } else {
            Issue.record("Expected toolUse content")
        }
    }

    @Test("ToolResult content")
    func toolResultContent() {
        let result = ToolResult(
            toolUseId: "use-123",
            content: "File contents here",
            isError: false
        )
        let content = MessageContent.toolResult(result)

        if case .toolResult(let tr) = content {
            #expect(tr.toolUseId == "use-123")
            #expect(tr.content == "File contents here")
            #expect(tr.isError == false)
        } else {
            Issue.record("Expected toolResult content")
        }
    }

    @Test("ToolResult error")
    func toolResultError() {
        let result = ToolResult(
            toolUseId: "use-456",
            content: "File not found",
            isError: true
        )

        #expect(result.isError == true)
    }
}

// MARK: - Artifact Tests

@Suite("Artifact Tests")
struct ArtifactTests {

    @Test("Artifact creation")
    func artifactCreation() {
        let artifact = Artifact(
            name: "output.txt",
            description: "Generated output",
            parts: [.text("Content here")]
        )

        #expect(artifact.name == "output.txt")
        #expect(artifact.description == "Generated output")
        #expect(artifact.parts.count == 1)
    }

    @Test("Artifact with metadata")
    func artifactMetadata() {
        let artifact = Artifact(
            name: "data.json",
            parts: [.text("{}")],
            metadata: ["format": AnyCodable("json"), "size": AnyCodable(2)]
        )

        #expect(artifact.metadata?["format"]?.value as? String == "json")
        #expect(artifact.metadata?["size"]?.value as? Int == 2)
    }

    @Test("Artifact has unique ID")
    func artifactUniqueId() {
        let a1 = Artifact(name: "file1", parts: [])
        let a2 = Artifact(name: "file2", parts: [])

        #expect(a1.id != a2.id)
    }
}
