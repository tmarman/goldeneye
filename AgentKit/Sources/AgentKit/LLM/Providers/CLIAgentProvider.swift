import Foundation

// MARK: - CLI Agent Provider Protocol

/// Protocol for providers that wrap CLI-based agent tools
///
/// Unlike traditional LLM providers that expose a completion API,
/// CLI agent providers wrap complete agent systems (Claude Code, Codex CLI,
/// Gemini CLI) that have their own tool execution and agentic loops.
///
/// These providers:
/// - Spawn a subprocess for the CLI tool
/// - Parse streaming output (typically JSON or structured text)
/// - Forward events to the AgentKit event stream
/// - Handle the CLI tool's own approval mechanisms
public protocol CLIAgentProvider: LLMProvider {
    /// Path to the CLI executable
    var executablePath: String { get }

    /// Check if the CLI tool is installed
    func isInstalled() async -> Bool

    /// Get the version of the installed CLI tool
    func version() async throws -> String
}

// MARK: - CLI Process Manager

/// Manages CLI subprocess lifecycle and output streaming
public actor CLIProcessManager {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var isRunning = false

    public init() {}

    /// Execute a CLI command and stream output
    public func execute(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil
    ) -> AsyncThrowingStream<CLIOutput, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments

                    // Merge environment
                    var env = ProcessInfo.processInfo.environment
                    for (key, value) in environment {
                        env[key] = value
                    }
                    process.environment = env

                    if let workDir = workingDirectory {
                        process.currentDirectoryURL = workDir
                    }

                    // Setup pipes
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe

                    self.process = process
                    self.outputPipe = outputPipe
                    self.errorPipe = errorPipe
                    self.isRunning = true

                    // Handle stdout
                    outputPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if !data.isEmpty {
                            if let text = String(data: data, encoding: .utf8) {
                                continuation.yield(.stdout(text))
                            }
                        }
                    }

                    // Handle stderr
                    errorPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if !data.isEmpty {
                            if let text = String(data: data, encoding: .utf8) {
                                continuation.yield(.stderr(text))
                            }
                        }
                    }

                    // Handle termination
                    process.terminationHandler = { proc in
                        Task {
                            await self.cleanup()
                            continuation.yield(.terminated(exitCode: proc.terminationStatus))
                            continuation.finish()
                        }
                    }

                    try process.run()

                } catch {
                    await self.cleanup()
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Send input to the running process
    public func sendInput(_ text: String) async throws {
        guard let process = process, isRunning else {
            throw CLIError.processNotRunning
        }

        guard let stdin = process.standardInput as? Pipe else {
            throw CLIError.stdinNotAvailable
        }

        guard let data = text.data(using: .utf8) else {
            throw CLIError.encodingError
        }

        stdin.fileHandleForWriting.write(data)
    }

    /// Terminate the running process
    public func terminate() async {
        process?.terminate()
        await cleanup()
    }

    /// Send interrupt signal (Ctrl+C)
    public func interrupt() async {
        process?.interrupt()
    }

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        isRunning = false
        process = nil
        outputPipe = nil
        errorPipe = nil
    }
}

/// Output from a CLI process
public enum CLIOutput: Sendable {
    case stdout(String)
    case stderr(String)
    case terminated(exitCode: Int32)
}

/// Errors from CLI process management
public enum CLIError: Error, Sendable {
    case processNotRunning
    case stdinNotAvailable
    case encodingError
    case executableNotFound(String)
    case executionFailed(String)
    case parseError(String)
    case timeout
}

// MARK: - CLI Output Parser

/// Protocol for parsing CLI-specific output formats
public protocol CLIOutputParser: Sendable {
    /// Parse a line of output into LLM events
    func parse(_ line: String) -> [LLMEvent]

    /// Parse accumulated output (for non-line-based formats)
    func parseAccumulated(_ text: String) -> [LLMEvent]
}

/// JSON Lines output parser (used by many CLI tools)
public struct JSONLinesParser: CLIOutputParser, Sendable {
    public init() {}

    public func parse(_ line: String) -> [LLMEvent] {
        guard !line.isEmpty,
              let data = line.data(using: .utf8)
        else { return [] }

        // Try to parse as JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // Not JSON, treat as text
            return [.textDelta(line)]
        }

        var events: [LLMEvent] = []

