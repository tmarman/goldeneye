import Foundation

// MARK: - Session Manager

/// Manages CLI sessions across devices with remote viewing and interaction
///
/// The SessionManager acts as both a local session host and a relay for
/// remote access. When running as a server, it exposes sessions via A2A/SSE.
/// When running as a client, it connects to remote servers to view/interact.
public actor SessionManager {
    public static let shared = SessionManager()

    // Local sessions (this machine is the host)
    private var localSessions: [String: CLISession] = [:]

    // Remote session proxies (connected from other machines)
    private var remoteSessions: [String: RemoteSessionProxy] = [:]

    // Session observers (for UI updates)
    private var sessionObservers: [UUID: SessionObserver] = [:]

    // Device identification
    private let deviceId: String
    private let deviceName: String

    public init() {
        // Generate or load persistent device ID
        self.deviceId = Self.getOrCreateDeviceId()
        self.deviceName = Host.current().localizedName ?? "Unknown Mac"
    }

    // MARK: - Local Session Management

    /// Create and start a new local CLI session
    public func createSession(
        taskId: String,
        cli: CLIType,
        prompt: String,
        workingDirectory: URL,
        environment: [String: String] = [:]
    ) async throws -> CLISession {
        let session = CLISession(
            taskId: taskId,
            cli: cli
        )

        try await session.start(
            prompt: prompt,
            workingDirectory: workingDirectory,
            environment: environment
        )

        localSessions[session.id] = session

        // Notify observers
        let info = await session.getInfo()
        await notifyObservers(.sessionCreated(info))

        return session
    }

    /// Get a local session by ID
    public func getSession(_ id: String) -> CLISession? {
        localSessions[id]
    }

    /// List all local sessions
    public func listLocalSessions() async -> [SessionInfo] {
        var infos: [SessionInfo] = []
        for session in localSessions.values {
            infos.append(await session.getInfo())
        }
        return infos.sorted { $0.createdAt > $1.createdAt }
    }

    /// Terminate a session
    public func terminateSession(_ id: String) async {
        guard let session = localSessions[id] else { return }
        await session.terminate()
        await notifyObservers(.sessionTerminated(id))
    }

    /// Remove a completed/terminated session
    public func removeSession(_ id: String) {
        localSessions.removeValue(forKey: id)
    }

    /// Clean up old sessions
    public func cleanupOldSessions(olderThan interval: TimeInterval) async {
        let cutoff = Date().addingTimeInterval(-interval)
        var toRemove: [String] = []

        for (id, session) in localSessions {
            let info = await session.getInfo()
            if info.createdAt < cutoff &&
               (info.status == .completed || info.status == .failed || info.status == .terminated) {
                toRemove.append(id)
            }
        }

        for id in toRemove {
            localSessions.removeValue(forKey: id)
        }
    }

    // MARK: - Remote Session Access

    /// Connect to a remote session server
    public func connectToRemote(
        host: String,
        port: Int = 8080
    ) async throws -> RemoteConnection {
        let connection = RemoteConnection(
            host: host,
            port: port,
            deviceId: deviceId
        )

        try await connection.connect()
        return connection
    }

    /// Register a remote session proxy
    public func registerRemoteSession(_ proxy: RemoteSessionProxy) {
        remoteSessions[proxy.id] = proxy
    }

    /// List all sessions (local + remote)
    public func listAllSessions() async -> [DeviceSession] {
        var sessions: [DeviceSession] = []

        // Local sessions
        for session in localSessions.values {
            let info = await session.getInfo()
            sessions.append(DeviceSession(
                info: info,
                deviceId: deviceId,
                deviceName: deviceName,
                isLocal: true
            ))
        }

        // Remote sessions
        for proxy in remoteSessions.values {
            let info = await proxy.getInfo()
            sessions.append(DeviceSession(
                info: info,
                deviceId: proxy.remoteDeviceId,
                deviceName: proxy.remoteDeviceName,
                isLocal: false
            ))
        }

        return sessions.sorted { $0.info.createdAt > $1.info.createdAt }
    }

    // MARK: - Session Observation

    /// Subscribe to session events
    public func observeSessions() -> AsyncStream<SessionEvent> {
        let id = UUID()

        return AsyncStream { continuation in
            let observer = SessionObserver(continuation: continuation)
            sessionObservers[id] = observer

            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeObserver(id)
                }
            }
        }
    }

    private func removeObserver(_ id: UUID) {
        sessionObservers.removeValue(forKey: id)
    }

    private func notifyObservers(_ event: SessionEvent) {
        for observer in sessionObservers.values {
            observer.continuation.yield(event)
        }
    }

    // MARK: - Device ID

    private static func getOrCreateDeviceId() -> String {
        let key = "com.goldeneye.deviceId"

        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }

        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    /// Get this device's info
    public func getDeviceInfo() -> DeviceInfo {
        DeviceInfo(
            id: deviceId,
            name: deviceName,
            platform: "macOS",
            version: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
}

// MARK: - Supporting Types

public struct DeviceSession: Identifiable, Sendable {
    public var id: String { info.id }
    public let info: SessionInfo
    public let deviceId: String
    public let deviceName: String
    public let isLocal: Bool

    public init(
        info: SessionInfo,
        deviceId: String,
        deviceName: String,
        isLocal: Bool
    ) {
        self.info = info
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.isLocal = isLocal
    }
}

public struct DeviceInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let platform: String
    public let version: String
}

