import AgentKit
import ArgumentParser
import Foundation

@main
struct AgentKitCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentkit",
        abstract: "AgentKit command-line interface",
        version: AgentKitVersion.string,
        subcommands: [
            Run.self,
            Chat.self,
            Sessions.self,
        ],
        defaultSubcommand: Chat.self
    )
}

// MARK: - Run Command

extension AgentKitCLI {
    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run a task and exit"
        )

        @Argument(help: "The task to run")
        var task: String

        @Option(name: .long, help: "Session name")
        var session: String?

        @Option(name: .long, help: "Data directory")
        var dataDir: String = "~/AgentKit"

        func run() async throws {
            let baseDir = URL(fileURLWithPath: NSString(string: dataDir).expandingTildeInPath)
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

            let sessionStore = SessionStore(baseDirectory: baseDir)
            let agentSession = try await sessionStore.create(name: session)

            let config = AgentConfiguration(
                name: "AgentKit CLI",
                systemPrompt: """
                    You are a helpful AI assistant with access to the local filesystem.
                    You can read and write files, and run shell commands.
                    Be concise and helpful.
                    """,
                tools: [ReadTool(), WriteTool(), BashTool(), GlobTool(), GrepTool()],
                llmProvider: MockLLMProvider(responses: [
                    "I understand you want me to: \(task). However, I'm currently running with a mock LLM provider. To use real inference, configure MLX with a local model."
                ])
            )

            let agent = AgentLoop(configuration: config, session: agentSession)

            let agentTask = AgentTask(
                message: Message(role: .user, content: .text(task))
            )

            print("Running task: \(task)\n")

            for try await event in await agent.execute(agentTask) {
                switch event {
                case .textDelta(let delta):
                    print(delta.delta, terminator: "")
                    fflush(stdout)
                case .toolCall(let call):
                    print("\n[Tool: \(call.toolName)]")
                case .toolResult(let result):
                    if result.output.isError {
                        print("[Error: \(result.output.content)]")
                    }
                case .completed:
                    print("\n\n✓ Task completed")
                case .failed(let event):
                    print("\n\n✗ Task failed: \(event.error)")
                case .inputRequired(let request):
                    print("\n[Approval required: \(request.description)]")
                default:
                    break
                }
            }
        }
    }
}

// MARK: - Chat Command

extension AgentKitCLI {
    struct Chat: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Interactive chat session"
        )

        @Option(name: .long, help: "Session name")
        var session: String?

        @Option(name: .long, help: "Data directory")
        var dataDir: String = "~/AgentKit"

        func run() async throws {
            print("AgentKit Chat v\(AgentKitVersion.string)")
            print("Type 'exit' or 'quit' to end the session.\n")

            let baseDir = URL(fileURLWithPath: NSString(string: dataDir).expandingTildeInPath)
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

            let sessionStore = SessionStore(baseDirectory: baseDir)
            let agentSession = try await sessionStore.create(name: session)

            print("Session: \(await agentSession.id.rawValue)\n")

            let config = AgentConfiguration(
                name: "AgentKit Chat",
                systemPrompt: """
                    You are a helpful AI assistant with access to the local filesystem.
                    You can read and write files, and run shell commands.
                    Be concise and helpful.
                    """,
                tools: [ReadTool(), WriteTool(), BashTool(), GlobTool(), GrepTool()],
                llmProvider: MockLLMProvider()
            )

            let agent = AgentLoop(configuration: config, session: agentSession)

            while true {
                print("> ", terminator: "")
                fflush(stdout)

                guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !input.isEmpty
                else {
                    continue
                }

                if input.lowercased() == "exit" || input.lowercased() == "quit" {
                    print("Goodbye!")
                    break
                }

                let task = AgentTask(
                    message: Message(role: .user, content: .text(input))
                )

                for try await event in await agent.execute(task) {
                    switch event {
                    case .textDelta(let delta):
                        print(delta.delta, terminator: "")
                        fflush(stdout)
                    case .completed:
                        print("\n")
                    default:
                        break
                    }
                }
            }
        }
    }
}

// MARK: - Sessions Command

extension AgentKitCLI {
    struct Sessions: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage sessions",
            subcommands: [
                List.self,
                Delete.self,
            ]
        )

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List all sessions"
            )

            @Option(name: .long, help: "Data directory")
            var dataDir: String = "~/AgentKit"

            func run() async throws {
                let baseDir = URL(fileURLWithPath: NSString(string: dataDir).expandingTildeInPath)
                let sessionStore = SessionStore(baseDirectory: baseDir)

                let sessions = try await sessionStore.list()

                if sessions.isEmpty {
                    print("No sessions found.")
                } else {
                    print("Sessions:")
                    for session in sessions {
                        print("  - \(session.rawValue)")
                    }
                }
            }
        }

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Delete a session"
            )

            @Argument(help: "Session ID to delete")
            var sessionId: String

            @Option(name: .long, help: "Data directory")
            var dataDir: String = "~/AgentKit"

            func run() async throws {
                let baseDir = URL(fileURLWithPath: NSString(string: dataDir).expandingTildeInPath)
                let sessionStore = SessionStore(baseDirectory: baseDir)

                try await sessionStore.delete(SessionID(sessionId))
                print("Deleted session: \(sessionId)")
            }
        }
    }
}
