//
//  KnowledgeTools.swift
//  AgentKit
//
//  MCP tools for knowledge backbone operations.
//  Provides search, ingest, and entity extraction capabilities to agents.
//

import Foundation

// MARK: - Knowledge Search Tool

/// Search the knowledge backbone for relevant information
public struct KnowledgeSearchTool: Tool {
    private let store: KnowledgeStore

    public let name = "knowledge_search"
    public let description = """
        Search your personal knowledge base for relevant information.
        This includes indexed Slack messages, documents, notes, emails, and more.
        Use semantic search to find contextually relevant content.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "query": .init(
                    type: "string",
                    description: "The search query - describe what you're looking for"
                ),
                "limit": .init(
                    type: "integer",
                    description: "Maximum number of results (default: 10)"
                ),
                "source_type": .init(
                    type: "string",
                    description: "Filter by source type",
                    enumValues: KSourceType.allCases.map { $0.rawValue }
                ),
                "min_score": .init(
                    type: "number",
                    description: "Minimum similarity score 0.0-1.0 (default: 0.5)"
                )
            ],
            required: ["query"]
        )
    }

    public init(store: KnowledgeStore) {
        self.store = store
    }

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let query = try input.require("query", as: String.self)
        let limit = input.get("limit", as: Int.self) ?? 10
        let minScore = input.get("min_score", as: Double.self).map { Float($0) } ?? 0.5

        var filters = KSearchFilters(minScore: minScore)
        if let sourceTypeStr = input.get("source_type", as: String.self),
           let sourceType = KSourceType(rawValue: sourceTypeStr) {
            filters.sources = [sourceType]
        }

        do {
            let results = try await store.search(query: query, limit: limit, filters: filters)

            if results.isEmpty {
                return .success("No results found for: \"\(query)\"")
            }

            var output = "Found \(results.count) results:\n\n"

            for (i, result) in results.enumerated() {
                output += "[\(i + 1)] Score: \(String(format: "%.2f", result.score))\n"
                output += "Source: \(result.document.sourceType.rawValue) | \(result.document.title ?? "Untitled")\n"
                if let author = result.document.metadata.author {
                    output += "Author: \(author)\n"
                }
                output += "---\n"
                output += result.chunk.content.prefix(500)
                if result.chunk.content.count > 500 {
                    output += "...\n"
                }
                output += "\n\n"
            }

            return .success(output)
        } catch {
            return .error("Search failed: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let query = input.get("query", as: String.self) {
            return "Search knowledge base for: \"\(query)\""
        }
        return "Search knowledge base"
    }
}

// MARK: - Knowledge Ingest Tool

/// Ingest content into the knowledge backbone
public struct KnowledgeIngestTool: Tool {
    private let store: KnowledgeStore

    public let name = "knowledge_ingest"
    public let description = """
        Add content to the knowledge base for future retrieval.
        Use this to store important information, notes, or decisions.
        Content is automatically chunked, embedded, and indexed for semantic search.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "title": .init(
                    type: "string",
                    description: "Title for this content"
                ),
                "content": .init(
                    type: "string",
                    description: "The content to store"
                ),
                "source_type": .init(
                    type: "string",
                    description: "Type of source (default: manual)",
                    enumValues: ["manual", "notes", "web"]
                ),
                "author": .init(
                    type: "string",
                    description: "Author of the content (optional)"
                )
            ],
            required: ["title", "content"]
        )
    }

    public init(store: KnowledgeStore) {
        self.store = store
    }

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let title = try input.require("title", as: String.self)
        let content = try input.require("content", as: String.self)
        let sourceTypeStr = input.get("source_type", as: String.self) ?? "manual"
        let author = input.get("author", as: String.self)

        let sourceType = KSourceType(rawValue: sourceTypeStr) ?? .manual

        // Create or get manual source
        let sourceId = "manual-agent-ingestion"
        let sources = try await store.getSources()

        if !sources.contains(where: { $0.id == sourceId }) {
            let source = KSource(
                id: sourceId,
                type: .manual,
                name: "Agent Ingested Content"
            )
            _ = try await store.registerSource(source)
        }

        // Create document
        var metadata = KDocumentMetadata()
        metadata.author = author

        let document = KDocument(
            sourceId: sourceId,
            sourceType: sourceType,
            title: title,
            content: content,
            metadata: metadata
        )

        do {
            let docId = try await store.ingest(document: document)
            return .success("✅ Content ingested successfully\nDocument ID: \(docId)\nTitle: \(title)\nContent length: \(content.count) characters")
        } catch {
            return .error("Ingestion failed: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let title = input.get("title", as: String.self) {
            return "Ingest content: \"\(title)\""
        }
        return "Ingest content into knowledge base"
    }
}

