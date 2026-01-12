import Foundation

// MARK: - Agent Registry

/// Central registry of all known agents in the system.
///
/// The AgentRegistry serves as the "employee directory" - it knows:
/// - Which agents exist (local and remote)
/// - What capabilities each agent has
/// - What Spaces each agent owns or contributes to
/// - Current status of each agent
///
/// Used by:
/// - Concierge to route tasks to the right agent
/// - Agents to discover other agents for delegation
/// - UI to show available agents
public actor AgentRegistry {

    // MARK: - Properties

    /// All registered agents
    private var _agents: [AgentID: RegisteredAgent] = [:]

    /// Capability index for fast lookup
    private var _capabilityIndex: [AgentCapability: Set<AgentID>] = [:]

    /// Space ownership index
    private var _spaceOwners: [SpaceID: AgentID] = [:]

    /// Space contributors index
    private var _spaceContributors: [SpaceID: Set<AgentID>] = [:]

    // MARK: - Initialization

    public init() {}

    // MARK: - Registration

    /// Register an agent with the system
    public func register(_ agent: RegisteredAgent) {
        _agents[agent.id] = agent

        // Index capabilities
        for capability in agent.capabilities {
            _capabilityIndex[capability, default: []].insert(agent.id)
        }

        // Index space ownership
        for spaceId in agent.ownedSpaces {
            _spaceOwners[spaceId] = agent.id
        }

        // Index space contributions
        for spaceId in agent.contributingSpaces {
            _spaceContributors[spaceId, default: []].insert(agent.id)
        }
    }

    /// Unregister an agent
    public func unregister(_ agentId: AgentID) {
        guard let agent = _agents.removeValue(forKey: agentId) else { return }

        // Remove from capability index
        for capability in agent.capabilities {
            _capabilityIndex[capability]?.remove(agentId)
        }

        // Remove from space indices
        for spaceId in agent.ownedSpaces {
            if _spaceOwners[spaceId] == agentId {
                _spaceOwners.removeValue(forKey: spaceId)
            }
        }

        for spaceId in agent.contributingSpaces {
            _spaceContributors[spaceId]?.remove(agentId)
        }
    }

    /// Update an agent's information
    public func update(_ agentId: AgentID, with updates: RegistryUpdate) {
        guard var agent = _agents[agentId] else { return }

        if let status = updates.status {
            agent.status = status
        }
        if let capabilities = updates.capabilities {
            // Remove old capability index
            for cap in agent.capabilities {
                _capabilityIndex[cap]?.remove(agentId)
            }
            agent.capabilities = capabilities
            // Add new capability index
            for cap in capabilities {
                _capabilityIndex[cap, default: []].insert(agentId)
            }
        }

        _agents[agentId] = agent
    }

    // MARK: - Queries

    /// Get all registered agents
    public var agents: [RegisteredAgent] {
        Array(_agents.values)
    }

    /// Get a specific agent
    public func agent(_ id: AgentID) -> RegisteredAgent? {
        _agents[id]
    }

    /// Get agents with a specific capability
    public func agents(withCapability capability: AgentCapability) -> [RegisteredAgent] {
        guard let ids = _capabilityIndex[capability] else { return [] }
        return ids.compactMap { _agents[$0] }
    }

    /// Get the owner of a space
    public func owner(of spaceId: SpaceID) -> RegisteredAgent? {
        guard let ownerId = _spaceOwners[spaceId] else { return nil }
        return _agents[ownerId]
    }

    /// Get contributors to a space
    public func contributors(to spaceId: SpaceID) -> [RegisteredAgent] {
        guard let ids = _spaceContributors[spaceId] else { return [] }
        return ids.compactMap { _agents[$0] }
    }

    /// Get agents by profile type
    public func agents(withProfile profile: AgentProfile) -> [RegisteredAgent] {
        _agents.values.filter { $0.profile == profile }
    }

    /// Get available agents (online and not busy)
    public var availableAgents: [RegisteredAgent] {
        _agents.values.filter { $0.status == .available }
    }

    /// Find the best agent for a task based on capabilities
    public func findBestAgent(
        for capabilities: [AgentCapability],
        excluding: Set<AgentID> = []
    ) -> RegisteredAgent? {
        // Score agents based on matching capabilities
        var scores: [(agent: RegisteredAgent, score: Int)] = []

        for agent in _agents.values {
            guard agent.status == .available,
                  !excluding.contains(agent.id)
            else { continue }

            let matchingCaps = capabilities.filter { agent.capabilities.contains($0) }
            if !matchingCaps.isEmpty {
                scores.append((agent, matchingCaps.count))
            }
        }

        // Return agent with highest score
        return scores.max(by: { $0.score < $1.score })?.agent
    }
}

