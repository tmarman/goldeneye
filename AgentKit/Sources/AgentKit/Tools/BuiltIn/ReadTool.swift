import Foundation

/// Tool for reading file contents
public struct ReadTool: Tool {
    public let name = "Read"
    public let description = "Read the contents of a file"

    public let inputSchema = ToolSchema(
        properties: [
            "file_path": .init(type: "string", description: "Absolute path to the file to read"),
            "offset": .init(type: "integer", description: "Line number to start reading from (optional)"),
            "limit": .init(type: "integer", description: "Maximum number of lines to read (optional)"),
        ],
        required: ["file_path"]
    )

    public let requiresApproval = false
    public let riskLevel = RiskLevel.low

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let filePath = try input.require("file_path", as: String.self)
        let offset = input.get("offset", as: Int.self) ?? 0
        let limit = input.get("limit", as: Int.self)

        let url = URL(fileURLWithPath: filePath)

        guard FileManager.default.fileExists(atPath: filePath) else {
            return .error("File not found: \(filePath)")
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            var lines = content.components(separatedBy: .newlines)

            // Apply offset
            if offset > 0 {
                lines = Array(lines.dropFirst(offset))
            }

            // Apply limit
            if let limit = limit {
                lines = Array(lines.prefix(limit))
            }

            // Format with line numbers
            let numbered = lines.enumerated().map { index, line in
                String(format: "%6d\t%@", offset + index + 1, line)
            }.joined(separator: "\n")

            return .success(numbered)
        } catch {
            return .error("Failed to read file: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        let path = input.get("file_path", as: String.self) ?? "unknown"
        return "Read file: \(path)"
    }
}
