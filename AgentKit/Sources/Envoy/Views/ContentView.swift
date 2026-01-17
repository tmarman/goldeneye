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
            DetailView(columnVisibility: $columnVisibility)
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
        .sheet(isPresented: $appState.showNewThreadSheet) {
            NewThreadSheet()
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
        // New Space sheet
        .sheet(isPresented: $appState.showNewSpaceSheet) {
            NewSpaceSheet()
        }
        // Model Picker sheet (Cmd+M)
        .sheet(isPresented: $appState.showModelPicker) {
            QuickModelSetupSheet()
        }
        // Onboarding sheet (first launch or triggered from Settings)
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView(isPresented: $appState.showOnboarding)
        }
        // Keyboard shortcut for model picker
        .onReceive(NotificationCenter.default.publisher(for: .openModelPicker)) { _ in
            appState.showModelPicker = true
        }
        // Check for first launch onboarding
        .onAppear {
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                // Small delay to let the app settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    appState.showOnboarding = true
                }
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(ChatService.self) private var chatService
    @Environment(ProviderConfigManager.self) private var providerManager
    @ObservedObject private var serverManager = ServerManager.shared
    @Binding var columnVisibility: NavigationSplitViewVisibility

    private var displaySpaces: [SpaceViewModel] {
        // Only show actual spaces - no sample data
        appState.spaces
    }

    /// Recent agent conversations for DM-style display
    /// Only shows agents that have actual conversations (user-created)
    /// Excludes About Me space conversations (shown as threads within that space)
    private var recentAgentChats: [AgentDMInfo] {
        var chats: [AgentDMInfo] = []

        // Only show threads that exist (user-initiated chats)
        // Exclude About Me space threads - they appear within that space
        for thread in appState.workspace.threads.prefix(10) {
            guard let agentName = thread.container.agentName else { continue }

            // Skip About Me space threads (Concierge threads)
            if thread.container.spaceId == AboutMeService.aboutMeSpaceId.rawValue {
                continue
            }

            // Find matching registered agent for color/icon, or use defaults
            let agent = appState.registeredAgents.first { $0.name == agentName }

            chats.append(AgentDMInfo(
                id: thread.id.rawValue,
                name: agentName,
                avatar: agent.map { iconFor($0.profile) } ?? "person.crop.circle.fill",
                color: agent.map { colorFor($0.profile) } ?? .blue,
                lastMessage: thread.messages.last?.textContent,
                unreadCount: 0
            ))
        }

        return chats
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

    var body: some View {
        VStack(spacing: 0) {
            // Header in title bar area - sits alongside traffic lights
            sidebarHeader

            // Main sidebar list
            List(selection: $appState.selectedSidebarItem) {
                // Open Space - Primary entry point (no section header)
                ForEach(SidebarItem.primaryItems) { item in
                    sidebarRow(for: item)
                        .font(.headline)
                }

                // Spaces with expandable channels
                Section("Spaces") {
                    ForEach(displaySpaces) { space in
                        SpaceSidebarRow(space: space)
                    }

                    // Add new space - with menu for options
                    HStack(spacing: 8) {
                        Button(action: { appState.showNewSpaceSheet = true }) {
                            Label("Add Space", systemImage: "plus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button(action: { appState.showNewSpaceSheet = true }) {
                                Label("New Space", systemImage: "folder.badge.plus")
                            }
                            Button(action: { addExternalFolder() }) {
                                Label("Add External Folder", systemImage: "folder.badge.gearshape")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.tertiary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 20)
                    }
                }

                // Direct Messages (Agent chats - Slack-like)
                Section("Direct Messages") {
                    // Show recent agent conversations
                    ForEach(recentAgentChats.prefix(5)) { agent in
                        AgentDMRow(agent: agent)
                    }

                    // "View all" link to Agents roster
                    Button(action: { appState.selectedSidebarItem = .agents }) {
                        Label("View all agents", systemImage: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Activity section
                Section {
                    sidebarRow(for: .tasks)

                    // Reviews only shown when there are pending items
                    let pendingCount = appState.pendingApprovals.count + appState.pendingDecisionCount
                    if pendingCount > 0 {
                        sidebarRow(for: .reviews)
                            .badge(pendingCount)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    // Model status bar
                    ModelStatusBar()

                    // Server status bar
                    HStack(spacing: 12) {
                        ServerStatusBar()

                        Spacer()

                        Button(action: { appState.selectedSidebarItem = .settings }) {
                            Image(systemName: "gearshape")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Settings")
                    }
                    .padding(.trailing, 12)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar(removing: .sidebarToggle) // Remove default toggle
        .onChange(of: appState.selectedSidebarItem) { _, newItem in
            // Clear space selection when switching to non-space sidebar items
            if newItem != .spaces {
                appState.selectedSpaceId = nil
            }
        }
    }

    private var itemCount: Int {
        appState.workspace.documents.count + appState.workspace.threads.count
    }

    /// Header that sits in the title bar area, aligned with traffic lights
    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            // Leave space for traffic lights (approximately 70pt)
            Spacer()
                .frame(width: 52)

            // Sidebar toggle button - right-aligned in header
            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle Sidebar")

            Spacer()

            // Demo mode indicator (small, subtle)
            if DemoDataManager.shared.isDemoMode {
                Text("DEMO")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 8)
    }

    private func sidebarRow(for item: SidebarItem) -> some View {
        Label(item.label, systemImage: item.icon)
            .tag(item)
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            columnVisibility = .detailOnly
        }
    }

    private func addExternalFolder() {
        // Open folder picker and create a new space linked to that folder
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Select Folder for New Space"
        panel.prompt = "Add Space"

        if panel.runModal() == .OK, let url = panel.url {
            // Create a new space linked to this folder
            let folderName = url.lastPathComponent
            let newSpace = SpaceViewModel(
                id: UUID().uuidString,
                name: folderName,
                description: "External folder: \(url.path)",
                icon: "folder",
                color: .blue,
                path: url,
                channels: []
            )
            appState.spaces.append(newSpace)

            // Select the new space
            appState.selectedSpaceId = SpaceID(newSpace.id)
        }
    }
}

// MARK: - Space Sidebar Row (Simplified - no expand/collapse)

struct SpaceSidebarRow: View {
    let space: SpaceViewModel
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false
    @State private var showInviteAgent = false
    @State private var isHovered = false

    private var isSelected: Bool {
        appState.selectedSpaceId?.rawValue == space.id
    }

    private var totalUnread: Int {
        space.channels.reduce(0) { $0 + $1.unreadCount }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Space icon
            RoundedRectangle(cornerRadius: 6)
                .fill(space.color.gradient)
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: space.icon)
                        .font(.caption)
                        .foregroundStyle(.white)
                }

            Text(space.name)
                .fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)

            Spacer()

            // Settings menu (appears on hover)
            if isHovered {
                Menu {
                    Button(action: { showSettings = true }) {
                        Label("Space Settings", systemImage: "gearshape")
                    }
                    Button(action: { showInviteAgent = true }) {
                        Label("Invite Agent", systemImage: "person.badge.plus")
                    }
                    if space.path != nil {
                        Divider()
                        Button(action: { showInFinder() }) {
                            Label("Show in Finder", systemImage: "folder")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            // Unread badge
            if totalUnread > 0 {
                Text("\(totalUnread)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            selectSpace()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(action: { showSettings = true }) {
                Label("Space Settings", systemImage: "gearshape")
            }
            Button(action: { showInviteAgent = true }) {
                Label("Invite Agent", systemImage: "person.badge.plus")
            }
            if space.path != nil {
                Divider()
                Button(action: { showInFinder() }) {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SpaceSettingsSheet(space: space)
        }
        .sheet(isPresented: $showInviteAgent) {
            InviteAgentSheet(space: space)
        }
    }

    private func showInFinder() {
        guard let path = space.path?.path else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    private func selectSpace() {
        print("🎯 Selecting space: \(space.name) with id: \(space.id)")
        appState.selectedSpaceId = SpaceID(space.id)
        appState.selectedChannelId = nil
    }
}

// MARK: - Space Settings Sheet

struct SpaceSettingsSheet: View {
    let space: SpaceViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var spaceName: String = ""
    @State private var selectedColor: Color = .blue
    @State private var selectedIcon: String = "folder.fill"

    private let colorOptions: [Color] = [
        .blue, .purple, .pink, .red, .orange, .yellow, .green, .mint, .cyan, .indigo, .brown, .gray
    ]

    private let iconOptions = [
        "folder.fill", "doc.fill", "book.fill", "briefcase.fill",
        "house.fill", "building.2.fill", "person.2.fill", "gear",
        "star.fill", "heart.fill", "flag.fill", "tag.fill"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Space Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.subheadline.weight(.medium))
                        TextField("Space name", text: $spaceName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .font(.subheadline.weight(.medium))

                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 6), spacing: 8) {
                            ForEach(colorOptions, id: \.self) { color in
                                Circle()
                                    .fill(color.gradient)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if selectedColor == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .onTapGesture {
                                        selectedColor = color
                                    }
                            }
                        }
                    }

                    // Icon picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.subheadline.weight(.medium))

                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 6), spacing: 8) {
                            ForEach(iconOptions, id: \.self) { icon in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedIcon == icon ? selectedColor.opacity(0.2) : Color(.controlBackgroundColor))
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        Image(systemName: icon)
                                            .foregroundStyle(selectedIcon == icon ? selectedColor : .secondary)
                                    }
                                    .onTapGesture {
                                        selectedIcon = icon
                                    }
                            }
                        }
                    }

                    // Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.subheadline.weight(.medium))

                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selectedColor.gradient)
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Image(systemName: selectedIcon)
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                }

                            Text(spaceName.isEmpty ? space.name : spaceName)
                                .font(.subheadline)
                        }
                        .padding(12)
                        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Location (read-only)
                    if let path = space.path {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location")
                                .font(.subheadline.weight(.medium))

                            HStack {
                                Text(path.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer()

                                Button("Show in Finder") {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
                                }
                                .font(.caption)
                            }
                            .padding(12)
                            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer with save/cancel
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Spacer()

                Button("Save Changes") {
                    saveSpaceSettings()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(spaceName.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 550)
        .onAppear {
            spaceName = space.name
            selectedColor = space.color
            selectedIcon = space.icon
        }
    }

    private func saveSpaceSettings() {
        // Find and update the space in appState
        if let index = appState.spaces.firstIndex(where: { $0.id == space.id }) {
            appState.spaces[index].name = spaceName
            appState.spaces[index].color = selectedColor
            appState.spaces[index].icon = selectedIcon
        }
    }
}

// MARK: - Invite Agent Sheet

struct InviteAgentSheet: View {
    let space: SpaceViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

    private var availableAgents: [RegisteredAgent] {
        let agents = appState.registeredAgents
        if searchText.isEmpty { return agents }
        return agents.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Invite Agent to \(space.name)")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search agents...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()

            // Agent list
            if availableAgents.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No agents available")
                        .font(.headline)
                    Text("Create agents in the Agents section")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Go to Agents") {
                        appState.selectedSidebarItem = .agents
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            } else {
                List(availableAgents) { agent in
                    AgentInviteRow(agent: agent) {
                        inviteAgent(agent)
                    }
                }
            }
        }
        .frame(width: 420, height: 480)
    }

    private func inviteAgent(_ agent: RegisteredAgent) {
        // Create a new DM thread with this agent
        let introMessage = AgentKit.ThreadMessage.assistant(
            """
            Hi! I'm \(agent.name), and I've been invited to join **\(space.name)**.

            Before I get started, I'd like to ask: would you like me to **review existing threads** in this space? This would help me understand the context and contribute more effectively.

            Please let me know:
            - **Yes** - Review past threads and provide insights
            - **No** - Start fresh with new threads only
            """,
            agentName: agent.name
        )

        var newThread = AgentKit.Thread(
            title: "Invite: \(agent.name) → \(space.name)",
            messages: [introMessage],
            container: .space(space.id)
        )

        // Add to workspace
        appState.workspace.threads.insert(newThread, at: 0)

        // Create a decision card for the retroactive review
        let decisionCard = DecisionCard(
            title: "Allow \(agent.name) to review existing threads?",
            description: """
            \(agent.name) has been invited to \(space.name).

            If approved, the agent will analyze existing threads to understand context and may provide insights or suggestions based on past threads.
            """,
            status: .pending,
            sourceType: .agentAction,
            sourceId: newThread.id.rawValue,
            requestedBy: agent.name
        )

        // Add to pending decisions
        appState.decisionCards.append(decisionCard)

        // Navigate to the thread
        appState.selectedAgentFilter = agent.name
        appState.selectedThreadId = newThread.id
        appState.selectedSidebarItem = .threads

        dismiss()
    }
}

struct AgentInviteRow: View {
    let agent: RegisteredAgent
    let onInvite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Agent avatar
            Circle()
                .fill(colorFor(agent.profile).gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: iconFor(agent.profile))
                        .font(.title3)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.headline)
                Text(agent.profile.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onInvite) {
                Label("Invite", systemImage: "person.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
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

// MARK: - Channel Sidebar Row

struct ChannelSidebarRow: View {
    let channel: ChannelViewModel
    let spaceId: String
    @EnvironmentObject private var appState: AppState
    @State private var showMembers = false
    @State private var isMuted = false
    @State private var showSettings = false

    private var isSelected: Bool {
        appState.selectedSpaceId?.rawValue == spaceId &&
        appState.selectedChannelId == channel.id
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: channel.icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(channel.name)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            if channel.unreadCount > 0 {
                Text("\(channel.unreadCount)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            selectChannel()
        }
        .contextMenu {
            Button(action: { showMembers = true }) {
                Label("View Members", systemImage: "person.2")
            }
            Button(action: { addMemberToChannel() }) {
                Label("Add Member", systemImage: "person.badge.plus")
            }
            Divider()
            Button(action: { showSettings = true }) {
                Label("Channel Settings", systemImage: "gearshape")
            }
            Button(action: { toggleMute() }) {
                Label(isMuted ? "Unmute Channel" : "Mute Channel",
                      systemImage: isMuted ? "bell" : "bell.slash")
            }
        }
        .sheet(isPresented: $showMembers) {
            ChannelMembersSheet(channel: channel, spaceId: spaceId)
        }
        .sheet(isPresented: $showSettings) {
            ChannelSettingsSheet(channel: channel, spaceId: spaceId)
        }
        .onAppear {
            // Load mute state from UserDefaults
            let key = "channelMuted_\(spaceId)_\(channel.id)"
            isMuted = UserDefaults.standard.bool(forKey: key)
        }
    }

    private func selectChannel() {
        appState.selectedSpaceId = SpaceID(spaceId)
        appState.selectedChannelId = channel.id
        // Channel selection is separate from sidebar item selection
    }

    private func addMemberToChannel() {
        // Navigate to agent recruitment to add a member to this channel
        appState.selectedSpaceId = SpaceID(spaceId)
        appState.selectedChannelId = channel.id
        appState.showAgentRecruitment = true
    }

    private func toggleMute() {
        isMuted.toggle()
        // Persist mute state to UserDefaults
        let key = "channelMuted_\(spaceId)_\(channel.id)"
        UserDefaults.standard.set(isMuted, forKey: key)
    }
}

// MARK: - Channel Settings Sheet

struct ChannelSettingsSheet: View {
    let channel: ChannelViewModel
    let spaceId: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var channelName: String = ""
    @State private var channelDescription: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Channel Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Channel name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Channel Name")
                            .font(.subheadline.weight(.medium))
                        TextField("Channel name", text: $channelName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Channel description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.subheadline.weight(.medium))
                        TextField("What's this channel about?", text: $channelDescription)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    // Channel info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Channel Info")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack {
                            Image(systemName: channel.icon)
                                .foregroundStyle(.secondary)
                            Text("Icon: \(channel.icon)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Image(systemName: "number")
                                .foregroundStyle(.secondary)
                            Text("ID: \(channel.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding()
            }
        }
        .frame(width: 400, height: 350)
        .onAppear {
            channelName = channel.name
        }
    }
}

// MARK: - Channel Members Sheet

struct ChannelMembersSheet: View {
    let channel: ChannelViewModel
    let spaceId: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Channel Members")
                        .font(.headline)
                    Text("#\(channel.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Members list
            if appState.registeredAgents.isEmpty {
                ContentUnavailableView(
                    "No Members Yet",
                    systemImage: "person.2.slash",
                    description: Text("Invite agents to this channel to collaborate")
                )
            } else {
                List {
                    Section("Agents") {
                        ForEach(appState.registeredAgents.prefix(5)) { agent in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        Image(systemName: "sparkles")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                        .font(.subheadline.weight(.medium))
                                    Text(agent.profile.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Menu {
                                    Button(action: {}) {
                                        Label("Message", systemImage: "bubble.left")
                                    }
                                    Button(action: {}) {
                                        Label("Remove from Channel", systemImage: "minus.circle")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundStyle(.secondary)
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                            }
                        }
                    }
                }
            }

            Divider()

            // Add member button
            HStack {
                Button {
                    // TODO: Show agent picker
                } label: {
                    Label("Invite Agent", systemImage: "person.badge.plus")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
        }
        .frame(width: 400, height: 450)
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

// MARK: - Model Status Bar

/// Compact bar showing current model status with quick access to model selection
struct ModelStatusBar: View {
    @Environment(ChatService.self) private var chatService
    @Environment(ProviderConfigManager.self) private var providerManager
    @State private var showPopover = false
    @State private var animatePulse = false

    private var statusIcon: String {
        if chatService.isLoadingModel {
            return "sparkles"
        } else if chatService.isReady {
            return "checkmark.circle.fill"
        } else {
            return "sparkles"
        }
    }

    private var statusColor: Color {
        if chatService.isLoadingModel {
            return .orange
        } else if chatService.isReady {
            return .green
        } else {
            return .secondary
        }
    }

    private var statusText: String {
        if chatService.isLoadingModel {
            let progress = Int(chatService.loadProgress * 100)
            return "Loading \(progress)%"
        } else if chatService.isReady {
            return shortModelName(chatService.loadedModelId ?? chatService.providerDescription)
        } else {
            return "Select a model"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Loading progress bar
            if chatService.isLoadingModel {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.orange.gradient)
                        .frame(width: geometry.size.width * chatService.loadProgress)
                }
                .frame(height: 2)
                .animation(.linear(duration: 0.2), value: chatService.loadProgress)
            }

            // Main button
            Button(action: { showPopover.toggle() }) {
                HStack(spacing: 8) {
                    // Status indicator with icon
                    HStack(spacing: 6) {
                        ZStack {
                            if chatService.isLoadingModel {
                                // Animated loading indicator
                                Circle()
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                                    .frame(width: 14, height: 14)

                                Circle()
                                    .trim(from: 0, to: chatService.loadProgress)
                                    .stroke(Color.orange, lineWidth: 2)
                                    .frame(width: 14, height: 14)
                                    .rotationEffect(.degrees(-90))
                            } else {
                                Image(systemName: statusIcon)
                                    .font(.caption)
                                    .foregroundStyle(statusColor)
                            }
                        }
                        .frame(width: 14, height: 14)

                        Text(statusText)
                            .font(.caption.weight(chatService.isReady ? .medium : .regular))
                            .foregroundStyle(chatService.isReady ? .primary : .secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Keyboard shortcut hint
                    if !chatService.isReady {
                        Text("⌘M")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                    }

                    // Chevron for popover
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showPopover ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: showPopover)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            ModelQuickSwitcher()
                .environment(chatService)
                .environment(providerManager)
        }
    }

    private var backgroundColor: Color {
        if chatService.isLoadingModel {
            return Color.orange.opacity(0.1)
        } else if chatService.isReady {
            return Color.green.opacity(0.1)
        } else {
            return Color(.controlBackgroundColor)
        }
    }

    private var borderColor: Color {
        if chatService.isLoadingModel {
            return Color.orange.opacity(0.2)
        } else if chatService.isReady {
            return Color.green.opacity(0.2)
        } else {
            return Color.clear
        }
    }

    private func shortModelName(_ name: String) -> String {
        let shortName = name.components(separatedBy: "/").last ?? name
        if shortName.count > 25 {
            return String(shortName.prefix(22)) + "..."
        }
        return shortName
    }
}

// MARK: - Model Quick Switcher Popover

struct ModelQuickSwitcher: View {
    @Environment(ChatService.self) private var chatService
    @Environment(ProviderConfigManager.self) private var providerManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var selectedModelId: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Model")
                        .font(.headline)

                    if chatService.isReady {
                        Text(chatService.providerDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Select a model to enable AI chat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            Divider()

            // Quick model options
            ScrollView {
                VStack(spacing: 4) {
                    // MLX quick picks
                    quickPickSection(
                        title: "On-Device (MLX)",
                        icon: "apple.logo",
                        models: [
                            ("mlx-community/Llama-3.2-1B-Instruct-4bit", "Llama 3.2 1B", "Fast, lightweight"),
                            ("mlx-community/Llama-3.2-3B-Instruct-4bit", "Llama 3.2 3B", "Good balance"),
                            ("mlx-community/Qwen2.5-7B-Instruct-4bit", "Qwen 2.5 7B", "Recommended"),
                        ]
                    )

                    // Ollama if configured
                    if let ollama = providerManager.providers.first(where: { $0.type == .ollama && $0.isEnabled }) {
                        quickPickSection(
                            title: "Ollama",
                            icon: "server.rack",
                            models: ollama.availableModels.prefix(3).map { ($0, $0, "") }
                        )
                    }
                }
            }
            .frame(maxHeight: 300)

            // Error
            if let error = error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                }
                .padding(8)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            // Footer actions
            HStack {
                Button("More Models") {
                    appState.targetSettingsCategory = "models"
                    appState.selectedSidebarItem = .settings
                    dismiss()
                }
                .font(.caption)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
        .padding()
        .frame(width: 300)
    }

    @ViewBuilder
    private func quickPickSection(title: String, icon: String, models: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            ForEach(models, id: \.0) { modelId, displayName, subtitle in
                Button(action: { selectModel(modelId) }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName)
                                .font(.subheadline)
                            if !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        if chatService.loadedModelId == modelId {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if isLoading && selectedModelId == modelId {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        chatService.loadedModelId == modelId
                            ? Color.green.opacity(0.1)
                            : Color(.controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
    }

    private func selectModel(_ modelId: String) {
        isLoading = true
        selectedModelId = modelId
        error = nil

        Task {
            do {
                // Determine provider type from model ID
                if modelId.hasPrefix("mlx-community/") || modelId.contains("Instruct-") {
                    try await chatService.loadMLXModel(modelId)
                } else {
                    // Assume Ollama for other models
                    if let ollama = providerManager.providers.first(where: { $0.type == .ollama && $0.isEnabled }) {
                        var config = ollama
                        config.selectedModel = modelId
                        try await chatService.selectProvider(config)
                    }
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
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
                        Image(systemName: "sparkles")
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
    @Binding var columnVisibility: NavigationSplitViewVisibility

    var body: some View {
        Group {
            // Check if a specific space is selected
            if let spaceId = appState.selectedSpaceId {
                // Special handling for About Me space
                if spaceId == AboutMeService.aboutMeSpaceId {
                    AboutMeView()
                        .onAppear {
                            print("📱 Showing AboutMeView")
                        }
                } else {
                    SpaceDetailView(spaceId: spaceId)
                        .onAppear {
                            print("📱 Showing SpaceDetailView for: \(spaceId)")
                        }
                }
            } else {
                // Regular sidebar navigation
                switch appState.selectedSidebarItem {
                case .headspace:
                    OpenSpaceView()
                case .spaces:
                    SpacesListView()
                case .documents:
                    DocumentsView()
                case .threads:
                    ThreadsView()
                case .tasks:
                    TasksView()
                case .reviews:
                    ReviewsView()
                case .agents:
                    AgentsView()
                case .connections:
                    ConnectionsView()
                case .settings:
                    SettingsDetailView()
                }
            }
        }
        .toolbar {
            // Only show toolbar toggle when sidebar is collapsed
            if columnVisibility == .detailOnly {
                ToolbarItem(placement: .navigation) {
                    Button(action: expandSidebar) {
                        Image(systemName: "sidebar.left")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show Sidebar")
                }
            }
        }
    }

    private func expandSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            columnVisibility = .all
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

// MARK: - Agent DM Model

struct AgentDMInfo: Identifiable {
    let id: String
    let name: String
    let avatar: String
    let color: Color
    let lastMessage: String?
    let unreadCount: Int
}

// MARK: - Agent DM Row (Slack-style, simplified)

struct AgentDMRow: View {
    let agent: AgentDMInfo
    @EnvironmentObject private var appState: AppState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Simple avatar (no status dot)
            Circle()
                .fill(agent.color.gradient)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: agent.avatar)
                        .font(.caption)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.subheadline)
                    .lineLimit(1)

                if let lastMessage = agent.lastMessage {
                    Text(lastMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Unread badge only (no timer)
            if agent.unreadCount > 0 {
                Text("\(agent.unreadCount)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .onTapGesture {
            // Navigate to agent conversation
            startAgentChat()
        }
    }

    private func startAgentChat() {
        // Set agent filter to show all threads with this agent
        appState.selectedAgentFilter = agent.name
        appState.selectedSidebarItem = .threads

        // If there's an existing thread with this agent, select it
        if let existing = appState.workspace.threads.first(where: { $0.container.agentName == agent.name }) {
            appState.selectedThreadId = existing.id
        } else {
            // Create new thread and select it
            let newThread = AgentKit.Thread(
                title: "Chat with \(agent.name)",
                container: .agent(agent.name)
            )
            appState.workspace.threads.insert(newThread, at: 0)
            appState.selectedThreadId = newThread.id
            appState.selectedSidebarItem = .threads
        }
    }
}