// MARK: - Knowledge Stats Tool

/// Get statistics about the knowledge backbone
public struct KnowledgeStatsTool: Tool {
    private let store: KnowledgeStore

    public let name = "knowledge_stats"
    public let description = """
        Get statistics about the knowledge base.
        Shows counts of sources, documents, chunks, entities, and indexing progress.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(properties: [:])
    }

    public init(store: KnowledgeStore) {
        self.store = store
    }

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        do {
            let stats = try await store.getStats()
            let sources = try await store.getSources()

            var output = """
                📊 Knowledge Base Statistics
                ────────────────────────────
                Sources:    \(stats.sourceCount)
                Documents:  \(stats.documentCount)
                Chunks:     \(stats.chunkCount)
                Entities:   \(stats.entityCount)
                Relations:  \(stats.relationCount)

                Indexing:   \(String(format: "%.1f", stats.indexingProgress * 100))% complete

                """

            if !sources.isEmpty {
                output += "Registered Sources:\n"
                for source in sources {
                    output += "  • \(source.name) (\(source.type.rawValue)) - \(source.status.rawValue)\n"
                }
            }

            return .success(output)
        } catch {
            return .error("Failed to get stats: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        "Get knowledge base statistics"
    }
}

// MARK: - Knowledge Entity Search Tool

/// Search for entities in the knowledge graph
public struct KnowledgeEntityTool: Tool {
    private let store: KnowledgeStore

    public let name = "knowledge_entities"
    public let description = """
        Search for entities (people, projects, concepts) in the knowledge graph.
        Entities are automatically extracted from indexed content.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "name": .init(
                    type: "string",
                    description: "Entity name to search for"
                ),
                "type": .init(
                    type: "string",
                    description: "Filter by entity type",
                    enumValues: KEntityType.allCases.map { $0.rawValue }
                )
            ],
            required: ["name"]
        )
    }

    public init(store: KnowledgeStore) {
        self.store = store
    }

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let name = try input.require("name", as: String.self)
        var entityType: KEntityType? = nil

        if let typeStr = input.get("type", as: String.self) {
            entityType = KEntityType(rawValue: typeStr)
        }

        do {
            let entities = try await store.findEntities(name: name, type: entityType)

            if entities.isEmpty {
                return .success("No entities found matching: \"\(name)\"")
            }

            var output = "Found \(entities.count) entities:\n\n"

            for entity in entities {
                output += "• \(entity.displayName) (\(entity.type.displayName))\n"
                if !entity.attributes.isEmpty {
                    for (key, value) in entity.attributes {
                        output += "  \(key): \(value)\n"
                    }
                }
            }

            return .success(output)
        } catch {
            return .error("Entity search failed: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let name = input.get("name", as: String.self) {
            return "Search entities for: \"\(name)\""
        }
        return "Search knowledge entities"
    }
}

// MARK: - Tool Factory

/// Factory for creating knowledge tools with a shared store
public struct KnowledgeToolFactory: Sendable {
    private let store: KnowledgeStore

    public init(store: KnowledgeStore) {
        self.store = store
    }

    /// Create all knowledge tools
    public func createTools() -> [any Tool] {
        [
            KnowledgeSearchTool(store: store),
            KnowledgeIngestTool(store: store),
            KnowledgeStatsTool(store: store),
            KnowledgeEntityTool(store: store)
        ]
    }
}
