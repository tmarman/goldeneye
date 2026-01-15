import AgentKit
import Foundation

/// Persistence layer for conversations.
///
/// Stores conversations as JSON files in `~/.envoy/conversations/`.
/// Each conversation is a separate file named `{id}.json`.
///
/// Conversations can be scoped to spaces via the `spaceId` property.
/// When `spaceId` is nil, the conversation appears in "Headspace" (cross-space view).
public actor ConversationStore {
    private let basePath: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// In-memory cache of loaded conversations
    private var cache: [ConversationID: Conversation] = [:]

    /// Whether the store has completed initial load
    private var isLoaded = false

    public init() throws {
        // Create base path: ~/.envoy/conversations/
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.basePath = appSupport.appendingPathComponent("Envoy/conversations", isDirectory: true)

        // Ensure directory exists
        try FileManager.default.createDirectory(at: basePath, withIntermediateDirectories: true)

        // Configure encoder/decoder
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - CRUD Operations

    /// Save a conversation to disk
    public func save(_ conversation: Conversation) throws {
        let path = filePath(for: conversation.id)
        let data = try encoder.encode(conversation)
        try data.write(to: path, options: .atomic)
        cache[conversation.id] = conversation
    }

    /// Load a specific conversation by ID
    public func load(_ id: ConversationID) throws -> Conversation? {
        // Check cache first
        if let cached = cache[id] {
            return cached
        }

        let path = filePath(for: id)
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }

        let data = try Data(contentsOf: path)
        let conversation = try decoder.decode(Conversation.self, from: data)
        cache[id] = conversation
        return conversation
    }

    /// Load all conversations from disk
    public func loadAll() throws -> [Conversation] {
        if isLoaded {
            return Array(cache.values)
        }

        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: basePath, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        var conversations: [Conversation] = []
        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let conversation = try decoder.decode(Conversation.self, from: data)
                cache[conversation.id] = conversation
                conversations.append(conversation)
            } catch {
                // Log but continue - don't fail entire load for one bad file
                print("⚠️ Failed to load conversation from \(file.lastPathComponent): \(error)")
            }
        }

        isLoaded = true
        return conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Load conversations for a specific space
    public func load(for spaceId: SpaceID) throws -> [Conversation] {
        let all = try loadAll()
        return all.filter { $0.spaceId == spaceId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Load conversations with no space (Headspace / cross-space)
    public func loadUnscoped() throws -> [Conversation] {
        let all = try loadAll()
        return all.filter { $0.spaceId == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Delete a conversation
    public func delete(_ id: ConversationID) throws {
        let path = filePath(for: id)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        cache.removeValue(forKey: id)
    }

    /// Clear all cached data (forces reload on next access)
    public func clearCache() {
        cache.removeAll()
        isLoaded = false
    }

    // MARK: - Helpers

    private func filePath(for id: ConversationID) -> URL {
        basePath.appendingPathComponent("\(id.rawValue).json")
    }
}

// MARK: - Conversation Extension for Space Scoping

extension Conversation {
    /// The space this conversation belongs to.
    /// When nil, the conversation appears in Headspace (cross-space view).
    public var spaceId: SpaceID? {
        get {
            // Store spaceId in the existing folderId field for now
            // This is a pragmatic approach that avoids breaking Codable
            guard let folderId = folderId else { return nil }
            return SpaceID(folderId.rawValue)
        }
        set {
            folderId = newValue.map { FolderID($0.rawValue) }
        }
    }
}
