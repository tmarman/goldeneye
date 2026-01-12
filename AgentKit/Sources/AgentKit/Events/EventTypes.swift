import Foundation

// MARK: - Trigger Event

/// An event that can trigger agent wake-up and processing.
///
/// Events flow through the system like this:
/// ```
/// EventSource → EventBus → Subscribed Agents → Wake & Process
/// ```
///
/// Examples:
/// - Email arrives → EmailEventSource → NotificationEvent → Concierge wakes
/// - File changes → FileWatchEventSource → FileChangeEvent → Librarian indexes
/// - 9am daily → ScheduleEventSource → ScheduleEvent → Coach sends check-in
/// - Agent needs help → AgentEventSource → DelegationRequestEvent → Specialist wakes
public struct TriggerEvent: Identifiable, Sendable {
    public let id: TriggerEventID
    public let sourceId: EventSourceID
    public let type: TriggerEventType
    public let payload: EventPayload
    public let timestamp: Date
    public let priority: EventPriority
    public let metadata: [String: String]

    public init(
        id: TriggerEventID = TriggerEventID(),
        sourceId: EventSourceID,
        type: TriggerEventType,
        payload: EventPayload,
        priority: EventPriority = .normal,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sourceId = sourceId
        self.type = type
        self.payload = payload
        self.timestamp = Date()
        self.priority = priority
        self.metadata = metadata
    }
}

// MARK: - Event IDs

public struct TriggerEventID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID().uuidString
    }

    public var description: String { rawValue }
}

public struct EventSourceID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }
}

// MARK: - Event Types

/// Categories of trigger events
public enum TriggerEventType: String, Sendable, Codable, CaseIterable {
    // Communication
    case notification       // Generic notification (email, message, etc.)
    case messageReceived    // Incoming message from user or system
    case mentionReceived    // Agent was @mentioned

    // Time-based
    case scheduled          // Cron-like scheduled trigger
    case reminder           // User-set reminder
    case deadline           // Deadline approaching

    // Data changes
    case fileChanged        // File system change
    case documentUpdated    // Document in a Space changed
    case dataSync           // External data source synced

    // Health & Activity (for coaching agents)
    case healthMetric       // HealthKit data point (weight, steps, etc.)
    case activityCompleted  // User completed an activity
    case goalProgress       // Progress toward a goal

    // Agent collaboration
    case delegationRequest  // Another agent is asking for help
    case delegationComplete // Delegated task finished
    case decisionNeeded     // Human decision required
    case approvalReceived   // Human approved/denied something

    // System
    case systemStartup      // Agent system started
    case systemShutdown     // Agent system shutting down
    case errorOccurred      // Error that needs attention
    case integrationEvent   // Event from external integration

    // Custom
    case custom             // Custom event type (check metadata for details)
}

// MARK: - Event Priority

public enum EventPriority: Int, Sendable, Codable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3

    public static func < (lhs: EventPriority, rhs: EventPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Event Payload

/// The data carried by an event
public enum EventPayload: Sendable {
    // Communication payloads
    case message(MessagePayload)
    case notification(NotificationPayload)

    // File/Document payloads
    case fileChange(FileChangePayload)
    case documentChange(DocumentChangePayload)

    // Schedule payloads
    case schedule(SchedulePayload)

    // Health payloads
    case healthMetric(HealthMetricPayload)

    // Agent payloads
    case delegation(DelegationPayload)
    case decision(DecisionPayload)

    // Generic
    case json([String: AnyCodable])
    case text(String)
    case empty
}

// MARK: - Payload Types

public struct MessagePayload: Sendable {
    public let from: String
    public let subject: String?
    public let body: String
    public let channel: MessageChannel

    public init(from: String, subject: String? = nil, body: String, channel: MessageChannel) {
        self.from = from
        self.subject = subject
        self.body = body
        self.channel = channel
    }
}

public enum MessageChannel: String, Sendable, Codable {
    case email
    case imessage
    case slack
    case discord
    case webhook
    case a2a
    case internal_
}

public struct NotificationPayload: Sendable {
    public let title: String
    public let body: String
    public let category: String?
    public let actionable: Bool

    public init(title: String, body: String, category: String? = nil, actionable: Bool = false) {
        self.title = title
        self.body = body
        self.category = category
        self.actionable = actionable
    }
}

public struct FileChangePayload: Sendable {
    public let path: String
    public let changeType: FileChangeType
    public let previousPath: String?  // For renames

    public init(path: String, changeType: FileChangeType, previousPath: String? = nil) {
        self.path = path
        self.changeType = changeType
        self.previousPath = previousPath
    }
}

public enum FileChangeType: String, Sendable, Codable {
    case created
    case modified
    case deleted
    case renamed
    case moved
}

public struct DocumentChangePayload: Sendable {
    public let documentId: DocumentID
    public let spaceId: SpaceID
    public let changeType: DocumentChangeType
    public let changedBy: String?

    public init(documentId: DocumentID, spaceId: SpaceID, changeType: DocumentChangeType, changedBy: String? = nil) {
        self.documentId = documentId
        self.spaceId = spaceId
        self.changeType = changeType
        self.changedBy = changedBy
    }
}

public enum DocumentChangeType: String, Sendable, Codable {
    case created
    case updated
    case deleted
    case published
    case archived
}

public struct SchedulePayload: Sendable {
    public let scheduleName: String
    public let scheduledTime: Date
    public let recurrence: String?  // Cron expression or human-readable
    public let context: [String: String]

    public init(scheduleName: String, scheduledTime: Date, recurrence: String? = nil, context: [String: String] = [:]) {
        self.scheduleName = scheduleName
        self.scheduledTime = scheduledTime
        self.recurrence = recurrence
        self.context = context
    }
}

public struct HealthMetricPayload: Sendable {
    public let metricType: HealthMetricType
    public let value: Double
    public let unit: String
    public let timestamp: Date
    public let source: String?

    public init(metricType: HealthMetricType, value: Double, unit: String, timestamp: Date = Date(), source: String? = nil) {
        self.metricType = metricType
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.source = source
    }
}

public enum HealthMetricType: String, Sendable, Codable {
    case weight
    case bodyFat
    case steps
    case activeCalories
    case heartRate
    case sleep
    case workout
    case nutrition
    case water
    case custom
}

public struct DelegationPayload: Sendable {
    public let delegationId: UUID
    public let fromAgent: AgentID
    public let task: String
    public let requiredCapabilities: [AgentCapability]
    public let urgency: EventPriority

    public init(delegationId: UUID, fromAgent: AgentID, task: String, requiredCapabilities: [AgentCapability], urgency: EventPriority = .normal) {
        self.delegationId = delegationId
        self.fromAgent = fromAgent
        self.task = task
        self.requiredCapabilities = requiredCapabilities
        self.urgency = urgency
    }
}

public struct DecisionPayload: Sendable {
    public let cardId: DecisionCardID
    public let decision: DecisionStatus
    public let reviewer: String
    public let comment: String?

    public init(cardId: DecisionCardID, decision: DecisionStatus, reviewer: String, comment: String? = nil) {
        self.cardId = cardId
        self.decision = decision
        self.reviewer = reviewer
        self.comment = comment
    }
}

// Note: AnyCodable is defined in Message.swift
