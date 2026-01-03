import AgentKit
import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTask: TaskInfo?
    @State private var filter: TaskFilter = .all

    var body: some View {
        HSplitView {
            // Task list
            VStack(spacing: 0) {
                // Filter bar
                FilterBar(filter: $filter)

                Divider()

                // Task list
                List(selection: $selectedTask) {
                    ForEach(filteredTasks) { task in
                        TaskListRow(task: task)
                            .tag(task)
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 300)

            // Task detail
            if let task = selectedTask {
                TaskDetailView(task: task)
            } else {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No Task Selected",
                    message: "Select a task to view details"
                )
            }
        }
        .navigationTitle("Tasks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.showNewTaskSheet = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
            }
        }
    }

    private var filteredTasks: [TaskInfo] {
        let allTasks = appState.activeTasks + appState.recentTasks

        switch filter {
        case .all:
            return allTasks
        case .active:
            return allTasks.filter { !$0.state.isTerminal }
        case .completed:
            return allTasks.filter { $0.state == .completed }
        case .failed:
            return allTasks.filter { $0.state == .failed }
        }
    }
}

// MARK: - Filter Bar

enum TaskFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"
    case failed = "Failed"
}

struct FilterBar: View {
    @Binding var filter: TaskFilter

    var body: some View {
        HStack {
            ForEach(TaskFilter.allCases, id: \.rawValue) { option in
                Button {
                    filter = option
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(filter == option ? Color.accentColor : Color.clear)
                        .foregroundStyle(filter == option ? .white : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Task List Row

struct TaskListRow: View {
    let task: TaskInfo

    var body: some View {
        HStack(spacing: 12) {
            stateIndicator

            VStack(alignment: .leading, spacing: 4) {
                Text(task.prompt)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(task.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if task.state == .working {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateIndicator: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 10, height: 10)
    }

    private var stateColor: Color {
        switch task.state {
        case .completed: return .green
        case .failed: return .red
        case .working: return .blue
        case .inputRequired: return .orange
        default: return .secondary
        }
    }
}

// MARK: - Task Detail View

struct TaskDetailView: View {
    let task: TaskInfo
    @State private var showCancelConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Task Details")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Spacer()

                        TaskStateBadge(state: task.state)
                    }

                    Text(task.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Divider()

                // Prompt
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt")
                        .font(.headline)

                    Text(task.prompt)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Timeline
                VStack(alignment: .leading, spacing: 8) {
                    Text("Timeline")
                        .font(.headline)

                    TimelineRow(label: "Created", date: task.createdAt)

                    if let completed = task.completedAt {
                        TimelineRow(label: "Completed", date: completed)
                    }
                }

                // Messages
                if !task.messages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Messages")
                            .font(.headline)

                        ForEach(Array(task.messages.enumerated()), id: \.offset) { _, message in
                            MessageBubble(message: message)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !task.state.isTerminal {
                    Button {
                        showCancelConfirmation = true
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                }

                Button {
                    // Retry task
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .disabled(task.state != .failed)
            }
        }
        .confirmationDialog("Cancel Task?", isPresented: $showCancelConfirmation) {
            Button("Cancel Task", role: .destructive) {
                // Cancel the task
            }
        }
    }
}

struct TaskStateBadge: View {
    let state: TaskState

    var body: some View {
        Text(state.rawValue)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch state {
        case .completed: return .green
        case .failed: return .red
        case .working: return .blue
        case .inputRequired: return .orange
        case .cancelled: return .secondary
        default: return .secondary
        }
    }
}

struct TimelineRow: View {
    let label: String
    let date: Date

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(date, format: .dateTime)
        }
        .font(.subheadline)
    }
}

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .assistant {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .leading : .trailing) {
                Text(message.textContent)
                    .padding()
                    .background(message.role == .user ? Color.blue : Color.secondary.opacity(0.2))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if message.role == .user {
                Spacer(minLength: 40)
            }
        }
    }
}
