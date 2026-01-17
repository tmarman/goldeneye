import Foundation
import Logging

// MARK: - Channel Orchestrator

/// Orchestrates message routing between channels and agents.
///
/// The ChannelOrchestrator is the bridge between the UI (channels) and the agent
/// execution layer. When a user posts a message to a channel, the orchestrator:
///
/// 1. **Parses** the message for @mentions and determines target agents
/// 2. **Dispatches** tasks to those agents (via AgentLoop or DelegationManager)
/// 3. **Streams** agent responses back to the channel
/// 4. **Posts** final responses as ChannelMessages
///
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │                    ChannelOrchestrator                           │
/// │                                                                  │
/// │  User Message ──► Parse Mentions ──► Select Agents              │
/// │                                           │                      │
/// │                                           ▼                      │
/// │                                    ┌─────────────┐              │
/// │                                    │ AgentLoop   │              │
/// │                                    │ (execute)   │              │
/// │                                    └──────┬──────┘              │
/// │                                           │                      │
/// │  Channel UI ◄── Post Response ◄── Stream Events                 │
/// └─────────────────────────────────────────────────────────────────┘
/// ```
public actor ChannelOrchestrator {

    // MARK: - Properties

    /// Registry of available agents
    private let registry: AgentRegistry

    /// Event bus for dispatching channel events
    private let eventBus: EventBus

    /// Factory to create agent instances
    private let agentFactory: AgentFactory

    /// Provider selector for LLM access
    private let providerSelector: ProviderSelector

    /// Default tools available to all agents
    private let defaultTools: [any Tool]

    /// Active tasks per channel (channelId -> [taskId: stream])
    private var activeTasks: [UUID: [TaskID: Task<Void, Never>]] = [:]

    /// Message handlers (for posting responses back to channels)
    private var messageHandlers: [UUID: MessageHandler] = [:]

    /// Channel configurations (which agents listen to which channels)
    private var channelAgents: [UUID: ChannelAgentConfig] = [:]

    /// Shared session for agent execution
    private let session: Session

    private let logger = Logger(label: "AgentKit.ChannelOrchestrator")

    // MARK: - Types

    /// Factory to create agent instances from configuration
    public typealias AgentFactory = @Sendable (AgentID, AgentConfiguration) async throws -> any Agent

    /// Handler for posting messages back to a channel
    public typealias MessageHandler = @Sendable (ChannelMessage) async -> Void

    /// Handler for streaming events (tool calls, deltas, etc.)
    public typealias StreamHandler = @Sendable (AgentEvent, UUID) async -> Void

    // MARK: - Initialization

    public init(
        registry: AgentRegistry,
        eventBus: EventBus,
        session: Session,
        providerSelector: ProviderSelector = ProviderSelector.localOnly(),
        defaultTools: [any Tool] = [],
        agentFactory: @escaping AgentFactory
    ) {
        self.registry = registry
        self.eventBus = eventBus
        self.session = session
        self.providerSelector = providerSelector
        self.defaultTools = defaultTools
        self.agentFactory = agentFactory
    }

    // MARK: - Configuration

    /// Configure which agents participate in a channel
    public func configureChannel(
        _ channelId: UUID,
        agents: [AgentID],
        alwaysRespond: [AgentID] = [],
        mentionOnly: [AgentID] = []
    ) {
        channelAgents[channelId] = ChannelAgentConfig(
            channelId: channelId,
            allAgents: Set(agents),
            alwaysRespond: Set(alwaysRespond),
            mentionOnly: Set(mentionOnly)
        )

        logger.info("Configured channel", metadata: [
            "channelId": "\(channelId)",
            "agents": "\(agents.count)",
            "alwaysRespond": "\(alwaysRespond.count)"
        ])
    }

    /// Set the handler for posting messages back to a channel
    public func setMessageHandler(for channelId: UUID, handler: @escaping MessageHandler) {
        messageHandlers[channelId] = handler
    }

    // MARK: - Message Handling

    /// Handle a new message in a channel
    ///
    /// This is the main entry point. When a user posts a message:
    /// 1. Parse @mentions to find explicitly targeted agents
    /// 2. Add any "always respond" agents for this channel
    /// 3. Dispatch tasks to each target agent
    /// 4. Stream responses back to the channel
    public func handleMessage(
        _ message: ChannelMessage,
        in channel: Channel,
        streamHandler: StreamHandler? = nil
    ) async {
        logger.info("Handling message", metadata: [
            "channelId": "\(channel.id)",
            "messageId": "\(message.id)",
            "mentions": "\(message.mentions)"
        ])

        // Determine which agents should respond
        let targetAgents = await selectTargetAgents(
            for: message,
            in: channel
        )

        guard !targetAgents.isEmpty else {
            logger.debug("No agents selected to respond")
            return
        }

        logger.info("Dispatching to agents", metadata: [
            "count": "\(targetAgents.count)",
            "agents": "\(targetAgents.map { $0.rawValue })"
        ])

        // Dispatch to each agent
        for agentId in targetAgents {
            await dispatchToAgent(
                agentId: agentId,
                message: message,
                channel: channel,
                streamHandler: streamHandler
            )
        }
    }

    // MARK: - Agent Selection

    /// Select which agents should respond to a message
    private func selectTargetAgents(
        for message: ChannelMessage,
        in channel: Channel
    ) async -> [AgentID] {
        var targets: Set<AgentID> = []

        // 1. Add explicitly @mentioned agents
        let mentionedAgents = parseMentions(message.content)
        for mention in mentionedAgents {
            targets.insert(AgentID(mention))
        }

        // Also check the pre-parsed mentions array
        for mention in message.mentions {
            targets.insert(AgentID(mention))
        }

        // 2. Add "always respond" agents for this channel
        if let config = channelAgents[message.channelId] {
            targets.formUnion(config.alwaysRespond)
        }

        // 3. If still no targets and channel has a default agent, use that
        if targets.isEmpty, let config = channelAgents[message.channelId] {
            // Fall back to first available agent in channel
            if let defaultAgent = config.allAgents.first {
                targets.insert(defaultAgent)
            }
        }

        // 4. Filter to only available agents
        var availableTargets: [AgentID] = []
        for agentId in targets {
            if let agent = await registry.agent(agentId),
               agent.status.canAcceptTasks {
                availableTargets.append(agentId)
            } else {
                logger.warning("Agent not available", metadata: ["agentId": "\(agentId)"])
            }
        }

        return availableTargets
    }

    /// Parse @mentions from message content
    ///
    /// Supports formats:
    /// - @agent-name
    /// - @AgentName
    /// - @agent_name
    private func parseMentions(_ content: String) -> [String] {
        let pattern = #"@([\w-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)

        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: content) else {
                return nil
            }
            return String(content[range])
        }
    }

    // MARK: - Task Dispatch

    /// Dispatch a message to a specific agent
    private func dispatchToAgent(
        agentId: AgentID,
        message: ChannelMessage,
        channel: Channel,
        streamHandler: StreamHandler?
    ) async {
        // Get agent configuration from registry
        guard let registeredAgent = await registry.agent(agentId) else {
            logger.error("Agent not found in registry", metadata: ["agentId": "\(agentId)"])
            return
        }

        // Select the best available LLM provider
        guard let provider = await providerSelector.selectProvider() else {
            logger.error("No LLM provider available")
            await postSystemMessage(
                "No LLM provider available. Please ensure Ollama is running or Apple Intelligence is enabled.",
                to: channel.id
            )
            return
        }

        // Get or create the agent instance
        let agent: any Agent
        do {
            // Check if agent has a local endpoint
            if case .local(let localAgent) = registeredAgent.endpoint {
                agent = localAgent
            } else {
                // Create new agent via factory with real provider
                let config = createAgentConfiguration(for: registeredAgent, channel: channel, provider: provider)
                agent = try await agentFactory(agentId, config)
            }
        } catch {
            logger.error("Failed to create agent", metadata: [
                "agentId": "\(agentId)",
                "error": "\(error)"
            ])
            return
        }

        // Create the task
        let agentTask = AgentTask(
            contextId: ContextID(channel.id.uuidString),
            message: Message(
                role: .user,
                content: .text(message.content)
            )
        )

        // Mark agent as busy
        await registry.update(agentId, with: RegistryUpdate(status: .busy))

        // Execute and stream results
        let task = Task {
            var accumulatedText = ""

            do {
                for try await event in await agent.execute(agentTask) {
                    // Forward events to stream handler
                    await streamHandler?(event, channel.id)

                    // Handle specific events
                    switch event {
                    case .textDelta(let delta):
                        accumulatedText += delta.delta

                    case .message(let responseMessage):
                        // Post complete message to channel
                        await postAgentResponse(
                            responseMessage,
                            from: agentId,
                            to: channel.id,
                            threadId: message.threadId
                        )

                    case .completed(let completed):
                        // If we accumulated text but didn't get a message event, post it
                        if !accumulatedText.isEmpty, completed.result == nil {
                            let finalMessage = Message(role: .assistant, content: .text(accumulatedText))
                            await postAgentResponse(
                                finalMessage,
                                from: agentId,
                                to: channel.id,
                                threadId: message.threadId
                            )
                        }

                        logger.info("Agent task completed", metadata: [
                            "agentId": "\(agentId)",
                            "taskId": "\(agentTask.id)",
                            "duration": "\(completed.duration)"
                        ])

                    case .failed(let failed):
                        logger.error("Agent task failed", metadata: [
                            "agentId": "\(agentId)",
                            "error": "\(failed.error)"
                        ])

                        // Post error message to channel
                        await postSystemMessage(
                            "Agent \(registeredAgent.name) encountered an error: \(failed.error)",
                            to: channel.id
                        )

                    case .toolCall(let toolCall):
                        logger.debug("Tool call", metadata: [
                            "tool": "\(toolCall.toolName)",
                            "agentId": "\(agentId)"
                        ])

                    default:
                        break
                    }
                }
            } catch {
                logger.error("Agent execution error", metadata: [
                    "agentId": "\(agentId)",
                    "error": "\(error)"
                ])
            }

            // Mark agent as available again
            await registry.update(agentId, with: RegistryUpdate(status: .available))

            // Remove from active tasks
            removeActiveTask(agentTask.id, from: channel.id)
        }

        // Track active task
        trackActiveTask(task, id: agentTask.id, channelId: channel.id)
    }

    // MARK: - Response Posting

    /// Post an agent response back to the channel
    private func postAgentResponse(
        _ message: Message,
        from agentId: AgentID,
        to channelId: UUID,
        threadId: UUID?
    ) async {
        let channelMessage = ChannelMessage.from(
            message: message,
            channelId: channelId,
            threadId: threadId,
            senderId: agentId.rawValue
        )

        // Call the message handler if registered
        if let handler = messageHandlers[channelId] {
            await handler(channelMessage)
        }

        // Also emit to event bus for other subscribers
        let event = TriggerEvent(
            sourceId: EventSourceID("channel-orchestrator"),
            type: .custom,
            payload: .message(MessagePayload(
                from: agentId.rawValue,
                subject: nil,
                body: message.textContent,
                channel: .internal_
            )),
            metadata: [
                "eventType": "agent.response",
                "channelId": channelId.uuidString,
                "agentId": agentId.rawValue
            ]
        )
        await eventBus.emit(event)
    }

    /// Post a system message to the channel
    private func postSystemMessage(_ content: String, to channelId: UUID) async {
        let message = ChannelMessage(
            channelId: channelId,
            senderId: "system",
            role: "system",
            content: content,
            type: .system
        )

        if let handler = messageHandlers[channelId] {
            await handler(message)
        }
    }

    // MARK: - Agent Configuration

    /// Create agent configuration from registered agent info
    private func createAgentConfiguration(
        for agent: RegisteredAgent,
        channel: Channel,
        provider: any LLMProvider
    ) -> AgentConfiguration {
        // Build system prompt based on agent profile
        let systemPrompt = buildSystemPrompt(for: agent, channel: channel)

        // Use injected provider and default tools
        let config = AgentConfiguration(
            name: agent.name,
            systemPrompt: systemPrompt,
            tools: defaultTools,
            llmProvider: provider,
            maxIterations: 10
        )

        return config
    }

    /// Build a system prompt for an agent based on its profile
    private func buildSystemPrompt(for agent: RegisteredAgent, channel: Channel) -> String {
        var prompt = """
        You are \(agent.name), a \(agent.profile.displayName) agent.

        You are participating in the channel "#\(channel.name)".
        """

        if let description = channel.metadata.description {
            prompt += "\n\nChannel description: \(description)"
        }

        if let topic = channel.metadata.topic {
            prompt += "\nCurrent topic: \(topic)"
        }

        // Add profile-specific instructions
        switch agent.profile {
        case .concierge:
            prompt += "\n\nAs a Concierge, help route requests to the right agents and provide helpful responses."
        case .librarian:
            prompt += "\n\nAs a Librarian, focus on research, finding information, and organizing knowledge."
        case .critic:
            prompt += "\n\nAs a Critic, provide constructive feedback and quality assurance."
        case .executor:
            prompt += "\n\nAs an Executor, focus on getting tasks done efficiently."
        case .coach:
            prompt += "\n\nAs a Coach, provide guidance and help users improve."
        default:
            break
        }

        return prompt
    }

    // MARK: - Task Management

    private func trackActiveTask(_ task: Task<Void, Never>, id: TaskID, channelId: UUID) {
        if activeTasks[channelId] == nil {
            activeTasks[channelId] = [:]
        }
        activeTasks[channelId]?[id] = task
    }

    private func removeActiveTask(_ id: TaskID, from channelId: UUID) {
        activeTasks[channelId]?.removeValue(forKey: id)
    }

    /// Cancel all active tasks in a channel
    public func cancelAllTasks(in channelId: UUID) {
        guard let tasks = activeTasks[channelId] else { return }

        for (_, task) in tasks {
            task.cancel()
        }
        activeTasks[channelId] = nil

        logger.info("Cancelled all tasks", metadata: ["channelId": "\(channelId)"])
    }

    /// Get count of active tasks
    public var activeTaskCount: Int {
        activeTasks.values.reduce(0) { $0 + $1.count }
    }
}

