import Foundation

// MARK: - Chat Config Agent

/// An agent that configures other agents through conversation.
///
/// This implements the Custom GPT-style configuration pattern where users
/// can describe what they want an agent to do, and the system automatically
/// generates/updates the agent configuration.
///
/// ## Usage Flow
/// ```
/// User: "I want an agent that helps me write blog posts"
/// ChatConfigAgent: "Great! I'll create a writing assistant..."
///                   [Updates: name="Writing Assistant", skills+=["content creation"]]
///
/// User: "It should use a friendly, casual tone"
/// ChatConfigAgent: "I've updated the tone guidelines..."
///                   [Updates: systemPrompt+="Use a friendly, casual tone"]
///
/// User: "Can it search the web for research?"
/// ChatConfigAgent: "I'll enable web search for research..."
///                   [Updates: tools+=["web_fetch"]]
/// ```
public actor ChatConfigAgent {
    // MARK: - Properties

    /// The configuration being built/edited
    private var configuration: ChatAgentConfig

    /// History of configuration changes
    private var changeHistory: [ConfigChange] = []

    /// Callback when configuration changes
    private var onConfigChange: ((ChatAgentConfig) -> Void)?

    /// The LLM provider for generating responses
    private let llmProvider: any LLMProvider

    // MARK: - Initialization

    public init(
        existingConfig: ChatAgentConfig? = nil,
        llmProvider: any LLMProvider,
        onConfigChange: ((ChatAgentConfig) -> Void)? = nil
    ) {
        self.configuration = existingConfig ?? ChatAgentConfig()
        self.llmProvider = llmProvider
        self.onConfigChange = onConfigChange
    }

    // MARK: - Configuration

    /// Process a user message and potentially update configuration
    public func processMessage(_ message: String) async throws -> ConfigResponse {
        // Build prompt for the configurator
        let systemPrompt = buildConfiguratorPrompt()

        // Build messages
        let messages = [
            Message(role: .system, content: .text(systemPrompt)),
            Message(role: .user, content: .text(message))
        ]

        // Get LLM response (collect stream into full text)
        var responseText = ""
        let stream = try await llmProvider.complete(
            messages,
            tools: [],
            options: CompletionOptions(
                maxTokens: 1000,
                temperature: 0.7
            )
        )

        for try await event in stream {
            if case .text(let text) = event {
                responseText += text
            }
        }

        // Parse the response for configuration updates
        let updates = parseConfigUpdates(from: responseText)

        // Apply updates
        for update in updates {
            applyUpdate(update)
        }

        // Notify of changes
        if !updates.isEmpty {
            onConfigChange?(configuration)
        }

        return ConfigResponse(
            message: responseText,
            updates: updates,
            currentConfig: configuration
        )
    }

    /// Get the current configuration
    public var currentConfig: ChatAgentConfig {
        configuration
    }

    /// Get change history
    public var history: [ConfigChange] {
        changeHistory
    }

    // MARK: - Prompt Building

    private func buildConfiguratorPrompt() -> String {
        """
        You are an agent configurator assistant. Your job is to help users create and customize AI agents through conversation.

        Current agent configuration:
        - Name: \(configuration.name.isEmpty ? "(not set)" : configuration.name)
        - Description: \(configuration.description.isEmpty ? "(not set)" : configuration.description)
        - Personality: \(configuration.personality.isEmpty ? "(not set)" : configuration.personality)
        - Enabled tools: \(configuration.enabledTools.isEmpty ? "(none)" : configuration.enabledTools.joined(separator: ", "))
        - Skills: \(configuration.skills.isEmpty ? "(none)" : configuration.skills.joined(separator: ", "))
        - Knowledge sources: \(configuration.knowledgeSources.isEmpty ? "(none)" : configuration.knowledgeSources.joined(separator: ", "))

        When the user describes what they want, respond conversationally AND include configuration updates in this format:

        [CONFIG_UPDATE]
        field: value
        [/CONFIG_UPDATE]

        Available fields:
        - name: The agent's name (short, memorable)
        - description: What the agent does (1-2 sentences)
        - personality: How the agent should communicate (tone, style)
        - add_tool: Enable a tool (one of: calendar, reminders, filesystem, git, shell, web, memory)
        - remove_tool: Disable a tool
        - add_skill: Add a capability description
        - add_knowledge: Add a knowledge source (topic or URL)
        - custom_instruction: Add a specific instruction to follow

        Example response:
        "I'll create a writing assistant for you! It will help craft blog posts with SEO optimization.

        [CONFIG_UPDATE]
        name: Writing Buddy
        description: Helps create engaging blog posts with SEO optimization
        personality: Friendly, encouraging, and detail-oriented
        add_skill: Blog post writing
        add_skill: SEO optimization
        add_tool: web
        [/CONFIG_UPDATE]"

        Be conversational and helpful. Ask clarifying questions if needed. Guide users through the configuration process naturally.
        """
    }

    // MARK: - Parsing

    private func parseConfigUpdates(from response: String) -> [ConfigUpdate] {
        var updates: [ConfigUpdate] = []

        // Find config update blocks
        let pattern = #"\[CONFIG_UPDATE\]([\s\S]*?)\[/CONFIG_UPDATE\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return updates
        }

        let range = NSRange(response.startIndex..<response.endIndex, in: response)
        let matches = regex.matches(in: response, options: [], range: range)

        for match in matches {
            guard let blockRange = Range(match.range(at: 1), in: response) else { continue }
            let block = String(response[blockRange])

            // Parse each line
            for line in block.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                let parts = trimmed.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }

                let field = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)

                if let update = ConfigUpdate(field: field, value: value) {
                    updates.append(update)
                }
            }
        }

        return updates
    }

    // MARK: - Applying Updates

    private func applyUpdate(_ update: ConfigUpdate) {
        let change = ConfigChange(
            timestamp: Date(),
            field: update.field,
            oldValue: getFieldValue(update.field),
            newValue: update.value
        )

        switch update.field {
        case "name":
            configuration.name = update.value
        case "description":
            configuration.description = update.value
        case "personality":
            configuration.personality = update.value
        case "add_tool":
            if !configuration.enabledTools.contains(update.value) {
                configuration.enabledTools.append(update.value)
            }
        case "remove_tool":
            configuration.enabledTools.removeAll { $0 == update.value }
        case "add_skill":
            if !configuration.skills.contains(update.value) {
                configuration.skills.append(update.value)
            }
        case "add_knowledge":
            if !configuration.knowledgeSources.contains(update.value) {
                configuration.knowledgeSources.append(update.value)
            }
        case "custom_instruction":
            configuration.customInstructions.append(update.value)
        default:
            return
        }

        changeHistory.append(change)
    }

    private func getFieldValue(_ field: String) -> String {
        switch field {
        case "name": return configuration.name
        case "description": return configuration.description
        case "personality": return configuration.personality
        case "add_tool", "remove_tool": return configuration.enabledTools.joined(separator: ", ")
        case "add_skill": return configuration.skills.joined(separator: ", ")
        case "add_knowledge": return configuration.knowledgeSources.joined(separator: ", ")
        default: return ""
        }
    }

    // MARK: - Export

    /// Export as AgentConfiguration for use with AgentLoop
    public func exportConfiguration(llmProvider: any LLMProvider) -> AgentConfiguration {
        // Build system prompt from chat config
        var systemPrompt = ""

        if !configuration.description.isEmpty {
            systemPrompt += "You are \(configuration.name.isEmpty ? "an AI assistant" : configuration.name). \(configuration.description)\n\n"
        }

        if !configuration.personality.isEmpty {
            systemPrompt += "Communication style: \(configuration.personality)\n\n"
        }

        if !configuration.skills.isEmpty {
            systemPrompt += "Your capabilities include:\n"
            for skill in configuration.skills {
                systemPrompt += "- \(skill)\n"
            }
            systemPrompt += "\n"
        }

        if !configuration.customInstructions.isEmpty {
            systemPrompt += "Additional instructions:\n"
            for instruction in configuration.customInstructions {
                systemPrompt += "- \(instruction)\n"
            }
        }

        // Map enabled tools to actual Tool instances
        let tools: [any Tool] = []  // Would map from configuration.enabledTools

        return AgentConfiguration(
            name: configuration.name,
            description: configuration.description,
            systemPrompt: systemPrompt,
            tools: tools,
            llmProvider: llmProvider
        )
    }
}

