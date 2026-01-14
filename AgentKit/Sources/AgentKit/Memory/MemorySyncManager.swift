import Foundation

// MARK: - Memory Sync Manager

/// Handles synchronization of memory items between local and master instances.
///
/// ## Sync Architecture
/// ```
/// Local Device          Master Server
/// ┌──────────┐          ┌──────────┐
/// │MemoryDB  │◄────────►│MemoryDB  │
/// │(VecturaKit)│  A2A   │(Postgres+│
/// │          │  Sync   │ pgvector)│
/// └──────────┘          └──────────┘
/// ```
///
/// The sync uses a CRDT-like approach where items are immutable after creation.
/// Conflicts are resolved by keeping all versions (append-only).
actor MemorySyncManager {
    private let config: MemorySyncConfig
    private weak var store: MemoryStore?

    /// Items pending sync (local changes not yet pushed)
    private var pendingPush: Set<MemoryItemID> = []

    /// Last sync timestamp for pull operations
    private var lastPullTimestamp: Date?

    /// Current sync operation
    private var currentOperation: MemorySyncOperation?

    // MARK: - Initialization

    init(config: MemorySyncConfig, store: MemoryStore) {
        self.config = config
        self.store = store

        // Start auto-sync if configured
        if config.autoSync {
            Task {
                await startAutoSync()
            }
        }
    }

    // MARK: - Sync Operations

    /// Perform a full sync (push + pull)
    func sync() async throws {
        guard let masterURL = config.masterServerURL else {
            throw MemoryStoreError.syncNotConfigured
        }

        let operationId = UUID().uuidString

        currentOperation = MemorySyncOperation(
            operationId: operationId,
            timestamp: Date(),
            direction: .merge,
            itemCount: pendingPush.count,
            status: .inProgress
        )

        do {
            // Push local changes
            try await pushChanges(to: masterURL)

            // Pull remote changes
            try await pullChanges(from: masterURL)

            currentOperation?.status = .completed
        } catch {
            currentOperation?.status = .failed
            throw error
        }
    }

    /// Mark an item for sync
    func markForSync(_ itemId: MemoryItemID) {
        pendingPush.insert(itemId)
    }

    // MARK: - Push

    private func pushChanges(to masterURL: URL) async throws {
        guard let store = store else { return }

        let itemsToSync = Array(pendingPush.prefix(config.batchSize))
        guard !itemsToSync.isEmpty else { return }

        let items = await store.getItemsForSync(ids: itemsToSync)

        // Encode items for sync
        let payload = SyncPayload(
            deviceId: getDeviceId(),
            timestamp: Date(),
            items: items
        )

        let data = try JSONEncoder().encode(payload)

        // Send to master
        var request = URLRequest(url: masterURL.appendingPathComponent("/api/memory/sync/push"))
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MemoryStoreError.syncFailed("Push failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        // Clear pushed items from pending
        for id in itemsToSync {
            pendingPush.remove(id)
        }
    }

    // MARK: - Pull

    private func pullChanges(from masterURL: URL) async throws {
        guard let store = store else { return }

        // Request changes since last pull
        var components = URLComponents(url: masterURL.appendingPathComponent("/api/memory/sync/pull"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "deviceId", value: getDeviceId()),
            URLQueryItem(name: "since", value: lastPullTimestamp?.ISO8601Format() ?? "1970-01-01T00:00:00Z")
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MemoryStoreError.syncFailed("Pull failed")
        }

        let payload = try JSONDecoder().decode(SyncPayload.self, from: data)

        // Import received items
        try await store.receiveFromSync(payload.items)

        lastPullTimestamp = payload.timestamp
    }

    // MARK: - Auto Sync

    private func startAutoSync() async {
        while true {
            try? await Task.sleep(for: .seconds(config.syncIntervalSeconds))

            // Check WiFi requirement
            if config.wifiOnly && !isOnWiFi() {
                continue
            }

            try? await sync()
        }
    }

    private func isOnWiFi() -> Bool {
        // Simplified check - in production would use Network framework
        true
    }

    private func getDeviceId() -> String {
        // Use a stable device identifier
        if let existing = UserDefaults.standard.string(forKey: "goldeneye.memory.deviceId") {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "goldeneye.memory.deviceId")
        return newId
    }
}

// MARK: - Sync Payload

private struct SyncPayload: Codable {
    let deviceId: String
    let timestamp: Date
    let items: [MemoryItem]
}
