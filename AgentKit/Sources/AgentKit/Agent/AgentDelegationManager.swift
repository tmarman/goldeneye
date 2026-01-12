import Foundation

// MARK: - Agent Delegation Manager

/// Orchestrates task delegation between agents.
///
/// When one agent needs help from another (e.g., Concierge routing to a Specialist,
/// or a Founder hiring a Contributor), the DelegationManager handles:
/// 1. Finding the right agent via AgentRegistry
/// 2. Creating the delegation request
/// 3. Tracking acceptance/rejection
/// 4. Monitoring task progress
/// 5. Handling completion or return
///
/// This is "A2A within AgentKit" - the internal protocol for agent collaboration.
public actor AgentDelegationManager {

    // MARK: - Properties

    private let registry: AgentRegistry
    private var _delegations: [UUID: AgentDelegation] = [:]
    private var _pendingCallbacks: [UUID: DelegationCallback] = [:]
    private var _observers: [DelegationObserver] = []

    // MARK: - Initialization

    public init(registry: AgentRegistry) {
        self.registry = registry
    }

    // MARK: - Delegation Creation

    /// Create a delegation request
    public func delegate(
        task: TimelineTask,
        from sourceAgent: AgentID,
        to targetAgent: AgentID,
        reason: String,
        callback: DelegationCallback? = nil
    ) async -> AgentDelegation {
        let delegation = AgentDelegation(
            fromAgent: sourceAgent,
            toAgent: targetAgent,
            task: task,
            reason: reason
        )

        _delegations[delegation.id] = delegation

        if let callback = callback {
            _pendingCallbacks[delegation.id] = callback
        }

        // Update target agent status
        await registry.update(targetAgent, with: RegistryUpdate(status: .busy))

        // Notify observers
        notifyObservers(.delegationCreated(delegation))

        return delegation
    }

    /// Delegate with automatic agent selection based on capabilities
    public func delegateToCapableAgent(
        task: TimelineTask,
        from sourceAgent: AgentID,
        requiredCapabilities: [AgentCapability],
        reason: String,
        callback: DelegationCallback? = nil
    ) async -> AgentDelegation? {
        // Find best available agent
        guard let targetAgent = await registry.findBestAgent(
            for: requiredCapabilities,
            excluding: [sourceAgent]
        ) else {
            return nil
        }

        return await delegate(
            task: task,
            from: sourceAgent,
            to: targetAgent.id,
            reason: reason,
            callback: callback
        )
    }

    /// Delegate to the owner of a space
    public func delegateToSpaceOwner(
        task: TimelineTask,
        from sourceAgent: AgentID,
        spaceId: SpaceID,
        reason: String,
        callback: DelegationCallback? = nil
    ) async -> AgentDelegation? {
        guard let owner = await registry.owner(of: spaceId) else {
            return nil
        }

        return await delegate(
            task: task,
            from: sourceAgent,
            to: owner.id,
            reason: reason,
            callback: callback
        )
    }

    // MARK: - Delegation Actions

    /// Accept a delegation (called by receiving agent)
    public func accept(_ delegationId: UUID) async {
        guard var delegation = _delegations[delegationId],
              delegation.status == .pending
        else { return }

        delegation.status = .accepted
        _delegations[delegationId] = delegation

        // Execute callback
        if let callback = _pendingCallbacks[delegationId] {
            await callback.onAccepted?(delegation)
        }

        notifyObservers(.delegationAccepted(delegation))
    }

    /// Decline a delegation (called by receiving agent)
    public func decline(_ delegationId: UUID, reason: String? = nil) async {
        guard var delegation = _delegations[delegationId],
              delegation.status == .pending
        else { return }

        delegation.status = .declined
        _delegations[delegationId] = delegation

        // Free up target agent
        await registry.update(delegation.toAgent, with: RegistryUpdate(status: .available))

        // Execute callback
        if let callback = _pendingCallbacks.removeValue(forKey: delegationId) {
            await callback.onDeclined?(delegation, reason)
        }

        notifyObservers(.delegationDeclined(delegation, reason: reason))
    }

    /// Mark a delegated task as completed
    public func complete(_ delegationId: UUID, result: TaskResult) async {
        guard var delegation = _delegations[delegationId],
              delegation.status == .accepted
        else { return }

        delegation.status = .completed
        _delegations[delegationId] = delegation

        // Free up agent
        await registry.update(delegation.toAgent, with: RegistryUpdate(status: .available))

        // Execute callback
        if let callback = _pendingCallbacks.removeValue(forKey: delegationId) {
            await callback.onCompleted?(delegation, result)
        }

        notifyObservers(.delegationCompleted(delegation, result: result))
    }

    /// Return a task to the original agent (can't complete)
    public func returnToSource(_ delegationId: UUID, reason: String) async {
        guard var delegation = _delegations[delegationId],
              delegation.status == .accepted
        else { return }

        delegation.status = .returned
        _delegations[delegationId] = delegation

        // Free up agent
        await registry.update(delegation.toAgent, with: RegistryUpdate(status: .available))

        // Execute callback
        if let callback = _pendingCallbacks.removeValue(forKey: delegationId) {
            await callback.onReturned?(delegation, reason)
        }

        notifyObservers(.delegationReturned(delegation, reason: reason))
    }

    // MARK: - Queries

    /// Get all delegations
    public var delegations: [AgentDelegation] {
        Array(_delegations.values).sorted { $0.timestamp > $1.timestamp }
    }

    /// Get a specific delegation
    public func delegation(_ id: UUID) -> AgentDelegation? {
        _delegations[id]
    }

    /// Get delegations from an agent
    public func delegations(from agentId: AgentID) -> [AgentDelegation] {
        delegations.filter { $0.fromAgent == agentId }
    }

    /// Get delegations to an agent
    public func delegations(to agentId: AgentID) -> [AgentDelegation] {
        delegations.filter { $0.toAgent == agentId }
    }

    /// Get pending delegations for an agent to review
    public func pendingDelegations(for agentId: AgentID) -> [AgentDelegation] {
        delegations.filter { $0.toAgent == agentId && $0.status == .pending }
    }

    /// Get active delegations (accepted, in progress)
    public var activeDelegations: [AgentDelegation] {
        delegations.filter { $0.status == .accepted }
    }

    // MARK: - Observers

    public func addObserver(_ observer: DelegationObserver) {
        _observers.append(observer)
    }

    public func removeObserver(_ id: String) {
        _observers.removeAll { $0.id == id }
    }

    private func notifyObservers(_ event: DelegationEvent) {
        for observer in _observers {
            Task {
                await observer.onEvent(event)
            }
        }
    }
}

