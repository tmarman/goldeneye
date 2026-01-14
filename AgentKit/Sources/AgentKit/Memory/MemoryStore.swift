import Foundation

// MARK: - Memory Store

/// Central memory store for RAG-based retrieval across all content.
///
/// MemoryStore uses on-device vector storage and retrieval,
/// with optional sync to a master instance for P2P/mesh scenarios.
///
/// ## Architecture
/// ```
/// Documents → Chunker → Embedder → Vector DB (local)
///                                       ↓
///                                  SyncManager → Master Server (optional)
/// ```
///
/// Note: VecturaKit integration is stubbed for now. When integrating:
/// - Add `import VecturaKit`
/// - Initialize with proper VecturaKit configuration
/// - Replace stub implementations with actual vector operations
public actor MemoryStore {
    // MARK: - Properties

    // VecturaKit will be integrated here:
    // private var vectorDB: VecturaKit?

    private let config: MemoryStoreConfig
    private let chunker: ContentChunker
    private var syncManager: MemorySyncManager?

    /// Local metadata cache (stores all item data including embeddings placeholder)
    private var itemMetadata: [MemoryItemID: MemoryItem] = [:]

    /// Path to local storage
    private let storagePath: URL

    // MARK: - Initialization

    public init(config: MemoryStoreConfig = .default) async throws {
        self.config = config
        self.chunker = ContentChunker(strategy: config.chunkingStrategy)

        // Set up storage path
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.storagePath = appSupport.appendingPathComponent("Goldeneye/memory", isDirectory: true)

        try FileManager.default.createDirectory(at: storagePath, withIntermediateDirectories: true)

        // TODO: Initialize VecturaKit when API is finalized
        // VecturaKit requires proper embedder configuration

        // Load metadata from disk
        await loadMetadata()

        // Initialize sync manager if configured
        if let syncConfig = config.syncConfig, syncConfig.masterServerURL != nil {
            self.syncManager = MemorySyncManager(config: syncConfig, store: self)
        }
    }

    // MARK: - Indexing

    /// Index a document into memory
    public func indexDocument(_ document: Document, spaceId: SpaceID? = nil) async throws {
        // Extract text content from all blocks
        let content = document.blocks.map { $0.extractContent() }.joined(separator: "\n\n")

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        // Chunk the content
        let chunks = chunker.chunk(content)

        for (index, chunk) in chunks.enumerated() {
            let itemId = MemoryItemID("\(document.id.rawValue)-\(index)")

            let item = MemoryItem(
                id: itemId,
                content: chunk,
                source: .document(documentId: document.id.rawValue, blockId: nil),
                metadata: MemoryMetadata(
                    spaceId: spaceId?.rawValue,
                    title: document.title,
                    wordCount: chunk.split(separator: " ").count
                )
            )

            try await addItem(item)
        }
    }

    /// Index a capture from OpenSpace
    public func indexCapture(_ capture: Capture) async throws {
        let itemId = MemoryItemID("capture-\(capture.id)")

        let item = MemoryItem(
            id: itemId,
            content: capture.content,
            source: .capture(captureId: capture.id),
            metadata: MemoryMetadata(
                tags: capture.tags,
                title: capture.title
            )
        )

        try await addItem(item)
    }

    /// Index content from a URL (reading list, shared link)
    public func indexURL(_ url: URL, title: String?, content: String, source: URLSource) async throws {
        let chunks = chunker.chunk(content)

        for (index, chunk) in chunks.enumerated() {
            let itemId = MemoryItemID("url-\(url.absoluteString.hashValue)-\(index)")

            let memorySource: MemorySource
            switch source {
            case .readingList:
                memorySource = .readingList(url: url.absoluteString, title: title)
            case .sharedWithYou(let sourceApp, let sharedBy):
                memorySource = .shared(sourceApp: sourceApp, sharedBy: sharedBy)
            case .airdrop(let sender):
                memorySource = .shared(sourceApp: "AirDrop", sharedBy: sender)
            }

            let item = MemoryItem(
                id: itemId,
                content: chunk,
                source: memorySource,
                metadata: MemoryMetadata(
                    title: title,
                    wordCount: chunk.split(separator: " ").count
                )
            )

            try await addItem(item)
        }
    }

    public enum URLSource {
        case readingList
        case sharedWithYou(sourceApp: String?, sharedBy: String?)
        case airdrop(sender: String?)
    }

    // MARK: - Core Operations

    /// Add a memory item to the store
    public func addItem(_ item: MemoryItem) async throws {
        // TODO: Add to VecturaKit when integrated
        // try await vectorDB.addDocument(text: item.content, id: item.id.rawValue)

        // Store metadata locally
        itemMetadata[item.id] = item

        // Mark for sync
        await syncManager?.markForSync(item.id)

        // Persist metadata periodically
        if itemMetadata.count % 10 == 0 {
            await saveMetadata()
        }
    }

    /// Search memory using semantic similarity
    public func search(
        query: String,
        limit: Int = 10,
        threshold: Float = 0.5,
        filter: MemoryFilter? = nil
    ) async throws -> [MemorySearchResult] {
        // TODO: Replace with VecturaKit search when integrated
        // For now, use simple keyword matching as placeholder
        let queryWords = Set(query.lowercased().split(separator: " ").map(String.init))

        var searchResults: [MemorySearchResult] = []

        for (itemId, item) in itemMetadata {
            // Apply filters first
            if let filter = filter, !filter.matches(item) {
                continue
            }

            // Simple keyword scoring (placeholder for vector similarity)
            let contentWords = Set(item.content.lowercased().split(separator: " ").map(String.init))
            let overlap = queryWords.intersection(contentWords)
            let score = Float(overlap.count) / Float(max(queryWords.count, 1))

            if score >= threshold {
                searchResults.append(MemorySearchResult(
                    id: itemId,
                    item: item,
                    score: score,
                    matchType: .keyword  // Will be .vector when VecturaKit integrated
                ))
            }

            if searchResults.count >= limit * 2 {
                break
            }
        }

        // Sort by score and limit
        searchResults.sort { $0.score > $1.score }
        return Array(searchResults.prefix(limit))
    }

    /// Delete a memory item
    public func deleteItem(_ id: MemoryItemID) async throws {
        // TODO: Delete from VecturaKit when integrated
        // try await vectorDB.deleteDocuments(ids: [id.rawValue])
        itemMetadata.removeValue(forKey: id)
    }

    /// Delete all items from a source
    public func deleteItemsFromSource(_ source: MemorySource) async throws {
        let itemsToDelete = itemMetadata.values.filter { $0.source == source }

        for item in itemsToDelete {
            try await deleteItem(item.id)
        }
    }

    // MARK: - Persistence

    private func loadMetadata() async {
        let metadataPath = storagePath.appendingPathComponent("metadata.json")

        guard FileManager.default.fileExists(atPath: metadataPath.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: metadataPath)
            let items = try JSONDecoder().decode([MemoryItem].self, from: data)
            itemMetadata = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        } catch {
            print("Failed to load memory metadata: \(error)")
        }
    }

    private func saveMetadata() async {
        let metadataPath = storagePath.appendingPathComponent("metadata.json")

        do {
            let data = try JSONEncoder().encode(Array(itemMetadata.values))
            try data.write(to: metadataPath)
        } catch {
            print("Failed to save memory metadata: \(error)")
        }
    }

    // MARK: - Sync

    /// Trigger a manual sync with the master server
    public func syncWithMaster() async throws {
        guard let syncManager = syncManager else {
            throw MemoryStoreError.syncNotConfigured
        }

        try await syncManager.sync()
    }

    /// Get items that need syncing
    func getItemsForSync(ids: [MemoryItemID]) -> [MemoryItem] {
        ids.compactMap { itemMetadata[$0] }
    }

    /// Receive items from sync
    func receiveFromSync(_ items: [MemoryItem]) async throws {
        for item in items {
            try await addItem(item)
        }
    }

    // MARK: - Stats

    public var itemCount: Int {
        itemMetadata.count
    }

    public var sourceBreakdown: [String: Int] {
        var breakdown: [String: Int] = [:]
        for item in itemMetadata.values {
            let key: String
            switch item.source {
            case .document: key = "Documents"
            case .capture: key = "Captures"
            case .conversation: key = "Conversations"
            case .readingList: key = "Reading List"
            case .shared: key = "Shared"
            case .externalImport: key = "Imports"
            case .agentGenerated: key = "Agent Generated"
            }
            breakdown[key, default: 0] += 1
        }
        return breakdown
    }
}

