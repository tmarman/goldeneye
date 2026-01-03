import AgentKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Status cards
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 300))],
                    spacing: 16
                ) {
                    StatusCard(
                        title: "Active Tasks",
                        value: "\(appState.activeTasks.count)",
                        icon: "list.bullet.rectangle",
                        color: .blue
                    )

                    StatusCard(
                        title: "Pending Approvals",
                        value: "\(appState.pendingApprovals.count)",
                        icon: "checkmark.shield",
                        color: appState.pendingApprovals.isEmpty ? .green : .orange
                    )

                    StatusCard(
                        title: "Connected Agents",
                        value: "\(connectedAgentCount)",
                        icon: "point.3.connected.trianglepath.dotted",
                        color: .purple
                    )

                    StatusCard(
                        title: "Local Agent",
                        value: localAgentStatus,
                        icon: "desktopcomputer",
                        color: appState.localAgent?.status.isConnected == true ? .green : .secondary
                    )
                }

                // Pending approvals section
                if !appState.pendingApprovals.isEmpty {
                    DashboardSection(title: "Pending Approvals", icon: "exclamationmark.triangle.fill") {
                        VStack(spacing: 12) {
                            ForEach(appState.pendingApprovals) { approval in
                                ApprovalCard(approval: approval)
                            }
                        }
                    }
                }

                // Recent activity
                DashboardSection(title: "Recent Activity", icon: "clock") {
                    if appState.activeTasks.isEmpty && appState.recentTasks.isEmpty {
                        EmptyStateView(
                            icon: "tray",
                            title: "No Recent Activity",
                            message: "Submit a task to get started"
                        )
                    } else {
                        VStack(spacing: 8) {
                            ForEach(appState.activeTasks) { task in
                                ActivityRow(task: task)
                            }
                            ForEach(appState.recentTasks.prefix(5)) { task in
                                ActivityRow(task: task)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appState.connectToLocalAgent() }
                } label: {
                    Label("Connect", systemImage: "link")
                }
                .disabled(appState.localAgent?.status.isConnected == true)
            }
        }
    }

    private var connectedAgentCount: Int {
        appState.connectedAgents.filter { $0.status.isConnected }.count
            + (appState.localAgent?.status.isConnected == true ? 1 : 0)
    }

    private var localAgentStatus: String {
        switch appState.localAgent?.status {
        case .connected: return "Online"
        case .connecting: return "Connecting"
        case .disconnected: return "Offline"
        case .error: return "Error"
        case .none: return "N/A"
        }
    }
}

// MARK: - Status Card

struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.semibold)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Dashboard Section

struct DashboardSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)

            content()
        }
    }
}

// MARK: - Approval Card

struct ApprovalCard: View {
    let approval: PendingApproval
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Risk indicator
            RiskBadge(level: approval.riskLevel)

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(approval.toolName)
                    .font(.headline)

                Text(approval.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !approval.parameters.isEmpty {
                    HStack {
                        ForEach(Array(approval.parameters.prefix(2)), id: \.key) { key, value in
                            Text("\(key): \(value)")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()

            // Actions
            VStack(spacing: 8) {
                Button {
                    // Approve action
                } label: {
                    Text("Approve")
                        .frame(width: 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    // Deny action
                } label: {
                    Text("Deny")
                        .frame(width: 80)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct RiskBadge: View {
    let level: RiskLevel

    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(level.rawValue.uppercased())
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
        .frame(width: 50)
    }

    private var icon: String {
        switch level {
        case .low: return "shield"
        case .medium: return "shield.lefthalf.filled"
        case .high: return "shield.fill"
        case .critical: return "exclamationmark.shield.fill"
        }
    }

    private var color: Color {
        switch level {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let task: TaskInfo

    var body: some View {
        HStack {
            stateIcon
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.prompt)
                    .lineLimit(1)

                Text(task.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(task.state.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(stateColor.opacity(0.1))
                .foregroundStyle(stateColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch task.state {
        case .working:
            ProgressView()
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .inputRequired:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
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

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