// MARK: - Delegation Callback

/// Callbacks for delegation lifecycle events
public struct DelegationCallback: Sendable {
    public let id: String
    public let onAccepted: (@Sendable (AgentDelegation) async -> Void)?
    public let onDeclined: (@Sendable (AgentDelegation, String?) async -> Void)?
    public let onCompleted: (@Sendable (AgentDelegation, TaskResult) async -> Void)?
    public let onReturned: (@Sendable (AgentDelegation, String) async -> Void)?

    public init(
        id: String = UUID().uuidString,
        onAccepted: (@Sendable (AgentDelegation) async -> Void)? = nil,
        onDeclined: (@Sendable (AgentDelegation, String?) async -> Void)? = nil,
        onCompleted: (@Sendable (AgentDelegation, TaskResult) async -> Void)? = nil,
        onReturned: (@Sendable (AgentDelegation, String) async -> Void)? = nil
    ) {
        self.id = id
        self.onAccepted = onAccepted
        self.onDeclined = onDeclined
        self.onCompleted = onCompleted
        self.onReturned = onReturned
    }
}

// MARK: - Delegation Observer

/// Observer for delegation events
public struct DelegationObserver: Sendable {
    public let id: String
    public let onEvent: @Sendable (DelegationEvent) async -> Void

    public init(id: String = UUID().uuidString, onEvent: @escaping @Sendable (DelegationEvent) async -> Void) {
        self.id = id
        self.onEvent = onEvent
    }
}

// MARK: - Delegation Event

/// Events emitted by the DelegationManager
public enum DelegationEvent: Sendable {
    case delegationCreated(AgentDelegation)
    case delegationAccepted(AgentDelegation)
    case delegationDeclined(AgentDelegation, reason: String?)
    case delegationCompleted(AgentDelegation, result: TaskResult)
    case delegationReturned(AgentDelegation, reason: String)
}

// MARK: - Task Result

/// Result of a completed delegated task
public struct TaskResult: Sendable {
    public let success: Bool
    public let output: String?
    public let artifacts: [TaskArtifact]
    public let metadata: [String: String]

    public init(
        success: Bool,
        output: String? = nil,
        artifacts: [TaskArtifact] = [],
        metadata: [String: String] = [:]
    ) {
        self.success = success
        self.output = output
        self.artifacts = artifacts
        self.metadata = metadata
    }
}

/// An artifact produced by a task
public struct TaskArtifact: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let type: ArtifactType
    public let content: ArtifactContent

    public init(id: UUID = UUID(), name: String, type: ArtifactType, content: ArtifactContent) {
        self.id = id
        self.name = name
        self.type = type
        self.content = content
    }
}

public enum ArtifactType: String, Sendable {
    case document
    case code
    case data
    case image
    case other
}

public enum ArtifactContent: Sendable {
    case text(String)
    case data(Data)
    case url(URL)
    case documentId(DocumentID)
    case spaceId(SpaceID)
}

// MARK: - Convenience Extensions

extension AgentDelegationManager {
    /// Quick helper to delegate and await completion
    public func delegateAndWait(
        task: TimelineTask,
        from sourceAgent: AgentID,
        to targetAgent: AgentID,
        reason: String,
        timeout: Duration = .seconds(60)
    ) async throws -> TaskResult {
        try await withThrowingTaskGroup(of: TaskResult.self) { group in
            let resultStream = AsyncStream<TaskResult> { continuation in
                Task {
                    _ = await delegate(
                        task: task,
                        from: sourceAgent,
                        to: targetAgent,
                        reason: reason,
                        callback: DelegationCallback(
                            onDeclined: { _, reason in
                                continuation.finish()
                            },
                            onCompleted: { _, result in
                                continuation.yield(result)
                                continuation.finish()
                            },
                            onReturned: { _, reason in
                                continuation.finish()
                            }
                        )
                    )
                }
            }

            group.addTask {
                for await result in resultStream {
                    return result
                }
                throw DelegationError.noResult
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw DelegationError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

public enum DelegationError: Error {
    case noResult
    case timeout
    case declined(String?)
    case returned(String)
}
