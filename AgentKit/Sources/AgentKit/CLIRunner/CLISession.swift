import Foundation

// MARK: - CLI Session

/// An interactive CLI session that can be viewed and controlled remotely
public actor CLISession: Identifiable {
    public nonisolated let id: String
    public nonisolated let taskId: String
    public nonisolated let cli: CLIType
    public nonisolated let createdAt: Date

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputBuffer: Data = Data()
    private var status: SessionStatus = .pending
    private var exitCode: Int32?

    // Stream continuations for real-time output
    private var outputContinuations: [UUID: AsyncStream<SessionOutput>.Continuation] = [:]

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        cli: CLIType,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.cli = cli
        self.createdAt = createdAt
    }

    // MARK: - Lifecycle

    /// Start the CLI session
    public func start(
        prompt: String,
        workingDirectory: URL,
        environment: [String: String] = [:]
    ) async throws {
        guard status == .pending else {
            throw CLISessionError.alreadyStarted
        }

        let process = Process()

        // Find CLI executable
        let cliPath = try await findCLI(cli)
        process.executableURL = URL(fileURLWithPath: cliPath)

        // Build arguments for interactive mode
        process.arguments = buildInteractiveArgs(prompt: prompt)
        process.currentDirectoryURL = workingDirectory

        // Merge environment
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        // Force color output and interactive mode
        env["TERM"] = "xterm-256color"
        env["FORCE_COLOR"] = "1"
        process.environment = env

        // Set up pipes
        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe  // Combine stderr with stdout

        // Handle output
        let outputHandle = outputPipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            Task { [weak self] in
                await self?.handleOutput(data)
            }
        }

        // Handle termination
        process.terminationHandler = { [weak self] process in
            Task { [weak self] in
                await self?.handleTermination(exitCode: process.terminationStatus)
            }
        }

        // Start
        try process.run()

        self.process = process
        self.inputPipe = inputPipe
        self.status = .running
    }

    /// Send input to the session
    public func sendInput(_ text: String) async throws {
        guard status == .running,
              let inputPipe = inputPipe else {
            throw CLISessionError.notRunning
        }

        guard let data = text.data(using: .utf8) else {
            throw CLISessionError.invalidInput
        }

        inputPipe.fileHandleForWriting.write(data)
    }

    /// Send a control character (e.g., Ctrl+C)
    public func sendControl(_ character: ControlCharacter) async throws {
        let byte: UInt8 = switch character {
        case .c: 0x03  // ETX - Ctrl+C
        case .d: 0x04  // EOT - Ctrl+D
        case .z: 0x1A  // SUB - Ctrl+Z
        case .l: 0x0C  // FF - Ctrl+L (clear)
        }

        try await sendInput(String(bytes: [byte], encoding: .utf8) ?? "")
    }

    /// Terminate the session
    public func terminate() async {
        process?.terminate()
        status = .terminated
        notifyAllListeners(SessionOutput(type: .terminated, data: nil))
        closeAllStreams()
    }

    /// Kill the session forcefully
    public func kill() async {
        if let process = process, process.isRunning {
            // Send SIGKILL
            Foundation.kill(process.processIdentifier, SIGKILL)
        }
        status = .terminated
        notifyAllListeners(SessionOutput(type: .terminated, data: nil))
        closeAllStreams()
    }

    // MARK: - Streaming

    /// Subscribe to session output
    public func outputStream() -> AsyncStream<SessionOutput> {
        let id = UUID()

        return AsyncStream { continuation in
            // Send buffered output first
            if !outputBuffer.isEmpty {
                continuation.yield(SessionOutput(type: .stdout, data: outputBuffer))
            }

            // Store continuation for future output
            outputContinuations[id] = continuation

            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeListener(id)
                }
            }
        }
    }

    /// Get current output buffer (for initial sync)
    public func getOutputBuffer() -> Data {
        outputBuffer
    }

    /// Get session info
    public func getInfo() -> SessionInfo {
        SessionInfo(
            id: id,
            taskId: taskId,
            cli: cli,
            status: status,
            createdAt: createdAt,
            outputSize: outputBuffer.count,
            exitCode: exitCode
        )
    }

    // MARK: - Private

    private func handleOutput(_ data: Data) {
        outputBuffer.append(data)
        notifyAllListeners(SessionOutput(type: .stdout, data: data))
    }

    private func handleTermination(exitCode: Int32) {
        self.exitCode = exitCode
        self.status = exitCode == 0 ? .completed : .failed
        notifyAllListeners(SessionOutput(type: .exit(code: exitCode), data: nil))
        closeAllStreams()
    }

    private func notifyAllListeners(_ output: SessionOutput) {
        for continuation in outputContinuations.values {
            continuation.yield(output)
        }
    }

    private func closeAllStreams() {
        for continuation in outputContinuations.values {
            continuation.finish()
        }
        outputContinuations.removeAll()
    }

    private func removeListener(_ id: UUID) {
        outputContinuations.removeValue(forKey: id)
    }

    private func findCLI(_ cli: CLIType) async throws -> String {
        let possiblePaths = [
            "/usr/local/bin/\(cli.defaultExecutable)",
            "/opt/homebrew/bin/\(cli.defaultExecutable)",
            "\(NSHomeDirectory())/.local/bin/\(cli.defaultExecutable)"
        ]

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        throw CLIRunnerError.cliNotFound(cli)
    }

    private func buildInteractiveArgs(prompt: String) -> [String] {
        switch cli {
        case .claudeCode:
            // Claude Code in interactive mode
            return [prompt]  // Just pass prompt, it will be interactive by default

        case .codex:
            return ["--task", prompt, "--interactive"]

        case .geminiCLI:
            return ["chat", "--prompt", prompt]
        }
    }
}

// MARK: - Supporting Types

public enum SessionStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case terminated
}

public enum ControlCharacter: String, Codable, Sendable {
    case c  // Interrupt
    case d  // EOF
    case z  // Suspend
    case l  // Clear
}

public struct SessionOutput: Sendable {
    public let type: OutputType
    public let data: Data?

    public enum OutputType: Sendable {
        case stdout
        case stderr
        case exit(code: Int32)
        case terminated
    }
}

public struct SessionInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let taskId: String
    public let cli: CLIType
    public let status: SessionStatus
    public let createdAt: Date
    public let outputSize: Int
    public let exitCode: Int32?

    public init(
        id: String,
        taskId: String,
        cli: CLIType,
        status: SessionStatus,
        createdAt: Date,
        outputSize: Int,
        exitCode: Int32?
    ) {
        self.id = id
        self.taskId = taskId
        self.cli = cli
        self.status = status
        self.createdAt = createdAt
        self.outputSize = outputSize
        self.exitCode = exitCode
    }
}

public enum CLISessionError: Error, Sendable {
    case alreadyStarted
    case notRunning
    case invalidInput
    case sessionNotFound(String)
}