// MARK: - Chat Agent Config

/// Serializable configuration built through chat
public struct ChatAgentConfig: Codable, Sendable {
    public var name: String
    public var description: String
    public var personality: String
    public var enabledTools: [String]
    public var skills: [String]
    public var knowledgeSources: [String]
    public var customInstructions: [String]
    public var icon: String
    public var color: String

    public init(
        name: String = "",
        description: String = "",
        personality: String = "",
        enabledTools: [String] = [],
        skills: [String] = [],
        knowledgeSources: [String] = [],
        customInstructions: [String] = [],
        icon: String = "sparkles",
        color: String = "blue"
    ) {
        self.name = name
        self.description = description
        self.personality = personality
        self.enabledTools = enabledTools
        self.skills = skills
        self.knowledgeSources = knowledgeSources
        self.customInstructions = customInstructions
        self.icon = icon
        self.color = color
    }

    /// Create from JSON file
    public static func load(from url: URL) throws -> ChatAgentConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ChatAgentConfig.self, from: data)
    }

    /// Save to JSON file
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

// MARK: - Config Update

public struct ConfigUpdate: Sendable {
    public let field: String
    public let value: String

    public init?(field: String, value: String) {
        let validFields = ["name", "description", "personality", "add_tool", "remove_tool",
                          "add_skill", "add_knowledge", "custom_instruction"]

        guard validFields.contains(field) else { return nil }

        self.field = field
        self.value = value
    }
}

// MARK: - Config Change

public struct ConfigChange: Sendable {
    public let timestamp: Date
    public let field: String
    public let oldValue: String
    public let newValue: String
}

// MARK: - Config Response

public struct ConfigResponse: Sendable {
    public let message: String
    public let updates: [ConfigUpdate]
    public let currentConfig: ChatAgentConfig
}
