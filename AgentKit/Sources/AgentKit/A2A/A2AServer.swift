import Foundation
import Hummingbird
import Logging

// MARK: - A2A Server

/// A2A protocol server implementation
public struct A2AServer<Context: RequestContext>: Sendable {
    private let agentCard: AgentCard
    private let taskManager: TaskManager
    private let approvalManager: ApprovalManager
    private let logger = Logger(label: "AgentKit.A2AServer")

    public init(agentCard: AgentCard, taskManager: TaskManager, approvalManager: ApprovalManager) {
        self.agentCard = agentCard
        self.taskManager = taskManager
        self.approvalManager = approvalManager
    }

    /// Configure routes on a Hummingbird router
    public func configure(router: Router<Context>) {
        // Agent Card discovery
        router.get("/.well-known/agent.json") { _, _ -> Response in
            let data = try JSONEncoder().encode(self.agentCard)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: data))
            )
        }

        // A2A endpoints
        let a2a = router.group("/a2a")

        // Send message (create/continue task)
        a2a.post("/message") { request, context in
            try await self.handleSendMessage(request, context)
        }

        // Send streaming message
        a2a.post("/message/stream") { request, context in
            try await self.handleStreamingMessage(request, context)
        }

        // Get task
        a2a.get("/task/{id}") { request, context in
            try await self.handleGetTask(request, context)
        }

        // List tasks
        a2a.get("/tasks") { request, context in
            try await self.handleListTasks(request, context)
        }

        // Cancel task
        a2a.post("/task/{id}/cancel") { request, context in
            try await self.handleCancelTask(request, context)
        }

        // Approval endpoints
        a2a.get("/approvals") { request, context in
            try await self.handleListApprovals(request, context)
        }

        a2a.post("/approval/{id}/respond") { request, context in
            try await self.handleRespondToApproval(request, context)
        }
    }

    // MARK: - Handlers

    private func handleSendMessage(_ request: Request, _ context: Context) async throws -> Response {
        let body = try await request.body.collect(upTo: .max)
        let rpcRequest = try JSONDecoder().decode(
            JSONRPCRequest<SendMessageParams>.self,
            from: body
        )

        guard let params = rpcRequest.params else {
            let error = JSONRPCResponse<A2ATask>(
                id: rpcRequest.id,
                error: .invalidParams("Missing params")
            )
            let errorData = try JSONEncoder().encode(error)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: errorData))
            )
        }

        let task = try await taskManager.sendMessage(params.message, configuration: params.configuration)

        let response = JSONRPCResponse(id: rpcRequest.id, result: task)
        let responseData = try JSONEncoder().encode(response)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: responseData))
        )
    }

    private func handleStreamingMessage(_ request: Request, _ context: Context) async throws -> Response {
        let body = try await request.body.collect(upTo: .max)
        let rpcRequest = try JSONDecoder().decode(
            JSONRPCRequest<SendMessageParams>.self,
            from: body
        )

        guard let params = rpcRequest.params else {
            let error = JSONRPCResponse<A2ATask>(
                id: rpcRequest.id,
                error: .invalidParams("Missing params")
            )
            let errorData = try JSONEncoder().encode(error)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: errorData))
            )
        }

        // Get the task and event stream (task is yielded in the stream)
        let (_, eventStream) = try await taskManager.sendMessageStreaming(
            params.message,
            configuration: params.configuration
        )

        // Create SSE response with streaming body
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        return Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache",
                .connection: "keep-alive"
            ],
            body: .init(asyncSequence: SSEEventSequence(
                eventStream: eventStream,
                encoder: encoder
            ))
        )
    }

    private func handleGetTask(_ request: Request, _ context: Context) async throws -> Response {
        guard let id = context.parameters.get("id") else {
            throw HTTPError(.badRequest, message: "Missing task ID")
        }

        guard let task = await taskManager.getTask(id) else {
            throw HTTPError(.notFound, message: "Task not found: \(id)")
        }

        let taskData = try JSONEncoder().encode(task)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: taskData))
        )
    }

    private func handleListTasks(_ request: Request, _ context: Context) async throws -> Response {
        let tasks = await taskManager.listTasks()

        let tasksData = try JSONEncoder().encode(tasks)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: tasksData))
        )
    }

    private func handleCancelTask(_ request: Request, _ context: Context) async throws -> Response {
        guard let id = context.parameters.get("id") else {
            throw HTTPError(.badRequest, message: "Missing task ID")
        }

        try await taskManager.cancelTask(id)

        return Response(status: .ok)
    }

    // MARK: - Approval Handlers

    private func handleListApprovals(_ request: Request, _ context: Context) async throws -> Response {
        let pending = await approvalManager.pending()

        // Convert to API format
        let apiApprovals = pending.map { request -> APIApprovalRequest in
            APIApprovalRequest(
                id: request.id,
                taskId: request.taskId,
                action: request.action,
                description: request.description,
                riskLevel: request.riskLevel.rawValue,
                canModify: request.canModify
            )
        }

        let data = try JSONEncoder().encode(apiApprovals)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }

    private func handleRespondToApproval(_ request: Request, _ context: Context) async throws -> Response {
        guard let id = context.parameters.get("id") else {
            throw HTTPError(.badRequest, message: "Missing approval ID")
        }

        let body = try await request.body.collect(upTo: .max)
        let responseParams = try JSONDecoder().decode(ApprovalResponseParams.self, from: body)

        // Convert to ApprovalResponse
        let response: ApprovalResponse
        switch responseParams.action {
        case "approved":
            response = .approved
        case "denied":
            response = .denied(reason: responseParams.reason)
        default:
            throw HTTPError(.badRequest, message: "Invalid action: \(responseParams.action)")
        }

        await approvalManager.respondToApproval(id: id, response: response)

        return Response(status: .ok)
    }
}

