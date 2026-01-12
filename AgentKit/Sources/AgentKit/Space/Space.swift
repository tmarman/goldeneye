import Foundation

// MARK: - Space

/// A Space is a Git-backed container for documents and agent collaboration.
///
/// Think of it as "GitHub for regular people":
/// - Documents are versioned artifacts (markdown, etc.)
/// - Agents can own or contribute to spaces
/// - Spaces can contain child spaces (like folders or submodules)
/// - Decision Cards are like Pull Requests for reviewing changes
///
/// Under the hood, each Space is a Git repository, giving us:
/// - Full version history
/// - Branching and merging
/// - Diffing and blame
/// - Distributed collaboration
public actor Space: Identifiable {
    public nonisolated let id: SpaceID
    public nonisolated let name: String
    public private(set) var localPath: URL  // Local Git repo path

    // Ownership & Access
    private var _owner: SpaceOwner
    private var _contributors: [AgentID: ContributorRole] = [:]

    // Contents
    private var _documents: [DocumentID: Document] = [:]
    private var _childSpaces: [SpaceID: Space] = [:]
    private var _decisionCards: [DecisionCardID: DecisionCard] = [:]

    // Metadata
    public nonisolated let createdAt: Date
    private var _updatedAt: Date
    private var _metadata: [String: String] = [:]

    // Display properties (nonisolated for UI access)
    public nonisolated let description: String?
    public nonisolated let icon: String
    public nonisolated let color: SpaceColor
    public private(set) var isStarred: Bool = false
    public private(set) var isArchived: Bool = false
    public private(set) var remoteURL: URL?

    // Git integration
    private var gitManager: GitManager?

    /// Full initializer with all properties
    public init(
        id: SpaceID = SpaceID(),
        name: String,
        description: String? = nil,
        localPath: URL,
        owner: SpaceOwner,
        icon: String = "folder",
        color: SpaceColor = .blue,
        remoteURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.localPath = localPath
        self._owner = owner
        self.icon = icon
        self.color = color
        self.remoteURL = remoteURL
        self.createdAt = Date()
        self._updatedAt = Date()

        // GitManager will be lazily initialized when needed
        self.gitManager = nil
    }

    /// Async initializer that also initializes Git
    public init(
        id: SpaceID = SpaceID(),
        name: String,
        description: String? = nil,
        localPath: URL,
        owner: SpaceOwner,
        icon: String = "folder",
        color: SpaceColor = .blue,
        initializeGit: Bool
    ) async throws {
        self.id = id
        self.name = name
        self.description = description
        self.localPath = localPath
        self._owner = owner
        self.icon = icon
        self.color = color
        self.createdAt = Date()
        self._updatedAt = Date()

        if initializeGit {
            self.gitManager = try await GitManager(path: localPath)
        }
    }

    // MARK: - Star/Archive

    public func star() {
        isStarred = true
        _updatedAt = Date()
    }

    public func unstar() {
        isStarred = false
        _updatedAt = Date()
    }

    public func archive(to newPath: URL) {
        localPath = newPath
        isArchived = true
        _updatedAt = Date()
    }

    public func unarchive(to newPath: URL) {
        localPath = newPath
        isArchived = false
        _updatedAt = Date()
    }

    /// Get the local path (for external access)
    public func getLocalPath() -> URL {
        localPath
    }

    // MARK: - Remote

    public func setRemote(_ url: URL?) {
        remoteURL = url
        _updatedAt = Date()
    }

    // MARK: - Ownership & Access

    public var owner: SpaceOwner { _owner }

    public func setOwner(_ newOwner: SpaceOwner) {
        _owner = newOwner
        _updatedAt = Date()
    }

    public func addContributor(_ agentId: AgentID, role: ContributorRole) {
        _contributors[agentId] = role
        _updatedAt = Date()
    }

    public func removeContributor(_ agentId: AgentID) {
        _contributors.removeValue(forKey: agentId)
        _updatedAt = Date()
    }

    public func contributors() -> [AgentID: ContributorRole] {
        _contributors
    }

    public func canWrite(_ agentId: AgentID) -> Bool {
        if case .agent(let ownerId) = _owner, ownerId == agentId {
            return true
        }
        guard let role = _contributors[agentId] else { return false }
        return role == .editor || role == .maintainer
    }

    public func canApprove(_ agentId: AgentID) -> Bool {
        if case .agent(let ownerId) = _owner, ownerId == agentId {
            return true
        }
        return _contributors[agentId] == .maintainer
    }

    // MARK: - Documents

    public func documents() -> [Document] {
        Array(_documents.values)
    }

    public func document(_ id: DocumentID) -> Document? {
        _documents[id]
    }

    public func addDocument(_ document: Document, by agentId: AgentID? = nil) async throws {
        _documents[document.id] = document
        _updatedAt = Date()

        // Commit to Git if manager is available
        if let gitManager {
            let message = "Add document: \(document.title)"
            try await gitManager.commitDocument(document, message: message, author: agentId)
        }
    }

    public func updateDocument(_ document: Document, by agentId: AgentID? = nil) async throws {
        guard _documents[document.id] != nil else {
            throw SpaceError.documentNotFound(document.id)
        }
        _documents[document.id] = document
        _updatedAt = Date()

        // Commit to Git if manager is available
        if let gitManager {
            let message = "Update document: \(document.title)"
            try await gitManager.commitDocument(document, message: message, author: agentId)
        }
    }

    public func removeDocument(_ id: DocumentID, by agentId: AgentID? = nil) async throws {
        guard let document = _documents.removeValue(forKey: id) else {
            throw SpaceError.documentNotFound(id)
        }
        _updatedAt = Date()

        // Commit deletion to Git if manager is available
        if let gitManager {
            let message = "Remove document: \(document.title)"
            try await gitManager.removeDocument(document, message: message, author: agentId)
        }
    }

    // MARK: - Child Spaces

    public func childSpaces() -> [Space] {
        Array(_childSpaces.values)
    }

    public func addChildSpace(_ space: Space) {
        _childSpaces[space.id] = space
        _updatedAt = Date()
    }

    public func removeChildSpace(_ id: SpaceID) {
        _childSpaces.removeValue(forKey: id)
        _updatedAt = Date()
    }

    // MARK: - Decision Cards (PRs)

    public func decisionCards() -> [DecisionCard] {
        Array(_decisionCards.values)
    }

    public func pendingDecisions() -> [DecisionCard] {
        _decisionCards.values.filter { $0.isActionable }
    }

    public func addDecisionCard(_ card: DecisionCard) {
        _decisionCards[card.id] = card
        _updatedAt = Date()
    }

    public func updateDecisionCard(_ card: DecisionCard) {
        _decisionCards[card.id] = card
        _updatedAt = Date()
    }

    // MARK: - Git Operations

    /// Ensure Git manager is initialized for operations that require it
    private func ensureGitManager() async throws -> GitManager {
        if let manager = gitManager {
            return manager
        }
        let manager = try await GitManager(path: localPath)
        gitManager = manager
        return manager
    }

    /// Get version history for a document
    public func history(for documentId: DocumentID) async throws -> [CommitInfo] {
        let manager = try await ensureGitManager()
        return try await manager.history(for: documentId)
    }

    /// Get the diff between two versions
    public func diff(documentId: DocumentID, from: String, to: String) async throws -> String {
        let manager = try await ensureGitManager()
        return try await manager.diff(documentId: documentId, from: from, to: to)
    }

    /// Create a branch for experimentation
    public func createBranch(_ name: String) async throws {
        let manager = try await ensureGitManager()
        try await manager.createBranch(name)
    }

    /// List branches
    public func branches() async throws -> [String] {
        let manager = try await ensureGitManager()
        return try await manager.branches()
    }

    /// Switch to a branch
    public func checkout(_ branch: String) async throws {
        let manager = try await ensureGitManager()
        try await manager.checkout(branch)
    }
}

