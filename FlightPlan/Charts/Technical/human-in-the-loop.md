# Human-in-the-Loop (HITL) System

AgentKit supports approval workflows, checkpoints, and interactive input via A2A's `INPUT_REQUIRED` state and Apple platform integration.

## Why HITL?

| Scenario | Example |
|----------|---------|
| **Safety** | Approve before deleting files |
| **Authorization** | Confirm before making purchases |
| **Clarification** | Agent needs more info to proceed |
| **Review** | Human validates agent's plan before execution |
| **Compliance** | Audit trail with explicit approvals |

---

## A2A Integration

The A2A protocol has native support for HITL via the `INPUT_REQUIRED` task state.

### Task State Flow

```
SUBMITTED → WORKING → INPUT_REQUIRED → WORKING → COMPLETED
                          ↑                ↓
                     (human input)    (continue)
```

### A2A Message with Input Request

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "id": "task-123",
    "status": {
      "state": "TASK_STATE_INPUT_REQUIRED",
      "message": {
        "role": "agent",
        "parts": [{
          "kind": "data",
          "data": {
            "type": "approval_request",
            "action": "delete_files",
            "files": ["report.md", "draft.txt"],
            "message": "Delete these 2 files?",
            "options": ["approve", "deny", "modify"]
          }
        }]
      }
    }
  }
}
```

### Resuming with User Input

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "SendMessage",
  "params": {
    "message": {
      "role": "user",
      "task_id": "task-123",
      "parts": [{
        "kind": "data",
        "data": {
          "type": "approval_response",
          "decision": "approve"
        }
      }]
    }
  }
}
```

---

## Approval Types

### 1. Action Approval

Before executing a potentially dangerous action:

```swift
enum ApprovalRequest: Codable, Sendable {
    case action(ActionApproval)
    case plan(PlanApproval)
    case input(InputRequest)
    case confirmation(ConfirmationRequest)
}

struct ActionApproval: Codable, Sendable {
    let id: String
    let action: String              // "delete_files", "run_command", "send_email"
    let description: String         // Human-readable description
    let parameters: [String: AnyCodable]  // Action details
    let risk: RiskLevel             // low, medium, high, critical
    let timeout: Duration?          // Auto-deny after timeout
}

enum RiskLevel: String, Codable {
    case low        // Informational, auto-approve option
    case medium     // Requires explicit approval
    case high       // Requires approval, shows warning
    case critical   // Requires approval + confirmation code
}
```

### 2. Plan Approval

Review multi-step plan before execution:

```swift
struct PlanApproval: Codable, Sendable {
    let id: String
    let title: String
    let steps: [PlanStep]
    let estimatedDuration: Duration?
    let canModify: Bool             // User can edit steps
}

struct PlanStep: Codable, Sendable {
    let order: Int
    let action: String
    let description: String
    let isOptional: Bool
    var isApproved: Bool            // Per-step approval
}
```

### 3. Input Request

Agent needs additional information:

```swift
struct InputRequest: Codable, Sendable {
    let id: String
    let question: String
    let inputType: InputType
    let required: Bool
    let defaultValue: String?
}

enum InputType: Codable {
    case text
    case number(min: Double?, max: Double?)
    case choice(options: [String])
    case multiChoice(options: [String])
    case date
    case file
}
```

### 4. Confirmation

Simple yes/no with explanation:

```swift
struct ConfirmationRequest: Codable, Sendable {
    let id: String
    let message: String
    let details: String?
    let confirmLabel: String        // "Delete", "Send", "Proceed"
    let cancelLabel: String         // "Cancel", "Go Back"
}
```

---

## Apple Platform Integration

### 1. Push Notifications

Alert users on any device when approval needed:

```swift
import UserNotifications

func sendApprovalNotification(_ request: ApprovalRequest) async throws {
    let content = UNMutableNotificationContent()
    content.title = "Agent Needs Approval"
    content.body = request.description
    content.categoryIdentifier = "AGENT_APPROVAL"
    content.userInfo = ["request_id": request.id, "task_id": request.taskId]
    content.interruptionLevel = .timeSensitive

    // Add action buttons
    let approveAction = UNNotificationAction(
        identifier: "APPROVE",
        title: "Approve",
        options: [.authenticationRequired]
    )
    let denyAction = UNNotificationAction(
        identifier: "DENY",
        title: "Deny",
        options: [.destructive]
    )
    let viewAction = UNNotificationAction(
        identifier: "VIEW",
        title: "View Details",
        options: [.foreground]
    )

    let category = UNNotificationCategory(
        identifier: "AGENT_APPROVAL",
        actions: [approveAction, denyAction, viewAction],
        intentIdentifiers: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([category])

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(
        identifier: request.id,
        content: content,
        trigger: trigger
    )
    try await UNUserNotificationCenter.current().add(request)
}
```

### 2. Live Activities (iOS 16.1+)

Show ongoing task with approval button on Lock Screen:

