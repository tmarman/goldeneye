import AgentKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(columnVisibility: $columnVisibility)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 350)
        } detail: {
            DetailView()
                .toolbar(removing: .title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1000, minHeight: 700)
        // Handle Cmd+, to navigate to Settings
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            appState.selectedSidebarItem = .settings
        }
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
        // Command Palette (⌘K triggered via menu command)
        .sheet(isPresented: $appState.showCommandPalette) {
            CommandPaletteView()
        }
        // Agent Recruitment
        .sheet(isPresented: $appState.showAgentRecruitment) {
            AgentRecruitmentView()
        }
        // Agent Builder (conversational custom agent creation)
        .sheet(isPresented: $appState.showAgentBuilder) {
            AgentBuilderView()
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var serverManager = ServerManager.shared
    @Binding var columnVisibility: NavigationSplitViewVisibility

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
                            .badge(appState.pendingDecisionCount)
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
        .toolbar(removing: .sidebarToggle) // We'll add our own
        .toolbar {
            // Sidebar toggle button (Notes style)
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle(.secondary)
                }
                .help("Toggle Sidebar")
            }
        }
        .safeAreaInset(edge: .top) {
            // Compact header with title and actions
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goldeneye")
                        .font(.headline)
                    Text("\(itemCount) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    ServerStatusButton()

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
                        Image(systemName: "square.and.pencil")
                            .font(.title3)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .safeAreaInset(edge: .bottom) {
            ServerStatusBar()
        }
    }

    private var itemCount: Int {
        appState.workspace.documents.count + appState.workspace.conversations.count
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            if columnVisibility == .all {
                columnVisibility = .detailOnly
            } else {
                columnVisibility = .all
            }
        }
    }

    private func sidebarRow(for item: SidebarItem) -> some View {
        Label(item.label, systemImage: item.icon)
            .tag(item)
    }
}

// MARK: - Server Status Button

struct ServerStatusButton: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var serverManager = ServerManager.shared

    var body: some View {
        Button(action: { appState.selectedSidebarItem = .settings }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Image(systemName: "server.rack")
            }
        }
        .help(statusHelp)
    }

    private var statusColor: Color {
        if serverManager.isRunning && appState.isAgentConnected {
            return .green
        } else if serverManager.isRunning {
            return .orange
        } else {
            return .gray
        }
    }

    private var statusHelp: String {
        if serverManager.isRunning && appState.isAgentConnected {
            return "Server running, agent connected"
        } else if serverManager.isRunning {
            return "Server running, agent not connected"
        } else {
            return "Server not running"
        }
    }
}

// MARK: - Server Status Bar (Compact with Popover)

struct ServerStatusBar: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var serverManager = ServerManager.shared
    @State private var showPopover = false
    @State private var isStarting = false
    @State private var isCopied = false

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            HStack(spacing: 8) {
                // Status indicator
                ZStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    if serverManager.isRunning && appState.isAgentConnected {
                        Circle()
                            .stroke(statusColor.opacity(0.4), lineWidth: 1)
                            .frame(width: 14, height: 14)
                    }
                }

                // Compact status text
                Text(compactStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            ServerStatusPopover(
                isStarting: $isStarting,
                isCopied: $isCopied,
                onStart: startServer,
                onConnect: { Task { await appState.connectToLocalAgent() } }
            )
            .environmentObject(appState)
        }
    }

    private var statusColor: Color {
        if serverManager.isRunning && appState.isAgentConnected {
            return .green
        } else if serverManager.isRunning {
            return .orange
        } else if !serverManager.ollamaAvailable {
            return .red
        } else {
            return .gray
        }
    }

    private var compactStatusText: String {
        if serverManager.isRunning && appState.isAgentConnected {
            return "Connected"
        } else if serverManager.isRunning {
            return "Running"
        } else if !serverManager.ollamaAvailable {
            return "Ollama unavailable"
        } else {
            return "Stopped"
        }
    }

    private func startServer() {
        isStarting = true
        Task {
            do {
                try await serverManager.startServer()
                try? await Task.sleep(for: .seconds(1))
                await appState.connectToLocalAgent()
            } catch {
                // Error displayed in serverManager.lastError
            }
            isStarting = false
        }
    }
}

// MARK: - Server Status Popover

struct ServerStatusPopover: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var serverManager = ServerManager.shared
    @Binding var isStarting: Bool
    @Binding var isCopied: Bool
    let onStart: () -> Void
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Agent Server")
                        .font(.headline)

                    Text(statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            NotesDivider()

            // Remote URL (for connecting from other devices)
            if serverManager.isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Remote URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(serverManager.remoteURL)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Button(action: copyURL) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(isCopied ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy URL")
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                    Text("Use this URL to connect from other devices on your network")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Model info
            if serverManager.isRunning && appState.isAgentConnected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "cpu")
                            .foregroundStyle(.secondary)
                        Text(serverManager.selectedModel)
                            .font(.system(.body, design: .monospaced))
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            NotesDivider()

            // Actions
            HStack {
                if !serverManager.isRunning {
                    Button(action: onStart) {
                        HStack(spacing: 6) {
                            if isStarting {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text("Start Server")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStarting)
                } else if !appState.isAgentConnected {
                    Button(action: onConnect) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("Connect")
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Stop") {
                        serverManager.stopServer()
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Button("Disconnect") {
                        appState.localAgent = nil
                    }
                    .foregroundStyle(.secondary)

                    Button("Stop Server") {
                        serverManager.stopServer()
                    }
                    .foregroundStyle(.red)
                }

                Spacer()

                Button(action: { appState.selectedSidebarItem = .settings }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Error message if any
            if let error = serverManager.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(8)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .frame(width: 320)
    }

    private var statusColor: Color {
        if serverManager.isRunning && appState.isAgentConnected {
            return .green
        } else if serverManager.isRunning {
            return .orange
        } else if !serverManager.ollamaAvailable {
            return .red
        } else {
            return .gray
        }
    }

    private var statusDescription: String {
        if serverManager.isRunning && appState.isAgentConnected {
            return "Connected to \(appState.localAgent?.name ?? "Local Agent")"
        } else if serverManager.isRunning {
            return "Running on port \(serverManager.serverPort)"
        } else if !serverManager.ollamaAvailable {
            return "Ollama not available - check Settings"
        } else {
            return "Not running"
        }
    }

    private func copyURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(serverManager.remoteURL, forType: .string)

        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
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
        case .settings:
            SettingsDetailView()
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

