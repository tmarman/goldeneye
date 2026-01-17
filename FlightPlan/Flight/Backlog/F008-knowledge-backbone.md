# F008: Knowledge Backbone

## Overview

Local-first knowledge infrastructure that indexes, embeds, and makes searchable all of your data sources. This is the foundation for the entire "Goldeneye Intelligence Network" - collectors feed into it, synthesis agents query it, and all interfaces access it.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     KNOWLEDGE BACKBONE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │  Vector Store   │    │  Knowledge DB   │                    │
│  │   (SQLite +     │    │    (SQLite)     │                    │
│  │   vec extension)│    │                 │                    │
│  │                 │    │  - Documents    │                    │
│  │  - Embeddings   │    │  - Entities     │                    │
│  │  - Chunks       │    │  - Relations    │                    │
│  │  - Metadata     │    │  - Sources      │                    │
│  └────────┬────────┘    └────────┬────────┘                    │
│           │                      │                              │
│           └──────────┬───────────┘                              │
│                      │                                          │
│           ┌──────────▼──────────┐                              │
│           │   Embedding Engine  │                              │
│           │  (MLX / Local Model)│                              │
│           └─────────────────────┘                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. KnowledgeStore (Core)

The central actor that manages all knowledge operations.

```swift
public actor KnowledgeStore {
    // Vector search
    func search(query: String, limit: Int, filters: SearchFilters?) async throws -> [SearchResult]

    // Document management
    func ingest(document: Document, source: Source) async throws -> DocumentID
    func update(documentId: DocumentID, content: String) async throws
    func delete(documentId: DocumentID) async throws

    // Entity extraction & linking
    func extractEntities(from documentId: DocumentID) async throws -> [Entity]
    func linkEntities(entity1: EntityID, entity2: EntityID, relation: String) async throws

    // Source management
    func registerSource(source: Source) async throws -> SourceID
    func getSourceStatus(sourceId: SourceID) async throws -> SourceStatus
}
```

### 2. EmbeddingEngine

Local embedding generation using MLX or sentence-transformers.

```swift
public actor EmbeddingEngine {
    // Generate embeddings for text
    func embed(text: String) async throws -> [Float]
    func embedBatch(texts: [String]) async throws -> [[Float]]

    // Model management
    func loadModel(_ model: EmbeddingModel) async throws
    var currentModel: EmbeddingModel { get }
}

public enum EmbeddingModel {
    case bgeSmall      // 384 dims, fast
    case bgeLarge      // 1024 dims, better quality
    case e5Small       // 384 dims, good for queries
    case custom(path: String, dimensions: Int)
}
```

### 3. Document Types

```swift
public struct Document: Sendable {
    let id: DocumentID
    let content: String
    let metadata: DocumentMetadata
    let chunks: [Chunk]
    let source: SourceReference
    let createdAt: Date
    let updatedAt: Date
}

public struct Chunk: Sendable {
    let id: ChunkID
    let content: String
    let embedding: [Float]?
    let position: Int
    let metadata: ChunkMetadata
}

public struct Entity: Sendable {
    let id: EntityID
    let name: String
    let type: EntityType  // person, project, concept, decision, etc.
    let mentions: [Mention]
    let attributes: [String: String]
}
```

### 4. Source Types

```swift
public enum SourceType: String, Codable {
    case slack
    case quip
    case localFile
    case notes
    case mail
    case rss
    case web
    case manual
}

public struct Source: Sendable {
    let id: SourceID
    let type: SourceType
    let name: String
    let config: SourceConfig
    let lastSync: Date?
    let status: SourceStatus
}
```

## Implementation Phases

### Phase 1: Core Storage
- [ ] SQLite database schema for documents, chunks, entities
- [ ] sqlite-vec extension integration for vector search
- [ ] Basic CRUD operations
- [ ] Chunking strategies (fixed size, semantic, hybrid)

### Phase 2: Embedding Engine
- [ ] MLX embedding model loading
- [ ] Batch embedding generation
- [ ] Model switching support
- [ ] Embedding cache

### Phase 3: Search & Retrieval
- [ ] Vector similarity search
- [ ] Hybrid search (vector + keyword)
- [ ] Filtered search by source/date/type
- [ ] Result ranking and deduplication

### Phase 4: Entity Extraction
- [ ] Named entity recognition (local model)
- [ ] Entity linking and deduplication
- [ ] Relationship extraction
- [ ] Knowledge graph queries

### Phase 5: MCP Interface
- [ ] knowledge_search tool
- [ ] knowledge_ingest tool
- [ ] knowledge_entities tool
- [ ] knowledge_sources tool

## Database Schema

