import Foundation

// MARK: - Type Aliases

public typealias ReviewID = String

// Note: SpaceID is defined in Space/Space.swift

// MARK: - Review

/// A content review representing changes between two commits
public struct Review: Codable, Identifiable, Sendable {
    public let id: ReviewID
    public let spaceId: SpaceID?
    public var title: String
    public var description: String
    public let author: Author

    // Git references
    public let baseCommit: String
    public let headCommit: String
    public let targetBranch: String
    public let sourceBranch: String

    // Status and workflow
    public var status: ReviewStatus
    public var approvals: [Approval]

    // Content
    public var summary: ReviewSummary?
    public var changes: [ReviewChange]

    // Metadata
    public let createdAt: Date
    public var updatedAt: Date
    public var mergedAt: Date?
    public var closedAt: Date?

    // External links
    public var githubPRURL: String?
    public var metadata: [String: String]

    public init(
        id: ReviewID = UUID().uuidString,
        spaceId: SpaceID? = nil,
        title: String,
        description: String = "",
        author: Author,
        baseCommit: String,
        headCommit: String,
        targetBranch: String = "main",
        sourceBranch: String,
        status: ReviewStatus = .draft,
        approvals: [Approval] = [],
        summary: ReviewSummary? = nil,
        changes: [ReviewChange] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        mergedAt: Date? = nil,
        closedAt: Date? = nil,
        githubPRURL: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.spaceId = spaceId
        self.title = title
        self.description = description
        self.author = author
        self.baseCommit = baseCommit
        self.headCommit = headCommit
        self.targetBranch = targetBranch
        self.sourceBranch = sourceBranch
        self.status = status
        self.approvals = approvals
        self.summary = summary
        self.changes = changes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mergedAt = mergedAt
        self.closedAt = closedAt
        self.githubPRURL = githubPRURL
        self.metadata = metadata
    }
}

// MARK: - Author

/// Author of a review, comment, or approval
public struct Author: Codable, Sendable, Equatable {
    public let name: String
    public let email: String?
    public let avatar: String?  // SF Symbol name or URL

    public init(name: String, email: String? = nil, avatar: String? = nil) {
        self.name = name
        self.email = email
        self.avatar = avatar
    }

    /// System author for automated changes
    public static let system = Author(name: "System", avatar: "gear")

    /// Agent author for CLI runner agent
    public static func agent(_ name: String) -> Author {
        Author(name: name, avatar: "sparkles")
    }
}

// MARK: - Review Status

public enum ReviewStatus: String, Codable, Sendable, CaseIterable {
    case draft              // Not yet open for review
    case open               // Open for review
    case approved           // Approved by reviewers
    case changesRequested   // Changes requested
    case merged             // Merged into target branch
    case closed             // Closed without merging
}

// MARK: - Approval

/// A reviewer's approval or request for changes
public struct Approval: Codable, Identifiable, Sendable {
    public let id: UUID
    public let reviewer: Author
    public let status: ApprovalStatus
    public let comment: String?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        reviewer: Author,
        status: ApprovalStatus,
        comment: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.reviewer = reviewer
        self.status = status
        self.comment = comment
        self.timestamp = timestamp
    }
}

public enum ApprovalStatus: String, Codable, Sendable {
    case approved
    case changesRequested
    case commented
}

// MARK: - Review Summary

/// AI-generated summary of changes in a review
public struct ReviewSummary: Codable, Sendable {
    public let overview: String
    public let filesChanged: Int
    public let additions: Int
    public let deletions: Int
    public let keyChanges: [KeyChange]
    public let impact: ImpactLevel

    public init(
        overview: String,
        filesChanged: Int,
        additions: Int,
        deletions: Int,
        keyChanges: [KeyChange],
        impact: ImpactLevel
    ) {
        self.overview = overview
        self.filesChanged = filesChanged
        self.additions = additions
        self.deletions = deletions
        self.keyChanges = keyChanges
        self.impact = impact
    }
}

public struct KeyChange: Codable, Identifiable, Sendable {
    public let id: UUID
    public let type: ChangeType
    public let description: String
    public let files: [String]

    public init(
        id: UUID = UUID(),
        type: ChangeType,
        description: String,
        files: [String]
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.files = files
    }
}

public enum ChangeType: String, Codable, Sendable {
    case content      // Text/document changes
    case structure    // Headings, organization
    case metadata     // Frontmatter, attributes
    case media        // Images, attachments
    case code         // Code blocks
}

public enum ImpactLevel: String, Codable, Sendable {
    case minor        // Typo fixes, formatting
    case moderate     // Section rewrites, additions
    case major        // Complete restructure, new content
}

// MARK: - Review Change

/// A changed file in a review
public struct ReviewChange: Codable, Identifiable, Sendable {
    public let id: UUID
    public let path: String
    public let changeType: ReviewFileChangeType

    // Content representation
    public var beforeContent: String?
    public var afterContent: String?
    public var diff: String

    // Content analysis
    public var contentAnalysis: DocumentContentAnalysis?

    public init(
        id: UUID = UUID(),
        path: String,
        changeType: ReviewFileChangeType,
        beforeContent: String? = nil,
        afterContent: String? = nil,
        diff: String,
        contentAnalysis: DocumentContentAnalysis? = nil
    ) {
        self.id = id
        self.path = path
        self.changeType = changeType
        self.beforeContent = beforeContent
        self.afterContent = afterContent
        self.diff = diff
        self.contentAnalysis = contentAnalysis
    }
}

public enum ReviewFileChangeType: String, Codable, Sendable {
    case added
    case modified
    case deleted
    case renamed

    public var icon: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        }
    }

    public var color: String {
        switch self {
        case .added: return "green"
        case .modified: return "orange"
        case .deleted: return "red"
        case .renamed: return "blue"
        }
    }
}

/// Content analysis specific to document changes in reviews
public struct DocumentContentAnalysis: Codable, Sendable {
    public let wordCountBefore: Int
    public let wordCountAfter: Int
    public let sectionsAdded: [String]
    public let sectionsRemoved: [String]
    public let sectionsModified: [String]

    public init(
        wordCountBefore: Int,
        wordCountAfter: Int,
        sectionsAdded: [String] = [],
        sectionsRemoved: [String] = [],
        sectionsModified: [String] = []
    ) {
        self.wordCountBefore = wordCountBefore
        self.wordCountAfter = wordCountAfter
        self.sectionsAdded = sectionsAdded
        self.sectionsRemoved = sectionsRemoved
        self.sectionsModified = sectionsModified
    }

    public var wordCountDelta: Int {
        wordCountAfter - wordCountBefore
    }
}
