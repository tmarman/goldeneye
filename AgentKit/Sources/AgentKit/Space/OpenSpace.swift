import Foundation

// MARK: - Open Space

/// The Open Space is your personal timeline/feed - a free-form input area
/// focused on upcoming events, quick capture, and agent-driven organization.
///
/// Unlike named Spaces (which are project-focused), Open Space is:
/// - Chronological (timeline-based)
/// - Ephemeral (items flow through, get processed, move to spaces)
/// - Calendar-centric (events anchor the timeline)
/// - Agent-driven (agents process input, extract tasks, route to spaces)
///
/// Flow:
/// 1. User captures quick note or voice memo
/// 2. Agent analyzes and associates with calendar event (if relevant)
/// 3. Agent extracts: learnings, tasks, contacts, follow-ups
/// 4. Items get routed to appropriate Spaces or remain in timeline
public actor OpenSpace {
    public let id: String = "open-space"

    // Timeline items (ordered by time)
    private var _items: [TimelineItem] = []

    // Calendar events (from external calendars)
    private var _events: [CalendarEvent] = []

    // Quick capture buffer (unprocessed inputs)
    private var _captureQueue: [CapturedInput] = []

    public init() {}

    // MARK: - Timeline

    public func items() -> [TimelineItem] {
        _items.sorted { $0.timestamp > $1.timestamp }
    }

    public func itemsForToday() -> [TimelineItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        return _items.filter { item in
            item.timestamp >= today && item.timestamp < tomorrow
        }.sorted { $0.timestamp < $1.timestamp }
    }

    public func addItem(_ item: TimelineItem) {
        _items.append(item)
    }

    public func removeItem(_ id: TimelineItemID) {
        _items.removeAll { $0.id == id }
    }

    // MARK: - Calendar Events

    public func events() -> [CalendarEvent] {
        _events.sorted { $0.startTime < $1.startTime }
    }

    public func upcomingEvents(limit: Int = 5) -> [CalendarEvent] {
        let now = Date()
        return _events
            .filter { $0.startTime > now }
            .sorted { $0.startTime < $1.startTime }
            .prefix(limit)
            .map { $0 }
    }

    public func addEvent(_ event: CalendarEvent) {
        _events.append(event)
        // Also add to timeline as a card
        addItem(TimelineItem(
            type: .event(event),
            timestamp: event.startTime
        ))
    }

    public func updateEvent(_ event: CalendarEvent) {
        if let index = _events.firstIndex(where: { $0.id == event.id }) {
            _events[index] = event
        }
    }

    // MARK: - Quick Capture

    /// Capture free-form input for agent processing
    public func capture(_ input: CapturedInput) {
        _captureQueue.append(input)
    }

    /// Get pending captures for agent processing
    public func pendingCaptures() -> [CapturedInput] {
        _captureQueue.filter { !$0.isProcessed }
    }

    /// Mark a capture as processed
    public func markProcessed(_ id: UUID, result: ProcessingResult) {
        if let index = _captureQueue.firstIndex(where: { $0.id == id }) {
            _captureQueue[index].isProcessed = true
            _captureQueue[index].processingResult = result

            // Add processed note to timeline
            addItem(TimelineItem(
                type: .note(ProcessedNote(
                    content: _captureQueue[index].content,
                    linkedEventId: result.linkedEventId,
                    extractedTasks: result.createdTasks,
                    extractedLearnings: result.learnings
                )),
                timestamp: _captureQueue[index].timestamp
            ))
        }
    }
}

// MARK: - Timeline Item

public struct TimelineItem: Identifiable, Sendable {
    public let id: TimelineItemID
    public let type: TimelineItemType
    public let timestamp: Date
    public var isRead: Bool

    public init(
        id: TimelineItemID = TimelineItemID(),
        type: TimelineItemType,
        timestamp: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.isRead = isRead
    }
}

public struct TimelineItemID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public enum TimelineItemType: Sendable {
    case event(CalendarEvent)           // Calendar event card
    case note(ProcessedNote)            // Processed quick note
    case task(TimelineTask)             // Task from a space
    case reminder(Reminder)             // Time-based reminder
    case activity(ActivityEntry)        // Something that happened
    case agentUpdate(AgentUpdate)       // Agent reporting status
}

