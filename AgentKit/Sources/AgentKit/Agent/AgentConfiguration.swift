import Foundation

// MARK: - Agent Configuration

/// Configuration for an agent instance
public struct AgentConfiguration: Sendable {
    /// Human-readable name
    public var name: String

    /// Description of agent capabilities
    public var description: String

    /// System prompt for the LLM
    public var systemPrompt: String

    /// Available tools
    public var tools: [any Tool]

    /// LLM provider to use
    public var llmProvider: any LLMProvider

    /// Approval policy for tool execution
    public var approvalPolicy: ApprovalPolicy

    /// Maximum context window tokens
    public var maxContextTokens: Int

    /// Maximum iterations before forcing completion
    public var maxIterations: Int

    public init(
        name: String,
        description: String = "",
        systemPrompt: String,
        tools: [any Tool] = [],
        llmProvider: any LLMProvider,
        approvalPolicy: ApprovalPolicy = .default,
        maxContextTokens: Int = 128_000,
        maxIterations: Int = 100
    ) {
        self.name = name
        self.description = description
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.llmProvider = llmProvider
        self.approvalPolicy = approvalPolicy
        self.maxContextTokens = maxContextTokens
        self.maxIterations = maxIterations
    }
}

// MARK: - Agent Card (A2A)

/// Agent Card for A2A protocol discovery
public struct AgentCard: Codable, Sendable {
    public let protocolVersion: String
    public let name: String
    public let description: String
    public let version: String
    public let supportedInterfaces: [AgentInterface]
    public let provider: AgentProvider?
    public let capabilities: AgentCapabilities
    public let skills: [AgentSkill]
    public let documentationUrl: String?
    public let iconUrl: String?

    public init(
        protocolVersion: String = "1.0",
        name: String,
        description: String,
        version: String = "1.0.0",
        supportedInterfaces: [AgentInterface] = [],
        provider: AgentProvider? = nil,
        capabilities: AgentCapabilities = AgentCapabilities(),
        skills: [AgentSkill] = [],
        documentationUrl: String? = nil,
        iconUrl: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.name = name
        self.description = description
        self.version = version
        self.supportedInterfaces = supportedInterfaces
        self.provider = provider
        self.capabilities = capabilities
        self.skills = skills
        self.documentationUrl = documentationUrl
        self.iconUrl = iconUrl
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case name, description, version
        case supportedInterfaces = "supported_interfaces"
        case provider, capabilities, skills
        case documentationUrl = "documentation_url"
        case iconUrl = "icon_url"
    }
}

public struct AgentInterface: Codable, Sendable {
    public let url: String
    public let protocolBinding: String

    public init(url: String, protocolBinding: String = "JSONRPC") {
        self.url = url
        self.protocolBinding = protocolBinding
    }

    enum CodingKeys: String, CodingKey {
        case url
        case protocolBinding = "protocol_binding"
    }
}

public struct AgentProvider: Codable, Sendable {
    public let name: String
    public let url: String?

    public init(name: String, url: String? = nil) {
        self.name = name
        self.url = url
    }
}

public struct AgentCapabilities: Codable, Sendable {
    public var streaming: Bool
    public var pushNotifications: Bool
    public var stateTransitionHistory: Bool

    public init(
        streaming: Bool = true,
        pushNotifications: Bool = false,
        stateTransitionHistory: Bool = true
    ) {
        self.streaming = streaming
        self.pushNotifications = pushNotifications
        self.stateTransitionHistory = stateTransitionHistory
    }

    enum CodingKeys: String, CodingKey {
        case streaming
        case pushNotifications = "push_notifications"
        case stateTransitionHistory = "state_transition_history"
    }
}

public struct AgentSkill: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let tags: [String]
    public let examples: [String]

    public init(
        id: String,
        name: String,
        description: String,
        tags: [String] = [],
        examples: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.examples = examples
    }
}
