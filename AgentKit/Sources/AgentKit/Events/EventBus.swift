import Foundation
import Logging

// MARK: - Event Bus

/// Central hub for event routing between sources and agents.
///
/// The EventBus is the nervous system of AgentKit:
/// 1. Registers event sources (schedule, file watch, notifications, etc.)
/// 2. Manages agent subscriptions to event types
/// 3. Dispatches events to subscribed agents
/// 4. Wakes sleeping agents when their triggers fire
///
/// ```
/// ┌─────────────────────────────────────────────────────────────┐
/// │                        EventBus                              │
/// │  ┌────────────┐  ┌─────────────┐  ┌───────────────────┐    │
/// │  │  Sources   │  │Subscriptions│  │   Wake Controller │    │
/// │  │  Registry  │──│   Filter    │──│   (Agent Routing) │    │
/// │  └────────────┘  └─────────────┘  └───────────────────┘    │
/// └─────────────────────────────────────────────────────────────┘
///           ▲                                     │
///           │                                     ▼
///     ┌─────┴─────┐                        ┌──────────────┐
///     │  Sources  │                        │   Agents     │
///     │(Schedule, │                        │  (wake up)   │
///     │ FileWatch)│                        └──────────────┘
///     └───────────┘
/// ```
public actor EventBus {

    // MARK: - Properties

    /// Registered event sources
    private var sources: [EventSourceID: any EventSource] = [:]

    /// Active source listeners
    private var sourceListeners: [EventSourceID: Task<Void, Never>] = [:]

    /// Agent subscriptions: AgentID → EventFilter
    private var subscriptions: [AgentID: [EventSubscription]] = [:]

    /// Callback for waking agents
    private var wakeHandler: WakeHandler?

    /// Event history (for debugging and replay)
    private var eventHistory: [TriggerEvent] = []
    private let maxHistorySize: Int

    /// Integration request handler (for agents requesting new sources)
    private var integrationRequestHandler: IntegrationRequestHandler?

    private let logger = Logger(label: "AgentKit.EventBus")

    // MARK: - Types

    /// Handler called when an agent should wake up
    public typealias WakeHandler = @Sendable (AgentID, TriggerEvent) async -> Void

    /// Handler for integration requests (create new event sources)
    public typealias IntegrationRequestHandler = @Sendable (IntegrationRequest) async -> Bool

    // MARK: - Initialization

    public init(maxHistorySize: Int = 1000) {
        self.maxHistorySize = maxHistorySize
    }

    // MARK: - Configuration

    /// Set the handler for waking agents
    public func setWakeHandler(_ handler: @escaping WakeHandler) {
        self.wakeHandler = handler
    }

    /// Set the handler for integration requests
    public func setIntegrationRequestHandler(_ handler: @escaping IntegrationRequestHandler) {
        self.integrationRequestHandler = handler
    }

    // MARK: - Source Management

    /// Register an event source
    public func register<S: EventSource>(_ source: S) async throws {
        sources[source.id] = source

        // Start listening to the source's events
        let listener = Task {
            for await event in await source.events {
                await dispatch(event)
            }
        }
        sourceListeners[source.id] = listener

        // Start the source
        try await source.start()

        logger.info("Registered event source", metadata: [
            "id": "\(source.id)",
            "name": "\(source.name)"
        ])
    }

    /// Unregister an event source
    public func unregister(_ sourceId: EventSourceID) async {
        if let source = sources.removeValue(forKey: sourceId) {
            await source.stop()
        }
        sourceListeners[sourceId]?.cancel()
        sourceListeners.removeValue(forKey: sourceId)

        logger.info("Unregistered event source", metadata: ["id": "\(sourceId)"])
    }

    /// Get a registered source
    public func source(_ id: EventSourceID) -> (any EventSource)? {
        sources[id]
    }

    /// Get all registered sources
    public var allSources: [any EventSource] {
        Array(sources.values)
    }

    // MARK: - Subscription Management

    /// Subscribe an agent to specific event types
    public func subscribe(
        _ agentId: AgentID,
        to filter: EventFilter,
        priority: SubscriptionPriority = .normal
    ) {
        let subscription = EventSubscription(
            agentId: agentId,
            filter: filter,
            priority: priority
        )

        if subscriptions[agentId] == nil {
            subscriptions[agentId] = []
        }
        subscriptions[agentId]?.append(subscription)

        logger.debug("Agent subscribed", metadata: [
            "agent": "\(agentId)",
            "filter": "\(filter)"
        ])
    }

    /// Unsubscribe an agent from all events
    public func unsubscribeAll(_ agentId: AgentID) {
        subscriptions.removeValue(forKey: agentId)
        logger.debug("Agent unsubscribed from all", metadata: ["agent": "\(agentId)"])
    }

    /// Unsubscribe an agent from specific event types
    public func unsubscribe(_ agentId: AgentID, from eventTypes: Set<TriggerEventType>) {
        subscriptions[agentId]?.removeAll { sub in
            sub.filter.matchesAny(eventTypes)
        }
    }

    /// Get all subscriptions for an agent
    public func subscriptions(for agentId: AgentID) -> [EventSubscription] {
        subscriptions[agentId] ?? []
    }

    // MARK: - Event Dispatch

    /// Dispatch an event to all subscribed agents
    public func dispatch(_ event: TriggerEvent) async {
        // Add to history
        eventHistory.append(event)
        if eventHistory.count > maxHistorySize {
            eventHistory.removeFirst()
        }

        logger.debug("Dispatching event", metadata: [
            "id": "\(event.id)",
            "type": "\(event.type.rawValue)",
            "source": "\(event.sourceId)"
        ])

        // Find matching subscriptions
        var matchingAgents: [(AgentID, SubscriptionPriority)] = []

        for (agentId, subs) in subscriptions {
            for sub in subs {
                if sub.filter.matches(event) {
                    matchingAgents.append((agentId, sub.priority))
                    break  // Don't double-notify same agent
                }
            }
        }

        // Sort by priority (higher first)
        matchingAgents.sort { $0.1.rawValue > $1.1.rawValue }

        // Wake agents
        guard let wakeHandler = wakeHandler else {
            logger.warning("No wake handler configured, events will not wake agents")
            return
        }

        for (agentId, _) in matchingAgents {
            logger.info("Waking agent", metadata: [
                "agent": "\(agentId)",
                "event": "\(event.type.rawValue)"
            ])
            await wakeHandler(agentId, event)
        }
    }

    /// Manually emit an event (for testing or external integrations)
    public func emit(_ event: TriggerEvent) async {
        await dispatch(event)
    }

    // MARK: - Integration Requests

    /// Request a new event source integration (sent to Integrator agent)
    public func requestIntegration(_ request: IntegrationRequest) async -> Bool {
        guard let handler = integrationRequestHandler else {
            logger.warning("No integration request handler configured")
            return false
        }

        logger.info("Integration requested", metadata: [
            "type": "\(request.sourceType)",
            "from": "\(request.requestingAgent)"
        ])

        return await handler(request)
    }

    // MARK: - History

    /// Get recent events
    public func recentEvents(limit: Int = 100) -> [TriggerEvent] {
        Array(eventHistory.suffix(limit))
    }

    /// Get events of a specific type
    public func events(ofType type: TriggerEventType, limit: Int = 100) -> [TriggerEvent] {
        eventHistory.filter { $0.type == type }.suffix(limit).reversed()
    }

    /// Clear event history
    public func clearHistory() {
        eventHistory.removeAll()
    }

    // MARK: - Lifecycle

    /// Start all registered sources
    public func startAll() async {
        for source in sources.values {
            do {
                try await source.start()
            } catch {
                logger.error("Failed to start source", metadata: [
                    "id": "\(source.id)",
                    "error": "\(error)"
                ])
            }
        }
    }

    /// Stop all sources
    public func stopAll() async {
        for source in sources.values {
            await source.stop()
        }
        for task in sourceListeners.values {
            task.cancel()
        }
        sourceListeners.removeAll()
    }
}

