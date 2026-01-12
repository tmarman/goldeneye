import Foundation
import Logging

// MARK: - Agents Directory Structure

/// The Agents directory in iCloud contains:
/// ```
/// ~/iCloud/Agents/
/// ├── Team/                    # Agent definitions (prompts & config)
/// │   ├── agentkit/
/// │   │   ├── system.md       # System prompt (markdown)
/// │   │   └── config.json     # Model/provider config
/// │   ├── concierge/
/// │   └── coach/
/// └── Spaces/                  # Agent workspaces
///     ├── project-alpha/       # A workspace
///     │   ├── documents/
///     │   └── artifacts/
///     └── daily-notes/
/// ```

// MARK: - Agent Definition

/// An agent definition from the Team folder.
public struct AgentDefinition: Sendable {
    /// Unique identifier (folder name)
    public let id: String

    /// Path to the definition directory
    public let path: URL

    /// Loaded configuration
    public let config: AgentConfig

    /// System prompt content
    public let systemPrompt: String

    /// Load an agent definition from a directory
    public init(path: URL) throws {
        self.path = path
        self.id = path.lastPathComponent

        // Load config (optional - uses defaults if not present)
        let configPath = path.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configPath.path) {
            let configData = try Data(contentsOf: configPath)
            self.config = try JSONDecoder().decode(AgentConfig.self, from: configData)
        } else {
            self.config = AgentConfig()
        }

        // Load system prompt
        let promptPath = path.appendingPathComponent("system.md")
        if FileManager.default.fileExists(atPath: promptPath.path) {
            self.systemPrompt = try String(contentsOf: promptPath, encoding: .utf8)
        } else {
            self.systemPrompt = Self.defaultPrompt(for: id)
        }
    }

    /// Create a new agent definition
    public static func create(
        id: String,
        at teamPath: URL,
        config: AgentConfig = AgentConfig(),
        systemPrompt: String? = nil
    ) throws -> AgentDefinition {
        let defPath = teamPath.appendingPathComponent(id)

        try FileManager.default.createDirectory(at: defPath, withIntermediateDirectories: true)

        // Write config
        let configPath = defPath.appendingPathComponent("config.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let configData = try encoder.encode(config)
        try configData.write(to: configPath)

        // Write system prompt
        let promptPath = defPath.appendingPathComponent("system.md")
        let prompt = systemPrompt ?? defaultPrompt(for: id)
        try prompt.write(to: promptPath, atomically: true, encoding: .utf8)

        return try AgentDefinition(path: defPath)
    }

    // MARK: - Default Prompts

    private static func defaultPrompt(for agentId: String) -> String {
        switch agentId.lowercased() {
        case "agentkit":
            return """
                You are AgentKit, a helpful AI assistant running locally on Apple Silicon.

                You have access to file system and shell tools to help users with tasks.
                Always explain what you're doing before taking actions.
                Be concise but thorough in your responses.

                When working with files:
                - Read files before modifying them
                - Create backups of important files
                - Explain changes you're making

                When running commands:
                - Explain what each command does
                - Handle errors gracefully
                - Never run destructive commands without confirmation
                """

        case "concierge":
            return """
                You are the Concierge, the first point of contact for incoming requests.

                Your role is to:
                - Understand what the user needs
                - Route requests to appropriate specialist agents
                - Handle simple queries directly
                - Maintain context across conversations

                Be warm, helpful, and efficient. Ask clarifying questions when needed.
                """

        case "librarian":
            return """
                You are the Librarian, responsible for knowledge organization and retrieval.

                Your role is to:
                - Index and organize documents
                - Find relevant information quickly
                - Maintain the knowledge base
                - Suggest related content

                Be precise and thorough. Cite sources when providing information.
                """

        case "coach":
            return """
                You are a personal Coach focused on health, habits, and goals.

                Your role is to:
                - Track progress toward goals
                - Provide encouragement and accountability
                - Suggest improvements based on data
                - Celebrate wins and learn from setbacks

                Be supportive but honest. Focus on sustainable progress over perfection.
                """

        case "executor":
            return """
                You are the Executor, focused on getting things done.

                Your role is to:
                - Break down tasks into actionable steps
                - Execute tasks efficiently
                - Track progress and blockers
                - Report completion status

                Be systematic and reliable. Prioritize completing tasks over perfect solutions.
                """

        default:
            return """
                You are a helpful AI assistant.
                Be concise and accurate in your responses.
                """
        }
    }
}

