import Foundation
import Logging

// MARK: - Agent Loop

/// The core execution engine for agents.
///
/// AgentLoop implements the observe-think-act cycle:
/// 1. Observe: Gather context (messages, tool results)
/// 2. Think: Call LLM to decide next action
/// 3. Act: Execute tools or produce output
/// 4. Repeat until done or human intervention needed
public actor AgentLoop: Agent {
    public let id: AgentID
    public let configuration: AgentConfiguration

    private var state: LoopState = .idle
    private var currentTask: AgentTask?
    private var messages: [Message] = []
    private var iteration: Int = 0

    private let session: Session
    private let approvalManager: ApprovalManager
    private let hookManager: ToolHookManager
    private let logger: Logger

    public init(
        id: AgentID = AgentID(),
        configuration: AgentConfiguration,
        session: Session,
        approvalManager: ApprovalManager = ApprovalManager(),
        hookManager: ToolHookManager = ToolHookManager()
    ) {
        self.id = id
        self.configuration = configuration
        self.session = session
        self.approvalManager = approvalManager
        self.hookManager = hookManager
        self.logger = Logger(label: "AgentKit.AgentLoop.\(id.rawValue)")
    }

    /// Add a tool execution hook
    public func addHook(_ hook: any ToolExecutionHook) async {
        await hookManager.add(hook)
    }

    // MARK: - Agent Protocol

    public func execute(_ task: AgentTask) -> AgentEventStream {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runLoop(task: task, continuation: continuation)
                } catch {
                    continuation.yield(.failed(FailedEvent(
                        taskId: task.id,
                        error: error as? AgentError ?? .llmError(error.localizedDescription)
                    )))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func pause() async {
        guard state == .running else { return }
        state = .paused
        logger.info("Agent paused", metadata: ["task": "\(currentTask?.id.rawValue ?? "none")"])
    }

    public func resume() async {
        guard state == .paused else { return }
        state = .running
        logger.info("Agent resumed", metadata: ["task": "\(currentTask?.id.rawValue ?? "none")"])
    }

    public func cancel() async {
        state = .cancelled
        logger.info("Agent cancelled", metadata: ["task": "\(currentTask?.id.rawValue ?? "none")"])
    }

    // MARK: - Core Loop

    private func runLoop(
        task: AgentTask,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws {
        let startTime = ContinuousClock.now

        // Initialize
        currentTask = task
        state = .running
        iteration = 0
        messages = [
            Message(role: .system, content: .text(configuration.systemPrompt)),
            task.message
        ]

        continuation.yield(.taskSubmitted(task.id))
        continuation.yield(.stateChanged(.working))

        // Main loop
        while state == .running {
            iteration += 1

            // Check limits
            guard iteration <= configuration.maxIterations else {
                throw AgentError.maxIterationsExceeded
            }

            continuation.yield(.working(WorkingEvent(
                taskId: task.id,
                iteration: iteration
            )))

            // Think: Call LLM
            let response = try await configuration.llmProvider.complete(messages)
            var assistantContent: [MessageContent] = []

            // Process response
            for try await token in response {
                switch token {
                case .text(let text):
                    continuation.yield(.textDelta(TextDeltaEvent(
                        taskId: task.id,
                        delta: text
                    )))
                    // Accumulate text
                    if case .text(var existing) = assistantContent.last {
                        existing += text
                        assistantContent[assistantContent.count - 1] = .text(existing)
                    } else {
                        assistantContent.append(.text(text))
                    }

                case .textDelta(let delta):
                    continuation.yield(.textDelta(TextDeltaEvent(
                        taskId: task.id,
                        delta: delta
                    )))
                    // Accumulate text
                    if case .text(var existing) = assistantContent.last {
                        existing += delta
                        assistantContent[assistantContent.count - 1] = .text(existing)
                    } else {
                        assistantContent.append(.text(delta))
                    }

                case .toolCall(let call):
                    assistantContent.append(.toolUse(ToolUse(
                        id: call.id,
                        name: call.name,
                        input: call.input
                    )))
                    continuation.yield(.toolCall(ToolCallEvent(
                        id: call.id,
                        toolName: call.name,
                        input: call.input
                    )))

                case .usage(let usage):
                    logger.debug("Token usage", metadata: [
                        "input": "\(usage.inputTokens)",
                        "output": "\(usage.outputTokens)"
                    ])

                case .error(let error):
                    logger.error("LLM error: \(error)")
                    throw AgentError.llmError(String(describing: error))

                case .done:
                    break
                }
            }

            // Add assistant message
            let assistantMessage = Message(role: .assistant, content: assistantContent)
            messages.append(assistantMessage)
            continuation.yield(.message(assistantMessage))

            // Act: Execute tool calls
            let toolUses = assistantContent.compactMap { content -> ToolUse? in
                if case .toolUse(let use) = content { return use }
                return nil
            }

            if toolUses.isEmpty {
                // No tool calls = done
                break
            }

            // Execute each tool
            for toolUse in toolUses {
                let result = try await executeToolWithApproval(
                    toolUse: toolUse,
                    task: task,
                    continuation: continuation
                )

                // Add tool result to messages
                messages.append(Message(
                    role: .user,
                    content: .toolResult(ToolResult(
                        toolUseId: toolUse.id,
                        content: result.content,
                        isError: result.isError
                    ))
                ))

                continuation.yield(.toolResult(ToolResultEvent(
                    callId: toolUse.id,
                    toolName: toolUse.name,
                    output: result,
                    duration: .seconds(0) // TODO: measure
                )))
            }

            // Check for pause between iterations
            while state == .paused {
                try await Task.sleep(for: .milliseconds(100))
            }

            if state == .cancelled {
                throw AgentError.taskCancelled
            }
        }

        // Complete
        let duration = ContinuousClock.now - startTime
        continuation.yield(.completed(CompletedEvent(
            taskId: task.id,
            result: messages.last,
            duration: duration
        )))
        continuation.yield(.stateChanged(.completed))
        continuation.finish()

        state = .idle
        currentTask = nil
    }

    // MARK: - Tool Execution

    private func executeToolWithApproval(
        toolUse: ToolUse,
        task: AgentTask,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws -> ToolOutput {
        // Find tool
        guard let tool = configuration.tools.first(where: { $0.name == toolUse.name }) else {
            return ToolOutput(content: "Unknown tool: \(toolUse.name)", isError: true)
        }

        // Check if approval needed
        if tool.requiresApproval {
            let request = ApprovalRequest.action(ActionApproval(
                id: UUID().uuidString,
                taskId: task.id.rawValue,
                action: tool.name,
                description: tool.describeAction(toolUse.input),
                parameters: toolUse.input.parameters,
                risk: tool.riskLevel,
                timeout: .seconds(300)
            ))

            continuation.yield(.inputRequired(request))
            continuation.yield(.stateChanged(.inputRequired))

            // Wait for approval
            let response = try await approvalManager.requestApproval(
                request,
                taskId: task.id.rawValue
            )

            continuation.yield(.stateChanged(.working))

            switch response {
            case .approved:
                break // Continue to execute
            case .denied(let reason):
                throw AgentError.approvalDenied(tool: tool.name, reason: reason)
            case .modified(let newInput):
                // Execute with modified input
                let context = ToolContext(session: session, workingDirectory: session.workingDirectory)
                return try await tool.execute(newInput, context: context)
            case .timeout:
                throw AgentError.approvalTimeout(tool: tool.name)
            }
        }

        // Execute tool with hooks
        let context = ToolContext(session: session, workingDirectory: session.workingDirectory)

        // Before hook
        try await hookManager.runBeforeHooks(
            tool: tool,
            input: toolUse.input,
            context: context
        )

        // Execute
        let output = try await tool.execute(toolUse.input, context: context)

        // After hook (fire-and-forget, don't fail task on hook errors)
        Task {
            do {
                try await hookManager.runAfterHooks(
                    tool: tool,
                    input: toolUse.input,
                    output: output,
                    context: context
                )
            } catch {
                logger.warning("Hook error: \(error.localizedDescription)")
            }
        }

        return output
    }
}

// MARK: - Loop State

private enum LoopState: Sendable {
    case idle
    case running
    case paused
    case cancelled
}
