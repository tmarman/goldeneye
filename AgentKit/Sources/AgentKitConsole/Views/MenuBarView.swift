import AgentKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            StatusHeader()

            Divider()

            // Pending approvals (if any)
            if !appState.pendingApprovals.isEmpty {
                PendingApprovalsSection()
                Divider()
            }

            // Active tasks
            ActiveTasksSection()

            Divider()

            // Quick actions
            QuickActionsSection()
        }
        .frame(width: 320)
    }
}

// MARK: - Status Header

private struct StatusHeader: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("AgentKit")
                    .font(.headline)

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("v\(AgentKitVersion.string)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private var statusColor: Color {
        if let local = appState.localAgent {
            return local.status.color
        }
        return .secondary
    }

    private var statusText: String {
        if let local = appState.localAgent {
            switch local.status {
            case .connected: return "Connected"
            case .connecting: return "Connecting..."
            case .disconnected: return "Disconnected"
            case .error(let msg): return "Error: \(msg)"
            }
        }
        return "No Local Agent"
    }
}

// MARK: - Pending Approvals

private struct PendingApprovalsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pending Approvals")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(appState.pendingApprovals.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ForEach(appState.pendingApprovals.prefix(3)) { approval in
                ApprovalRow(approval: approval)
            }

            if appState.pendingApprovals.count > 3 {
                Text("+ \(appState.pendingApprovals.count - 3) more...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
        .padding(.bottom, 8)
    }
}

private struct ApprovalRow: View {
    let approval: PendingApproval
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(approval.toolName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(approval.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                Button {
                    // Approve
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

                Button {
                    // Deny
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - Active Tasks

private struct ActiveTasksSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Tasks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            if appState.activeTasks.isEmpty {
                Text("No active tasks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
            } else {
                ForEach(appState.activeTasks.prefix(5)) { task in
                    TaskRow(task: task)
                }
            }
        }
        .padding(.bottom, 8)
    }
}

private struct TaskRow: View {
    let task: TaskInfo

    var body: some View {
        HStack {
            stateIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(task.prompt)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(task.state.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch task.state {
        case .working:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .inputRequired:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Quick Actions

private struct QuickActionsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Button {
                appState.showNewTaskSheet = true
            } label: {
                Label("New Task", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Button {
                Task { await appState.connectToLocalAgent() }
            } label: {
                Label("Connect Local Agent", systemImage: "link")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .disabled(appState.localAgent?.status.isConnected == true)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit AgentKit", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
