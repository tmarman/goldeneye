import Foundation

// MARK: - Thread

/// A thread is a conversation that lives in a container (Space, Agent DM, or Group).
///
/// This is the unified model for all conversations in Envoy:
/// - Space threads: broadcast to all members of a space
/// - Agent DMs: private 1:1 conversations with an agent
/// - Group DMs: private multi-party conversations
///
/// Threads are stored as markdown files with YAML frontmatter:
/// ```
/// ~/.envoy/
/// ├── Spaces/{name}/.threads/{id}.md
/// ├── Agents/{name}/.threads/{id}.md
/// └── Groups/{hash}/.threads/{id}.md
/// ```
public struct Thread: Identifiable, Codable, Sendable {
    public let id: ThreadID
    public var title: String
    public var messages: [ThreadMessage]
    public var container: ThreadContainer
    public var participants: [String]
    public var isStarred: Bool
    public var isPinned: Bool
    public var isArchived: Bool
    public let createdAt: Date
    public var updatedAt: Date

    /// Context ID for maintaining continuity with agent servers (A2A)
    public var contextId: String?

    /// Model ID for direct model conversations
    public var modelId: String?

    /// Provider ID for direct model conversations
    public var providerId: String?

    public init(
        id: ThreadID = ThreadID(),
        title: String = "New Thread",
        messages: [ThreadMessage] = [],
        container: ThreadContainer,
        participants: [String] = [],
        isStarred: Bool = false,
        isPinned: Bool = false,
        isArchived: Bool = false,
        contextId: String? = nil,
        modelId: String? = nil,
        providerId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.container = container
        self.participants = participants
        self.isStarred = isStarred
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.contextId = contextId
        self.modelId = modelId
        self.providerId = providerId
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Convenience

    /// The last message in the thread
    public var lastMessage: ThreadMessage? {
        messages.last
    }

    /// Preview text for list views
    public var preview: String {
        lastMessage?.textContent.prefix(100).description ?? "No messages yet"
    }

    /// Add a message and update timestamp
    public mutating func addMessage(_ message: ThreadMessage) {
        messages.append(message)
        updatedAt = Date()

        // Track participants
        let sender = message.role == .user ? "user" : (message.agentId ?? "assistant")
        if !participants.contains(sender) {
            participants.append(sender)
        }
    }
}

// MARK: - Thread ID

public struct ThreadID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

// MARK: - Thread Container

/// Where a thread lives - determines visibility and access
public enum ThreadContainer: Codable, Sendable, Hashable {
    /// Thread in a space (broadcast to all space members)
    case space(String)  // Space ID

    /// DM thread with a specific agent
    case agent(String)  // Agent name

    /// Group DM thread
    case group(String)  // Group ID (hashed from participants)

    /// Unscoped thread (appears in Headspace / global view)
    case global

    /// Get space ID if this is a space container
    public var spaceId: String? {
        if case .space(let id) = self { return id }
        return nil
    }

    /// Get agent name if this is an agent container
    public var agentName: String? {
        if case .agent(let name) = self { return name }
        return nil
    }

    /// Get group ID if this is a group container
    public var groupId: String? {
        if case .group(let id) = self { return id }
        return nil
    }
}

// MARK: - Thread Message

/// A message is the fundamental unit of communication in a thread.
///
/// Everything is a message - text, decisions, tool calls, system events.
/// The `content` enum determines what kind of message it is.
public struct ThreadMessage: Identifiable, Codable, Sendable {
    public let id: UUID
    public var sender: MessageSender
    public var content: ThreadContent
    public var attachments: [ThreadAttachment]
    public var metadata: ThreadMessageMetadata?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        sender: MessageSender,
        content: ThreadContent,
        attachments: [ThreadAttachment] = [],
        metadata: ThreadMessageMetadata? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sender = sender
        self.content = content
        self.attachments = attachments
        self.metadata = metadata
        self.timestamp = timestamp
    }

    // MARK: - Convenience initializers

    /// Create a simple text message from the user
    public static func user(_ text: String) -> ThreadMessage {
        ThreadMessage(sender: .user, content: .text(text))
    }

