import Foundation

// MARK: - Event Source Protocol

/// A source of trigger events that can wake agents.
///
/// Event sources are the "inputs" to the agent system. They watch for
/// external changes (files, time, messages, health data, etc.) and emit
/// events when something happens that agents might care about.
///
/// Built-in sources:
/// - `ScheduleEventSource`: Time-based triggers (cron-like)
/// - `FileWatchEventSource`: File system monitoring
/// - `AgentEventSource`: Inter-agent delegation events
/// - `A2AEventSource`: External agent messages
///
/// Custom sources can be created by conforming to this protocol.
/// Agents can request new sources via the Integrator agent profile.
public protocol EventSource: Actor {
    /// Unique identifier for this source (nonisolated for use outside actor)
    nonisolated var id: EventSourceID { get }

    /// Human-readable name
    nonisolated var name: String { get }

    /// Description of what this source monitors
    nonisolated var description: String { get }

    /// What types of events this source can emit
    var supportedEventTypes: Set<TriggerEventType> { get }

    /// Current state of the source
    var state: EventSourceState { get }

    /// Start monitoring and emitting events
    func start() async throws

    /// Stop monitoring
    func stop() async

    /// Stream of events from this source
    var events: AsyncStream<TriggerEvent> { get }
}

// MARK: - Event Source State

public enum EventSourceState: String, Sendable {
    case idle           // Not started
    case starting       // In process of starting
    case running        // Actively monitoring
    case paused         // Temporarily paused
    case stopped        // Stopped
    case error          // Error state
}

// MARK: - Event Source Configuration

/// Base configuration for event sources
public protocol EventSourceConfiguration: Sendable {
    var sourceId: EventSourceID { get }
    var enabled: Bool { get }
}

// MARK: - Schedule Event Source

