import Foundation

// MARK: - Agent Scheduler

/// The Scheduler is like cron for agents - it triggers agent tasks based on
/// time patterns, events, or conditions.
public actor AgentScheduler {
    public static let shared = AgentScheduler()

    private var schedules: [ScheduleID: Schedule] = [:]
    private var timers: [ScheduleID: Task<Void, Never>] = [:]
    private var eventSubscriptions: [ScheduleID: EventSubscription] = [:]

    private let eventBus: EventBus?

    public init(eventBus: EventBus? = nil) {
        self.eventBus = eventBus
    }

    // MARK: - Schedule Management

    /// Create a new schedule
    public func schedule(
        _ task: AgentTask,
        for agent: AgentID,
        pattern: SchedulePattern,
        in space: SpaceID? = nil,
        enabled: Bool = true
    ) async throws -> Schedule {
        let schedule = Schedule(
            id: ScheduleID(),
            agentId: agent,
            task: task,
            spaceId: space,
            pattern: pattern,
            enabled: enabled
        )

        schedules[schedule.id] = schedule

        if enabled {
            try await activate(schedule)
        }

        return schedule
    }

    /// Update an existing schedule
    public func update(_ id: ScheduleID, pattern: SchedulePattern? = nil, enabled: Bool? = nil) async throws {
        guard var schedule = schedules[id] else {
            throw SchedulerError.notFound
        }

        // Deactivate current schedule
        await deactivate(schedule)

        // Update
        if let pattern {
            schedule.pattern = pattern
        }
        if let enabled {
            schedule.enabled = enabled
        }
        schedule.updatedAt = Date()

        schedules[id] = schedule

        // Reactivate if enabled
        if schedule.enabled {
            try await activate(schedule)
        }
    }

    /// Delete a schedule
    public func delete(_ id: ScheduleID) async {
        guard let schedule = schedules[id] else { return }

        await deactivate(schedule)
        schedules.removeValue(forKey: id)
    }

    /// Get a schedule by ID
    public func get(_ id: ScheduleID) -> Schedule? {
        schedules[id]
    }

    /// List all schedules, optionally filtered
    public func list(for agent: AgentID? = nil, in space: SpaceID? = nil, enabled: Bool? = nil) -> [Schedule] {
        schedules.values.filter { schedule in
            (agent == nil || schedule.agentId == agent) &&
            (space == nil || schedule.spaceId == space) &&
            (enabled == nil || schedule.enabled == enabled)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Activation

    private func activate(_ schedule: Schedule) async throws {
        switch schedule.pattern {
        case .cron(let expression):
            try await activateCron(schedule, expression: expression)

        case .interval(let duration):
            activateInterval(schedule, duration: duration)

        case .once(let date):
            activateOnce(schedule, at: date)

        case .natural(let description):
            let resolved = try parseNaturalLanguage(description)
            var updated = schedule
            updated.pattern = resolved
            schedules[schedule.id] = updated
            try await activate(updated)

        case .event(let filter):
            await activateEventTrigger(schedule, filter: filter)
        }
    }

    private func deactivate(_ schedule: Schedule) async {
        // Cancel timer if exists
        timers[schedule.id]?.cancel()
        timers.removeValue(forKey: schedule.id)

        // Remove event subscription if exists
        eventSubscriptions.removeValue(forKey: schedule.id)
    }

    // MARK: - Pattern Handlers

    private func activateCron(_ schedule: Schedule, expression: String) async throws {
        let parser = CronParser(expression: expression)
        guard let nextRun = try parser.nextDate(after: Date()) else {
            throw SchedulerError.invalidPattern
        }

        scheduleTimer(schedule, fireAt: nextRun, repeating: true)
    }

    private func activateInterval(_ schedule: Schedule, duration: Duration) {
        let timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: duration)

                guard !Task.isCancelled else { break }

                await self.executeSchedule(schedule)
            }
        }

        timers[schedule.id] = timer
    }

    private func activateOnce(_ schedule: Schedule, at date: Date) {
        let delay = date.timeIntervalSince(Date())
        guard delay > 0 else {
            // Already passed, execute immediately
            Task { await executeSchedule(schedule) }
            return
        }

        scheduleTimer(schedule, fireAt: date, repeating: false)
    }

    private func activateEventTrigger(_ schedule: Schedule, filter: EventFilter) async {
        let subscription = EventSubscription(
            agentId: schedule.agentId,
            filter: filter,
            priority: .normal
        )

        eventSubscriptions[schedule.id] = subscription

        // Register with event bus
        // eventBus?.subscribe(subscription) { event in
        //     await self.executeSchedule(schedule)
        // }
    }

    private func scheduleTimer(_ schedule: Schedule, fireAt: Date, repeating: Bool) {
        let timer = Task {
            let delay = fireAt.timeIntervalSince(Date())
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard !Task.isCancelled else { return }

            await self.executeSchedule(schedule)

            // If repeating (cron), schedule next occurrence
            if repeating {
                if case .cron(let expression) = schedule.pattern {
                    try? await self.activateCron(schedule, expression: expression)
                }
            }
        }

        timers[schedule.id] = timer
    }

    // MARK: - Execution

    private func executeSchedule(_ schedule: Schedule) async {
        guard schedule.enabled else { return }

        // Record execution
        var updated = schedule
        updated.lastRun = Date()
        updated.runCount += 1
        schedules[schedule.id] = updated

        // Emit scheduled event
        await eventBus?.emit(.scheduled(schedule.id.rawValue.uuidString))

        // The actual task execution would be handled by the agent system
        // This scheduler just triggers the event
    }

    // MARK: - Natural Language Parsing

    private func parseNaturalLanguage(_ description: String) throws -> SchedulePattern {
        let lowered = description.lowercased()

        // Simple patterns
        if lowered.contains("every hour") {
            return .interval(.seconds(3600))
        }
        if lowered.contains("every day") || lowered.contains("daily") {
            return .cron("0 0 * * *")
        }
        if lowered.contains("every week") || lowered.contains("weekly") {
            return .cron("0 0 * * 0")
        }
        if lowered.contains("every morning") {
            return .cron("0 9 * * *")
        }
        if lowered.contains("every evening") {
            return .cron("0 18 * * *")
        }
        if lowered.contains("weekday") || lowered.contains("work day") {
            return .cron("0 9 * * 1-5")
        }

        // Time-specific patterns
        if let match = lowered.range(of: #"at (\d{1,2}):?(\d{2})?\s*(am|pm)?"#, options: .regularExpression) {
            // Parse time and create cron
            // Simplified: just return a morning schedule
            return .cron("0 9 * * *")
        }

        // Interval patterns
        if let match = lowered.range(of: #"every (\d+) (minute|hour|day)"#, options: .regularExpression) {
            let substring = String(lowered[match])
            // Simplified parsing
            if substring.contains("minute") {
                return .interval(.seconds(60))
            } else if substring.contains("hour") {
                return .interval(.seconds(3600))
            }
        }

        throw SchedulerError.invalidPattern
    }
}

