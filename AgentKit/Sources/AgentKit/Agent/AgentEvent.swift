import Foundation

// MARK: - Agent Events

/// Events emitted during agent execution
public enum AgentEvent: Sendable {
    /// Task has been received and queued
    case taskSubmitted(TaskID)

    /// Agent is actively working
    case working(WorkingEvent)

    /// Agent is waiting for human input
    case inputRequired(ApprovalRequest)

    /// Agent generated a message
    case message(Message)

    /// Agent is calling a tool
    case toolCall(ToolCallEvent)

    /// Tool execution completed
    case toolResult(ToolResultEvent)

    /// Agent produced an artifact
    case artifact(Artifact)

    /// Streaming text chunk
    case textDelta(TextDeltaEvent)

    /// Task completed successfully
    case completed(CompletedEvent)

    /// Task failed
    case failed(FailedEvent)

    /// Task was cancelled
    case cancelled

    /// Task state changed
    case stateChanged(TaskState)
}

// MARK: - Event Details

public struct WorkingEvent: Sendable {
    public let taskId: TaskID
    public let iteration: Int
    public let description: String?

    public init(taskId: TaskID, iteration: Int, description: String? = nil) {
        self.taskId = taskId
        self.iteration = iteration
        self.description = description
    }
}

public struct ToolCallEvent: Sendable {
    public let id: String
    public let toolName: String
    public let input: ToolInput
    public let timestamp: Date

    public init(id: String, toolName: String, input: ToolInput, timestamp: Date = .now) {
        self.id = id
        self.toolName = toolName
        self.input = input
        self.timestamp = timestamp
    }
}

public struct ToolResultEvent: Sendable {
    public let callId: String
    public let toolName: String
    public let output: ToolOutput
    public let duration: Duration
    public let timestamp: Date

    public init(
        callId: String,
        toolName: String,
        output: ToolOutput,
        duration: Duration,
        timestamp: Date = .now
    ) {
        self.callId = callId
        self.toolName = toolName
        self.output = output
        self.duration = duration
        self.timestamp = timestamp
    }
}

public struct TextDeltaEvent: Sendable {
    public let taskId: TaskID
    public let delta: String
    public let timestamp: Date

    public init(taskId: TaskID, delta: String, timestamp: Date = .now) {
        self.taskId = taskId
        self.delta = delta
        self.timestamp = timestamp
    }
}

public struct CompletedEvent: Sendable {
    public let taskId: TaskID
    public let result: Message?
    public let artifacts: [Artifact]
    public let duration: Duration
    public let tokenUsage: TokenUsage?

    public init(
        taskId: TaskID,
        result: Message? = nil,
        artifacts: [Artifact] = [],
        duration: Duration,
        tokenUsage: TokenUsage? = nil
    ) {
        self.taskId = taskId
        self.result = result
        self.artifacts = artifacts
        self.duration = duration
        self.tokenUsage = tokenUsage
    }
}

public struct FailedEvent: Sendable {
    public let taskId: TaskID
    public let error: AgentError
    public let timestamp: Date

    public init(taskId: TaskID, error: AgentError, timestamp: Date = .now) {
        self.taskId = taskId
        self.error = error
        self.timestamp = timestamp
    }
}

public struct TokenUsage: Sendable, Codable {
    public let inputTokens: Int
    public let outputTokens: Int
    public var totalTokens: Int { inputTokens + outputTokens }

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

// MARK: - Task State (A2A)

/// Task states per A2A protocol
public enum TaskState: String, Sendable, Codable {
    case submitted = "TASK_STATE_SUBMITTED"
    case working = "TASK_STATE_WORKING"
    case inputRequired = "TASK_STATE_INPUT_REQUIRED"
    case authRequired = "TASK_STATE_AUTH_REQUIRED"
    case completed = "TASK_STATE_COMPLETED"
    case failed = "TASK_STATE_FAILED"
    case cancelled = "TASK_STATE_CANCELLED"
    case rejected = "TASK_STATE_REJECTED"

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .rejected:
            return true
        case .submitted, .working, .inputRequired, .authRequired:
            return false
        }
    }
}

// MARK: - Errors

public enum AgentError: Error, Sendable {
    case taskNotFound(TaskID)
    case taskAlreadyRunning(TaskID)
    case taskCancelled
    case approvalDenied(tool: String, reason: String?)
    case approvalTimeout(tool: String)
    case toolExecutionFailed(tool: String, underlying: String)
    case llmError(String)
    case contextOverflow
    case maxIterationsExceeded
    case invalidConfiguration(String)
}
