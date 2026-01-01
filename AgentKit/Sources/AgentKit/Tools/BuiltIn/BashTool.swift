import Foundation

/// Tool for executing shell commands
public struct BashTool: Tool {
    public let name = "Bash"
    public let description = "Execute a bash command"

    public let inputSchema = ToolSchema(
        properties: [
            "command": .init(type: "string", description: "The command to execute"),
            "timeout": .init(type: "integer", description: "Timeout in seconds (optional, default 120)"),
        ],
        required: ["command"]
    )

    public let requiresApproval = true
    public let riskLevel = RiskLevel.high

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let command = try input.require("command", as: String.self)
        let timeout = input.get("timeout", as: Int.self) ?? 120

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = context.workingDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Run with timeout
        do {
            try process.run()

            // Wait with timeout
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(timeout))
                if process.isRunning {
                    process.terminate()
                }
            }

            process.waitUntilExit()
            timeoutTask.cancel()

            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: stdoutData, encoding: .utf8) ?? ""
            let errorOutput = String(data: stderrData, encoding: .utf8) ?? ""

            let exitCode = process.terminationStatus

            if exitCode == 0 {
                return .success(output.isEmpty ? "(no output)" : output)
            } else {
                let combined = [output, errorOutput].filter { !$0.isEmpty }.joined(separator: "\n")
                return .error("Exit code \(exitCode): \(combined)")
            }
        } catch {
            return .error("Failed to execute command: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        let command = input.get("command", as: String.self) ?? ""
        // Truncate long commands
        let display = command.count > 100 ? String(command.prefix(100)) + "..." : command
        return "Run: \(display)"
    }
}