        // Common patterns in CLI output
        if let type = json["type"] as? String {
            switch type {
            case "text", "content":
                if let text = json["text"] as? String ?? json["content"] as? String {
                    events.append(.textDelta(text))
                }
            case "tool_use", "tool_call":
                if let id = json["id"] as? String,
                   let name = json["name"] as? String
                {
                    let input = (json["input"] as? [String: Any]) ?? [:]
                    let params = input.mapValues { AnyCodable($0) }
                    events.append(.toolCall(LLMToolCall(
                        id: id,
                        name: name,
                        input: ToolInput(parameters: params)
                    )))
                }
            case "tool_result":
                // Tool results are handled by the agent loop, not the provider
                break
            case "done", "end", "stop":
                events.append(.done)
            case "error":
                let message = json["message"] as? String ?? "Unknown error"
                events.append(.error(.unknown(message)))
            default:
                break
            }
        }

        // Check for streaming text delta
        if let delta = json["delta"] as? String {
            events.append(.textDelta(delta))
        }

        // Check for usage info
        if let usage = json["usage"] as? [String: Any],
           let input = usage["input_tokens"] as? Int,
           let output = usage["output_tokens"] as? Int
        {
            events.append(.usage(LLMUsage(inputTokens: input, outputTokens: output)))
        }

        return events
    }

    public func parseAccumulated(_ text: String) -> [LLMEvent] {
        text.split(separator: "\n").flatMap { parse(String($0)) }
    }
}

// MARK: - Base CLI Agent Provider

/// Base implementation for CLI-based agent providers
public actor BaseCLIAgentProvider: CLIAgentProvider {
    public let id: String
    public let name: String
    public let executablePath: String
    public let supportsToolCalling = true
    public let supportsStreaming = true

    private let processManager = CLIProcessManager()
    private let outputParser: CLIOutputParser
    private let buildArguments: @Sendable ([Message], [ToolDefinition], CompletionOptions) -> [String]
    private let environment: [String: String]

    public init(
        id: String,
        name: String,
        executablePath: String,
        environment: [String: String] = [:],
        outputParser: CLIOutputParser = JSONLinesParser(),
        buildArguments: @escaping @Sendable ([Message], [ToolDefinition], CompletionOptions) -> [String]
    ) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.environment = environment
        self.outputParser = outputParser
        self.buildArguments = buildArguments
    }

    public func complete(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        guard await isInstalled() else {
            throw CLIError.executableNotFound(executablePath)
        }

        let arguments = buildArguments(messages, tools, options)

        return AsyncThrowingStream { continuation in
            Task {
                var accumulatedOutput = ""

                let outputStream = await processManager.execute(
                    executable: executablePath,
                    arguments: arguments,
                    environment: environment
                )

                do {
                    for try await output in outputStream {
                        switch output {
                        case .stdout(let text):
                            accumulatedOutput += text

                            // Process complete lines
                            while let newlineIndex = accumulatedOutput.firstIndex(of: "\n") {
                                let line = String(accumulatedOutput[..<newlineIndex])
                                accumulatedOutput = String(accumulatedOutput[accumulatedOutput.index(after: newlineIndex)...])

                                let events = outputParser.parse(line)
                                for event in events {
                                    continuation.yield(event)
                                }
                            }

                        case .stderr(let text):
                            // Log stderr but don't treat as error
                            // Many CLI tools use stderr for progress/status
                            if text.lowercased().contains("error") {
                                continuation.yield(.error(.unknown(text)))
                            }

                        case .terminated(let exitCode):
                            // Process any remaining output
                            if !accumulatedOutput.isEmpty {
                                let events = outputParser.parseAccumulated(accumulatedOutput)
                                for event in events {
                                    continuation.yield(event)
                                }
                            }

                            if exitCode != 0 {
                                continuation.yield(.error(.executionFailed(
                                    "Process exited with code \(exitCode)"
                                )))
                            }
                            continuation.yield(.done)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.yield(.error(.networkError(error.localizedDescription)))
                    continuation.finish()
                }
            }
        }
    }

    public func isAvailable() async -> Bool {
        await isInstalled()
    }

    public func isInstalled() async -> Bool {
        FileManager.default.isExecutableFile(atPath: executablePath)
    }

    public func version() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    /// Cancel the current operation
    public func cancel() async {
        await processManager.interrupt()
    }

    /// Terminate the process forcefully
    public func terminate() async {
        await processManager.terminate()
    }
}

// MARK: - LLMError Extension

extension LLMError {
    static func executionFailed(_ message: String) -> LLMError {
        .providerUnavailable(message)
    }
}
