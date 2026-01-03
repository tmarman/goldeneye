import Foundation

// MARK: - Codex CLI Provider

/// Provider that wraps OpenAI's Codex CLI
///
/// Codex CLI is OpenAI's agentic coding assistant that provides
/// code generation, editing, and shell access capabilities.
///
/// Usage:
/// ```swift
/// let provider = CodexCLIProvider()
/// // Uses codex CLI in PATH, or specify path explicitly
/// let provider = CodexCLIProvider(executablePath: "/usr/local/bin/codex")
/// ```
///
/// Note: Codex CLI must be installed and authenticated with OpenAI.
/// Install via: npm install -g @openai/codex
public actor CodexCLIProvider: CLIAgentProvider {
    public let id = "codex-cli"
    public let name = "Codex CLI"
    public let supportsToolCalling = true
    public let supportsStreaming = true
    public let executablePath: String

    private let processManager = CLIProcessManager()
    private let model: String?
    private let workingDirectory: URL?
    private let approvalMode: ApprovalMode

    /// Approval mode for Codex CLI
    public enum ApprovalMode: String, Sendable {
        /// Suggest changes but require approval
        case suggest
        /// Auto-approve safe edits, ask for others
        case autoEdit = "auto-edit"
        /// Full auto mode - approve everything
        case fullAuto = "full-auto"
    }

    /// Standard Codex CLI locations
    public static let standardPaths = [
        "/usr/local/bin/codex",
        "/opt/homebrew/bin/codex",
        "\(NSHomeDirectory())/.npm-global/bin/codex",
        "\(NSHomeDirectory())/.local/bin/codex"
    ]

    public init(
        executablePath: String? = nil,
        model: String? = nil,
        workingDirectory: URL? = nil,
        approvalMode: ApprovalMode = .suggest
    ) {
        self.executablePath = executablePath ?? Self.findExecutable() ?? "codex"
        self.model = model
        self.workingDirectory = workingDirectory
        self.approvalMode = approvalMode
    }

    /// Find the Codex CLI executable in standard locations
    public static func findExecutable() -> String? {
        // Check PATH first
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let fullPath = "\(dir)/codex"
                if FileManager.default.isExecutableFile(atPath: fullPath) {
                    return fullPath
                }
            }
        }

        // Check standard locations
        for path in standardPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    public func complete(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error> {
        guard await isInstalled() else {
            throw CLIError.executableNotFound(executablePath)
        }

        // Build prompt from messages
        let prompt = messages.compactMap { message -> String? in
            switch message.role {
            case .user:
                return message.textContent
            case .assistant, .system:
                return nil
            }
        }.joined(separator: "\n")

        // Build arguments
        var arguments: [String] = []

        // Approval mode
        arguments += ["--approval-mode", approvalMode.rawValue]

        // Model selection
        if let model = options.model ?? self.model {
            arguments += ["--model", model]
        }

        // Quiet mode for JSON output
        arguments += ["--quiet"]

        // Add the prompt
        arguments.append(prompt)

        return AsyncThrowingStream { continuation in
            Task {
                var accumulatedOutput = ""
                let parser = CodexOutputParser()

                let outputStream = await processManager.execute(
                    executable: executablePath,
                    arguments: arguments,
                    workingDirectory: workingDirectory
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

                                let events = parser.parse(line)
                                for event in events {
                                    continuation.yield(event)
                                }
                            }

                        case .stderr(let text):
                            if text.lowercased().contains("error") {
                                continuation.yield(.error(.unknown(text.trimmingCharacters(in: .whitespacesAndNewlines))))
                            }

                        case .terminated(let exitCode):
                            if !accumulatedOutput.isEmpty {
                                let events = parser.parseAccumulated(accumulatedOutput)
                                for event in events {
                                    continuation.yield(event)
                                }
                            }

                            if exitCode != 0 && exitCode != 130 {
                                continuation.yield(.error(.providerUnavailable(
                                    "Codex CLI exited with code \(exitCode)"
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

    public func cancel() async {
        await processManager.interrupt()
    }
}

// MARK: - Codex Output Parser

private struct CodexOutputParser: CLIOutputParser {
    func parse(_ line: String) -> [LLMEvent] {
        guard !line.isEmpty else { return [] }

        // Try JSON first
        if let data = line.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return parseJSON(json)
        }

        // Fallback to plain text
        return [.textDelta(line + "\n")]
    }

    private func parseJSON(_ json: [String: Any]) -> [LLMEvent] {
        var events: [LLMEvent] = []

        if let type = json["type"] as? String {
            switch type {
            case "message":
                if let content = json["content"] as? String {
                    events.append(.textDelta(content))
                }

            case "function_call", "tool_call":
                if let name = json["name"] as? String {
                    let id = json["id"] as? String ?? UUID().uuidString
                    let args = json["arguments"] as? [String: Any] ?? [:]
                    let params = args.mapValues { AnyCodable($0) }
                    events.append(.toolCall(LLMToolCall(
                        id: id,
                        name: name,
                        input: ToolInput(parameters: params)
                    )))
                }

            case "file_edit":
                // Codex reports file edits
                if let path = json["path"] as? String,
                   let diff = json["diff"] as? String
                {
                    events.append(.textDelta("Editing \(path):\n\(diff)\n"))
                }

            case "shell":
                // Shell command execution
                if let command = json["command"] as? String {
                    events.append(.textDelta("$ \(command)\n"))
                }
                if let output = json["output"] as? String {
                    events.append(.textDelta(output))
                }

            case "complete", "done":
                events.append(.done)

            case "error":
                let message = json["message"] as? String ?? "Unknown error"
                events.append(.error(.unknown(message)))

            default:
                break
            }
        }

        // Handle usage info
        if let usage = json["usage"] as? [String: Any] {
            let input = usage["prompt_tokens"] as? Int ?? usage["input_tokens"] as? Int ?? 0
            let output = usage["completion_tokens"] as? Int ?? usage["output_tokens"] as? Int ?? 0
            events.append(.usage(LLMUsage(inputTokens: input, outputTokens: output)))
        }

        return events
    }

    func parseAccumulated(_ text: String) -> [LLMEvent] {
        text.split(separator: "\n").flatMap { parse(String($0)) }
    }
}