// MARK: - Calendar Event

public struct CalendarEvent: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var startTime: Date
    public var endTime: Date
    public var location: String?
    public var attendees: [Attendee]
    public var notes: [EventNote]           // Notes attached to this event
    public var linkedSpaceId: SpaceID?      // If this event belongs to a space
    public var calendarSource: String?      // "iCloud", "Google", etc.

    public init(
        id: String = UUID().uuidString,
        title: String,
        startTime: Date,
        endTime: Date,
        location: String? = nil,
        attendees: [Attendee] = [],
        notes: [EventNote] = [],
        linkedSpaceId: SpaceID? = nil,
        calendarSource: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.attendees = attendees
        self.notes = notes
        self.linkedSpaceId = linkedSpaceId
        self.calendarSource = calendarSource
    }

    public var isUpcoming: Bool {
        startTime > Date()
    }

    public var isHappeningNow: Bool {
        let now = Date()
        return startTime <= now && endTime >= now
    }

    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

public struct Attendee: Codable, Sendable {
    public let name: String
    public let email: String?
    public var status: AttendeeStatus

    public init(name: String, email: String? = nil, status: AttendeeStatus = .pending) {
        self.name = name
        self.email = email
        self.status = status
    }
}

public enum AttendeeStatus: String, Codable, Sendable {
    case accepted
    case declined
    case tentative
    case pending
}

public struct EventNote: Identifiable, Codable, Sendable {
    public let id: UUID
    public var content: String
    public let timestamp: Date
    public var processedBy: AgentID?    // Agent that processed this note

    public init(
        id: UUID = UUID(),
        content: String,
        timestamp: Date = Date(),
        processedBy: AgentID? = nil
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.processedBy = processedBy
    }
}

// MARK: - Quick Capture

public struct CapturedInput: Identifiable, Sendable {
    public let id: UUID
    public let content: String
    public let timestamp: Date
    public let inputType: CaptureType
    public var isProcessed: Bool
    public var processingResult: ProcessingResult?

    public init(
        id: UUID = UUID(),
        content: String,
        timestamp: Date = Date(),
        inputType: CaptureType = .text,
        isProcessed: Bool = false
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.inputType = inputType
        self.isProcessed = isProcessed
    }
}

public enum CaptureType: String, Sendable {
    case text           // Typed text
    case voice          // Voice transcription
    case photo          // Photo with potential OCR
    case screenshot     // Screenshot capture
}

public struct ProcessingResult: Sendable {
    public let linkedEventId: String?
    public let linkedSpaceId: SpaceID?
    public let createdTasks: [TimelineTask]
    public let learnings: [String]
    public let contacts: [ExtractedContact]
    public let followUps: [FollowUp]

    public init(
        linkedEventId: String? = nil,
        linkedSpaceId: SpaceID? = nil,
        createdTasks: [TimelineTask] = [],
        learnings: [String] = [],
        contacts: [ExtractedContact] = [],
        followUps: [FollowUp] = []
    ) {
        self.linkedEventId = linkedEventId
        self.linkedSpaceId = linkedSpaceId
        self.createdTasks = createdTasks
        self.learnings = learnings
        self.contacts = contacts
        self.followUps = followUps
    }
}

// MARK: - Processed Note

public struct ProcessedNote: Sendable {
    public let content: String
    public let linkedEventId: String?
    public let extractedTasks: [TimelineTask]
    public let extractedLearnings: [String]

    public init(
        content: String,
        linkedEventId: String? = nil,
        extractedTasks: [TimelineTask] = [],
        extractedLearnings: [String] = []
    ) {
        self.content = content
        self.linkedEventId = linkedEventId
        self.extractedTasks = extractedTasks
        self.extractedLearnings = extractedLearnings
    }
}

// MARK: - Timeline Task