public enum SessionEvent: Sendable {
    case sessionCreated(SessionInfo)
    case sessionUpdated(SessionInfo)
    case sessionTerminated(String)
    case remoteConnected(DeviceInfo)
    case remoteDisconnected(String)
}

private struct SessionObserver {
    let continuation: AsyncStream<SessionEvent>.Continuation
}

// MARK: - Remote Connection

/// Connection to a remote session server
public actor RemoteConnection {
    private let host: String
    private let port: Int
    private let deviceId: String
    private var isConnected = false
    private var sessionProxies: [String: RemoteSessionProxy] = [:]

    public init(host: String, port: Int, deviceId: String) {
        self.host = host
        self.port = port
        self.deviceId = deviceId
    }

    public func connect() async throws {
        // TODO: Implement WebSocket/SSE connection to remote server
        // This would connect to the A2A server running on the remote machine
        isConnected = true
    }

    public func disconnect() async {
        isConnected = false
        for proxy in sessionProxies.values {
            await proxy.disconnect()
        }
        sessionProxies.removeAll()
    }

    public func listRemoteSessions() async throws -> [SessionInfo] {
        // TODO: Fetch session list from remote server
        return []
    }

    public func attachToSession(_ sessionId: String) async throws -> RemoteSessionProxy {
        let proxy = RemoteSessionProxy(
            sessionId: sessionId,
            host: host,
            port: port,
            remoteDeviceId: "",  // Would come from server
            remoteDeviceName: host
        )
        sessionProxies[sessionId] = proxy
        return proxy
    }
}

// MARK: - Remote Session Proxy

/// Proxy for interacting with a remote session
public actor RemoteSessionProxy: Identifiable {
    public nonisolated let id: String
    public nonisolated let remoteDeviceId: String
    public nonisolated let remoteDeviceName: String

    private let host: String
    private let port: Int
    private var isConnected = false

    public init(
        sessionId: String,
        host: String,
        port: Int,
        remoteDeviceId: String,
        remoteDeviceName: String
    ) {
        self.id = sessionId
        self.host = host
        self.port = port
        self.remoteDeviceId = remoteDeviceId
        self.remoteDeviceName = remoteDeviceName
    }

    public func connect() async throws {
        // TODO: Establish SSE/WebSocket connection for output streaming
        isConnected = true
    }

    public func disconnect() async {
        isConnected = false
    }

    /// Send input to remote session
    public func sendInput(_ text: String) async throws {
        // TODO: Send via HTTP POST or WebSocket
    }

    /// Send control character to remote session
    public func sendControl(_ char: ControlCharacter) async throws {
        // TODO: Send via HTTP POST or WebSocket
    }

    /// Stream output from remote session
    public func outputStream() -> AsyncStream<SessionOutput> {
        // TODO: Return SSE/WebSocket stream
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func getInfo() -> SessionInfo {
        // TODO: Fetch from remote
        SessionInfo(
            id: id,
            taskId: "",
            cli: .claudeCode,
            status: .running,
            createdAt: Date(),
            outputSize: 0,
            exitCode: nil
        )
    }
}
