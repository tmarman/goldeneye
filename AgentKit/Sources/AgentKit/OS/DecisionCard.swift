import Foundation

// MARK: - Decision Card (PR-like)

/// A DecisionCard is the primary mechanism for content changes in the agentic OS.
/// Like a Pull Request, it represents proposed changes from one agent/context to another.
/// Content flows through DecisionCards, while orchestration flows through Events.
public struct DecisionCard: Identifiable, Codable, Sendable {
    public let id: DecisionID
    public let createdAt: Date
    public var updatedAt: Date

    // Source
    public let sourceAgent: AgentID?
    public let sourceBranch: String
    public let sourceSpace: SpaceID?

    // Target
    public let targetSpace: SpaceID
    public let targetBranch: String

    // Content
    public var title: String
    public var description: String
    public var changes: [Change]

    // State
    public var status: DecisionStatus
    public var reviews: [Review]
    public var approvals: [DecisionApproval]

    // Metadata
    public var labels: [String]
    public var priority: Priority
    public var dueDate: Date?
    public var linkedCards: [DecisionID]

    public init(
        id: DecisionID = DecisionID(),
        sourceAgent: AgentID? = nil,
        sourceBranch: String,
        sourceSpace: SpaceID? = nil,
        targetSpace: SpaceID,
        targetBranch: String = "main",
        title: String,
        description: String = "",
        changes: [Change] = [],
        labels: [String] = [],
        priority: Priority = .normal
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sourceAgent = sourceAgent
        self.sourceBranch = sourceBranch
        self.sourceSpace = sourceSpace
        self.targetSpace = targetSpace
        self.targetBranch = targetBranch
        self.title = title
        self.description = description
        self.changes = changes
        self.status = .draft
        self.reviews = []
        self.approvals = []
        self.labels = labels
        self.priority = priority
        self.dueDate = nil
        self.linkedCards = []
    }
}

public struct DecisionID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init() {
        self.rawValue = UUID()
    }

    public init(_ uuid: UUID) {
        self.rawValue = uuid
    }
}

// MARK: - Decision Status

public enum DecisionStatus: String, Codable, Sendable {
    /// Agent is still working on changes
    case draft

    /// Ready for review
    case proposed

    /// Under review by other agents or humans
    case reviewing

    /// All required approvals received
    case approved

    /// Changes have been merged to target
    case merged

    /// Changes were rejected
    case rejected

    /// Merge conflicts need resolution
    case conflicted

    /// Card was abandoned
    case closed

    public var isOpen: Bool {
        switch self {
        case .draft, .proposed, .reviewing, .approved, .conflicted:
            return true
        case .merged, .rejected, .closed:
            return false
        }
    }

    public var canMerge: Bool {
        self == .approved
    }

    public var needsAction: Bool {
        switch self {
        case .proposed, .reviewing, .conflicted:
            return true
        default:
            return false
        }
    }
}

// MARK: - Changes

public struct Change: Codable, Sendable {
    public let id: String
    public let path: String
    public let type: ChangeType
    public let additions: Int
    public let deletions: Int
    public let patch: String?

    public enum ChangeType: String, Codable, Sendable {
        case added
        case modified
        case deleted
        case renamed
        case copied
    }
}

// MARK: - Reviews

public struct Review: Identifiable, Codable, Sendable {
    public let id: String
    public let reviewerId: String  // AgentID or UserID
    public let reviewerType: ReviewerType
    public let createdAt: Date
    public let status: ReviewStatus
    public let body: String?
    public let comments: [ReviewComment]

    public enum ReviewerType: String, Codable, Sendable {
        case agent
        case human
    }

    public enum ReviewStatus: String, Codable, Sendable {
        case pending
        case approved
        case changesRequested
        case commented
        case dismissed
    }
}

public struct ReviewComment: Identifiable, Codable, Sendable {
    public let id: String
    public let path: String?
    public let line: Int?
    public let body: String
    public let createdAt: Date
    public let resolved: Bool
}

// MARK: - Approvals

public struct DecisionApproval: Identifiable, Codable, Sendable {
    public let id: String
    public let approverId: String
    public let approverType: Review.ReviewerType
    public let approvedAt: Date
    public let expiresAt: Date?
    public let scope: ApprovalScope

    public enum ApprovalScope: String, Codable, Sendable {
        case full           // Approve entire decision
        case partial        // Approve specific changes
        case conditional    // Approve with conditions
    }
}

// MARK: - Priority

