import Foundation

// MARK: - Workspace Store

/// File-based storage for the entire workspace hierarchy.
///
/// Directory structure:
/// ```
/// ~/.envoy/
/// ├── Spaces/
/// │   ├── {space-name}/
/// │   │   ├── space.md           # Space metadata
/// │   │   └── .threads/
/// │   │       └── {date}-{id}.md # Thread files
/// ├── Agents/
/// │   ├── {agent-name}/
/// │   │   ├── agent.md           # Agent definition
/// │   │   └── .threads/          # DMs with this agent
/// │   │       └── {date}-{id}.md
/// ├── Groups/
/// │   ├── {hash}/
/// │   │   ├── group.md           # Group metadata
/// │   │   └── .threads/          # Group DM threads
/// └── Skills/
///     └── {skill-name}.md        # Skill definitions
/// ```
public actor WorkspaceStore {

    // MARK: - Properties

    /// Root directory for all workspace data
    public let rootPath: String

    /// File manager for file operations
    private let fileManager = FileManager.default

    // MARK: - Path Constants

    private var spacesPath: String { "\(rootPath)/Spaces" }
    private var agentsPath: String { "\(rootPath)/Agents" }
    private var groupsPath: String { "\(rootPath)/Groups" }
    private var skillsPath: String { "\(rootPath)/Skills" }

    // MARK: - Initialization

    public init(rootPath: String? = nil) {
        if let path = rootPath {
            self.rootPath = path
        } else {
            // Default to ~/.envoy
            let home = fileManager.homeDirectoryForCurrentUser.path
            self.rootPath = "\(home)/.envoy"
        }
    }

    /// Ensure the workspace directory structure exists
    public func initialize() throws {
        try createDirectoryIfNeeded(rootPath)
        try createDirectoryIfNeeded(spacesPath)
        try createDirectoryIfNeeded(agentsPath)
        try createDirectoryIfNeeded(groupsPath)
        try createDirectoryIfNeeded(skillsPath)
    }

    // MARK: - Agent Operations

    /// List all agents in the workspace
    public func listAgents() throws -> [MarkdownAgentSpec] {
        let agentDirs = try fileManager.contentsOfDirectory(atPath: agentsPath)
        var agents: [MarkdownAgentSpec] = []

        for dir in agentDirs where !dir.hasPrefix(".") {
            let agentPath = "\(agentsPath)/\(dir)/agent.md"
            if fileManager.fileExists(atPath: agentPath) {
                if let agent = try? loadAgent(named: dir) {
                    agents.append(agent)
                }
            }
        }

        return agents.sorted { $0.name < $1.name }
    }

    /// Load a specific agent by name
    public func loadAgent(named name: String) throws -> MarkdownAgentSpec {
        let path = agentPath(for: name)
        return try MarkdownAgentSpec.load(from: path)
    }

    /// Save an agent definition
    public func saveAgent(_ agent: MarkdownAgentSpec) throws {
        let dirPath = "\(agentsPath)/\(agent.name)"
        try createDirectoryIfNeeded(dirPath)
        try createDirectoryIfNeeded("\(dirPath)/.threads")

        let path = "\(dirPath)/agent.md"
        try agent.save(to: path)
    }

    /// Delete an agent and all its threads
    public func deleteAgent(named name: String) throws {
        let dirPath = "\(agentsPath)/\(name)"
        if fileManager.fileExists(atPath: dirPath) {
            try fileManager.removeItem(atPath: dirPath)
        }
    }

    /// Get the path to an agent's definition file
    public func agentPath(for name: String) -> String {
        return "\(agentsPath)/\(name)/agent.md"
    }

    // MARK: - Space Operations

    /// List all spaces in the workspace
    public func listSpaces() throws -> [EnvoySpaceInfo] {
        let spaceDirs = try fileManager.contentsOfDirectory(atPath: spacesPath)
        var spaces: [EnvoySpaceInfo] = []

        for dir in spaceDirs where !dir.hasPrefix(".") {
            let spacePath = "\(spacesPath)/\(dir)/space.md"
            if fileManager.fileExists(atPath: spacePath) {
                if let space = try? loadEnvoySpaceInfo(named: dir) {
                    spaces.append(space)
                }
            }
        }

        return spaces.sorted { $0.name < $1.name }
    }

    /// Load space metadata
    public func loadEnvoySpaceInfo(named name: String) throws -> EnvoySpaceInfo {
        let path = "\(spacesPath)/\(name)/space.md"
        return try EnvoySpaceInfo.load(from: path)
    }

    /// Save space metadata
    public func saveSpace(_ space: EnvoySpaceInfo) throws {
        let dirPath = "\(spacesPath)/\(space.name)"
        try createDirectoryIfNeeded(dirPath)
        try createDirectoryIfNeeded("\(dirPath)/.threads")

        let path = "\(dirPath)/space.md"
        try space.save(to: path)
    }

    // MARK: - Thread Operations

    /// List threads for an agent (DMs)
    public func listAgentThreads(agentName: String) throws -> [Thread] {
        let threadsPath = "\(agentsPath)/\(agentName)/.threads"
        return try loadThreads(from: threadsPath)
    }

    /// List threads for a space
    public func listSpaceThreads(spaceName: String) throws -> [Thread] {
        let threadsPath = "\(spacesPath)/\(spaceName)/.threads"
        return try loadThreads(from: threadsPath)
    }

    /// List threads for a group DM
    public func listGroupThreads(groupId: String) throws -> [Thread] {
        let threadsPath = "\(groupsPath)/\(groupId)/.threads"
        return try loadThreads(from: threadsPath)
    }

    /// Load all threads from a directory
    private func loadThreads(from path: String) throws -> [Thread] {
        guard fileManager.fileExists(atPath: path) else {
            return []
        }

        let files = try fileManager.contentsOfDirectory(atPath: path)
        var threads: [Thread] = []

        for file in files where file.hasSuffix(".md") {
            let filePath = "\(path)/\(file)"
            if let thread = try? Thread.load(from: filePath) {
                threads.append(thread)
            }
        }

        return threads.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Save a thread to an agent's DM folder
    public func saveAgentThread(_ thread: Thread, agentName: String) throws {
        let dirPath = "\(agentsPath)/\(agentName)/.threads"
        try createDirectoryIfNeeded(dirPath)
        let path = "\(dirPath)/\(thread.suggestedFilename)"
        try thread.save(to: path)
    }

    /// Save a thread to a space
    public func saveSpaceThread(_ thread: Thread, spaceName: String) throws {
        let dirPath = "\(spacesPath)/\(spaceName)/.threads"
        try createDirectoryIfNeeded(dirPath)
        let path = "\(dirPath)/\(thread.suggestedFilename)"
        try thread.save(to: path)
    }

    /// Save a thread to a group DM
    public func saveGroupThread(_ thread: Thread, groupId: String) throws {
        let dirPath = "\(groupsPath)/\(groupId)/.threads"
        try createDirectoryIfNeeded(dirPath)
        let path = "\(dirPath)/\(thread.suggestedFilename)"
        try thread.save(to: path)
    }

    // MARK: - Group Operations

    /// Create a group ID from participant names
    public func groupId(for participants: [String]) -> String {
        let sorted = participants.sorted()
        let combined = sorted.joined(separator: ",")
        // Create a short hash
        var hasher = Hasher()
        hasher.combine(combined)
        let hash = abs(hasher.finalize())
        return String(hash, radix: 16)
    }

    /// List all groups
    public func listGroups() throws -> [EnvoyGroupInfo] {
        guard fileManager.fileExists(atPath: groupsPath) else {
            return []
        }

        let groupDirs = try fileManager.contentsOfDirectory(atPath: groupsPath)
        var groups: [EnvoyGroupInfo] = []

        for dir in groupDirs where !dir.hasPrefix(".") {
            let metaPath = "\(groupsPath)/\(dir)/group.md"
            if fileManager.fileExists(atPath: metaPath) {
                if let group = try? EnvoyGroupInfo.load(from: metaPath) {
                    groups.append(group)
                }
            }
        }

        return groups.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Helpers

    private func createDirectoryIfNeeded(_ path: String) throws {
        if !fileManager.fileExists(atPath: path) {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Space Metadata

/// Metadata for a space (stored in space.md)
public struct EnvoySpaceInfo: Codable, Sendable {
    public let id: String
    public var name: String
    public var description: String?
    public var icon: String?
    public var color: String?
    public var members: [String]  // Agent names
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        icon: String? = nil,
        color: String? = nil,
        members: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.members = members
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func load(from path: String) throws -> EnvoySpaceInfo {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)

        guard let content = String(data: data, encoding: .utf8) else {
            throw WorkspaceStoreError.invalidEncoding
        }

        let document = FrontmatterParser.parse(content)

        guard let name = document.string("name") else {
            throw WorkspaceStoreError.missingName
        }

        return EnvoySpaceInfo(
            id: document.string("id") ?? UUID().uuidString,
            name: name,
            description: document.string("description"),
            icon: document.string("icon"),
            color: document.string("color"),
            members: document.stringArray("members") ?? [],
            createdAt: document.date("created") ?? Date(),
            updatedAt: document.date("updated") ?? Date()
        )
    }

    public func save(to path: String) throws {
        var frontmatter: [String: Any] = [
            "id": id,
            "name": name
        ]

        if let description = description {
            frontmatter["description"] = description
        }
        if let icon = icon {
            frontmatter["icon"] = icon
        }
        if let color = color {
            frontmatter["color"] = color
        }
        if !members.isEmpty {
            frontmatter["members"] = members
        }

        let formatter = ISO8601DateFormatter()
        frontmatter["created"] = formatter.string(from: createdAt)
        frontmatter["updated"] = formatter.string(from: updatedAt)

        let markdown = FrontmatterParser.createDocument(frontmatter: frontmatter, content: "")

        guard let data = markdown.data(using: .utf8) else {
            throw WorkspaceStoreError.invalidEncoding
        }

        let url = URL(fileURLWithPath: path)
        try data.write(to: url)
    }
}

// MARK: - Group Metadata

/// Metadata for a group DM (stored in group.md)
public struct EnvoyGroupInfo: Codable, Sendable {
    public let id: String
    public var name: String?
    public var participants: [String]  // Agent names + user
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String? = nil,
        participants: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.participants = participants
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func load(from path: String) throws -> EnvoyGroupInfo {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)

        guard let content = String(data: data, encoding: .utf8) else {
            throw WorkspaceStoreError.invalidEncoding
        }

        let document = FrontmatterParser.parse(content)

        guard let id = document.string("id") else {
            throw WorkspaceStoreError.missingId
        }

        return EnvoyGroupInfo(
            id: id,
            name: document.string("name"),
            participants: document.stringArray("participants") ?? [],
            createdAt: document.date("created") ?? Date(),
            updatedAt: document.date("updated") ?? Date()
        )
    }

    public func save(to path: String) throws {
        var frontmatter: [String: Any] = [
            "id": id,
            "participants": participants
        ]

        if let name = name {
            frontmatter["name"] = name
        }

        let formatter = ISO8601DateFormatter()
        frontmatter["created"] = formatter.string(from: createdAt)
        frontmatter["updated"] = formatter.string(from: updatedAt)

        let markdown = FrontmatterParser.createDocument(frontmatter: frontmatter, content: "")

        guard let data = markdown.data(using: .utf8) else {
            throw WorkspaceStoreError.invalidEncoding
        }

        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

// MARK: - Errors

public enum WorkspaceStoreError: Error, LocalizedError {
    case invalidEncoding
    case missingName
    case missingId
    case notFound

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "File encoding is not valid UTF-8"
        case .missingName:
            return "File is missing required 'name' field"
        case .missingId:
            return "File is missing required 'id' field"
        case .notFound:
            return "File not found"
        }
    }
}
