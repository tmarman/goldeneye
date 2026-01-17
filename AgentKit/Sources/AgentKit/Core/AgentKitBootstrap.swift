import Foundation
import Logging

// MARK: - AgentKit Bootstrap

/// Bootstraps and configures all AgentKit services for application startup.
///
/// AgentKitBootstrap is the entry point for initializing the agent system.
/// It creates and wires together all the core services:
/// - AgentRegistry (agent discovery)
/// - EventBus (event routing)
/// - ProviderSelector (LLM provider selection)
/// - ChannelOrchestrator (message routing)
///
/// Usage:
/// ```swift
/// // At app startup
/// let agentKit = try await AgentKitBootstrap.initialize(
///     workingDirectory: documentsURL,
///     config: .default
/// )
///
/// // Access services
/// let orchestrator = agentKit.channelOrchestrator
/// let registry = agentKit.registry
///
/// // Later, configure a channel
/// await orchestrator.setupSimpleChannel(channelId, agent: conciergeId) { message in
///     // Handle message in UI
/// }
/// ```
public actor AgentKitBootstrap {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        /// Provider configuration
        public var providerConfig: ProviderSelector.Configuration

        /// Default agents to register at startup
        public var defaultAgents: [DefaultAgentConfig]

        /// Default tools available to all agents
        public var defaultToolNames: [String]

        /// Working directory for agent sessions
        public var workingDirectory: URL?

        public static let `default` = Configuration(
            providerConfig: .default,
            defaultAgents: [
                DefaultAgentConfig(
                    name: "Concierge",
                    profile: .concierge,
                    capabilities: [.routing, .conversation, .scheduling]
                ),
                DefaultAgentConfig(
                    name: "Librarian",
                    profile: .librarian,
                    capabilities: [.research, .retrieval, .summarization]
                ),
                DefaultAgentConfig(
                    name: "Executor",
                    profile: .executor,
                    capabilities: [.coding, .integration]
                )
            ],
            defaultToolNames: [],
            workingDirectory: nil
        )

        public init(
            providerConfig: ProviderSelector.Configuration = .default,
            defaultAgents: [DefaultAgentConfig] = [],
            defaultToolNames: [String] = [],
            workingDirectory: URL? = nil
        ) {
            self.providerConfig = providerConfig
            self.defaultAgents = defaultAgents
            self.defaultToolNames = defaultToolNames
            self.workingDirectory = workingDirectory
        }
    }

    public struct DefaultAgentConfig: Sendable {
        public let name: String
        public let profile: AgentProfile
        public let capabilities: Set<AgentCapability>

        public init(name: String, profile: AgentProfile, capabilities: Set<AgentCapability>) {
            self.name = name
            self.profile = profile
            self.capabilities = capabilities
        }
    }

    // MARK: - Services

    /// The agent registry
    public let registry: AgentRegistry

    /// The event bus
    public let eventBus: EventBus

    /// The provider selector
    public let providerSelector: ProviderSelector

    /// The channel orchestrator
    public let channelOrchestrator: ChannelOrchestrator

    /// The shared session
    public let session: Session

    /// Available tools
    public private(set) var tools: [any Tool] = []

    private let logger = Logger(label: "AgentKit.Bootstrap")
    private let config: Configuration

    // MARK: - Initialization

    private init(
        config: Configuration,
        registry: AgentRegistry,
        eventBus: EventBus,
        providerSelector: ProviderSelector,
        channelOrchestrator: ChannelOrchestrator,
        session: Session,
        tools: [any Tool]
    ) {
        self.config = config
        self.registry = registry
        self.eventBus = eventBus
        self.providerSelector = providerSelector
        self.channelOrchestrator = channelOrchestrator
        self.session = session
        self.tools = tools
    }

    /// Initialize AgentKit with the given configuration
    public static func initialize(
        workingDirectory: URL? = nil,
        config: Configuration = .default
    ) async throws -> AgentKitBootstrap {
        let logger = Logger(label: "AgentKit.Bootstrap")
        logger.info("Initializing AgentKit")

        // 1. Create core services
        let registry = AgentRegistry()
        let eventBus = EventBus()

        // 2. Determine working directory
        let workDir = workingDirectory
            ?? config.workingDirectory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("AgentKit")

        // Ensure directory exists
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        // 3. Create session
        let session = Session(workingDirectory: workDir)

        // 4. Create provider selector
        let providerSelector = ProviderSelector(config: config.providerConfig)

        // 5. Check provider availability
        let availability = await providerSelector.checkAvailability()
        for (type, available) in availability {
            logger.info("Provider status", metadata: [
                "provider": "\(type.displayName)",
                "available": "\(available)"
            ])
        }

        // 6. Create default tools
        let tools = createDefaultTools(session: session)

        // 7. Create channel orchestrator
        let orchestrator = ChannelOrchestrator(
            registry: registry,
            eventBus: eventBus,
            session: session,
            providerSelector: providerSelector,
            defaultTools: tools
        ) { agentId, config in
            // Default agent factory creates AgentLoop instances
            AgentLoop(id: agentId, configuration: config, session: session)
        }

        // 8. Register default agents
        for agentConfig in config.defaultAgents {
            let agent = RegisteredAgent(
                id: AgentID(agentConfig.name.lowercased()),
                name: agentConfig.name,
                profile: agentConfig.profile,
                capabilities: agentConfig.capabilities,
                status: .available
            )
            await registry.register(agent)
            logger.info("Registered agent", metadata: [
                "name": "\(agent.name)",
                "profile": "\(agent.profile.displayName)"
            ])
        }

        let bootstrap = AgentKitBootstrap(
            config: config,
            registry: registry,
            eventBus: eventBus,
            providerSelector: providerSelector,
            channelOrchestrator: orchestrator,
            session: session,
            tools: tools
        )

        logger.info("AgentKit initialized", metadata: [
            "agents": "\(config.defaultAgents.count)",
            "tools": "\(tools.count)"
        ])

        return bootstrap
    }

    // MARK: - Tool Creation

    private static func createDefaultTools(session: Session) -> [any Tool] {
        var tools: [any Tool] = []

        // Add built-in tools
        // These are safe, read-only tools that all agents can use
        // More dangerous tools (Write, Bash) should be added explicitly

        // Note: Actual tool instances would be created here
        // For now, return empty - tools will be added as they're implemented

        return tools
    }

    // MARK: - Runtime Management

    /// Register an additional agent at runtime
    public func registerAgent(_ agent: RegisteredAgent) async {
        await registry.register(agent)
        logger.info("Registered agent", metadata: ["name": "\(agent.name)"])
    }

    /// Add a tool to the default tool set
    public func addTool(_ tool: any Tool) {
        tools.append(tool)
        logger.info("Added tool", metadata: ["name": "\(tool.name)"])
    }

    /// Get provider status for UI display
    public func getProviderStatus() async -> [ProviderStatus] {
        await providerSelector.getProviderStatus()
    }

    /// Check if the system is ready (has available provider)
    public func isReady() async -> Bool {
        await providerSelector.hasAvailableProvider()
    }

    /// Shutdown and cleanup
    public func shutdown() async {
        logger.info("Shutting down AgentKit")
        // Cancel any active tasks, cleanup resources
    }
}

// MARK: - Convenience Extensions

extension AgentKitBootstrap {
    /// Quick setup for a channel with default concierge
    public func setupDefaultChannel(
        _ channelId: UUID,
        messageHandler: @escaping ChannelOrchestrator.MessageHandler
    ) async {
        let conciergeId = AgentID("concierge")
        await channelOrchestrator.setupSimpleChannel(
            channelId,
            agent: conciergeId,
            messageHandler: messageHandler
        )
    }

    /// Get list of available agent names for UI
    public func availableAgentNames() async -> [String] {
        await registry.agents.map(\.name)
    }
}