// MARK: - Registered Agent

/// A registered agent in the system
public struct RegisteredAgent: Identifiable, Sendable {
    public let id: AgentID
    public var name: String
    public var profile: AgentProfile
    public var capabilities: Set<AgentCapability>
    public var status: AgentStatus
    public var ownedSpaces: [SpaceID]
    public var contributingSpaces: [SpaceID]
    public var endpoint: AgentEndpoint?
    public let registeredAt: Date

    public init(
        id: AgentID,
        name: String,
        profile: AgentProfile,
        capabilities: Set<AgentCapability> = [],
        status: AgentStatus = .available,
        ownedSpaces: [SpaceID] = [],
        contributingSpaces: [SpaceID] = [],
        endpoint: AgentEndpoint? = nil
    ) {
        self.id = id
        self.name = name
        self.profile = profile
        self.capabilities = capabilities
        self.status = status
        self.ownedSpaces = ownedSpaces
        self.contributingSpaces = contributingSpaces
        self.endpoint = endpoint
        self.registeredAt = Date()
    }
}

// MARK: - Agent Profile

/// The archetype/role of an agent (from agent_profiles.md)
public enum AgentProfile: String, Sendable, Codable, CaseIterable {
    case founder        // Owns a space, entrepreneurial
    case concierge      // Routes requests, learns user preferences
    case librarian      // Research, collection, retrieval
    case weaver         // Pattern recognition, synthesis
    case integrator     // Builds tools, UI, integrations
    case critic         // Quality assurance, review
    case executor       // Gets things done, task-focused
    case coach          // Domain-specific guidance
    case guardian       // Security, permissions, audit

    public var displayName: String {
        switch self {
        case .founder: return "Founder"
        case .concierge: return "Concierge"
        case .librarian: return "Librarian"
        case .weaver: return "Weaver"
        case .integrator: return "Integrator"
        case .critic: return "Critic"
        case .executor: return "Executor"
        case .coach: return "Coach"
        case .guardian: return "Guardian"
        }
    }

    public var icon: String {
        switch self {
        case .founder: return "flag"
        case .concierge: return "person.badge.shield.checkmark"
        case .librarian: return "books.vertical"
        case .weaver: return "network"
        case .integrator: return "gearshape.2"
        case .critic: return "magnifyingglass"
        case .executor: return "checkmark.seal"
        case .coach: return "figure.mind.and.body"
        case .guardian: return "shield"
        }
    }
}

// MARK: - Agent Capability

/// What an agent can do
public enum AgentCapability: String, Sendable, Codable, Hashable {
    // Research & Knowledge
    case research
    case synthesis
    case retrieval
    case summarization

    // Content
    case writing
    case editing
    case formatting
    case translation

    // Technical
    case coding
    case debugging
    case architecture
    case integration

    // Communication
    case routing
    case scheduling
    case notification
    case conversation

    // Analysis
    case patternRecognition
    case trendAnalysis
    case qualityAssurance
    case riskAssessment

    // Domain-specific
    case careerCoaching
    case fitnessCoaching
    case financeAdvice
    case projectManagement
}

// MARK: - Agent Status

/// Current status of an agent
public enum AgentStatus: String, Sendable, Codable {
    case available      // Ready to accept tasks
    case busy           // Currently working on a task
    case offline        // Not available
    case maintenance    // Temporarily unavailable

    public var canAcceptTasks: Bool {
        self == .available
    }
}

// MARK: - Agent Endpoint

/// How to communicate with an agent
public enum AgentEndpoint: Sendable {
    case local(any Agent)       // In-process agent
    case remote(URL)            // A2A HTTP endpoint
    case process(pid: Int32)    // Subprocess

    public var isLocal: Bool {
        if case .local = self { return true }
        return false
    }
}

// MARK: - Registry Update

/// Updates to an agent's registration
public struct RegistryUpdate: Sendable {
    public var status: AgentStatus?
    public var capabilities: Set<AgentCapability>?

    public init(status: AgentStatus? = nil, capabilities: Set<AgentCapability>? = nil) {
        self.status = status
        self.capabilities = capabilities
    }
}
