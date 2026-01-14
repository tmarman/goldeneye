import Foundation

// MARK: - Extension Registry

/// Central registry for discovering and managing agent extensions/tools.
///
/// Extensions can be:
/// - Built-in tools (Calendar, Reminders, etc.)
/// - AppIntents-based shortcuts
/// - MCP servers
/// - Custom tools
///
/// The UI presents these in an "Extensions" settings panel where users
/// can enable/disable and configure which tools agents have access to.
public actor ExtensionRegistry {
    // MARK: - Properties

    /// All registered extensions
    private var extensions: [ExtensionID: ExtensionDescriptor] = [:]

    /// User preferences for extension enabling
    private var enabledExtensions: Set<ExtensionID> = []

    /// Extension-specific configurations
    private var extensionConfigs: [ExtensionID: [String: Any]] = [:]

    /// Path to persist extension settings
    private let settingsPath: URL

    // MARK: - Initialization

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.settingsPath = appSupport.appendingPathComponent("Goldeneye/extensions.json")

        // Note: loadSettings() and registerBuiltInExtensions() are called
        // via initialize() after construction due to actor isolation
    }

    /// Initialize the registry - call after construction
    public func initialize() async {
        loadSettings()
        registerBuiltInExtensions()
    }

    // MARK: - Registration

    /// Register a new extension
    public func register(_ descriptor: ExtensionDescriptor) {
        extensions[descriptor.id] = descriptor

        // Enable by default if it's a built-in
        if descriptor.source == .builtIn {
            enabledExtensions.insert(descriptor.id)
        }
    }

    /// Unregister an extension
    public func unregister(_ id: ExtensionID) {
        extensions.removeValue(forKey: id)
        enabledExtensions.remove(id)
        extensionConfigs.removeValue(forKey: id)
    }

    // MARK: - Discovery

    /// Get all registered extensions
    public var allExtensions: [ExtensionDescriptor] {
        Array(extensions.values).sorted { $0.name < $1.name }
    }

    /// Get extensions by category
    public func extensions(in category: ExtensionCategory) -> [ExtensionDescriptor] {
        extensions.values.filter { $0.category == category }.sorted { $0.name < $1.name }
    }

    /// Get enabled extensions
    public var enabledExtensionsList: [ExtensionDescriptor] {
        extensions.values.filter { enabledExtensions.contains($0.id) }.sorted { $0.name < $1.name }
    }

    /// Check if an extension is enabled
    public func isEnabled(_ id: ExtensionID) -> Bool {
        enabledExtensions.contains(id)
    }

    // MARK: - Enable/Disable

    /// Enable an extension
    public func enable(_ id: ExtensionID) {
        enabledExtensions.insert(id)
        saveSettings()
    }

    /// Disable an extension
    public func disable(_ id: ExtensionID) {
        enabledExtensions.remove(id)
        saveSettings()
    }

    /// Toggle extension enabled state
    public func toggle(_ id: ExtensionID) {
        if enabledExtensions.contains(id) {
            enabledExtensions.remove(id)
        } else {
            enabledExtensions.insert(id)
        }
        saveSettings()
    }

    // MARK: - Configuration

    /// Get configuration for an extension
    public func config(for id: ExtensionID) -> [String: Any] {
        extensionConfigs[id] ?? [:]
    }

    /// Update configuration for an extension
    public func setConfig(_ config: [String: Any], for id: ExtensionID) {
        extensionConfigs[id] = config
        saveSettings()
    }

    // MARK: - Auto-Discovery

    /// Discover available extensions on the system
    public func discoverExtensions() async throws {
        // Discover AppIntents shortcuts
        #if os(macOS)
        if #available(macOS 13.0, *) {
            let appIntentsTool = AppIntentsTool()
            let shortcuts = try await appIntentsTool.discoverShortcuts()

            for shortcut in shortcuts {
                let descriptor = ExtensionDescriptor(
                    id: ExtensionID("shortcut.\(shortcut.id)"),
                    name: shortcut.name,
                    description: shortcut.description,
                    category: mapShortcutCategory(shortcut.category),
                    source: .appIntents,
                    icon: categoryIcon(for: shortcut.category),
                    capabilities: [.execute]
                )
                register(descriptor)
            }
        }
        #endif

        // Discover MCP servers from config
        // TODO: Read from MCP config file
    }

    private func mapShortcutCategory(_ category: String) -> ExtensionCategory {
        switch category {
        case "calendar": return .calendar
        case "reminders": return .tasks
        case "mail": return .communication
        case "messages": return .communication
        case "notes": return .documents
        case "files": return .files
        case "shortcuts": return .automation
        case "system": return .system
        default: return .other
        }
    }

    private func categoryIcon(for category: String) -> String {
        switch category {
        case "calendar": return "calendar"
        case "reminders": return "checklist"
        case "mail": return "envelope"
        case "messages": return "message"
        case "notes": return "note.text"
        case "files": return "folder"
        case "shortcuts": return "bolt.circle"
        case "system": return "gearshape"
        default: return "puzzlepiece.extension"
        }
    }

    // MARK: - Built-in Extensions

    private func registerBuiltInExtensions() {
        // Calendar
        register(ExtensionDescriptor(
            id: ExtensionID("goldeneye.calendar"),
            name: "Calendar",
            description: "Access and manage calendar events",
            category: .calendar,
            source: .builtIn,
            icon: "calendar",
            capabilities: [.read, .write, .execute]
        ))

        // Reminders
        register(ExtensionDescriptor(
            id: ExtensionID("goldeneye.reminders"),
            name: "Reminders",
            description: "Create and manage reminders",
            category: .tasks,
            source: .builtIn,
            icon: "checklist",
            capabilities: [.read, .write, .execute]
        ))

        // Safari Reading List
        register(ExtensionDescriptor(
            id: ExtensionID("goldeneye.reading-list"),
            name: "Reading List",
            description: "Import and index Safari Reading List",
            category: .documents,
            source: .builtIn,
            icon: "book",
            capabilities: [.read]
        ))

        // Shared with You
        register(ExtensionDescriptor(
            id: ExtensionID("goldeneye.shared-with-you"),
            name: "Shared with You",
            description: "Access content shared via Messages",
            category: .communication,
            source: .builtIn,
            icon: "person.2",
            capabilities: [.read]
        ))

        // File System
        register(ExtensionDescriptor(
            id: ExtensionID("goldeneye.filesystem"),
            name: "File System",
            description: "Read and write files",
            category: .files,
            source: .builtIn,
            icon: "folder",
            capabilities: [.read, .write]
        ))

        // Git
        register(ExtensionDescriptor(
            id: ExtensionID("goldeneye.git"),
            name: "Git",
            description: "Git repository operations",
            category: .development,
            source: .builtIn,
            icon: "arrow.triangle.branch",
            capabilities: [.read, .write, .execute]
        ))

        // Shell
        register(ExtensionDescriptor(
            id: ExtensionID("goldeneye.shell"),
            name: "Shell Commands",
            description: "Execute shell commands (with approval)",
            category: .system,
            source: .builtIn,
            icon: "terminal",
            capabilities: [.execute],
            requiresApproval: true
        ))

        // Web
        register(ExtensionDescriptor(
            id: ExtensionID("goldeneye.web"),
            name: "Web Fetch",
            description: "Fetch and parse web content",
            category: .other,
            source: .builtIn,
            icon: "globe",
            capabilities: [.read]
        ))

        // Memory/RAG
        register(ExtensionDescriptor(
            id: ExtensionID("goldeneye.memory"),
            name: "Memory",
            description: "Long-term memory with semantic search",
            category: .other,
            source: .builtIn,
            icon: "brain",
            capabilities: [.read, .write]
        ))
    }

    // MARK: - Persistence

    private func loadSettings() {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else { return }

        do {
            let data = try Data(contentsOf: settingsPath)
            let settings = try JSONDecoder().decode(ExtensionSettings.self, from: data)
            enabledExtensions = Set(settings.enabledIds.map { ExtensionID($0) })
        } catch {
            print("Failed to load extension settings: \(error)")
        }
    }

    private func saveSettings() {
        let settings = ExtensionSettings(
            enabledIds: enabledExtensions.map { $0.rawValue }
        )

        do {
            let data = try JSONEncoder().encode(settings)
            try FileManager.default.createDirectory(
                at: settingsPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: settingsPath)
        } catch {
            print("Failed to save extension settings: \(error)")
        }
    }
}

