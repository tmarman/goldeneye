import Foundation
import Testing
@testable import AgentKit

// MARK: - Tool Protocol Tests

@Suite("Tool Protocol Tests")
struct ToolProtocolTests {

    @Test("Tool default implementations")
    func toolDefaults() {
        let tool = MockTool()
        #expect(tool.requiresApproval == false)
        #expect(tool.riskLevel == .low)
        #expect(tool.describeAction(makeInput([:])).contains("MockTool"))
    }

    @Test("Tool to definition conversion")
    func toolToDefinition() {
        let tool = MockTool(
            name: "TestTool",
            description: "A test tool",
            schema: ToolSchema(
                properties: ["path": .init(type: "string", description: "File path")],
                required: ["path"]
            )
        )

        let def = tool.toDefinition()
        #expect(def.name == "TestTool")
        #expect(def.description == "A test tool")
        #expect(def.inputSchema.required.contains("path"))
    }

    @Test("Tool array to definitions")
    func toolArrayToDefinitions() {
        let tools: [any Tool] = [
            MockTool(name: "Tool1"),
            MockTool(name: "Tool2"),
            MockTool(name: "Tool3")
        ]

        let definitions = tools.toDefinitions()
        #expect(definitions.count == 3)
        #expect(definitions.map { $0.name } == ["Tool1", "Tool2", "Tool3"])
    }
}

// MARK: - ToolInput Tests

@Suite("ToolInput Tests")
struct ToolInputTests {

    @Test("Get string parameter")
    func getString() {
        let input = makeInput(["name": "Alice", "age": 30])
        #expect(input.get("name", as: String.self) == "Alice")
    }

    @Test("Get integer parameter")
    func getInt() {
        let input = makeInput(["count": 42])
        #expect(input.get("count", as: Int.self) == 42)
    }

    @Test("Get boolean parameter")
    func getBool() {
        let input = makeInput(["enabled": true])
        #expect(input.get("enabled", as: Bool.self) == true)
    }

    @Test("Get missing parameter returns nil")
    func getMissing() {
        let input = makeInput(["key": "value"])
        #expect(input.get("missing", as: String.self) == nil)
    }

    @Test("Require existing parameter succeeds")
    func requireExisting() throws {
        let input = makeInput(["path": "/home/user"])
        let path = try input.require("path", as: String.self)
        #expect(path == "/home/user")
    }

    @Test("Require missing parameter throws")
    func requireMissing() throws {
        let input = makeInput([:])
        #expect(throws: ToolError.self) {
            _ = try input.require("missing", as: String.self)
        }
    }

    @Test("Input summary lists keys")
    func inputSummary() {
        let input = makeInput(["a": 1, "b": 2, "c": 3])
        let summary = input.summary
        #expect(summary.contains("a"))
        #expect(summary.contains("b"))
        #expect(summary.contains("c"))
    }

    @Test("Input encoding and decoding")
    func inputCodable() throws {
        let original = makeInput(["key": "value", "num": 42])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ToolInput.self, from: encoded)

        #expect(decoded.get("key", as: String.self) == "value")
        #expect(decoded.get("num", as: Int.self) == 42)
    }
}

// MARK: - ToolOutput Tests

@Suite("ToolOutput Tests")
struct ToolOutputTests {

    @Test("Success output")
    func successOutput() {
        let output = ToolOutput.success("Result text")
        #expect(output.content == "Result text")
        #expect(output.isError == false)
    }

    @Test("Error output")
    func errorOutput() {
        let output = ToolOutput.error("Something failed")
        #expect(output.content == "Something failed")
        #expect(output.isError == true)
    }

    @Test("Output with metadata")
    func outputWithMetadata() {
        let output = ToolOutput(
            content: "Result",
            isError: false,
            metadata: ["lines": AnyCodable(100)]
        )
        #expect(output.metadata?["lines"]?.value as? Int == 100)
    }
}

// MARK: - ToolSchema Tests

@Suite("ToolSchema Tests")
struct ToolSchemaTests {