// MARK: - Configuration

public struct MemoryStoreConfig: Sendable {
    public var databaseName: String
    public var chunkingStrategy: ChunkingStrategy
    public var syncConfig: MemorySyncConfig?

    public init(
        databaseName: String = "goldeneye-memory",
        chunkingStrategy: ChunkingStrategy = .semantic,
        syncConfig: MemorySyncConfig? = nil
    ) {
        self.databaseName = databaseName
        self.chunkingStrategy = chunkingStrategy
        self.syncConfig = syncConfig
    }

    public static var `default`: MemoryStoreConfig {
        MemoryStoreConfig()
    }
}

// MARK: - Filter

public struct MemoryFilter: Sendable {
    public var spaceIds: Set<String>?
    public var tags: Set<String>?
    public var sourceTypes: Set<SourceType>?
    public var minImportance: Float?
    public var dateRange: ClosedRange<Date>?

    public enum SourceType: Sendable {
        case document, capture, conversation, readingList, shared, externalImport, agentGenerated
    }

    public init(
        spaceIds: Set<String>? = nil,
        tags: Set<String>? = nil,
        sourceTypes: Set<SourceType>? = nil,
        minImportance: Float? = nil,
        dateRange: ClosedRange<Date>? = nil
    ) {
        self.spaceIds = spaceIds
        self.tags = tags
        self.sourceTypes = sourceTypes
        self.minImportance = minImportance
        self.dateRange = dateRange
    }

