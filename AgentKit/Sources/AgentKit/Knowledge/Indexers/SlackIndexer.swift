//
//  SlackIndexer.swift
//  AgentKit
//
//  Indexes Slack workspace history into the Knowledge Backbone.
//  Supports incremental sync with cursor-based pagination.
//

import Foundation

// MARK: - Slack Indexer

/// Indexes Slack channels and messages into KnowledgeStore
public actor SlackIndexer {
    private let slack: SlackIntegration
    private let store: KnowledgeStore
    private let sourceId: String

    /// Rate limiting
    private let requestDelay: TimeInterval = 0.5  // Slack tier 3 rate limit friendly
    private var lastRequestTime: Date = .distantPast

    /// User cache to avoid repeated lookups
    private var userCache: [String: SlackUser] = [:]

    /// Index stats
    private var stats = IndexStats()

    public init(slack: SlackIntegration, store: KnowledgeStore, sourceId: String = "slack-workspace") {
        self.slack = slack
        self.store = store
        self.sourceId = sourceId
    }

    // MARK: - Full Sync

    /// Index all accessible channels
    public func indexAll(
        channelTypes: String = "public_channel,private_channel",
        daysBack: Int = 90,
        progress: ((IndexProgress) -> Void)? = nil
    ) async throws {
        stats = IndexStats()
        let startTime = Date()

        // Ensure source is registered
        try await ensureSource()

        // Get all channels
        print("📡 SlackIndexer: Fetching channels...")
        let channels = try await fetchAllChannels(types: channelTypes)
        print("📡 SlackIndexer: Found \(channels.count) channels")

        stats.totalChannels = channels.count

        // Calculate oldest message date
        let oldestDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()

        // Index each channel
        for (index, channel) in channels.enumerated() {
            do {
                let messageCount = try await indexChannel(channel, oldestDate: oldestDate)
                stats.indexedChannels += 1
                stats.totalMessages += messageCount

                progress?(IndexProgress(
                    phase: .indexingChannel(channel.name),
                    channelIndex: index + 1,
                    totalChannels: channels.count,
                    messagesProcessed: stats.totalMessages
                ))
            } catch {
                print("⚠️ SlackIndexer: Failed to index #\(channel.name): \(error)")
                stats.failedChannels += 1
            }
        }

        // Update source sync time
        try await store.updateSourceSync(sourceId: sourceId, lastSync: Date())

        stats.duration = Date().timeIntervalSince(startTime)
        print("✅ SlackIndexer: Complete - \(stats.summary)")
    }

    /// Index a single channel
    public func indexChannel(_ channel: SlackChannel, oldestDate: Date = .distantPast) async throws -> Int {
        var messageCount = 0
        var cursor: String? = nil
        var hasMore = true

        while hasMore {
            await rateLimitDelay()

            // Fetch messages batch
            let (messages, nextCursor) = try await fetchMessages(
                channelId: channel.id,
                cursor: cursor,
                oldestDate: oldestDate
            )

            // Process messages
            for message in messages {
                // Skip bot messages, joins, etc.
                guard shouldIndex(message) else { continue }

                // Resolve user
                let user = await resolveUser(message.userId)

                // Create document
                let doc = createDocument(
                    message: message,
                    channel: channel,
                    user: user
                )

                // Ingest into knowledge store
                _ = try await store.ingest(document: doc)
                messageCount += 1
            }

            cursor = nextCursor
            hasMore = nextCursor != nil && !messages.isEmpty
        }

        return messageCount
    }

    // MARK: - Incremental Sync

    /// Sync only new messages since last sync
    public func incrementalSync(
        progress: ((IndexProgress) -> Void)? = nil
    ) async throws {
        stats = IndexStats()
        let startTime = Date()

        // Get source to check last sync
        guard let source = try await store.getSource(id: sourceId) else {
            // No previous sync, do full sync with 30 days
            try await indexAll(daysBack: 30, progress: progress)
            return
        }

        let lastSync = source.lastSync ?? Date.distantPast
        print("📡 SlackIndexer: Incremental sync since \(lastSync)")

        // Get channels and sync each
        let channels = try await fetchAllChannels(types: "public_channel,private_channel")
        stats.totalChannels = channels.count

        for (index, channel) in channels.enumerated() {
            do {
                let messageCount = try await indexChannel(channel, oldestDate: lastSync)
                stats.indexedChannels += 1
                stats.totalMessages += messageCount

                progress?(IndexProgress(
                    phase: .indexingChannel(channel.name),
                    channelIndex: index + 1,
                    totalChannels: channels.count,
                    messagesProcessed: stats.totalMessages
                ))
            } catch {
                stats.failedChannels += 1
            }
        }

        // Update sync time
        try await store.updateSourceSync(sourceId: sourceId, lastSync: Date())

        stats.duration = Date().timeIntervalSince(startTime)
        print("✅ SlackIndexer: Incremental sync complete - \(stats.summary)")
    }

    // MARK: - Private Methods

    private func ensureSource() async throws {
        let sources = try await store.getSources()
        if !sources.contains(where: { $0.id == sourceId }) {
            var config = KSourceConfig()
            config.custom["platform"] = "slack"

            let source = KSource(
                id: sourceId,
                type: .slack,
                name: "Slack Workspace",
                config: config
            )
            _ = try await store.registerSource(source)
        }
    }

    private func fetchAllChannels(types: String) async throws -> [SlackChannel] {
        var channels: [SlackChannel] = []
        var cursor: String? = nil
        var hasMore = true

        while hasMore {
            await rateLimitDelay()

            var params: [String: Any] = [
                "types": types,
                "limit": 200,
                "exclude_archived": true
            ]
            if let c = cursor {
                params["cursor"] = c
            }

            let response = try await slackAPI("conversations.list", params: params)

            if let channelList = response["channels"] as? [[String: Any]] {
                for channelData in channelList {
                    if let channel = parseChannel(channelData) {
                        channels.append(channel)
                    }
                }
            }

            // Handle pagination
            if let metadata = response["response_metadata"] as? [String: Any],
               let nextCursor = metadata["next_cursor"] as? String,
               !nextCursor.isEmpty {
                cursor = nextCursor
            } else {
                hasMore = false
            }
        }

        return channels
    }

    private func fetchMessages(
        channelId: String,
        cursor: String?,
        oldestDate: Date
    ) async throws -> ([SlackMessage], String?) {
        var params: [String: Any] = [
            "channel": channelId,
            "limit": 100,
            "oldest": String(oldestDate.timeIntervalSince1970)
        ]
        if let c = cursor {
            params["cursor"] = c
        }

        let response = try await slackAPI("conversations.history", params: params)

        var messages: [SlackMessage] = []
        if let messageList = response["messages"] as? [[String: Any]] {
            for msgData in messageList {
                if let msg = parseMessage(msgData, channelId: channelId) {
                    messages.append(msg)
                }
            }
        }

        // Get next cursor
        var nextCursor: String? = nil
        if let hasMore = response["has_more"] as? Bool, hasMore,
           let metadata = response["response_metadata"] as? [String: Any],
           let next = metadata["next_cursor"] as? String,
           !next.isEmpty {
            nextCursor = next
        }

        return (messages, nextCursor)
    }

    private func resolveUser(_ userId: String?) async -> SlackUser? {
        guard let userId = userId else { return nil }

        // Check cache
        if let cached = userCache[userId] {
            return cached
        }

        // Fetch from API
        await rateLimitDelay()

        do {
            let response = try await slackAPI("users.info", params: ["user": userId])
            if let userData = response["user"] as? [String: Any],
               let user = parseUser(userData) {
                userCache[userId] = user
                return user
            }
        } catch {
            print("⚠️ SlackIndexer: Failed to resolve user \(userId)")
        }

        return nil
    }

    private func shouldIndex(_ message: SlackMessage) -> Bool {
        // Skip system messages
        guard message.subtype == nil || message.subtype == "me_message" else {
            return false
        }

        // Skip very short messages
        guard message.text.count >= 10 else {
            return false
        }

        // Skip pure emoji reactions
        let emojiPattern = try! NSRegularExpression(pattern: "^:[a-zA-Z0-9_+-]+:$")
        let range = NSRange(message.text.startIndex..., in: message.text)
        if emojiPattern.firstMatch(in: message.text, range: range) != nil {
            return false
        }

        return true
    }

    private func createDocument(
        message: SlackMessage,
        channel: SlackChannel,
        user: SlackUser?
    ) -> KDocument {
        let title = "Slack: #\(channel.name) - \(message.timestamp.prefix(10))"

        // Enrich content with context
        var content = message.text

        // Add thread context if reply
        if message.threadTs != nil && message.threadTs != message.ts {
            content = "[Reply in thread]\n\(content)"
        }

        // Add reaction summary if any
        if !message.reactions.isEmpty {
            let reactionSummary = message.reactions.map { ":\($0.name): ×\($0.count)" }.joined(separator: " ")
            content += "\n[Reactions: \(reactionSummary)]"
        }

        var tags = ["channel:\(channel.name)"]
        if channel.isPrivate {
            tags.append("private")
        }

        let metadata = KDocumentMetadata(
            author: user?.realName ?? user?.displayName ?? message.userId,
            tags: tags
        )

        let createdAt = Date(timeIntervalSince1970: Double(message.ts.split(separator: ".").first.flatMap { Double($0) } ?? 0))

        return KDocument(
            sourceId: sourceId,
            sourceType: .slack,
            sourceRef: "\(channel.id)/\(message.ts)",
            title: title,
            content: content,
            createdAt: createdAt,
            metadata: metadata
        )
    }

    private func slackAPI(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        // Serialize params to Data for Sendable crossing
        let paramsData = try JSONSerialization.data(withJSONObject: params)
        let data = try await slackAPICall(method, paramsData: paramsData)

        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SlackIndexerError.apiError("Invalid JSON response")
        }

        // Check for API errors
        if let ok = response["ok"] as? Bool, !ok {
            let error = response["error"] as? String ?? "Unknown error"
            throw SlackIndexerError.apiError(error)
        }

        return response
    }

    /// Sendable-safe API call wrapper
    private func slackAPICall(_ method: String, paramsData: Data) async throws -> Data {
        guard let params = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any] else {
            throw SlackIndexerError.apiError("Invalid params")
        }
        return try await slack.rawAPI(method, params: params)
    }

    private func rateLimitDelay() async {
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < requestDelay {
            try? await Task.sleep(nanoseconds: UInt64((requestDelay - elapsed) * 1_000_000_000))
        }
        lastRequestTime = Date()
    }

    // MARK: - Parsing

    private func parseChannel(_ data: [String: Any]) -> SlackChannel? {
        guard let id = data["id"] as? String,
              let name = data["name"] as? String else {
            return nil
        }

        return SlackChannel(
            id: id,
            name: name,
            isPrivate: data["is_private"] as? Bool ?? false,
            isArchived: data["is_archived"] as? Bool ?? false,
            memberCount: data["num_members"] as? Int,
            topic: (data["topic"] as? [String: Any])?["value"] as? String,
            purpose: (data["purpose"] as? [String: Any])?["value"] as? String
        )
    }

    private func parseMessage(_ data: [String: Any], channelId: String) -> SlackMessage? {
        guard let ts = data["ts"] as? String,
              let text = data["text"] as? String else {
            return nil
        }

        var reactions: [SlackReaction] = []
        if let reactionData = data["reactions"] as? [[String: Any]] {
            for r in reactionData {
                if let name = r["name"] as? String,
                   let count = r["count"] as? Int {
                    reactions.append(SlackReaction(name: name, count: count))
                }
            }
        }

        return SlackMessage(
            ts: ts,
            channelId: channelId,
            userId: data["user"] as? String,
            text: text,
            subtype: data["subtype"] as? String,
            threadTs: data["thread_ts"] as? String,
            reactions: reactions,
            timestamp: ts
        )
    }

    private func parseUser(_ data: [String: Any]) -> SlackUser? {
        guard let id = data["id"] as? String else { return nil }

        let profile = data["profile"] as? [String: Any]

        return SlackUser(
            id: id,
            realName: data["real_name"] as? String ?? profile?["real_name"] as? String,
            displayName: profile?["display_name"] as? String,
            email: profile?["email"] as? String,
            isBot: data["is_bot"] as? Bool ?? false
        )
    }

    // MARK: - Stats

    public var indexStats: IndexStats {
        stats
    }
}

