//
//  KnowledgeDatabase.swift
//  AgentKit
//
//  SQLite database wrapper for the Knowledge Backbone.
//  Handles document, chunk, entity, and source storage.
//

import Foundation
import SQLite3

// MARK: - Knowledge Database

/// SQLite database for knowledge storage
public actor KnowledgeDatabase {
    // Using nonisolated(unsafe) because sqlite3 is thread-safe and we need deinit access
    private nonisolated(unsafe) var db: OpaquePointer?
    private let path: String
    private var isInitialized = false

    public init(path: String) {
        self.path = path
    }

    // MARK: - Lifecycle

    /// Open the database and initialize schema
    public func open() throws {
        // Ensure directory exists
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        // Open database
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw KnowledgeDatabaseError.failedToOpen(lastError)
        }

        // Enable WAL mode for better concurrency
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")

        // Initialize schema
        try initializeSchema()
        isInitialized = true
    }

    /// Close the database
    public func close() {
        if let db = db {
            sqlite3_close(db)
        }
        db = nil
        isInitialized = false
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Schema

    private func initializeSchema() throws {
        // Sources table
        try execute("""
            CREATE TABLE IF NOT EXISTS sources (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                name TEXT NOT NULL,
                config TEXT,
                last_sync TEXT,
                sync_cursor TEXT,
                status TEXT DEFAULT 'active',
                error_message TEXT,
                created_at TEXT DEFAULT (datetime('now'))
            )
        """)

        // KDocuments table
        try execute("""
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL,
                source_type TEXT NOT NULL,
                source_ref TEXT,
                title TEXT,
                content TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                created_at TEXT DEFAULT (datetime('now')),
                updated_at TEXT DEFAULT (datetime('now')),
                indexed_at TEXT,
                metadata TEXT,
                FOREIGN KEY (source_id) REFERENCES sources(id)
            )
        """)

        // KChunks table
        try execute("""
            CREATE TABLE IF NOT EXISTS chunks (
                id TEXT PRIMARY KEY,
                document_id TEXT NOT NULL,
                content TEXT NOT NULL,
                position INTEGER NOT NULL,
                start_char INTEGER,
                end_char INTEGER,
                embedding BLOB,
                metadata TEXT,
                FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
            )
        """)

        // Entities table
        try execute("""
            CREATE TABLE IF NOT EXISTS entities (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                type TEXT NOT NULL,
                canonical_name TEXT,
                attributes TEXT,
                created_at TEXT DEFAULT (datetime('now')),
                updated_at TEXT DEFAULT (datetime('now'))
            )
        """)

        // KEntity mentions
        try execute("""
            CREATE TABLE IF NOT EXISTS mentions (
                id TEXT PRIMARY KEY,
                entity_id TEXT NOT NULL,
                chunk_id TEXT NOT NULL,
                start_char INTEGER,
                end_char INTEGER,
                context TEXT,
                confidence REAL,
                FOREIGN KEY (entity_id) REFERENCES entities(id) ON DELETE CASCADE,
                FOREIGN KEY (chunk_id) REFERENCES chunks(id) ON DELETE CASCADE
            )
        """)

        // KEntity relations
        try execute("""
            CREATE TABLE IF NOT EXISTS relations (
                id TEXT PRIMARY KEY,
                source_entity_id TEXT NOT NULL,
                target_entity_id TEXT NOT NULL,
                relation_type TEXT NOT NULL,
                confidence REAL,
                evidence_chunk_id TEXT,
                metadata TEXT,
                FOREIGN KEY (source_entity_id) REFERENCES entities(id) ON DELETE CASCADE,
                FOREIGN KEY (target_entity_id) REFERENCES entities(id) ON DELETE CASCADE,
                FOREIGN KEY (evidence_chunk_id) REFERENCES chunks(id)
            )
        """)

        // Indexes
        try execute("CREATE INDEX IF NOT EXISTS idx_documents_source ON documents(source_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_documents_updated ON documents(updated_at)")
        try execute("CREATE INDEX IF NOT EXISTS idx_documents_hash ON documents(content_hash)")
        try execute("CREATE INDEX IF NOT EXISTS idx_chunks_document ON chunks(document_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(type)")
        try execute("CREATE INDEX IF NOT EXISTS idx_entities_name ON entities(name)")
        try execute("CREATE INDEX IF NOT EXISTS idx_mentions_entity ON mentions(entity_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_mentions_chunk ON mentions(chunk_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_relations_source ON relations(source_entity_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_relations_target ON relations(target_entity_id)")
    }

    // MARK: - Source Operations

    public func insertSource(_ source: KSource) throws {
        let sql = """
            INSERT OR REPLACE INTO sources (id, type, name, config, last_sync, sync_cursor, status, error_message, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        let configJson = try? JSONEncoder().encode(source.config)
        let configString = configJson.flatMap { String(data: $0, encoding: .utf8) }

        try execute(sql, params: [
            source.id,
            source.type.rawValue,
            source.name,
            configString,
            source.lastSync?.iso8601String,
            source.syncCursor,
            source.status.rawValue,
            source.errorMessage,
            source.createdAt.iso8601String
        ])
    }

    public func getSource(id: String) throws -> KSource? {
        let sql = "SELECT * FROM sources WHERE id = ?"
        let rows = try query(sql, params: [id])
        return rows.first.flatMap { parseSource($0) }
    }

    public func getAllSources() throws -> [KSource] {
        let sql = "SELECT * FROM sources ORDER BY name"
        let rows = try query(sql)
        return rows.compactMap { parseSource($0) }
    }

    public func updateSourceStatus(_ sourceId: String, status: KSourceStatus, error: String? = nil) throws {
        let sql = "UPDATE sources SET status = ?, error_message = ? WHERE id = ?"
        try execute(sql, params: [status.rawValue, error, sourceId])
    }

    public func updateSourceSync(_ sourceId: String, lastSync: Date, cursor: String?) throws {
        let sql = "UPDATE sources SET last_sync = ?, sync_cursor = ?, status = 'active' WHERE id = ?"
        try execute(sql, params: [lastSync.iso8601String, cursor, sourceId])
    }

    // MARK: - KDocument Operations

    public func insertDocument(_ document: KDocument) throws {
        let sql = """
            INSERT OR REPLACE INTO documents (id, source_id, source_type, source_ref, title, content, content_hash, created_at, updated_at, indexed_at, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        let metadataJson = try? JSONEncoder().encode(document.metadata)
        let metadataString = metadataJson.flatMap { String(data: $0, encoding: .utf8) }

        try execute(sql, params: [
            document.id,
            document.sourceId,
            document.sourceType.rawValue,
            document.sourceRef,
            document.title,
            document.content,
            document.contentHash,
            document.createdAt.iso8601String,
            document.updatedAt.iso8601String,
            document.indexedAt?.iso8601String,
            metadataString
        ])
    }

    public func getDocument(id: String) throws -> KDocument? {
        let sql = "SELECT * FROM documents WHERE id = ?"
        let rows = try query(sql, params: [id])
        return rows.first.flatMap { parseDocument($0) }
    }

    public func getDocumentByHash(_ hash: String, sourceId: String) throws -> KDocument? {
        let sql = "SELECT * FROM documents WHERE content_hash = ? AND source_id = ?"
        let rows = try query(sql, params: [hash, sourceId])
        return rows.first.flatMap { parseDocument($0) }
    }

    public func getDocuments(sourceId: String, limit: Int = 100, offset: Int = 0) throws -> [KDocument] {
        let sql = "SELECT * FROM documents WHERE source_id = ? ORDER BY updated_at DESC LIMIT ? OFFSET ?"
        let rows = try query(sql, params: [sourceId, limit, offset])
        return rows.compactMap { parseDocument($0) }
    }

    public func deleteDocument(_ id: String) throws {
        try execute("DELETE FROM documents WHERE id = ?", params: [id])
    }

    public func markDocumentIndexed(_ id: String) throws {
        let sql = "UPDATE documents SET indexed_at = ? WHERE id = ?"
        try execute(sql, params: [Date().iso8601String, id])
    }

    // MARK: - KChunk Operations

    public func insertChunks(_ chunks: [KChunk]) throws {
        let sql = """
            INSERT OR REPLACE INTO chunks (id, document_id, content, position, start_char, end_char, embedding, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """

        for chunk in chunks {
            let metadataJson = try? JSONEncoder().encode(chunk.metadata)
            let metadataString = metadataJson.flatMap { String(data: $0, encoding: .utf8) }
            let embeddingBlob = chunk.embedding.flatMap { floatArrayToBlob($0) }

            try execute(sql, params: [
                chunk.id,
                chunk.documentId,
                chunk.content,
                chunk.position,
                chunk.startChar,
                chunk.endChar,
                embeddingBlob,
                metadataString
            ])
        }
    }

    public func getChunks(documentId: String) throws -> [KChunk] {
        let sql = "SELECT * FROM chunks WHERE document_id = ? ORDER BY position"
        let rows = try query(sql, params: [documentId])
        return rows.compactMap { parseChunk($0) }
    }

    public func deleteChunks(documentId: String) throws {
        try execute("DELETE FROM chunks WHERE document_id = ?", params: [documentId])
    }

    public func updateChunkEmbedding(_ chunkId: String, embedding: [Float]) throws {
        let sql = "UPDATE chunks SET embedding = ? WHERE id = ?"
        let blob = floatArrayToBlob(embedding)
        try execute(sql, params: [blob, chunkId])
    }

    // MARK: - KEntity Operations

    public func insertEntity(_ entity: KEntity) throws {
        let sql = """
            INSERT OR REPLACE INTO entities (id, name, type, canonical_name, attributes, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        let attributesJson = try? JSONEncoder().encode(entity.attributes)
        let attributesString = attributesJson.flatMap { String(data: $0, encoding: .utf8) }

        try execute(sql, params: [
            entity.id,
            entity.name,
            entity.type.rawValue,
            entity.canonicalName,
            attributesString,
            entity.createdAt.iso8601String,
            entity.updatedAt.iso8601String
        ])
    }

    public func getEntity(id: String) throws -> KEntity? {
        let sql = "SELECT * FROM entities WHERE id = ?"
        let rows = try query(sql, params: [id])
        return rows.first.flatMap { parseEntity($0) }
    }

    public func findEntities(name: String, type: KEntityType? = nil) throws -> [KEntity] {
        var sql = "SELECT * FROM entities WHERE name LIKE ?"
        var params: [Any?] = ["%\(name)%"]

        if let type = type {
            sql += " AND type = ?"
            params.append(type.rawValue)
        }

        let rows = try query(sql, params: params)
        return rows.compactMap { parseEntity($0) }
    }

    // MARK: - Mention Operations

    public func insertMention(_ mention: KEntityMention) throws {
        let sql = """
            INSERT OR REPLACE INTO mentions (id, entity_id, chunk_id, start_char, end_char, context, confidence)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        try execute(sql, params: [
            mention.id,
            mention.entityId,
            mention.chunkId,
            mention.startChar,
            mention.endChar,
            mention.context,
            mention.confidence
        ])
    }

    public func getMentions(entityId: String) throws -> [KEntityMention] {
        let sql = "SELECT * FROM mentions WHERE entity_id = ?"
        let rows = try query(sql, params: [entityId])
        return rows.compactMap { parseMention($0) }
    }

    // MARK: - Relation Operations

    public func insertRelation(_ relation: KEntityRelation) throws {
        let sql = """
            INSERT OR REPLACE INTO relations (id, source_entity_id, target_entity_id, relation_type, confidence, evidence_chunk_id, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        let metadataJson = try? JSONEncoder().encode(relation.metadata)
        let metadataString = metadataJson.flatMap { String(data: $0, encoding: .utf8) }

        try execute(sql, params: [
            relation.id,
            relation.sourceEntityId,
            relation.targetEntityId,
            relation.relationType.rawValue,
            relation.confidence,
            relation.evidenceChunkId,
            metadataString
        ])
    }

    public func getRelations(entityId: String) throws -> [KEntityRelation] {
        let sql = "SELECT * FROM relations WHERE source_entity_id = ? OR target_entity_id = ?"
        let rows = try query(sql, params: [entityId, entityId])
        return rows.compactMap { parseRelation($0) }
    }

    // MARK: - Statistics

    public func getStats() throws -> KnowledgeStats {
        let sources = try querySingle("SELECT COUNT(*) FROM sources") ?? 0
        let documents = try querySingle("SELECT COUNT(*) FROM documents") ?? 0
        let chunks = try querySingle("SELECT COUNT(*) FROM chunks") ?? 0
        let entities = try querySingle("SELECT COUNT(*) FROM entities") ?? 0
        let relations = try querySingle("SELECT COUNT(*) FROM relations") ?? 0
        let indexedChunks = try querySingle("SELECT COUNT(*) FROM chunks WHERE embedding IS NOT NULL") ?? 0

        return KnowledgeStats(
            sourceCount: sources,
            documentCount: documents,
            chunkCount: chunks,
            entityCount: entities,
            relationCount: relations,
            indexedChunkCount: indexedChunks
        )
    }

    // MARK: - SQL Helpers

    private func execute(_ sql: String, params: [Any?] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw KnowledgeDatabaseError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(stmt) }

        try bindParams(stmt, params)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw KnowledgeDatabaseError.executeFailed(lastError)
        }
    }

    private func query(_ sql: String, params: [Any?] = []) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw KnowledgeDatabaseError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(stmt) }

        try bindParams(stmt, params)

        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let columnCount = sqlite3_column_count(stmt)
            for i in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                let type = sqlite3_column_type(stmt, i)

                switch type {
                case SQLITE_INTEGER:
                    row[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(stmt, i) {
                        row[name] = String(cString: text)
                    }
                case SQLITE_BLOB:
                    let bytes = sqlite3_column_blob(stmt, i)
                    let size = sqlite3_column_bytes(stmt, i)
                    if let bytes = bytes {
                        row[name] = Data(bytes: bytes, count: Int(size))
                    }
                default:
                    row[name] = NSNull()
                }
            }
            results.append(row)
        }

        return results
    }

    private func querySingle(_ sql: String) throws -> Int? {
        let rows = try query(sql)
        if let firstRow = rows.first, let firstValue = firstRow.values.first {
            return (firstValue as? Int64).map { Int($0) }
        }
        return nil
    }

    private func bindParams(_ stmt: OpaquePointer?, _ params: [Any?]) throws {
        for (index, param) in params.enumerated() {
            let idx = Int32(index + 1)
            if param == nil {
                sqlite3_bind_null(stmt, idx)
            } else if let value = param as? String {
                sqlite3_bind_text(stmt, idx, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else if let value = param as? Int {
                sqlite3_bind_int64(stmt, idx, Int64(value))
            } else if let value = param as? Int64 {
                sqlite3_bind_int64(stmt, idx, value)
            } else if let value = param as? Double {
                sqlite3_bind_double(stmt, idx, value)
            } else if let value = param as? Float {
                sqlite3_bind_double(stmt, idx, Double(value))
            } else if let value = param as? Data {
                value.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, idx, ptr.baseAddress, Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            } else {
                throw KnowledgeDatabaseError.invalidParameter("Unsupported parameter type at index \(index)")
            }
        }
    }

    private var lastError: String {
        String(cString: sqlite3_errmsg(db))
    }

    // MARK: - Parsing Helpers

    private func parseSource(_ row: [String: Any]) -> KSource? {
        guard let id = row["id"] as? String,
              let typeRaw = row["type"] as? String,
              let type = KSourceType(rawValue: typeRaw),
              let name = row["name"] as? String else {
            return nil
        }

        var source = KSource(id: id, type: type, name: name)

        if let configString = row["config"] as? String,
           let configData = configString.data(using: .utf8),
           let config = try? JSONDecoder().decode(KSourceConfig.self, from: configData) {
            source.config = config
        }

        if let lastSyncString = row["last_sync"] as? String {
            source.lastSync = Date.fromISO8601(lastSyncString)
        }
        source.syncCursor = row["sync_cursor"] as? String
        if let statusRaw = row["status"] as? String {
            source.status = KSourceStatus(rawValue: statusRaw) ?? .active
        }
        source.errorMessage = row["error_message"] as? String

        return source
    }

    private func parseDocument(_ row: [String: Any]) -> KDocument? {
        guard let id = row["id"] as? String,
              let sourceId = row["source_id"] as? String,
              let sourceTypeRaw = row["source_type"] as? String,
              let sourceType = KSourceType(rawValue: sourceTypeRaw),
              let content = row["content"] as? String else {
            return nil
        }

        var doc = KDocument(
            id: id,
            sourceId: sourceId,
            sourceType: sourceType,
            sourceRef: row["source_ref"] as? String,
            title: row["title"] as? String,
            content: content
        )

        if let metadataString = row["metadata"] as? String,
           let metadataData = metadataString.data(using: .utf8),
           let metadata = try? JSONDecoder().decode(KDocumentMetadata.self, from: metadataData) {
            doc.metadata = metadata
        }

        if let indexedString = row["indexed_at"] as? String {
            doc.indexedAt = Date.fromISO8601(indexedString)
        }

        return doc
    }

    private func parseChunk(_ row: [String: Any]) -> KChunk? {
        guard let id = row["id"] as? String,
              let documentId = row["document_id"] as? String,
              let content = row["content"] as? String,
              let position = row["position"] as? Int64 else {
            return nil
        }

        var chunk = KChunk(
            id: id,
            documentId: documentId,
            content: content,
            position: Int(position),
            startChar: (row["start_char"] as? Int64).map { Int($0) },
            endChar: (row["end_char"] as? Int64).map { Int($0) }
        )

        if let embeddingData = row["embedding"] as? Data {
            chunk.embedding = blobToFloatArray(embeddingData)
        }

        if let metadataString = row["metadata"] as? String,
           let metadataData = metadataString.data(using: .utf8),
           let metadata = try? JSONDecoder().decode(KChunkMetadata.self, from: metadataData) {
            chunk.metadata = metadata
        }

        return chunk
    }

    private func parseEntity(_ row: [String: Any]) -> KEntity? {
        guard let id = row["id"] as? String,
              let name = row["name"] as? String,
              let typeRaw = row["type"] as? String,
              let type = KEntityType(rawValue: typeRaw) else {
            return nil
        }

        var entity = KEntity(id: id, name: name, type: type)
        entity.canonicalName = row["canonical_name"] as? String

        if let attributesString = row["attributes"] as? String,
           let attributesData = attributesString.data(using: .utf8),
           let attributes = try? JSONDecoder().decode([String: String].self, from: attributesData) {
            entity.attributes = attributes
        }

        return entity
    }

    private func parseMention(_ row: [String: Any]) -> KEntityMention? {
        guard let id = row["id"] as? String,
              let entityId = row["entity_id"] as? String,
              let chunkId = row["chunk_id"] as? String else {
            return nil
        }

        return KEntityMention(
            id: id,
            entityId: entityId,
            chunkId: chunkId,
            startChar: (row["start_char"] as? Int64).map { Int($0) },
            endChar: (row["end_char"] as? Int64).map { Int($0) },
            context: row["context"] as? String,
            confidence: (row["confidence"] as? Double).map { Float($0) } ?? 1.0
        )
    }

    private func parseRelation(_ row: [String: Any]) -> KEntityRelation? {
        guard let id = row["id"] as? String,
              let sourceId = row["source_entity_id"] as? String,
              let targetId = row["target_entity_id"] as? String,
              let typeRaw = row["relation_type"] as? String,
              let type = KRelationType(rawValue: typeRaw) else {
            return nil
        }

        var relation = KEntityRelation(
            id: id,
            sourceEntityId: sourceId,
            targetEntityId: targetId,
            relationType: type,
            confidence: (row["confidence"] as? Double).map { Float($0) } ?? 1.0,
            evidenceChunkId: row["evidence_chunk_id"] as? String
        )

        if let metadataString = row["metadata"] as? String,
           let metadataData = metadataString.data(using: .utf8),
           let metadata = try? JSONDecoder().decode([String: String].self, from: metadataData) {
            relation.metadata = metadata
        }

        return relation
    }

    // MARK: - Blob Helpers

    private func floatArrayToBlob(_ floats: [Float]) -> Data {
        var data = Data()
        for float in floats {
            var value = float
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }

    private func blobToFloatArray(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        var floats = [Float](repeating: 0, count: count)
        _ = floats.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return floats
    }
}

// MARK: - Stats

public struct KnowledgeStats: Sendable {
    public let sourceCount: Int
    public let documentCount: Int
    public let chunkCount: Int
    public let entityCount: Int
    public let relationCount: Int
    public let indexedChunkCount: Int

    public var indexingProgress: Double {
        guard chunkCount > 0 else { return 0 }
        return Double(indexedChunkCount) / Double(chunkCount)
    }
}

// MARK: - Errors

public enum KnowledgeDatabaseError: Error, LocalizedError {
    case failedToOpen(String)
    case prepareFailed(String)
    case executeFailed(String)
    case invalidParameter(String)

    public var errorDescription: String? {
        switch self {
        case .failedToOpen(let msg): return "Failed to open database: \(msg)"
        case .prepareFailed(let msg): return "Failed to prepare statement: \(msg)"
        case .executeFailed(let msg): return "Failed to execute: \(msg)"
        case .invalidParameter(let msg): return "Invalid parameter: \(msg)"
        }
    }
}

// MARK: - Date Extensions

extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }

    static func fromISO8601(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
