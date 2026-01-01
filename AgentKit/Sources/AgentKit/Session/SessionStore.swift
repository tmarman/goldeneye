import Foundation
import Logging

// MARK: - Session Store

/// Manages session persistence and lifecycle
public actor SessionStore {
    private let baseDirectory: URL
    private var sessions: [SessionID: Session] = [:]
    private let logger = Logger(label: "AgentKit.SessionStore")

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    // MARK: - Session Lifecycle

    /// Create a new session
    public func create(name: String? = nil) async throws -> Session {
        let id = SessionID(name ?? UUID().uuidString)
        let workDir = baseDirectory.appendingPathComponent("sessions").appendingPathComponent(id.rawValue)
        let gitRepo = workDir.appendingPathComponent(".git")

        // Create directory
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        // Initialize git repo
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = workDir
        try process.run()
        process.waitUntilExit()

        let session = Session(id: id, workingDirectory: workDir, gitRepo: gitRepo)
        sessions[id] = session

        // Save initial state
        try await save(session)

        logger.info("Created session", metadata: ["id": "\(id.rawValue)"])
        return session
    }

    /// Get an existing session
    public func get(_ id: SessionID) async -> Session? {
        if let session = sessions[id] {
            return session
        }

        // Try to load from disk
        if let session = try? await load(id) {
            sessions[id] = session
            return session
        }

        return nil
    }

    /// List all sessions
    public func list() async throws -> [SessionID] {
        let sessionsDir = baseDirectory.appendingPathComponent("sessions")

        guard FileManager.default.fileExists(atPath: sessionsDir.path) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        return contents.compactMap { url -> SessionID? in
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return SessionID(url.lastPathComponent)
            }
            return nil
        }
    }

    /// Delete a session
    public func delete(_ id: SessionID) async throws {
        sessions.removeValue(forKey: id)

        let sessionDir = baseDirectory.appendingPathComponent("sessions").appendingPathComponent(id.rawValue)
        if FileManager.default.fileExists(atPath: sessionDir.path) {
            try FileManager.default.removeItem(at: sessionDir)
        }

        logger.info("Deleted session", metadata: ["id": "\(id.rawValue)"])
    }

    // MARK: - Persistence

    private func save(_ session: Session) async throws {
        let data = try await session.toData()
        let stateFile = baseDirectory
            .appendingPathComponent("sessions")
            .appendingPathComponent(await session.id.rawValue)
            .appendingPathComponent("session.json")

        try data.write(to: stateFile)
    }

    private func load(_ id: SessionID) async throws -> Session {
        let stateFile = baseDirectory
            .appendingPathComponent("sessions")
            .appendingPathComponent(id.rawValue)
            .appendingPathComponent("session.json")

        let data = try Data(contentsOf: stateFile)
        return try Session.fromData(data)
    }

    /// Save all sessions (e.g., on shutdown)
    public func saveAll() async {
        for session in sessions.values {
            do {
                try await save(session)
            } catch {
                let sessionId = await session.id.rawValue
                logger.error("Failed to save session", metadata: [
                    "id": "\(sessionId)",
                    "error": "\(error)",
                ])
            }
        }
    }
}
