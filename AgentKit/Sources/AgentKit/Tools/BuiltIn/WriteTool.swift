import Foundation

/// Tool for writing file contents
public struct WriteTool: Tool {
    public let name = "Write"
    public let description = "Write content to a file, creating it if it doesn't exist"

    public let inputSchema = ToolSchema(
        properties: [
            "file_path": .init(type: "string", description: "Absolute path to the file to write"),
            "content": .init(type: "string", description: "Content to write to the file"),
        ],
        required: ["file_path", "content"]
    )

    public let requiresApproval = true
    public let riskLevel = RiskLevel.medium

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let filePath = try input.require("file_path", as: String.self)
        let content = try input.require("content", as: String.self)

        let url = URL(fileURLWithPath: filePath)

        do {
            // Create parent directories if needed
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

            // Write content
            try content.write(to: url, atomically: true, encoding: .utf8)

            let lineCount = content.components(separatedBy: .newlines).count
            return .success("Wrote \(lineCount) lines to \(filePath)")
        } catch {
            return .error("Failed to write file: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        let path = input.get("file_path", as: String.self) ?? "unknown"
        let content = input.get("content", as: String.self) ?? ""
        let lines = content.components(separatedBy: .newlines).count
        return "Write \(lines) lines to: \(path)"
    }
}
