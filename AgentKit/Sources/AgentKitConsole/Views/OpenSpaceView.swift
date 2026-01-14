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
    @State private var captureMode: CaptureMode = .note
    @FocusState private var isInputFocused: Bool

    private let eventStore = EKEventStore()

    enum TimelineFilter: String, CaseIterable {
        case all = "All Items"
        case events = "Events Only"
        case tasks = "Tasks Only"
        case notes = "Notes Only"
    }

    enum CaptureMode: String, CaseIterable {
        case note = "Note"
        case brainstorm = "Brainstorm"
        case transcribe = "Transcribe"

        var icon: String {
            switch self {
            case .note: return "square.and.pencil"
            case .brainstorm: return "lightbulb.max"
            case .transcribe: return "waveform"
            }
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

    // MARK: - Quick Capture Card (Post-it style)

    private var quickCaptureCard: some View {
        VStack(spacing: 12) {
            captureModeSelector
            captureTextArea
            captureActionBar
        }
        .padding(16)
        .background(captureCardBackground)
        .overlay(captureCardBorder)
        .padding()
        .animation(.spring(response: 0.25), value: isInputFocused)
        .animation(.spring(response: 0.25), value: captureMode)
    }

    @ViewBuilder
    private var captureModeSelector: some View {
        HStack(spacing: 4) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                CaptureModeButton(
                    mode: mode,
                    isSelected: captureMode == mode,
                    action: { captureMode = mode }
                )
            }

            Spacer()

            if captureMode == .transcribe {
                recordButton
            }
        }
    }

    @ViewBuilder
    private var recordButton: some View {
        Button(action: startTranscription) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Record")
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.1), in: Capsule())
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var captureTextArea: some View {
        TextEditor(text: $quickInput)
            .font(.body)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .frame(minHeight: 100, maxHeight: 200)
            .focused($isInputFocused)
            .overlay(alignment: .topLeading) {
                if quickInput.isEmpty {
                    Text(capturePlaceholder)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
            }
    }

    @ViewBuilder
    private var captureActionBar: some View {
        HStack {
            captureSuggestions
            Spacer()
            captureSubmitButton
        }
    }

    @ViewBuilder
    private var captureSuggestions: some View {
        if !quickInput.isEmpty {
            HStack(spacing: 8) {
                if quickInput.contains("@") || quickInput.contains("action") {
                    SuggestionChip(icon: "checklist", text: "Create task")
                }
                if quickInput.contains("tomorrow") || quickInput.contains("next week") {
                    SuggestionChip(icon: "calendar.badge.plus", text: "Add reminder")
                }
            }
        }
    }

    @ViewBuilder
    private var captureSubmitButton: some View {
        Button(action: submitCapture) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                Text("Capture")
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(quickInput.isEmpty ? Color.secondary.opacity(0.2) : Color.accentColor)
            .foregroundColor(quickInput.isEmpty ? .secondary : .white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(quickInput.isEmpty)
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

    private var capturePlaceholder: String {
        switch captureMode {
        case .note:
            return "Jot down notes, ideas, or tasks..."
        case .brainstorm:
            return "Brain dump your thoughts here..."
        case .transcribe:
            return "Press Record to start transcribing..."
        }
    }

    private func startTranscription() {
        // TODO: Start SpeechAnalyzer transcription
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

// MARK: - Capture Mode Button

struct CaptureModeButton: View {
    let mode: OpenSpaceView.CaptureMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                Text(mode.rawValue)
            }
            .font(.caption.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.15))
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time column
            VStack {
                if let time = item.displayTime {
                    Text(time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Timeline dot
                Circle()
                    .fill(item.isProcessing ? Color.orange : item.iconColor.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .overlay {
                        if item.isProcessing {
                            Circle()
                                .stroke(Color.orange, lineWidth: 2)
                                .scaleEffect(1.5)
                                .opacity(0)
                                .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: item.isProcessing)
                        }
                    }
            }
            .frame(width: 50)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: item.icon)
                        .foregroundStyle(item.iconColor)

                    Text(item.title)
                        .font(.body.weight(.medium))

                    Spacer()

                    if item.isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
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

                // Task actions if applicable
                if item.type == .task, let task = item.linkedTask {
                    HStack(spacing: 12) {
                        Button(action: { onTaskComplete?(task) }) {
                            Label(task.isCompleted ? "Completed" : "Complete", systemImage: task.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(task.isCompleted ? Color.secondary : Color.green)
                        .disabled(task.isCompleted)

                        Menu {
                            Button("1 hour") { onSnooze?(task) }
                            Button("Tomorrow morning") { onSnooze?(task) }
                            Button("Next week") { onSnooze?(task) }
                        } label: {
                            Label("Snooze", systemImage: "clock")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                    }
                    .font(.caption)
                    .padding(.top, 4)
                }

                // Note actions
                if item.type == .note {
                    HStack(spacing: 12) {
                        Button(action: {
                            // Show link to event picker
                            // For now, this would open a sheet to select an event
                        }) {
                            Label("Link to event", systemImage: "link")
                        }
                        Button(action: {
                            onCreateTask?(item)
                        }) {
                            Label("Create task", systemImage: "checklist")
                        }
                        Menu {
                            ForEach(appState.workspace.folders) { folder in
                                Button(folder.name) {
                                    // Move note to this folder
                                }
                            }
                            Divider()
                            Button("New Folder...") {
                                // Create new folder with this note
                            }
                        } label: {
                            Label("Move to folder", systemImage: "folder")
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal)
        .contentShape(Rectangle())
    }
}

// MARK: - Event Card

struct EventCard: View {
    let event: EventDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(event.timeRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !event.attendees.isEmpty {
                HStack(spacing: -6) {
                    ForEach(event.attendees.prefix(3), id: \.self) { attendee in
                        Circle()
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Text(String(attendee.prefix(1)))
                                    .font(.caption2.weight(.medium))
                            }
                    }
                    if event.attendees.count > 3 {
                        Text("+\(event.attendees.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }
                }
            }

            if let notes = event.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Quick note input for this event
            HStack {
                Image(systemName: "plus.bubble")
                    .foregroundStyle(.secondary)
                Text("Add note to this event...")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .padding(8)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(event.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(event.color.opacity(0.3), lineWidth: 1)
        )
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

