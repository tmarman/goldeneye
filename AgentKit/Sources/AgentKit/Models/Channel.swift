import Foundation

// MARK: - Channel Types

/// Type of channel for organizing agent communication
public enum ChannelType: String, Codable, Sendable {
    case channel        // Public channel (#general, #code-review)
    case directMessage  // 1:1 DM between user and agent or agent and agent
    case thread         // Reply thread in a channel
}

// MARK: - Channel

/// A channel for agent communication, similar to Slack channels
/// Can be a public channel, direct message, or thread
public struct Channel: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let isPublic: Bool
    public let type: ChannelType
    public var threads: [Thread]
    public var documents: [Document]
    public var members: [String]        // Agent IDs or "user"
    public var metadata: ChannelMetadata
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        isPublic: Bool,
        type: ChannelType,
        threads: [Thread] = [],
        documents: [Document] = [],
        members: [String] = [],
        metadata: ChannelMetadata = ChannelMetadata(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isPublic = isPublic
        self.type = type
        self.threads = threads
        self.documents = documents
        self.members = members
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Channel Metadata

/// Additional metadata for channels
public struct ChannelMetadata: Codable, Sendable {
    public var description: String?
    public var topic: String?
    public var pinned: Bool
    public var archived: Bool
    public var unreadCount: Int
    public var lastReadMessageId: UUID?

    public init(
        description: String? = nil,
        topic: String? = nil,
        pinned: Bool = false,
        archived: Bool = false,
        unreadCount: Int = 0,
        lastReadMessageId: UUID? = nil
    ) {
        self.description = description
        self.topic = topic
        self.pinned = pinned
        self.archived = archived
        self.unreadCount = unreadCount
        self.lastReadMessageId = lastReadMessageId
    }
}