// MARK: - Schedule Types

public struct ScheduleID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init() {
        self.rawValue = UUID()
    }
}

public struct Schedule: Identifiable, Codable, Sendable {
    public let id: ScheduleID
    public let agentId: AgentID
    public let task: AgentTask
    public let spaceId: SpaceID?
    public var pattern: SchedulePattern
    public var enabled: Bool

    public let createdAt: Date
    public var updatedAt: Date
    public var lastRun: Date?
    public var nextRun: Date?
    public var runCount: Int

    public init(
        id: ScheduleID = ScheduleID(),
        agentId: AgentID,
        task: AgentTask,
        spaceId: SpaceID? = nil,
        pattern: SchedulePattern,
        enabled: Bool = true
    ) {
        self.id = id
        self.agentId = agentId
        self.task = task
        self.spaceId = spaceId
        self.pattern = pattern
        self.enabled = enabled
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastRun = nil
        self.nextRun = nil
        self.runCount = 0
    }
}

public enum SchedulePattern: Codable, Sendable, Equatable {
    /// Standard cron expression (minute hour day month weekday)
    case cron(String)

    /// Fixed interval
    case interval(Duration)

    /// One-time execution at specific date
    case once(Date)

    /// Natural language description (parsed to another pattern)
    case natural(String)

