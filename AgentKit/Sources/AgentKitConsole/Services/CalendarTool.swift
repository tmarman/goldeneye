import AgentKit
import EventKit
import Foundation

// MARK: - Calendar Tool

/// Tool for accessing local calendar events via EventKit
/// Exposes calendar data to agents for cross-machine access via A2A protocol
public final class CalendarTool: Tool, @unchecked Sendable {
    public static let shared = CalendarTool()

    public let name = "calendar"
    public let description = "Access local calendar events. Supports listing today's events, upcoming events, or events within a date range."

    public let inputSchema = ToolSchema(
        properties: [
            "action": .init(
                type: "string",
                description: "Action to perform: 'today', 'upcoming', 'range', or 'search'",
                enumValues: ["today", "upcoming", "range", "search"]
            ),
            "start_date": .init(
                type: "string",
                description: "Start date for range query (ISO 8601 format, e.g., '2024-01-15')"
            ),
            "end_date": .init(
                type: "string",
                description: "End date for range query (ISO 8601 format)"
            ),
            "query": .init(
                type: "string",
                description: "Search query for finding events by title"
            ),
            "days_ahead": .init(
                type: "integer",
                description: "Number of days ahead for upcoming events (default: 7)"
            ),
        ],
        required: ["action"]
    )

    public var requiresApproval: Bool { false }
    public var riskLevel: RiskLevel { .low }

    private init() {}

    // MARK: - Tool Protocol

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        await CalendarHelper.shared.execute(input)
    }

    public func describeAction(_ input: ToolInput) -> String {
        guard let action = input.get("action", as: String.self) else {
            return "Access calendar"
        }
        switch action {
        case "today":
            return "Get today's calendar events"
        case "upcoming":
            let days = input.get("days_ahead", as: Int.self) ?? 7
            return "Get calendar events for the next \(days) days"
        case "range":
            return "Get calendar events within date range"
        case "search":
            let query = input.get("query", as: String.self) ?? ""
            return "Search calendar for '\(query)'"
        default:
            return "Access calendar"
        }
    }
}

// MARK: - Calendar Helper Actor

/// Actor to handle EventKit operations with proper isolation
@MainActor
private final class CalendarHelper {
    static let shared = CalendarHelper()

    private let eventStore = EKEventStore()
    private var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private init() {
        checkAuthorizationStatus()
    }

    private func checkAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    private func requestAccessIfNeeded() async -> Bool {
        checkAuthorizationStatus()

        if authorizationStatus == .fullAccess || authorizationStatus == .authorized {
            return true
        }

        if authorizationStatus == .notDetermined {
            do {
                let granted: Bool
                if #available(macOS 14.0, *) {
                    granted = try await eventStore.requestFullAccessToEvents()
                } else {
                    granted = try await eventStore.requestAccess(to: .event)
                }
                checkAuthorizationStatus()
                return granted
            } catch {
                return false
            }
        }

        return false
    }

    func execute(_ input: ToolInput) async -> ToolOutput {
        guard await requestAccessIfNeeded() else {
            return .error("Calendar access not granted. Please enable calendar permissions in System Settings.")
        }

        guard let action = input.get("action", as: String.self) else {
            return .error("Missing required parameter: action")
        }

        switch action {
        case "today":
            return fetchTodayEvents()
        case "upcoming":
            let daysAhead = input.get("days_ahead", as: Int.self) ?? 7
            return fetchUpcomingEvents(daysAhead: daysAhead)
        case "range":
            guard let startStr = input.get("start_date", as: String.self),
                  let endStr = input.get("end_date", as: String.self)
            else {
                return .error("Range action requires start_date and end_date parameters")
            }
            return fetchEventsInRange(startDateStr: startStr, endDateStr: endStr)
        case "search":
            guard let query = input.get("query", as: String.self) else {
                return .error("Search action requires query parameter")
            }
            let daysAhead = input.get("days_ahead", as: Int.self) ?? 30
            return searchEvents(query: query, daysAhead: daysAhead)
        default:
            return .error("Unknown action: \(action). Use 'today', 'upcoming', 'range', or 'search'.")
        }
    }

    // MARK: - Event Fetching

    private func fetchTodayEvents() -> ToolOutput {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        let predicate = eventStore.predicateForEvents(
            withStart: todayStart,
            end: todayEnd,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        return formatEvents(events, title: "Today's Events")
    }

    private func fetchUpcomingEvents(daysAhead: Int) -> ToolOutput {
        let calendar = Calendar.current
        let startDate = Date()
        let endDate = calendar.date(byAdding: .day, value: daysAhead, to: startDate)!

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        return formatEvents(events, title: "Upcoming Events (next \(daysAhead) days)")
    }

    private func fetchEventsInRange(startDateStr: String, endDateStr: String) -> ToolOutput {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        guard let startDate = formatter.date(from: startDateStr) else {
            return .error("Invalid start_date format. Use ISO 8601 format (e.g., '2024-01-15').")
        }

        guard let endDate = formatter.date(from: endDateStr) else {
            return .error("Invalid end_date format. Use ISO 8601 format (e.g., '2024-01-20').")
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        return formatEvents(events, title: "Events from \(startDateStr) to \(endDateStr)")
    }

    private func searchEvents(query: String, daysAhead: Int) -> ToolOutput {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -30, to: Date())!
        let endDate = calendar.date(byAdding: .day, value: daysAhead, to: Date())!

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)
            .filter { event in
                event.title?.localizedCaseInsensitiveContains(query) ?? false ||
                    event.location?.localizedCaseInsensitiveContains(query) ?? false ||
                    event.notes?.localizedCaseInsensitiveContains(query) ?? false
            }
            .sorted { $0.startDate < $1.startDate }

        return formatEvents(events, title: "Search Results for '\(query)'")
    }

    // MARK: - Formatting

    private func formatEvents(_ events: [EKEvent], title: String) -> ToolOutput {
        if events.isEmpty {
            return .success("\(title)\n\nNo events found.")
        }

        var output = "\(title)\n\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        for event in events {
            let timeStr: String
            if event.isAllDay {
                dateFormatter.timeStyle = .none
                timeStr = "\(dateFormatter.string(from: event.startDate)) (All Day)"
                dateFormatter.timeStyle = .short
            } else {
                timeStr = "\(dateFormatter.string(from: event.startDate)) - \(dateFormatter.string(from: event.endDate))"
            }

            output += "• \(event.title ?? "Untitled")\n"
            output += "  Time: \(timeStr)\n"
            if let location = event.location, !location.isEmpty {
                output += "  Location: \(location)\n"
            }
            if let calendar = event.calendar {
                output += "  Calendar: \(calendar.title)\n"
            }
            output += "\n"
        }

        return .success(output)
    }
}
