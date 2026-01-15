import AgentKit
import EventKit
import SwiftUI

// MARK: - Open Space View

/// The Open Space view - a timeline/feed focused on quick capture and upcoming events
struct OpenSpaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var quickInput = ""
    @State private var selectedTab: OpenSpaceTab = .today
    @State private var itemFilter: TimelineFilter = .all
    @State private var currentMeeting: EKEvent?
    @State private var agentSuggestions: [AgentSuggestion] = []
    @State private var isProcessingSuggestions = false
    @FocusState private var isInputFocused: Bool

    private let eventStore = EKEventStore()

    enum TimelineFilter: String, CaseIterable {
        case all = "All Items"
        case events = "Events Only"
        case tasks = "Tasks Only"
        case notes = "Notes Only"
    }

    struct AgentSuggestion: Identifiable {
        let id = UUID()
        let icon: String
        let action: String
        let detail: String?
        let color: Color

        static func note() -> AgentSuggestion {
            AgentSuggestion(icon: "note.text", action: "Save as note", detail: nil, color: .blue)
        }

        static func tasks(count: Int) -> AgentSuggestion {
            AgentSuggestion(icon: "checklist", action: "Extract \(count) task\(count == 1 ? "" : "s")", detail: nil, color: .orange)
        }

        static func event(title: String) -> AgentSuggestion {
            AgentSuggestion(icon: "calendar.badge.plus", action: "Create event", detail: title, color: .green)
        }

        static func connection(to: String) -> AgentSuggestion {
            AgentSuggestion(icon: "link", action: "Relates to", detail: to, color: .purple)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Active meeting banner (if any)
            if let meeting = currentMeeting {
                activeMeetingBanner(meeting)
            }

            // Quick Capture Card - bigger, post-it style
            quickCaptureCard

            Divider()

            // Tab selector
            tabSelector

            Divider()

            // Timeline content
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems) { item in
                        TimelineItemRow(item: item, onTaskComplete: { handleTaskComplete($0) })
                        Divider()
                            .padding(.leading, 60)
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Open Space")
        .task {
            await appState.loadTimelineItems()
            await checkForActiveMeeting()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusQuickCapture)) { _ in
            isInputFocused = true
        }
    }

    // MARK: - Active Meeting Banner

    @ViewBuilder
    private func activeMeetingBanner(_ meeting: EKEvent) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(cgColor: meeting.calendar.cgColor))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text("In meeting")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(meeting.title ?? "Untitled Meeting")
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            Text(meetingTimeRemaining(meeting))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Link notes") {
                // Link current quick capture to this meeting
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color(cgColor: meeting.calendar.cgColor).opacity(0.1))
        .overlay(
            Rectangle()
                .fill(Color(cgColor: meeting.calendar.cgColor))
                .frame(width: 4),
            alignment: .leading
        )
    }

    private func meetingTimeRemaining(_ meeting: EKEvent) -> String {
        let remaining = meeting.endDate.timeIntervalSince(Date())
        let minutes = Int(remaining / 60)
        if minutes < 60 {
            return "\(minutes)m left"
        } else {
            return "\(minutes / 60)h \(minutes % 60)m left"
        }
    }

    // MARK: - Quick Capture Card (Whiteboard style)

    private var quickCaptureCard: some View {
        VStack(spacing: 0) {
            // Canvas area
            VStack(spacing: 12) {
                captureTextArea

                // Agent suggestions (appear as user types)
                if !agentSuggestions.isEmpty {
                    agentSuggestionsView
                }
            }
            .padding(16)

            Divider()

            // Action bar
            captureActionBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(captureCardBackground)
        .overlay(captureCardBorder)
        .padding()
        .animation(.spring(response: 0.25), value: isInputFocused)
        .animation(.spring(response: 0.3), value: agentSuggestions.count)
        .onChange(of: quickInput) { _, newValue in
            Task {
                await updateAgentSuggestions(for: newValue)
            }
        }
    }

    @ViewBuilder
    private var agentSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Agent will:")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                if isProcessingSuggestions {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(agentSuggestions) { suggestion in
                    HStack(spacing: 8) {
                        Image(systemName: suggestion.icon)
                            .font(.caption)
                            .foregroundStyle(suggestion.color)
                            .frame(width: 16)

                        Text(suggestion.action)
                            .font(.caption)

                        if let detail = suggestion.detail {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(suggestion.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var captureTextArea: some View {
        ZStack(alignment: .topLeading) {
            if quickInput.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start writing, drawing, or brainstorming...")
                        .font(.body)
                        .foregroundStyle(.tertiary)

                    Text("The agent will suggest what to do with your input")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
                .allowsHitTesting(false)
                .padding(.horizontal, 5)
                .padding(.top, 8)
            }

            TextEditor(text: $quickInput)
                .font(.body)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 120, maxHeight: 300)
                .focused($isInputFocused)
        }
    }

    @ViewBuilder
    private var captureActionBar: some View {
        HStack(spacing: 12) {
            // Future: Voice input, drawing tools
            HStack(spacing: 8) {
                Button(action: {}) {
                    Image(systemName: "mic")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(true)
                .opacity(0.5)
                .help("Voice input coming soon")

                Button(action: {}) {
                    Image(systemName: "scribble")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(true)
                .opacity(0.5)
                .help("Drawing coming soon on iPad")
            }

            Spacer()

            // Submit button
            Button(action: submitCapture) {
                HStack(spacing: 6) {
                    if agentSuggestions.isEmpty {
                        Text("Submit")
                    } else {
                        Text("Submit")
                        Text("·")
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(agentSuggestions.count) action\(agentSuggestions.count == 1 ? "" : "s")")
                            .font(.caption)
                    }
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(quickInput.isEmpty ? Color.secondary.opacity(0.2) : Color.accentColor)
                .foregroundColor(quickInput.isEmpty ? .secondary : .white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(quickInput.isEmpty)
        }
    }

    @ViewBuilder
    private var captureCardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(isInputFocused ? Color.accentColor.opacity(0.05) : Color(.controlBackgroundColor).opacity(0.5))
            .shadow(color: .black.opacity(0.05), radius: isInputFocused ? 8 : 0, y: 2)
    }

    @ViewBuilder
    private var captureCardBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(isInputFocused ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
    }

    // MARK: - Agent Suggestions Logic

    private func updateAgentSuggestions(for text: String) async {
        guard !text.isEmpty else {
            agentSuggestions = []
            return
        }

        // Debounce - wait a moment before processing
        try? await Task.sleep(for: .milliseconds(500))

        isProcessingSuggestions = true
        defer { isProcessingSuggestions = false }

        // Simple heuristic analysis (in production, call LLM orchestrator)
        var suggestions: [AgentSuggestion] = []

        // Always save as note
        suggestions.append(.note())

        // Detect tasks (lines starting with -, [], *, or containing words like "todo", "task")
        let lines = text.components(separatedBy: .newlines)
        let taskLines = lines.filter { line in
            line.trimmingCharacters(in: .whitespaces).starts(with: "-") ||
            line.trimmingCharacters(in: .whitespaces).starts(with: "*") ||
            line.contains("[]") ||
            line.contains("[ ]") ||
            line.lowercased().contains("todo") ||
            line.lowercased().contains("task")
        }

        if !taskLines.isEmpty {
            suggestions.append(.tasks(count: taskLines.count))
        }

        // Detect calendar events (mentions of dates, times, meetings)
        let eventKeywords = ["meeting", "call", "appointment", "tomorrow", "next week", "friday", "monday"]
        if eventKeywords.contains(where: { text.lowercased().contains($0) }) {
            suggestions.append(.event(title: "Suggested from context"))
        }

        // Detect potential connections (mentions of @ or project names)
        if text.contains("@") || text.lowercased().contains("project") {
            suggestions.append(.connection(to: "Related conversations"))
        }

        agentSuggestions = suggestions
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(OpenSpaceTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                        Text(tab.title)
                    }
                    .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.15))
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Filter button
            Menu {
                ForEach(TimelineFilter.allCases, id: \.self) { filter in
                    Button(action: { itemFilter = filter }) {
                        HStack {
                            Text(filter.rawValue)
                            if itemFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: itemFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .font(.title3)
                    .foregroundStyle(itemFilter == .all ? Color.secondary : Color.accentColor)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Filtered Items

    private var filteredItems: [TimelineItemViewModel] {
        var items: [TimelineItemViewModel]

        // Filter by tab first
        switch selectedTab {
        case .today:
            items = appState.timelineItems.filter { Calendar.current.isDateInToday($0.timestamp) }
        case .upcoming:
            items = appState.timelineItems.filter { $0.timestamp > Date() }
        case .activity:
            items = appState.timelineItems.filter { $0.type == .activity }
        }

        // Then apply type filter
        switch itemFilter {
        case .all:
            return items
        case .events:
            return items.filter { $0.type == .event }
        case .tasks:
            return items.filter { $0.type == .task }
        case .notes:
            return items.filter { $0.type == .note }
        }
    }

    // MARK: - Actions

    private func submitCapture() {
        guard !quickInput.isEmpty else { return }

        let captureText = quickInput
        quickInput = ""
        isInputFocused = false

        // Submit to AppState for real agent processing
        Task {
            await appState.submitCapture(captureText)
        }
    }

    private func handleTaskComplete(_ task: TimelineTask) {
        // Mark task as complete in timeline
        if let index = appState.timelineItems.firstIndex(where: { $0.linkedTask?.id == task.id }) {
            appState.timelineItems[index].linkedTask?.isCompleted = true
        }
    }

    private func checkForActiveMeeting() async {
        // Request calendar access
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            guard granted else { return }

            // Find current meeting
            let now = Date()
            let predicate = eventStore.predicateForEvents(
                withStart: now.addingTimeInterval(-3600), // 1 hour ago
                end: now.addingTimeInterval(3600), // 1 hour from now
                calendars: nil
            )

            let events = eventStore.events(matching: predicate)
            currentMeeting = events.first { event in
                event.startDate <= now && event.endDate > now
            }
        } catch {
            // Calendar access denied or error
            print("Calendar access error: \(error)")
        }
    }
}

// MARK: - Suggestion Chip

struct SuggestionChip: View {
    let icon: String
    let text: String
    var action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(text)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.1), in: Capsule())
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab Enum

enum OpenSpaceTab: String, CaseIterable {
    case today
    case upcoming
    case activity

    var title: String {
        switch self {
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .activity: return "Activity"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .upcoming: return "calendar"
        case .activity: return "bolt"
        }
    }
}

// MARK: - Timeline Item Row

struct TimelineItemRow: View {
    @EnvironmentObject private var appState: AppState
    let item: TimelineItemViewModel
    var onTaskComplete: ((TimelineTask) -> Void)?
    var onSnooze: ((TimelineTask) -> Void)?
    var onCreateTask: ((TimelineItemViewModel) -> Void)?

    @State private var isHovered = false
    @State private var pulsePhase = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Enhanced time column
            VStack(spacing: 6) {
                if let time = item.displayTime {
                    Text(time)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(isHovered ? .primary : .secondary)
                }

                // Enhanced timeline dot with pulse
                ZStack {
                    if item.isProcessing {
                        Circle()
                            .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                            .frame(width: 16, height: 16)
                            .scaleEffect(pulsePhase ? 1.5 : 1.0)
                            .opacity(pulsePhase ? 0 : 0.8)
                    }

                    Circle()
                        .fill(item.isProcessing ? Color.orange : item.iconColor.opacity(isHovered ? 0.5 : 0.3))
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle()
                                .stroke(item.iconColor.opacity(0.1), lineWidth: isHovered ? 2 : 0)
                                .frame(width: 16, height: 16)
                        }
                }
            }
            .frame(width: 50)

            // Content with hover background
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    // Icon with background
                    ZStack {
                        Circle()
                            .fill(item.iconColor.opacity(0.12))
                            .frame(width: 28, height: 28)

                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(item.iconColor)
                    }

                    Text(item.title)
                        .font(.body.weight(.medium))

                    Spacer()

                    if item.isProcessing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                            Text("Processing")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Event card if applicable
                if item.type == .event, let event = item.eventDetails {
                    EventCard(event: event)
                        .padding(.top, 4)
                }

                // Enhanced task actions
                if item.type == .task, let task = item.linkedTask {
                    HStack(spacing: 8) {
                        Button(action: { onTaskComplete?(task) }) {
                            HStack(spacing: 4) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                Text(task.isCompleted ? "Completed" : "Mark complete")
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                task.isCompleted ? Color.secondary.opacity(0.1) : Color.green.opacity(0.1),
                                in: Capsule()
                            )
                            .foregroundStyle(task.isCompleted ? Color.secondary : Color.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(task.isCompleted)

                        Menu {
                            Button("1 hour") { onSnooze?(task) }
                            Button("Tomorrow morning") { onSnooze?(task) }
                            Button("Next week") { onSnooze?(task) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 12))
                                Text("Snooze")
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.1), in: Capsule())
                            .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }

                // Enhanced note actions
                if item.type == .note {
                    HStack(spacing: 8) {
                        ActionButton(icon: "checklist", label: "Create task") {
                            onCreateTask?(item)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.primary.opacity(0.03) : .clear)
            )
        }
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onAppear {
            if item.isProcessing {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulsePhase = true
                }
            }
        }
    }
}

// Small action button for timeline items
private struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isHovered ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1),
                in: Capsule()
            )
            .foregroundStyle(isHovered ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Event Card

struct EventCard: View {
    let event: EventDetails
    @State private var isHovered = false
    @State private var showNoteInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            eventHeader

            if !event.attendees.isEmpty {
                attendeesSection
            }

            if let notes = event.notes, !notes.isEmpty {
                notesSection(notes)
            }

            Divider().opacity(0.5)

            addNoteButton
        }
        .padding(14)
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, y: 2)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var eventHeader: some View {
        HStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 3, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(event.timeRange)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var attendeesSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            HStack(spacing: -8) {
                ForEach(event.attendees.prefix(3), id: \.self) { attendee in
                    attendeeBubble(attendee)
                }
                if event.attendees.count > 3 {
                    Text("+\(event.attendees.count - 3)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }
            }
        }
    }

    private func attendeeBubble(_ attendee: String) -> some View {
        ZStack {
            Circle()
                .fill(event.color.opacity(0.2))
                .frame(width: 24, height: 24)

            Circle()
                .stroke(Color(.controlBackgroundColor), lineWidth: 2)
                .frame(width: 24, height: 24)

            Text(String(attendee.prefix(1)))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(event.color)
        }
    }

    private func notesSection(_ notes: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "note.text")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            Text(notes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var addNoteButton: some View {
        Button(action: { showNoteInput = true }) {
            HStack(spacing: 6) {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 12))
                Text("Add note to this event...")
                    .font(.caption)
            }
            .foregroundStyle(isHovered ? event.color : Color.secondary.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? event.color.opacity(0.08) : Color(.controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(event.color.opacity(0.06))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                isHovered ? event.color.opacity(0.4) : event.color.opacity(0.2),
                lineWidth: isHovered ? 1.5 : 1
            )
    }

    private var cardShadowColor: Color {
        isHovered ? event.color.opacity(0.1) : .clear
    }

    private var cardShadowRadius: CGFloat {
        isHovered ? 8 : 0
    }
}

// MARK: - View Models

struct TimelineItemViewModel: Identifiable {
    let id: UUID
    var type: TimelineItemType
    var title: String
    var subtitle: String?
    var timestamp: Date
    var icon: String
    var iconColor: Color
    var isProcessing: Bool = false
    var eventDetails: EventDetails?
    var linkedTask: TimelineTask?
    var processingResult: ProcessingResult?

    enum TimelineItemType {
        case event
        case note
        case task
        case reminder
        case activity
    }

    init(
        id: UUID = UUID(),
        type: TimelineItemType,
        title: String,
        subtitle: String? = nil,
        timestamp: Date,
        icon: String,
        iconColor: Color,
        isProcessing: Bool = false,
        eventDetails: EventDetails? = nil,
        linkedTask: TimelineTask? = nil,
        processingResult: ProcessingResult? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
        self.icon = icon
        self.iconColor = iconColor
        self.isProcessing = isProcessing
        self.eventDetails = eventDetails
        self.linkedTask = linkedTask
        self.processingResult = processingResult
    }

    var displayTime: String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: timestamp)
    }
}

struct EventDetails {
    let title: String
    let timeRange: String
    let attendees: [String]
    let notes: String?
    let color: Color
}

// MARK: - Notification Names

extension Notification.Name {
    static let focusQuickCapture = Notification.Name("focusQuickCapture")
}

