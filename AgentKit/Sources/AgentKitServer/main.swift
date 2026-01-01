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

        // Create task manager
        let taskManager = TaskManager { message in
            // Create a new agent for each task
            let session = try await sessionStore.create()
            let config = AgentConfiguration(
                name: "AgentKit",
                systemPrompt: "You are a helpful AI assistant.",
                tools: [ReadTool(), WriteTool(), BashTool(), GlobTool(), GrepTool()],
                llmProvider: MockLLMProvider()  // TODO: Replace with MLX
            )
            return AgentLoop(configuration: config, session: session)
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

        // A2A server
        let a2aServer = A2AServer<BasicRequestContext>(agentCard: agentCard, taskManager: taskManager)
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
}
