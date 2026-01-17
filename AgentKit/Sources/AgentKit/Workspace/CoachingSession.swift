import Foundation

// MARK: - Coaching Session

/// A coaching session is a structured interaction focused on learning and growth.
///
/// Unlike open-ended conversations, coaching sessions follow a pattern:
/// Learn → Grow → Practice → Reflect
public struct CoachingSession: Identifiable, Codable, Sendable {
    public let id: CoachingSessionID
    public var title: String
    public var domain: CoachingDomain
    public var phase: CoachingPhase
    public var goal: String?
    public var messages: [ThreadMessage]
    public var notes: [CoachingNote]
    public var progress: CoachingProgress
    public var agentId: AgentID?
    public let createdAt: Date
    public var updatedAt: Date
    public var endedAt: Date?

    public init(
        id: CoachingSessionID = CoachingSessionID(),
        title: String = "Coaching Session",
        domain: CoachingDomain,
        phase: CoachingPhase = .learn,
        goal: String? = nil,
        messages: [ThreadMessage] = [],
        notes: [CoachingNote] = [],
        progress: CoachingProgress = CoachingProgress(),
        agentId: AgentID? = nil
    ) {
        self.id = id
        self.title = title
        self.domain = domain
        self.phase = phase
        self.goal = goal
        self.messages = messages
        self.notes = notes
        self.progress = progress
        self.agentId = agentId
        self.createdAt = Date()
        self.updatedAt = Date()
        self.endedAt = nil
    }

    /// Whether the session is currently active
    public var isActive: Bool {
        endedAt == nil
    }

    /// Duration of the session
    public var duration: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(createdAt)
    }
}

public struct CoachingSessionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

// MARK: - Coaching Domain

/// The domain or area of coaching.
public enum CoachingDomain: String, Codable, Sendable, CaseIterable {
    case career      // Job search, interviews, career growth
    case fitness     // Workout plans, form, motivation
    case writing     // Style, editing, creative writing
    case skills      // Learning any skill with structured practice
    case wellness    // Mental health, stress, habits
    case finance     // Budgeting, investing, planning
    case language    // Language learning
    case custom      // User-defined domain

    public var displayName: String {
        switch self {
        case .career: return "Career"
        case .fitness: return "Fitness"
        case .writing: return "Writing"
        case .skills: return "Skills"
        case .wellness: return "Wellness"
        case .finance: return "Finance"
        case .language: return "Language"
        case .custom: return "Custom"
        }
    }

    public var icon: String {
        switch self {
        case .career: return "briefcase.fill"
        case .fitness: return "figure.run"
        case .writing: return "pencil.line"
        case .skills: return "lightbulb.fill"
        case .wellness: return "heart.fill"
        case .finance: return "dollarsign.circle.fill"
        case .language: return "globe"
        case .custom: return "star.fill"
        }
    }

    public var color: String {
        switch self {
        case .career: return "blue"
        case .fitness: return "orange"
        case .writing: return "purple"
        case .skills: return "yellow"
        case .wellness: return "pink"
        case .finance: return "green"
        case .language: return "teal"
        case .custom: return "gray"
        }
    }
}

// MARK: - Coaching Phase

/// The current phase in the coaching session.
///
/// Sessions progress through: Learn → Grow → Practice → Reflect
public enum CoachingPhase: String, Codable, Sendable, CaseIterable {
    case learn      // Understanding concepts and context
    case grow       // Applying and expanding knowledge
    case practice   // Hands-on practice and repetition
    case reflect    // Review and consolidate learnings

    public var displayName: String {
        switch self {
        case .learn: return "Learn"
        case .grow: return "Grow"
        case .practice: return "Practice"
        case .reflect: return "Reflect"
        }
    }

    public var description: String {
        switch self {
        case .learn: return "Understanding concepts and building foundation"
        case .grow: return "Applying knowledge and expanding capabilities"
        case .practice: return "Hands-on practice and skill building"
        case .reflect: return "Reviewing progress and consolidating learnings"
        }
    }

    public var icon: String {
        switch self {
        case .learn: return "book.fill"
        case .grow: return "arrow.up.right"
        case .practice: return "figure.walk"
        case .reflect: return "sparkles"
        }
    }

    /// The next phase in the cycle
    public var next: CoachingPhase {
        switch self {
        case .learn: return .grow
        case .grow: return .practice
        case .practice: return .reflect
        case .reflect: return .learn
        }
    }
}

// MARK: - Coaching Note

/// A note taken during a coaching session.
public struct CoachingNote: Identifiable, Codable, Sendable {
    public let id: UUID
    public var content: String
    public var type: NoteType
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        content: String,
        type: NoteType = .general
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.timestamp = Date()
    }
}

public enum NoteType: String, Codable, Sendable {
    case general
    case strength     // Something done well
    case improvement  // Area to improve
    case action       // Action item
    case insight      // Key insight or learning
}

// MARK: - Coaching Progress

/// Tracks progress within and across coaching sessions.
public struct CoachingProgress: Codable, Sendable {
    public var totalSessions: Int
    public var totalDuration: TimeInterval
    public var streakDays: Int
    public var lastSessionDate: Date?
    public var milestones: [Milestone]
    public var goals: [Goal]

    public init(
        totalSessions: Int = 0,
        totalDuration: TimeInterval = 0,
        streakDays: Int = 0,
        lastSessionDate: Date? = nil,
        milestones: [Milestone] = [],
        goals: [Goal] = []
    ) {
        self.totalSessions = totalSessions
        self.totalDuration = totalDuration
        self.streakDays = streakDays
        self.lastSessionDate = lastSessionDate
        self.milestones = milestones
        self.goals = goals
    }
}

public struct Milestone: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var description: String?
    public var achievedAt: Date?
    public var icon: String

    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        achievedAt: Date? = nil,
        icon: String = "star.fill"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.achievedAt = achievedAt
        self.icon = icon
    }

    public var isAchieved: Bool {
        achievedAt != nil
    }
}

public struct Goal: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var description: String?
    public var targetDate: Date?
    public var progress: Double  // 0.0 - 1.0
    public var isCompleted: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        targetDate: Date? = nil,
        progress: Double = 0.0,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.targetDate = targetDate
        self.progress = progress
        self.isCompleted = isCompleted
    }
}
