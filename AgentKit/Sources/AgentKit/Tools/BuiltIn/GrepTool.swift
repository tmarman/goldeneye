import Foundation

/// Tool for searching file contents
public struct GrepTool: Tool {
    public let name = "Grep"
    public let description = "Search for patterns in files using regular expressions"

    public let inputSchema = ToolSchema(
        properties: [
            "pattern": .init(type: "string", description: "Regular expression pattern to search for"),
            "path": .init(type: "string", description: "File or directory to search in (optional)"),
            "glob": .init(type: "string", description: "Glob pattern to filter files (optional, e.g., '*.swift')"),
            "case_insensitive": .init(type: "boolean", description: "Case insensitive search (optional)"),
        ],
        required: ["pattern"]
    )

    public let requiresApproval = false
    public let riskLevel = RiskLevel.low

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let pattern = try input.require("pattern", as: String.self)
        let path = input.get("path", as: String.self) ?? "."
        let glob = input.get("glob", as: String.self)
        let caseInsensitive = input.get("case_insensitive", as: Bool.self) ?? false

        // Use ripgrep if available, fall back to grep
        let (executable, args) = buildGrepCommand(
            pattern: pattern,
            path: path,
            glob: glob,
            caseInsensitive: caseInsensitive
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = context.workingDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if output.isEmpty {
                return .success("No matches found for '\(pattern)'")
            }

            // Limit output to avoid overwhelming context
            let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > 100 {
                let truncated = lines.prefix(100).joined(separator: "\n")
                return .success(truncated + "\n\n... (\(lines.count - 100) more lines)")
            }

            return .success(output)
        } catch {
            return .error("Search failed: \(error.localizedDescription)")
        }
    }

    private func buildGrepCommand(
        pattern: String,
        path: String,
        glob: String?,
        caseInsensitive: Bool
    ) -> (String, [String]) {
        // Check for ripgrep
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/rg")
            || FileManager.default.fileExists(atPath: "/usr/local/bin/rg")
        {
            var args = ["-n", "--color=never"]  // Line numbers, no color
            if caseInsensitive { args.append("-i") }
            if let glob = glob { args.append(contentsOf: ["--glob", glob]) }
            args.append(pattern)
            args.append(path)

            let rgPath =
                FileManager.default.fileExists(atPath: "/opt/homebrew/bin/rg")
                ? "/opt/homebrew/bin/rg" : "/usr/local/bin/rg"
            return (rgPath, args)
        }

        // Fall back to grep
        var args = ["-rn"]  // Recursive, line numbers
        if caseInsensitive { args.append("-i") }
        args.append(pattern)
        args.append(path)
        return ("/usr/bin/grep", args)
    }

    public func describeAction(_ input: ToolInput) -> String {
        let pattern = input.get("pattern", as: String.self) ?? ""
        return "Search for: \(pattern)"
    }
}
