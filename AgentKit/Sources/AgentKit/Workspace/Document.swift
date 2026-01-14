import Foundation

// MARK: - Document

/// A document is a block-based unit of content, similar to Craft or Notion.
///
/// Documents contain an ordered list of blocks that can be text, headings,
/// lists, code, or agent-maintained content.
public struct Document: Identifiable, Codable, Sendable {
    public let id: DocumentID
    public var title: String
    public var blocks: [Block]
    public var folderId: FolderID?
    public var tagIds: [TagID]
    public var isStarred: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: DocumentID = DocumentID(),
        title: String = "",
        blocks: [Block] = [],
        folderId: FolderID? = nil,
        tagIds: [TagID] = [],
        isStarred: Bool = false
    ) {
        self.id = id
        self.title = title
        self.blocks = blocks
        self.folderId = folderId
        self.tagIds = tagIds
        self.isStarred = isStarred
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Create a new document with initial text
    public static func blank(title: String = "") -> Document {
        Document(
            title: title,
            blocks: [.text(TextBlock(content: ""))]
        )
    }
}

public struct DocumentID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

// MARK: - Block

/// A block is the fundamental unit of content within a document.
public enum Block: Identifiable, Codable, Sendable {
    case text(TextBlock)
    case heading(HeadingBlock)
    case bulletList(BulletListBlock)
    case numberedList(NumberedListBlock)
    case todo(TodoBlock)
    case code(CodeBlock)
    case quote(QuoteBlock)
    case divider(DividerBlock)
    case callout(CalloutBlock)
    case image(ImageBlock)
    case agent(AgentBlock)  // Live agent-maintained content

    public var id: BlockID {
        switch self {
        case .text(let block): return block.id
        case .heading(let block): return block.id
        case .bulletList(let block): return block.id
        case .numberedList(let block): return block.id
        case .todo(let block): return block.id
        case .code(let block): return block.id
        case .quote(let block): return block.id
        case .divider(let block): return block.id
        case .callout(let block): return block.id
        case .image(let block): return block.id
        case .agent(let block): return block.id
        }
    }
}

public struct BlockID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

// MARK: - Block Operations

extension Block {
    /// Creates a duplicate of this block with a new ID
    public func duplicate() -> Block {
        switch self {
        case .text(let block):
            return .text(TextBlock(content: block.content, style: block.style))
        case .heading(let block):
            return .heading(HeadingBlock(content: block.content, level: block.level))
        case .bulletList(let block):
            return .bulletList(BulletListBlock(items: block.items.map { ListItem(content: $0.content, children: $0.children) }))
        case .numberedList(let block):
            return .numberedList(NumberedListBlock(items: block.items.map { ListItem(content: $0.content, children: $0.children) }))
        case .todo(let block):
            return .todo(TodoBlock(items: block.items.map { TodoItem(content: $0.content, isCompleted: $0.isCompleted, dueDate: $0.dueDate) }))
        case .code(let block):
            return .code(CodeBlock(content: block.content, language: block.language))
        case .quote(let block):
            return .quote(QuoteBlock(content: block.content, attribution: block.attribution))
        case .divider:
            return .divider(DividerBlock())
        case .callout(let block):
            return .callout(CalloutBlock(content: block.content, icon: block.icon, style: block.style))
        case .image(let block):
            return .image(ImageBlock(url: block.url, localPath: block.localPath, caption: block.caption, alt: block.alt))
        case .agent(let block):
            return .agent(AgentBlock(agentId: block.agentId, prompt: block.prompt, content: block.content))
        }
    }

    /// Extracts the primary text content from this block
    public func extractContent() -> String {
        switch self {
        case .text(let block): return block.content
        case .heading(let block): return block.content
        case .bulletList(let block): return block.items.map { $0.content }.joined(separator: "\n")
        case .numberedList(let block): return block.items.map { $0.content }.joined(separator: "\n")
        case .todo(let block): return block.items.map { $0.content }.joined(separator: "\n")
        case .code(let block): return block.content
        case .quote(let block): return block.content
        case .divider: return ""
        case .callout(let block): return block.content
        case .image(let block): return block.caption ?? ""
        case .agent(let block): return block.prompt
        }
    }

    /// Sets the content of this block (mutating)
    public mutating func setContent(_ content: String) {
        switch self {
        case .text(var block):
            block.content = content
            self = .text(block)
        case .heading(var block):
            block.content = content
            self = .heading(block)
        case .bulletList(var block):
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
            block.items = lines.map { ListItem(content: $0) }
            if block.items.isEmpty { block.items = [ListItem(content: "")] }
            self = .bulletList(block)
        case .numberedList(var block):
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
            block.items = lines.map { ListItem(content: $0) }
            if block.items.isEmpty { block.items = [ListItem(content: "")] }
            self = .numberedList(block)
        case .todo(var block):
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
            block.items = lines.map { TodoItem(content: $0) }
            if block.items.isEmpty { block.items = [TodoItem(content: "")] }
            self = .todo(block)
        case .code(var block):
            block.content = content
            self = .code(block)
        case .quote(var block):
            block.content = content
            self = .quote(block)
        case .divider:
            break // Dividers have no content
        case .callout(var block):
            block.content = content
            self = .callout(block)
        case .image(var block):
            block.caption = content.isEmpty ? nil : content
            self = .image(block)
        case .agent(var block):
            block.prompt = content
            self = .agent(block)
        }
    }
}

