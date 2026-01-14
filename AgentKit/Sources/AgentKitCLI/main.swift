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
            MLX.self,
        ],
        defaultSubcommand: Chat.self
    )
}

// MARK: - MLX Command

extension AgentKitCLI {
    struct MLX: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "MLX local model commands",
            subcommands: [
                ListModels.self,
                TestModel.self,
                Generate.self,
            ]
        )
        
        struct ListModels: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "list",
                abstract: "List available MLX models"
            )
            
            func run() async throws {
                print("Cached MLX Models:")
                print("------------------")
                
                let cachedModels = MLXProvider.cachedModels()
                if cachedModels.isEmpty {
                    print("  No cached models found.")
                    print("\n  Download a model with: agentkit mlx test <model-id>")
                } else {
                    for model in cachedModels {
                        let statusIcon = model.hasWeights ? "✓" : "⚠"
                        print("  \(statusIcon) \(model.id)")
                        print("    Size: \(model.sizeFormatted)")
                        print("    Status: \(model.status)\n")
                    }
                }
                
                print("\nRecommended Models (from mlx-community):")
                print("-----------------------------------------")
                for model in MLXProvider.recommendedModels {
                    print("  • \(model.name) (\(model.size))")
                    print("    ID: \(model.id)")
                    print("    \(model.description)\n")
                }
            }
        }
        
        struct TestModel: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "test",
                abstract: "Test loading and running an MLX model"
            )
            
            @Argument(help: "Model ID (e.g., mlx-community/Qwen2.5-7B-Instruct-4bit)")
            var modelId: String = "mlx-community/Qwen2.5-7B-Instruct-4bit"
            
            func run() async throws {
                print("Testing MLX Provider")
                print("====================")
                print("Model: \(modelId)\n")
                
                print("Loading model (this may download if not cached)...")
                let startLoad = ContinuousClock.now
                
                let provider = MLXProvider(modelId: modelId, lazyLoad: false)
                
                // Force load by checking availability
                let isAvailable = await provider.isAvailable()
                guard isAvailable else {
                    print("❌ Model not available")
                    return
                }
                
                let loadDuration = ContinuousClock.now - startLoad
                print("✓ Model loaded in \(loadDuration)\n")
                
                // Show memory usage
                let memory = await provider.memoryUsage()
                print("Memory Usage:")
                print("  Current: \(MLXProvider.formatMemory(memory.current))")
                print("  Peak: \(MLXProvider.formatMemory(memory.peak))\n")
                
                // Test generation
                print("Testing generation...")
                let prompt = "Hello! Please respond with a short greeting."
                print("Prompt: \"\(prompt)\"\n")
                
                let messages = [
                    Message(role: .system, content: .text("You are a helpful assistant. Be concise.")),
                    Message(role: .user, content: .text(prompt))
                ]
                
                let startGen = ContinuousClock.now
                print("Response: ", terminator: "")
                fflush(stdout)
                
                var tokenCount = 0
                for try await event in try await provider.complete(messages, tools: [], options: .default) {
                    switch event {
                    case .textDelta(let delta):
                        print(delta, terminator: "")
                        fflush(stdout)
                        tokenCount += 1
                    case .usage(let usage):
                        print("\n\nTokens: \(usage.inputTokens) in, \(usage.outputTokens) out")
                    case .done:
                        let genDuration = ContinuousClock.now - startGen
                        let tokensPerSecond = Double(tokenCount) / Double(genDuration.components.seconds)
                        print("Generation time: \(genDuration)")
                        print("Speed: ~\(String(format: "%.1f", tokensPerSecond)) tok/s")
                    case .error(let error):
                        print("\n❌ Error: \(error)")
                    default:
                        break
                    }
                }
                
                print("\n✓ Test complete!")
            }
        }
        
        struct Generate: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "generate",
                abstract: "Generate text with an MLX model"
            )
            
            @Argument(help: "The prompt to generate from")
            var prompt: String
            
            @Option(name: .shortAndLong, help: "Model ID")
            var model: String = "mlx-community/Qwen2.5-7B-Instruct-4bit"
            
            @Option(name: .long, help: "System prompt")
            var system: String = "You are a helpful assistant."
            
            @Option(name: .long, help: "Maximum tokens to generate")
            var maxTokens: Int = 1024
            
            @Option(name: .long, help: "Temperature (0.0-2.0)")
            var temperature: Double = 0.7
            
            func run() async throws {
                let provider = MLXProvider(
                    modelId: model,
                    configuration: MLXConfiguration(
                        maxTokens: maxTokens,
                        temperature: Float(temperature)
                    )
                )
                
                let messages = [
                    Message(role: .system, content: .text(system)),
                    Message(role: .user, content: .text(prompt))
                ]
                
                for try await event in try await provider.complete(messages, tools: [], options: .default) {
                    switch event {
                    case .textDelta(let delta):
                        print(delta, terminator: "")
                        fflush(stdout)
                    case .done:
                        print()
                    default:
                        break
                    }
                }
            }
        }
    }
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
        
        @Flag(name: .long, help: "Use MLX for local inference")
        var mlx: Bool = false
        
        @Option(name: .long, help: "MLX model ID (requires --mlx)")
        var model: String = "mlx-community/Qwen2.5-7B-Instruct-4bit"

        func run() async throws {
            print("AgentKit Chat v\(AgentKitVersion.string)")
            
            // Create LLM provider
            let llmProvider: any LLMProvider
            if mlx {
                print("Using MLX with model: \(model)")
                print("Loading model (this may take a moment)...")
                llmProvider = MLXProvider(modelId: model)
            } else {
                print("Using mock provider (use --mlx for local inference)")
                llmProvider = MockLLMProvider()
            }
            
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
                llmProvider: llmProvider
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
                
                // Special commands
                if input.lowercased() == "/memory" && mlx {
                    if let mlxProvider = llmProvider as? MLXProvider {
                        let memory = await mlxProvider.memoryUsage()
                        print("Memory: \(MLXProvider.formatMemory(memory.current)) (peak: \(MLXProvider.formatMemory(memory.peak)))\n")
                    }
                    continue
                }

                let task = AgentTask(
                    message: Message(role: .user, content: .text(input))
                )

                for try await event in await agent.execute(task) {
                    switch event {
                    case .textDelta(let delta):
                        print(delta.delta, terminator: "")
                        fflush(stdout)
                    case .toolCall(let call):
                        print("\n[Tool: \(call.toolName)]", terminator: "")
                    case .toolResult(let result):
                        if result.output.isError {
                            print(" ❌")
                        } else {
                            print(" ✓")
                        }
                    case .completed:
                        print("\n")
                    case .failed(let event):
                        print("\n❌ Error: \(event.error)\n")
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
