import AgentKit
import SwiftUI

struct AgentsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedAgent: ConnectedAgent?
    @State private var isScanning = false

    var body: some View {
        HSplitView {
            // Agent list
            VStack(spacing: 0) {
                List(selection: $selectedAgent) {
                    // Local agent section
                    Section("Local") {
                        if let local = appState.localAgent {
                            AgentListRow(agent: local)
                                .tag(local)
                        }
                    }

                    // Remote agents section
                    Section("Remote") {
                        if appState.connectedAgents.isEmpty {
                            Text("No remote agents")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(appState.connectedAgents) { agent in
                                AgentListRow(agent: agent)
                                    .tag(agent)
                            }
                        }
                    }

                    // Discovered agents (Bonjour)
                    Section("Discovered") {
                        if isScanning {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Scanning...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No agents found on network")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 250)

            // Agent detail
            if let agent = selectedAgent {
                AgentDetailView(agent: agent)
            } else {
                EmptyStateView(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "No Agent Selected",
                    message: "Select an agent to view details and capabilities"
                )
            }
        }
        .navigationTitle("Agents")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isScanning = true
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        isScanning = false
                    }
                } label: {
                    Label("Scan", systemImage: "antenna.radiowaves.left.and.right")
                }

                Button {
                    appState.showConnectSheet = true
                } label: {
                    Label("Connect", systemImage: "plus")
                }
            }
        }
    }
}

// MARK: - Agent List Row

struct AgentListRow: View {
    let agent: ConnectedAgent

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(agent.status.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .fontWeight(.medium)

                Text(agent.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Agent Detail View

struct AgentDetailView: View {
    let agent: ConnectedAgent
    @EnvironmentObject private var appState: AppState
    @State private var isConnecting = false
    @State private var showDisconnectConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(agent.name)
                            .font(.title)
                            .fontWeight(.bold)

                        Text(agent.url.absoluteString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    StatusBadge(status: agent.status)
                }

                Divider()

                // Connection actions
                HStack(spacing: 12) {
                    switch agent.status {
                    case .disconnected, .error:
                        Button {
                            connectAgent()
                        } label: {
                            Label("Connect", systemImage: "link")
                                .frame(width: 120)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isConnecting)

                    case .connecting:
                        Button {
                            // Cancel connection
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                                .frame(width: 120)
                        }
                        .buttonStyle(.bordered)

                    case .connected:
                        Button {
                            showDisconnectConfirmation = true
                        } label: {
                            Label("Disconnect", systemImage: "link.badge.xmark")
                                .frame(width: 120)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        // Refresh agent card
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(agent.status != .connected)
                }

                // Agent card info
                if let card = agent.card {
                    AgentCardSection(card: card)
                } else if agent.status == .connected {
                    VStack {
                        ProgressView()
                        Text("Loading agent card...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }

                // Quick actions
                if agent.status == .connected {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Actions")
                            .font(.headline)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150))],
                            spacing: 12
                        ) {
                            QuickActionButton(
                                title: "New Task",
                                icon: "plus.square",
                                action: { appState.showNewTaskSheet = true }
                            )

                            QuickActionButton(
                                title: "View Tasks",
                                icon: "list.bullet.rectangle",
                                action: { appState.selectedSidebarItem = .tasks }
                            )

                            QuickActionButton(
                                title: "Health Check",
                                icon: "heart.text.square",
                                action: { /* Ping agent */ }
                            )

                            QuickActionButton(
                                title: "View Logs",
                                icon: "doc.text",
                                action: { /* Open logs */ }
                            )
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .confirmationDialog("Disconnect from agent?", isPresented: $showDisconnectConfirmation) {
            Button("Disconnect", role: .destructive) {
                // Disconnect
            }
        }
    }

    private func connectAgent() {
        isConnecting = true
        Task {
            if agent.id == appState.localAgent?.id {
                await appState.connectToLocalAgent()
            }
            isConnecting = false
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: AgentConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.color.opacity(0.1))
        .clipShape(Capsule())
    }

    private var statusText: String {
        switch status {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return "Disconnected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Agent Card Section

struct AgentCardSection: View {
    let card: AgentCard

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Agent Card")
                .font(.headline)

            // Basic info
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Name", value: card.name)
                InfoRow(label: "Description", value: card.description)
                InfoRow(label: "Version", value: card.version)
            }

            // Capabilities
            VStack(alignment: .leading, spacing: 8) {
                Text("Capabilities")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    CapabilityBadge(name: "Streaming", enabled: card.capabilities.streaming)
                    CapabilityBadge(name: "Push", enabled: card.capabilities.pushNotifications)
                    CapabilityBadge(name: "History", enabled: card.capabilities.stateTransitionHistory)
                }
            }

            // Skills
            if !card.skills.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Skills")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(card.skills, id: \.id) { skill in
                        SkillRow(skill: skill)
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
        }
        .font(.subheadline)
    }
}

struct CapabilityBadge: View {
    let name: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(enabled ? .green : .secondary)

            Text(name)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary)
        .clipShape(Capsule())
    }
}

struct SkillRow: View {
    let skill: AgentSkill

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(skill.name)
                .fontWeight(.medium)

            Text(skill.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !skill.tags.isEmpty {
                HStack {
                    ForEach(skill.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)

                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
