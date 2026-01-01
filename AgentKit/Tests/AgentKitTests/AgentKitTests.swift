import Foundation
import Testing
@testable import AgentKit

@Suite("AgentKit Core Tests")
struct AgentKitTests {

    @Test("Version is set correctly")
    func version() {
        #expect(AgentKitVersion.major == 0)
        #expect(AgentKitVersion.minor == 1)
        #expect(AgentKitVersion.patch == 0)
        #expect(AgentKitVersion.string == "0.1.0")
    }

    @Test("AgentID generates unique values")
    func agentIdUniqueness() {
        let id1 = AgentID()
        let id2 = AgentID()
        #expect(id1 != id2)
    }

    @Test("TaskID can be created with custom value")
    func taskIdCustomValue() {
        let id = TaskID("my-task")
        #expect(id.rawValue == "my-task")
        #expect(id.description == "my-task")
    }

    @Test("Message text content extraction")
    func messageTextContent() {
        let message = Message(
            role: .user,
            content: [
                .text("Hello "),
                .text("World")
            ]
        )
        #expect(message.textContent == "Hello World")
    }

    @Test("ToolInput parameter access")
    func toolInputParameters() throws {
        let input = ToolInput(parameters: [
            "file_path": AnyCodable("/path/to/file"),
            "limit": AnyCodable(100)
        ])

        #expect(input.get("file_path", as: String.self) == "/path/to/file")
        #expect(input.get("limit", as: Int.self) == 100)
        #expect(input.get("missing", as: String.self) == nil)

        let path = try input.require("file_path", as: String.self)
        #expect(path == "/path/to/file")
    }

    @Test("RiskLevel comparison")
    func riskLevelComparison() {
        #expect(RiskLevel.low < RiskLevel.medium)
        #expect(RiskLevel.medium < RiskLevel.high)
        #expect(RiskLevel.high < RiskLevel.critical)
    }

    @Test("TaskState terminal check")
    func taskStateTerminal() {
        #expect(TaskState.completed.isTerminal == true)
        #expect(TaskState.failed.isTerminal == true)
        #expect(TaskState.cancelled.isTerminal == true)
        #expect(TaskState.rejected.isTerminal == true)

        #expect(TaskState.submitted.isTerminal == false)
        #expect(TaskState.working.isTerminal == false)
        #expect(TaskState.inputRequired.isTerminal == false)
    }

    @Test("ApprovalPolicy default preset")
    func approvalPolicyDefault() {
        let policy = ApprovalPolicy.default

        #expect(policy.requiresApproval(toolName: "Bash", riskLevel: .high) == true)
        #expect(policy.requiresApproval(toolName: "Write", riskLevel: .medium) == true)
        #expect(policy.requiresApproval(toolName: "Read", riskLevel: .low) == false)
        #expect(policy.requiresApproval(toolName: "Glob", riskLevel: .low) == false)
    }

    @Test("AnyCodable encoding and decoding")
    func anyCodableRoundTrip() throws {
        let original: [String: AnyCodable] = [
            "string": AnyCodable("hello"),
            "number": AnyCodable(42),
            "bool": AnyCodable(true),
            "array": AnyCodable([1, 2, 3])
        ]

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: encoded)

        #expect(decoded["string"]?.value as? String == "hello")
        #expect(decoded["number"]?.value as? Int == 42)
        #expect(decoded["bool"]?.value as? Bool == true)
    }
}

@Suite("Tool Tests")
struct ToolTests {

    @Test("ReadTool schema is correct")
    func readToolSchema() {
        let tool = ReadTool()
        #expect(tool.name == "Read")
        #expect(tool.requiresApproval == false)
        #expect(tool.riskLevel == .low)
        #expect(tool.inputSchema.required.contains("file_path"))
    }

    @Test("WriteTool requires approval")
    func writeToolApproval() {
        let tool = WriteTool()
        #expect(tool.name == "Write")
        #expect(tool.requiresApproval == true)
        #expect(tool.riskLevel == .medium)
    }

    @Test("BashTool is high risk")
    func bashToolRisk() {
        let tool = BashTool()
        #expect(tool.name == "Bash")
        #expect(tool.requiresApproval == true)
        #expect(tool.riskLevel == .high)
    }
}

@Suite("A2A Types Tests")
struct A2ATypesTests {

    @Test("A2ATask JSON encoding")
    func taskEncoding() throws {
        let task = A2ATask(
            id: "task-123",
            contextId: "ctx-456",
            status: A2ATaskStatus(state: .working)
        )

        let encoded = try JSONEncoder().encode(task)
        let json = String(data: encoded, encoding: .utf8)!

        #expect(json.contains("\"id\":\"task-123\""))
        #expect(json.contains("\"context_id\":\"ctx-456\""))
        #expect(json.contains("TASK_STATE_WORKING"))
    }

    @Test("JSONRPCError standard codes")
    func jsonRpcErrors() {
        let parseError = JSONRPCError.parseError()
        #expect(parseError.code == -32700)

        let methodNotFound = JSONRPCError.methodNotFound("foo")
        #expect(methodNotFound.code == -32601)
        #expect(methodNotFound.message.contains("foo"))
    }
}

@Suite("PacketLine Tests")
struct PacketLineTests {

    @Test("Packet line encoding")
    func encoding() {
        let line = PacketLine.encode("hello")
        let str = String(data: line, encoding: .utf8)!
        #expect(str == "0009hello")  // 5 chars + 4 = 9
    }

    @Test("Flush packet")
    func flush() {
        let flush = PacketLine.flush
        let str = String(data: flush, encoding: .utf8)!
        #expect(str == "0000")
    }
}
