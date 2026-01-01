# AgentKit Management UI

Native macOS application for managing local and remote agents with full control capabilities.

## Overview

| Aspect | Choice |
|--------|--------|
| Platform | macOS (SwiftUI) |
| Scope | Full control (pause/resume, edit, fork) |
| Agents | Local + remote (via A2A) |
| Distribution | Direct download (V1), App Store (future) |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    AgentKit Console (macOS)                      │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                      SwiftUI Views                          │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │ │
│  │  │Dashboard │ │  Tasks   │ │ Sessions │ │   Settings   │  │ │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│  ┌───────────────────────────┴───────────────────────────────┐  │
│  │                    AgentKitClient                          │  │
│  │  ┌─────────────────┐  ┌─────────────────────────────────┐ │  │
│  │  │ A2A Client      │  │ Agent Registry                  │ │  │
│  │  │ (JSON-RPC/SSE)  │  │ (local + discovered remotes)    │ │  │
│  │  └─────────────────┘  └─────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│  ┌───────────────────────────┴───────────────────────────────┐  │
│  │                  System Integration                        │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │  │
│  │  │Menu Bar  │ │Notif.    │ │Shortcuts │ │ Spotlight    │  │  │
│  │  │(NSStatusItem)│(UNUser) │ │(AppIntent)│ │(CSSearchable)│  │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
           │                    │                    │
           ▼                    ▼                    ▼
    ┌────────────┐      ┌────────────┐      ┌────────────┐
    │ Local Agent│      │Remote Agent│      │Remote Agent│
    │ :8080      │      │ 192.168... │      │ agent.com  │
    └────────────┘      └────────────┘      └────────────┘
```

---

## Core Features

### 1. Agent Registry

Manage connections to local and remote agents.

```swift
@Observable
class AgentRegistry {
    var agents: [RegisteredAgent] = []

    struct RegisteredAgent: Identifiable, Codable {
        let id: UUID
        var name: String
        var endpoint: URL                    // A2A endpoint
        var card: A2AAgentCard?             // Cached agent card
        var status: ConnectionStatus
        var isLocal: Bool
        var lastSeen: Date
    }

    enum ConnectionStatus {
        case connected
        case connecting
        case disconnected
        case error(String)
    }

    // Discovery
    func discoverLocal() async                          // Bonjour/mDNS
    func addRemote(endpoint: URL) async throws
    func refreshCard(_ agent: RegisteredAgent) async throws
}
```

### 2. Dashboard View

At-a-glance status of all agents and tasks.

```swift
struct DashboardView: View {
    @Environment(AgentRegistry.self) var registry
    @Environment(TaskManager.self) var tasks

    var body: some View {
        NavigationSplitView {
            // Sidebar: Agent list
            List(registry.agents) { agent in
                AgentRow(agent: agent)
            }
        } detail: {
            // Main content
            VStack {
                // Active tasks summary
                ActiveTasksGrid(tasks: tasks.active)

                // Pending approvals (prominent)
                if !tasks.pendingApprovals.isEmpty {
                    PendingApprovalsSection(approvals: tasks.pendingApprovals)
                }

                // Recent events stream
                EventStreamView()
            }
        }
    }
}
```

### 3. Task Control

Full lifecycle management for each task.

```swift
struct TaskDetailView: View {
    let task: A2ATask
    @Environment(TaskManager.self) var manager

    var body: some View {
        VStack {
            // Status header
            TaskStatusHeader(task: task)

            // Conversation history
            ScrollView {
                ForEach(task.history ?? []) { message in
                    MessageBubble(message: message)
                }
            }

            // Control bar
            HStack {
                // Inject message mid-task
                TextField("Send message...", text: $newMessage)
                Button("Send") { manager.sendMessage(task.id, newMessage) }

                Divider()

                // Lifecycle controls
                Button("Pause") { manager.pause(task.id) }
                Button("Resume") { manager.resume(task.id) }
                Button("Cancel", role: .destructive) { manager.cancel(task.id) }

                // Advanced
                Menu("More") {
                    Button("Fork Session") { manager.fork(task.id) }
                    Button("Export History") { manager.export(task.id) }
                    Button("View in Git") { openGitRepo(task) }
                }
            }
        }
    }
}
```

### 4. HITL Approval Interface

Handle approval requests with full context.

```swift
struct ApprovalSheet: View {
    let request: ApprovalRequest
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header with risk level indicator
            HStack {
                RiskBadge(level: request.riskLevel)
                Text(request.action)
                    .font(.headline)
            }