// MARK: - Event Subscription

/// A subscription linking an agent to an event filter
public struct EventSubscription: Sendable {
    public let id: UUID
    public let agentId: AgentID
    public let filter: EventFilter
    public let priority: SubscriptionPriority
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        agentId: AgentID,
        filter: EventFilter,
        priority: SubscriptionPriority = .normal
    ) {
        self.id = id
        self.agentId = agentId
        self.filter = filter
        self.priority = priority
        self.createdAt = Date()
    }
}

/// Priority for subscription processing
public enum SubscriptionPriority: Int, Sendable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    public static func < (lhs: SubscriptionPriority, rhs: SubscriptionPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Event Filter

/// Filter for matching events to subscriptions
public struct EventFilter: Sendable, CustomStringConvertible {
    public let eventTypes: Set<TriggerEventType>?
    public let sourceIds: Set<EventSourceID>?
    public let minPriority: EventPriority?
    public let metadataMatch: [String: String]?

    public init(
        eventTypes: Set<TriggerEventType>? = nil,
        sourceIds: Set<EventSourceID>? = nil,
        minPriority: EventPriority? = nil,
        metadataMatch: [String: String]? = nil
    ) {
        self.eventTypes = eventTypes
        self.sourceIds = sourceIds
        self.minPriority = minPriority
        self.metadataMatch = metadataMatch
    }

    /// Check if an event matches this filter
    public func matches(_ event: TriggerEvent) -> Bool {
        // Check event type
        if let types = eventTypes, !types.contains(event.type) {
            return false
        }

        // Check source
        if let sources = sourceIds, !sources.contains(event.sourceId) {
            return false
        }

        // Check priority
        if let minPri = minPriority, event.priority < minPri {
            return false
        }

        // Check metadata
        if let required = metadataMatch {
            for (key, value) in required {
                if event.metadata[key] != value {
                    return false
                }
            }
        }

        return true
    }

    /// Check if this filter matches any of the given event types
    public func matchesAny(_ types: Set<TriggerEventType>) -> Bool {
        guard let filterTypes = eventTypes else { return true }
        return !filterTypes.isDisjoint(with: types)
    }

    public var description: String {
        var parts: [String] = []
        if let types = eventTypes {
            parts.append("types: \(types.map { $0.rawValue }.joined(separator: ", "))")
        }
        if let sources = sourceIds {
            parts.append("sources: \(sources.map { $0.rawValue }.joined(separator: ", "))")
        }
        if let pri = minPriority {
            parts.append("minPriority: \(pri)")
        }
        return "EventFilter(\(parts.joined(separator: "; ")))"
    }

    // MARK: - Convenience Factories

    /// Filter for all events of specific types
    public static func types(_ types: TriggerEventType...) -> EventFilter {
        EventFilter(eventTypes: Set(types))
    }

    /// Filter for events from specific sources
    public static func sources(_ ids: EventSourceID...) -> EventFilter {
        EventFilter(sourceIds: Set(ids))
    }

    /// Filter for high priority events only
    public static var highPriority: EventFilter {
        EventFilter(minPriority: .high)
    }

    /// Filter that matches all events
    public static var all: EventFilter {
        EventFilter()
    }
}

// MARK: - Integration Request

/// Request from an agent to add a new event source integration
public struct IntegrationRequest: Sendable {
    public let id: UUID
    public let requestingAgent: AgentID
    public let sourceType: RequestedSourceType
    public let configuration: [String: String]
    public let reason: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        requestingAgent: AgentID,
        sourceType: RequestedSourceType,
        configuration: [String: String] = [:],
        reason: String
    ) {
        self.id = id
        self.requestingAgent = requestingAgent
        self.sourceType = sourceType
        self.configuration = configuration
        self.reason = reason
        self.timestamp = Date()
    }
}

/// Types of event sources that can be requested
public enum RequestedSourceType: String, Sendable {
    case email          // Email monitoring
    case calendar       // Calendar events
    case reminders      // Apple Reminders
    case webhook        // Custom webhook
    case rss            // RSS feed
    case api            // External API polling
    case healthKit      // HealthKit metrics
    case homeKit        // HomeKit device events
    case shortcuts      // Shortcuts automation
    case custom         // Custom integration
}

// MARK: - Convenience Extensions

extension EventBus {
    /// Subscribe an agent to specific event types (convenience)
    public func subscribe(_ agentId: AgentID, to types: TriggerEventType...) {
        subscribe(agentId, to: .types(types.first!, types.dropFirst().map { $0 }.first ?? types.first!))
    }

    /// Create standard event sources
    public func createStandardSources() async throws {
        // Schedule source
        let schedule = ScheduleEventSource()
        try await register(schedule)

        // File watch source
        let fileWatch = FileWatchEventSource()
        try await register(fileWatch)

        // Agent events source
        let agentEvents = AgentEventSource()
        try await register(agentEvents)

        // Notification source
        let notifications = NotificationEventSource()
        try await register(notifications)

        logger.info("Created standard event sources")
    }
}