// MARK: - Supporting Types

public struct SlackChannel: Sendable {
    public let id: String
    public let name: String
    public let isPrivate: Bool
    public let isArchived: Bool
    public let memberCount: Int?
    public let topic: String?
    public let purpose: String?
}

public struct SlackMessage: Sendable {
    public let ts: String
    public let channelId: String
    public let userId: String?
    public let text: String
    public let subtype: String?
    public let threadTs: String?
    public let reactions: [SlackReaction]
    public let timestamp: String
}

public struct SlackReaction: Sendable {
    public let name: String
    public let count: Int
}

public struct SlackUser: Sendable {
    public let id: String
    public let realName: String?
    public let displayName: String?
    public let email: String?
    public let isBot: Bool
}

public struct IndexProgress: Sendable {
    public enum Phase: Sendable {
        case fetchingChannels
        case indexingChannel(String)
        case complete
    }

    public let phase: Phase
    public let channelIndex: Int
    public let totalChannels: Int
    public let messagesProcessed: Int

    public var percentComplete: Double {
        guard totalChannels > 0 else { return 0 }
        return Double(channelIndex) / Double(totalChannels)
    }
}

public struct IndexStats: Sendable {
    public var totalChannels: Int = 0
    public var indexedChannels: Int = 0
    public var failedChannels: Int = 0
    public var totalMessages: Int = 0
    public var duration: TimeInterval = 0

    public var summary: String {
        let durationStr = String(format: "%.1f", duration)
        return "\(indexedChannels)/\(totalChannels) channels, \(totalMessages) messages in \(durationStr)s"
    }
}

// MARK: - Errors

public enum SlackIndexerError: Error, LocalizedError {
    case notImplemented(String)
    case apiError(String)
    case rateLimited

    public var errorDescription: String? {
        switch self {
        case .notImplemented(let msg):
            return "Not implemented: \(msg)"
        case .apiError(let msg):
            return "Slack API error: \(msg)"
        case .rateLimited:
            return "Rate limited by Slack API"
        }
    }
}