// MARK: - Supporting Types

public struct SpaceID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// Who owns a space
public enum SpaceOwner: Codable, Sendable, Equatable {
    case user               // Current human user (default)
    case namedUser(String)  // Specific named user
    case agent(AgentID)     // Agent owns this space

    public var displayName: String {
        switch self {
        case .user: return "You"
        case .namedUser(let name): return name
        case .agent(let id): return "Agent \(id.rawValue.prefix(8))"
        }
    }
}

/// Color theme for a Space
public enum SpaceColor: String, Codable, Sendable, CaseIterable {
    case blue, purple, green, orange, pink, cyan, red, yellow, gray
}

/// Role of a contributor agent
public enum ContributorRole: String, Codable, Sendable {
    case reader      // Can view only
    case editor      // Can make changes (creates Decision Cards if not owner)
    case maintainer  // Can approve Decision Cards
}

/// Information about a Git commit
public struct CommitInfo: Identifiable, Codable, Sendable {
    public let id: String  // commit hash
    public let message: String
    public let author: String
    public let date: Date
    public let changes: [String]  // files changed

    public init(id: String, message: String, author: String, date: Date, changes: [String] = []) {
        self.id = id
        self.message = message
        self.author = author
        self.date = date
        self.changes = changes
    }
}

/// Errors that can occur in Space operations
public enum SpaceError: Error, Sendable {
    case documentNotFound(DocumentID)
    case spaceNotFound(SpaceID)
    case permissionDenied(AgentID, String)
    case gitError(String)
}

