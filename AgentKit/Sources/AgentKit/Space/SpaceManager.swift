import Foundation

// MARK: - Space Manager

/// Central coordinator for all Spaces in the system.
///
/// SpaceManager is responsible for:
/// - Managing the OpenSpace (default timeline/capture area)
/// - Creating and tracking named Spaces (Git-backed containers)
/// - Coordinating with GitServer to expose repos
/// - Handling space discovery and lifecycle
public actor SpaceManager {
    // MARK: - Properties

    /// The user's Open Space (personal timeline)
    public nonisolated let openSpace: OpenSpace

    /// All named Spaces
    private var _spaces: [SpaceID: Space] = [:]

    /// Base path for all Space repos
    public let reposPath: URL

    /// Recently accessed spaces for quick navigation
    private var _recentSpaceIds: [SpaceID] = []
    private let maxRecentSpaces = 10

    // MARK: - Initialization

    public init(reposPath: URL? = nil) {
        self.reposPath = reposPath ?? SpaceManager.defaultReposPath
        self.openSpace = OpenSpace()
    }

    private static var defaultReposPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Goldeneye/repos", isDirectory: true)
    }

    // MARK: - Default Personal Space

    /// Well-known ID for the user's personal documents space
    private static let personalSpaceID = SpaceID("personal")

    /// Get or create the user's personal documents space
    public func personalSpace() async throws -> Space {
        // Return existing personal space if found
        if let space = _spaces[Self.personalSpaceID] {
            return space
        }

        // Create the personal space
        let localPath = reposPath.appendingPathComponent(Self.personalSpaceID.rawValue, isDirectory: true)

        // Create directory if needed
        if !FileManager.default.fileExists(atPath: localPath.path) {
            try FileManager.default.createDirectory(at: localPath, withIntermediateDirectories: true)
            try await initializeGitRepo(at: localPath, name: "Personal", description: "Your personal documents")
        }

        let space = Space(
            id: Self.personalSpaceID,
            name: "Personal",
            description: "Your personal documents",
            localPath: localPath,
            owner: .user,
            icon: "person.crop.square",
            color: .blue
        )

        _spaces[Self.personalSpaceID] = space
        return space
    }

    // MARK: - Space Access

    public var spaces: [Space] {
        get async {
            var result: [Space] = []
            for space in _spaces.values {
                result.append(space)
            }
            return result.sorted { a, b in
                // Sort by recent access, then by name
                let aIndex = _recentSpaceIds.firstIndex(where: { $0 == a.id })
                let bIndex = _recentSpaceIds.firstIndex(where: { $0 == b.id })

                if let ai = aIndex, let bi = bIndex {
                    return ai < bi
                } else if aIndex != nil {
                    return true
                } else if bIndex != nil {
                    return false
                }
                return a.name < b.name
            }
        }
    }

    public func space(id: SpaceID) -> Space? {
        _spaces[id]
    }

    public func space(named name: String) async -> Space? {
        for space in _spaces.values {
            if space.name == name {
                return space
            }
        }
        return nil
    }

    // MARK: - Space Creation

    /// Create a new Space with Git backing
    public func createSpace(
        name: String,
        description: String? = nil,
        owner: SpaceOwner,
        icon: String = "folder",
        color: SpaceColor = .blue
    ) async throws -> Space {
        let spaceId = SpaceID()
        let localPath = reposPath.appendingPathComponent(spaceId.rawValue, isDirectory: true)

        // Create directory
        try FileManager.default.createDirectory(at: localPath, withIntermediateDirectories: true)

        // Initialize Git repo
        try await initializeGitRepo(at: localPath, name: name, description: description)

        // Create Space instance
        let space = Space(
            id: spaceId,
            name: name,
            description: description,
            localPath: localPath,
            owner: owner,
            icon: icon,
            color: color
        )

        _spaces[spaceId] = space
        markRecentAccess(spaceId)

        return space
    }

    /// Clone an existing Space from a remote URL
    public func cloneSpace(from remoteURL: URL, owner: SpaceOwner) async throws -> Space {
        let spaceId = SpaceID()
        let localPath = reposPath.appendingPathComponent(spaceId.rawValue, isDirectory: true)

        // Clone the repo
        try await cloneGitRepo(from: remoteURL, to: localPath)

        // Read space metadata from .goldeneye/space.yaml if it exists
        let metadata = try await readSpaceMetadata(at: localPath)

        let space = Space(
            id: spaceId,
            name: metadata?.name ?? remoteURL.lastPathComponent,
            description: metadata?.description,
            localPath: localPath,
            owner: owner,
            remoteURL: remoteURL
        )

        _spaces[spaceId] = space
        markRecentAccess(spaceId)

        return space
    }

    // MARK: - Space Lifecycle

    public func deleteSpace(_ id: SpaceID) async throws {
        guard let space = _spaces[id] else { return }

        // Remove from disk
        let path = await space.getLocalPath()
        try FileManager.default.removeItem(at: path)

        // Remove from memory
        _spaces.removeValue(forKey: id)
        _recentSpaceIds.removeAll { $0 == id }
    }

    public func archiveSpace(_ id: SpaceID) async throws {
        guard let space = _spaces[id] else { return }

        // Move to archive directory
        let archivePath = reposPath
            .deletingLastPathComponent()
            .appendingPathComponent("archived", isDirectory: true)
            .appendingPathComponent(id.rawValue, isDirectory: true)

        try FileManager.default.createDirectory(
            at: archivePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let currentPath = await space.getLocalPath()
        try FileManager.default.moveItem(at: currentPath, to: archivePath)

        // Update space reference
        await space.archive(to: archivePath)

        _recentSpaceIds.removeAll { $0 == id }
    }

    // MARK: - Recent Access Tracking

    private func markRecentAccess(_ id: SpaceID) {
        _recentSpaceIds.removeAll { $0 == id }
        _recentSpaceIds.insert(id, at: 0)
        if _recentSpaceIds.count > maxRecentSpaces {
            _recentSpaceIds.removeLast()
        }
    }

    public func touchSpace(_ id: SpaceID) {
        markRecentAccess(id)
    }

    public var recentSpaces: [Space] {
        _recentSpaceIds.compactMap { _spaces[$0] }
    }

    // MARK: - Starred Spaces

    public var starredSpaces: [Space] {
        get async {
            var result: [Space] = []
            for space in _spaces.values {
                if await space.isStarred {
                    result.append(space)
                }
            }
            return result.sorted { $0.name < $1.name }
        }
    }

    // MARK: - Space Discovery

    /// Scan repos directory and load existing Spaces
    public func discoverSpaces() async throws {
        guard FileManager.default.fileExists(atPath: reposPath.path) else { return }

        let contents = try FileManager.default.contentsOfDirectory(
            at: reposPath,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for url in contents {
            guard url.hasDirectoryPath else { continue }

            // Check if it's a Git repo
            let gitDir = url.appendingPathComponent(".git")
            guard FileManager.default.fileExists(atPath: gitDir.path) else { continue }

            // Try to load space metadata
            let metadata = try? await readSpaceMetadata(at: url)

            let spaceId = SpaceID(url.lastPathComponent)
            let space = Space(
                id: spaceId,
                name: metadata?.name ?? url.lastPathComponent,
                description: metadata?.description,
                localPath: url,
                owner: .user  // Default to user ownership for discovered spaces
            )

            _spaces[spaceId] = space
        }
    }

    // MARK: - Git Operations

    private func initializeGitRepo(at path: URL, name: String, description: String?) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", "--initial-branch=main", path.path]
        process.currentDirectoryURL = path.deletingLastPathComponent()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SpaceManagerError.gitInitFailed
        }

        // Create .goldeneye/space.yaml with metadata
        let goldeneyeDir = path.appendingPathComponent(".goldeneye", isDirectory: true)
        try FileManager.default.createDirectory(at: goldeneyeDir, withIntermediateDirectories: true)

        let metadata = SpaceMetadata(name: name, description: description)
        let yamlContent = metadata.toYAML()
        try yamlContent.write(to: goldeneyeDir.appendingPathComponent("space.yaml"), atomically: true, encoding: .utf8)

        // Create initial commit
        try await gitAdd(at: path, files: [".goldeneye"])
        try await gitCommit(at: path, message: "Initialize space: \(name)")
    }

    private func cloneGitRepo(from remote: URL, to local: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", remote.absoluteString, local.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SpaceManagerError.gitCloneFailed(remote)
        }
    }

    private func gitAdd(at path: URL, files: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["add"] + files
        process.currentDirectoryURL = path

        try process.run()
        process.waitUntilExit()
    }

    private func gitCommit(at path: URL, message: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["commit", "-m", message]
        process.currentDirectoryURL = path

        // Set author for commits if not configured
        process.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_AUTHOR_NAME": "Goldeneye",
            "GIT_AUTHOR_EMAIL": "agent@goldeneye.local",
            "GIT_COMMITTER_NAME": "Goldeneye",
            "GIT_COMMITTER_EMAIL": "agent@goldeneye.local",
        ], uniquingKeysWith: { _, new in new })

        try process.run()
        process.waitUntilExit()
    }

    private func readSpaceMetadata(at path: URL) async throws -> SpaceMetadata? {
        let metadataPath = path.appendingPathComponent(".goldeneye/space.yaml")

        guard FileManager.default.fileExists(atPath: metadataPath.path) else {
            return nil
        }

        let content = try String(contentsOf: metadataPath, encoding: .utf8)
        return SpaceMetadata.from(yaml: content)
    }
}

// MARK: - Space Metadata

/// Metadata stored in .goldeneye/space.yaml
struct SpaceMetadata {
    var name: String
    var description: String?
    var version: String = "1.0"

    func toYAML() -> String {
        var lines = [
            "name: \(name)",
            "version: \(version)",
        ]
        if let desc = description {
            lines.append("description: \(desc)")
        }
        return lines.joined(separator: "\n")
    }

    static func from(yaml: String) -> SpaceMetadata? {
        var name: String?
        var description: String?

        for line in yaml.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "name":
                name = value
            case "description":
                description = value
            default:
                break
            }
        }

        guard let name = name else { return nil }
        return SpaceMetadata(name: name, description: description)
    }
}

// MARK: - Errors

public enum SpaceManagerError: Error, LocalizedError {
    case gitInitFailed
    case gitCloneFailed(URL)
    case spaceNotFound(SpaceID)
    case invalidSpacePath

    public var errorDescription: String? {
        switch self {
        case .gitInitFailed:
            return "Failed to initialize Git repository"
        case .gitCloneFailed(let url):
            return "Failed to clone repository from \(url)"
        case .spaceNotFound(let id):
            return "Space not found: \(id)"
        case .invalidSpacePath:
            return "Invalid space path"
        }
    }
}