```swift
import ActivityKit

struct AgentTaskAttributes: ActivityAttributes {
    let taskId: String
    let agentName: String

    struct ContentState: Codable, Hashable {
        var status: String
        var pendingApproval: ApprovalSummary?
        var progress: Double
    }
}

struct ApprovalSummary: Codable, Hashable {
    let id: String
    let action: String
    let message: String
}

// Start activity when task begins
func startTaskActivity(_ task: AgentTask) async throws {
    let attributes = AgentTaskAttributes(taskId: task.id, agentName: task.agentName)
    let state = AgentTaskAttributes.ContentState(
        status: "Working...",
        pendingApproval: nil,
        progress: 0.0
    )
    let activity = try Activity.request(
        attributes: attributes,
        content: .init(state: state, staleDate: nil)
    )
}

// Update when approval needed
func updateActivityForApproval(_ approval: ApprovalRequest) async {
    let state = AgentTaskAttributes.ContentState(
        status: "Waiting for approval",
        pendingApproval: ApprovalSummary(
            id: approval.id,
            action: approval.action,
            message: approval.description
        ),
        progress: 0.5
    )
    await activity.update(using: state)
}
```

### 3. App Intents (Siri, Shortcuts, Spotlight)

Approve via voice or Shortcuts:

```swift
import AppIntents

struct ApproveAgentActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Approve Agent Action"
    static var description = IntentDescription("Approve a pending agent action")

    @Parameter(title: "Request ID")
    var requestId: String

    @Parameter(title: "Decision")
    var decision: ApprovalDecision

    enum ApprovalDecision: String, AppEnum {
        case approve
        case deny

        static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Decision")
        static var caseDisplayRepresentations: [ApprovalDecision: DisplayRepresentation] = [
            .approve: "Approve",
            .deny: "Deny"
        ]
    }

    func perform() async throws -> some IntentResult {
        let client = AgentKitClient.shared
        try await client.respondToApproval(requestId: requestId, decision: decision)
        return .result(dialog: "Action \(decision == .approve ? "approved" : "denied")")
    }
}

// Siri: "Hey Siri, approve agent action"
// Shortcuts: Can chain with other automations
```

### 4. Handoff (Continuity)

Start reviewing on Mac, approve on iPhone:

```swift
// On Mac (where agent is running)
func advertiseApprovalActivity(_ approval: ApprovalRequest) {
    let activity = NSUserActivity(activityType: "com.agentkit.approval")
    activity.title = "Approve: \(approval.action)"
    activity.userInfo = [
        "request_id": approval.id,
        "task_id": approval.taskId,
        "action": approval.action
    ]
    activity.isEligibleForHandoff = true
    activity.becomeCurrent()
}

// On iPhone (receiving handoff)
.onContinueUserActivity("com.agentkit.approval") { activity in
    if let requestId = activity.userInfo?["request_id"] as? String {
        showApprovalSheet(requestId: requestId)
    }
}
```

### 5. Widget (Quick Glance + Approve)

Interactive widget showing pending approvals:

```swift
import WidgetKit
import AppIntents

struct PendingApprovalsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "PendingApprovals",
            provider: ApprovalsProvider()
        ) { entry in
            ApprovalsWidgetView(entry: entry)
        }
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ApprovalsWidgetView: View {
    let entry: ApprovalsEntry

    var body: some View {
        VStack(alignment: .leading) {
            Text("Pending Approvals")
                .font(.headline)

            ForEach(entry.approvals) { approval in
                HStack {
                    VStack(alignment: .leading) {
                        Text(approval.action)
                            .font(.subheadline)
                        Text(approval.message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Interactive buttons (iOS 17+)
                    Button(intent: ApproveIntent(requestId: approval.id)) {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .tint(.green)

                    Button(intent: DenyIntent(requestId: approval.id)) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .tint(.red)
                }
            }
        }
    }
}
```

---

## AgentKit Core Integration

### ApprovalManager Actor

```swift
actor ApprovalManager {
    private var pendingApprovals: [String: PendingApproval] = [:]
    private var continuations: [String: CheckedContinuation<ApprovalResponse, Error>] = [:]

    struct PendingApproval {
        let request: ApprovalRequest
        let createdAt: Date
        let timeout: Duration?
        let taskId: String
    }

    /// Request approval and suspend until response received
    func requestApproval(
        _ request: ApprovalRequest,
        taskId: String,
        timeout: Duration? = nil
    ) async throws -> ApprovalResponse {

        let id = request.id

        // Store pending approval
        pendingApprovals[id] = PendingApproval(
            request: request,
            createdAt: .now,
            timeout: timeout,
            taskId: taskId
        )

        // Notify user via configured channels
        await notifyUser(request)

        // Suspend until response or timeout
        return try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation

            // Set up timeout if specified
            if let timeout {
                Task {
                    try await Task.sleep(for: timeout)
                    if continuations[id] != nil {
                        self.respondToApproval(id: id, response: .timeout)
                    }
                }
            }
        }
    }

    /// Called when user responds (from notification, widget, API, etc.)
    func respondToApproval(id: String, response: ApprovalResponse) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        pendingApprovals.removeValue(forKey: id)
        continuation.resume(returning: response)
    }

    private func notifyUser(_ request: ApprovalRequest) async {
        // Send push notification
        try? await sendApprovalNotification(request)

        // Update Live Activity if active
        await updateActivityForApproval(request)

        // Advertise for Handoff
        advertiseApprovalActivity(request)

        // Update widget
        WidgetCenter.shared.reloadTimelines(ofKind: "PendingApprovals")
    }
}
```