    /// Create a simple text message from an agent
    public static func assistant(_ text: String, agentId: String? = nil, agentName: String? = nil) -> ThreadMessage {
        ThreadMessage(sender: .agent(id: agentId, name: agentName ?? "Assistant"), content: .text(text))
    }

    /// Create a system message
    public static func system(_ text: String) -> ThreadMessage {
        ThreadMessage(sender: .system, content: .text(text))
    }

    // MARK: - Legacy compatibility

    /// Text content for display (works for all content types)
    public var textContent: String {
        switch content {
        case .text(let text):
            return text
        case .decision(let decision):
            return "Decision: \(decision.title)"
        case .toolUse(let tool):
            return "Using tool: \(tool.name)"
        case .toolResult(let result):
            return result.output.prefix(200).description
        case .request(let request):
            return "Request: \(request.title)"
        case .event(let event):
            return "Event: \(event.type)"
        }
    }

    /// Legacy role accessor
    public var role: MessageSenderRole {
        sender.role
    }

    /// Legacy agentName accessor
    public var agentName: String? {
        if case .agent(_, let name) = sender {
            return name
        }
        return nil
    }

    /// Legacy agentId accessor
    public var agentId: String? {
        if case .agent(let id, _) = sender {
            return id
        }
        return nil
    }
}

// MARK: - Message Sender

/// Who sent a message
public enum MessageSender: Codable, Sendable, Hashable {
    case user
    case agent(id: String?, name: String)
    case system

    public var role: MessageSenderRole {
        switch self {
        case .user: return .user
        case .agent: return .assistant
        case .system: return .system
        }
    }

    public var displayName: String {
        switch self {
        case .user: return "You"
        case .agent(_, let name): return name
        case .system: return "System"
        }
    }
}

public enum MessageSenderRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

/// Type alias for backward compatibility
public typealias MessageRole = MessageSenderRole

// MARK: - Message Content

/// The content of a message - everything is a message
public enum ThreadContent: Codable, Sendable {
    /// Plain text message
    case text(String)

    /// A decision card requiring user input
    case decision(DecisionContent)

    /// A tool/function call by the agent
    case toolUse(ToolUseContent)

    /// Result of a tool call
    case toolResult(ToolResultContent)

    /// A request/task
    case request(RequestContent)

    /// A system event (agent joined, status change, etc.)
    case event(EventContent)
}

// MARK: - Content Types

/// A decision card embedded in the conversation
public struct DecisionContent: Codable, Sendable {
    public let id: String
    public var title: String
    public var description: String
    public var options: [DecisionOption]
    public var status: DecisionStatus
    public var selectedOptionId: String?
    public var resolvedAt: Date?

    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String,
        options: [DecisionOption],
        status: DecisionStatus = .pending,
        selectedOptionId: String? = nil,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.options = options
        self.status = status
        self.selectedOptionId = selectedOptionId
        self.resolvedAt = resolvedAt
    }
}

public struct DecisionOption: Codable, Sendable, Identifiable {
    public let id: String
    public var label: String
    public var description: String?

    public init(id: String = UUID().uuidString, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

// Note: DecisionStatus is already defined in Workspace/DecisionCard.swift - reusing that type

/// Tool/function call content
public struct ToolUseContent: Codable, Sendable {
    public let id: String
    public var name: String
    public var input: [String: AnyCodable]

    public init(id: String = UUID().uuidString, name: String, input: [String: AnyCodable] = [:]) {
        self.id = id
        self.name = name
        self.input = input
    }
}

/// Tool result content
public struct ToolResultContent: Codable, Sendable {
    public let toolUseId: String
    public var output: String
    public var isError: Bool

    public init(toolUseId: String, output: String, isError: Bool = false) {
        self.toolUseId = toolUseId
        self.output = output
        self.isError = isError
    }
}

/// A request/task within the conversation
public struct RequestContent: Codable, Sendable {
    public let id: String
    public var title: String
    public var description: String?
    public var status: RequestStatus

    public init(id: String = UUID().uuidString, title: String, description: String? = nil, status: RequestStatus = .pending) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
    }
}

public enum RequestStatus: String, Codable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
}