    func matches(_ item: MemoryItem) -> Bool {
        // Space filter
        if let spaceIds = spaceIds {
            guard let itemSpaceId = item.metadata.spaceId,
                  spaceIds.contains(itemSpaceId) else {
                return false
            }
        }

        // Tag filter
        if let tags = tags {
            let itemTags = Set(item.metadata.tags)
            if itemTags.isDisjoint(with: tags) {
                return false
            }
        }

        // Source type filter
        if let sourceTypes = sourceTypes {
            let itemSourceType: SourceType
            switch item.source {
            case .document: itemSourceType = .document
            case .capture: itemSourceType = .capture
            case .conversation: itemSourceType = .conversation
            case .readingList: itemSourceType = .readingList
            case .shared: itemSourceType = .shared
            case .externalImport: itemSourceType = .externalImport
            case .agentGenerated: itemSourceType = .agentGenerated
            }

            if !sourceTypes.contains(itemSourceType) {
                return false
            }
        }

        // Importance filter
        if let minImportance = minImportance {
            if let importance = item.metadata.importance, importance < minImportance {
                return false
            }
        }

        // Date range filter
        if let dateRange = dateRange {
            if !dateRange.contains(item.createdAt) {
                return false
            }
        }

        return true
    }
}

// MARK: - Errors

public enum MemoryStoreError: Error, LocalizedError {
    case notInitialized
    case syncNotConfigured
    case syncFailed(String)
    case indexingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Memory store is not initialized"
        case .syncNotConfigured:
            return "Sync is not configured - set masterServerURL in config"
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        case .indexingFailed(let reason):
            return "Indexing failed: \(reason)"
        }
    }
}

// MARK: - Helper Types

/// Capture type for indexing
public struct Capture: Sendable {
    public let id: String
    public let content: String
    public let title: String?
    public let tags: [String]

    public init(id: String, content: String, title: String? = nil, tags: [String] = []) {
        self.id = id
        self.content = content
        self.title = title
        self.tags = tags
    }
}
