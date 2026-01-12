import AgentKit
import Foundation

/// A2A Protocol client for communicating with agents
public actor A2AClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private var requestId: Int = 0

    public init(baseURL: URL) {
        self.baseURL = baseURL
        self.urlSession = URLSession(configuration: .default)
    }

    // MARK: - Agent Card

    /// Fetch the agent card from /.well-known/agent.json
    public func fetchAgentCard() async throws -> AgentCard {
        let url = baseURL.appendingPathComponent(".well-known/agent.json")
        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw A2AClientError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AgentCard.self, from: data)
    }

    // MARK: - Task Operations

    /// Send a message to create or continue a task
    public func sendMessage(
        _ message: A2AMessage,
        contextId: String? = nil,
        blocking: Bool = false
    ) async throws -> A2ATask {
        let params = ClientSendMessageParams(
            message: message,
            configuration: MessageConfiguration(
                blocking: blocking,
                acceptedOutputModes: ["text"]
            )
        )

        let response: ClientJSONRPCResponse<A2ATask> = try await call(method: "SendMessage", params: params)

        if let error = response.error {
            throw A2AClientError.rpcError(code: error.code, message: error.message)
        }

        guard let result = response.result else {
            throw A2AClientError.noResult
        }

        return result
    }

    /// Send a streaming message and receive SSE events
    public func sendStreamingMessage(
        _ message: A2AMessage,
        contextId: String? = nil
    ) -> AsyncThrowingStream<A2AStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let params = ClientSendMessageParams(
                        message: message,
                        configuration: MessageConfiguration(
                            blocking: false,
                            acceptedOutputModes: ["text"]
                        )
                    )

                    let request = try await buildStreamRequest(method: "SendStreamingMessage", params: params)

                    let (bytes, response) = try await urlSession.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200
                    else {
                        throw A2AClientError.invalidResponse
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let json = String(line.dropFirst(6))
                            if let data = json.data(using: .utf8) {
                                let decoder = JSONDecoder()
                                decoder.keyDecodingStrategy = .convertFromSnakeCase
                                let event = try decoder.decode(A2AStreamEvent.self, from: data)
                                let isFinal = event.isFinal
                                continuation.yield(event)

                                // Check for terminal event
                                if isFinal {
                                    break
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Get task by ID
    public func getTask(id: String, historyLength: Int? = nil) async throws -> A2ATask {
        let params = ClientGetTaskParams(id: id, historyLength: historyLength)
        let response: ClientJSONRPCResponse<A2ATask> = try await call(method: "GetTask", params: params)

        if let error = response.error {
            throw A2AClientError.rpcError(code: error.code, message: error.message)
        }

        guard let result = response.result else {
            throw A2AClientError.noResult
        }

        return result
    }

    /// List tasks with optional pagination
    public func listTasks(contextId: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> [A2ATask] {
        let params = ClientListTasksParams(contextId: contextId, limit: limit, offset: offset)
        let response: ClientJSONRPCResponse<[A2ATask]> = try await call(method: "ListTasks", params: params)

        if let error = response.error {
            throw A2AClientError.rpcError(code: error.code, message: error.message)
        }

        return response.result ?? []
    }

    /// Cancel a running task
    public func cancelTask(id: String) async throws -> A2ATask {
        let params = ClientCancelTaskParams(id: id)
        let response: ClientJSONRPCResponse<A2ATask> = try await call(method: "CancelTask", params: params)

        if let error = response.error {
            throw A2AClientError.rpcError(code: error.code, message: error.message)
        }

        guard let result = response.result else {
            throw A2AClientError.noResult
        }

        return result
    }

    // MARK: - Health Check

    public func healthCheck() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        let (_, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    // MARK: - Approvals

    /// Fetch pending approval requests
    public func fetchPendingApprovals() async throws -> [ClientApprovalRequest] {
        let url = baseURL.appendingPathComponent("a2a/approvals")
        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw A2AClientError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([ClientApprovalRequest].self, from: data)
    }

    /// Respond to an approval request
    public func respondToApproval(id: String, approved: Bool, reason: String? = nil) async throws {
        let url = baseURL.appendingPathComponent("a2a/approval/\(id)/respond")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let params = ClientApprovalResponse(
            action: approved ? "approved" : "denied",
            reason: reason
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(params)

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw A2AClientError.invalidResponse
        }
    }

    // MARK: - Private Helpers

    private func call<P: Encodable, R: Decodable>(method: String, params: P) async throws -> ClientJSONRPCResponse<R> {
        requestId += 1

        let request = ClientJSONRPCRequest(
            jsonrpc: "2.0",
            id: requestId,
            method: method,
            params: params
        )

        let url = baseURL.appendingPathComponent("a2a")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw A2AClientError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ClientJSONRPCResponse<R>.self, from: data)
    }

    private func buildStreamRequest<P: Encodable>(method: String, params: P) async throws -> URLRequest {
        requestId += 1

        let request = ClientJSONRPCRequest(
            jsonrpc: "2.0",
            id: requestId,
            method: method,
            params: params
        )

        let url = baseURL.appendingPathComponent("a2a")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        return urlRequest
    }
}

// MARK: - Client-specific Types (to avoid conflicts with AgentKit types)

private struct ClientJSONRPCRequest<P: Encodable>: Encodable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: P
}

private struct ClientJSONRPCResponse<R: Decodable>: Decodable {
    let jsonrpc: String
    let id: Int?
    let result: R?
    let error: ClientJSONRPCError?
}

private struct ClientJSONRPCError: Decodable {
    let code: Int
    let message: String
}

private struct ClientSendMessageParams: Encodable {
    let message: A2AMessage
    let configuration: MessageConfiguration
}

private struct ClientGetTaskParams: Encodable {
    let id: String
    let historyLength: Int?
}

private struct ClientListTasksParams: Encodable {
    let contextId: String?
    let limit: Int
    let offset: Int
}

private struct ClientCancelTaskParams: Encodable {
    let id: String
}

// MARK: - Approval Types

public struct ClientApprovalRequest: Codable, Sendable, Identifiable {
    public let id: String
    public let taskId: String
    public let action: String
    public let description: String
    public let riskLevel: String
    public let canModify: Bool

    public var risk: ClientRiskLevel {
        ClientRiskLevel(rawValue: riskLevel) ?? .medium
    }
}

public enum ClientRiskLevel: String, Codable, Sendable {
    case low, medium, high, critical
}

private struct ClientApprovalResponse: Encodable {
    let action: String
    let reason: String?
}

// MARK: - Stream Events

public enum A2AStreamEvent: Decodable, Sendable {
    case task(A2ATask)
    case message(A2AMessage)
    case statusUpdate(TaskStatusUpdateEvent)
    case artifactUpdate(TaskArtifactUpdateEvent)

    /// Returns true if this is a terminal event
    public var isFinal: Bool {
        switch self {
        case .statusUpdate(let update):
            return update.final
        case .task(let task):
            return task.status.state.isTerminal
        default:
            return false
        }
    }

    enum CodingKeys: String, CodingKey {
        case task
        case message
        case statusUpdate
        case artifactUpdate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let task = try container.decodeIfPresent(A2ATask.self, forKey: .task) {
            self = .task(task)
        } else if let message = try container.decodeIfPresent(A2AMessage.self, forKey: .message) {
            self = .message(message)
        } else if let update = try container.decodeIfPresent(TaskStatusUpdateEvent.self, forKey: .statusUpdate) {
            self = .statusUpdate(update)
        } else if let update = try container.decodeIfPresent(TaskArtifactUpdateEvent.self, forKey: .artifactUpdate) {
            self = .artifactUpdate(update)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown stream event type"
                )
            )
        }
    }
}

public struct TaskStatusUpdateEvent: Codable, Sendable {
    public let taskId: String
    public let contextId: String
    public let status: A2ATaskStatus
    public let final: Bool
}

public struct TaskArtifactUpdateEvent: Codable, Sendable {
    public let taskId: String
    public let contextId: String
    public let artifact: A2AArtifact
    public let append: Bool
    public let lastChunk: Bool
}

// MARK: - Errors

public enum A2AClientError: Error, LocalizedError {
    case invalidResponse
    case noResult
    case rpcError(code: Int, message: String)
    case connectionFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from agent"
        case .noResult:
            return "No result in response"
        case .rpcError(let code, let message):
            return "RPC Error \(code): \(message)"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        }
    }
}
