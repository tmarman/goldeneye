import Foundation
import Logging

// MARK: - Agent Wake Controller

/// Controls agent wake-up in response to events.
///
/// The WakeController sits between the EventBus and agents:
/// 1. Receives events from the EventBus
/// 2. Determines which agents should handle them
/// 3. Wakes sleeping agents or queues events for busy agents
/// 4. Creates tasks for agents to process events
///
/// This enables the "reactive" agent pattern where agents sleep until
/// triggered by external events (email, time, file changes, etc.)
public actor AgentWakeController {

    // MARK: - Properties

    private let eventBus: EventBus
    private let registry: AgentRegistry
    private let delegationManager: AgentDelegationManager

    /// Queue of events waiting for busy agents
    private var pendingEvents: [AgentID: [TriggerEvent]] = [:]

    /// Currently processing events per agent
    private var processingEvents: [AgentID: TriggerEvent] = [:]

    /// Agent wake callbacks
    private var wakeCallbacks: [AgentID: WakeCallback] = [:]

    private let logger = Logger(label: "AgentKit.WakeController")

    // MARK: - Types

    /// Callback when an agent is woken
    public typealias WakeCallback = @Sendable (TriggerEvent) async -> Void

    // MARK: - Initialization

    public init(
        eventBus: EventBus,
        registry: AgentRegistry,
        delegationManager: AgentDelegationManager
    ) {
        self.eventBus = eventBus
        self.registry = registry
        self.delegationManager = delegationManager
    }

    /// Connect to the event bus
    public func connect() async {
        await eventBus.setWakeHandler { [weak self] agentId, event in
            await self?.handleWakeRequest(agentId: agentId, event: event)
        }

        logger.info("Wake controller connected to event bus")
    }

    // MARK: - Wake Callbacks

    /// Register a wake callback for an agent
    public func registerWakeCallback(_ agentId: AgentID, callback: @escaping WakeCallback) {
        wakeCallbacks[agentId] = callback
        logger.debug("Registered wake callback", metadata: ["agent": "\(agentId)"])
    }

    /// Unregister a wake callback
    public func unregisterWakeCallback(_ agentId: AgentID) {
        wakeCallbacks.removeValue(forKey: agentId)
    }

    // MARK: - Event Handling

    /// Handle a wake request from the event bus
    private func handleWakeRequest(agentId: AgentID, event: TriggerEvent) async {
        // Check if agent exists and is available
        guard let agent = await registry.agent(agentId) else {
            logger.warning("Wake requested for unknown agent", metadata: ["agent": "\(agentId)"])
            return
        }

        switch agent.status {
        case .available:
            // Agent is ready, wake immediately
            await wakeAgent(agentId, with: event)

        case .busy:
            // Agent is busy, queue the event
            queueEvent(event, for: agentId)
            logger.debug("Queued event for busy agent", metadata: [
                "agent": "\(agentId)",
                "event": "\(event.id)"
            ])

        case .offline, .maintenance:
            // Agent is offline, try to find alternative
            await handleOfflineAgent(agentId, event: event)
        }
    }

    /// Wake an agent with an event
    private func wakeAgent(_ agentId: AgentID, with event: TriggerEvent) async {
        processingEvents[agentId] = event

        // Update agent status
        await registry.update(agentId, with: RegistryUpdate(status: .busy))

        logger.info("Waking agent", metadata: [
            "agent": "\(agentId)",
            "event": "\(event.type.rawValue)",
            "priority": "\(event.priority)"
        ])

        // Call the wake callback
        if let callback = wakeCallbacks[agentId] {
            await callback(event)
        }
    }

    /// Queue an event for a busy agent
    private func queueEvent(_ event: TriggerEvent, for agentId: AgentID) {
        if pendingEvents[agentId] == nil {
            pendingEvents[agentId] = []
        }

        // Insert by priority (higher priority first)
        if let index = pendingEvents[agentId]?.firstIndex(where: { $0.priority < event.priority }) {
            pendingEvents[agentId]?.insert(event, at: index)
        } else {
            pendingEvents[agentId]?.append(event)
        }
    }

    /// Handle event for an offline agent
    private func handleOfflineAgent(_ agentId: AgentID, event: TriggerEvent) async {
        // Try to find an alternative agent with similar capabilities
        if let agent = await registry.agent(agentId) {
            let alternatives = await registry.agents(withProfile: agent.profile)
                .filter { $0.status == .available && $0.id != agentId }

            if let alternative = alternatives.first {
                logger.info("Routing to alternative agent", metadata: [
                    "original": "\(agentId)",
                    "alternative": "\(alternative.id)"
                ])
                await wakeAgent(alternative.id, with: event)
                return
            }
        }

        // No alternative, queue for when agent comes back
        queueEvent(event, for: agentId)
        logger.warning("No alternative agent available, queued event", metadata: [
            "agent": "\(agentId)",
            "event": "\(event.id)"
        ])
    }

    // MARK: - Completion

    /// Mark an agent as done processing an event
    public func markEventProcessed(_ agentId: AgentID) async {
        processingEvents.removeValue(forKey: agentId)

        // Check for queued events
        if let nextEvent = pendingEvents[agentId]?.first {
            pendingEvents[agentId]?.removeFirst()
            await wakeAgent(agentId, with: nextEvent)
        } else {
            // No more events, mark agent as available
            await registry.update(agentId, with: RegistryUpdate(status: .available))
        }
    }

    // MARK: - Queries

    /// Get pending events for an agent
    public func pendingEvents(for agentId: AgentID) -> [TriggerEvent] {
        pendingEvents[agentId] ?? []
    }

    /// Get the event an agent is currently processing
    public func currentEvent(for agentId: AgentID) -> TriggerEvent? {
        processingEvents[agentId]
    }

    /// Get all agents with pending events
    public var agentsWithPendingEvents: [AgentID] {
        pendingEvents.keys.filter { !(pendingEvents[$0]?.isEmpty ?? true) }
    }

    /// Get total pending event count
    public var totalPendingEvents: Int {
        pendingEvents.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - Event Routing Helpers

    /// Route an event to the best available agent based on capabilities
    public func routeToCapableAgent(
        event: TriggerEvent,
        requiredCapabilities: [AgentCapability]
    ) async -> AgentID? {
        guard let agent = await registry.findBestAgent(for: requiredCapabilities) else {
            logger.warning("No capable agent found", metadata: [
                "capabilities": "\(requiredCapabilities.map { $0.rawValue })"
            ])
            return nil
        }

        await handleWakeRequest(agentId: agent.id, event: event)
        return agent.id
    }

    /// Route an event to the Concierge (default router)
    public func routeToConcierge(event: TriggerEvent) async {
        let concierges = await registry.agents(withProfile: .concierge)
        if let concierge = concierges.first(where: { $0.status == .available }) ?? concierges.first {
            await handleWakeRequest(agentId: concierge.id, event: event)
        } else {
            logger.error("No Concierge agent registered")
        }
    }
}

// MARK: - Convenience Extensions

extension AgentWakeController {
    /// Setup standard event subscriptions for agent profiles
    public func setupStandardSubscriptions() async {
        let agents = await registry.agents

        for agent in agents {
            let filter = Self.defaultFilter(for: agent.profile)
            await eventBus.subscribe(agent.id, to: filter)
        }

        logger.info("Setup standard subscriptions for \(agents.count) agents")
    }

    /// Get default event filter for an agent profile
    public static func defaultFilter(for profile: AgentProfile) -> EventFilter {
        switch profile {
        case .concierge:
            // Concierge handles all incoming communications
            return EventFilter(eventTypes: [
                .notification,
                .messageReceived,
                .mentionReceived,
                .delegationRequest
            ])

        case .librarian:
            // Librarian handles document and file changes
            return EventFilter(eventTypes: [
                .fileChanged,
                .documentUpdated,
                .dataSync
            ])

        case .weaver:
            // Weaver handles pattern-related events
            return EventFilter(eventTypes: [
                .documentUpdated,
                .dataSync
            ])

        case .executor:
            // Executor handles scheduled tasks and deadlines
            return EventFilter(eventTypes: [
                .scheduled,
                .deadline,
                .delegationRequest
            ])

        case .coach:
            // Coach handles health metrics and reminders
            return EventFilter(eventTypes: [
                .healthMetric,
                .activityCompleted,
                .goalProgress,
                .scheduled,
                .reminder
            ])

        case .critic:
            // Critic handles review requests
            return EventFilter(eventTypes: [
                .decisionNeeded,
                .documentUpdated
            ])

        case .integrator:
            // Integrator handles system events and integration requests
            return EventFilter(eventTypes: [
                .systemStartup,
                .integrationEvent,
                .errorOccurred
            ])

        case .guardian:
            // Guardian handles security-related events
            return EventFilter(eventTypes: [
                .errorOccurred,
                .systemStartup,
                .systemShutdown
            ], minPriority: .high)

        case .founder:
            // Founders get events for their owned spaces
            return EventFilter(eventTypes: [
                .documentUpdated,
                .decisionNeeded,
                .delegationRequest
            ])
        }
    }
}

// MARK: - Event-Driven Agent Protocol

/// Protocol for agents that can be woken by events
public protocol EventDrivenAgent: Agent {
    /// Process a trigger event
    func process(_ event: TriggerEvent) async throws

    /// Event types this agent handles
    var subscribedEventTypes: Set<TriggerEventType> { get }
}

extension EventDrivenAgent {
    /// Default implementation returns empty set (manual subscription)
    public var subscribedEventTypes: Set<TriggerEventType> { [] }
}
