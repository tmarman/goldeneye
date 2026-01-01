import Foundation

// MARK: - Agent Protocol

/// Core protocol for all agents in AgentKit.
///
/// Agents are actors that process tasks using an LLM and tools.
/// They run autonomously until completion, failure, or human intervention.
public protocol Agent: Actor {
    /// Unique identifier for this agent instance
    var id: AgentID { get }

    /// Agent configuration (model, tools, policies)
    var configuration: AgentConfiguration { get }

    /// Execute a task and return a stream of events
    func execute(_ task: AgentTask) -> AgentEventStream

    /// Pause execution (can be resumed)
    func pause() async

    /// Resume paused execution
    func resume() async

    /// Cancel execution (terminal)
    func cancel() async
}

// MARK: - Supporting Types

/// Unique identifier for an agent
public struct AgentID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID().uuidString
    }

    public var description: String { rawValue }
}

/// Task to be executed by an agent
public struct AgentTask: Sendable, Identifiable {
    public let id: TaskID
    public let contextId: ContextID
    public let message: Message
    public let configuration: TaskConfiguration?

    public init(
        id: TaskID = TaskID(),
        contextId: ContextID = ContextID(),
        message: Message,
        configuration: TaskConfiguration? = nil
    ) {
        self.id = id
        self.contextId = contextId
        self.message = message
        self.configuration = configuration
    }
}

public struct TaskID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID().uuidString
    }

    public var description: String { rawValue }
}

public struct ContextID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID().uuidString
    }

    public var description: String { rawValue }
}

/// Configuration for task execution
public struct TaskConfiguration: Sendable, Codable {
    /// Whether to block until completion (vs. return immediately)
    public var blocking: Bool

    /// Maximum duration for task execution
    public var timeout: Duration?

    /// Override approval policy for this task
    public var approvalPolicy: ApprovalPolicyOverride?

    public init(
        blocking: Bool = false,
        timeout: Duration? = nil,
        approvalPolicy: ApprovalPolicyOverride? = nil
    ) {
        self.blocking = blocking
        self.timeout = timeout
        self.approvalPolicy = approvalPolicy
    }
}

public enum ApprovalPolicyOverride: Sendable, Codable {
    case alwaysApprove
    case neverApprove
    case useDefault
}

// MARK: - Agent Event Stream

/// Async stream of events from agent execution
public typealias AgentEventStream = AsyncThrowingStream<AgentEvent, Error>