            // Details
            Text(request.description)
                .font(.body)

            // Parameters (expandable)
            if let params = request.parameters {
                DisclosureGroup("Details") {
                    ParameterGrid(params: params)
                }
            }

            // For plan approvals: step-by-step review
            if case .plan(let plan) = request {
                PlanReviewView(plan: plan)
            }

            // For input requests: form fields
            if case .input(let input) = request {
                InputFormView(input: input, value: $inputValue)
            }

            Divider()

            // Actions
            HStack {
                Button("Deny", role: .destructive) {
                    respond(.denied(reason: nil))
                }

                if request.canModify {
                    Button("Modify...") {
                        showModifySheet = true
                    }
                }

                Button("Approve") {
                    respond(.approved)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 400)
    }
}
```

### 5. Session Browser

Inspect and manage agent sessions with git integration.

```swift
struct SessionBrowserView: View {
    let agent: RegisteredAgent
    @State var sessions: [AgentSession] = []

    var body: some View {
        List(sessions) { session in
            NavigationLink(destination: SessionDetailView(session: session)) {
                VStack(alignment: .leading) {
                    Text(session.name)
                        .font(.headline)
                    Text(session.lastActivity, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            Button("Clone Repository") { cloneRepo(session) }
            Button("View Git Log") { showGitLog(session) }
            Divider()
            Button("Delete Session", role: .destructive) { delete(session) }
        }
    }
}

struct SessionDetailView: View {
    let session: AgentSession

    var body: some View {
        HSplitView {
            // File browser (from git working tree)
            FileTreeView(root: session.workingDirectory)

            // Git history
            GitLogView(repo: session.gitRepo)
        }
    }
}
```

### 6. Settings & Configuration

Agent and policy configuration.

```swift
struct SettingsView: View {
    var body: some View {
        TabView {
            // Agent connections
            AgentConnectionsSettings()
                .tabItem { Label("Agents", systemImage: "server.rack") }

            // Approval policies
            ApprovalPolicySettings()
                .tabItem { Label("Approvals", systemImage: "hand.raised") }

            // Notifications
            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell") }

            // Shortcuts integration
            ShortcutsSettings()
                .tabItem { Label("Shortcuts", systemImage: "arrow.triangle.branch") }
        }
    }
}
```

---

## System Integration

### Menu Bar Presence

Always-available status and quick actions.

```swift
@main
struct AgentKitConsoleApp: App {
    @State var menuBarManager = MenuBarManager()

    var body: some Scene {
        // Main window
        WindowGroup {
            ContentView()
        }

        // Menu bar extra
        MenuBarExtra("AgentKit", systemImage: "brain") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        // Settings
        Settings {
            SettingsView()
        }
    }
}

struct MenuBarView: View {
    @Environment(TaskManager.self) var tasks

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Quick status
            HStack {
                Circle()
                    .fill(tasks.hasActiveWork ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text("\(tasks.active.count) active tasks")
            }

            // Pending approvals (if any)
            if !tasks.pendingApprovals.isEmpty {
                Divider()
                Text("Pending Approvals")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(tasks.pendingApprovals.prefix(3)) { approval in
                    ApprovalQuickAction(approval: approval)
                }
            }

            Divider()

            Button("Open Console") { openMainWindow() }
            Button("New Task...") { showNewTaskSheet() }

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 280)
    }
}
```

### Push Notifications

Alert for approvals and task completions.

```swift
class NotificationManager {
    func requestPermission() async throws {
        let center = UNUserNotificationCenter.current()
        try await center.requestAuthorization(options: [.alert, .sound, .badge])

        // Register approval action category
        let approve = UNNotificationAction(identifier: "APPROVE", title: "Approve", options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: "DENY", title: "Deny", options: [.destructive])
        let view = UNNotificationAction(identifier: "VIEW", title: "View", options: [.foreground])

        let category = UNNotificationCategory(
            identifier: "AGENT_APPROVAL",
            actions: [approve, deny, view],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    func notifyApprovalNeeded(_ request: ApprovalRequest) async {
        let content = UNMutableNotificationContent()
        content.title = "Agent Needs Approval"
        content.subtitle = request.action
        content.body = request.description
        content.categoryIdentifier = "AGENT_APPROVAL"
        content.userInfo = [
            "request_id": request.id,
            "agent_id": request.agentId
        ]
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: request.id,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
```

### Shortcuts / Siri Integration

Voice and automation control.

```swift
// List pending approvals
struct ListPendingApprovalsIntent: AppIntent {
    static var title: LocalizedStringResource = "List Pending Agent Approvals"

    func perform() async throws -> some IntentResult & ReturnsValue<[ApprovalEntity]> {
        let approvals = await TaskManager.shared.pendingApprovals
        return .result(value: approvals.map { ApprovalEntity($0) })
    }
}

// Approve by voice
struct ApproveActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Approve Agent Action"

    @Parameter(title: "Approval")
    var approval: ApprovalEntity

    func perform() async throws -> some IntentResult {
        try await TaskManager.shared.respond(approval.id, decision: .approved)
        return .result(dialog: "Approved: \(approval.action)")
    }
}

// Start a new task
struct StartAgentTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Agent Task"

    @Parameter(title: "Agent")
    var agent: AgentEntity

    @Parameter(title: "Task")
    var taskDescription: String

    func perform() async throws -> some IntentResult & ReturnsValue<TaskEntity> {
        let task = try await agent.sendMessage(taskDescription)
        return .result(value: TaskEntity(task), dialog: "Started task on \(agent.name)")
    }
}

// "Hey Siri, what are my agents working on?"
struct AgentStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Agent Status"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let tasks = await TaskManager.shared.active
        if tasks.isEmpty {
            return .result(dialog: "No agents are currently working.")
        }
        let summary = tasks.map { "\($0.agentName): \($0.status.state)" }.joined(separator: ". ")
        return .result(dialog: summary)
    }
}
```

### Spotlight Integration

Search tasks and sessions.

```swift
import CoreSpotlight

class SpotlightManager {
    func indexTask(_ task: A2ATask) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
        attributeSet.title = "Task: \(task.id)"
        attributeSet.contentDescription = task.history?.first?.textContent
        attributeSet.keywords = ["agent", "task", task.status.state.rawValue]

        let item = CSSearchableItem(
            uniqueIdentifier: "task:\(task.id)",
            domainIdentifier: "com.agentkit.tasks",
            attributeSet: attributeSet
        )

        CSSearchableIndex.default().indexSearchableItems([item])
    }
}
```

---

## Agent Discovery

### Local Discovery (Bonjour)

Find agents on local network.

```swift
class AgentDiscovery: NSObject, NetServiceBrowserDelegate {
    private let browser = NetServiceBrowser()
    private let serviceType = "_agentkit._tcp."