// MARK: - API Types for Approvals

struct APIApprovalRequest: Codable, Sendable {
    let id: String
    let taskId: String
    let action: String
    let description: String
    let riskLevel: String
    let canModify: Bool
}

struct ApprovalResponseParams: Codable, Sendable {
    let action: String  // "approved" or "denied"
    let reason: String?
}

// MARK: - Request Types

struct SendMessageParams: Codable, Sendable {
    let message: A2AMessage
    let configuration: MessageConfiguration?
}

public struct MessageConfiguration: Codable, Sendable {
    public let blocking: Bool?
    public let historyLength: Int?
    public let acceptedOutputModes: [String]?

    public init(blocking: Bool? = nil, historyLength: Int? = nil, acceptedOutputModes: [String]? = nil) {
        self.blocking = blocking
        self.historyLength = historyLength
        self.acceptedOutputModes = acceptedOutputModes
    }

    enum CodingKeys: String, CodingKey {
        case blocking
        case historyLength = "history_length"
        case acceptedOutputModes = "accepted_output_modes"
    }
}

// MARK: - Task Manager

/// Manages task lifecycle
public actor TaskManager {
    private var tasks: [String: A2ATask] = [:]
    private var agents: [String: any Agent] = [:]
    private let agentFactory: AgentFactory

    public init(agentFactory: @escaping AgentFactory) {
        self.agentFactory = agentFactory
    }

    public typealias AgentFactory = @Sendable (A2AMessage) async throws -> any Agent

    /// Send a message, creating or continuing a task
    public func sendMessage(
        _ message: A2AMessage,
        configuration: MessageConfiguration?
    ) async throws -> A2ATask {
        let taskId = message.taskId ?? UUID().uuidString
        let contextId = message.contextId ?? UUID().uuidString

        // Create or get existing task
        var task = tasks[taskId] ?? A2ATask(
            id: taskId,
            contextId: contextId,
            status: A2ATaskStatus(state: .submitted)
        )

        // Add message to history
        var history = task.history ?? []
        history.append(message)
        task.history = history

        // Update status
        task.status = A2ATaskStatus(state: .working)
        tasks[taskId] = task

        // Create agent if needed
        if agents[taskId] == nil {
            let agent = try await agentFactory(message)
            agents[taskId] = agent
        }

        // Execute in background
        Task {
            await executeTask(taskId)
        }

        return task
    }

    /// Send a message with streaming response
    public func sendMessageStreaming(
        _ message: A2AMessage,
        configuration: MessageConfiguration?
    ) async throws -> (A2ATask, AsyncThrowingStream<A2AStreamResponse, Error>) {
        let taskId = message.taskId ?? UUID().uuidString
        let contextId = message.contextId ?? UUID().uuidString

        // Create or get existing task
        var task = tasks[taskId] ?? A2ATask(
            id: taskId,
            contextId: contextId,
            status: A2ATaskStatus(state: .submitted)
        )

        // Add message to history
        var history = task.history ?? []
        history.append(message)
        task.history = history

        // Update status
        task.status = A2ATaskStatus(state: .working)
        tasks[taskId] = task

        // Create agent if needed
        if agents[taskId] == nil {
            let agent = try await agentFactory(message)
            agents[taskId] = agent
        }

        // Create event stream
        let stream = AsyncThrowingStream<A2AStreamResponse, Error> { continuation in
            Task {
                await self.executeTaskStreaming(taskId, continuation: continuation)
            }
        }

        return (task, stream)
    }

    /// Execute task and stream events
    private func executeTaskStreaming(
        _ taskId: String,
        continuation: AsyncThrowingStream<A2AStreamResponse, Error>.Continuation
    ) async {
        guard let agent = agents[taskId],
              var task = tasks[taskId]
        else {
            continuation.finish()
            return
        }

        // Send initial task event
        continuation.yield(.task(task))

        // Convert A2A message to AgentTask
        let lastMessage = task.history?.last
        let agentMessage = Message(
            role: .user,
            content: .text(lastMessage?.parts.compactMap { part -> String? in
                if case .text(let t) = part { return t.text }
                return nil
            }.joined() ?? "")
        )

        let agentTask = AgentTask(
            id: TaskID(taskId),
            contextId: ContextID(task.contextId),
            message: agentMessage
        )

        // Execute and stream events
        do {
            for try await event in await agent.execute(agentTask) {
                var isFinal = false

                switch event {
                case .working(let workingEvent):
                    // Stream working status with optional description
                    let statusMessage = workingEvent.description.map { description in
                        A2AMessage(
                            contextId: task.contextId,
                            taskId: taskId,
                            role: .agent,
                            parts: [.text(A2APart.TextPart(text: description))]
                        )
                    }
                    let statusEvent = TaskStatusUpdateEvent(
                        taskId: taskId,
                        contextId: task.contextId,
                        status: A2ATaskStatus(state: .working, message: statusMessage),
                        final: false
                    )
                    continuation.yield(.statusUpdate(statusEvent))

                case .toolCall(let call):
                    // Stream tool calls as status updates
                    let toolMessage = A2AMessage(
                        contextId: task.contextId,
                        taskId: taskId,
                        role: .agent,
                        parts: [.text(A2APart.TextPart(text: "Using tool: \(call.toolName)"))]
                    )
                    let statusEvent = TaskStatusUpdateEvent(
                        taskId: taskId,
                        contextId: task.contextId,
                        status: A2ATaskStatus(state: .working, message: toolMessage),
                        final: false
                    )
                    continuation.yield(.statusUpdate(statusEvent))

                case .message(let msg):
                    // Stream message content
                    let a2aMessage = A2AMessage(
                        contextId: task.contextId,
                        taskId: taskId,
                        role: .agent,
                        parts: [.text(A2APart.TextPart(text: msg.textContent))]
                    )
                    continuation.yield(.message(a2aMessage))

                case .completed:
                    task.status = A2ATaskStatus(state: .completed)
                    isFinal = true

                case .failed:
                    task.status = A2ATaskStatus(state: .failed)
                    isFinal = true

                case .inputRequired:
                    task.status = A2ATaskStatus(state: .inputRequired)
                    isFinal = true

                case .cancelled:
                    task.status = A2ATaskStatus(state: .cancelled)
                    isFinal = true

                default:
                    break
                }

                tasks[taskId] = task

                if isFinal {
                    let statusEvent = TaskStatusUpdateEvent(
                        taskId: taskId,
                        contextId: task.contextId,
                        status: task.status,
                        final: true
                    )
                    continuation.yield(.statusUpdate(statusEvent))
                    continuation.finish()
                    return
                }
            }

            // If we get here without a terminal event, mark as completed
            task.status = A2ATaskStatus(state: .completed)
            tasks[taskId] = task
            let statusEvent = TaskStatusUpdateEvent(
                taskId: taskId,
                contextId: task.contextId,
                status: task.status,
                final: true
            )
            continuation.yield(.statusUpdate(statusEvent))
            continuation.finish()

        } catch {
            task.status = A2ATaskStatus(state: .failed)
            tasks[taskId] = task
            continuation.finish(throwing: error)
        }
    }

    private func executeTask(_ taskId: String) async {
        guard let agent = agents[taskId],
              var task = tasks[taskId]
        else { return }

        // Convert A2A message to AgentTask
        let lastMessage = task.history?.last
        let agentMessage = Message(
            role: .user,
            content: .text(lastMessage?.parts.compactMap { part -> String? in
                if case .text(let t) = part { return t.text }
                return nil
            }.joined() ?? "")
        )

        let agentTask = AgentTask(
            id: TaskID(taskId),
            contextId: ContextID(task.contextId),
            message: agentMessage
        )

        // Execute and collect events
        do {
            for try await event in await agent.execute(agentTask) {
                switch event {
                case .completed:
                    task.status = A2ATaskStatus(state: .completed)
                case .failed:
                    task.status = A2ATaskStatus(state: .failed)
                case .inputRequired:
                    task.status = A2ATaskStatus(state: .inputRequired)
                case .cancelled:
                    task.status = A2ATaskStatus(state: .cancelled)
                default:
                    break
                }
                tasks[taskId] = task
            }
        } catch {
            task.status = A2ATaskStatus(state: .failed)
            tasks[taskId] = task
        }
    }

    /// Get a task by ID
    public func getTask(_ id: String) -> A2ATask? {
        tasks[id]
    }

    /// List all tasks
    public func listTasks() -> [A2ATask] {
        Array(tasks.values)
    }

    /// Cancel a task
    public func cancelTask(_ id: String) async throws {
        guard var task = tasks[id] else {
            throw HTTPError(.notFound, message: "Task not found")
        }

        if let agent = agents[id] {
            await agent.cancel()
        }

        task.status = A2ATaskStatus(state: .cancelled)
        tasks[id] = task
    }
}