    @Test("Schema with properties")
    func schemaProperties() {
        let schema = ToolSchema(
            properties: [
                "file_path": .init(type: "string", description: "Path to file"),
                "limit": .init(type: "integer", description: "Max lines")
            ],
            required: ["file_path"]
        )

        #expect(schema.type == "object")
        #expect(schema.properties.count == 2)
        #expect(schema.required == ["file_path"])
        #expect(schema.properties["file_path"]?.type == "string")
    }

    @Test("Property schema with enum")
    func propertyWithEnum() {
        let prop = ToolSchema.PropertySchema(
            type: "string",
            description: "Output format",
            enumValues: ["json", "xml", "csv"]
        )

        #expect(prop.enumValues == ["json", "xml", "csv"])
    }

    @Test("Schema encoding and decoding")
    func schemaCodable() throws {
        let original = ToolSchema(
            properties: ["name": .init(type: "string")],
            required: ["name"]
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ToolSchema.self, from: encoded)

        #expect(decoded.properties["name"]?.type == "string")
        #expect(decoded.required == ["name"])
    }
}

// MARK: - RiskLevel Tests

@Suite("RiskLevel Tests")
struct RiskLevelTests {

    @Test("Risk level ordering")
    func ordering() {
        #expect(RiskLevel.low < RiskLevel.medium)
        #expect(RiskLevel.medium < RiskLevel.high)
        #expect(RiskLevel.high < RiskLevel.critical)
        #expect(RiskLevel.low < RiskLevel.critical)
    }

    @Test("Risk level equality")
    func equality() {
        #expect(RiskLevel.low == RiskLevel.low)
        #expect(RiskLevel.high == RiskLevel.high)
        #expect(RiskLevel.low != RiskLevel.high)
    }

    @Test("Risk level encoding")
    func encoding() throws {
        let encoded = try JSONEncoder().encode(RiskLevel.high)
        let decoded = try JSONDecoder().decode(RiskLevel.self, from: encoded)
        #expect(decoded == .high)
    }
}

// MARK: - ToolError Tests

@Suite("ToolError Tests")
struct ToolErrorTests {

    @Test("Missing parameter error")
    func missingParameter() {
        let error = ToolError.missingParameter("file_path")
        if case .missingParameter(let param) = error {
            #expect(param == "file_path")
        } else {
            Issue.record("Expected missingParameter error")
        }
    }

    @Test("Invalid parameter error")
    func invalidParameter() {
        let error = ToolError.invalidParameter("count", expected: "integer")
        if case .invalidParameter(let param, let expected) = error {
            #expect(param == "count")
            #expect(expected == "integer")
        } else {
            Issue.record("Expected invalidParameter error")
        }
    }

    @Test("Execution failed error")
    func executionFailed() {
        let error = ToolError.executionFailed("Command failed")
        if case .executionFailed(let message) = error {
            #expect(message == "Command failed")
        } else {
            Issue.record("Expected executionFailed error")
        }
    }
}

// MARK: - Mock Tool Execution Tests

@Suite("Mock Tool Execution Tests")
struct MockToolExecutionTests {

    @Test("Succeeding tool returns success")
    func succeedingTool() async throws {
        let tool = MockTool.succeeding("Hello World")
        let context = makeTestContext()
        let output = try await tool.execute(makeInput([:]), context: context)

        #expect(output.content == "Hello World")
        #expect(output.isError == false)
    }

    @Test("Failing tool throws error")
    func failingTool() async {
        let tool = MockTool.failing("Something broke")
        let context = makeTestContext()

        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(makeInput([:]), context: context)
        }
    }

    @Test("Error output tool returns error")
    func errorOutputTool() async throws {
        let tool = MockTool.errorOutput("Error message")
        let context = makeTestContext()
        let output = try await tool.execute(makeInput([:]), context: context)

        #expect(output.isError == true)
        #expect(output.content == "Error message")
    }

    @Test("Echoing tool echoes input")
    func echoingTool() async throws {
        let tool = MockTool.echoing()
        let context = makeTestContext()
        let output = try await tool.execute(makeInput(["message": "Test"]), context: context)

        #expect(output.content == "Echo: Test")
    }

    @Test("High risk tool has correct properties")
    func highRiskTool() {
        let tool = MockTool.highRisk()
        #expect(tool.requiresApproval == true)
        #expect(tool.riskLevel == .high)
    }
}