public struct TimelineTask: Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var isCompleted: Bool
    public var dueDate: Date?
    public var sourceSpaceId: SpaceID?      // Which space this task belongs to
    public var assignedAgentId: AgentID?    // Agent responsible for this task
    public var delegatedFrom: AgentID?      // If delegated from another agent

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        sourceSpaceId: SpaceID? = nil,
        assignedAgentId: AgentID? = nil,
        delegatedFrom: AgentID? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.sourceSpaceId = sourceSpaceId
        self.assignedAgentId = assignedAgentId
        self.delegatedFrom = delegatedFrom
    }
}

// MARK: - Reminder

public struct Reminder: Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var triggerTime: Date
    public var linkedEventId: String?
    public var linkedSpaceId: SpaceID?
    public var isTriggered: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        triggerTime: Date,
        linkedEventId: String? = nil,
        linkedSpaceId: SpaceID? = nil,
        isTriggered: Bool = false
    ) {
        self.id = id
        self.title = title
        self.triggerTime = triggerTime
        self.linkedEventId = linkedEventId
        self.linkedSpaceId = linkedSpaceId
        self.isTriggered = isTriggered
    }
}

// MARK: - Activity Entry

public struct ActivityEntry: Sendable {
    public let description: String
    public let actor: ActivityActor
    public let timestamp: Date
    public let linkedSpaceId: SpaceID?
    public let linkedDocumentId: DocumentID?

    public init(
        description: String,
        actor: ActivityActor,
        timestamp: Date = Date(),
        linkedSpaceId: SpaceID? = nil,
        linkedDocumentId: DocumentID? = nil
    ) {
        self.description = description
        self.actor = actor
        self.timestamp = timestamp
        self.linkedSpaceId = linkedSpaceId
        self.linkedDocumentId = linkedDocumentId
    }
}

public enum ActivityActor: Sendable {
    case user(String)
    case agent(AgentID, name: String)
    case system
}

// MARK: - Agent Update

public struct AgentUpdate: Sendable {
    public let agentId: AgentID
    public let agentName: String
    public let message: String
    public let updateType: AgentUpdateType
    public let linkedSpaceId: SpaceID?

    public init(
        agentId: AgentID,
        agentName: String,
        message: String,
        updateType: AgentUpdateType,
        linkedSpaceId: SpaceID? = nil
    ) {
        self.agentId = agentId
        self.agentName = agentName
        self.message = message
        self.updateType = updateType
        self.linkedSpaceId = linkedSpaceId
    }
}

public enum AgentUpdateType: Sendable {
    case taskCompleted
    case taskDelegated(to: AgentID)
    case needsInput
    case decisionRequired
    case information
}

// MARK: - Extracted Data

public struct ExtractedContact: Sendable {
    public let name: String
    public var email: String?
    public var phone: String?
    public var notes: String?

    public init(name: String, email: String? = nil, phone: String? = nil, notes: String? = nil) {
        self.name = name
        self.email = email
        self.phone = phone
        self.notes = notes
    }
}

public struct FollowUp: Identifiable, Sendable {
    public let id: UUID
    public var description: String
    public var suggestedDate: Date?
    public var contactName: String?

    public init(
        id: UUID = UUID(),
        description: String,
        suggestedDate: Date? = nil,
        contactName: String? = nil
    ) {
        self.id = id
        self.description = description
        self.suggestedDate = suggestedDate
        self.contactName = contactName
    }
}

// MARK: - Agent Delegation

/// Represents when one agent delegates a task to another
public struct AgentDelegation: Identifiable, Sendable {
    public let id: UUID
    public let fromAgent: AgentID
    public let toAgent: AgentID
    public let task: TimelineTask
    public let reason: String
    public let timestamp: Date
    public var status: DelegationStatus

    public init(
        id: UUID = UUID(),
        fromAgent: AgentID,
        toAgent: AgentID,
        task: TimelineTask,
        reason: String,
        timestamp: Date = Date(),
        status: DelegationStatus = .pending
    ) {
        self.id = id
        self.fromAgent = fromAgent
        self.toAgent = toAgent
        self.task = task
        self.reason = reason
        self.timestamp = timestamp
        self.status = status
    }
}

public enum DelegationStatus: String, Sendable {
    case pending        // Waiting for receiving agent
    case accepted       // Receiving agent accepted
    case declined       // Receiving agent declined
    case completed      // Task was completed
    case returned       // Returned to original agent
}
