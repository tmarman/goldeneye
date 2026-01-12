import Foundation

// MARK: - CLI Executor

/// Spawns and monitors CLI processes (claude-code, codex, gemini-cli)
public actor CLIExecutor {
    private var runningProcesses: [String: Process] = [:]
    private var installedCLIs: [CLIType: String]? = nil

    public init() {}

    // MARK: - Execution

    /// Execute a CLI with the given configuration
    public func execute(
        taskId: String,
        config: ExecutionConfig,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> ExecutionResult {
        // Check if task is already running
        if runningProcesses[taskId] != nil {
            throw CLIRunnerError.taskAlreadyRunning(taskId)
        }

        // Find CLI executable
        let executablePath = try await findCLI(config.cli)

        // Build arguments
        let args = buildArguments(for: config)

        let startTime = Date()

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        process.currentDirectoryURL = config.workingDirectory

        // Merge environment
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in config.environment {
            environment[key] = value
        }
        process.environment = environment

        // Set up pipes for output capture
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Track running process
        runningProcesses[taskId] = process

        // Thread-safe output collector
        let outputCollector = OutputCollector()

        // Handle stdout streaming
        let stdoutHandle = stdoutPipe.fileHandleForReading
        stdoutHandle.readabilityHandler = { [outputCollector] handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task {
                    await outputCollector.appendStdout(data)
                    if let output = String(data: data, encoding: .utf8) {
                        await progress(output)
                    }
                }
            }
        }

        // Handle stderr streaming
        let stderrHandle = stderrPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { [outputCollector] handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task {
                    await outputCollector.appendStderr(data)
                }
            }
        }

        // Start process
        try process.run()

        // Wait with timeout
        if let timeout = config.timeout {
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(timeout))
                return true
            }

            let processTask = Task.detached { [process] in
                process.waitUntilExit()
                return false
            }

            // Wait for either completion or timeout
            let didTimeout = await withTaskGroup(of: Bool.self) { group in
                group.addTask { (try? await timeoutTask.value) ?? false }
                group.addTask { await processTask.value }

                // First to complete wins
                if let first = await group.next() {
                    timeoutTask.cancel()
                    return first
                }
                return false
            }

            if didTimeout {
                process.terminate()
                runningProcesses.removeValue(forKey: taskId)
                throw CLIRunnerError.executionTimeout(taskId: taskId)
            }
        } else {
            process.waitUntilExit()
        }

        // Clean up
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        runningProcesses.removeValue(forKey: taskId)

        let duration = Date().timeIntervalSince(startTime)

        // Get collected output
        let stdoutData = await outputCollector.getStdout()
        let stderrData = await outputCollector.getStderr()

        return ExecutionResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            duration: duration
        )
    }

    // MARK: - Process Management

    /// Cancel a running task
    public func cancel(taskId: String) async throws {
        guard let process = runningProcesses[taskId] else {
            throw CLIRunnerError.taskNotFound(taskId)
        }

        process.terminate()
        runningProcesses.removeValue(forKey: taskId)
    }

    /// Check if a task is currently running
    public func isRunning(taskId: String) -> Bool {
        runningProcesses[taskId]?.isRunning ?? false
    }

    /// List all running task IDs
    public func runningTasks() -> [String] {
        Array(runningProcesses.keys)
    }

    // MARK: - CLI Detection

    /// Detect which CLIs are installed
    public func detectInstalledCLIs() async -> [CLIType: String] {
        if let cached = installedCLIs {
            return cached
        }

        var found: [CLIType: String] = [:]

        for cli in CLIType.allCases {
            if let path = await findCLIPath(cli) {
                found[cli] = path
            }
        }

        installedCLIs = found
        return found
    }

    /// Get version of a specific CLI
    public func getCLIVersion(_ cli: CLIType) async throws -> String {
        let path = try await findCLI(cli)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    // MARK: - Private Helpers

    private func findCLI(_ cli: CLIType) async throws -> String {
        if let path = await findCLIPath(cli) {
            return path
        }
        throw CLIRunnerError.cliNotFound(cli)
    }

    private func findCLIPath(_ cli: CLIType) async -> String? {
        // Check common locations
        let possiblePaths = [
            "/usr/local/bin/\(cli.defaultExecutable)",
            "/opt/homebrew/bin/\(cli.defaultExecutable)",
            "\(NSHomeDirectory())/.local/bin/\(cli.defaultExecutable)",
            "\(NSHomeDirectory())/bin/\(cli.defaultExecutable)"
        ]

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try `which` command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [cli.defaultExecutable]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // which command failed
        }

        return nil
    }

    private func buildArguments(for config: ExecutionConfig) -> [String] {
        var args: [String] = []

        switch config.cli {
        case .claudeCode:
            // Claude Code arguments
            args.append("--print")  // Non-interactive mode
            args.append(config.prompt)
            args.append(contentsOf: config.additionalArgs)

        case .codex:
            // Codex CLI (hypothetical)
            args.append("--task")
            args.append(config.prompt)
            args.append("--workspace")
            args.append(".")
            args.append(contentsOf: config.additionalArgs)

        case .geminiCLI:
            // Gemini CLI (hypothetical)
            args.append("code")
            args.append("--prompt")
            args.append(config.prompt)
            args.append(contentsOf: config.additionalArgs)
        }

        return args
    }
}

// MARK: - Output Collector

/// Thread-safe collector for process output
private actor OutputCollector {
    private var stdoutData = Data()
    private var stderrData = Data()

    func appendStdout(_ data: Data) {
        stdoutData.append(data)
    }

    func appendStderr(_ data: Data) {
        stderrData.append(data)
    }

    func getStdout() -> Data {
        stdoutData
    }

    func getStderr() -> Data {
        stderrData
    }
}
