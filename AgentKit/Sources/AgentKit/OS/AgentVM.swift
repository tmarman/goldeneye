import Foundation

// MARK: - Agent VM

/// An Agent VM represents an isolated execution environment for an agent.
/// Like a process in Unix, each VM has its own:
/// - Worktree (filesystem sandbox)
/// - Context window (memory)
/// - Tool access (syscalls)
/// - Event subscriptions (interrupts)
public actor AgentVM {
    public let id: AgentID
    public let config: AgentConfiguration

    // Isolation
    private let worktree: Worktree
    private var context: ContextWindow

    // Capabilities (syscalls this VM can make)
    private let capabilities: Set<Capability>

    // Event subscriptions (what wakes this VM)
    private var subscriptions: [EventSubscription]

    // Process tree
    private weak var parent: AgentVM?
    private var children: [AgentID: AgentVM]

    // Resource limits
    private let limits: AgentLimits
    private var resourceUsage: ResourceUsage

    // State
    private var state: VMState

    public init(
        id: AgentID = AgentID(),
        config: AgentConfiguration,
        worktree: Worktree,
        capabilities: Set<Capability> = .standard,
        limits: AgentLimits = .default,
        parent: AgentVM? = nil
    ) {
        self.id = id
        self.config = config
        self.worktree = worktree
        self.context = ContextWindow(limit: config.contextLimit)
        self.capabilities = capabilities
        self.subscriptions = []
        self.parent = parent
        self.children = [:]
        self.limits = limits
        self.resourceUsage = ResourceUsage()
        self.state = .ready
    }

    // MARK: - VM Lifecycle

    /// Spawn a child agent VM
    public func spawn(config: AgentConfiguration) async throws -> AgentVM {
        guard children.count < limits.maxChildAgents else {
            throw VMError.resourceLimitExceeded(.maxChildAgents)
        }

        let childWorktree = try await worktree.createChild(for: config.name)
        let child = AgentVM(
            config: config,
            worktree: childWorktree,
            capabilities: capabilities.intersection(config.requiredCapabilities),
            limits: limits.childLimits,
            parent: self
        )

        children[child.id] = child
        return child
    }

    /// Execute a task in this VM
    public func exec(task: AgentTask) async throws -> AgentEventStream {
        guard state == .ready || state == .suspended else {
            throw VMError.invalidState(current: state, expected: [.ready, .suspended])
        }

        guard resourceUsage.canExecute(task, within: limits) else {
            throw VMError.resourceLimitExceeded(.tokens)
        }

        state = .running(taskId: task.id)

        // Create isolated execution environment
        let sandbox = Sandbox(
            worktree: worktree,
            capabilities: capabilities,
            limits: limits
        )

        // Execute through agent loop
        let loop = AgentLoop(
            agent: self,
            sandbox: sandbox,
            context: context
        )

        return try await loop.execute(task: task)
    }

    /// Suspend execution (like SIGSTOP)
    public func suspend() async {
        guard case .running = state else { return }
        state = .suspended
    }

    /// Resume execution (like SIGCONT)
    public func resume() async {
        guard state == .suspended else { return }
        state = .ready
    }

    /// Terminate the VM (like SIGTERM)
    public func terminate(reason: TerminationReason = .requested) async {
        // Terminate children first
        for child in children.values {
            await child.terminate(reason: .parentTerminated)
        }
        children.removeAll()

        // Cleanup worktree
        try? await worktree.cleanup()

        state = .terminated(reason: reason)
    }

    // MARK: - Event Subscriptions

    /// Subscribe to events (like signal handlers)
    public func subscribe(to filter: EventFilter, priority: SubscriptionPriority = .normal) {
        let subscription = EventSubscription(
            agentId: id,
            filter: filter,
            priority: priority
        )
        subscriptions.append(subscription)
    }

    /// Unsubscribe from events
    public func unsubscribe(from filter: EventFilter) {
        subscriptions.removeAll { $0.filter == filter }
    }

    /// Handle incoming event
    public func handleEvent(_ event: SystemEvent) async {
        guard subscriptions.contains(where: { $0.filter.matches(event) }) else {
            return
        }

        // Wake up if suspended
        if state == .suspended {
            await resume()
        }

        // Queue event for processing
        context.queueEvent(event)
    }

    // MARK: - Resource Tracking

    public var usage: ResourceUsage {
        resourceUsage
    }

    public func recordTokenUsage(_ tokens: TokenUsage) {
        resourceUsage.totalTokens += tokens.inputTokens + tokens.outputTokens
    }
}