// MARK: - Built-in Tool Tests

@Suite("Built-in Tool Tests")
struct BuiltInToolTests {

    @Test("ReadTool properties")
    func readToolProperties() {
        let tool = ReadTool()
        #expect(tool.name == "Read")
        #expect(tool.requiresApproval == false)
        #expect(tool.riskLevel == .low)
        #expect(tool.inputSchema.required.contains("file_path"))
    }

    @Test("WriteTool properties")
    func writeToolProperties() {
        let tool = WriteTool()
        #expect(tool.name == "Write")
        #expect(tool.requiresApproval == true)
        #expect(tool.riskLevel == .medium)
        #expect(tool.inputSchema.required.contains("file_path"))
        #expect(tool.inputSchema.required.contains("content"))
    }

    @Test("BashTool properties")
    func bashToolProperties() {
        let tool = BashTool()
        #expect(tool.name == "Bash")
        #expect(tool.requiresApproval == true)
        #expect(tool.riskLevel == .high)
        #expect(tool.inputSchema.required.contains("command"))
    }

    @Test("EditTool properties")
    func editToolProperties() {
        let tool = EditTool()
        #expect(tool.name == "Edit")
        #expect(tool.requiresApproval == true)
        #expect(tool.riskLevel == .medium)
    }

    @Test("GlobTool properties")
    func globToolProperties() {
        let tool = GlobTool()
        #expect(tool.name == "Glob")
        #expect(tool.requiresApproval == false)
        #expect(tool.riskLevel == .low)
        #expect(tool.inputSchema.required.contains("pattern"))
    }

    @Test("GrepTool properties")
    func grepToolProperties() {
        let tool = GrepTool()
        #expect(tool.name == "Grep")
        #expect(tool.requiresApproval == false)
        #expect(tool.riskLevel == .low)
        #expect(tool.inputSchema.required.contains("pattern"))
    }

    @Test("ReadTool reads file content")
    func readToolExecution() async throws {
        // Create temp file
        let content = "Line 1\nLine 2\nLine 3"
        let fileURL = try createTempFile(content: content)
        defer { cleanup(fileURL) }

        let tool = ReadTool()
        let context = makeTestContext()
        let output = try await tool.execute(
            makeInput(["file_path": fileURL.path]),
            context: context
        )

        #expect(output.isError == false)
        #expect(output.content.contains("Line 1"))
        #expect(output.content.contains("Line 2"))
        #expect(output.content.contains("Line 3"))
    }

    @Test("ReadTool handles missing file")
    func readToolMissingFile() async throws {
        let tool = ReadTool()
        let context = makeTestContext()
        let output = try await tool.execute(
            makeInput(["file_path": "/nonexistent/file.txt"]),
            context: context
        )

        #expect(output.isError == true)
    }

    @Test("WriteTool writes content to file")
    func writeToolExecution() async throws {
        let tempDir = try createTempDirectory()
        let filePath = tempDir.appendingPathComponent("test.txt").path
        defer { cleanup(tempDir) }

        let tool = WriteTool()
        let context = makeTestContext()
        let output = try await tool.execute(
            makeInput(["file_path": filePath, "content": "Hello World"]),
            context: context
        )

        #expect(output.isError == false)

        // Verify file was written
        let written = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(written == "Hello World")
    }

    @Test("GlobTool finds matching files")
    func globToolExecution() async throws {
        let tempDir = try createTempDirectory()
        defer { cleanup(tempDir) }

        // Create some test files
        try "content".write(to: tempDir.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
        try "content".write(to: tempDir.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)
        try "content".write(to: tempDir.appendingPathComponent("other.md"), atomically: true, encoding: .utf8)

        let tool = GlobTool()
        let context = makeTestContext(workingDirectory: tempDir)
        let output = try await tool.execute(
            makeInput(["pattern": "*.txt", "path": tempDir.path]),
            context: context
        )

        #expect(output.isError == false)
        #expect(output.content.contains("file1.txt"))
        #expect(output.content.contains("file2.txt"))
        #expect(!output.content.contains("other.md"))
    }
}
