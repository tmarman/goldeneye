import Foundation

// MARK: - A2A Task

/// Task representation per A2A protocol
public struct A2ATask: Sendable, Codable, Identifiable {
    public let id: String
    public let contextId: String
    public var status: A2ATaskStatus
    public var artifacts: [A2AArtifact]?
    public var history: [A2AMessage]?
    public var metadata: [String: AnyCodable]?

    public init(
        id: String = UUID().uuidString,
        contextId: String = UUID().uuidString,
        status: A2ATaskStatus,
        artifacts: [A2AArtifact]? = nil,
        history: [A2AMessage]? = nil,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.contextId = contextId
        self.status = status
        self.artifacts = artifacts
        self.history = history
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case contextId = "context_id"
        case status, artifacts, history, metadata
    }
}

// MARK: - Task Status

public struct A2ATaskStatus: Sendable, Codable {
    public let state: TaskState
    public var message: A2AMessage?
    public let timestamp: Date

    public init(state: TaskState, message: A2AMessage? = nil, timestamp: Date = .now) {
        self.state = state
        self.message = message
        self.timestamp = timestamp
    }
}

// MARK: - A2A Message

public struct A2AMessage: Sendable, Codable, Identifiable {
    public let id: String?
    public let contextId: String?
    public let taskId: String?
    public let role: Role
    public let parts: [A2APart]
    public let metadata: [String: AnyCodable]?

    public enum Role: String, Sendable, Codable {
        case user
        case agent
    }

    public init(
        id: String? = UUID().uuidString,
        contextId: String? = nil,
        taskId: String? = nil,
        role: Role,
        parts: [A2APart],
        metadata: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.contextId = contextId
        self.taskId = taskId
        self.role = role
        self.parts = parts
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id = "message_id"
        case contextId = "context_id"
        case taskId = "task_id"
        case role, parts, metadata
    }
}

// MARK: - A2A Part

public enum A2APart: Sendable, Codable {
    case text(TextPart)
    case file(FilePart)
    case data(DataPart)

    public struct TextPart: Sendable, Codable {
        public let text: String
        public let metadata: [String: AnyCodable]?

        public init(text: String, metadata: [String: AnyCodable]? = nil) {
            self.text = text
            self.metadata = metadata
        }
    }

    public struct FilePart: Sendable, Codable {
        public let file: FileSource
        public let mimeType: String
        public let name: String?
        public let metadata: [String: AnyCodable]?

        public enum FileSource: Sendable, Codable {
            case uri(String)
            case bytes(Data)
        }

        public init(
            file: FileSource,
            mimeType: String,
            name: String? = nil,
            metadata: [String: AnyCodable]? = nil
        ) {
            self.file = file
            self.mimeType = mimeType
            self.name = name
            self.metadata = metadata
        }

        enum CodingKeys: String, CodingKey {
            case file
            case mimeType = "mime_type"
            case name, metadata
        }
    }

    public struct DataPart: Sendable, Codable {
        public let data: [String: AnyCodable]
        public let metadata: [String: AnyCodable]?

        public init(data: [String: AnyCodable], metadata: [String: AnyCodable]? = nil) {
            self.data = data
            self.metadata = metadata
        }
    }

    // Custom coding for polymorphic parts
    enum CodingKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)

        switch kind {
        case "text":
            self = .text(try TextPart(from: decoder))
        case "file":
            self = .file(try FilePart(from: decoder))
        case "data":
            self = .data(try DataPart(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown part kind: \(kind)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let part):
            try container.encode("text", forKey: .kind)
            try part.encode(to: encoder)
        case .file(let part):
            try container.encode("file", forKey: .kind)
            try part.encode(to: encoder)
        case .data(let part):
            try container.encode("data", forKey: .kind)
            try part.encode(to: encoder)
        }
    }
}

// MARK: - A2A Artifact

public struct A2AArtifact: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let parts: [A2APart]
    public let metadata: [String: AnyCodable]?

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        parts: [A2APart],
        metadata: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.parts = parts
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id = "artifact_id"
        case name, description, parts, metadata
    }
}

// MARK: - Streaming Events

public enum A2AStreamResponse: Sendable, Codable {
    case task(A2ATask)
    case message(A2AMessage)
    case statusUpdate(TaskStatusUpdateEvent)
    case artifactUpdate(TaskArtifactUpdateEvent)
}

public struct TaskStatusUpdateEvent: Sendable, Codable {
    public let taskId: String
    public let contextId: String
    public let status: A2ATaskStatus
    public let final: Bool
    public let metadata: [String: AnyCodable]?

    public init(
        taskId: String,
        contextId: String,
        status: A2ATaskStatus,
        final: Bool = false,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.taskId = taskId
        self.contextId = contextId
        self.status = status
        self.final = final
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case contextId = "context_id"
        case status
        case final
        case metadata
    }
}

public struct TaskArtifactUpdateEvent: Sendable, Codable {
    public let taskId: String
    public let contextId: String
    public let artifact: A2AArtifact
    public let append: Bool
    public let lastChunk: Bool

    public init(
        taskId: String,
        contextId: String,
        artifact: A2AArtifact,
        append: Bool = false,
        lastChunk: Bool = false
    ) {
        self.taskId = taskId
        self.contextId = contextId
        self.artifact = artifact
        self.append = append
        self.lastChunk = lastChunk
    }

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case contextId = "context_id"
        case artifact, append
        case lastChunk = "last_chunk"
    }
}

// MARK: - JSON-RPC

/// JSON-RPC ID supporting both string and integer values
/// Per JSON-RPC 2.0 spec, id can be string, number, or null
public struct JSONRPCId: Codable, Sendable, Hashable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(_ value: Int) {
        self.value = String(value)
    }

    /// Generate a new unique ID
    public static func generate() -> JSONRPCId {
        JSONRPCId(UUID().uuidString)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try string first, then int
        if let stringValue = try? container.decode(String.self) {
            self.value = stringValue
        } else if let intValue = try? container.decode(Int.self) {
            self.value = String(intValue)
        } else {
            throw DecodingError.typeMismatch(
                JSONRPCId.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected string or integer for JSON-RPC id"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Always encode as string for consistency
        try container.encode(value)
    }

    public var description: String { value }
}

public struct JSONRPCRequest<T: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCId
    public let method: String
    public let params: T?

    public init(id: JSONRPCId, method: String, params: T? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }

    /// Convenience init with string ID
    public init(id: String, method: String, params: T? = nil) {
        self.init(id: JSONRPCId(id), method: method, params: params)
    }

    /// Convenience init with auto-generated ID
    public init(method: String, params: T? = nil) {
        self.init(id: .generate(), method: method, params: params)
    }
}

public struct JSONRPCResponse<T: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCId
    public let result: T?
    public let error: JSONRPCError?

    public init(id: JSONRPCId, result: T) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    public init(id: JSONRPCId, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: AnyCodable?

    public init(code: Int, message: String, data: AnyCodable? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // Standard error codes
    public static func parseError(_ message: String = "Parse error") -> JSONRPCError {
        JSONRPCError(code: -32700, message: message)
    }

    public static func invalidRequest(_ message: String = "Invalid request") -> JSONRPCError {
        JSONRPCError(code: -32600, message: message)
    }

    public static func methodNotFound(_ method: String) -> JSONRPCError {
        JSONRPCError(code: -32601, message: "Method not found: \(method)")
    }

    public static func invalidParams(_ message: String) -> JSONRPCError {
        JSONRPCError(code: -32602, message: message)
    }

    public static func internalError(_ message: String) -> JSONRPCError {
        JSONRPCError(code: -32603, message: message)
    }
}
