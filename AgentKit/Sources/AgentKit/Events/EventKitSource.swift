import EventKit
import Foundation

// MARK: - EventKit Event Source

/// Event source for Calendar events via EventKit.
///
/// Monitors the user's calendar and emits events for:
/// - Upcoming meetings (configurable lead time)
/// - Event changes (created, modified, deleted)
/// - Daily agenda at configurable time
///
/// This is the "heartbeat" for agents that need calendar awareness.
/// The Concierge agent typically subscribes to prepare for meetings.
public actor EventKitEventSource: EventSource {
    public nonisolated let id: EventSourceID
    public nonisolated let name: String
    public nonisolated let description: String
    public let supportedEventTypes: Set<TriggerEventType> = [
        .scheduled,
        .reminder,
        .deadline
    ]

    public private(set) var state: EventSourceState = .idle

    private let eventStore: EKEventStore
    private var eventContinuation: AsyncStream<TriggerEvent>.Continuation?
    private var monitorTask: Task<Void, Never>?
    private var notificationObserver: Any?

    // Configuration
    private var upcomingEventLeadTime: TimeInterval = 15 * 60  // 15 minutes
    private var dailyAgendaHour: Int = 8  // 8 AM
    private var monitoredCalendarIds: Set<String> = []
    private var processedEventIds: Set<String> = []  // Track already-notified events

    public var events: AsyncStream<TriggerEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    public init(
        id: EventSourceID = EventSourceID("eventkit"),
        name: String = "Calendar"
    ) {
        self.id = id
        self.name = name
        self.description = "Calendar events via EventKit"
        self.eventStore = EKEventStore()
    }

    // MARK: - Configuration

    /// Set lead time for upcoming event notifications (in seconds)
    public func setUpcomingLeadTime(_ seconds: TimeInterval) {
        upcomingEventLeadTime = seconds
    }

    /// Set hour for daily agenda (0-23)
    public func setDailyAgendaHour(_ hour: Int) {
        dailyAgendaHour = max(0, min(23, hour))
    }

    /// Monitor specific calendars (empty = all calendars)
    public func monitorCalendars(_ calendarIds: [String]) {
        monitoredCalendarIds = Set(calendarIds)
    }

    // MARK: - EventSource Protocol

    public func start() async throws {
        guard state == .idle || state == .stopped else { return }
        state = .starting

        // Request calendar access
        let granted = try await requestCalendarAccess()
        guard granted else {
            state = .error
            throw EventKitError.accessDenied
        }

        // Subscribe to EventKit notifications for real-time changes
        setupChangeNotifications()

        // Start monitoring task
        monitorTask = Task { [weak self] in
            await self?.runMonitorLoop()
        }

        state = .running
    }

    public func stop() async {
        state = .stopped
        monitorTask?.cancel()
        monitorTask = nil

        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }

        eventContinuation?.finish()
    }

    // MARK: - Calendar Access

    private func requestCalendarAccess() async throws -> Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            return try await eventStore.requestFullAccessToEvents()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    // MARK: - Change Notifications

    private func setupChangeNotifications() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: nil
        ) { [weak self] _ in
            Task {
                await self?.handleStoreChanged()
            }
        }
    }

    private func handleStoreChanged() async {
        // Emit a generic calendar change event
        let event = TriggerEvent(
            sourceId: id,
            type: .scheduled,
            payload: .json(["change_type": AnyCodable("calendar_updated")]),
            metadata: ["trigger": "store_change"]
        )
        eventContinuation?.yield(event)
    }

    // MARK: - Monitor Loop

    private func runMonitorLoop() async {
        state = .running

        while !Task.isCancelled && state == .running {
            // Check for upcoming events
            await checkUpcomingEvents()

            // Check if it's time for daily agenda
            await checkDailyAgenda()

            // Sleep for 1 minute before next check
            try? await Task.sleep(for: .seconds(60))
        }
    }

    private func checkUpcomingEvents() async {
        let now = Date()
        let leadTimeEnd = now.addingTimeInterval(upcomingEventLeadTime)

        // Get events in the upcoming window
        let calendars = getMonitoredCalendars()
        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: leadTimeEnd,
            calendars: calendars
        )

        let upcomingEvents = eventStore.events(matching: predicate)

        for ekEvent in upcomingEvents {
            // Skip if we've already notified about this event at this time
            let notificationKey = "\(ekEvent.eventIdentifier ?? "")-\(Int(ekEvent.startDate.timeIntervalSince1970 / 60))"
            guard !processedEventIds.contains(notificationKey) else { continue }

            // Create calendar event payload
            let calendarEvent = CalendarEvent(from: ekEvent)

            // Emit the event
            let triggerEvent = TriggerEvent(
                sourceId: id,
                type: .scheduled,
                payload: .schedule(SchedulePayload(
                    scheduleName: calendarEvent.title,
                    scheduledTime: calendarEvent.startTime,
                    context: [
                        "event_id": calendarEvent.id,
                        "calendar": ekEvent.calendar?.title ?? "Unknown",
                        "location": calendarEvent.location ?? "",
                        "duration_minutes": String(Int(calendarEvent.endTime.timeIntervalSince(calendarEvent.startTime) / 60))
                    ]
                )),
                priority: .high,
                metadata: [
                    "event_type": "upcoming_meeting",
                    "minutes_until": String(Int(ekEvent.startDate.timeIntervalSince(now) / 60))
                ]
            )
            eventContinuation?.yield(triggerEvent)

            // Mark as processed
            processedEventIds.insert(notificationKey)

            // Clean up old processed IDs (keep last hour)
            let oneHourAgo = Int(Date().addingTimeInterval(-3600).timeIntervalSince1970 / 60)
            processedEventIds = processedEventIds.filter { key in
                guard let timestamp = key.split(separator: "-").last,
                      let ts = Int(timestamp) else { return false }
                return ts > oneHourAgo
            }
        }
    }

    private func checkDailyAgenda() async {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: now)

        // Check if it's the daily agenda time (within the first minute of the hour)
        guard components.hour == dailyAgendaHour,
              let minute = components.minute, minute < 1 else { return }

        // Get today's events
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let calendars = getMonitoredCalendars()
        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: calendars
        )

        let todaysEvents = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        // Create agenda summary
        let eventSummaries = todaysEvents.map { event in
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "\(formatter.string(from: event.startDate)): \(event.title ?? "Untitled")"
        }

        let agenda = eventSummaries.isEmpty
            ? "No events scheduled for today."
            : eventSummaries.joined(separator: "\n")

        // Emit daily agenda event
        let triggerEvent = TriggerEvent(
            sourceId: id,
            type: .scheduled,
            payload: .text(agenda),
            priority: .normal,
            metadata: [
                "event_type": "daily_agenda",
                "event_count": String(todaysEvents.count),
                "date": ISO8601DateFormatter().string(from: now)
            ]
        )
        eventContinuation?.yield(triggerEvent)
    }

    private func getMonitoredCalendars() -> [EKCalendar]? {
        if monitoredCalendarIds.isEmpty {
            return nil  // All calendars
        }
        return eventStore.calendars(for: .event)
            .filter { monitoredCalendarIds.contains($0.calendarIdentifier) }
    }

    // MARK: - Public API

    /// Get today's events
    public func getTodaysEvents() async -> [CalendarEvent] {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let calendars = getMonitoredCalendars()
        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: calendars
        )

        return eventStore.events(matching: predicate)
            .map { CalendarEvent(from: $0) }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Get events in a date range
    public func getEvents(from start: Date, to end: Date) async -> [CalendarEvent] {
        let calendars = getMonitoredCalendars()
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars
        )

        return eventStore.events(matching: predicate)
            .map { CalendarEvent(from: $0) }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Get available calendars
    public func getCalendars() -> [CalendarInfo] {
        eventStore.calendars(for: .event).map { calendar in
            CalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                color: calendar.cgColor.map { NSColor(cgColor: $0)?.hexString } ?? nil,
                isDefault: calendar.calendarIdentifier == eventStore.defaultCalendarForNewEvents?.calendarIdentifier
            )
        }
    }
}

