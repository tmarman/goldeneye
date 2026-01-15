import Combine
import EventKit
import Foundation
import SwiftUI

/// Service for accessing the user's calendar using EventKit
@MainActor
public final class CalendarService: ObservableObject {
    // MARK: - Singleton

    public static let shared = CalendarService()

    // MARK: - Published Properties

    @Published public private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published public private(set) var calendars: [EKCalendar] = []
    @Published public private(set) var todayEvents: [LocalCalendarEvent] = []
    @Published public private(set) var upcomingEvents: [LocalCalendarEvent] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: String?

    // MARK: - Private Properties

    private let eventStore = EKEventStore()
    private var refreshTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Check current authorization status
    public func checkAuthorizationStatus() {
        if #available(macOS 14.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }

    /// Request calendar access
    public func requestAccess() async -> Bool {
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }

            checkAuthorizationStatus()

            if granted {
                await loadCalendars()
                await refreshEvents()
            }

            return granted
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Calendar Loading

    /// Load available calendars
    public func loadCalendars() async {
        calendars = eventStore.calendars(for: .event)
    }

    // MARK: - Event Fetching

    /// Refresh events for today and upcoming week
    public func refreshEvents() async {
        guard authorizationStatus == .fullAccess || authorizationStatus == .authorized else {
            return
        }

        isLoading = true
        lastError = nil

        let calendar = Calendar.current
        let now = Date()

        // Today's events
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        // Upcoming week events
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: todayStart)!

        do {
            // Fetch today's events
            let todayPredicate = eventStore.predicateForEvents(
                withStart: todayStart,
                end: todayEnd,
                calendars: nil
            )
            let ekTodayEvents = eventStore.events(matching: todayPredicate)
            todayEvents = ekTodayEvents.map { LocalCalendarEvent(from: $0) }
                .sorted { $0.startDate < $1.startDate }

            // Fetch upcoming events (excluding today)
            let upcomingPredicate = eventStore.predicateForEvents(
                withStart: todayEnd,
                end: weekEnd,
                calendars: nil
            )
            let ekUpcomingEvents = eventStore.events(matching: upcomingPredicate)
            upcomingEvents = ekUpcomingEvents.map { LocalCalendarEvent(from: $0) }
                .sorted { $0.startDate < $1.startDate }

        }

        isLoading = false
    }

    /// Start automatic refresh (every 5 minutes)
    public func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshEvents()
                try? await Task.sleep(for: .seconds(300)) // 5 minutes
            }
        }
    }

    /// Stop automatic refresh
    public func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Event Creation

    /// Create a new calendar event
    public func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String? = nil,
        calendar: EKCalendar? = nil
    ) async throws -> LocalCalendarEvent {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.calendar = calendar ?? eventStore.defaultCalendarForNewEvents

        try eventStore.save(event, span: .thisEvent)
        await refreshEvents()

        return LocalCalendarEvent(from: event)
    }
}

// MARK: - Calendar Event Model

/// Local calendar event from EventKit (distinct from AgentKit.CalendarEvent)
public struct LocalCalendarEvent: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?
    public let calendarTitle: String
    public let calendarColor: Color
    public let attendees: [String]
    public let url: URL?
    public let hasAlarms: Bool

    public init(from event: EKEvent) {
        self.id = event.eventIdentifier ?? UUID().uuidString
        self.title = event.title ?? "Untitled Event"
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.isAllDay = event.isAllDay
        self.location = event.location
        self.notes = event.notes
        self.calendarTitle = event.calendar?.title ?? "Calendar"
        self.calendarColor = Color(cgColor: event.calendar?.cgColor ?? CGColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1))
        self.attendees = event.attendees?.compactMap { $0.name } ?? []
        self.url = event.url
        self.hasAlarms = event.hasAlarms
    }

    /// Formatted time range string
    public var timeRange: String {
        if isAllDay {
            return "All Day"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)

        return "\(start) - \(end)"
    }

    /// Duration in minutes
    public var durationMinutes: Int {
        Int(endDate.timeIntervalSince(startDate) / 60)
    }

    /// Check if event is happening now
    public var isHappeningNow: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }

    /// Check if event starts within the next hour
    public var startsWithinHour: Bool {
        let now = Date()
        let hourFromNow = now.addingTimeInterval(3600)
        return startDate > now && startDate <= hourFromNow
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: LocalCalendarEvent, rhs: LocalCalendarEvent) -> Bool {
        lhs.id == rhs.id
    }
}

