import Foundation

// MARK: - Message

/// A message in the conversation
public struct Message: Sendable, Identifiable {
    public let id: String
    public let role: Role
    public let content: [MessageContent]
    public let timestamp: Date

    public enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
    }

    public init(
        id: String = UUID().uuidString,
        role: Role,
        content: [MessageContent],
        timestamp: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    /// Convenience initializer for single content
    public init(
        id: String = UUID().uuidString,
        role: Role,
        content: MessageContent,
        timestamp: Date = .now
    ) {
        self.init(id: id, role: role, content: [content], timestamp: timestamp)
    }

    /// Extract text content
    public var textContent: String {
        content.compactMap { part in
            if case .text(let text) = part { return text }
            return nil
        }.joined()
    }
}

// MARK: - Message Content

/// Content parts of a message (text, tool use, tool result, file, data)
public enum MessageContent: Sendable {
    case text(String)
    case toolUse(ToolUse)
    case toolResult(ToolResult)
    case file(FileContent)
    case data([String: AnyCodable])
}

public struct ToolUse: Sendable {
    public let id: String
    public let name: String
    public let input: ToolInput

    public init(id: String, name: String, input: ToolInput) {
        self.id = id
        self.name = name
        self.input = input
    }
}

public struct ToolResult: Sendable {
    public let toolUseId: String
    public let content: String
    public let isError: Bool

    public init(toolUseId: String, content: String, isError: Bool = false) {
        self.toolUseId = toolUseId
        self.content = content
        self.isError = isError
    }
}

public struct FileContent: Sendable {
    public enum Source: Sendable {
        case uri(String)
        case bytes(Data)
    }

    public let source: Source
    public let mimeType: String
    public let name: String?

    public init(source: Source, mimeType: String, name: String? = nil) {
        self.source = source
        self.mimeType = mimeType
        self.name = name
    }
}

// MARK: - Artifact

/// Output artifact from agent execution
public struct Artifact: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let parts: [MessageContent]
    public let metadata: [String: AnyCodable]?

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        parts: [MessageContent],
        metadata: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.parts = parts
        self.metadata = metadata
    }
}

// MARK: - AnyCodable

/// Type-erased Codable value for dynamic JSON
public struct AnyCodable: @unchecked Sendable, Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: [], debugDescription: "Unable to encode value")
            )
        }
    }
}
