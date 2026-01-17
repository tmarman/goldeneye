//
//  KnowledgeStore.swift
//  AgentKit
//
//  Central knowledge store for the Knowledge Backbone.
//  Manages documents, chunks, embeddings, entities, and search.
//

import Foundation

// MARK: - Knowledge Store

/// Central actor for all knowledge operations
/// Manages document ingestion, embedding, search, and entity extraction.
public actor KnowledgeStore {
    private let database: KnowledgeDatabase
    private let embeddingEngine: KEmbeddingEngine
    private let chunker: KChunker
    private var isInitialized = false

    // In-memory vector index for fast search
    private var vectorIndex: [String: [Float]] = [:]  // chunkId -> embedding

    public init(
        databasePath: String? = nil,
        embeddingModel: KEmbeddingModel = .bgeSmallEn,
        chunkingStrategy: KChunkingStrategy = .semantic
    ) {
        let path = databasePath ?? Self.defaultDatabasePath
        self.database = KnowledgeDatabase(path: path)
        self.embeddingEngine = KEmbeddingEngine(model: embeddingModel)
        self.chunker = KChunker(strategy: chunkingStrategy)
    }

    /// Default database path
    public static var defaultDatabasePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.goldeneye/knowledge.db"
    }

    // MARK: - Initialization

    /// Initialize the knowledge store
    public func initialize() async throws {
        guard !isInitialized else { return }

        print("🧠 KnowledgeStore: Initializing...")

        // Open database
        try await database.open()

        // Load embedding model
        try await embeddingEngine.loadModel()

        // Load vector index from database
        try await loadVectorIndex()

        isInitialized = true
        print("✅ KnowledgeStore: Ready")
    }

    /// Shutdown the knowledge store
    public func shutdown() async {
        await database.close()
        vectorIndex.removeAll()
        isInitialized = false
    }

    private func ensureInitialized() async throws {
        if !isInitialized {
            try await initialize()
        }
    }

    /// Load all embeddings into memory for fast search
    private func loadVectorIndex() async throws {
        // Get all sources first
        let sources = try await database.getAllSources()

        for source in sources {
            let documents = try await database.getDocuments(sourceId: source.id, limit: 10000)
            for document in documents {
                let chunks = try await database.getChunks(documentId: document.id)
                for chunk in chunks {
                    if let embedding = chunk.embedding {
                        vectorIndex[chunk.id] = embedding
                    }
                }
            }
        }

        print("📊 KnowledgeStore: Loaded \(vectorIndex.count) embeddings into index")
    }

    // MARK: - Source Management

    /// Register a new knowledge source
    public func registerSource(_ source: KSource) async throws -> String {
        try await ensureInitialized()
        try await database.insertSource(source)
        return source.id
    }

    /// Get all registered sources
    public func getSources() async throws -> [KSource] {
        try await ensureInitialized()
        return try await database.getAllSources()
    }

    /// Get a specific source
    public func getSource(id: String) async throws -> KSource? {
        try await ensureInitialized()
        return try await database.getSource(id: id)
    }

    /// Update source sync status
    public func updateSourceSync(
        sourceId: String,
        lastSync: Date,
        cursor: String? = nil
    ) async throws {
        try await database.updateSourceSync(sourceId, lastSync: lastSync, cursor: cursor)
    }

    // MARK: - Document Ingestion

    /// Ingest a document into the knowledge store
    /// - Returns: Document ID
    public func ingest(document: KDocument) async throws -> String {
        try await ensureInitialized()

        // Check if document already exists (by content hash)
        if let existing = try await database.getDocumentByHash(document.contentHash, sourceId: document.sourceId) {
            // Document unchanged, skip
            return existing.id
        }

        // Store document
        try await database.insertDocument(document)

        // Chunk document
        let chunks = chunker.chunk(document)

        // Generate embeddings
        let texts = chunks.map { $0.content }
        let embeddings = try await embeddingEngine.embedBatch(texts)

        // Store chunks with embeddings
        var chunksWithEmbeddings: [KChunk] = []
        for (i, var chunk) in chunks.enumerated() {
            chunk.embedding = embeddings[i]
            chunksWithEmbeddings.append(chunk)

            // Add to in-memory index
            vectorIndex[chunk.id] = embeddings[i]
        }

        try await database.insertChunks(chunksWithEmbeddings)

        // Mark document as indexed
        try await database.markDocumentIndexed(document.id)

        return document.id
    }

    /// Ingest multiple documents
    public func ingestBatch(documents: [KDocument], progress: ((Int, Int) -> Void)? = nil) async throws -> [String] {
        var ids: [String] = []

        for (index, document) in documents.enumerated() {
            let id = try await ingest(document: document)
            ids.append(id)
            progress?(index + 1, documents.count)
        }

        return ids
    }

    /// Delete a document and its chunks
    public func deleteDocument(_ id: String) async throws {
        try await ensureInitialized()

        // Remove chunks from vector index
        let chunks = try await database.getChunks(documentId: id)
        for chunk in chunks {
            vectorIndex.removeValue(forKey: chunk.id)
        }

        // Delete from database (cascades to chunks)
        try await database.deleteDocument(id)
    }

    // MARK: - Search

    /// Search the knowledge store
    public func search(
        query: String,
        limit: Int = 10,
        filters: KSearchFilters? = nil
    ) async throws -> [KSearchResult] {
        try await ensureInitialized()

        // Generate query embedding
        let queryEmbedding = try await embeddingEngine.embed(query)

        // Search vector index
        let candidates = vectorIndex.map { (id: $0.key, embedding: $0.value) }
        let matches = await embeddingEngine.findSimilar(
            query: queryEmbedding,
            candidates: candidates,
            limit: limit * 2,  // Get extra for filtering
            minScore: filters?.minScore ?? 0.0
        )

        // Fetch full chunk and document data
        var results: [KSearchResult] = []

        for match in matches {
            // Get chunk from database
            // We need to get the document ID from the chunk first
            // For now, we'll iterate through sources
            var foundChunk: KChunk?
            var foundDocument: KDocument?

            let sources = try await database.getAllSources()
            outer: for source in sources {
                let documents = try await database.getDocuments(sourceId: source.id, limit: 1000)
                for document in documents {
                    // Apply filters
                    if let sourceFilter = filters?.sources, !sourceFilter.contains(document.sourceType) {
                        continue
                    }
                    if let sourceIds = filters?.sourceIds, !sourceIds.contains(document.sourceId) {
                        continue
                    }
                    if let dateRange = filters?.dateRange {
                        let (from, to) = dateRange.dateInterval
                        if document.createdAt < from || document.createdAt > to {
                            continue
                        }
                    }
                    if let authors = filters?.authors, let author = document.metadata.author {
                        if !authors.contains(author) {
                            continue
                        }
                    }

                    let chunks = try await database.getChunks(documentId: document.id)
                    if let chunk = chunks.first(where: { $0.id == match.id }) {
                        foundChunk = chunk
                        foundDocument = document
                        break outer
                    }
                }
            }

            if let chunk = foundChunk, let document = foundDocument {
                results.append(KSearchResult(
                    chunk: chunk,
                    document: document,
                    score: match.score
                ))

                if results.count >= limit {
                    break
                }
            }
        }

        return results
    }

    /// Hybrid search combining vector and keyword search
    public func hybridSearch(
        query: String,
        limit: Int = 10,
        vectorWeight: Float = 0.7,
        filters: KSearchFilters? = nil
    ) async throws -> [KSearchResult] {
        // For now, just use vector search
        // TODO: Implement keyword search and combine scores
        return try await search(query: query, limit: limit, filters: filters)
    }

    // MARK: - Entity Operations

    /// Extract entities from a document
    public func extractEntities(from documentId: String) async throws -> [KEntity] {
        try await ensureInitialized()

        guard let document = try await database.getDocument(id: documentId) else {
            throw KnowledgeStoreError.documentNotFound(documentId)
        }

        // Simple entity extraction using patterns
        // TODO: Use NER model for better extraction
        var entities: [KEntity] = []

        // Extract URLs
        let urlPattern = try! NSRegularExpression(pattern: "https?://[\\w\\-._~:/?#\\[\\]@!$&'()*+,;=%]+", options: [])
        let nsContent = document.content as NSString
        let urlMatches = urlPattern.matches(in: document.content, options: [], range: NSRange(location: 0, length: nsContent.length))

        for match in urlMatches {
            if let range = Range(match.range, in: document.content) {
                let url = String(document.content[range])
                let entity = KEntity(name: url, type: .url)
                entities.append(entity)
                try await database.insertEntity(entity)
            }
        }

        // Extract @mentions (Slack-style)
        let mentionPattern = try! NSRegularExpression(pattern: "@[\\w]+", options: [])
        let mentionMatches = mentionPattern.matches(in: document.content, options: [], range: NSRange(location: 0, length: nsContent.length))

        for match in mentionMatches {
            if let range = Range(match.range, in: document.content) {
                let mention = String(document.content[range])
                let entity = KEntity(name: mention, type: .person)
                entities.append(entity)
                try await database.insertEntity(entity)
            }
        }

        // Extract #hashtags
        let hashtagPattern = try! NSRegularExpression(pattern: "#[\\w]+", options: [])
        let hashtagMatches = hashtagPattern.matches(in: document.content, options: [], range: NSRange(location: 0, length: nsContent.length))

        for match in hashtagMatches {
            if let range = Range(match.range, in: document.content) {
                let hashtag = String(document.content[range])
                let entity = KEntity(name: hashtag, type: .concept)
                entities.append(entity)
                try await database.insertEntity(entity)
            }
        }

        return entities
    }

    /// Find entities by name
    public func findEntities(name: String, type: KEntityType? = nil) async throws -> [KEntity] {
        try await ensureInitialized()
        return try await database.findEntities(name: name, type: type)
    }

    /// Link two entities with a relationship
    public func linkEntities(
        sourceId: String,
        targetId: String,
        relation: KRelationType,
        evidenceChunkId: String? = nil
    ) async throws {
        try await ensureInitialized()

        let entityRelation = KEntityRelation(
            sourceEntityId: sourceId,
            targetEntityId: targetId,
            relationType: relation,
            evidenceChunkId: evidenceChunkId
        )

        try await database.insertRelation(entityRelation)
    }

    // MARK: - Statistics

    /// Get knowledge store statistics
    public func getStats() async throws -> KnowledgeStats {
        try await ensureInitialized()
        return try await database.getStats()
    }

    // MARK: - Maintenance

    /// Rebuild vector index from database
    public func rebuildIndex() async throws {
        try await ensureInitialized()
        vectorIndex.removeAll()
        try await loadVectorIndex()
    }

    /// Re-embed all chunks (useful after model change)
    public func reembedAll(progress: ((Int, Int) -> Void)? = nil) async throws {
        try await ensureInitialized()

        let sources = try await database.getAllSources()
        var total = 0
        var processed = 0

        // Count total chunks
        for source in sources {
            let documents = try await database.getDocuments(sourceId: source.id, limit: 10000)
            for document in documents {
                let chunks = try await database.getChunks(documentId: document.id)
                total += chunks.count
            }
        }

        // Re-embed each chunk
        for source in sources {
            let documents = try await database.getDocuments(sourceId: source.id, limit: 10000)
            for document in documents {
                let chunks = try await database.getChunks(documentId: document.id)
                let texts = chunks.map { $0.content }
                let embeddings = try await embeddingEngine.embedBatch(texts)

                for (i, chunk) in chunks.enumerated() {
                    try await database.updateChunkEmbedding(chunk.id, embedding: embeddings[i])
                    vectorIndex[chunk.id] = embeddings[i]
                    processed += 1
                    progress?(processed, total)
                }
            }
        }
    }
}

// MARK: - Errors

public enum KnowledgeStoreError: Error, LocalizedError {
    case notInitialized
    case documentNotFound(String)
    case sourceNotFound(String)
    case ingestionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Knowledge store not initialized"
        case .documentNotFound(let id):
            return "Document not found: \(id)"
        case .sourceNotFound(let id):
            return "Source not found: \(id)"
        case .ingestionFailed(let reason):
            return "Ingestion failed: \(reason)"
        }
    }
}
