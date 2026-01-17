//
//  KnowledgeSpaceManager.swift
//  AgentKit
//
//  Manages multiple isolated knowledge bases (spaces).
//  Each space has its own database, embeddings, and vector index.
//

import Foundation

// MARK: - Knowledge Space

/// A named, isolated knowledge base
public struct KnowledgeSpace: Sendable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let description: String?
    public let icon: String
    public let isDefault: Bool
    public let createdAt: Date
    public var lastAccessedAt: Date

    /// Access level for this space
    public let access: KSpaceAccess

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        icon: String = "brain.head.profile",
        isDefault: Bool = false,
        access: KSpaceAccess = .private,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.isDefault = isDefault
        self.access = access
        self.createdAt = createdAt
        self.lastAccessedAt = createdAt
    }

    /// Database path for this space
    public var databasePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let safeId = id.replacingOccurrences(of: "/", with: "_")
        return "\(home)/.goldeneye/spaces/\(safeId)/knowledge.db"
    }
}

/// Access level for knowledge spaces
public enum KSpaceAccess: String, Sendable, Codable {
    case `private`      // Only accessible to owner
    case shared         // Accessible to specific agents/users
    case team           // Accessible to all team members
    case `public`       // World-readable (for sharing)
}

// MARK: - Knowledge Space Manager

