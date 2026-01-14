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

                // Getting started (when no agents connected)
                if connectedAgentCount == 0 {
                    GettingStartedCard()
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

                // Active Agents section
                if !activeAgents.isEmpty {
                    DashboardSection(title: "Active Agents", icon: "sparkles") {
                        VStack(spacing: 16) {
                            ForEach(activeAgents, id: \.id) { agent in
                                AgentActivityCard(agent: agent)
                            }
                        }
                    }
                }

                // Agent Conversations section
                if !agentConversations.isEmpty {
                    DashboardSection(title: "Agent Conversations", icon: "bubble.left.and.bubble.right") {
                        VStack(spacing: 12) {
                            ForEach(agentConversations, id: \.id) { conversation in
                                AgentConversationCard(conversation: conversation)
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

    private var activeAgents: [AgentActivity] {
        // Return agents currently working on tasks
        var agents: [AgentActivity] = []

        // Local agent activity
        if let local = appState.localAgent, local.status.isConnected {
            let activeTasks = appState.activeTasks.prefix(2)
            agents.append(AgentActivity(
                id: local.id,
                name: local.name,
                status: .working,
                currentTask: activeTasks.first?.prompt,
                progressPercent: 0.65,
                recentActions: ["Reading files...", "Analyzing code structure"],
                isLocal: true
            ))
        }

        // Remote agents
        for agent in appState.connectedAgents where agent.status.isConnected {
            agents.append(AgentActivity(
                id: agent.id,
                name: agent.name,
                status: .idle,
                currentTask: nil,
                progressPercent: nil,
                recentActions: [],
                isLocal: false
            ))
        }

        return agents
    }

    private var agentConversations: [AgentConversation] {
        // Mock conversations for demo
        guard connectedAgentCount > 0 else { return [] }

        return [
            AgentConversation(
                id: "conv-1",
                participants: ["Local Agent", "Remote Agent"],
                topic: "Agent Discovery",
                messages: [
                    AgentMessage(sender: "Local Agent", content: "Hello! I'm a Claude Code agent running on Tim's MacBook. I specialize in Swift and TypeScript development.", timestamp: Date().addingTimeInterval(-60)),
                    AgentMessage(sender: "Remote Agent", content: "Nice to meet you! I'm running on the Home Mac Studio. I have access to GPU resources for ML tasks.", timestamp: Date().addingTimeInterval(-30)),
                    AgentMessage(sender: "Local Agent", content: "Great! We could collaborate on compute-intensive tasks. I'll handle code generation and you can run inference.", timestamp: Date())
                ],
                isActive: true
            )
        ]
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
    @State private var showDenyDialog = false
    @State private var denyReason = ""

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
                    Task {
                        await appState.approveRequest(approval)
                    }
                } label: {
                    Text("Approve")
                        .frame(width: 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    showDenyDialog = true
                } label: {
                    Text("Deny")
                        .frame(width: 80)
                }
                .buttonStyle(.bordered)
            }
            .alert("Deny Request", isPresented: $showDenyDialog) {
                TextField("Reason (optional)", text: $denyReason)
                Button("Cancel", role: .cancel) {
                    denyReason = ""
                }
                Button("Deny", role: .destructive) {
                    Task {
                        await appState.denyRequest(approval, reason: denyReason.isEmpty ? nil : denyReason)
                        denyReason = ""
                    }
                }
            } message: {
                Text("Optionally provide a reason for denying this request.")
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

// MARK: - Agent Activity Types

struct AgentActivity: Identifiable {
    let id: String
    let name: String
    let status: AgentActivityStatus
    let currentTask: String?
    let progressPercent: Double?
    let recentActions: [String]
    let isLocal: Bool

    enum AgentActivityStatus {
        case working, idle, waiting, error
    }
}

struct AgentConversation: Identifiable {
    let id: String
    let participants: [String]
    let topic: String
    let messages: [AgentMessage]
    let isActive: Bool
}

struct AgentMessage: Identifiable {
    let id = UUID()
    let sender: String
    let content: String
    let timestamp: Date
}

// MARK: - Agent Activity Card

struct AgentActivityCard: View {
    let agent: AgentActivity
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Animated status indicator
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 40, height: 40)

                    if agent.status == .working {
                        Circle()
                            .stroke(statusColor, lineWidth: 2)
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(isExpanded ? 360 : 0))
                            .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isExpanded)
                    }

                    Image(systemName: agent.isLocal ? "laptopcomputer" : "desktopcomputer")
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(agent.name)
                            .font(.headline)

                        if agent.status == .working {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        }
                    }

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Expand button
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Current task
            if let task = agent.currentTask {
                HStack(alignment: .top) {
                    Image(systemName: "arrow.right.circle")
                        .foregroundStyle(.blue)
                    Text(task)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Progress bar
            if let progress = agent.progressPercent {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 4)

                            Rectangle()
                                .fill(statusColor)
                                .frame(width: geo.size.width * progress, height: 4)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 4)

                    Text("\(Int(progress * 100))% complete")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Recent actions (expanded)
            if isExpanded && !agent.recentActions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Actions")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    ForEach(agent.recentActions, id: \.self) { action in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.secondary)
                                .frame(width: 4, height: 4)
                            Text(action)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { isExpanded = true }
    }

    private var statusColor: Color {
        switch agent.status {
        case .working: return .blue
        case .idle: return .green
        case .waiting: return .orange
        case .error: return .red
        }
    }

    private var statusText: String {
        switch agent.status {
        case .working: return "Working on task"
        case .idle: return "Ready"
        case .waiting: return "Waiting for input"
        case .error: return "Error"
        }
    }
}

// MARK: - Agent Conversation Card

struct AgentConversationCard: View {
    let conversation: AgentConversation
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.topic)
                        .font(.headline)

                    Text(conversation.participants.joined(separator: " ↔ "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if conversation.isActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("Active")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.1))
                    .clipShape(Capsule())
                }

                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Messages
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(conversation.messages) { message in
                        AgentMessageBubble(message: message)
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Agent Message Bubble

struct AgentMessageBubble: View {
    let message: AgentMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            Circle()
                .fill(avatarColor)
                .frame(width: 28, height: 28)
                .overlay {
                    Text(String(message.sender.prefix(1)))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.sender)
                        .font(.caption)
                        .fontWeight(.medium)

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(message.content)
                    .font(.subheadline)
                    .padding(10)
                    .background(avatarColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var avatarColor: Color {
        message.sender.contains("Local") ? .blue : .purple
    }
}

// MARK: - Getting Started Card

struct GettingStartedCard: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var serverManager = ServerManager.shared
    @State private var isStarting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(.linearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Goldeneye")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Your AI agent workspace")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // Steps
            VStack(alignment: .leading, spacing: 12) {
                StepRow(
                    number: 1,
                    title: "Start the local server",
                    description: "Launch the AgentKit server to enable AI capabilities",
                    isComplete: serverManager.isRunning
                )

                StepRow(
                    number: 2,
                    title: "Connect to your agent",
                    description: "Establish connection to start sending tasks",
                    isComplete: appState.isAgentConnected
                )

                StepRow(
                    number: 3,
                    title: "Submit your first task",
                    description: "Ask your agent to help with coding, research, or analysis",
                    isComplete: !appState.activeTasks.isEmpty || !appState.recentTasks.isEmpty
                )
            }

            Divider()

            // Quick actions
            HStack(spacing: 12) {
                if !serverManager.isRunning {
                    Button(action: startServer) {
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
                    Button(action: { Task { await appState.connectToLocalAgent() } }) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("Connect")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                Button(action: { appState.selectedSidebarItem = .settings }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.background.secondary)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
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

struct StepRow: View {
    let number: Int
    let title: String
    let description: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Step number/checkmark
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green : Color.secondary.opacity(0.2))
                    .frame(width: 28, height: 28)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(isComplete, color: .secondary)
                    .foregroundStyle(isComplete ? .secondary : .primary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }
}
