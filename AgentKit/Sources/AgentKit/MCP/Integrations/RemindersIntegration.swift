//
//  RemindersIntegration.swift
//  AgentKit
//
//  Native Apple Reminders integration via EventKit.
//  Provides MCP-style tools for creating, listing, and managing reminders.
//

import EventKit
import Foundation

// MARK: - Reminders Integration

/// Native Apple Reminders integration providing MCP-style tools for agent use.
///
/// Uses EventKit's EKReminder API to:
/// - Create reminders with due dates and priorities
/// - List reminders from specific lists
/// - Mark reminders as complete
/// - Search reminders by title/notes
///
/// Usage:
/// ```swift
/// let reminders = RemindersIntegration()
/// try await reminders.requestAccess()
/// let tools = reminders.tools
/// let result = try await reminders.callTool("reminders_create", arguments: [
///     "title": "Review PR",
///     "notes": "Check the new feature implementation",
///     "due_date": "2024-01-15T10:00:00Z"
/// ])
/// ```
public actor RemindersIntegration {
    private let eventStore: EKEventStore
    private var hasAccess: Bool = false

    public init() {
        self.eventStore = EKEventStore()
    }

    // MARK: - Access Management

    /// Request access to Reminders
    public func requestAccess() async throws -> Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            hasAccess = try await eventStore.requestFullAccessToReminders()
        } else {
            hasAccess = try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
        return hasAccess
    }

    /// Check if we have access
    public var isConfigured: Bool {
        hasAccess
    }

    // MARK: - Health Check

    /// Health status for Reminders access
    public enum HealthStatus: Sendable {
        case healthy(String)
        case warning(String)
        case error(String)
        case unknown

        public var isHealthy: Bool {
            if case .healthy = self { return true }
            return false
        }

        public var message: String {
            switch self {
            case .healthy(let msg): return msg
            case .warning(let msg): return msg
            case .error(let msg): return msg
            case .unknown: return "Unknown status"
            }
        }
    }

    /// Check Reminders health status
    public func checkHealth() -> HealthStatus {
        let authStatus = EKEventStore.authorizationStatus(for: .reminder)

        switch authStatus {
        case .fullAccess, .authorized:
            let calendars = eventStore.calendars(for: .reminder)
            if calendars.isEmpty {
                return .warning("Access granted but no reminder lists found")
            }
            return .healthy("\(calendars.count) reminder lists accessible")

        case .writeOnly:
            return .warning("Write-only access - cannot read reminders")

        case .notDetermined:
            return .warning("Reminders access not requested")

        case .restricted:
            return .error("Reminders access restricted")

        case .denied:
            return .error("Reminders access denied - enable in System Settings > Privacy & Security > Reminders")

        @unknown default:
            return .unknown
        }
    }

    // MARK: - Tool Discovery

    /// All available Reminders tools
    public var tools: [MCPTool] {
        [
            MCPTool(from: [
                "name": "reminders_create",
                "description": "Create a new reminder in Apple Reminders. Returns the reminder ID.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Reminder title"],
                        "notes": ["type": "string", "description": "Optional notes for the reminder"],
                        "list": ["type": "string", "description": "Optional: Name of reminder list (defaults to default list)"],
                        "due_date": ["type": "string", "description": "Optional: Due date in ISO 8601 format"],
                        "priority": ["type": "integer", "description": "Priority: 0 (none), 1 (high), 5 (medium), 9 (low)"]
                    ],
                    "required": ["title"]
                ]
            ]),
            MCPTool(from: [
                "name": "reminders_list",
                "description": "List reminders from a specific list or all lists.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "list": ["type": "string", "description": "Optional: Name of reminder list to query"],
                        "include_completed": ["type": "boolean", "description": "Include completed reminders (default: false)"],
                        "limit": ["type": "integer", "description": "Maximum reminders to return (default: 50)"]
                    ],
                    "required": []
                ]
            ]),
            MCPTool(from: [
                "name": "reminders_complete",
                "description": "Mark a reminder as complete.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "reminder_id": ["type": "string", "description": "The reminder's calendar item identifier"]
                    ],
                    "required": ["reminder_id"]
                ]
            ]),
            MCPTool(from: [
                "name": "reminders_search",
                "description": "Search reminders by title or notes.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query to match against title and notes"],
                        "include_completed": ["type": "boolean", "description": "Include completed reminders (default: false)"]
                    ],
                    "required": ["query"]
                ]
            ]),
            MCPTool(from: [
                "name": "reminders_lists",
                "description": "List all reminder lists (calendars).",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ])
        ]
    }

    // MARK: - Tool Execution

    /// Call a Reminders tool with the given arguments
    public func callTool(_ name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        if !hasAccess {
            // Try to get access
            let granted = try await requestAccess()
            if !granted {
                return errorResult("Reminders access not granted. Please enable in System Settings.")
            }
        }

        switch name {
        case "reminders_create":
            return try await createReminder(arguments)
        case "reminders_list":
            return try await listReminders(arguments)
        case "reminders_complete":
            return try await completeReminder(arguments)
        case "reminders_search":
            return try await searchReminders(arguments)
        case "reminders_lists":
            return await listReminderLists()
        default:
            throw MCPError.toolNotFound(name)
        }
    }

    // MARK: - API Methods

    private func createReminder(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let title = args["title"] as? String else {
            return errorResult("Missing required: title")
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title

        // Set notes
        if let notes = args["notes"] as? String {
            reminder.notes = notes
        }

        // Set priority (0 = none, 1-4 = high, 5 = medium, 6-9 = low)
        if let priority = args["priority"] as? Int {
            reminder.priority = priority
        }

        // Set due date
        if let dueDateString = args["due_date"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let dueDate = formatter.date(from: dueDateString) ?? ISO8601DateFormatter().date(from: dueDateString) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: dueDate
                )
            }
        }

        // Find the target calendar (reminder list)
        if let listName = args["list"] as? String {
            let calendars = eventStore.calendars(for: .reminder)
            if let targetCalendar = calendars.first(where: { $0.title.lowercased() == listName.lowercased() }) {
                reminder.calendar = targetCalendar
            } else {
                return errorResult("Reminder list '\(listName)' not found")
            }
        } else {
            // Use default calendar
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
        }

        // Save the reminder
        do {
            try eventStore.save(reminder, commit: true)
            let listName = reminder.calendar?.title ?? "Unknown"
            return successResult("Created reminder '\(title)' in '\(listName)' (ID: \(reminder.calendarItemIdentifier))")
        } catch {
            return errorResult("Failed to create reminder: \(error.localizedDescription)")
        }
    }

    private func listReminders(_ args: [String: Any]) async throws -> MCPToolResult {
        let includeCompleted = args["include_completed"] as? Bool ?? false
        let limit = args["limit"] as? Int ?? 50

        // Get calendars to query
        var calendars: [EKCalendar]?
        if let listName = args["list"] as? String {
            let allCalendars = eventStore.calendars(for: .reminder)
            if let targetCalendar = allCalendars.first(where: { $0.title.lowercased() == listName.lowercased() }) {
                calendars = [targetCalendar]
            } else {
                return errorResult("Reminder list '\(listName)' not found")
            }
        }

        // Create predicate
        let predicate: NSPredicate
        if includeCompleted {
            predicate = eventStore.predicateForReminders(in: calendars)
        } else {
            predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: calendars
            )
        }

        // Fetch reminders - map to Sendable data immediately
        let reminderData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ReminderData], Error>) in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let data = (reminders ?? []).map { ReminderData(from: $0) }
                continuation.resume(returning: data)
            }
        }

        // Format results
        let limitedReminders = Array(reminderData.prefix(limit))
        let formatted = limitedReminders.map { reminder -> String in
            let status = reminder.isCompleted ? "✅" : "⬜️"
            let dueStr = reminder.dueDate.map { date -> String in
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return "Due: \(formatter.string(from: date))"
            } ?? ""
            let priorityStr = priorityString(reminder.priority)

            return "\(status) \(reminder.title)\(priorityStr.isEmpty ? "" : " [\(priorityStr)]")\n   List: \(reminder.listName)\(dueStr.isEmpty ? "" : " | \(dueStr)")"
        }

        if formatted.isEmpty {
            return successResult("No reminders found")
        }

        return successResult("Found \(reminderData.count) reminders (showing \(limitedReminders.count)):\n\n\(formatted.joined(separator: "\n\n"))")
    }

    private func completeReminder(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let reminderId = args["reminder_id"] as? String else {
            return errorResult("Missing required: reminder_id")
        }

        // Fetch the reminder
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            return errorResult("Reminder not found with ID: \(reminderId)")
        }

        // Mark as complete
        reminder.isCompleted = true
        reminder.completionDate = Date()

        do {
            try eventStore.save(reminder, commit: true)
            return successResult("Marked '\(reminder.title ?? "Untitled")' as complete")
        } catch {
            return errorResult("Failed to complete reminder: \(error.localizedDescription)")
        }
    }

    private func searchReminders(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let query = args["query"] as? String else {
            return errorResult("Missing required: query")
        }

        let includeCompleted = args["include_completed"] as? Bool ?? false
        let queryLower = query.lowercased()

        // Fetch all reminders
        let predicate: NSPredicate
        if includeCompleted {
            predicate = eventStore.predicateForReminders(in: nil)
        } else {
            predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: nil
            )
        }

        let allReminders = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ReminderData], Error>) in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let data = (reminders ?? []).map { ReminderData(from: $0) }
                continuation.resume(returning: data)
            }
        }

        // Filter by search query
        let matches = allReminders.filter { reminder in
            let titleMatch = reminder.title.lowercased().contains(queryLower)
            let notesMatch = reminder.notes?.lowercased().contains(queryLower) ?? false
            return titleMatch || notesMatch
        }

        if matches.isEmpty {
            return successResult("No reminders found matching '\(query)'")
        }

        let formatted = matches.prefix(20).map { reminder -> String in
            let status = reminder.isCompleted ? "✅" : "⬜️"
            return "\(status) \(reminder.title) [\(reminder.listName)]\n   ID: \(reminder.id)"
        }

        return successResult("Found \(matches.count) reminders matching '\(query)':\n\n\(formatted.joined(separator: "\n\n"))")
    }

    private func listReminderLists() async -> MCPToolResult {
        let calendars = eventStore.calendars(for: .reminder)

        if calendars.isEmpty {
            return successResult("No reminder lists found")
        }

        let defaultCalendar = eventStore.defaultCalendarForNewReminders()
        let formatted = calendars.map { calendar -> String in
            let isDefault = calendar.calendarIdentifier == defaultCalendar?.calendarIdentifier
            return "\(calendar.title)\(isDefault ? " (default)" : "")"
        }

        return successResult("Available reminder lists:\n• \(formatted.joined(separator: "\n• "))")
    }

    // MARK: - Helpers

    private func priorityString(_ priority: Int) -> String {
        switch priority {
        case 1...4: return "High"
        case 5: return "Medium"
        case 6...9: return "Low"
        default: return ""
        }
    }

    private func successResult(_ text: String) -> MCPToolResult {
        MCPToolResult(from: [
            "content": [["type": "text", "text": text]],
            "isError": false
        ])
    }

    private func errorResult(_ text: String) -> MCPToolResult {
        MCPToolResult(from: [
            "content": [["type": "text", "text": text]],
            "isError": true
        ])
    }
}

// MARK: - Sendable Helper

/// Sendable representation of reminder data for crossing actor boundaries
private struct ReminderData: Sendable {
    let id: String
    let title: String
    let notes: String?
    let isCompleted: Bool
    let priority: Int
    let dueDate: Date?
    let listName: String

    init(from reminder: EKReminder) {
        self.id = reminder.calendarItemIdentifier
        self.title = reminder.title ?? "Untitled"
        self.notes = reminder.notes
        self.isCompleted = reminder.isCompleted
        self.priority = reminder.priority
        self.dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        self.listName = reminder.calendar?.title ?? ""
    }
}
