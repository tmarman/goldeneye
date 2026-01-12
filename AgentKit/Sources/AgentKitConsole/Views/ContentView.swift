import AgentKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .frame(minWidth: 1000, minHeight: 700)
        // Agent panel overlay
        .overlay(alignment: .bottomTrailing) {
            AgentPanelButton()
                .padding()
        }
        // Sheets
        .sheet(isPresented: $appState.showNewTaskSheet) {
            NewTaskSheet()
        }
        .sheet(isPresented: $appState.showConnectSheet) {
            ConnectAgentSheet()
        }
        .sheet(isPresented: $appState.showNewDocumentSheet) {
            NewDocumentSheet()
        }
        .sheet(isPresented: $appState.showNewConversationSheet) {
            NewConversationSheet()
        }
        .sheet(isPresented: $appState.showNewCoachingSheet) {
            NewCoachingSheet()
        }
        // Agent panel slide-over
        .sheet(isPresented: $appState.isAgentPanelVisible) {
            AgentPanelView()
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: $appState.selectedSidebarItem) {
            // Open Space - Primary entry point (no section header)
            ForEach(SidebarItem.primaryItems) { item in
                sidebarRow(for: item)
                    .font(.headline)
            }

            Section("Spaces") {
                ForEach(SidebarItem.workspaceItems) { item in
                    sidebarRow(for: item)
                }
            }

            Section("Activity") {
                ForEach(SidebarItem.activityItems) { item in
                    if item == .approvals {
                        sidebarRow(for: item)
                            .badge(appState.pendingApprovals.count)
                    } else if item == .decisions {
                        sidebarRow(for: item)
                            .badge(3)  // TODO: wire up real count
                    } else {
                        sidebarRow(for: item)
                    }
                }
            }

            Section("Infrastructure") {
                ForEach(SidebarItem.infrastructureItems) { item in
                    if item == .agents {
                        sidebarRow(for: item)
                            .badge(appState.connectedAgents.count + (appState.localAgent != nil ? 1 : 0))
                    } else {
                        sidebarRow(for: item)
                    }
                }
            }

            // Starred section (if any)
            if !appState.workspace.starredDocuments.isEmpty || !appState.workspace.starredConversations.isEmpty {
                Section("Starred") {
                    ForEach(appState.workspace.starredDocuments) { doc in
                        Label(doc.title.isEmpty ? "Untitled" : doc.title, systemImage: "doc.text")
                            .tag(SidebarItem.documents)
                    }
                    ForEach(appState.workspace.starredConversations) { conv in
                        Label(conv.title, systemImage: "bubble.left")
                            .tag(SidebarItem.conversations)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Goldeneye")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button(action: { appState.showNewDocumentSheet = true }) {
                        Label("New Document", systemImage: "doc.badge.plus")
                    }
                    Button(action: { appState.showNewConversationSheet = true }) {
                        Label("New Conversation", systemImage: "bubble.left.and.bubble.right")
                    }
                    Button(action: { appState.showNewCoachingSheet = true }) {
                        Label("New Coaching Session", systemImage: "figure.mind.and.body")
                    }
                    Divider()
                    Button(action: { appState.showNewTaskSheet = true }) {
                        Label("New Task", systemImage: "plus.circle")
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
        }
    }

    private func sidebarRow(for item: SidebarItem) -> some View {
        Label(item.label, systemImage: item.icon)
            .tag(item)
    }
}

// MARK: - Detail View Router

struct DetailView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        switch appState.selectedSidebarItem {
        case .openSpace:
            OpenSpaceView()
        case .spaces:
            SpacesListView()
        case .documents:
            DocumentsView()
        case .conversations:
            ConversationsView()
        case .tasks:
            TasksView()
        case .decisions:
            DecisionCardsView()
        case .approvals:
            ApprovalsView()
        case .agents:
            AgentsView()
        case .connections:
            ConnectionsView()
        }
    }
}

// MARK: - Agent Panel Button

struct AgentPanelButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var isHovered = false

    var body: some View {
        Button(action: { appState.isAgentPanelVisible.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse, options: .repeating, isActive: appState.isAgentPanelVisible)
                Text("Agent")
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if appState.isAgentPanelVisible {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.2))
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                Capsule()
                    .stroke(
                        appState.isAgentPanelVisible
                            ? Color.accentColor.opacity(0.5)
                            : Color.white.opacity(isHovered ? 0.25 : 0.15),
                        lineWidth: 0.5
                    )
            )
            .foregroundStyle(appState.isAgentPanelVisible ? Color.accentColor : Color.primary)
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .shadow(
                color: .black.opacity(isHovered ? 0.15 : 0.1),
                radius: isHovered ? 10 : 6,
                x: 0,
                y: isHovered ? 4 : 2
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut("/", modifiers: .command)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Sheets

struct NewTaskSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var selectedAgentId: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("New Task")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Agent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Agent", selection: $selectedAgentId) {
                    if let local = appState.localAgent {
                        Text(local.name).tag(local.id as String?)
                    }
                    ForEach(appState.connectedAgents) { agent in
                        Text(agent.name).tag(agent.id as String?)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Submit") {
                    submitTask()
                }
                .keyboardShortcut(.return)
                .disabled(prompt.isEmpty || selectedAgentId == nil)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            selectedAgentId = appState.localAgent?.id
        }
    }

    private func submitTask() {
        guard let agentId = selectedAgentId else { return }
        let agent =
            appState.localAgent?.id == agentId
            ? appState.localAgent
            : appState.connectedAgents.first(where: { $0.id == agentId })

        if let agent = agent {
            Task {
                await appState.submitTask(prompt, to: agent)
                dismiss()
            }
        }
    }
}

struct ConnectAgentSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Connect to Agent")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Agent URL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("http://192.168.1.100:8080", text: $url)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Connect") {
                    connectToAgent()
                }
                .keyboardShortcut(.return)
                .disabled(url.isEmpty || isConnecting)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func connectToAgent() {
        guard let agentURL = URL(string: url) else { return }
        isConnecting = true

        let agent = ConnectedAgent(
            id: UUID().uuidString,
            name: agentURL.host ?? "Remote Agent",
            url: agentURL,
            status: .connecting
        )

        appState.connectedAgents.append(agent)
        dismiss()
    }
}
