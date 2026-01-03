import Foundation

// MARK: - Claude Code Provider

/// Provider that wraps Claude Code CLI
///
/// Claude Code is Anthropic's agentic coding assistant CLI tool.
/// It provides a complete agent loop with tool execution, file editing,
/// and shell access.
///
/// Usage:
/// ```swift
/// let provider = ClaudeCodeProvider()
/// // Uses claude CLI in PATH, or specify path explicitly
/// let provider = ClaudeCodeProvider(executablePath: "/usr/local/bin/claude")
/// ```
///
/// Note: Claude Code must be installed and authenticated.
/// Install via: npm install -g @anthropic-ai/claude-code
public actor ClaudeCodeProvider: CLIAgentProvider {
    public let id = "claude-code"
    public let name = "Claude Code"
    public let supportsToolCalling = true
    public let supportsStreaming = true
    public let executablePath: String

    private let processManager = CLIProcessManager()
    private let model: String?
    private let workingDirectory: URL?
    private let allowedTools: Set<String>?
    private let maxTurns: Int?

    /// Standard Claude Code CLI locations
    public static let standardPaths = [
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
        "\(NSHomeDirectory())/.npm-global/bin/claude",
        "\(NSHomeDirectory())/.local/bin/claude"
    ]

    public init(
        executablePath: String? = nil,
        model: String? = nil,
        workingDirectory: URL? = nil,
        allowedTools: Set<String>? = nil,
        maxTurns: Int? = nil
    ) {
        self.executablePath = executablePath ?? Self.findExecutable() ?? "claude"
        self.model = model
        self.workingDirectory = workingDirectory
        self.allowedTools = allowedTools
        self.maxTurns = maxTurns
    }

    /// Find the Claude Code executable in standard locations
    public static func findExecutable() -> String? {
        // Check PATH first
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let fullPath = "\(dir)/claude"
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
            case .assistant:
                return nil // Skip assistant messages for prompt
            case .system:
                return nil // System prompt handled separately
            }
        }.joined(separator: "\n")

        // Build arguments
        var arguments = ["--print", "--output-format", "stream-json"]

        if let model = options.model ?? self.model {
            arguments += ["--model", model]
        }

        if let maxTurns = self.maxTurns {
            arguments += ["--max-turns", String(maxTurns)]
        }

        // Add allowed tools if specified
        if let tools = allowedTools {
            for tool in tools {
                arguments += ["--allowedTools", tool]
            }
        }

        // Add the prompt
        arguments += ["--prompt", prompt]

        return AsyncThrowingStream { continuation in
            Task {
                var accumulatedOutput = ""
                let parser = ClaudeCodeOutputParser()

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
                            // Claude Code uses stderr for status messages
                            // Only treat as error if it contains error indicators
                            if text.lowercased().contains("error:") ||
                               text.lowercased().contains("fatal:")
                            {
                                continuation.yield(.error(.unknown(text.trimmingCharacters(in: .whitespacesAndNewlines))))
                            }

                        case .terminated(let exitCode):
                            // Process remaining output
                            if !accumulatedOutput.isEmpty {
                                let events = parser.parseAccumulated(accumulatedOutput)
                                for event in events {
                                    continuation.yield(event)
                                }
                            }

                            if exitCode != 0 && exitCode != 130 { // 130 = SIGINT (Ctrl+C)
                                continuation.yield(.error(.providerUnavailable(
                                    "Claude Code exited with code \(exitCode)"
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
}

// MARK: - Claude Code Output Parser

/// Parser for Claude Code's stream-json output format
private struct ClaudeCodeOutputParser: CLIOutputParser {
    func parse(_ line: String) -> [LLMEvent] {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }

        var events: [LLMEvent] = []

        // Claude Code event types
        if let type = json["type"] as? String {
            switch type {
            case "assistant":
                // Assistant message with content blocks
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]]
                {
                    for block in content {
                        if let blockType = block["type"] as? String {
                            switch blockType {
                            case "text":
                                if let text = block["text"] as? String {
                                    events.append(.textDelta(text))
                                }
                            case "tool_use":
                                if let id = block["id"] as? String,
                                   let name = block["name"] as? String
                                {
                                    let input = (block["input"] as? [String: Any]) ?? [:]
                                    let params = input.mapValues { AnyCodable($0) }
                                    events.append(.toolCall(LLMToolCall(
                                        id: id,
                                        name: name,
                                        input: ToolInput(parameters: params)
                                    )))
                                }
                            default:
                                break
                            }
                        }
                    }
                }

            case "content_block_delta":
                // Streaming text delta
                if let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String
                {
                    events.append(.textDelta(text))
                }

            case "message_stop", "result":
                // Message complete
                if let result = json["result"] as? [String: Any],
                   let usage = result["usage"] as? [String: Any]
                {
                    let input = usage["input_tokens"] as? Int ?? 0
                    let output = usage["output_tokens"] as? Int ?? 0
                    events.append(.usage(LLMUsage(inputTokens: input, outputTokens: output)))
                }
                events.append(.done)

            case "error":
                let message = json["error"] as? String ?? "Unknown error"
                events.append(.error(.unknown(message)))

            case "tool_result":
                // Tool results are handled internally by Claude Code
                break

            default:
                break
            }
        }

        return events
    }

    func parseAccumulated(_ text: String) -> [LLMEvent] {
        text.split(separator: "\n").flatMap { parse(String($0)) }
    }
}