// MARK: - Types

public struct ExtensionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public struct ExtensionDescriptor: Identifiable, Sendable {
    public var id: ExtensionID
    public var name: String
    public var description: String
    public var category: ExtensionCategory
    public var source: ExtensionSource
    public var icon: String
    public var capabilities: Set<ExtensionCapability>
    public var requiresApproval: Bool
    public var configSchema: [ConfigField]

    public init(
        id: ExtensionID,
        name: String,
        description: String,
        category: ExtensionCategory,
        source: ExtensionSource,
        icon: String,
        capabilities: Set<ExtensionCapability>,
        requiresApproval: Bool = false,
        configSchema: [ConfigField] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.source = source
        self.icon = icon
        self.capabilities = capabilities
        self.requiresApproval = requiresApproval
        self.configSchema = configSchema
    }
}

public enum ExtensionCategory: String, Codable, Sendable, CaseIterable {
    case calendar
    case tasks
    case communication
    case documents
    case files
    case development
    case automation
    case system
    case other
}

public enum ExtensionSource: String, Codable, Sendable {
    case builtIn
    case appIntents
    case mcp
    case custom
}

public enum ExtensionCapability: String, Codable, Sendable {
    case read
    case write
    case execute
}

public struct ConfigField: Sendable {
    public let name: String
    public let type: ConfigFieldType
    public let required: Bool
    public let description: String?
}

public enum ConfigFieldType: Sendable {
    case string
    case number
    case boolean
    case selection([String])
}

private struct ExtensionSettings: Codable {
    let enabledIds: [String]
}
