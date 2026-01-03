import Foundation
import Hummingbird
import Logging

// MARK: - A2A Server

/// A2A protocol server implementation
public struct A2AServer<Context: RequestContext>: Sendable {
    private let agentCard: AgentCard
    private let taskManager: TaskManager
    private let logger = Logger(label: "AgentKit.A2AServer")

    public init(agentCard: AgentCard, taskManager: TaskManager) {
        self.agentCard = agentCard
        self.taskManager = taskManager
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
        // TODO: Implement SSE streaming
        // For now, fall back to non-streaming
        return try await handleSendMessage(request, context)
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