```sql
-- Documents table
CREATE TABLE documents (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    source_type TEXT NOT NULL,
    source_ref TEXT,  -- e.g., slack channel+ts, file path
    title TEXT,
    content TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    indexed_at DATETIME,
    metadata JSON,
    FOREIGN KEY (source_id) REFERENCES sources(id)
);

-- Chunks table (for embeddings)
CREATE TABLE chunks (
    id TEXT PRIMARY KEY,
    document_id TEXT NOT NULL,
    content TEXT NOT NULL,
    position INTEGER NOT NULL,
    start_char INTEGER,
    end_char INTEGER,
    embedding BLOB,  -- sqlite-vec compatible
    metadata JSON,
    FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
);

-- Create vector index
CREATE VIRTUAL TABLE chunks_vec USING vec0(
    embedding float[384]
);

-- Entities table
CREATE TABLE entities (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    canonical_name TEXT,
    attributes JSON,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Entity mentions (linking entities to chunks)
CREATE TABLE mentions (
    id TEXT PRIMARY KEY,
    entity_id TEXT NOT NULL,
    chunk_id TEXT NOT NULL,
    start_char INTEGER,
    end_char INTEGER,
    context TEXT,
    confidence REAL,
    FOREIGN KEY (entity_id) REFERENCES entities(id) ON DELETE CASCADE,
    FOREIGN KEY (chunk_id) REFERENCES chunks(id) ON DELETE CASCADE
);

-- Entity relationships
CREATE TABLE relations (
    id TEXT PRIMARY KEY,
    source_entity_id TEXT NOT NULL,
    target_entity_id TEXT NOT NULL,
    relation_type TEXT NOT NULL,
    confidence REAL,
    evidence_chunk_id TEXT,
    metadata JSON,
    FOREIGN KEY (source_entity_id) REFERENCES entities(id) ON DELETE CASCADE,
    FOREIGN KEY (target_entity_id) REFERENCES entities(id) ON DELETE CASCADE,
    FOREIGN KEY (evidence_chunk_id) REFERENCES chunks(id)
);

-- Sources table
CREATE TABLE sources (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    name TEXT NOT NULL,
    config JSON,
    last_sync DATETIME,
    sync_cursor TEXT,  -- For incremental sync
    status TEXT DEFAULT 'active',
    error_message TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_documents_source ON documents(source_id);
CREATE INDEX idx_documents_updated ON documents(updated_at);
CREATE INDEX idx_chunks_document ON chunks(document_id);
CREATE INDEX idx_entities_type ON entities(type);
CREATE INDEX idx_entities_name ON entities(name);
CREATE INDEX idx_mentions_entity ON mentions(entity_id);
CREATE INDEX idx_mentions_chunk ON mentions(chunk_id);
CREATE INDEX idx_relations_source ON relations(source_entity_id);
CREATE INDEX idx_relations_target ON relations(target_entity_id);
```

## File Structure

```
AgentKit/Sources/AgentKit/Knowledge/
├── KnowledgeStore.swift           # Main actor
├── EmbeddingEngine.swift          # MLX embeddings
├── Storage/
│   ├── KnowledgeDatabase.swift    # SQLite wrapper
│   ├── VectorIndex.swift          # sqlite-vec operations
│   └── Schema.swift               # Database schema
├── Models/
│   ├── Document.swift
│   ├── Chunk.swift
│   ├── Entity.swift
│   ├── Source.swift
│   └── SearchResult.swift
├── Processing/
│   ├── Chunker.swift              # Text chunking strategies
│   ├── EntityExtractor.swift      # NER
│   └── TextProcessor.swift        # Cleaning, normalization
└── Tools/
    └── KnowledgeTools.swift       # MCP tool definitions
```

## Dependencies

- **sqlite-vec**: Vector similarity search extension for SQLite
- **MLX Swift**: For local embedding models
- **Swift NLP** (optional): For entity extraction fallback

## Usage Example

```swift
// Initialize
let knowledge = KnowledgeStore(
    databasePath: "~/.goldeneye/knowledge.db",
    embeddingModel: .bgeSmall
)

// Ingest a document
let doc = Document(
    content: slackMessage.text,
    metadata: DocumentMetadata(
        title: nil,
        author: slackMessage.user,
        timestamp: slackMessage.ts
    ),
    source: SourceReference(
        type: .slack,
        id: "workspace-123",
        ref: "\(channel)/\(ts)"
    )
)
let docId = try await knowledge.ingest(document: doc)

// Search
let results = try await knowledge.search(
    query: "What did we decide about the API design?",
    limit: 10,
    filters: SearchFilters(
        sources: [.slack],
        dateRange: .lastWeek
    )
)

// Get entities
let entities = try await knowledge.extractEntities(from: docId)
```

## Success Criteria

1. Can ingest 10,000 documents in under 5 minutes
2. Vector search returns results in < 100ms
3. Embedding generation at 100+ docs/second (batched)
4. Database size < 2x raw content size
5. Works completely offline with local models