/// Manages multiple knowledge spaces with lazy initialization
public actor KnowledgeSpaceManager {
    /// Registry of all spaces (loaded from disk)
    private var spaces: [String: KnowledgeSpace] = [:]

    /// Active knowledge stores (lazily initialized)
    private var stores: [String: KnowledgeStore] = [:]

    /// Currently active space ID
    private var activeSpaceId: String?

    /// Path to spaces registry
    private let registryPath: String

    /// Embedding model to use for new stores
    private let embeddingModel: KEmbeddingModel

    public init(
        registryPath: String? = nil,
        embeddingModel: KEmbeddingModel = .bgeSmallEn
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.registryPath = registryPath ?? "\(home)/.goldeneye/spaces/registry.json"
        self.embeddingModel = embeddingModel
    }

    // MARK: - Initialization

    /// Initialize the manager and load existing spaces
    public func initialize() async throws {
        try await loadRegistry()

        // Create default space if none exist
        if spaces.isEmpty {
            let defaultSpace = KnowledgeSpace(
                id: "default",
                name: "Personal Knowledge",
                description: "Your personal knowledge base",
                icon: "brain.head.profile",
                isDefault: true
            )
            try await registerSpace(defaultSpace)
            activeSpaceId = defaultSpace.id
        } else if activeSpaceId == nil {
            // Set active to default or first space
            activeSpaceId = spaces.values.first(where: { $0.isDefault })?.id
                ?? spaces.keys.first
        }

        print("🧠 KnowledgeSpaceManager: Loaded \(spaces.count) spaces")
    }

    // MARK: - Space Management

    /// Create a new knowledge space
    public func createSpace(
        name: String,
        description: String? = nil,
        icon: String = "folder",
        access: KSpaceAccess = .private
    ) async throws -> KnowledgeSpace {
        let space = KnowledgeSpace(
            name: name,
            description: description,
            icon: icon,
            isDefault: false,
            access: access
        )
        try await registerSpace(space)
        return space
    }

    /// Register an existing space
    private func registerSpace(_ space: KnowledgeSpace) async throws {
        spaces[space.id] = space
        try await saveRegistry()
    }

    /// Delete a space and its data
    public func deleteSpace(_ spaceId: String) async throws {
        guard spaceId != "default" else {
            throw KSpaceError.cannotDeleteDefault
        }

        // Shutdown store if active
        if let store = stores[spaceId] {
            await store.shutdown()
            stores.removeValue(forKey: spaceId)
        }

        guard let space = spaces.removeValue(forKey: spaceId) else {
            throw KSpaceError.spaceNotFound(spaceId)
        }

        // Delete database file
        let dbPath = space.databasePath
        let directory = (dbPath as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: directory)

        // Update active space if needed
        if activeSpaceId == spaceId {
            activeSpaceId = spaces.values.first(where: { $0.isDefault })?.id
                ?? spaces.keys.first
        }

        try await saveRegistry()
    }

    /// Get all registered spaces
    public func listSpaces() -> [KnowledgeSpace] {
        Array(spaces.values).sorted { $0.name < $1.name }
    }

    /// Get a specific space
    public func getSpace(_ spaceId: String) -> KnowledgeSpace? {
        spaces[spaceId]
    }

    // MARK: - Active Space

    /// Switch to a different space
    public func switchSpace(_ spaceId: String) async throws {
        guard spaces[spaceId] != nil else {
            throw KSpaceError.spaceNotFound(spaceId)
        }
        activeSpaceId = spaceId

        // Update last accessed time
        spaces[spaceId]?.lastAccessedAt = Date()
        try await saveRegistry()
    }

    /// Get the currently active space
    public func activeSpace() -> KnowledgeSpace? {
        guard let id = activeSpaceId else { return nil }
        return spaces[id]
    }

    /// Get the store for the active space
    public func activeStore() async throws -> KnowledgeStore {
        guard let spaceId = activeSpaceId else {
            throw KSpaceError.noActiveSpace
        }
        return try await getStore(for: spaceId)
    }

    // MARK: - Store Access

    /// Get the knowledge store for a specific space (lazily initialized)
    public func getStore(for spaceId: String) async throws -> KnowledgeStore {
        // Return cached store
        if let store = stores[spaceId] {
            return store
        }

        // Get space info
        guard let space = spaces[spaceId] else {
            throw KSpaceError.spaceNotFound(spaceId)
        }

        // Create and initialize store
        let store = KnowledgeStore(
            databasePath: space.databasePath,
            embeddingModel: embeddingModel
        )
        try await store.initialize()

        stores[spaceId] = store
        return store
    }

    // MARK: - Cross-Space Search

    /// Search across all accessible spaces
    public func searchAllSpaces(
        query: String,
        limit: Int = 10,
        spaceIds: [String]? = nil
    ) async throws -> [KSpaceSearchResult] {
        let targetSpaces = spaceIds ?? Array(spaces.keys)
        var allResults: [KSpaceSearchResult] = []

        for spaceId in targetSpaces {
            guard let space = spaces[spaceId] else { continue }

            do {
                let store = try await getStore(for: spaceId)
                let results = try await store.search(query: query, limit: limit)

                for result in results {
                    allResults.append(KSpaceSearchResult(
                        space: space,
                        result: result
                    ))
                }
            } catch {
                // Log but continue with other spaces
                print("⚠️ Search failed for space \(spaceId): \(error)")
            }
        }

        // Sort by score across all spaces
        allResults.sort { $0.result.score > $1.result.score }

        return Array(allResults.prefix(limit))
    }

    // MARK: - Persistence

    private func loadRegistry() async throws {
        let url = URL(fileURLWithPath: registryPath)

        guard FileManager.default.fileExists(atPath: registryPath) else {
            return // No existing registry
        }

        let data = try Data(contentsOf: url)
        let registry = try JSONDecoder().decode(KSpaceRegistry.self, from: data)

        spaces = Dictionary(uniqueKeysWithValues: registry.spaces.map { ($0.id, $0) })
        activeSpaceId = registry.activeSpaceId
    }

    private func saveRegistry() async throws {
        let url = URL(fileURLWithPath: registryPath)

        // Ensure directory exists
        let directory = (registryPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        let registry = KSpaceRegistry(
            spaces: Array(spaces.values),
            activeSpaceId: activeSpaceId
        )

        let data = try JSONEncoder().encode(registry)
        try data.write(to: url)
    }

    /// Shutdown all stores
    public func shutdown() async {
        for store in stores.values {
            await store.shutdown()
        }
        stores.removeAll()
    }
}

// MARK: - Supporting Types

/// Cross-space search result
public struct KSpaceSearchResult: Sendable {
    public let space: KnowledgeSpace
    public let result: KSearchResult
}

/// Registry file format
private struct KSpaceRegistry: Codable {
    let spaces: [KnowledgeSpace]
    let activeSpaceId: String?
}

// MARK: - Errors

public enum KSpaceError: Error, LocalizedError {
    case spaceNotFound(String)
    case noActiveSpace
    case cannotDeleteDefault
    case storeInitializationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .spaceNotFound(let id):
            return "Knowledge space not found: \(id)"
        case .noActiveSpace:
            return "No active knowledge space"
        case .cannotDeleteDefault:
            return "Cannot delete the default knowledge space"
        case .storeInitializationFailed(let msg):
            return "Failed to initialize knowledge store: \(msg)"
        }
    }
}
