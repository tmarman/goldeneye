import Foundation

// MARK: - Conversation

/// A conversation is a persistent thread of messages with one or more agents.
///
/// Unlike ephemeral task submissions, conversations maintain context across
/// multiple interactions and can be resumed at any time.
public struct Conversation: Identifiable, Codable, Sendable {
    public let id: ConversationID
    public var title: String
    public var messages: [ConversationMessage]
    public var agentId: AgentID?
    public var agentName: String?
    public var folderId: FolderID?
    public var tagIds: [TagID]
    public var isStarred: Bool
    public var isPinned: Bool
    public var isArchived: Bool
    public let createdAt: Date
    public var updatedAt: Date

    /// A2A context ID for maintaining conversation continuity with the agent server.
    /// When set, subsequent messages use the same context, preserving full history.
    public var contextId: String?

    /// The model ID for direct model conversations (e.g., "mlx-community/Qwen2.5-7B-Instruct-4bit")
    public var modelId: String?

    /// The provider ID for direct model conversations (e.g., UUID of the ProviderConfig)
    public var providerId: String?

    public init(
        id: ConversationID = ConversationID(),
        title: String = "New Conversation",
        messages: [ConversationMessage] = [],
        agentId: AgentID? = nil,
        agentName: String? = nil,
        folderId: FolderID? = nil,
        tagIds: [TagID] = [],
        isStarred: Bool = false,
        isPinned: Bool = false,
        isArchived: Bool = false,
        contextId: String? = nil,
        modelId: String? = nil,
        providerId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.agentId = agentId
        self.agentName = agentName
        self.folderId = folderId
        self.tagIds = tagIds
        self.isStarred = isStarred
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.contextId = contextId
        self.modelId = modelId
        self.providerId = providerId
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// The last message in the conversation, if any
    public var lastMessage: ConversationMessage? {
        messages.last
    }

    /// Preview text for list views
    public var preview: String {
        lastMessage?.content.prefix(100).description ?? "No messages yet"
    }
}

public struct ConversationID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

// MARK: - Conversation Message

/// A single message within a conversation.
public struct ConversationMessage: Identifiable, Codable, Sendable {
    public let id: UUID
    public var role: MessageRole
    public var content: String
    public var attachments: [Attachment]
    public var metadata: MessageMetadata?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        attachments: [Attachment] = [],
        metadata: MessageMetadata? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

// MARK: - Attachments

/// An attachment to a conversation message (document, image, etc.)
public struct Attachment: Identifiable, Codable, Sendable {
    public let id: UUID
    public var type: AttachmentType
    public var name: String
    public var reference: String  // Document ID, file path, or URL

    public init(
        id: UUID = UUID(),
        type: AttachmentType,
        name: String,
        reference: String
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.reference = reference
    }
}

public enum AttachmentType: String, Codable, Sendable {
    case document   // Reference to a Document
    case file       // Local file path
    case image      // Image file
    case url        // Web URL
}

// MARK: - Message Metadata

/// Additional metadata about a message (model info, tokens, etc.)
public struct MessageMetadata: Codable, Sendable {
    public var model: String?
    public var provider: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var latencyMs: Int?
    public var toolsUsed: [String]?

    public init(
        model: String? = nil,
        provider: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        latencyMs: Int? = nil,
        toolsUsed: [String]? = nil
    ) {
        self.model = model
        self.provider = provider
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.latencyMs = latencyMs
        self.toolsUsed = toolsUsed
    }

    /// Convenience initializer for chat completions
    public init(
        model: String?,
        provider: String?,
        tokens: Int?,
        latency: TimeInterval?
    ) {
        self.model = model
        self.provider = provider
        self.inputTokens = nil
        self.outputTokens = tokens
        self.latencyMs = latency.map { Int($0 * 1000) }
        self.toolsUsed = nil
    }

    /// Total tokens used (output only for now)
    public var tokens: Int? {
        outputTokens
    }
}