// MARK: - Supporting Types

public enum VMState: Equatable {
    case ready
    case running(taskId: TaskID)
    case suspended
    case terminated(reason: TerminationReason)
}

public enum TerminationReason: Equatable {
    case requested
    case parentTerminated
    case resourceLimitExceeded
    case error(String)
    case timeout
}

public enum VMError: Error {
    case invalidState(current: VMState, expected: [VMState])
    case resourceLimitExceeded(ResourceType)
    case capabilityDenied(Capability)
    case worktreeError(String)
}

public enum ResourceType {
    case tokens
    case iterations
    case time
    case storage
    case maxChildAgents
}

/// Capabilities an agent VM can have (like syscalls)
public enum Capability: Hashable {
    // File operations
    case fileRead
    case fileWrite
    case fileDelete

    // Network
    case networkAccess
    case webSearch
    case webFetch

    // Execution
    case shellExec
    case shellExecPrivileged

    // Agent operations
    case spawnAgent
    case sendA2A
    case emitEvent

    // System
    case accessSecrets
    case modifySchedule

    public static let standard: Set<Capability> = [
        .fileRead, .fileWrite,
        .networkAccess, .webSearch, .webFetch,
        .shellExec,
        .spawnAgent, .sendA2A, .emitEvent
    ]

    public static let restricted: Set<Capability> = [
        .fileRead,
        .webSearch
    ]
}

/// Resource limits for an agent VM (like ulimits)
public struct AgentLimits {
    public var maxTokensPerTask: Int
    public var maxIterationsPerTask: Int
    public var maxConcurrentTasks: Int
    public var maxChildAgents: Int
    public var maxWorktreeSize: Int // bytes
    public var timeout: Duration

    public var toolAllowlist: Set<String>?
    public var toolDenylist: Set<String>?

    public static let `default` = AgentLimits(
        maxTokensPerTask: 128_000,
        maxIterationsPerTask: 100,
        maxConcurrentTasks: 5,
        maxChildAgents: 10,
        maxWorktreeSize: 1_073_741_824, // 1GB
        timeout: .seconds(3600)
    )

    public var childLimits: AgentLimits {
        AgentLimits(
            maxTokensPerTask: maxTokensPerTask / 2,
            maxIterationsPerTask: maxIterationsPerTask,
            maxConcurrentTasks: maxConcurrentTasks / 2,
            maxChildAgents: maxChildAgents / 2,
            maxWorktreeSize: maxWorktreeSize / 4,
            timeout: timeout
        )
    }
}

/// Tracks resource usage within a VM
public struct ResourceUsage {
    public var totalTokens: Int = 0
    public var totalIterations: Int = 0
    public var activeTasks: Int = 0
    public var storageUsed: Int = 0
    public var startTime: Date = Date()

    public func canExecute(_ task: AgentTask, within limits: AgentLimits) -> Bool {
        activeTasks < limits.maxConcurrentTasks
    }
}

/// An isolated filesystem for an agent
public struct Worktree {
    public let id: String
    public let path: URL
    public let branch: String
    public let baseBranch: String

    public func createChild(for name: String) async throws -> Worktree {
        // Implementation would create a new worktree
        fatalError("TODO: Implement worktree creation")
    }

    public func cleanup() async throws {
        // Implementation would remove worktree
        fatalError("TODO: Implement worktree cleanup")
    }
}

/// Agent's working memory
public struct ContextWindow {
    public let limit: Int
    public var messages: [Message]
    public var pendingEvents: [SystemEvent]

    public init(limit: Int) {
        self.limit = limit
        self.messages = []
        self.pendingEvents = []
    }

    public mutating func queueEvent(_ event: SystemEvent) {
        pendingEvents.append(event)
    }
}

/// Sandbox execution environment
public struct Sandbox {
    public let worktree: Worktree
    public let capabilities: Set<Capability>
    public let limits: AgentLimits

    public func checkCapability(_ capability: Capability) throws {
        guard capabilities.contains(capability) else {
            throw VMError.capabilityDenied(capability)
        }
    }
}