public enum Priority: Int, Codable, Sendable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3
    case critical = 4

    public static func < (lhs: Priority, rhs: Priority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Decision Card Manager

/// Manages the lifecycle of DecisionCards across spaces
public actor DecisionCardManager {
    private var cards: [DecisionID: DecisionCard] = [:]
    private var cardsBySpace: [SpaceID: Set<DecisionID>] = [:]
    private var cardsByAgent: [AgentID: Set<DecisionID>] = [:]

    private let eventBus: EventBus

    public init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    // MARK: - CRUD Operations

    public func create(_ card: DecisionCard) async throws -> DecisionCard {
        cards[card.id] = card

        // Index by space
        cardsBySpace[card.targetSpace, default: []].insert(card.id)
        if let sourceSpace = card.sourceSpace {
            cardsBySpace[sourceSpace, default: []].insert(card.id)
        }

        // Index by agent
        if let agent = card.sourceAgent {
            cardsByAgent[agent, default: []].insert(card.id)
        }

        // Emit event
        await eventBus.emit(.decisionCardCreated(card.id))

        return card
    }

    public func get(_ id: DecisionID) -> DecisionCard? {
        cards[id]
    }

    public func update(_ card: DecisionCard) async throws {
        var updated = card
        updated.updatedAt = Date()
        cards[card.id] = updated
    }

    public func list(for space: SpaceID, status: DecisionStatus? = nil) -> [DecisionCard] {
        guard let cardIds = cardsBySpace[space] else { return [] }

        return cardIds.compactMap { cards[$0] }
            .filter { status == nil || $0.status == status }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func list(by agent: AgentID) -> [DecisionCard] {
        guard let cardIds = cardsByAgent[agent] else { return [] }

        return cardIds.compactMap { cards[$0] }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Workflow Operations

    /// Propose a draft card for review
    public func propose(_ id: DecisionID) async throws {
        guard var card = cards[id], card.status == .draft else {
            throw DecisionError.invalidTransition
        }

        card.status = .proposed
        card.updatedAt = Date()
        cards[id] = card

        await eventBus.emit(.decisionCardProposed(id))
    }

    /// Add a review to a card
    public func addReview(_ review: Review, to id: DecisionID) async throws {
        guard var card = cards[id], card.status.isOpen else {
            throw DecisionError.cardNotOpen
        }

        card.reviews.append(review)
        card.status = .reviewing
        card.updatedAt = Date()
        cards[id] = card

        await eventBus.emit(.decisionCardReviewed(id, by: AgentID()))
    }

    /// Approve a card
    public func approve(_ id: DecisionID, approval: DecisionApproval) async throws {
        guard var card = cards[id], card.status.isOpen else {
            throw DecisionError.cardNotOpen
        }

        card.approvals.append(approval)

        // Check if all required approvals are present
        if hasAllRequiredApprovals(card) {
            card.status = .approved
        }

        card.updatedAt = Date()
        cards[id] = card

        if card.status == .approved {
            await eventBus.emit(.decisionCardApproved(id))
        }
    }

    /// Merge an approved card
    public func merge(_ id: DecisionID) async throws {
        guard var card = cards[id], card.status == .approved else {
            throw DecisionError.cannotMerge
        }

        // Perform the actual git merge
        try await performMerge(card)

        card.status = .merged
        card.updatedAt = Date()
        cards[id] = card

        await eventBus.emit(.decisionCardMerged(id))
    }

    /// Reject a card
    public func reject(_ id: DecisionID, reason: String) async throws {
        guard var card = cards[id], card.status.isOpen else {
            throw DecisionError.cardNotOpen
        }

        card.status = .rejected
        card.updatedAt = Date()
        cards[id] = card

        await eventBus.emit(.decisionCardRejected(id, reason: reason))
    }

    // MARK: - Private Helpers

    private func hasAllRequiredApprovals(_ card: DecisionCard) -> Bool {
        // Simple: at least one approval
        // Could be extended to check required reviewers, approval count, etc.
        !card.approvals.isEmpty
    }

    private func performMerge(_ card: DecisionCard) async throws {
        // Would perform actual git merge here
        // git merge card.sourceBranch into card.targetBranch
    }
}

// MARK: - Errors

public enum DecisionError: Error {
    case notFound
    case invalidTransition
    case cardNotOpen
    case cannotMerge
    case conflicted
    case unauthorized
}

// MARK: - System Events Extension

public enum SystemEvent: Sendable {
    // Agent lifecycle
    case agentSpawned(AgentID)
    case agentTerminated(AgentID, reason: TerminationReason)

    // Decision cards
    case decisionCardCreated(DecisionID)
    case decisionCardProposed(DecisionID)
    case decisionCardReviewed(DecisionID, by: AgentID)
    case decisionCardApproved(DecisionID)
    case decisionCardMerged(DecisionID)
    case decisionCardRejected(DecisionID, reason: String)

    // Tasks
    case taskCreated(TaskID)
    case taskStarted(TaskID)
    case taskCompleted(TaskID)
    case taskFailed(TaskID, error: String)

    // Spaces
    case spaceCreated(SpaceID)
    case spaceUpdated(SpaceID)
    case documentCreated(DocumentID, in: SpaceID)

    // Scheduling
    case scheduled(String)
    case deadline(String)
    case reminder(String)

    // External
    case userInput(String)
    case webhook(String, payload: String)
}

// MARK: - Placeholder Types

// These would be defined elsewhere but are needed for compilation
public struct SpaceID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init() { self.rawValue = UUID() }
}

public struct DocumentID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init() { self.rawValue = UUID() }
}

public struct Space: Sendable {
    public let id: SpaceID
    public let name: String
    public let description: String?
}

public struct TaskResult: Sendable {
    public let success: Bool
    public let artifacts: [String]
}
