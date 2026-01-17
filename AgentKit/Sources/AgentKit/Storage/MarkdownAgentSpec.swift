import Foundation

// MARK: - Agent Profile (Markdown Definition)

/// Represents an agent profile defined in a markdown file with YAML frontmatter.
///
/// This is a lightweight format for defining agent personas that can be converted
/// to the full MarkdownAgentSpec (in AgentSpace.swift) for runtime use.
///
/// Profile files follow this format:
/// ```markdown
/// ---
/// name: Research Assistant
/// role: researcher
/// model: claude-sonnet-4-20250514
/// tools: [web_search, read_file]
/// ---
///
/// You are a research assistant that helps users find and synthesize information.
///
/// ## Capabilities
/// - Search the web for current information
/// - Read and analyze documents
/// ```
public struct MarkdownAgentSpec: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var role: String?
    public var model: String?
    public var tools: [String]
    public var skills: [String]
    public var systemPrompt: String
    public var avatar: String?
    public var color: String?
    public var createdAt: Date
    public var updatedAt: Date

    /// Source file path (not persisted in the file itself)
    public var sourcePath: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        role: String? = nil,
        model: String? = nil,
        tools: [String] = [],
        skills: [String] = [],
        systemPrompt: String = "",
        avatar: String? = nil,
        color: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourcePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.model = model
        self.tools = tools
        self.skills = skills
        self.systemPrompt = systemPrompt
        self.avatar = avatar
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourcePath = sourcePath
    }
}

// MARK: - Parsing

extension MarkdownAgentSpec {

    /// Parse an agent definition from markdown with YAML frontmatter
    public static func parse(from markdown: String, sourcePath: String? = nil) -> MarkdownAgentSpec? {
        let document = FrontmatterParser.parse(markdown)

        // Name is required
        guard let name = document.string("name") ?? document.string("title") else {
            return nil
        }

        let id = document.string("id") ?? UUID().uuidString

        // Parse dates
        let createdAt = document.date("created") ?? document.date("createdAt") ?? Date()
        let updatedAt = document.date("updated") ?? document.date("updatedAt") ?? Date()

        return MarkdownAgentSpec(
            id: id,
            name: name,
            role: document.string("role"),
            model: document.string("model"),
            tools: document.stringArray("tools") ?? [],
            skills: document.stringArray("skills") ?? [],
            systemPrompt: document.content,
            avatar: document.string("avatar"),
            color: document.string("color"),
            createdAt: createdAt,
            updatedAt: updatedAt,
            sourcePath: sourcePath
        )
    }

    /// Serialize agent definition to markdown with YAML frontmatter
    public func toMarkdown() -> String {
        var frontmatter: [String: Any] = [
            "id": id,
            "name": name
        ]

        if let role = role {
            frontmatter["role"] = role
        }
        if let model = model {
            frontmatter["model"] = model
        }
        if !tools.isEmpty {
            frontmatter["tools"] = tools
        }
        if !skills.isEmpty {
            frontmatter["skills"] = skills
        }
        if let avatar = avatar {
            frontmatter["avatar"] = avatar
        }
        if let color = color {
            frontmatter["color"] = color
        }

        let formatter = ISO8601DateFormatter()
        frontmatter["created"] = formatter.string(from: createdAt)
        frontmatter["updated"] = formatter.string(from: updatedAt)

        return FrontmatterParser.createDocument(
            frontmatter: frontmatter,
            content: systemPrompt
        )
    }
}

// MARK: - File Operations

extension MarkdownAgentSpec {

    /// Load an agent definition from a file path
    public static func load(from path: String) throws -> MarkdownAgentSpec {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)

        guard let content = String(data: data, encoding: .utf8) else {
            throw MarkdownAgentSpecError.invalidEncoding
        }

        guard let agent = parse(from: content, sourcePath: path) else {
            throw MarkdownAgentSpecError.invalidFormat
        }

        return agent
    }

    /// Save agent definition to a file path
    public func save(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let markdown = toMarkdown()

        guard let data = markdown.data(using: .utf8) else {
            throw MarkdownAgentSpecError.invalidEncoding
        }

        // Create parent directory if needed
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try data.write(to: url)
    }

    /// Generate a safe filename from the agent name
    public var suggestedFilename: String {
        let safe = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "-")))
            .joined()
        return "\(safe).md"
    }
}

// MARK: - Errors

public enum MarkdownAgentSpecError: Error, LocalizedError {
    case invalidEncoding
    case invalidFormat
    case missingName
    case fileNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "File encoding is not valid UTF-8"
        case .invalidFormat:
            return "File is not a valid agent definition"
        case .missingName:
            return "Agent definition is missing required 'name' field"
        case .fileNotFound:
            return "Agent file not found"
        }
    }
}

// MARK: - Conversion to AgentCard

extension MarkdownAgentSpec {

    /// Convert to AgentCard for A2A protocol discovery
    public func toAgentCard() -> AgentCard {
        let agentSkills = skills.map { skillName in
            AgentSkill(
                id: skillName.lowercased().replacingOccurrences(of: " ", with: "-"),
                name: skillName,
                description: skillName
            )
        }

        return AgentCard(
            name: name,
            description: role ?? systemPrompt.prefix(200).description,
            skills: agentSkills
        )
    }
}