// MARK: - Git Manager

/// Manages Git operations for a Space
actor GitManager {
    let path: URL

    init(path: URL) async throws {
        self.path = path

        // Initialize repo if it doesn't exist
        if !FileManager.default.fileExists(atPath: path.appendingPathComponent(".git").path) {
            try await initRepo()
        }
    }

    private func initRepo() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = path
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SpaceError.gitError("Failed to initialize Git repository")
        }
    }

    func commitDocument(_ document: Document, message: String, author: AgentID?) async throws {
        // Write document to file
        let filePath = path.appendingPathComponent("\(document.id.rawValue).md")
        let content = document.toMarkdown()
        try content.write(to: filePath, atomically: true, encoding: .utf8)

        // Git add
        try await runGit(["add", filePath.lastPathComponent])

        // Git commit
        var commitArgs = ["commit", "-m", message]
        if let author {
            commitArgs += ["--author", "Agent <\(author.rawValue)@agent.local>"]
        }
        try await runGit(commitArgs)
    }

    func removeDocument(_ document: Document, message: String, author: AgentID?) async throws {
        let filePath = path.appendingPathComponent("\(document.id.rawValue).md")

        // Git rm
        try await runGit(["rm", filePath.lastPathComponent])

        // Git commit
        var commitArgs = ["commit", "-m", message]
        if let author {
            commitArgs += ["--author", "Agent <\(author.rawValue)@agent.local>"]
        }
        try await runGit(commitArgs)
    }

    func history(for documentId: DocumentID) async throws -> [CommitInfo] {
        let output = try await runGit([
            "log", "--pretty=format:%H|%s|%an|%aI",
            "--", "\(documentId.rawValue).md"
        ])

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 3)
            guard parts.count == 4,
                  let date = ISO8601DateFormatter().date(from: String(parts[3])) else {
                return nil
            }
            return CommitInfo(
                id: String(parts[0]),
                message: String(parts[1]),
                author: String(parts[2]),
                date: date
            )
        }
    }

    func diff(documentId: DocumentID, from: String, to: String) async throws -> String {
        try await runGit(["diff", from, to, "--", "\(documentId.rawValue).md"])
    }

    func createBranch(_ name: String) async throws {
        try await runGit(["checkout", "-b", name])
    }

    func branches() async throws -> [String] {
        let output = try await runGit(["branch", "--list"])
        return output.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "* ", with: "")
        }
    }

    func checkout(_ branch: String) async throws {
        try await runGit(["checkout", branch])
    }

    @discardableResult
    private func runGit(_ args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = path

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Document Extension

extension Document {
    /// Convert document to Markdown for Git storage
    func toMarkdown() -> String {
        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("id: \(id.rawValue)")
        lines.append("title: \(title)")
        lines.append("created: \(ISO8601DateFormatter().string(from: createdAt))")
        lines.append("updated: \(ISO8601DateFormatter().string(from: updatedAt))")
        if !tagIds.isEmpty {
            lines.append("tags: [\(tagIds.map { $0.rawValue }.joined(separator: ", "))]")
        }
        lines.append("---")
        lines.append("")

        // Content from blocks
        for block in blocks {
            lines.append(block.toMarkdown())
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

extension Block {
    func toMarkdown() -> String {
        switch self {
        case .text(let block):
            return block.content
        case .heading(let block):
            let prefix = String(repeating: "#", count: block.level.rawValue)
            return "\(prefix) \(block.content)"
        case .bulletList(let block):
            return block.items.map { "- \($0.content)" }.joined(separator: "\n")
        case .numberedList(let block):
            return block.items.enumerated().map { "\($0.offset + 1). \($0.element.content)" }.joined(separator: "\n")
        case .todo(let block):
            return block.items.map { item in
                let checkbox = item.isCompleted ? "[x]" : "[ ]"
                return "- \(checkbox) \(item.content)"
            }.joined(separator: "\n")
        case .code(let block):
            return "```\(block.language ?? "")\n\(block.content)\n```"
        case .quote(let block):
            let lines = block.content.split(separator: "\n")
            var result = lines.map { "> \($0)" }.joined(separator: "\n")
            if let attribution = block.attribution {
                result += "\n> — \(attribution)"
            }
            return result
        case .divider(_):
            return "---"
        case .callout(let block):
            return "> \(block.icon) **\(block.style.rawValue.capitalized):** \(block.content)"
        case .image(let block):
            return "![\(block.caption ?? "")](\(block.url?.absoluteString ?? ""))"
        case .agent(let block):
            return "<!-- agent:\(block.agentId?.rawValue ?? "none") -->\n\(block.content)\n<!-- /agent -->"
        }
    }
}