// MARK: - Channel Agent Configuration

/// Configuration for which agents participate in a channel
public struct ChannelAgentConfig: Sendable {
    public let channelId: UUID

    /// All agents that can participate in this channel
    public let allAgents: Set<AgentID>

    /// Agents that respond to every message (no @mention needed)
    public let alwaysRespond: Set<AgentID>

    /// Agents that only respond when explicitly @mentioned
    public let mentionOnly: Set<AgentID>

    public init(
        channelId: UUID,
        allAgents: Set<AgentID>,
        alwaysRespond: Set<AgentID> = [],
        mentionOnly: Set<AgentID> = []
    ) {
        self.channelId = channelId
        self.allAgents = allAgents
        self.alwaysRespond = alwaysRespond
        self.mentionOnly = mentionOnly
    }
}


// MARK: - Convenience Extensions

extension ChannelOrchestrator {
    /// Quick setup for a channel with a single always-responding agent
    public func setupSimpleChannel(
        _ channelId: UUID,
        agent: AgentID,
        messageHandler: @escaping MessageHandler
    ) {
        configureChannel(channelId, agents: [agent], alwaysRespond: [agent])
        setMessageHandler(for: channelId, handler: messageHandler)
    }

    /// Setup a channel where agents only respond to @mentions
    public func setupMentionOnlyChannel(
        _ channelId: UUID,
        agents: [AgentID],
        messageHandler: @escaping MessageHandler
    ) {
        configureChannel(channelId, agents: agents, mentionOnly: agents)
        setMessageHandler(for: channelId, handler: messageHandler)
    }
}