    /// Triggered by matching events
    case event(EventFilter)
}

// MARK: - Cron Parser

/// Simple cron expression parser
public struct CronParser {
    public let expression: String

    public init(expression: String) {
        self.expression = expression
    }

    /// Parse expression and return next occurrence after given date
    public func nextDate(after date: Date) throws -> Date? {
        let parts = expression.split(separator: " ")
        guard parts.count == 5 else {
            throw SchedulerError.invalidPattern
        }

        // Simplified: just add appropriate time to current date
        // A real implementation would properly parse cron expressions

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        // Very simplified logic
        if let minute = Int(parts[0]) {
            components.minute = minute
        }
        if let hour = Int(parts[1]) {
            components.hour = hour
        }

        var nextDate = calendar.date(from: components) ?? date

        // If next date is in the past, add a day
        if nextDate <= date {
            nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? nextDate
        }

        return nextDate
    }
}

// MARK: - Event Filter

public struct EventFilter: Codable, Sendable, Equatable {
    public let eventTypes: [String]?
    public let sourceAgents: [AgentID]?
    public let spaces: [SpaceID]?
    public let priority: Priority?
    public let metadata: [String: String]?

    public init(
        eventTypes: [String]? = nil,
        sourceAgents: [AgentID]? = nil,
        spaces: [SpaceID]? = nil,
        priority: Priority? = nil,
        metadata: [String: String]? = nil
    ) {
        self.eventTypes = eventTypes
        self.sourceAgents = sourceAgents
        self.spaces = spaces
        self.priority = priority
        self.metadata = metadata
    }

    public func matches(_ event: SystemEvent) -> Bool {
        // Simplified matching logic
        // Would check event type, source, etc.
        true
    }
}

public struct EventSubscription: Sendable {
    public let agentId: AgentID
    public let filter: EventFilter
    public let priority: SubscriptionPriority
}

public enum SubscriptionPriority: Int, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
}

// MARK: - Errors

public enum SchedulerError: Error {
    case notFound
    case invalidPattern
    case alreadyExists
    case disabled
}

// MARK: - Convenience Extensions

extension AgentScheduler {
    /// Schedule a daily task
    public func daily(
        at hour: Int,
        minute: Int = 0,
        task: AgentTask,
        for agent: AgentID
    ) async throws -> Schedule {
        try await schedule(
            task,
            for: agent,
            pattern: .cron("\(minute) \(hour) * * *")
        )
    }

    /// Schedule a task to run every N minutes
    public func everyMinutes(
        _ minutes: Int,
        task: AgentTask,
        for agent: AgentID
    ) async throws -> Schedule {
        try await schedule(
            task,
            for: agent,
            pattern: .interval(.seconds(Double(minutes * 60)))
        )
    }

    /// Schedule a one-time task
    public func once(
        at date: Date,
        task: AgentTask,
        for agent: AgentID
    ) async throws -> Schedule {
        try await schedule(
            task,
            for: agent,
            pattern: .once(date)
        )
    }

    /// Schedule based on natural language
    public func schedule(
        _ description: String,
        task: AgentTask,
        for agent: AgentID
    ) async throws -> Schedule {
        try await schedule(
            task,
            for: agent,
            pattern: .natural(description)
        )
    }
}

// MARK: - EventBus Placeholder

/// Placeholder for EventBus - would be the real implementation
public actor EventBus {
    public func emit(_ event: SystemEvent) async {
        // Would route event to subscribers
    }

    public func subscribe(_ subscription: EventSubscription, handler: @escaping (SystemEvent) async -> Void) {
        // Would register subscription
    }
}