// MARK: - SSE Event Sequence

/// Converts A2AStreamResponse to SSE-formatted byte chunks
struct SSEEventSequence: AsyncSequence, Sendable {
    typealias Element = ByteBuffer

    let eventStream: AsyncThrowingStream<A2AStreamResponse, Error>
    let encoder: JSONEncoder

    struct AsyncIterator: AsyncIteratorProtocol {
        var eventIterator: AsyncThrowingStream<A2AStreamResponse, Error>.AsyncIterator
        let encoder: JSONEncoder

        mutating func next() async throws -> ByteBuffer? {
            guard let event = try await eventIterator.next() else {
                return nil
            }

            // Encode event to JSON
            let eventData: Data
            switch event {
            case .task(let task):
                let wrapper = ["task": task]
                eventData = try encoder.encode(wrapper)
            case .message(let message):
                let wrapper = ["message": message]
                eventData = try encoder.encode(wrapper)
            case .statusUpdate(let update):
                let wrapper = ["statusUpdate": update]
                eventData = try encoder.encode(wrapper)
            case .artifactUpdate(let update):
                let wrapper = ["artifactUpdate": update]
                eventData = try encoder.encode(wrapper)
            }

            // Format as SSE: "data: {json}\n\n"
            let jsonString = String(data: eventData, encoding: .utf8) ?? "{}"
            let sseData = "data: \(jsonString)\n\n"

            var buffer = ByteBuffer()
            buffer.writeString(sseData)
            return buffer
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            eventIterator: eventStream.makeAsyncIterator(),
            encoder: encoder
        )
    }
}