### Agent Loop Integration

```swift
// In AgentLoop
func executeToolWithApproval(_ tool: Tool, input: ToolInput) async throws -> ToolOutput {
    // Check if tool requires approval
    if tool.requiresApproval {
        let request = ApprovalRequest.action(ActionApproval(
            id: UUID().uuidString,
            action: tool.name,
            description: tool.describeAction(input),
            parameters: input.parameters,
            risk: tool.riskLevel,
            timeout: .seconds(300)  // 5 minute timeout
        ))

        // This suspends until user responds
        let response = try await approvalManager.requestApproval(
            request,
            taskId: currentTask.id
        )

        switch response {
        case .approved:
            break  // Continue to execute
        case .denied(let reason):
            throw AgentError.actionDenied(tool: tool.name, reason: reason)
        case .modified(let newInput):
            return try await tool.execute(newInput, context: toolContext)
        case .timeout:
            throw AgentError.approvalTimeout(tool: tool.name)
        }
    }

    return try await tool.execute(input, context: toolContext)
}
```

### Tool Approval Configuration

```swift
protocol Tool {
    // ...existing...

    /// Whether this tool requires human approval
    var requiresApproval: Bool { get }

    /// Risk level for approval UI
    var riskLevel: RiskLevel { get }

    /// Generate human-readable description of what this action will do
    func describeAction(_ input: ToolInput) -> String
}

// Example: Bash tool with approval
struct BashTool: Tool {
    var requiresApproval: Bool {
        // Could be configurable per-command
        true
    }

    var riskLevel: RiskLevel {
        .high  // Shell commands are risky
    }

    func describeAction(_ input: ToolInput) -> String {
        let command = input.get("command", as: String.self) ?? ""
        return "Run command: \(command)"
    }
}
```

---

## Approval Policies

Configurable rules for when to require approval:

```swift
struct ApprovalPolicy: Codable {
    /// Tools that always require approval
    var alwaysApprove: Set<ToolID>

    /// Tools that never require approval (trusted)
    var neverApprove: Set<ToolID>

    /// Auto-approve after N successful approvals
    var trustAfterCount: Int?

    /// Auto-approve if action matches pattern
    var autoApprovePatterns: [String]

    /// Always require approval for these patterns
    var alwaysRequirePatterns: [String]

    /// Maximum auto-approve risk level
    var maxAutoApproveRisk: RiskLevel

    /// Timeout before auto-denying (nil = no timeout)
    var defaultTimeout: Duration?
}

// Example policy
let policy = ApprovalPolicy(
    alwaysApprove: ["Bash", "Write", "Delete"],
    neverApprove: ["Read", "Glob", "Grep"],
    trustAfterCount: 5,  // Auto-approve Bash after 5 manual approvals
    autoApprovePatterns: ["git status", "ls -la"],
    alwaysRequirePatterns: ["rm -rf", "sudo", "curl.*| sh"],
    maxAutoApproveRisk: .low,
    defaultTimeout: .minutes(5)
)
```

---

## Git Integration

Approvals are committed to the Git history:

```
* [Approval] Approved: delete_files (files: report.md, draft.txt)
* [Write] Created report.md
* [Approval] Approved: run_command (command: npm install)
* [Bash] Ran npm install
```

```swift
func commitApprovalResponse(_ request: ApprovalRequest, _ response: ApprovalResponse) async throws {
    let message = switch response {
    case .approved:
        "[Approval] Approved: \(request.action)"
    case .denied(let reason):
        "[Approval] Denied: \(request.action) - \(reason ?? "No reason")"
    case .modified:
        "[Approval] Modified: \(request.action)"
    case .timeout:
        "[Approval] Timeout: \(request.action)"
    }
    try await session.commit(message: message)
}
```

---

## V1 Scope

### Phase 1 (Core)
- [ ] `ApprovalRequest` types
- [ ] `ApprovalManager` actor
- [ ] A2A `INPUT_REQUIRED` state handling
- [ ] HTTP endpoint for approval responses
- [ ] Basic web UI for approvals

### Phase 2 (Apple Integration)
- [ ] Push notifications with actions
- [ ] App Intent for Siri/Shortcuts approval
- [ ] Widget for pending approvals

### Future
- [ ] Live Activities
- [ ] Handoff between devices
- [ ] Apple Watch approval
- [ ] Face ID/Touch ID for high-risk actions

---

## References

- [A2A Protocol: Human-in-the-Loop](https://a2a-protocol.org/latest/specification/)
- [Microsoft: Function Tools with Approvals](https://learn.microsoft.com/en-us/agent-framework/tutorials/agents/function-tools-approvals)
- [Live Activities + Notifications](https://medium.com/@saritasa/ios-development-guide-live-activities-actionable-notifications-with-swiftui-2a3dc56bf63c)
- [App Intents in SwiftUI](https://www.avanderlee.com/swift/app-intent-driven-development/)
