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
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $appState.showNewTaskSheet) {
            NewTaskSheet()
        }
        .sheet(isPresented: $appState.showConnectSheet) {
            ConnectAgentSheet()
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: $appState.selectedSidebarItem) {
            Section("Overview") {
                ForEach([SidebarItem.dashboard]) { item in
                    Label(item.label, systemImage: item.icon)
                        .tag(item)
                }
            }

            Section("Activity") {
                ForEach([SidebarItem.tasks, SidebarItem.sessions]) { item in
                    sidebarRow(for: item)
                }
            }

            Section("Control") {
                sidebarRow(for: .approvals)
                    .badge(appState.pendingApprovals.count)
            }

            Section("Infrastructure") {
                sidebarRow(for: .agents)
                    .badge(appState.connectedAgents.count + (appState.localAgent != nil ? 1 : 0))
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("AgentKit")
        .toolbar {
            ToolbarItem {
                Button(action: { appState.showNewTaskSheet = true }) {
                    Label("New Task", systemImage: "plus")
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
        case .dashboard:
            DashboardView()
        case .tasks:
            TasksView()
        case .sessions:
            SessionsView()
        case .approvals:
            ApprovalsView()
        case .agents:
            AgentsView()
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
