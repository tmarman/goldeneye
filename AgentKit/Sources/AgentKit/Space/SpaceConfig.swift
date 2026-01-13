import Foundation

// MARK: - Linked Space

/// A linked external space (code repo or content workspace)
/// Referenced in place - no cloning. Claude Code handles its own worktrees.
/// Stored in ~/.agents/spaces.json
public struct LinkedSpace: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let path: URL                    // Reference to original location (no cloning)
    public let type: SpaceType
    public let defaultRunner: TaskRunner
    public let linkedAt: Date

    // Git info (if applicable)
    public var gitRemote: String?
    public var defaultBranch: String?

    // Optional metadata
    public var description: String?
    public var tags: [String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        path: URL,
        type: SpaceType,
        defaultRunner: TaskRunner? = nil,
        linkedAt: Date = Date(),
        gitRemote: String? = nil,
        defaultBranch: String? = nil,
        description: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.type = type
        self.defaultRunner = defaultRunner ?? type.defaultRunner
        self.linkedAt = linkedAt
        self.gitRemote = gitRemote
        self.defaultBranch = defaultBranch
        self.description = description
        self.tags = tags
    }
}

// MARK: - Space Type

/// The type of content a space primarily contains
public enum SpaceType: String, Codable, Sendable, CaseIterable {
    case code           // Software project - route to CLI agents
    case content        // Documents, writing - route to content agents
    case mixed          // Both code and content

    /// Default task runner for this space type
    public var defaultRunner: TaskRunner {
        switch self {
        case .code: return .claudeCode
        case .content: return .contentAgent
        case .mixed: return .auto
        }
    }

    /// Display name
    public var displayName: String {
        switch self {
        case .code: return "Code Repository"
        case .content: return "Content Workspace"
        case .mixed: return "Mixed Project"
        }
    }

    /// SF Symbol icon
    public var icon: String {
        switch self {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .content: return "doc.text"
        case .mixed: return "square.grid.2x2"
        }
    }
}

// MARK: - Task Runner

/// How tasks should be executed in this space
public enum TaskRunner: String, Codable, Sendable, CaseIterable {
    case claudeCode     // Route to Claude Code CLI (handles its own worktrees)
    case contentAgent   // Route to normal agent flow
    case auto           // Analyze task and decide

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .contentAgent: return "Content Agent"
        case .auto: return "Auto-detect"
        }
    }

    public var icon: String {
        switch self {
        case .claudeCode: return "terminal"
        case .contentAgent: return "person.crop.circle"
        case .auto: return "sparkles"
        }
    }
}

// MARK: - Space Registry

/// Manages the registry of linked spaces
/// Stores in ~/.agents/spaces.json
public actor SpaceRegistry {
    public static let shared = SpaceRegistry()

    private var spaces: [String: LinkedSpace] = [:]
    private let storageURL: URL

    public init() {
        let agentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents")
        self.storageURL = agentsDir.appendingPathComponent("spaces.json")
    }

    // MARK: - CRUD Operations

    /// Link a new space (folder) to the registry
    public func linkSpace(
        name: String,
        path: URL,
        type: SpaceType,
        defaultRunner: TaskRunner? = nil
    ) async throws -> LinkedSpace {
        // Detect git info if present
        let (remote, branch) = await detectGitInfo(at: path)

        let config = LinkedSpace(
            name: name,
            path: path,
            type: type,
            defaultRunner: defaultRunner,
            gitRemote: remote,
            defaultBranch: branch
        )

        spaces[config.id] = config
        try await save()

        return config
    }

    /// Unlink a space from the registry
    public func unlinkSpace(_ id: String) async throws {
        spaces.removeValue(forKey: id)
        try await save()
    }

    /// Get a space by ID
    public func getSpace(_ id: String) -> LinkedSpace? {
        spaces[id]
    }

    /// Get a space by path
    public func getSpace(at path: URL) -> LinkedSpace? {
        spaces.values.first { $0.path == path }
    }

    /// List all linked spaces
    public func listSpaces() -> [LinkedSpace] {
        Array(spaces.values).sorted { $0.name < $1.name }
    }

    /// Update a space's configuration
    public func updateSpace(_ config: LinkedSpace) async throws {
        spaces[config.id] = config
        try await save()
    }

    // MARK: - Persistence

    public func load() async throws {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return
        }

        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode([LinkedSpace].self, from: data)

        spaces = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
    }

    private func save() async throws {
        // Ensure directory exists
        let dir = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(Array(spaces.values))
        try data.write(to: storageURL)
    }

    // MARK: - Git Detection

    private func detectGitInfo(at path: URL) async -> (remote: String?, branch: String?) {
        // Check if it's a git repo
        let gitDir = path.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            return (nil, nil)
        }

        // Get remote
        let remote = try? await runGit(["config", "--get", "remote.origin.url"], at: path)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Get default branch
        let branch = try? await runGit(["symbolic-ref", "--short", "HEAD"], at: path)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (remote, branch)
    }

    private func runGit(_ args: [String], at directory: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Task Routing

extension LinkedSpace {
    /// Determine how to run a task in this space
    public func routeTask(_ prompt: String) -> TaskRunner {
        switch defaultRunner {
        case .auto:
            return analyzePromptForRouting(prompt)
        default:
            return defaultRunner
        }
    }

    /// Simple heuristic to determine task routing
    /// TODO: This is where you could add smarter analysis
    private func analyzePromptForRouting(_ prompt: String) -> TaskRunner {
        let codeKeywords = [
            "implement", "fix", "refactor", "debug", "test", "build",
            "code", "function", "class", "bug", "error", "compile",
            "deploy", "api", "endpoint", "database", "migration"
        ]

        let lowercased = prompt.lowercased()
        let codeScore = codeKeywords.filter { lowercased.contains($0) }.count

        // If it looks like a coding task, use Claude Code
        return codeScore >= 2 ? .claudeCode : .contentAgent
    }
}
