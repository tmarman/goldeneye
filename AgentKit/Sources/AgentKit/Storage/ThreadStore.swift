import Foundation

// MARK: - Thread Store

/// Unified persistence layer for threads across all container types.
///
/// ThreadStore provides a container-aware API for thread operations:
/// - Automatically routes threads to correct directories based on container
/// - Supports in-memory caching with file persistence
/// - Handles migration from old Conversation type
///
/// Example:
/// ```swift
/// let store = try ThreadStore()
///
/// // Load threads for a container
/// let spaceThreads = try await store.threads(for: .space("my-space"))
/// let agentDMs = try await store.threads(for: .agent("Claude"))
///
/// // Save a thread
/// var thread = Thread(container: .agent("Claude"), title: "Planning session")
/// try await store.save(thread)
/// ```
public actor ThreadStore {

    // MARK: - Properties

    private let workspace: WorkspaceStore

    /// In-memory cache of loaded threads, keyed by thread ID
    private var cache: [ThreadID: Thread] = [:]

    /// Tracks which containers have been fully loaded
    private var loadedContainers: Set<String> = []

    // MARK: - Initialization

    public init(workspace: WorkspaceStore? = nil) throws {
        self.workspace = workspace ?? WorkspaceStore()
    }

    /// Initialize the store and ensure directory structure exists
    public func initialize() async throws {
        try await workspace.initialize()
    }

    // MARK: - Query Operations

    /// Load all threads for a specific container
    public func threads(for container: ThreadContainer) async throws -> [Thread] {
        let containerKey = cacheKey(for: container)

        // Load from disk if not cached
        if !loadedContainers.contains(containerKey) {
            let loaded = try await loadFromDisk(container: container)
            for thread in loaded {
                cache[thread.id] = thread
            }
            loadedContainers.insert(containerKey)
        }

        // Filter cache by container
        return cache.values
            .filter { $0.container == container }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Load a specific thread by ID
    public func thread(_ id: ThreadID) -> Thread? {
        cache[id]
    }

    /// Load all threads across all containers (for global search)
    public func allThreads() async throws -> [Thread] {
        // Load all container types
        let spaces = try await workspace.listSpaces()
        for space in spaces {
            _ = try await threads(for: .space(space.id))
        }

        let agents = try await workspace.listAgents()
        for agent in agents {
            _ = try await threads(for: .agent(agent.name))
        }

        let groups = try await workspace.listGroups()
        for group in groups {
            _ = try await threads(for: .group(group.id))
        }

        return cache.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Search threads by title or content
    public func search(query: String, in container: ThreadContainer? = nil) async throws -> [Thread] {
        let searchThreads: [Thread]

        if let container = container {
            searchThreads = try await threads(for: container)
        } else {
            searchThreads = try await allThreads()
        }

        let lowercaseQuery = query.lowercased()
        return searchThreads.filter { thread in
            // Search title
            if thread.title.lowercased().contains(lowercaseQuery) {
                return true
            }
            // Search message content
            return thread.messages.contains { message in
                message.textContent.lowercased().contains(lowercaseQuery)
            }
        }
    }

    /// Get starred threads
    public func starredThreads() async throws -> [Thread] {
        let all = try await allThreads()
        return all.filter { $0.isStarred }
    }

    /// Get pinned threads for a container
    public func pinnedThreads(for container: ThreadContainer) async throws -> [Thread] {
        let containerThreads = try await threads(for: container)
        return containerThreads.filter { $0.isPinned }
    }

    // MARK: - CRUD Operations

    /// Save a thread to disk
    public func save(_ thread: Thread) async throws {
        // Update cache
        cache[thread.id] = thread

        // Persist to disk
        try await saveToDisk(thread)
    }

    /// Create a new thread in a container
    public func create(in container: ThreadContainer, title: String = "New Thread") async throws -> Thread {
        let thread = Thread(
            title: title,
            container: container
        )
        try await save(thread)
        return thread
    }

    /// Delete a thread
    public func delete(_ id: ThreadID) async throws {
        guard let thread = cache[id] else { return }

        // Remove from cache
        cache.removeValue(forKey: id)

        // Delete from disk
        try await deleteFromDisk(thread)
    }

    /// Update thread properties
    public func update(_ id: ThreadID, _ update: (inout Thread) -> Void) async throws {
        guard var thread = cache[id] else { return }

        update(&thread)
        thread.updatedAt = Date()

        try await save(thread)
    }

    /// Add a message to a thread
    public func addMessage(_ message: ThreadMessage, to threadId: ThreadID) async throws {
        try await update(threadId) { thread in
            thread.addMessage(message)
        }
    }

    // MARK: - Convenience Methods

    /// Get or create the most recent thread for a container
    public func activeThread(for container: ThreadContainer) async throws -> Thread {
        let containerThreads = try await threads(for: container)

        // Return most recent non-archived thread, or create new one
        if let active = containerThreads.first(where: { !$0.isArchived }) {
            return active
        }

        return try await create(in: container)
    }

    /// Archive a thread
    public func archive(_ id: ThreadID) async throws {
        try await update(id) { thread in
            thread.isArchived = true
        }
    }

    /// Toggle star on a thread
    public func toggleStar(_ id: ThreadID) async throws {
        try await update(id) { thread in
            thread.isStarred.toggle()
        }
    }

    /// Toggle pin on a thread
    public func togglePin(_ id: ThreadID) async throws {
        try await update(id) { thread in
            thread.isPinned.toggle()
        }
    }

    // MARK: - Cache Management

    /// Clear all cached data (forces reload on next access)
    public func clearCache() {
        cache.removeAll()
        loadedContainers.removeAll()
    }

    /// Clear cache for a specific container
    public func clearCache(for container: ThreadContainer) {
        let containerKey = cacheKey(for: container)
        loadedContainers.remove(containerKey)

        // Remove threads for this container from cache
        let toRemove = cache.filter { $0.value.container == container }.map(\.key)
        for id in toRemove {
            cache.removeValue(forKey: id)
        }
    }

    // MARK: - Private Helpers

    private func cacheKey(for container: ThreadContainer) -> String {
        switch container {
        case .space(let id): return "space:\(id)"
        case .agent(let name): return "agent:\(name)"
        case .group(let id): return "group:\(id)"
        case .global: return "global"
        }
    }

    private func loadFromDisk(container: ThreadContainer) async throws -> [Thread] {
        switch container {
        case .space(let spaceId):
            return try await workspace.listSpaceThreads(spaceName: spaceId)
        case .agent(let agentName):
            return try await workspace.listAgentThreads(agentName: agentName)
        case .group(let groupId):
            return try await workspace.listGroupThreads(groupId: groupId)
        case .global:
            // Global threads don't have a specific directory
            // They could be stored in a special "global" space or just returned empty
            return []
        }
    }

    private func saveToDisk(_ thread: Thread) async throws {
        switch thread.container {
        case .space(let spaceId):
            try await workspace.saveSpaceThread(thread, spaceName: spaceId)
        case .agent(let agentName):
            try await workspace.saveAgentThread(thread, agentName: agentName)
        case .group(let groupId):
            try await workspace.saveGroupThread(thread, groupId: groupId)
        case .global:
            // Global threads could be stored in a special location
            // For now, we'll create a "Global" space for them
            try await workspace.saveSpaceThread(thread, spaceName: "Global")
        }
    }

    private func deleteFromDisk(_ thread: Thread) async throws {
        // Get the file path based on container
        let path: String
        let rootPath = await workspace.rootPath

        switch thread.container {
        case .space(let spaceId):
            path = "\(rootPath)/Spaces/\(spaceId)/.threads/\(thread.suggestedFilename)"
        case .agent(let agentName):
            path = "\(rootPath)/Agents/\(agentName)/.threads/\(thread.suggestedFilename)"
        case .group(let groupId):
            path = "\(rootPath)/Groups/\(groupId)/.threads/\(thread.suggestedFilename)"
        case .global:
            path = "\(rootPath)/Spaces/Global/.threads/\(thread.suggestedFilename)"
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
    }
}

// MARK: - Thread Statistics

extension ThreadStore {

    /// Get statistics for a container
    public func statistics(for container: ThreadContainer) async throws -> ThreadStatistics {
        let containerThreads = try await threads(for: container)

        let totalMessages = containerThreads.reduce(0) { $0 + $1.messages.count }
        let starred = containerThreads.filter { $0.isStarred }.count
        let archived = containerThreads.filter { $0.isArchived }.count

        return ThreadStatistics(
            totalThreads: containerThreads.count,
            totalMessages: totalMessages,
            starredCount: starred,
            archivedCount: archived,
            lastActivity: containerThreads.first?.updatedAt
        )
    }
}

/// Statistics for a thread container
public struct ThreadStatistics: Sendable {
    public let totalThreads: Int
    public let totalMessages: Int
    public let starredCount: Int
    public let archivedCount: Int
    public let lastActivity: Date?
}
