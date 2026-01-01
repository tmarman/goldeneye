import Foundation

// MARK: - Session

/// Represents an agent session with working directory and git repo
public actor Session {
    public let id: SessionID
    public let workingDirectory: URL
    public let gitRepo: URL?
    public private(set) var createdAt: Date
    public private(set) var lastActivity: Date

    private var metadata: [String: AnyCodable] = [:]

    public init(
        id: SessionID = SessionID(),
        workingDirectory: URL,
        gitRepo: URL? = nil
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.gitRepo = gitRepo
        self.createdAt = .now
        self.lastActivity = .now
    }

    // MARK: - Metadata

    public func setMetadata(_ key: String, value: Any) {
        metadata[key] = AnyCodable(value)
        lastActivity = .now
    }

    public func getMetadata(_ key: String) -> Any? {
        metadata[key]?.value
    }

    // MARK: - Git Integration

    /// Commit changes with message
    public func commit(message: String) async throws {
        guard gitRepo != nil else { return }

        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "-A"]
        addProcess.currentDirectoryURL = workingDirectory
        try addProcess.run()
        addProcess.waitUntilExit()

        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["commit", "-m", message, "--allow-empty"]
        commitProcess.currentDirectoryURL = workingDirectory
        try commitProcess.run()
        commitProcess.waitUntilExit()

        lastActivity = .now
    }

    /// Create a checkpoint commit after tool execution
    public func checkpoint(_ description: String) async throws {
        try await commit(message: description)
    }

    // MARK: - Serialization

    public func toData() throws -> Data {
        let state = SessionState(
            id: id,
            workingDirectory: workingDirectory,
            gitRepo: gitRepo,
            createdAt: createdAt,
            lastActivity: lastActivity,
            metadata: metadata
        )
        return try JSONEncoder().encode(state)
    }

    public static func fromData(_ data: Data) throws -> Session {
        let state = try JSONDecoder().decode(SessionState.self, from: data)
        let session = Session(
            id: state.id,
            workingDirectory: state.workingDirectory,
            gitRepo: state.gitRepo
        )
        // Restore timestamps
        Task {
            await session.restore(
                createdAt: state.createdAt,
                lastActivity: state.lastActivity,
                metadata: state.metadata
            )
        }
        return session
    }

    private func restore(
        createdAt: Date,
        lastActivity: Date,
        metadata: [String: AnyCodable]
    ) {
        self.createdAt = createdAt
        self.lastActivity = lastActivity
        self.metadata = metadata
    }
}

// MARK: - Session ID

public struct SessionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID().uuidString
    }

    public var description: String { rawValue }
}

// MARK: - Session State (for serialization)

struct SessionState: Codable {
    let id: SessionID
    let workingDirectory: URL
    let gitRepo: URL?
    let createdAt: Date
    let lastActivity: Date
    let metadata: [String: AnyCodable]
}
