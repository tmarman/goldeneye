import Foundation

// MARK: - Decision Card

/// A Decision Card represents something that needs human review and decision.
///
/// Inspired by GitHub PR reviews, decision cards allow:
/// - Inline comments on specific parts
/// - Approve or request revisions
/// - Track decision history
///
/// Use cases:
/// - Agent-generated content needing approval
/// - Draft documents ready for review
/// - Proposed actions or changes
/// - Multi-step workflows requiring checkpoints
public struct DecisionCard: Identifiable, Codable, Sendable {
    public let id: DecisionCardID
    public var title: String
    public var description: String
    public var status: DecisionStatus
    public var sourceType: DecisionSourceType
    public var sourceId: String?  // ID of the source (document, task, etc.)
    public var comments: [DecisionComment]
    public var reviewHistory: [DecisionReview]
    public let createdAt: Date
    public var updatedAt: Date
    public var requestedBy: String?  // Agent or user who created this

    public init(
        id: DecisionCardID = DecisionCardID(),
        title: String,
        description: String,
        status: DecisionStatus = .pending,
        sourceType: DecisionSourceType,
        sourceId: String? = nil,
        comments: [DecisionComment] = [],
        reviewHistory: [DecisionReview] = [],
        requestedBy: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.comments = comments
        self.reviewHistory = reviewHistory
        self.createdAt = Date()
        self.updatedAt = Date()
        self.requestedBy = requestedBy
    }

    /// Check if this card is actionable (pending decision)
    public var isActionable: Bool {
        status == .pending || status == .changesRequested
    }
}

public struct DecisionCardID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

// MARK: - Decision Status

public enum DecisionStatus: String, Codable, Sendable {
    case pending            // Awaiting decision
    case approved           // Approved as-is
    case changesRequested   // Needs revisions (like GitHub "Request changes")
    case dismissed          // Dismissed/rejected
    case expired            // No longer relevant
}

// MARK: - Decision Source Type

/// What type of content this decision card relates to
public enum DecisionSourceType: String, Codable, Sendable {
    case document           // Document content review
    case agentAction        // Agent wants to perform an action
    case generatedContent   // AI-generated content needing approval
    case workflowStep       // Step in a multi-stage workflow
    case suggestion         // Suggested improvement or change
    case other
}

// MARK: - Decision Comment

/// An inline comment on a decision card, similar to PR review comments
public struct DecisionComment: Identifiable, Codable, Sendable {
    public let id: UUID
    public var content: String
    public var author: String  // User or agent name
    public var lineReference: LineReference?  // Optional reference to specific content
    public var isResolved: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        content: String,
        author: String,
        lineReference: LineReference? = nil,
        isResolved: Bool = false
    ) {
        self.id = id
        self.content = content
        self.author = author
        self.lineReference = lineReference
        self.isResolved = isResolved
        self.createdAt = Date()
    }
}

/// Reference to a specific location in content (like a PR line comment)
public struct LineReference: Codable, Sendable {
    public var blockId: String?     // For block-based documents
    public var startLine: Int?      // For text content
    public var endLine: Int?
    public var snippet: String?     // The referenced text snippet

    public init(
        blockId: String? = nil,
        startLine: Int? = nil,
        endLine: Int? = nil,
        snippet: String? = nil
    ) {
        self.blockId = blockId
        self.startLine = startLine
        self.endLine = endLine
        self.snippet = snippet
    }
}

// MARK: - Decision Review

/// A review action taken on a decision card
public struct DecisionReview: Identifiable, Codable, Sendable {
    public let id: UUID
    public var action: ReviewAction
    public var reviewer: String
    public var comment: String?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        action: ReviewAction,
        reviewer: String,
        comment: String? = nil
    ) {
        self.id = id
        self.action = action
        self.reviewer = reviewer
        self.comment = comment
        self.timestamp = Date()
    }
}

public enum ReviewAction: String, Codable, Sendable {
    case approved           // Approved the card
    case changesRequested   // Requested changes
    case commented          // Left a comment only
    case dismissed          // Dismissed/rejected
    case reopened           // Reopened after being closed
}

// MARK: - Decision Card Actions

extension DecisionCard {
    /// Approve this decision card
    public mutating func approve(by reviewer: String, comment: String? = nil) {
        let review = DecisionReview(
            action: .approved,
            reviewer: reviewer,
            comment: comment
        )
        reviewHistory.append(review)
        status = .approved
        updatedAt = Date()
    }

    /// Request changes on this decision card
    public mutating func requestChanges(by reviewer: String, comment: String) {
        let review = DecisionReview(
            action: .changesRequested,
            reviewer: reviewer,
            comment: comment
        )
        reviewHistory.append(review)
        status = .changesRequested
        updatedAt = Date()
    }

    /// Dismiss this decision card
    public mutating func dismiss(by reviewer: String, reason: String? = nil) {
        let review = DecisionReview(
            action: .dismissed,
            reviewer: reviewer,
            comment: reason
        )
        reviewHistory.append(review)
        status = .dismissed
        updatedAt = Date()
    }

    /// Add a comment to this decision card
    public mutating func addComment(_ comment: DecisionComment) {
        comments.append(comment)
        updatedAt = Date()
    }
}
