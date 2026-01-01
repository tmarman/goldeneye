import Foundation

/// Tool for finding files by glob pattern
public struct GlobTool: Tool {
    public let name = "Glob"
    public let description = "Find files matching a glob pattern"

    public let inputSchema = ToolSchema(
        properties: [
            "pattern": .init(type: "string", description: "Glob pattern to match (e.g., '**/*.swift')"),
            "path": .init(type: "string", description: "Directory to search in (optional, defaults to working directory)"),
        ],
        required: ["pattern"]
    )

    public let requiresApproval = false
    public let riskLevel = RiskLevel.low

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let pattern = try input.require("pattern", as: String.self)
        let basePath = input.get("path", as: String.self).map { URL(fileURLWithPath: $0) }
            ?? context.workingDirectory

        // Use find command for glob matching (simpler than implementing full glob)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.currentDirectoryURL = basePath

        // Convert glob to find arguments
        // This is a simplified implementation - full glob support would need more work
        if pattern.contains("**") {
            // Recursive search
            let namePattern = pattern.replacingOccurrences(of: "**/", with: "")
            process.arguments = [".", "-name", namePattern, "-type", "f"]
        } else {
            process.arguments = [".", "-name", pattern, "-type", "f", "-maxdepth", "1"]
        }

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let files = output.split(separator: "\n")
                .map { String($0) }
                .map { $0.hasPrefix("./") ? String($0.dropFirst(2)) : $0 }
                .sorted()

            if files.isEmpty {
                return .success("No files found matching '\(pattern)'")
            }

            return .success(files.joined(separator: "\n"))
        } catch {
            return .error("Failed to search: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        let pattern = input.get("pattern", as: String.self) ?? "*"
        return "Find files matching: \(pattern)"
    }
}