// MARK: - Block Types

public struct TextBlock: Codable, Sendable {
    public let id: BlockID
    public var content: String
    public var style: TextStyle

    public init(
        id: BlockID = BlockID(),
        content: String,
        style: TextStyle = .body
    ) {
        self.id = id
        self.content = content
        self.style = style
    }
}

public enum TextStyle: String, Codable, Sendable {
    case body
    case caption
    case strong
}

public struct HeadingBlock: Codable, Sendable {
    public let id: BlockID
    public var content: String
    public var level: HeadingLevel

    public init(
        id: BlockID = BlockID(),
        content: String,
        level: HeadingLevel = .h1
    ) {
        self.id = id
        self.content = content
        self.level = level
    }
}

public enum HeadingLevel: Int, Codable, Sendable {
    case h1 = 1
    case h2 = 2
    case h3 = 3
}

public struct BulletListBlock: Codable, Sendable {
    public let id: BlockID
    public var items: [ListItem]

    public init(id: BlockID = BlockID(), items: [ListItem] = []) {
        self.id = id
        self.items = items
    }
}

public struct NumberedListBlock: Codable, Sendable {
    public let id: BlockID
    public var items: [ListItem]

    public init(id: BlockID = BlockID(), items: [ListItem] = []) {
        self.id = id
        self.items = items
    }
}

public struct ListItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public var content: String
    public var children: [ListItem]

    public init(id: UUID = UUID(), content: String, children: [ListItem] = []) {
        self.id = id
        self.content = content
        self.children = children
    }
}

public struct TodoBlock: Codable, Sendable {
    public let id: BlockID
    public var items: [TodoItem]

    public init(id: BlockID = BlockID(), items: [TodoItem] = []) {
        self.id = id
        self.items = items
    }
}

public struct TodoItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public var content: String
    public var isCompleted: Bool
    public var dueDate: Date?

    public init(
        id: UUID = UUID(),
        content: String,
        isCompleted: Bool = false,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.isCompleted = isCompleted
        self.dueDate = dueDate
    }
}

public struct CodeBlock: Codable, Sendable {
    public let id: BlockID
    public var content: String
    public var language: String?

    public init(id: BlockID = BlockID(), content: String, language: String? = nil) {
        self.id = id
        self.content = content
        self.language = language
    }
}

public struct QuoteBlock: Codable, Sendable {
    public let id: BlockID
    public var content: String
    public var attribution: String?

    public init(id: BlockID = BlockID(), content: String, attribution: String? = nil) {
        self.id = id
        self.content = content
        self.attribution = attribution
    }
}

public struct DividerBlock: Codable, Sendable {
    public let id: BlockID

    public init(id: BlockID = BlockID()) {
        self.id = id
    }
}

public struct CalloutBlock: Codable, Sendable {
    public let id: BlockID
    public var content: String
    public var icon: String
    public var style: CalloutStyle

    public init(
        id: BlockID = BlockID(),
        content: String,
        icon: String = "💡",
        style: CalloutStyle = .info
    ) {
        self.id = id
        self.content = content
        self.icon = icon
        self.style = style
    }
}

public enum CalloutStyle: String, Codable, Sendable {
    case info, warning, success, error
}

public struct ImageBlock: Codable, Sendable {
    public let id: BlockID
    public var url: URL?
    public var localPath: String?
    public var caption: String?
    public var alt: String?

    public init(
        id: BlockID = BlockID(),
        url: URL? = nil,
        localPath: String? = nil,
        caption: String? = nil,
        alt: String? = nil
    ) {
        self.id = id
        self.url = url
        self.localPath = localPath
        self.caption = caption
        self.alt = alt
    }
}

// MARK: - Agent Block

/// An agent block is a live section of a document maintained by an agent.
///
/// The content is periodically refreshed by the assigned agent, enabling
/// dynamic, agent-generated content within documents.
public struct AgentBlock: Codable, Sendable {
    public let id: BlockID
    public var agentId: AgentID?
    public var prompt: String
    public var content: String
    public var lastUpdated: Date?
    public var isLoading: Bool
    public var error: String?

    public init(
        id: BlockID = BlockID(),
        agentId: AgentID? = nil,
        prompt: String,
        content: String = "",
        lastUpdated: Date? = nil,
        isLoading: Bool = false,
        error: String? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.prompt = prompt
        self.content = content
        self.lastUpdated = lastUpdated
        self.isLoading = isLoading
        self.error = error
    }
}
