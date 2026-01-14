import Foundation

#if os(macOS)

// MARK: - Content Sync Service

/// Background service that syncs external content into the memory store.
///
/// Periodically checks for new items from:
/// - Safari Reading List
/// - Shared with You
/// - AirDrop (future)
///
/// ## Usage
/// ```swift
/// let syncService = ContentSyncService(memoryStore: memoryStore)
/// await syncService.startPeriodicSync(interval: 300) // Every 5 minutes
/// ```
public actor ContentSyncService {
    // MARK: - Properties

    private let memoryStore: MemoryStore
    private let safariIntegration: SafariIntegration
    private var sharedWithYouIntegration: SharedWithYouIntegration?
    private var syncTask: Task<Void, Never>?
    private var isRunning = false

    /// Statistics for monitoring
    public private(set) var stats = SyncStatistics()

    // MARK: - Initialization

    public init(memoryStore: MemoryStore) {
        self.memoryStore = memoryStore
        self.safariIntegration = SafariIntegration()

        // Initialize SharedWithYou if available (macOS 13+)
        if #available(macOS 13.0, *) {
            self.sharedWithYouIntegration = SharedWithYouIntegration()
        }
    }

    // MARK: - Periodic Sync

    /// Start periodic background sync
    /// - Parameter interval: Sync interval in seconds (default: 300 = 5 minutes)
    public func startPeriodicSync(interval: TimeInterval = 300) {
        guard !isRunning else { return }

        isRunning = true

        syncTask = Task {
            while isRunning {
                await performSync()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Stop periodic sync
    public func stopPeriodicSync() {
        isRunning = false
        syncTask?.cancel()
        syncTask = nil
    }

    // MARK: - Manual Sync

    /// Perform a one-time sync of all sources
    public func performSync() async {
        stats.lastSyncStarted = Date()

        await withTaskGroup(of: Void.self) { group in
            // Sync Reading List
            group.addTask {
                await self.syncReadingList()
            }

            // Sync Shared with You
            if #available(macOS 13.0, *), sharedWithYouIntegration != nil {
                group.addTask {
                    await self.syncSharedWithYou()
                }
            }
        }

        stats.lastSyncCompleted = Date()
    }

    // MARK: - Reading List Sync

    private func syncReadingList() async {
        do {
            // Get new items since last sync
            let newItems = try await safariIntegration.getNewReadingListItems()

            guard !newItems.isEmpty else { return }

            print("📚 Syncing \(newItems.count) new Reading List items...")

            for item in newItems {
                do {
                    // Fetch content from URL
                    let content = try await safariIntegration.fetchContent(for: item)

                    // Index into memory store
                    try await memoryStore.indexURL(
                        item.url,
                        title: item.title ?? item.url.absoluteString,
                        content: content,
                        source: .readingList
                    )

                    stats.readingListItemsSynced += 1
                } catch {
                    print("⚠️ Failed to sync Reading List item \(item.url): \(error)")
                    stats.errors.append(SyncError(
                        source: .readingList,
                        url: item.url,
                        error: error,
                        timestamp: Date()
                    ))
                }
            }

            print("✅ Reading List sync complete: \(stats.readingListItemsSynced) items")
        } catch {
            print("❌ Reading List sync failed: \(error)")
        }
    }

    // MARK: - Shared with You Sync

    @available(macOS 13.0, *)
    private func syncSharedWithYou() async {
        guard let integration = sharedWithYouIntegration else { return }

        do {
            let newItems = try await integration.getNewSharedItems()

            guard !newItems.isEmpty else { return }

            print("🔗 Syncing \(newItems.count) new Shared with You items...")

            for item in newItems {
                do {
                    // Fetch content from URL
                    let (data, response) = try await URLSession.shared.data(from: item.url)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        continue
                    }

                    // Extract text content
                    let content = String(data: data, encoding: .utf8) ?? ""

                    // Index into memory store
                    try await memoryStore.indexURL(
                        item.url,
                        title: item.title ?? item.url.absoluteString,
                        content: content,
                        source: .sharedWithYou(
                            sourceApp: item.sourceApp,
                            sharedBy: item.sharedBy
                        )
                    )

                    stats.sharedItemsSynced += 1
                } catch {
                    print("⚠️ Failed to sync Shared item \(item.url): \(error)")
                    stats.errors.append(SyncError(
                        source: .sharedWithYou,
                        url: item.url,
                        error: error,
                        timestamp: Date()
                    ))
                }
            }

            print("✅ Shared with You sync complete: \(stats.sharedItemsSynced) items")
        } catch {
            print("❌ Shared with You sync failed: \(error)")
        }
    }

    // MARK: - Statistics

    public struct SyncStatistics: Sendable {
        public var lastSyncStarted: Date?
        public var lastSyncCompleted: Date?
        public var readingListItemsSynced = 0
        public var sharedItemsSynced = 0
        public var errors: [SyncError] = []

        public var isHealthy: Bool {
            errors.filter { $0.timestamp > Date().addingTimeInterval(-3600) }.count < 5
        }
    }

    public struct SyncError: Sendable {
        public enum Source: Sendable {
            case readingList
            case sharedWithYou
        }

        public let source: Source
        public let url: URL
        public let error: Error
        public let timestamp: Date
    }
}

#endif
