import Foundation

// MARK: - User Profile Store

/// Persistence layer for the user profile.
///
/// Stores the profile as a markdown file with YAML frontmatter at:
/// `~/.envoy/Spaces/about-me/profile.md`
///
/// The file format is human-readable and editable:
/// ```markdown
/// ---
/// version: 1
/// lastIndexed: 2025-01-16T10:30:00Z
/// lastUpdated: 2025-01-16T10:30:00Z
/// ---
/// # About You
///
/// ## Work
/// - **Software Developer**: Works with Swift and iOS...
///
/// ## Interests
/// - **Photography**: Active interest in photography...
/// ```
public actor UserProfileStore {

    // MARK: - Properties

    private var profile: UserProfile
    private let profilePath: URL
    private var isDirty = false

    /// Default path for the profile file
    public static var defaultProfilePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".envoy")
            .appendingPathComponent("Spaces")
            .appendingPathComponent("about-me")
            .appendingPathComponent("profile.md")
    }

    // MARK: - Initialization

    public init(profilePath: URL? = nil) {
        self.profilePath = profilePath ?? Self.defaultProfilePath
        self.profile = UserProfile()
    }

    /// Load the profile from disk
    public func load() async throws {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: profilePath.path) else {
            // No profile yet, start fresh
            profile = UserProfile()
            return
        }

        let content = try String(contentsOf: profilePath, encoding: .utf8)
        profile = try parseProfile(from: content)
    }

    /// Save the profile to disk
    public func save() async throws {
        // Ensure directory exists
        let directory = profilePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Generate markdown content
        let content = generateMarkdown(from: profile)

        // Write to disk
        try content.write(to: profilePath, atomically: true, encoding: .utf8)
        isDirty = false
    }

    /// Save if there are unsaved changes
    public func saveIfNeeded() async throws {
        if isDirty {
            try await save()
        }
    }

    // MARK: - Profile Access

    /// Get the current profile
    public var currentProfile: UserProfile {
        profile
    }

    /// Get all learnings
    public var learnings: [ProfileLearning] {
        profile.learnings
    }

    /// Get learnings by category
    public func learnings(for category: LearningCategory) -> [ProfileLearning] {
        profile.learnings(for: category)
    }

    /// Get high-confidence learnings
    public var highConfidenceLearnings: [ProfileLearning] {
        profile.highConfidenceLearnings
    }

    // MARK: - Profile Updates

    /// Add a new learning
    public func addLearning(_ learning: ProfileLearning) {
        // Check for duplicates by title
        if profile.learnings.contains(where: { $0.title == learning.title && $0.category == learning.category }) {
            // Update existing instead of duplicate
            updateLearning(matching: learning.title, with: learning)
            return
        }

        profile.learnings.append(learning)
        profile.lastUpdated = Date()
        isDirty = true
    }

    /// Add multiple learnings
    public func addLearnings(_ learnings: [ProfileLearning]) {
        for learning in learnings {
            addLearning(learning)
        }
    }

    /// Update an existing learning by title
    public func updateLearning(matching title: String, with updated: ProfileLearning) {
        if let index = profile.learnings.firstIndex(where: { $0.title == title }) {
            profile.learnings[index] = updated
            profile.lastUpdated = Date()
            isDirty = true
        }
    }

    /// Remove a learning
    public func removeLearning(_ id: UUID) {
        profile.learnings.removeAll { $0.id == id }
        profile.lastUpdated = Date()
        isDirty = true
    }

    /// Clear all learnings
    public func clearLearnings() {
        profile.learnings.removeAll()
        profile.lastUpdated = Date()
        isDirty = true
    }

    /// Mark indexing as complete
    public func markIndexingComplete() {
        profile.lastIndexed = Date()
        profile.lastUpdated = Date()
        isDirty = true
    }

    // MARK: - Profile Summary

    /// Generate a human-readable summary
    public func generateSummary() -> String {
        profile.generateSummary()
    }

    // MARK: - Markdown Parsing/Generation

    private func parseProfile(from content: String) throws -> UserProfile {
        // Split frontmatter and body
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else {
            // No frontmatter, just body
            return UserProfile()
        }

        let frontmatter = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        // let body = parts[2...].joined(separator: "---")

        // Parse YAML frontmatter
        var version = 1
        var lastIndexed: Date?
        var lastUpdated = Date()

        for line in frontmatter.split(separator: "\n") {
            let keyValue = line.split(separator: ":", maxSplits: 1)
            guard keyValue.count == 2 else { continue }

            let key = keyValue[0].trimmingCharacters(in: .whitespaces)
            let value = keyValue[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "version":
                version = Int(value) ?? 1
            case "lastIndexed":
                lastIndexed = ISO8601DateFormatter().date(from: value)
            case "lastUpdated":
                lastUpdated = ISO8601DateFormatter().date(from: value) ?? Date()
            default:
                break
            }
        }

        // TODO: Parse learnings from markdown body
        // For now, we only persist metadata in frontmatter
        // Learnings are stored separately in profile-learnings.json

        return UserProfile(
            learnings: try loadLearningsFromJSON(),
            lastIndexed: lastIndexed,
            lastUpdated: lastUpdated,
            version: version
        )
    }

    private func generateMarkdown(from profile: UserProfile) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var content = "---\n"
        content += "version: \(profile.version)\n"
        if let lastIndexed = profile.lastIndexed {
            content += "lastIndexed: \(formatter.string(from: lastIndexed))\n"
        }
        content += "lastUpdated: \(formatter.string(from: profile.lastUpdated))\n"
        content += "---\n\n"

        content += "# About You\n\n"

        if profile.learnings.isEmpty {
            content += "_No learnings yet. Start indexing or chat with an agent to build your profile._\n"
        } else {
            content += profile.generateSummary()
        }

        // Also save learnings to JSON for structured access
        Task {
            try? await saveLearningsToJSON()
        }

        return content
    }

    // MARK: - JSON Persistence for Learnings

    private var learningsJSONPath: URL {
        profilePath
            .deletingLastPathComponent()
            .appendingPathComponent("profile-learnings.json")
    }

    private func loadLearningsFromJSON() throws -> [ProfileLearning] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: learningsJSONPath.path) else {
            return []
        }

        let data = try Data(contentsOf: learningsJSONPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ProfileLearning].self, from: data)
    }

    private func saveLearningsToJSON() async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(profile.learnings)
        try data.write(to: learningsJSONPath)
    }
}

// MARK: - Convenience Extensions

extension UserProfileStore {

    /// Add a learning from indexing
    public func addFromIndexing(
        category: LearningCategory,
        title: String,
        description: String,
        evidence: [String] = [],
        confidence: Double
    ) {
        let learning = ProfileLearning(
            category: category,
            title: title,
            description: description,
            evidence: evidence,
            confidence: confidence,
            source: .indexing(date: Date())
        )
        addLearning(learning)
    }

    /// Add a learning from a conversation
    public func addFromConversation(
        category: LearningCategory,
        title: String,
        description: String,
        threadId: String,
        agentName: String,
        confidence: Double
    ) {
        let learning = ProfileLearning(
            category: category,
            title: title,
            description: description,
            confidence: confidence,
            source: .conversation(threadId: threadId, agentName: agentName)
        )
        addLearning(learning)
    }
}
