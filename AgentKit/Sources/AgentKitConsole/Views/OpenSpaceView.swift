import AgentKit
import SwiftUI

// MARK: - Open Space View

/// The Open Space view - a timeline/feed focused on quick capture and upcoming events
struct OpenSpaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var quickInput = ""
    @State private var selectedTab: OpenSpaceTab = .today
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Quick Capture Bar
            quickCaptureBar

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
        }
    }

    // MARK: - Quick Capture Bar

    private var quickCaptureBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            TextField("Quick capture... (notes, tasks, ideas)", text: $quickInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($isInputFocused)
                .onSubmit {
                    submitCapture()
                }

            if !quickInput.isEmpty {
                Button(action: submitCapture) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding()
        .background {
            if isInputFocused {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.05))
            }
        }
        .animation(.spring(response: 0.25), value: isInputFocused)
        .animation(.spring(response: 0.25), value: quickInput.isEmpty)
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
                Button("All Items") {}
                Button("Events Only") {}
                Button("Tasks Only") {}
                Button("Notes Only") {}
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title3)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Filtered Items

    private var filteredItems: [TimelineItemViewModel] {
        switch selectedTab {
        case .today:
            return appState.timelineItems.filter { Calendar.current.isDateInToday($0.timestamp) }
        case .upcoming:
            return appState.timelineItems.filter { $0.timestamp > Date() }
        case .activity:
            return appState.timelineItems.filter { $0.type == .activity }
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
    let item: TimelineItemViewModel
    var onTaskComplete: ((TimelineTask) -> Void)?

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

                        Button(action: {}) {
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
                        Button(action: {}) {
                            Label("Link to event", systemImage: "link")
                        }
                        Button(action: {}) {
                            Label("Create task", systemImage: "checklist")
                        }
                        Button(action: {}) {
                            Label("Move to space", systemImage: "folder")
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

