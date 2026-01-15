import Foundation

// MARK: - Channel Message

/// A message in a channel or thread
/// Stores simplified message data for persistence and display
public struct ChannelMessage: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let channelId: UUID
    public let threadId: UUID?
    public let senderId: String          // "user" or agent ID
    public let role: String               // "system", "user", or "assistant"
    public let content: String            // Text content or summary
    public let type: MessageType
    public let mentions: [String]         // @agent-id mentions
    public var reactions: [Reaction]
    public var metadata: ChannelMessageMetadata

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        channelId: UUID,
        threadId: UUID? = nil,
        senderId: String,
        role: String,
        content: String,
        type: MessageType = .text,
        mentions: [String] = [],
        reactions: [Reaction] = [],
        metadata: ChannelMessageMetadata = ChannelMessageMetadata()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.channelId = channelId
        self.threadId = threadId
        self.senderId = senderId
        self.role = role
        self.content = content
        self.type = type
        self.mentions = mentions
        self.reactions = reactions
        self.metadata = metadata
    }

    /// Create a ChannelMessage from the core Message type
    public static func from(
        message: Message,
        channelId: UUID,
        threadId: UUID? = nil,
        senderId: String
    ) -> ChannelMessage {
        let content = message.textContent
        let type: MessageType = {
            // Determine type based on message content
            if message.content.contains(where: { if case .toolUse = $0 { return true } else { return false } }) {
                return .toolCall
            } else if message.content.contains(where: { if case .toolResult = $0 { return true } else { return false } }) {
                return .toolResult
            }
            return .text
        }()

        return ChannelMessage(
            timestamp: message.timestamp,
            channelId: channelId,
            threadId: threadId,
            senderId: senderId,
            role: message.role.rawValue,
            content: content,
            type: type
        )
    }
}


// MARK: - Message Type

/// Type of message content
public enum MessageType: String, Codable, Sendable {
    case text
    case toolCall
    case toolResult
    case agentEvent
    case system
}

// MARK: - Reaction

/// Reaction to a message (emoji, etc.)
public struct Reaction: Codable, Sendable {
    public let emoji: String
    public var users: [String]  // User IDs who reacted

    public init(emoji: String, users: [String] = []) {
        self.emoji = emoji
        self.users = users
    }
}

// MARK: - Channel Message Metadata

/// Additional metadata for channel messages
public struct ChannelMessageMetadata: Codable, Sendable {
    public var edited: Bool
    public var editedAt: Date?
    public var deleted: Bool
    public var deletedAt: Date?
    public var pinned: Bool

    public init(
        edited: Bool = false,
        editedAt: Date? = nil,
        deleted: Bool = false,
        deletedAt: Date? = nil,
        pinned: Bool = false
    ) {
        self.edited = edited
        self.editedAt = editedAt
        self.deleted = deleted
        self.deletedAt = deletedAt
        self.pinned = pinned
    }
}
