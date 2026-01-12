import Foundation

// MARK: - Workspace

/// A workspace is the shared context container across all Goldeneye pillars.
///
/// Documents, conversations, and coaching sessions all exist within a workspace,
/// enabling agents to have full context across different interaction modes.
public actor Workspace: Identifiable {
    public let id: WorkspaceID
    public let name: String
    public let createdAt: Date

    private var _documents: [DocumentID: Document] = [:]
    private var _conversations: [ConversationID: Conversation] = [:]
    private var _coachingSessions: [CoachingSessionID: CoachingSession] = [:]
    private var _folders: [FolderID: Folder] = [:]
    private var _tags: [TagID: Tag] = [:]

    public init(id: WorkspaceID = WorkspaceID(), name: String) {
        self.id = id
        self.name = name
        self.createdAt = Date()
    }

    // MARK: - Documents

    public var documents: [Document] {
        Array(_documents.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func document(id: DocumentID) -> Document? {
        _documents[id]
    }

    public func addDocument(_ document: Document) {
        _documents[document.id] = document
    }

    public func updateDocument(_ document: Document) {
        _documents[document.id] = document
    }

    public func deleteDocument(id: DocumentID) {
        _documents.removeValue(forKey: id)
    }

    // MARK: - Conversations

    public var conversations: [Conversation] {
        Array(_conversations.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func conversation(id: ConversationID) -> Conversation? {
        _conversations[id]
    }

    public func addConversation(_ conversation: Conversation) {
        _conversations[conversation.id] = conversation
    }

    public func updateConversation(_ conversation: Conversation) {
        _conversations[conversation.id] = conversation
    }

    // MARK: - Coaching Sessions

    public var coachingSessions: [CoachingSession] {
        Array(_coachingSessions.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func coachingSession(id: CoachingSessionID) -> CoachingSession? {
        _coachingSessions[id]
    }

    public func addCoachingSession(_ session: CoachingSession) {
        _coachingSessions[session.id] = session
    }

    public func updateCoachingSession(_ session: CoachingSession) {
        _coachingSessions[session.id] = session
    }

    // MARK: - Folders

    public var folders: [Folder] {
        Array(_folders.values).sorted { $0.name < $1.name }
    }

    public func addFolder(_ folder: Folder) {
        _folders[folder.id] = folder
    }

    // MARK: - Tags

    public var tags: [Tag] {
        Array(_tags.values).sorted { $0.name < $1.name }
    }

    public func addTag(_ tag: Tag) {
        _tags[tag.id] = tag
    }

    public func tag(id: TagID) -> Tag? {
        _tags[id]
    }
}

// MARK: - Supporting Types

public struct WorkspaceID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public struct Folder: Identifiable, Codable, Sendable {
    public let id: FolderID
    public var name: String
    public var parentId: FolderID?
    public var icon: String?
    public let createdAt: Date

    public init(
        id: FolderID = FolderID(),
        name: String,
        parentId: FolderID? = nil,
        icon: String? = nil
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.icon = icon
        self.createdAt = Date()
    }
}

public struct FolderID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public struct Tag: Identifiable, Codable, Sendable {
    public let id: TagID
    public var name: String
    public var color: TagColor
    public let createdAt: Date

    public init(
        id: TagID = TagID(),
        name: String,
        color: TagColor = .gray
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = Date()
    }
}

public struct TagID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public enum TagColor: String, Codable, Sendable, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink, gray
}
