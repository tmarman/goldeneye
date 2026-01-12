import AgentKit
import SwiftUI

struct ApprovalsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedApproval: PendingApproval?
    @State private var historyFilter: ApprovalHistoryFilter = .all

    var body: some View {
        HSplitView {
            // Pending approvals list
            VStack(spacing: 0) {
                // Section header
                HStack {
                    Text("Pending")
                        .font(.headline)

                    Spacer()

                    if !appState.pendingApprovals.isEmpty {
                        Button("Approve All") {
                            Task { await appState.approveAllPending() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()

                Divider()

                if appState.pendingApprovals.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.shield",
                        title: "No Pending Approvals",
                        message: "All caught up!"
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List(selection: $selectedApproval) {
                        ForEach(appState.pendingApprovals) { approval in
                            ApprovalListRow(approval: approval)
                                .tag(approval)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 300)

            // Detail/action panel
            if let approval = selectedApproval {
                ApprovalDetailView(approval: approval)
            } else {
                VStack {
                    EmptyStateView(
                        icon: "hand.raised",
                        title: "Select an Approval",
                        message: "Review and approve or deny tool executions"
                    )

                    // Keyboard shortcuts hint
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard Shortcuts")
                            .font(.headline)

                        ShortcutRow(keys: "⌘ ⏎", action: "Approve selected")
                        ShortcutRow(keys: "⌘ ⌫", action: "Deny selected")
                        ShortcutRow(keys: "⇧ ⌘ A", action: "Approve all pending")
                    }
                    .padding()
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                }
            }
        }
        .navigationTitle("Approvals")
    }
}

// MARK: - Approval List Row

struct ApprovalListRow: View {
    let approval: PendingApproval

    var body: some View {
        HStack(spacing: 12) {
            // Risk indicator
            RiskIndicator(level: approval.riskLevel)

            VStack(alignment: .leading, spacing: 4) {
                Text(approval.toolName)
                    .fontWeight(.medium)

                Text(approval.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(approval.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct RiskIndicator: View {
    let level: RiskLevel

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
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

// MARK: - Approval Detail View

struct ApprovalDetailView: View {
    let approval: PendingApproval
    @EnvironmentObject private var appState: AppState
    @State private var showModifySheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(approval.toolName)
                            .font(.title)
                            .fontWeight(.bold)

                        Text(approval.description)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    RiskBadgeLarge(level: approval.riskLevel)
                }

                Divider()

                // Parameters
                VStack(alignment: .leading, spacing: 12) {
                    Text("Parameters")
                        .font(.headline)

                    if approval.parameters.isEmpty {
                        Text("No parameters")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(approval.parameters.sorted(by: { $0.key < $1.key })), id: \.key) {
                                key,
                                value in
                                ParameterRow(key: key, value: value)
                            }
                        }
                    }
                }

                // Context
                VStack(alignment: .leading, spacing: 12) {
                    Text("Context")
                        .font(.headline)

                    HStack {
                        Label("Task", systemImage: "list.bullet.rectangle")
                        Spacer()
                        Text(approval.taskId)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Agent", systemImage: "brain")
                        Spacer()
                        Text(approval.agentId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Requested", systemImage: "clock")
                        Spacer()
                        Text(approval.createdAt, format: .dateTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Actions
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        Button {
                            Task { await appState.denyRequest(approval) }
                        } label: {
                            Label("Deny", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.delete, modifiers: .command)

                        Button {
                            showModifySheet = true
                        } label: {
                            Label("Modify", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await appState.approveRequest(approval) }
                        } label: {
                            Label("Approve", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .keyboardShortcut(.return, modifiers: .command)
                    }

                    // Quick approve options
                    HStack {
                        Button("Approve + Remember") {
                            // TODO: Approve and add to allow list
                            Task { await appState.approveRequest(approval) }
                        }
                        .font(.caption)

                        Spacer()

                        Button("Approve All Similar") {
                            // Approve all with same tool
                            Task {
                                for pending in appState.pendingApprovals where pending.toolName == approval.toolName {
                                    await appState.approveRequest(pending)
                                }
                            }
                        }
                        .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showModifySheet) {
            ModifyApprovalSheet(approval: approval)
        }
    }
}

struct RiskBadgeLarge: View {
    let level: RiskLevel

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)

            Text(level.rawValue.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

struct ParameterRow: View {
    let key: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct ShortcutRow: View {
    let keys: String
    let action: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.caption)
                .fontDesign(.monospaced)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(action)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Modify Sheet

struct ModifyApprovalSheet: View {
    let approval: PendingApproval
    @Environment(\.dismiss) private var dismiss
    @State private var modifiedParameters: [String: String] = [:]

    var body: some View {
        VStack(spacing: 20) {
            Text("Modify Parameters")
                .font(.headline)

            VStack(spacing: 12) {
                ForEach(Array(approval.parameters.keys.sorted()), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(key)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField(
                            key,
                            text: Binding(
                                get: { modifiedParameters[key] ?? approval.parameters[key] ?? "" },
                                set: { modifiedParameters[key] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Approve with Changes") {
                    // Submit modified approval
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - History Filter

enum ApprovalHistoryFilter: String, CaseIterable {
    case all = "All"
    case approved = "Approved"
    case denied = "Denied"
    case modified = "Modified"
}
