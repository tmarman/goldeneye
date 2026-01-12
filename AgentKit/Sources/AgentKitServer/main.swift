import AgentKit
import ArgumentParser
import Foundation
import Hummingbird
import Logging

@main
struct AgentKitServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentkit-server",
        abstract: "AgentKit HTTP server with A2A protocol support",
        version: AgentKitVersion.string
    )

    @Option(name: .shortAndLong, help: "Port to listen on")
    var port: Int = 8080

    @Option(name: .shortAndLong, help: "Host to bind to")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "Base directory for AgentKit data")
    var dataDir: String = "~/AgentKit"

    @Option(name: .long, help: "Log level (trace, debug, info, warning, error)")
    var logLevel: String = "info"

    @Option(name: .long, help: "LLM provider (ollama, lmstudio, mock)")
    var llmProvider: String = "ollama"

    @Option(name: .long, help: "Ollama/LMStudio base URL")
    var llmUrl: String = "http://localhost:11434"

    @Option(name: .long, help: "Model name to use")
    var model: String = "llama3.2"

    func run() async throws {
        // Configure logging
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = parseLogLevel(logLevel)
            return handler
        }

        let logger = Logger(label: "AgentKit.Server")
        logger.info("Starting AgentKit Server v\(AgentKitVersion.string)")

        // Expand data directory
        let baseDir = URL(fileURLWithPath: NSString(string: dataDir).expandingTildeInPath)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        logger.info("Data directory: \(baseDir.path)")

        // Create session store
        let sessionStore = SessionStore(baseDirectory: baseDir)

        // Create LLM provider based on configuration
        let provider: any LLMProvider = createLLMProvider(
            type: llmProvider,
            url: llmUrl,
            model: model,
            logger: logger
        )

        // Check LLM availability
        if await provider.isAvailable() {
            logger.info("LLM provider ready", metadata: [
                "provider": "\(llmProvider)",
                "model": "\(model)"
            ])
        } else {
            logger.warning("LLM provider not available - agents will not be able to think!", metadata: [
                "provider": "\(llmProvider)",
                "url": "\(llmUrl)"
            ])
        }

        // Load agents from iCloud/Agents/Team
        let agentsManager = AgentsManager()
        do {
            try await agentsManager.loadAll()
            let agentCount = await agentsManager.allAgentIds.count
            let workspaceCount = await agentsManager.allWorkspaceIds.count
            logger.info("Loaded from iCloud", metadata: [
                "agents": "\(agentCount)",
                "workspaces": "\(workspaceCount)",
                "path": "\(agentsManager.basePath.path)"
            ])
        } catch {
            logger.warning("Failed to load from iCloud: \(error)")
        }

        // Get or create default AgentKit agent definition
        let agentDef: AgentDefinition
        do {
            agentDef = try await agentsManager.getOrCreateAgent("agentkit", config: AgentConfig(
                name: "AgentKit",
                description: "Local AI agent running on Apple Silicon"
            ))
            logger.info("Using agent definition", metadata: [
                "id": "agentkit",
                "path": "\(agentDef.path.path)"
            ])
        } catch {
            logger.error("Failed to create agent definition: \(error)")
            throw error
        }

        // Create shared approval manager for HITL
        let approvalManager = ApprovalManager()
        logger.info("Approval manager ready for human-in-the-loop")

        // Create task manager with file-based config
        let taskManager = TaskManager { [provider, agentDef, approvalManager] message in
            // Create a new agent for each task
            let session = try await sessionStore.create()

            // Use system prompt from agent definition (file-based, editable)
            let config = AgentConfiguration(
                name: agentDef.config.name ?? "AgentKit",
                systemPrompt: agentDef.systemPrompt,
                tools: [ReadTool(), WriteTool(), EditTool(), BashTool(), GlobTool(), GrepTool()],
                llmProvider: provider,
                maxIterations: agentDef.config.maxIterations ?? 10
            )
            return AgentLoop(configuration: config, session: session, approvalManager: approvalManager)
        }

        // Create agent card
        let agentCard = AgentCard(
            name: "AgentKit",
            description: "Local AI agent running on Apple Silicon",
            version: AgentKitVersion.string,
            supportedInterfaces: [
                AgentInterface(url: "http://\(host):\(port)/a2a", protocolBinding: "JSONRPC")
            ],
            capabilities: AgentCapabilities(
                streaming: true,
                pushNotifications: false,
                stateTransitionHistory: true
            ),
            skills: [
                AgentSkill(
                    id: "general",
                    name: "General Assistant",
                    description: "General-purpose AI assistant with file and shell access",
                    tags: ["assistant", "files", "shell"],
                    examples: ["Read the contents of main.swift", "Create a new file"]
                )
            ]
        )

        // Configure router
        let router = Router()

        // A2A server with approval support
        let a2aServer = A2AServer<BasicRequestContext>(
            agentCard: agentCard,
            taskManager: taskManager,
            approvalManager: approvalManager
        )
        a2aServer.configure(router: router)

        // Git server
        let reposPath = baseDir.appendingPathComponent("repos")
        try FileManager.default.createDirectory(at: reposPath, withIntermediateDirectories: true)
        let gitServer = GitServer<BasicRequestContext>(reposPath: reposPath)
        gitServer.configure(router: router)

        // Health check
        router.get("/health") { _, _ -> Response in
            let data = try! JSONEncoder().encode(["status": "ok"])
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: data))
            )
        }

        // Root info
        router.get("/") { _, _ -> Response in
            let info: [String: String] = [
                "name": "AgentKit Server",
                "version": AgentKitVersion.string,
                "agent_card": "/.well-known/agent.json",
                "a2a": "/a2a",
                "repos": "/repos",
            ]
            let data = try! JSONEncoder().encode(info)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: data))
            )
        }

        // Create and run application
        let app = Application(
            router: router,
            configuration: .init(address: .hostname(host, port: port))
        )

        logger.info("Server listening on http://\(host):\(port)")
        logger.info("Agent card: http://\(host):\(port)/.well-known/agent.json")

        try await app.runService()
    }

    private func parseLogLevel(_ level: String) -> Logger.Level {
        switch level.lowercased() {
        case "trace": return .trace
        case "debug": return .debug
        case "info": return .info
        case "warning", "warn": return .warning
        case "error": return .error
        case "critical": return .critical
        default: return .info
        }
    }

    private func createLLMProvider(
        type: String,
        url: String,
        model: String,
        logger: Logger
    ) -> any LLMProvider {
        switch type.lowercased() {
        case "ollama":
            logger.info("Using Ollama provider", metadata: [
                "url": "\(url)",
                "model": "\(model)"
            ])
            return OllamaProvider(
                baseURL: URL(string: url)!,
                model: model
            )

        case "lmstudio":
            // Parse host and port from URL, defaulting to localhost:1234
            let parsedURL = URL(string: url) ?? URL(string: "http://localhost:1234")!
            let host = parsedURL.host ?? "localhost"
            let port = parsedURL.port ?? 1234

            logger.info("Using LM Studio provider", metadata: [
                "host": "\(host)",
                "port": "\(port)",
                "model": "\(model)"
            ])
            return LMStudioProvider(
                host: host,
                port: port,
                defaultModel: model
            )

        case "mock":
            logger.warning("Using mock provider - no real LLM!")
            return MockLLMProvider()

        default:
            logger.warning("Unknown provider '\(type)', falling back to Ollama")
            return OllamaProvider(
                baseURL: URL(string: url)!,
                model: model
            )
        }
    }
}
