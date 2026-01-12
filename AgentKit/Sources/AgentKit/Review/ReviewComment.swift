import Foundation

// MARK: - Review Comment

/// A comment on a review with threading support
public struct ReviewComment: Codable, Identifiable, Sendable {
    public let id: UUID
    public let reviewId: ReviewID
    public let author: Author

    // Positioning
    public var position: CommentPosition

    // Content
    public let content: String
    public var type: CommentType
    public var suggestion: String?  // For suggestion type

    // Threading
    public var replyTo: UUID?

    // Status
    public var resolved: Bool
    public var resolvedBy: Author?
    public var resolvedAt: Date?

    // Timestamps
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        reviewId: ReviewID,
        author: Author,
        position: CommentPosition,
        content: String,
        type: CommentType = .comment,
        suggestion: String? = nil,
        replyTo: UUID? = nil,
        resolved: Bool = false,
        resolvedBy: Author? = nil,
        resolvedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.reviewId = reviewId
        self.author = author
        self.position = position
        self.content = content
        self.type = type
        self.suggestion = suggestion
        self.replyTo = replyTo
        self.resolved = resolved
        self.resolvedBy = resolvedBy
        self.resolvedAt = resolvedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Comment Position

/// Where a comment is positioned in the review
public enum CommentPosition: Codable, Sendable, Equatable {
    /// General comment on the overall review
    case general

    /// Comment on a whole file
    case file(path: String)

    /// Comment on a specific line
    case line(path: String, line: Int)

    /// Comment on a range of lines
    case range(path: String, start: Int, end: Int)

    /// Comment on a document section (by heading)
    case section(path: String, heading: String)

    /// Comment on a specific block (for block-based documents)
    case block(path: String, blockId: String)

    public var path: String? {
        switch self {
        case .general:
            return nil
        case .file(let path),
             .line(let path, _),
             .range(let path, _, _),
             .section(let path, _),
             .block(let path, _):
            return path
        }
    }

    public var displayDescription: String {
        switch self {
        case .general:
            return "General comment"
        case .file(let path):
            return path
        case .line(let path, let line):
            return "\(path):\(line)"
        case .range(let path, let start, let end):
            return "\(path):\(start)-\(end)"
        case .section(let path, let heading):
            return "\(path) § \(heading)"
        case .block(let path, let blockId):
            return "\(path) #\(blockId.prefix(8))"
        }
    }
}

// MARK: - Comment Type

public enum CommentType: String, Codable, Sendable {
    case comment      // General comment
    case question     // Question for author
    case suggestion   // Proposed change
    case praise       // Positive feedback
    case concern      // Issue/concern

    public var icon: String {
        switch self {
        case .comment: return "bubble.left"
        case .question: return "questionmark.circle"
        case .suggestion: return "pencil.and.outline"
        case .praise: return "hand.thumbsup"
        case .concern: return "exclamationmark.triangle"
        }
    }

    public var displayName: String {
        switch self {
        case .comment: return "Comment"
        case .question: return "Question"
        case .suggestion: return "Suggestion"
        case .praise: return "Praise"
        case .concern: return "Concern"
        }
    }
}

// MARK: - Comment Thread

/// A thread of comments (root + replies)
public struct CommentThread: Sendable {
    public let root: ReviewComment
    public let replies: [ReviewComment]

    public init(root: ReviewComment, replies: [ReviewComment] = []) {
        self.root = root
        self.replies = replies
    }

    public var allComments: [ReviewComment] {
        [root] + replies
    }

    public var isResolved: Bool {
        root.resolved
    }

    public var replyCount: Int {
        replies.count
    }
}
