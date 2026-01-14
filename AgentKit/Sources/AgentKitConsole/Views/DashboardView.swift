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

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Icon with subtle glow
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(color)
                }

                Spacer()

                // Subtle trend indicator
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(color.opacity(isHovered ? 0.8 : 0.4))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isHovered ? color.opacity(0.25) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(
            color: isHovered ? color.opacity(0.15) : .black.opacity(0.05),
            radius: isHovered ? 12 : 6,
            y: isHovered ? 4 : 2
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Dashboard Section

struct DashboardSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                // Icon with subtle background
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 26, height: 26)

                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Text(title)
                    .font(.headline)

                // Subtle line separator
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
            }

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
    @State private var isHovered = false
    @State private var pulseRisk = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Enhanced risk indicator with pulse for high/critical
            ZStack {
                if approval.riskLevel == .high || approval.riskLevel == .critical {
                    Circle()
                        .fill(riskColor.opacity(0.2))
                        .frame(width: 56, height: 56)
                        .scaleEffect(pulseRisk ? 1.2 : 1.0)
                        .opacity(pulseRisk ? 0 : 0.6)
                }

                RiskBadge(level: approval.riskLevel)
            }

            // Details
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(approval.toolName)
                        .font(.headline)

                    Spacer()

                    Text("Just now")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(approval.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !approval.parameters.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(approval.parameters.prefix(3)), id: \.key) { key, value in
                            HStack(spacing: 4) {
                                Text(key)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(value)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 16)

            // Enhanced action buttons
            VStack(spacing: 8) {
                Button {
                    Task {
                        await appState.approveRequest(approval)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text("Approve")
                    }
                    .frame(width: 90)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    showDenyDialog = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Deny")
                    }
                    .frame(width: 90)
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
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isHovered ? riskColor.opacity(0.3) : Color.primary.opacity(0.06),
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .shadow(
            color: isHovered ? riskColor.opacity(0.12) : .black.opacity(0.05),
            radius: isHovered ? 10 : 5,
            y: isHovered ? 4 : 2
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear {
            if approval.riskLevel == .high || approval.riskLevel == .critical {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulseRisk = true
                }
            }
        }
    }

    private var riskColor: Color {
        switch approval.riskLevel {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
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
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Enhanced state icon
            ZStack {
                Circle()
                    .fill(stateColor.opacity(0.12))
                    .frame(width: 32, height: 32)

                stateIcon
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(task.prompt)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    Text(task.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Enhanced state badge
            HStack(spacing: 4) {
                if task.state == .working {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                }

                Text(stateLabel)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(stateColor.opacity(0.1), in: Capsule())
            .foregroundStyle(stateColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.primary.opacity(0.04) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch task.state {
        case .working:
            ProgressView()
                .scaleEffect(0.6)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.red)
        case .inputRequired:
            Image(systemName: "questionmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)
        default:
            Image(systemName: "circle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var stateLabel: String {
        switch task.state {
        case .completed: return "Done"
        case .failed: return "Failed"
        case .working: return "Running"
        case .inputRequired: return "Input needed"
        default: return task.state.rawValue
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
    @State private var isHovered = false
    @State private var pulseAnimation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Animated status indicator with pulse
                ZStack {
                    // Pulse ring for working state
                    if agent.status == .working {
                        Circle()
                            .stroke(statusColor.opacity(0.3), lineWidth: 2)
                            .frame(width: 44, height: 44)
                            .scaleEffect(pulseAnimation ? 1.4 : 1.0)
                            .opacity(pulseAnimation ? 0 : 0.8)
                    }

                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 40, height: 40)

                    if agent.status == .working {
                        // Spinning arc indicator
                        Circle()
                            .trim(from: 0, to: 0.3)
                            .stroke(statusColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(pulseAnimation ? 360 : 0))
                    }

                    Image(systemName: agent.isLocal ? "laptopcomputer" : "desktopcomputer")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(agent.name)
                            .font(.headline)

                        if agent.status == .working {
                            Text("●")
                                .font(.system(size: 8))
                                .foregroundStyle(statusColor)
                                .opacity(pulseAnimation ? 1 : 0.3)
                        }
                    }

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(agent.status == .working ? "Active" : "Ready")
                        .font(.caption2.weight(.medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.1), in: Capsule())

                // Expand button
                Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                        )
                }
                .buttonStyle(.plain)
            }

            // Current task with better styling
            if let task = agent.currentTask {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)

                    Text(task)
                        .font(.subheadline)
                        .lineLimit(2)
                        .foregroundStyle(.primary.opacity(0.9))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.blue.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.blue.opacity(0.15), lineWidth: 1)
                        )
                )
            }

            // Enhanced progress bar
            if let progress = agent.progressPercent {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Track
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 6)

                            // Progress fill with gradient
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [statusColor, statusColor.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * progress, height: 6)

                            // Shimmer effect on progress
                            if agent.status == .working {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, .white.opacity(0.3), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: 40, height: 6)
                                    .offset(x: pulseAnimation ? geo.size.width * progress : -40)
                            }
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("\(Int(progress * 100))% complete")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if agent.status == .working {
                            Text("In progress...")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            // Recent actions (expanded) with better animation
            if isExpanded && !agent.recentActions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recent Actions")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(agent.recentActions.count) items")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }

                    ForEach(Array(agent.recentActions.enumerated()), id: \.offset) { index, action in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(width: 18, height: 18)

                                Text("\(index + 1)")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }

                            Text(action)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isHovered ? statusColor.opacity(0.2) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(
            color: .black.opacity(isHovered ? 0.08 : 0.04),
            radius: isHovered ? 10 : 5,
            y: isHovered ? 4 : 2
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear {
            isExpanded = true
            // Start animations
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                pulseAnimation = true
            }
        }
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
