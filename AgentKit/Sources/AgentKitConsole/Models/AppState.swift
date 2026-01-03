import AgentKit
import Combine
import Foundation
import SwiftUI

/// Global application state for the Console app
@MainActor
public final class AppState: ObservableObject {
    // MARK: - Navigation

    @Published var selectedSidebarItem: SidebarItem = .dashboard
    @Published var showNewTaskSheet = false
    @Published var showConnectSheet = false

    // MARK: - Agents

    @Published var connectedAgents: [ConnectedAgent] = []
    @Published var localAgent: ConnectedAgent?

    // MARK: - Tasks

    @Published var activeTasks: [TaskInfo] = []
    @Published var recentTasks: [TaskInfo] = []

    // MARK: - Approvals

    @Published var pendingApprovals: [PendingApproval] = []

    // MARK: - Menu Bar

    var menuBarIcon: String {
        if !pendingApprovals.isEmpty {
            return "brain.fill"
        } else if activeTasks.contains(where: { $0.state == .working }) {
            return "brain"
        }
        return "brain"
    }

    // MARK: - Initialization

    init() {
        // Start with a mock local agent for development
        localAgent = ConnectedAgent(
            id: "local",
            name: "Local Agent",
            url: URL(string: "http://127.0.0.1:8080")!,
            status: .disconnected
        )
    }

    // MARK: - Actions

    func connectToLocalAgent() async {
        guard var agent = localAgent else { return }
        agent.status = .connecting
        localAgent = agent

        // Simulate connection delay
        try? await Task.sleep(for: .milliseconds(500))

        agent.status = .connected
        localAgent = agent
    }

    func approveAllPending() async {
        // In a real implementation, this would call the approval manager
        pendingApprovals.removeAll()
    }

    func submitTask(_ prompt: String, to agent: ConnectedAgent) async {
        let task = TaskInfo(
            id: UUID().uuidString,
            agentId: agent.id,
            prompt: prompt,
            state: .submitted,
            createdAt: Date()
        )
        activeTasks.append(task)
    }
}

// MARK: - Supporting Types

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard
    case tasks
    case sessions
    case approvals
    case agents

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: "Dashboard"
        case .tasks: "Tasks"
        case .sessions: "Sessions"
        case .approvals: "Approvals"
        case .agents: "Agents"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .tasks: "list.bullet.rectangle"
        case .sessions: "clock.arrow.circlepath"
        case .approvals: "checkmark.shield"
        case .agents: "point.3.connected.trianglepath.dotted"
        }
    }
}

struct ConnectedAgent: Identifiable, Hashable {
    let id: String
    var name: String
    var url: URL
    var status: AgentConnectionStatus
    var card: AgentCard?

    static func == (lhs: ConnectedAgent, rhs: ConnectedAgent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum AgentConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var color: Color {
        switch self {
        case .disconnected: .secondary
        case .connecting: .orange
        case .connected: .green
        case .error: .red
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct TaskInfo: Identifiable, Hashable {
    let id: String
    let agentId: String
    let prompt: String
    var state: TaskState
    let createdAt: Date
    var completedAt: Date?
    var messages: [Message] = []

    static func == (lhs: TaskInfo, rhs: TaskInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PendingApproval: Identifiable, Hashable {
    let id: String
    let taskId: String
    let agentId: String
    let toolName: String
    let description: String
    let riskLevel: RiskLevel
    let parameters: [String: String]
    let createdAt: Date

    static func == (lhs: PendingApproval, rhs: PendingApproval) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
