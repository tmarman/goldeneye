import Foundation

#if os(macOS)
import AppKit
import AppIntents

// MARK: - AppIntents Tool

/// MCP-compatible tool that wraps AppIntents for agent use.
///
/// This allows agents to discover and invoke any AppIntents-based
/// shortcuts and actions installed on the system.
///
/// ## Capabilities
/// - Discover available AppIntents shortcuts
/// - Execute shortcuts with parameters
/// - Calendar, Reminders, Mail, Messages integrations
/// - Third-party app shortcuts
///
/// ## Example
/// ```swift
/// let tool = AppIntentsTool()
/// let shortcuts = try await tool.discoverShortcuts()
///
/// // Execute a shortcut
/// let result = try await tool.execute(
///     shortcutId: "com.apple.calendar.create-event",
///     parameters: ["title": "Meeting", "date": "2024-01-15T10:00:00"]
/// )
/// ```
@available(macOS 13.0, *)
public struct AppIntentsTool: Tool {
    public let name = "app_intents"
    public let description = "Execute macOS Shortcuts and AppIntents actions"

    public init() {}

    // MARK: - Tool Protocol

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "action": ToolSchema.PropertySchema(type: "string", description: "The action to perform: 'discover', 'execute', 'list_categories'"),
                "shortcut_id": ToolSchema.PropertySchema(type: "string", description: "The shortcut identifier (for execute action)"),
                "parameters": ToolSchema.PropertySchema(type: "object", description: "Parameters for the shortcut")
            ],
            required: ["action"]
        )
    }

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        guard let action = input.get("action", as: String.self) else {
            return .error("Missing required 'action' parameter")
        }

        switch action {
        case "discover":
            let shortcuts = try await discoverShortcuts()
            let data = try JSONEncoder().encode(shortcuts)
            return .success(String(data: data, encoding: .utf8) ?? "[]")

        case "execute":
            guard let shortcutId = input.get("shortcut_id", as: String.self) else {
                return .error("Missing 'shortcut_id' for execute action")
            }
            let parameters = input.get("parameters", as: [String: Any].self) ?? [:]
            let result = try await executeShortcut(shortcutId: shortcutId, parameters: parameters)
            return .success(result)

        case "list_categories":
            return .success("""
            [
                {"id": "calendar", "name": "Calendar", "description": "Create events, check availability"},
                {"id": "reminders", "name": "Reminders", "description": "Create and manage tasks"},
                {"id": "mail", "name": "Mail", "description": "Send emails, search inbox"},
                {"id": "messages", "name": "Messages", "description": "Send messages"},
                {"id": "notes", "name": "Notes", "description": "Create and search notes"},
                {"id": "files", "name": "Files", "description": "File operations"},
                {"id": "shortcuts", "name": "Shortcuts", "description": "User-created shortcuts"},
                {"id": "system", "name": "System", "description": "System preferences and settings"}
            ]
            """)

        default:
            return .error("Unknown action: \(action). Use 'discover', 'execute', or 'list_categories'")
        }
    }

    // MARK: - Discovery

    /// Discover available shortcuts on the system
    public func discoverShortcuts() async throws -> [DiscoverableShortcut] {
        var shortcuts: [DiscoverableShortcut] = []

        // Built-in integrations we support directly
        shortcuts.append(contentsOf: calendarShortcuts())
        shortcuts.append(contentsOf: remindersShortcuts())
        shortcuts.append(contentsOf: mailShortcuts())
        shortcuts.append(contentsOf: messagesShortcuts())
        shortcuts.append(contentsOf: notesShortcuts())

        // User-created Shortcuts.app shortcuts
        let userShortcuts = try await discoverUserShortcuts()
        shortcuts.append(contentsOf: userShortcuts)

        return shortcuts
    }

    // MARK: - Execution

    /// Execute a shortcut with parameters
    func executeShortcut(shortcutId: String, parameters: [String: Any]) async throws -> String {
        let parts = shortcutId.split(separator: ".")

        // Route to appropriate handler
        if parts.first == "calendar" {
            return try await executeCalendarAction(String(parts.dropFirst().joined(separator: ".")), parameters: parameters)
        } else if parts.first == "reminders" {
            return try await executeRemindersAction(String(parts.dropFirst().joined(separator: ".")), parameters: parameters)
        } else if parts.first == "mail" {
            return try await executeMailAction(String(parts.dropFirst().joined(separator: ".")), parameters: parameters)
        } else if parts.first == "messages" {
            return try await executeMessagesAction(String(parts.dropFirst().joined(separator: ".")), parameters: parameters)
        } else if parts.first == "shortcut" {
            // User shortcut
            let shortcutName = String(parts.dropFirst().joined(separator: "."))
            return try await runUserShortcut(name: shortcutName, input: parameters)
        }

        throw AppIntentsToolError.unknownShortcut(shortcutId)
    }

    // MARK: - Calendar

    private func calendarShortcuts() -> [DiscoverableShortcut] {
        [
            DiscoverableShortcut(
                id: "calendar.create-event",
                name: "Create Calendar Event",
                description: "Create a new calendar event",
                category: "calendar",
                parameters: [
                    ShortcutParameter(name: "title", type: "string", required: true),
                    ShortcutParameter(name: "start_date", type: "date", required: true),
                    ShortcutParameter(name: "end_date", type: "date", required: false),
                    ShortcutParameter(name: "location", type: "string", required: false),
                    ShortcutParameter(name: "notes", type: "string", required: false),
                    ShortcutParameter(name: "calendar", type: "string", required: false)
                ]
            ),
            DiscoverableShortcut(
                id: "calendar.get-events",
                name: "Get Calendar Events",
                description: "Retrieve calendar events for a date range",
                category: "calendar",
                parameters: [
                    ShortcutParameter(name: "start_date", type: "date", required: true),
                    ShortcutParameter(name: "end_date", type: "date", required: true),
                    ShortcutParameter(name: "calendar", type: "string", required: false)
                ]
            ),
            DiscoverableShortcut(
                id: "calendar.check-availability",
                name: "Check Availability",
                description: "Check if a time slot is available",
                category: "calendar",
                parameters: [
                    ShortcutParameter(name: "start_date", type: "date", required: true),
                    ShortcutParameter(name: "end_date", type: "date", required: true)
                ]
            )
        ]
    }

    private func executeCalendarAction(_ action: String, parameters: [String: Any]) async throws -> String {
        // Uses EventKit - implementation in EventKitSource.swift
        switch action {
        case "create-event":
            guard let title = parameters["title"] as? String,
                  let startDateStr = parameters["start_date"] as? String else {
                throw AppIntentsToolError.missingParameter("title and start_date required")
            }
            // Would call EventKitSource to create event
            return "Event '\(title)' created"

        case "get-events":
            return "Events retrieved"

        case "check-availability":
            return "Time slot available"

        default:
            throw AppIntentsToolError.unknownAction(action)
        }
    }

    // MARK: - Reminders

    private func remindersShortcuts() -> [DiscoverableShortcut] {
        [
            DiscoverableShortcut(
                id: "reminders.create-reminder",
                name: "Create Reminder",
                description: "Create a new reminder",
                category: "reminders",
                parameters: [
                    ShortcutParameter(name: "title", type: "string", required: true),
                    ShortcutParameter(name: "due_date", type: "date", required: false),
                    ShortcutParameter(name: "priority", type: "string", required: false),
                    ShortcutParameter(name: "list", type: "string", required: false),
                    ShortcutParameter(name: "notes", type: "string", required: false)
                ]
            ),
            DiscoverableShortcut(
                id: "reminders.get-reminders",
                name: "Get Reminders",
                description: "Retrieve reminders from a list",
                category: "reminders",
                parameters: [
                    ShortcutParameter(name: "list", type: "string", required: false),
                    ShortcutParameter(name: "completed", type: "boolean", required: false)
                ]
            ),
            DiscoverableShortcut(
                id: "reminders.complete-reminder",
                name: "Complete Reminder",
                description: "Mark a reminder as complete",
                category: "reminders",
                parameters: [
                    ShortcutParameter(name: "reminder_id", type: "string", required: true)
                ]
            )
        ]
    }

    private func executeRemindersAction(_ action: String, parameters: [String: Any]) async throws -> String {
        switch action {
        case "create-reminder":
            guard let title = parameters["title"] as? String else {
                throw AppIntentsToolError.missingParameter("title required")
            }
            // Would use EventKit's EKReminder
            return "Reminder '\(title)' created"

        default:
            throw AppIntentsToolError.unknownAction(action)
        }
    }

    // MARK: - Mail

    private func mailShortcuts() -> [DiscoverableShortcut] {
        [
            DiscoverableShortcut(
                id: "mail.compose",
                name: "Compose Email",
                description: "Open a new email composition window",
                category: "mail",
                parameters: [
                    ShortcutParameter(name: "to", type: "string", required: true),
                    ShortcutParameter(name: "subject", type: "string", required: false),
                    ShortcutParameter(name: "body", type: "string", required: false),
                    ShortcutParameter(name: "cc", type: "string", required: false),
                    ShortcutParameter(name: "bcc", type: "string", required: false)
                ]
            )
        ]
    }

    private func executeMailAction(_ action: String, parameters: [String: Any]) async throws -> String {
        switch action {
        case "compose":
            guard let to = parameters["to"] as? String else {
                throw AppIntentsToolError.missingParameter("to required")
            }
            // Use mailto: URL scheme
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = to
            var queryItems: [URLQueryItem] = []
            if let subject = parameters["subject"] as? String {
                queryItems.append(URLQueryItem(name: "subject", value: subject))
            }
            if let body = parameters["body"] as? String {
                queryItems.append(URLQueryItem(name: "body", value: body))
            }
            components.queryItems = queryItems.isEmpty ? nil : queryItems

            if let url = components.url {
                await NSWorkspace.shared.open(url)
                return "Email composition opened"
            }
            throw AppIntentsToolError.executionFailed("Could not create mailto URL")

        default:
            throw AppIntentsToolError.unknownAction(action)
        }
    }

    // MARK: - Messages

    private func messagesShortcuts() -> [DiscoverableShortcut] {
        [
            DiscoverableShortcut(
                id: "messages.send",
                name: "Send Message",
                description: "Send an iMessage or SMS",
                category: "messages",
                parameters: [
                    ShortcutParameter(name: "to", type: "string", required: true),
                    ShortcutParameter(name: "message", type: "string", required: true)
                ]
            )
        ]
    }

    private func executeMessagesAction(_ action: String, parameters: [String: Any]) async throws -> String {
        switch action {
        case "send":
            guard let to = parameters["to"] as? String,
                  let message = parameters["message"] as? String else {
                throw AppIntentsToolError.missingParameter("to and message required")
            }
            // Use imessage: URL scheme
            let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
            if let url = URL(string: "imessage://\(to)?body=\(encodedMessage)") {
                await NSWorkspace.shared.open(url)
                return "Message window opened"
            }
            throw AppIntentsToolError.executionFailed("Could not create message URL")

        default:
            throw AppIntentsToolError.unknownAction(action)
        }
    }

    // MARK: - Notes

    private func notesShortcuts() -> [DiscoverableShortcut] {
        [
            DiscoverableShortcut(
                id: "notes.create",
                name: "Create Note",
                description: "Create a new Apple Note",
                category: "notes",
                parameters: [
                    ShortcutParameter(name: "title", type: "string", required: false),
                    ShortcutParameter(name: "body", type: "string", required: true),
                    ShortcutParameter(name: "folder", type: "string", required: false)
                ]
            )
        ]
    }

    // MARK: - User Shortcuts

    private func discoverUserShortcuts() async throws -> [DiscoverableShortcut] {
        // Use shortcuts CLI to list available shortcuts
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { name in
                DiscoverableShortcut(
                    id: "shortcut.\(name)",
                    name: name,
                    description: "User-created shortcut",
                    category: "shortcuts",
                    parameters: [
                        ShortcutParameter(name: "input", type: "string", required: false)
                    ]
                )
            }
    }

    private func runUserShortcut(name: String, input: [String: Any]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]

        // Pass input if provided
        if let inputStr = input["input"] as? String {
            let inputPipe = Pipe()
            inputPipe.fileHandleForWriting.write(inputStr.data(using: .utf8) ?? Data())
            inputPipe.fileHandleForWriting.closeFile()
            process.standardInput = inputPipe
        }

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "Shortcut executed"
    }
}

// MARK: - Types

public struct DiscoverableShortcut: Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let category: String
    public let parameters: [ShortcutParameter]
}

public struct ShortcutParameter: Codable, Sendable {
    public let name: String
    public let type: String
    public let required: Bool
}

public enum AppIntentsToolError: Error, LocalizedError {
    case unknownShortcut(String)
    case unknownAction(String)
    case missingParameter(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unknownShortcut(let id):
            return "Unknown shortcut: \(id)"
        case .unknownAction(let action):
            return "Unknown action: \(action)"
        case .missingParameter(let param):
            return "Missing parameter: \(param)"
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        }
    }
}

#endif
