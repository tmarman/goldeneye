//
//  KnowledgeDocument.swift
//  AgentKit
//
//  Core document model for the Knowledge Backbone.
//  Prefixed with K to avoid collision with Workspace.Document
//

import Foundation
import CommonCrypto

// MARK: - Knowledge Document

/// A document in the knowledge store.
/// Documents are the primary unit of content - they get chunked and embedded for search.
public struct KDocument: Sendable, Identifiable, Codable {
    public let id: String
    public let sourceId: String
    public let sourceType: KSourceType
    public let sourceRef: String?  // Source-specific reference (e.g., slack ts, file path)
    public let title: String?
    public let content: String
    public let contentHash: String
    public let createdAt: Date
    public var updatedAt: Date
    public var indexedAt: Date?
    public var metadata: KDocumentMetadata

    public init(
        id: String = UUID().uuidString,
        sourceId: String,
        sourceType: KSourceType,
        sourceRef: String? = nil,
        title: String? = nil,
        content: String,
        createdAt: Date = Date(),
        metadata: KDocumentMetadata = KDocumentMetadata()
    ) {
        self.id = id
        self.sourceId = sourceId
        self.sourceType = sourceType
        self.sourceRef = sourceRef
        self.title = title
        self.content = content
        self.contentHash = content.kSha256Hash
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.indexedAt = nil
        self.metadata = metadata
    }
}

// MARK: - Document Metadata

/// Flexible metadata for documents
public struct KDocumentMetadata: Sendable, Codable {
    public var author: String?
    public var authorId: String?
    public var tags: [String]
    public var language: String?
    public var wordCount: Int?
    public var custom: [String: String]

    public init(
        author: String? = nil,
        authorId: String? = nil,
        tags: [String] = [],
        language: String? = nil,
        wordCount: Int? = nil,
        custom: [String: String] = [:]
    ) {
        self.author = author
        self.authorId = authorId
        self.tags = tags
        self.language = language
        self.wordCount = wordCount
        self.custom = custom
    }
}

// MARK: - Chunk

/// A chunk of a document, with its embedding.
/// Chunks are the unit of retrieval - search returns chunks, not full documents.
public struct KChunk: Sendable, Identifiable, Codable {
    public let id: String
    public let documentId: String
    public let content: String
    public let position: Int        // Chunk index within document
    public let startChar: Int?      // Character offset in original
    public let endChar: Int?
    public var embedding: [Float]?
    public var metadata: KChunkMetadata

    public init(
        id: String = UUID().uuidString,
        documentId: String,
        content: String,
        position: Int,
        startChar: Int? = nil,
        endChar: Int? = nil,
        embedding: [Float]? = nil,
        metadata: KChunkMetadata = KChunkMetadata()
    ) {
        self.id = id
        self.documentId = documentId
        self.content = content
        self.position = position
        self.startChar = startChar
        self.endChar = endChar
        self.embedding = embedding
        self.metadata = metadata
    }
}

/// Chunk-specific metadata
public struct KChunkMetadata: Sendable, Codable {
    public var headings: [String]?      // Section headers above this chunk
    public var chunkType: KChunkType?
    public var custom: [String: String]

    public init(
        headings: [String]? = nil,
        chunkType: KChunkType? = nil,
        custom: [String: String] = [:]
    ) {
        self.headings = headings
        self.chunkType = chunkType
        self.custom = custom
    }
}

/// Type of chunk content
public enum KChunkType: String, Sendable, Codable {
    case paragraph
    case heading
    case code
    case list
    case table
    case quote
    case other
}

// MARK: - Search Result

/// A search result from the knowledge store
public struct KSearchResult: Sendable, Identifiable {
    public let id: String
    public let chunk: KChunk
    public let document: KDocument
    public let score: Float
    public let highlights: [String]?

    public init(
        chunk: KChunk,
        document: KDocument,
        score: Float,
        highlights: [String]? = nil
    ) {
        self.id = chunk.id
        self.chunk = chunk
        self.document = document
        self.score = score
        self.highlights = highlights
    }
}

// MARK: - Search Filters

/// Filters for knowledge search
public struct KSearchFilters: Sendable {
    public var sources: [KSourceType]?
    public var sourceIds: [String]?
    public var dateRange: DateRange?
    public var authors: [String]?
    public var tags: [String]?
    public var minScore: Float?

    public init(
        sources: [KSourceType]? = nil,
        sourceIds: [String]? = nil,
        dateRange: DateRange? = nil,
        authors: [String]? = nil,
        tags: [String]? = nil,
        minScore: Float? = nil
    ) {
        self.sources = sources
        self.sourceIds = sourceIds
        self.dateRange = dateRange
        self.authors = authors
        self.tags = tags
        self.minScore = minScore
    }

    public enum DateRange: Sendable {
        case lastHour
        case lastDay
        case lastWeek
        case lastMonth
        case lastYear
        case custom(from: Date, to: Date)

        public var dateInterval: (from: Date, to: Date) {
            let now = Date()
            let calendar = Calendar.current
            switch self {
            case .lastHour:
                return (calendar.date(byAdding: .hour, value: -1, to: now)!, now)
            case .lastDay:
                return (calendar.date(byAdding: .day, value: -1, to: now)!, now)
            case .lastWeek:
                return (calendar.date(byAdding: .weekOfYear, value: -1, to: now)!, now)
            case .lastMonth:
                return (calendar.date(byAdding: .month, value: -1, to: now)!, now)
            case .lastYear:
                return (calendar.date(byAdding: .year, value: -1, to: now)!, now)
            case .custom(let from, let to):
                return (from, to)
            }
        }
    }
}

// MARK: - Helpers

extension String {
    /// SHA256 hash of the string (prefixed to avoid collision)
    var kSha256Hash: String {
        let data = Data(self.utf8)
        var hash = [UInt8](repeating: 0, count: 32)

        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
