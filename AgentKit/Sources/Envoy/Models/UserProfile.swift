import Foundation

// MARK: - User Profile

/// Persistent profile representing what we've learned about the user.
///
/// The profile is built from:
/// - File system indexing (documents, projects, images)
/// - Agent conversations (preferences, interests mentioned)
/// - User-provided information (explicit settings)
///
/// Stored as `~/.envoy/Spaces/about-me/profile.md` with YAML frontmatter.
public struct UserProfile: Codable, Sendable {
    /// All learnings we've gathered about the user
    public var learnings: [ProfileLearning]

    /// When the file system was last indexed
    public var lastIndexed: Date?

    /// When the profile was last updated (from any source)
    public var lastUpdated: Date

    /// Profile version for migrations
    public var version: Int

    public init(
        learnings: [ProfileLearning] = [],
        lastIndexed: Date? = nil,
        lastUpdated: Date = Date(),
        version: Int = 1
    ) {
        self.learnings = learnings
        self.lastIndexed = lastIndexed
        self.lastUpdated = lastUpdated
        self.version = version
    }

    // MARK: - Convenience Accessors

    /// Learnings filtered by category
    public func learnings(for category: LearningCategory) -> [ProfileLearning] {
        learnings.filter { $0.category == category }
    }

    /// High-confidence learnings only (>= 0.7)
    public var highConfidenceLearnings: [ProfileLearning] {
        learnings.filter { $0.confidence >= 0.7 }
    }

    /// Generate a human-readable summary of the profile
    public func generateSummary() -> String {
        var sections: [String] = []

        // Work section
        let workLearnings = learnings(for: .work)
        if !workLearnings.isEmpty {
            var work = "### Work\n"
            for learning in workLearnings.prefix(5) {
                work += "- **\(learning.title)**: \(learning.description)\n"
            }
            sections.append(work)
        }

        // Interests section
        let interestLearnings = learnings(for: .interest)
        if !interestLearnings.isEmpty {
            var interests = "### Interests\n"
            for learning in interestLearnings.prefix(5) {
                interests += "- **\(learning.title)**: \(learning.description)\n"
            }
            sections.append(interests)
        }

        // Patterns section
        let patternLearnings = learnings(for: .pattern)
        if !patternLearnings.isEmpty {
            var patterns = "### Patterns\n"
            for learning in patternLearnings.prefix(5) {
                patterns += "- **\(learning.title)**: \(learning.description)\n"
            }
            sections.append(patterns)
        }

        if sections.isEmpty {
            return "No learnings yet. Start indexing to build your profile."
        }

        return sections.joined(separator: "\n")
    }
}

// MARK: - Profile Learning

/// A single thing we've learned about the user.
public struct ProfileLearning: Codable, Identifiable, Sendable {
    public let id: UUID

    /// Category of learning (work, interest, pattern)
    public let category: LearningCategory

    /// Short title (e.g., "Swift Developer")
    public let title: String

    /// Longer description (e.g., "Works primarily with Swift and iOS development")
    public let description: String

    /// Evidence supporting this learning (file paths, conversation excerpts)
    public let evidence: [String]

    /// Confidence level (0.0 to 1.0)
    public let confidence: Double

    /// When we learned this
    public let learnedAt: Date

    /// How we learned this
    public let source: LearningSource

    public init(
        id: UUID = UUID(),
        category: LearningCategory,
        title: String,
        description: String,
        evidence: [String] = [],
        confidence: Double,
        learnedAt: Date = Date(),
        source: LearningSource
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.description = description
        self.evidence = evidence
        self.confidence = min(1.0, max(0.0, confidence))  // Clamp to [0, 1]
        self.learnedAt = learnedAt
        self.source = source
    }
}

// MARK: - Learning Category

/// Categories of user learnings.
public enum LearningCategory: String, Codable, Sendable, CaseIterable {
    /// Work-related (profession, skills, tools)
    case work

    /// Personal interests (hobbies, topics)
    case interest

    /// Behavioral patterns (work style, preferences)
    case pattern

    /// General information
    case general

    public var displayName: String {
        switch self {
        case .work: return "Work"
        case .interest: return "Interests"
        case .pattern: return "Patterns"
        case .general: return "General"
        }
    }

    public var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .interest: return "heart.fill"
        case .pattern: return "chart.bar.fill"
        case .general: return "info.circle.fill"
        }
    }
}

// MARK: - Learning Source

/// How a learning was acquired.
public enum LearningSource: Codable, Sendable {
    /// Discovered during file system indexing
    case indexing(date: Date)

    /// Learned from a conversation with an agent
    case conversation(threadId: String, agentName: String)

    /// Explicitly provided by the user
    case userProvided

    /// Inferred from multiple sources
    case inferred

    public var displayName: String {
        switch self {
        case .indexing: return "File Indexing"
        case .conversation(_, let agent): return "Conversation with \(agent)"
        case .userProvided: return "User Provided"
        case .inferred: return "Inferred"
        }
    }
}
