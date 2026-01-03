import Foundation

// MARK: - Gemini CLI Provider

/// Provider that wraps Google's Gemini CLI
///
/// Gemini CLI is Google's agentic coding assistant that provides
/// code generation, editing, and multimodal capabilities.
///
/// Usage:
/// ```swift
/// let provider = GeminiCLIProvider()
/// // Uses gemini CLI in PATH, or specify path explicitly
/// let provider = GeminiCLIProvider(executablePath: "/usr/local/bin/gemini")
/// ```
///
/// Note: Gemini CLI must be installed and authenticated with Google.
/// Install via: npm install -g @google/gemini-cli
public actor GeminiCLIProvider: CLIAgentProvider {
    public let id = "gemini-cli"
    public let name = "Gemini CLI"
    public let supportsToolCalling = true
    public let supportsStreaming = true
    public let executablePath: String

    private let processManager = CLIProcessManager()
    private let model: String?
    private let workingDirectory: URL?
    private let sandboxMode: SandboxMode

    /// Sandbox mode for Gemini CLI
    public enum SandboxMode: String, Sendable {
        /// No sandboxing (full access)
        case none
        /// Sandbox file operations
        case files
        /// Full sandbox (files + network)
        case full
    }

    /// Standard Gemini CLI locations
    public static let standardPaths = [
        "/usr/local/bin/gemini",
        "/opt/homebrew/bin/gemini",
        "\(NSHomeDirectory())/.npm-global/bin/gemini",
        "\(NSHomeDirectory())/.local/bin/gemini"
    ]

    public init(
        executablePath: String? = nil,
        model: String? = nil,
        workingDirectory: URL? = nil,
        sandboxMode: SandboxMode = .none
    ) {
        self.executablePath = executablePath ?? Self.findExecutable() ?? "gemini"
        self.model = model
        self.workingDirectory = workingDirectory
        self.sandboxMode = sandboxMode
    }

    /// Find the Gemini CLI executable in standard locations
    public static func findExecutable() -> String? {
        // Check PATH first
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let fullPath = "\(dir)/gemini"
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

        // Model selection
        if let model = options.model ?? self.model {
            arguments += ["-m", model]
        }

        // Sandbox mode
        if sandboxMode != .none {
            arguments += ["--sandbox", sandboxMode.rawValue]
        }

        // Non-interactive mode with streaming
        arguments += ["--non-interactive", "--stream"]

        // Add the prompt (Gemini CLI typically reads from stdin or -p flag)
        arguments += ["-p", prompt]

        return AsyncThrowingStream { continuation in
            Task {
                var accumulatedOutput = ""
                let parser = GeminiOutputParser()

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
                                    "Gemini CLI exited with code \(exitCode)"
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

// MARK: - Gemini Output Parser

private struct GeminiOutputParser: CLIOutputParser {
    func parse(_ line: String) -> [LLMEvent] {
        guard !line.isEmpty else { return [] }

        // Try JSON first (Gemini CLI may output JSON in streaming mode)
        if let data = line.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return parseJSON(json)
        }

        // Check for special prefixes
        if line.hasPrefix("🤖 ") || line.hasPrefix("Gemini: ") {
            let content = line
                .replacingOccurrences(of: "🤖 ", with: "")
                .replacingOccurrences(of: "Gemini: ", with: "")
            return [.textDelta(content + "\n")]
        }

        if line.hasPrefix("📁 ") || line.hasPrefix("File: ") {
            return [.textDelta(line + "\n")]
        }

        if line.hasPrefix("⚡ ") || line.hasPrefix("Running: ") {
            return [.textDelta(line + "\n")]
        }

        // Plain text output
        return [.textDelta(line + "\n")]
    }

    private func parseJSON(_ json: [String: Any]) -> [LLMEvent] {
        var events: [LLMEvent] = []

        if let type = json["type"] as? String {
            switch type {
            case "text", "content":
                if let text = json["text"] as? String ?? json["content"] as? String {
                    events.append(.textDelta(text))
                }

            case "functionCall", "function_call", "tool_call":
                let name = json["name"] as? String ?? json["functionName"] as? String ?? ""
                let id = json["id"] as? String ?? UUID().uuidString
                let args = json["args"] as? [String: Any] ?? json["arguments"] as? [String: Any] ?? [:]
                let params = args.mapValues { AnyCodable($0) }
                events.append(.toolCall(LLMToolCall(
                    id: id,
                    name: name,
                    input: ToolInput(parameters: params)
                )))

            case "codeExecution":
                if let code = json["code"] as? String {
                    let language = json["language"] as? String ?? ""
                    events.append(.textDelta("```\(language)\n\(code)\n```\n"))
                }

            case "done", "complete", "finished":
                events.append(.done)

            case "error":
                let message = json["message"] as? String ?? json["error"] as? String ?? "Unknown error"
                events.append(.error(.unknown(message)))

            default:
                break
            }
        }

        // Handle candidates array (Gemini API format)
        if let candidates = json["candidates"] as? [[String: Any]],
           let firstCandidate = candidates.first,
           let content = firstCandidate["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]]
        {
            for part in parts {
                if let text = part["text"] as? String {
                    events.append(.textDelta(text))
                }
                if let functionCall = part["functionCall"] as? [String: Any],
                   let name = functionCall["name"] as? String
                {
                    let args = functionCall["args"] as? [String: Any] ?? [:]
                    let params = args.mapValues { AnyCodable($0) }
                    events.append(.toolCall(LLMToolCall(
                        id: UUID().uuidString,
                        name: name,
                        input: ToolInput(parameters: params)
                    )))
                }
            }
        }

        // Handle usage metadata
        if let usageMetadata = json["usageMetadata"] as? [String: Any] {
            let input = usageMetadata["promptTokenCount"] as? Int ?? 0
            let output = usageMetadata["candidatesTokenCount"] as? Int ?? 0
            events.append(.usage(LLMUsage(inputTokens: input, outputTokens: output)))
        }

        return events
    }

    func parseAccumulated(_ text: String) -> [LLMEvent] {
        text.split(separator: "\n").flatMap { parse(String($0)) }
    }
}
