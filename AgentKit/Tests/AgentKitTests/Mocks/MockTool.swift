import Foundation
@testable import AgentKit

// MARK: - Mock Tool

/// A configurable mock tool for testing
public struct MockTool: Tool, @unchecked Sendable {
    public let name: String
    public let description: String
    public let inputSchema: ToolSchema
    public var requiresApproval: Bool
    public var riskLevel: RiskLevel

    private let handler: @Sendable (ToolInput, ToolContext) async throws -> ToolOutput

    public init(
        name: String = "MockTool",
        description: String = "A mock tool for testing",
        schema: ToolSchema = ToolSchema(properties: [:]),
        requiresApproval: Bool = false,
        riskLevel: RiskLevel = .low,
        handler: @escaping @Sendable (ToolInput, ToolContext) async throws -> ToolOutput = { _, _ in
            ToolOutput.success("Mock result")
        }
    ) {
        self.name = name
        self.description = description
        self.inputSchema = schema
        self.requiresApproval = requiresApproval
        self.riskLevel = riskLevel
        self.handler = handler
    }

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        try await handler(input, context)
    }

    public func describeAction(_ input: ToolInput) -> String {
        "Mock action: \(name)"
    }
}

// MARK: - Mock Tool Variants

extension MockTool {
    /// Creates a tool that always succeeds with a given message
    public static func succeeding(_ message: String, name: String = "SuccessTool") -> MockTool {
        MockTool(name: name) { _, _ in
            ToolOutput.success(message)
        }
    }

    /// Creates a tool that always fails with a given error
    public static func failing(_ error: String, name: String = "FailTool") -> MockTool {
        MockTool(name: name) { _, _ in
            throw ToolError.executionFailed(error)
        }
    }

    /// Creates a tool that returns an error output (not throwing)
    public static func errorOutput(_ message: String, name: String = "ErrorTool") -> MockTool {
        MockTool(name: name) { _, _ in
            ToolOutput.error(message)
        }
    }

    /// Creates a tool that echoes input parameters
    public static func echoing(name: String = "EchoTool") -> MockTool {
        MockTool(
            name: name,
            schema: ToolSchema(
                properties: ["message": .init(type: "string", description: "Message to echo")],
                required: ["message"]
            )
        ) { input, _ in
            let message = input.get("message", as: String.self) ?? "no message"
            return ToolOutput.success("Echo: \(message)")
        }
    }

    /// Creates a high-risk tool for approval testing
    public static func highRisk(name: String = "HighRiskTool") -> MockTool {
        MockTool(
            name: name,
            requiresApproval: true,
            riskLevel: .high
        )
    }

    /// Creates a tool with specific schema for validation testing
    public static func withSchema(
        name: String = "SchemaTool",
        properties: [String: ToolSchema.PropertySchema],
        required: [String] = []
    ) -> MockTool {
        MockTool(
            name: name,
            schema: ToolSchema(properties: properties, required: required)
        )
    }

    /// Creates a tool that captures calls for verification
    public static func capturing(
        name: String = "CaptureTool",
        captures: @escaping @Sendable (ToolInput) -> Void
    ) -> MockTool {
        MockTool(name: name) { input, _ in
            captures(input)
            return ToolOutput.success("Captured")
        }
    }

    /// Creates a slow tool for timeout testing
    public static func slow(
        name: String = "SlowTool",
        delay: Duration = .seconds(1)
    ) -> MockTool {
        MockTool(name: name) { _, _ in
            try await Task.sleep(for: delay)
            return ToolOutput.success("Slow result")
        }
    }
}