    func startDiscovery() {
        browser.delegate = self
        browser.searchForServices(ofType: serviceType, inDomain: "local.")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.resolve(withTimeout: 5.0)
        // Extract endpoint from TXT record, add to registry
    }
}

// Server side: advertise via Bonjour
class AgentAdvertiser {
    private var service: NetService?

    func advertise(port: Int) {
        service = NetService(domain: "local.", type: "_agentkit._tcp.", name: "AgentKit", port: Int32(port))
        service?.setTXTRecord(NetService.data(fromTXTRecord: [
            "version": "1.0".data(using: .utf8)!,
            "a2a": "/a2a".data(using: .utf8)!
        ]))
        service?.publish()
    }
}
```

### Remote Agent Registration

Manual addition of remote agents.

```swift
struct AddRemoteAgentSheet: View {
    @State var endpoint: String = ""
    @State var isValidating = false
    @State var validationResult: ValidationResult?

    var body: some View {
        Form {
            TextField("Endpoint URL", text: $endpoint)
                .textContentType(.URL)

            if let result = validationResult {
                switch result {
                case .success(let card):
                    Label("Found: \(card.name)", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                case .failure(let error):
                    Label(error.localizedDescription, systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Button("Validate") {
                    Task { await validate() }
                }
                .disabled(endpoint.isEmpty || isValidating)

                Button("Add") {
                    Task { await add() }
                }
                .disabled(validationResult?.isSuccess != true)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    func validate() async {
        isValidating = true
        defer { isValidating = false }

        guard let url = URL(string: endpoint) else {
            validationResult = .failure(ValidationError.invalidURL)
            return
        }

        do {
            let cardURL = url.appendingPathComponent(".well-known/agent.json")
            let (data, _) = try await URLSession.shared.data(from: cardURL)
            let card = try JSONDecoder().decode(A2AAgentCard.self, from: data)
            validationResult = .success(card)
        } catch {
            validationResult = .failure(error)
        }
    }
}
```

---

## Package Structure

```
AgentKitConsole/
├── Package.swift
├── Sources/
│   └── AgentKitConsole/
│       ├── App/
│       │   ├── AgentKitConsoleApp.swift
│       │   └── MenuBarManager.swift
│       ├── Views/
│       │   ├── Dashboard/
│       │   │   ├── DashboardView.swift
│       │   │   └── ActiveTasksGrid.swift
│       │   ├── Tasks/
│       │   │   ├── TaskListView.swift
│       │   │   ├── TaskDetailView.swift
│       │   │   └── MessageBubble.swift
│       │   ├── Approvals/
│       │   │   ├── ApprovalSheet.swift
│       │   │   ├── PlanReviewView.swift
│       │   │   └── RiskBadge.swift
│       │   ├── Sessions/
│       │   │   ├── SessionBrowserView.swift
│       │   │   ├── FileTreeView.swift
│       │   │   └── GitLogView.swift
│       │   └── Settings/
│       │       ├── SettingsView.swift
│       │       └── ApprovalPolicySettings.swift
│       ├── Models/
│       │   ├── AgentRegistry.swift
│       │   ├── TaskManager.swift
│       │   └── ApprovalManager.swift
│       ├── Networking/
│       │   ├── A2AClient.swift
│       │   └── SSEClient.swift
│       ├── Intents/
│       │   ├── ApprovalIntents.swift
│       │   ├── TaskIntents.swift
│       │   └── StatusIntents.swift
│       └── System/
│           ├── NotificationManager.swift
│           ├── SpotlightManager.swift
│           └── AgentDiscovery.swift
└── Tests/
```

---

## V1 Scope

### Phase 1 (Core UI)
- [ ] Dashboard with agent list and task overview
- [ ] Task detail view with history
- [ ] Basic approval handling (approve/deny)
- [ ] Settings for agent connections

### Phase 2 (Full Control)
- [ ] Pause/resume/cancel tasks
- [ ] Inject messages mid-task
- [ ] Fork sessions
- [ ] Git integration (view commits, clone)

### Phase 3 (System Integration)
- [ ] Menu bar presence
- [ ] Push notifications with actions
- [ ] AppIntents for Siri/Shortcuts
- [ ] Bonjour discovery

### Future
- [ ] Spotlight indexing
- [ ] Widget for pending approvals
- [ ] iOS companion app
- [ ] Multi-window support

---

## Dependencies

```swift
// Package.swift
dependencies: [
    // Shared types with AgentKit
    .package(path: "../AgentKit"),
]
```

The console shares `A2ATypes`, `ApprovalTypes`, etc. with the main AgentKit package.

---

## Open Questions

1. **Single app or two?** — Console + Server as one app, or separate?
2. **Embedded server?** — Run local AgentKit server inside the console app?
3. **Document-based?** — Treat sessions as documents (File → Open Session)?
4. **Sync settings?** — Use iCloud for agent registry across devices?

---

## References

- [SwiftUI on macOS](https://developer.apple.com/documentation/swiftui/building-a-great-mac-app-with-swiftui)
- [Menu Bar Extras](https://developer.apple.com/documentation/swiftui/menubarextra)
- [App Intents](https://developer.apple.com/documentation/appintents)
- [Bonjour/mDNS](https://developer.apple.com/bonjour/)