/// Time-based event source using cron-like scheduling.
///
/// Examples:
/// - Daily at 9am: `0 9 * * *`
/// - Every Monday: `0 0 * * 1`
/// - Every 30 minutes: `*/30 * * * *`
public actor ScheduleEventSource: EventSource {
    public nonisolated let id: EventSourceID
    public nonisolated let name: String
    public nonisolated let description: String
    public let supportedEventTypes: Set<TriggerEventType> = [.scheduled, .reminder, .deadline]

    public private(set) var state: EventSourceState = .idle

    private var schedules: [ScheduleEntry] = []
    private var eventContinuation: AsyncStream<TriggerEvent>.Continuation?
    private var monitorTask: Task<Void, Never>?

    public var events: AsyncStream<TriggerEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    public init(id: EventSourceID = EventSourceID("schedule"), name: String = "Schedule") {
        self.id = id
        self.name = name
        self.description = "Time-based event triggers using cron-like scheduling"
    }

    // MARK: - Schedule Management

    /// Add a schedule
    public func addSchedule(_ entry: ScheduleEntry) {
        schedules.append(entry)
    }

    /// Remove a schedule
    public func removeSchedule(_ scheduleId: String) {
        schedules.removeAll { $0.id == scheduleId }
    }

    /// Get all schedules
    public var allSchedules: [ScheduleEntry] {
        schedules
    }

    // MARK: - EventSource Protocol

    public func start() async throws {
        guard state == .idle || state == .stopped else { return }
        state = .starting

        monitorTask = Task {
            state = .running

            while !Task.isCancelled && state == .running {
                let now = Date()

                for schedule in schedules where schedule.isEnabled {
                    if schedule.shouldFire(at: now) {
                        let event = TriggerEvent(
                            sourceId: id,
                            type: .scheduled,
                            payload: .schedule(SchedulePayload(
                                scheduleName: schedule.name,
                                scheduledTime: now,
                                recurrence: schedule.cronExpression,
                                context: schedule.context
                            )),
                            priority: schedule.priority
                        )
                        eventContinuation?.yield(event)
                    }
                }

                // Check every minute
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    public func stop() async {
        state = .stopped
        monitorTask?.cancel()
        monitorTask = nil
        eventContinuation?.finish()
    }
}

/// A scheduled trigger entry
public struct ScheduleEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let cronExpression: String?
    public let interval: Duration?
    public let priority: EventPriority
    public let context: [String: String]
    public var isEnabled: Bool

    private var lastFired: Date?

    public init(
        id: String = UUID().uuidString,
        name: String,
        cronExpression: String? = nil,
        interval: Duration? = nil,
        priority: EventPriority = .normal,
        context: [String: String] = [:],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.cronExpression = cronExpression
        self.interval = interval
        self.priority = priority
        self.context = context
        self.isEnabled = isEnabled
    }

    /// Check if this schedule should fire at the given time
    public func shouldFire(at date: Date) -> Bool {
        // Simple interval-based check (cron parsing would go here)
        if let interval = interval {
            if let last = lastFired {
                let intervalSeconds = Double(interval.components.seconds)
                return date.timeIntervalSince(last) >= intervalSeconds
            }
            return true
        }

        // TODO: Implement proper cron expression parsing
        return false
    }
}

// MARK: - File Watch Event Source

/// File system monitoring event source.
///
/// Watches directories for changes and emits events when files
/// are created, modified, deleted, or renamed.
public actor FileWatchEventSource: EventSource {
    public nonisolated let id: EventSourceID
    public nonisolated let name: String
    public nonisolated let description: String
    public let supportedEventTypes: Set<TriggerEventType> = [.fileChanged]

    public private(set) var state: EventSourceState = .idle

    private var watchedPaths: Set<String> = []
    private var eventContinuation: AsyncStream<TriggerEvent>.Continuation?
    private var monitorTask: Task<Void, Never>?

    public var events: AsyncStream<TriggerEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    public init(id: EventSourceID = EventSourceID("filewatch"), name: String = "File Watch") {
        self.id = id
        self.name = name
        self.description = "File system monitoring for directory changes"
    }

    /// Add a path to watch
    public func watch(_ path: String) {
        watchedPaths.insert(path)
    }

    /// Remove a path from watching
    public func unwatch(_ path: String) {
        watchedPaths.remove(path)
    }

    public func start() async throws {
        guard state == .idle || state == .stopped else { return }
        state = .starting

        // TODO: Implement using FSEvents or DispatchSource
        // For now, this is a placeholder that would use:
        // - FSEventStreamCreate on macOS
        // - DispatchSource.makeFileSystemObjectSource

        monitorTask = Task {
            state = .running
            // File monitoring loop would go here
            while !Task.isCancelled && state == .running {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func stop() async {
        state = .stopped
        monitorTask?.cancel()
        monitorTask = nil
        eventContinuation?.finish()
    }

    /// Manually emit a file change event (for testing or external notifications)
    public func emitChange(path: String, type: FileChangeType) {
        let event = TriggerEvent(
            sourceId: id,
            type: .fileChanged,
            payload: .fileChange(FileChangePayload(path: path, changeType: type))
        )
        eventContinuation?.yield(event)
    }
}

// MARK: - Agent Event Source

/// Event source for inter-agent communication.
///
/// Emits events when:
/// - Another agent requests help (delegation)
/// - A delegated task completes
/// - An agent needs a decision
public actor AgentEventSource: EventSource {
    public nonisolated let id: EventSourceID
    public nonisolated let name: String
    public nonisolated let description: String
    public let supportedEventTypes: Set<TriggerEventType> = [
        .delegationRequest,
        .delegationComplete,
        .decisionNeeded,
        .approvalReceived
    ]

    public private(set) var state: EventSourceState = .idle
    private var eventContinuation: AsyncStream<TriggerEvent>.Continuation?

    public var events: AsyncStream<TriggerEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    public init(id: EventSourceID = EventSourceID("agent"), name: String = "Agent Events") {
        self.id = id
        self.name = name
        self.description = "Inter-agent communication and delegation events"
    }

    public func start() async throws {
        state = .running
    }

    public func stop() async {
        state = .stopped
        eventContinuation?.finish()
    }

    /// Emit a delegation request event
    public func emitDelegationRequest(
        delegationId: UUID,
        fromAgent: AgentID,
        task: String,
        capabilities: [AgentCapability],
        urgency: EventPriority = .normal
    ) {
        let event = TriggerEvent(
            sourceId: id,
            type: .delegationRequest,
            payload: .delegation(DelegationPayload(
                delegationId: delegationId,
                fromAgent: fromAgent,
                task: task,
                requiredCapabilities: capabilities,
                urgency: urgency
            )),
            priority: urgency
        )
        eventContinuation?.yield(event)
    }

    /// Emit a decision received event
    public func emitDecisionReceived(
        cardId: DecisionCardID,
        decision: DecisionStatus,
        reviewer: String,
        comment: String? = nil
    ) {
        let event = TriggerEvent(
            sourceId: id,
            type: .approvalReceived,
            payload: .decision(DecisionPayload(
                cardId: cardId,
                decision: decision,
                reviewer: reviewer,
                comment: comment
            )),
            priority: .high
        )
        eventContinuation?.yield(event)
    }
}

// MARK: - Notification Event Source

/// Event source for external notifications (email, messages, webhooks).
///
/// This is typically connected to:
/// - Mail.app via AppleScript/automation
/// - Messages.app via AppleScript
/// - Webhook endpoints
/// - A2A protocol messages
public actor NotificationEventSource: EventSource {
    public nonisolated let id: EventSourceID
    public nonisolated let name: String
    public nonisolated let description: String
    public let supportedEventTypes: Set<TriggerEventType> = [
        .notification,
        .messageReceived,
        .mentionReceived
    ]

    public private(set) var state: EventSourceState = .idle
    private var eventContinuation: AsyncStream<TriggerEvent>.Continuation?

    public var events: AsyncStream<TriggerEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    public init(id: EventSourceID = EventSourceID("notification"), name: String = "Notifications") {
        self.id = id
        self.name = name
        self.description = "External notifications from email, messages, and webhooks"
    }

    public func start() async throws {
        state = .running
    }

    public func stop() async {
        state = .stopped
        eventContinuation?.finish()
    }

    /// Emit a message received event
    public func emitMessage(from: String, subject: String?, body: String, channel: MessageChannel) {
        let event = TriggerEvent(
            sourceId: id,
            type: .messageReceived,
            payload: .message(MessagePayload(
                from: from,
                subject: subject,
                body: body,
                channel: channel
            )),
            priority: .normal
        )
        eventContinuation?.yield(event)
    }

    /// Emit a notification event
    public func emitNotification(title: String, body: String, category: String? = nil, actionable: Bool = false) {
        let event = TriggerEvent(
            sourceId: id,
            type: .notification,
            payload: .notification(NotificationPayload(
                title: title,
                body: body,
                category: category,
                actionable: actionable
            ))
        )
        eventContinuation?.yield(event)
    }
}

// MARK: - Health Event Source

/// Event source for HealthKit data (for coaching agents).
///
/// Monitors health metrics and emits events for:
/// - Weight changes
/// - Activity completion
/// - Goal progress
/// - Sleep patterns
public actor HealthEventSource: EventSource {
    public nonisolated let id: EventSourceID
    public nonisolated let name: String
    public nonisolated let description: String
    public let supportedEventTypes: Set<TriggerEventType> = [
        .healthMetric,
        .activityCompleted,
        .goalProgress
    ]

    public private(set) var state: EventSourceState = .idle
    private var eventContinuation: AsyncStream<TriggerEvent>.Continuation?
    private var monitoredMetrics: Set<HealthMetricType> = []

    public var events: AsyncStream<TriggerEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    public init(id: EventSourceID = EventSourceID("health"), name: String = "Health") {
        self.id = id
        self.name = name
        self.description = "HealthKit metrics and activity monitoring"
    }

    /// Monitor a specific metric type
    public func monitor(_ metric: HealthMetricType) {
        monitoredMetrics.insert(metric)
    }

    public func start() async throws {
        state = .running
        // TODO: Connect to HealthKit
        // HKHealthStore.requestAuthorization
        // HKObserverQuery for monitored metrics
    }

    public func stop() async {
        state = .stopped
        eventContinuation?.finish()
    }

    /// Manually emit a health metric (for testing or external input)
    public func emitMetric(type: HealthMetricType, value: Double, unit: String, source: String? = nil) {
        let event = TriggerEvent(
            sourceId: id,
            type: .healthMetric,
            payload: .healthMetric(HealthMetricPayload(
                metricType: type,
                value: value,
                unit: unit,
                source: source
            ))
        )
        eventContinuation?.yield(event)
    }
}