// MARK: - Agent Config

/// Configuration for an agent
public struct AgentConfig: Codable, Sendable {
    /// Display name for the agent
    public var name: String?

    /// Agent description
    public var description: String?

    /// LLM provider to use (nil = use default)
    public var provider: String?

    /// Model to use (nil = use provider default)
    public var model: String?

    /// Provider base URL (for self-hosted)
    public var providerURL: String?

    /// Maximum iterations for agent loop
    public var maxIterations: Int?

    /// Tools enabled for this agent
    public var tools: [String]?

    /// Agent profile type
    public var profile: String?

    public init(
        name: String? = nil,
        description: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        providerURL: String? = nil,
        maxIterations: Int? = nil,
        tools: [String]? = nil,
        profile: String? = nil
    ) {
        self.name = name
        self.description = description
        self.provider = provider
        self.model = model
        self.providerURL = providerURL
        self.maxIterations = maxIterations
        self.tools = tools
        self.profile = profile
    }
}

// MARK: - Agent Workspace

/// An AgentWorkspace is a lightweight loader for git-backed spaces where agents work.
///
/// This is a simple data-loading struct that finds and parses convention files.
/// For full Space functionality (git operations, documents, contributors),
/// use the `Space` actor in Space/Space.swift.
///
/// Workspaces are repos with convention files that agents look for:
/// - `CLAUDE.md` - Project context (like Claude Code)
/// - `AGENTS.md` - Instructions for how agents should work in this space
/// - `HANDBOOK.md` - Rules, conventions, and guidelines
/// - `.space/config.json` - Space configuration
/// - `documents/` - Documents and files
/// - `artifacts/` - Agent-generated artifacts
///
/// Space owners define rules for how agents engage and organize.
public struct AgentWorkspace: Sendable {
    /// Unique identifier (folder name)
    public let id: String

    /// Path to the space directory (repo root)
    public let path: URL

    /// Space configuration
    public let config: SpaceConfig

    /// Convention files found in this space
    public let conventions: SpaceConventions

    /// Load a workspace from a directory
    public init(path: URL) throws {
        self.path = path
        self.id = path.lastPathComponent

        let spaceDir = path.appendingPathComponent(".space")

        // Load config
        let configPath = spaceDir.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configPath.path) {
            let data = try Data(contentsOf: configPath)
            self.config = try JSONDecoder().decode(SpaceConfig.self, from: data)
        } else {
            self.config = SpaceConfig(name: id)
        }

