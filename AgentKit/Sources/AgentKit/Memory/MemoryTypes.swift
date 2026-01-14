import Foundation

// MARK: - Memory Item

/// A memory item represents a chunk of indexed content.
///
/// Memory items can come from documents, captures, conversations,
/// or external sources like reading lists and shared links.
public struct MemoryItem: Identifiable, Codable, Sendable {
    public let id: MemoryItemID
    public var content: String
    public var source: MemorySource
    public var metadata: MemoryMetadata
    public let createdAt: Date
    public var lastAccessedAt: Date

    /// Vector embedding for semantic search (optional until generated)
    public var embedding: [Float]?

    public init(
        id: MemoryItemID = MemoryItemID(),
        content: String,
        source: MemorySource,
        metadata: MemoryMetadata = MemoryMetadata(),
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.content = content
        self.source = source
        self.metadata = metadata
        self.createdAt = Date()
        self.lastAccessedAt = Date()
        self.embedding = embedding
    }
}

public struct MemoryItemID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

// MARK: - Memory Source

/// The origin of a memory item
public enum MemorySource: Codable, Sendable, Equatable {
    /// From a document block
    case document(documentId: String, blockId: String?)

    /// From an OpenSpace capture
    case capture(captureId: String)

    /// From an agent conversation
    case conversation(sessionId: String, messageId: String?)

    /// From a reading list item
    case readingList(url: String, title: String?)

    /// From a shared link or AirDrop
    case shared(sourceApp: String?, sharedBy: String?)

    /// External import (e.g., Obsidian, Notion export)
    case externalImport(source: String)

    /// Agent-generated knowledge
    case agentGenerated(agentId: String)
}

// MARK: - Memory Metadata

/// Additional metadata for memory items
public struct MemoryMetadata: Codable, Sendable {
    public var tags: [String]
    public var spaceId: String?
    public var title: String?
    public var summary: String?
    public var language: String?
    public var wordCount: Int?
    public var importance: Float?  // 0.0-1.0, for prioritizing retrieval
    public var customFields: [String: String]

    public init(
        tags: [String] = [],
        spaceId: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        language: String? = nil,
        wordCount: Int? = nil,
        importance: Float? = nil,
        customFields: [String: String] = [:]
    ) {
        self.tags = tags
        self.spaceId = spaceId
        self.title = title
        self.summary = summary
        self.language = language
        self.wordCount = wordCount
        self.importance = importance
        self.customFields = customFields
    }
}

// MARK: - Search Result

/// A search result from the memory store
public struct MemorySearchResult: Identifiable, Sendable {
    public let id: MemoryItemID
    public let item: MemoryItem
    public let score: Float
    public let matchType: MatchType

    public enum MatchType: Sendable {
        case vector      // Semantic similarity match
        case keyword     // BM25 keyword match
        case hybrid      // Combined vector + keyword
    }
}

// MARK: - Sync Types

/// Represents a sync operation between local and remote memory stores
public struct MemorySyncOperation: Codable, Sendable {
    public let operationId: String
    public let timestamp: Date
    public let direction: SyncDirection
    public let itemCount: Int
    public var status: SyncStatus

    public enum SyncDirection: String, Codable, Sendable {
        case push    // Local → Remote
        case pull    // Remote → Local
        case merge   // Bidirectional merge
    }

    public enum SyncStatus: String, Codable, Sendable {
        case pending
        case inProgress
        case completed
        case failed
        case conflicted
    }
}

/// Configuration for memory sync
public struct MemorySyncConfig: Codable, Sendable {
    /// URL of the master memory server
    public var masterServerURL: URL?

    /// Whether to sync automatically
    public var autoSync: Bool

    /// Sync interval in seconds
    public var syncIntervalSeconds: TimeInterval

    /// Whether to sync only on WiFi
    public var wifiOnly: Bool

    /// Maximum items per sync batch
    public var batchSize: Int

    public init(
        masterServerURL: URL? = nil,
        autoSync: Bool = true,
        syncIntervalSeconds: TimeInterval = 300,  // 5 minutes
        wifiOnly: Bool = false,
        batchSize: Int = 100
    ) {
        self.masterServerURL = masterServerURL
        self.autoSync = autoSync
        self.syncIntervalSeconds = syncIntervalSeconds
        self.wifiOnly = wifiOnly
        self.batchSize = batchSize
    }
}

// MARK: - Chunking Strategy

/// Strategy for splitting content into chunks for embedding
public enum ChunkingStrategy: Sendable {
    /// Fixed size chunks with optional overlap
    case fixed(size: Int, overlap: Int)

    /// Semantic chunking based on structure (paragraphs, sections)
    case semantic

    /// Sentence-based chunking
    case sentence(maxPerChunk: Int)

    /// No chunking - embed entire content
    case none
}