/// A system event (agent joined, status change, etc.)
public struct EventContent: Codable, Sendable {
    public var type: String
    public var description: String?
    public var data: [String: AnyCodable]?

    public init(type: String, description: String? = nil, data: [String: AnyCodable]? = nil) {
        self.type = type
        self.description = description
        self.data = data
    }
}

// Note: AnyCodable is already defined in Agent/Message.swift - reusing that type

// MARK: - Attachments

public struct ThreadAttachment: Identifiable, Codable, Sendable {
    public let id: UUID
    public var type: ThreadAttachmentType
    public var name: String
    public var reference: String

    public init(
        id: UUID = UUID(),
        type: ThreadAttachmentType,
        name: String,
        reference: String
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.reference = reference
    }
}

public enum ThreadAttachmentType: String, Codable, Sendable {
    case document
    case file
    case image
    case url
}

// MARK: - Message Metadata

public struct ThreadMessageMetadata: Codable, Sendable {
    public var model: String?
    public var provider: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var latencyMs: Int?
    public var toolsUsed: [String]?

    public init(
        model: String? = nil,
        provider: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        latencyMs: Int? = nil,
        toolsUsed: [String]? = nil
    ) {
        self.model = model
        self.provider = provider
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.latencyMs = latencyMs
        self.toolsUsed = toolsUsed
    }

    public var tokens: Int? { outputTokens }
}

// MARK: - File Persistence

extension Thread {

    /// Parse a thread from markdown with YAML frontmatter
    public static func parse(from markdown: String) -> Thread? {
        let document = FrontmatterParser.parse(markdown)

        // Parse ID
        let id = ThreadID(document.string("id") ?? UUID().uuidString)

        // Parse container
        let container: ThreadContainer
        if let spaceId = document.string("spaceId") {
            container = .space(spaceId)
        } else if let agentName = document.string("agentName") {
            container = .agent(agentName)
        } else if let groupId = document.string("groupId") {
            container = .group(groupId)
        } else {
            container = .global
        }

        // Parse dates
        let createdAt = document.date("created") ?? Date()
        let updatedAt = document.date("updated") ?? Date()

        // Parse messages from content
        let messages = parseMessages(from: document.content)

        var thread = Thread(
            id: id,
            title: document.string("title") ?? "Thread",
            messages: messages,
            container: container,
            participants: document.stringArray("participants") ?? [],
            isStarred: document.bool("starred") ?? false,
            isPinned: document.bool("pinned") ?? false,
            isArchived: document.bool("archived") ?? false,
            contextId: document.string("contextId"),
            modelId: document.string("modelId"),
            providerId: document.string("providerId")
        )

        // Manually set dates since init sets them to now
        thread = Thread(
            id: thread.id,
            title: thread.title,
            messages: thread.messages,
            container: thread.container,
            participants: thread.participants,
            isStarred: thread.isStarred,
            isPinned: thread.isPinned,
            isArchived: thread.isArchived,
            contextId: thread.contextId,
            modelId: thread.modelId,
            providerId: thread.providerId
        )

        return thread
    }

    /// Parse messages from markdown content section
    private static func parseMessages(from content: String) -> [ThreadMessage] {
        var messages: [ThreadMessage] = []
        var currentSender: MessageSender?
        var currentTimestamp: Date?
        var currentContent: [String] = []

        for line in content.components(separatedBy: .newlines) {
            // Check for message header: [role:name] or [role]
            if let header = parseMessageHeader(line) {
                // Save previous message
                if let sender = currentSender {
                    let text = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        let msg = ThreadMessage(
                            sender: sender,
                            content: .text(text),
                            timestamp: currentTimestamp ?? Date()
                        )
                        messages.append(msg)
                    }
                }

                currentSender = header.sender
                currentTimestamp = header.timestamp
                currentContent = []
            } else {
                currentContent.append(line)
            }
        }