        // Load convention files
        self.conventions = try SpaceConventions.load(from: path)
    }

    /// Combined context for agents (all convention files merged)
    public var agentContext: String {
        conventions.combinedContext
    }

    /// Create a new workspace
    public static func create(
        id: String,
        at spacesPath: URL,
        config: SpaceConfig,
        agentsContent: String? = nil
    ) throws -> AgentWorkspace {
        let spacePath = spacesPath.appendingPathComponent(id)
        let spaceDir = spacePath.appendingPathComponent(".space")

        // Create directories
        try FileManager.default.createDirectory(at: spaceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: spacePath.appendingPathComponent("documents"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: spacePath.appendingPathComponent("artifacts"),
            withIntermediateDirectories: true
        )

        // Write config
        let configPath = spaceDir.appendingPathComponent("config.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let configData = try encoder.encode(config)
        try configData.write(to: configPath)

        // Write AGENTS.md with instructions
        let agentsPath = spacePath.appendingPathComponent("AGENTS.md")
        let content = agentsContent ?? defaultAgentsContent(for: id)
        try content.write(to: agentsPath, atomically: true, encoding: .utf8)

        // Initialize git repo
        let gitPath = spacePath.appendingPathComponent(".git")
        if !FileManager.default.fileExists(atPath: gitPath.path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["init"]
            process.currentDirectoryURL = spacePath
            try process.run()
            process.waitUntilExit()
        }

        return try AgentWorkspace(path: spacePath)
    }

    // MARK: - Paths

    /// Path to .space config directory
    public var spaceConfigDir: URL {
        path.appendingPathComponent(".space")
    }

    /// Path to documents directory
    public var documentsPath: URL {
        path.appendingPathComponent("documents")
    }

    /// Path to artifacts directory
    public var artifactsPath: URL {
        path.appendingPathComponent("artifacts")
    }

    // MARK: - Default Content

    private static func defaultAgentsContent(for spaceId: String) -> String {
        """
        # \(spaceId)

        ## Purpose

        [Describe what this space is for]

        ## For Agents

        When working in this space:

        1. **Organization**: Keep files organized in appropriate subdirectories
        2. **Naming**: Use clear, descriptive names for all files
        3. **Documentation**: Document significant changes or decisions
        4. **Artifacts**: Place generated content in `artifacts/`

        ## Structure

        ```
        documents/     - Source documents and files
        artifacts/     - Agent-generated content
        ```

        ## Owner Notes

        [Add specific instructions for agents working here]
        """
    }
}

// MARK: - Space Conventions

/// Convention files that agents look for in a space
public struct SpaceConventions: Sendable {
    /// CLAUDE.md - Project context (like Claude Code)
    public let claude: String?

    /// AGENTS.md - Instructions for agents
    public let agents: String?

    /// HANDBOOK.md - Rules and guidelines
    public let handbook: String?

    /// README.md - Project readme
    public let readme: String?

    /// Load conventions from a directory
    public static func load(from path: URL) throws -> SpaceConventions {
        SpaceConventions(
            claude: try? String(contentsOf: path.appendingPathComponent("CLAUDE.md"), encoding: .utf8),
            agents: try? String(contentsOf: path.appendingPathComponent("AGENTS.md"), encoding: .utf8),
            handbook: try? String(contentsOf: path.appendingPathComponent("HANDBOOK.md"), encoding: .utf8),
            readme: try? String(contentsOf: path.appendingPathComponent("README.md"), encoding: .utf8)
        )
    }

    /// Combined context from all convention files
    public var combinedContext: String {
        var parts: [String] = []

        if let claude = claude {
            parts.append("# Project Context (CLAUDE.md)\n\n\(claude)")
        }

        if let agents = agents {
            parts.append("# Agent Instructions (AGENTS.md)\n\n\(agents)")
        }

        if let handbook = handbook {
            parts.append("# Guidelines (HANDBOOK.md)\n\n\(handbook)")
        }

        if let readme = readme {
            parts.append("# README\n\n\(readme)")
        }

        return parts.joined(separator: "\n\n---\n\n")
    }

    /// Whether any conventions exist
    public var hasConventions: Bool {
        claude != nil || agents != nil || handbook != nil || readme != nil
    }
}

/// Space configuration
public struct SpaceConfig: Codable, Sendable {
    /// Display name
    public var name: String

    /// Description
    public var description: String?

    /// Owner/creator
    public var owner: String?

    /// When the space was created
    public var createdAt: Date

    /// Agents assigned to this space
    public var assignedAgents: [String]?

    /// Tags for organization
    public var tags: [String]?

    /// Custom metadata
    public var metadata: [String: String]?

    public init(
        name: String,
        description: String? = nil,
        owner: String? = nil,
        createdAt: Date = Date(),
        assignedAgents: [String]? = nil,
        tags: [String]? = nil,
        metadata: [String: String]? = nil
    ) {
        self.name = name
        self.description = description
        self.owner = owner
        self.createdAt = createdAt
        self.assignedAgents = assignedAgents
        self.tags = tags
        self.metadata = metadata
    }
}

// MARK: - Agents Manager

/// Manages agents and spaces in the iCloud Agents directory
public actor AgentsManager {
    /// Base path (iCloud/Agents)
    public nonisolated let basePath: URL

    /// Team path (iCloud/Agents/Team)
    public nonisolated var teamPath: URL { basePath.appendingPathComponent("Team") }

    /// Spaces path (iCloud/Agents/Spaces)
    public nonisolated var spacesPath: URL { basePath.appendingPathComponent("Spaces") }

    /// Loaded agent definitions
    private var agents: [String: AgentDefinition] = [:]

    /// Loaded workspaces
    private var workspaces: [String: AgentWorkspace] = [:]

    private let logger = Logger(label: "AgentKit.AgentsManager")

    // MARK: - Initialization

    public init(basePath: URL? = nil) {
        self.basePath = basePath ?? Self.defaultBasePath
    }

    /// Default base path (iCloud Drive/Agents)
    public static var defaultBasePath: URL {
        let iCloudPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Agents")

        // Fall back to local if iCloud container doesn't exist
        let iCloudContainer = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")

        if FileManager.default.fileExists(atPath: iCloudContainer.path) {
            return iCloudPath
        }

        // Local fallback
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Agents")
    }

    // MARK: - Loading

    /// Load all agents and workspaces
    public func loadAll() throws {
        // Create directories if needed
        try FileManager.default.createDirectory(at: teamPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: spacesPath, withIntermediateDirectories: true)

        // Load agents from Team
        agents = [:]
        if let contents = try? FileManager.default.contentsOfDirectory(at: teamPath, includingPropertiesForKeys: [.isDirectoryKey]) {
            for url in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    do {
                        let agent = try AgentDefinition(path: url)
                        agents[agent.id] = agent
                        logger.info("Loaded agent", metadata: ["id": "\(agent.id)"])
                    } catch {
                        logger.warning("Failed to load agent", metadata: ["path": "\(url.path)", "error": "\(error)"])
                    }
                }
            }
        }

        // Load workspaces from Spaces
        workspaces = [:]
        if let contents = try? FileManager.default.contentsOfDirectory(at: spacesPath, includingPropertiesForKeys: [.isDirectoryKey]) {
            for url in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    do {
                        let workspace = try AgentWorkspace(path: url)
                        workspaces[workspace.id] = workspace
                        logger.info("Loaded workspace", metadata: ["id": "\(workspace.id)"])
                    } catch {
                        logger.warning("Failed to load workspace", metadata: ["path": "\(url.path)", "error": "\(error)"])
                    }
                }
            }
        }

        logger.info("Loaded \(agents.count) agents and \(workspaces.count) workspaces from \(basePath.path)")
    }

    // MARK: - Agent Operations

    /// Get an agent by ID
    public func agent(_ id: String) -> AgentDefinition? {
        agents[id]
    }

    /// Get or create an agent
    public func getOrCreateAgent(_ id: String, config: AgentConfig = AgentConfig()) throws -> AgentDefinition {
        if let existing = agents[id] {
            return existing
        }

        let agent = try AgentDefinition.create(id: id, at: teamPath, config: config)
        agents[id] = agent
        logger.info("Created agent", metadata: ["id": "\(id)"])
        return agent
    }

    /// List all agent IDs
    public var allAgentIds: [String] {
        Array(agents.keys).sorted()
    }

    // MARK: - Workspace Operations

    /// Get a workspace by ID
    public func workspace(_ id: String) -> AgentWorkspace? {
        workspaces[id]
    }

    /// Get or create a workspace
    public func getOrCreateWorkspace(_ id: String, config: SpaceConfig? = nil) throws -> AgentWorkspace {
        if let existing = workspaces[id] {
            return existing
        }

        let workspace = try AgentWorkspace.create(id: id, at: spacesPath, config: config ?? SpaceConfig(name: id))
        workspaces[id] = workspace
        logger.info("Created workspace", metadata: ["id": "\(id)"])
        return workspace
    }

    /// List all workspace IDs
    public var allWorkspaceIds: [String] {
        Array(workspaces.keys).sorted()
    }
}
