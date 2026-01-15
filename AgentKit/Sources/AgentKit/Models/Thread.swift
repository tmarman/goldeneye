import Foundation

// MARK: - Thread

/// A conversation thread within a channel
/// Threads group related messages together, similar to Slack threads
public struct Thread: Codable, Identifiable, Sendable {
    public let id: UUID
    public let channelId: UUID
    public let parentMessageId: UUID?    // For nested threads
    public var messages: [ChannelMessage]
    public let createdAt: Date
    public var updatedAt: Date
    public var participants: [String]    // User + mentioned agents

    public init(
        id: UUID = UUID(),
        channelId: UUID,
        parentMessageId: UUID? = nil,
        messages: [ChannelMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        participants: [String] = []
    ) {
        self.id = id
        self.channelId = channelId
        self.parentMessageId = parentMessageId
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.participants = participants
    }

    /// Add a message to the thread
    public mutating func addMessage(_ message: ChannelMessage) {
        messages.append(message)
        updatedAt = Date()

        // Add sender to participants if not already present
        if !participants.contains(message.senderId) {
            participants.append(message.senderId)
        }
    }

    /// Get the most recent message in the thread
    public var latestMessage: ChannelMessage? {
        messages.max(by: { $0.timestamp < $1.timestamp })
    }

    /// Count of messages in the thread
    public var messageCount: Int {
        messages.count
    }
}