        // Don't forget last message
        if let sender = currentSender {
            let text = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let msg = ThreadMessage(
                    sender: sender,
                    content: .text(text),
                    timestamp: currentTimestamp ?? Date()
                )
                messages.append(msg)
            }
        }

        return messages
    }

    private static func parseMessageHeader(_ line: String) -> (sender: MessageSender, timestamp: Date?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") else { return nil }
        guard let closeBracket = trimmed.firstIndex(of: "]") else { return nil }

        let inside = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket])
        let remaining = String(trimmed[trimmed.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)

        // Parse role and optional agent name: "user" or "assistant:AgentName"
        let parts = inside.split(separator: ":", maxSplits: 1)
        let roleStr = String(parts[0]).lowercased()

        let sender: MessageSender
        switch roleStr {
        case "user":
            sender = .user
        case "assistant", "agent":
            let agentName = parts.count > 1 ? String(parts[1]) : "Assistant"
            sender = .agent(id: nil, name: agentName)
        case "system":
            sender = .system
        default:
            return nil
        }

        // Parse timestamp from remaining
        var timestamp: Date?
        if !remaining.isEmpty {
            let isoFormatter = ISO8601DateFormatter()
            timestamp = isoFormatter.date(from: remaining)

            if timestamp == nil {
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm"
                if let time = timeFormatter.date(from: remaining) {
                    let calendar = Calendar.current
                    timestamp = calendar.date(bySettingHour: calendar.component(.hour, from: time),
                                              minute: calendar.component(.minute, from: time),
                                              second: 0, of: Date())
                }
            }
        }

        return (sender, timestamp)
    }

    /// Serialize thread to markdown with YAML frontmatter
    public func toMarkdown() -> String {
        var frontmatter: [String: Any] = [
            "id": id.rawValue,
            "title": title
        ]

        // Container
        switch container {
        case .space(let spaceId):
            frontmatter["spaceId"] = spaceId
        case .agent(let name):
            frontmatter["agentName"] = name
        case .group(let groupId):
            frontmatter["groupId"] = groupId
        case .global:
            break
        }

        if !participants.isEmpty {
            frontmatter["participants"] = participants
        }
        if isStarred { frontmatter["starred"] = true }
        if isPinned { frontmatter["pinned"] = true }
        if isArchived { frontmatter["archived"] = true }
        if let contextId = contextId { frontmatter["contextId"] = contextId }
        if let modelId = modelId { frontmatter["modelId"] = modelId }
        if let providerId = providerId { frontmatter["providerId"] = providerId }

        let formatter = ISO8601DateFormatter()
        frontmatter["created"] = formatter.string(from: createdAt)
        frontmatter["updated"] = formatter.string(from: updatedAt)

        // Serialize messages
        let content = messages.map { msg in
            let timeStr = formatMessageTime(msg.timestamp)
            let senderStr: String
            switch msg.sender {
            case .user:
                senderStr = "user"
            case .agent(_, let name):
                senderStr = "assistant:\(name)"
            case .system:
                senderStr = "system"
            }
            return "[\(senderStr)] \(timeStr)\n\(msg.textContent)"
        }.joined(separator: "\n\n")

        return FrontmatterParser.createDocument(frontmatter: frontmatter, content: content)
    }

    private func formatMessageTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Suggested filename for this thread
    public var suggestedFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let datePrefix = formatter.string(from: createdAt)
        let idSuffix = String(id.rawValue.prefix(8))
        return "\(datePrefix)-\(idSuffix).md"
    }

    // MARK: - File Operations

    /// Load a thread from a file path
    public static func load(from path: String) throws -> Thread {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)

        guard let content = String(data: data, encoding: .utf8) else {
            throw ThreadError.invalidEncoding
        }

        guard let thread = parse(from: content) else {
            throw ThreadError.invalidFormat
        }

        return thread
    }

    /// Save thread to a file path
    public func save(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let markdown = toMarkdown()

        guard let data = markdown.data(using: .utf8) else {
            throw ThreadError.invalidEncoding
        }

        // Create parent directory if needed
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try data.write(to: url)
    }
}

// MARK: - Thread Errors

public enum ThreadError: Error, LocalizedError {
    case invalidEncoding
    case invalidFormat
    case fileNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "File encoding is not valid UTF-8"
        case .invalidFormat:
            return "File is not a valid thread file"
        case .fileNotFound:
            return "Thread file not found"
        }
    }
}