// MARK: - CalendarEvent Extension

/// Extension to create CalendarEvent from EKEvent
extension CalendarEvent {
    /// Create from EventKit EKEvent
    init(from ekEvent: EKEvent) {
        let attendeeList = ekEvent.attendees?.map { participant in
            Attendee(
                name: participant.name ?? participant.url.absoluteString,
                email: participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
                status: AttendeeStatus.from(ekStatus: participant.participantStatus)
            )
        } ?? []

        let notesList = ekEvent.notes.map { [EventNote(content: $0)] } ?? []

        self.init(
            id: ekEvent.eventIdentifier ?? UUID().uuidString,
            title: ekEvent.title ?? "Untitled",
            startTime: ekEvent.startDate,
            endTime: ekEvent.endDate,
            location: ekEvent.location,
            attendees: attendeeList,
            notes: notesList,
            calendarSource: ekEvent.calendar?.title
        )
    }
}

/// Extension to convert EKParticipantStatus to AttendeeStatus
extension AttendeeStatus {
    static func from(ekStatus: EKParticipantStatus) -> AttendeeStatus {
        switch ekStatus {
        case .accepted: return .accepted
        case .declined: return .declined
        case .tentative: return .tentative
        case .pending, .unknown, .delegated, .completed, .inProcess:
            return .pending
        @unknown default:
            return .pending
        }
    }
}

// MARK: - Calendar Info

/// Information about a calendar
public struct CalendarInfo: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let color: String?
    public let isDefault: Bool
}

// MARK: - Errors

public enum EventKitError: Error, LocalizedError {
    case accessDenied
    case eventNotFound
    case calendarNotFound

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access was denied. Please enable in System Preferences > Security & Privacy > Privacy > Calendars"
        case .eventNotFound:
            return "The requested event was not found"
        case .calendarNotFound:
            return "The requested calendar was not found"
        }
    }
}

// MARK: - NSColor Extension

#if canImport(AppKit)
import AppKit

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
#endif
