import AgentKit
import SwiftUI

// MARK: - Agents View (Simple Roster)

struct AgentsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedAgentId: String?

    /// All agents - registered + recruited
    private var allAgents: [AgentRosterItem] {
        var items: [AgentRosterItem] = []

        // Add registered agents
        for agent in appState.registeredAgents {
            items.append(AgentRosterItem(
                id: agent.id.rawValue,
                name: agent.name,
                profile: agent.profile,
                capabilities: Array(agent.capabilities),
                isRecruited: false
            ))
        }

        // Add recruited agents from templates
        for agent in appState.recruitedAgents {
            // Map template skills to capabilities (best effort)
            let capabilities: [AgentCapability] = agent.template.skills.compactMap { skill in
                AgentCapability(rawValue: skill.lowercased())
            }
            items.append(AgentRosterItem(
                id: agent.id,
                name: agent.name,
                profile: .concierge, // Default profile for template-based agents
                capabilities: capabilities,
                isRecruited: true
            ))
        }

        return items
    }

    var body: some View {
        Group {
            if allAgents.isEmpty {
                emptyState
            } else {
                agentList
            }
        }
        .navigationTitle("Agents")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.showAgentRecruitment = true
                } label: {
                    Label("Add Agent", systemImage: "plus")
                }

                Menu {
                    Button(action: { appState.showAgentBuilder = true }) {
                        Label("Create Custom Agent", systemImage: "sparkles")
                    }
                    Button(action: { appState.showConnectSheet = true }) {
                        Label("Connect Remote Server", systemImage: "network")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)

                Text("No Agents Yet")
                    .font(.title2.bold())

                Text("Add an agent to start chatting and delegating tasks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Button {
                appState.showAgentRecruitment = true
            } label: {
                Label("Add Agent", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var agentList: some View {
        List(selection: $selectedAgentId) {
            ForEach(allAgents) { agent in
                AgentRosterRow(agent: agent)
                    .tag(agent.id)
            }
            .onDelete(perform: deleteAgents)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func deleteAgents(at offsets: IndexSet) {
        // Remove agents at the specified indices
        for index in offsets {
            let agent = allAgents[index]
            if agent.isRecruited {
                appState.recruitedAgents.removeAll { $0.id == agent.id }
            }
            // Can't delete registered agents (they're system-level)
        }
    }
}

// MARK: - Agent Roster Item

struct AgentRosterItem: Identifiable {
    let id: String
    let name: String
    let profile: AgentProfile
    let capabilities: [AgentCapability]
    let isRecruited: Bool
}

// MARK: - Agent Roster Row

struct AgentRosterRow: View {
    let agent: AgentRosterItem
    @EnvironmentObject private var appState: AppState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            Circle()
                .fill(colorFor(agent.profile).gradient)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: iconFor(agent.profile))
                        .font(.title3)
                        .foregroundStyle(.white)
                }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name)
                    .font(.headline)

                Text(agent.profile.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Capabilities preview
            HStack(spacing: 4) {
                ForEach(agent.capabilities.prefix(3), id: \.self) { cap in
                    Text(cap.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                if agent.capabilities.count > 3 {
                    Text("+\(agent.capabilities.count - 3)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Chat button
            Button {
                startChatWithAgent()
            } label: {
                Image(systemName: "bubble.left")
            }
            .buttonStyle(.borderless)
            .help("Chat with \(agent.name)")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isHovered ? Color.gray.opacity(0.05) : Color.clear)
        .onHover { isHovered = $0 }
    }

    private func startChatWithAgent() {
        // Find or create conversation with this agent
        if let conv = appState.workspace.conversations.first(where: { $0.agentName == agent.name }) {
            appState.selectedConversationId = conv.id
            appState.selectedSidebarItem = .conversations
        } else {
            let newConv = Conversation(
                title: "Chat with \(agent.name)",
                messages: [],
                agentName: agent.name
            )
            appState.workspace.conversations.insert(newConv, at: 0)
            appState.selectedConversationId = newConv.id
            appState.selectedSidebarItem = .conversations
        }
    }

    private func iconFor(_ profile: AgentProfile) -> String {
        switch profile {
        case .concierge: return "person.crop.circle.badge.questionmark"
        case .founder: return "lightbulb.fill"
        case .coach: return "figure.mind.and.body"
        case .integrator: return "gearshape.2.fill"
        case .librarian: return "books.vertical.fill"
        case .weaver: return "arrow.triangle.merge"
        case .critic: return "eye.fill"
        case .executor: return "bolt.fill"
        case .guardian: return "shield.fill"
        }
    }

    private func colorFor(_ profile: AgentProfile) -> Color {
        switch profile {
        case .concierge: return .blue
        case .founder: return .purple
        case .coach: return .orange
        case .integrator: return .green
        case .librarian: return .brown
        case .weaver: return .pink
        case .critic: return .red
        case .executor: return .yellow
        case .guardian: return .gray
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
