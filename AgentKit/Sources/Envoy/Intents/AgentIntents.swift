import AppIntents
import SwiftUI

// MARK: - App Shortcuts Provider

struct AgentKitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunTaskIntent(),
            phrases: [
                "Run a task with \(.applicationName)",
                "Ask \(.applicationName) to \(\.$prompt)",
                "Have \(.applicationName) do \(\.$prompt)"
            ],
            shortTitle: "Run Task",
            systemImageName: "brain"
        )

        AppShortcut(
            intent: ApproveAllIntent(),
            phrases: [
                "Approve all pending in \(.applicationName)",
                "Approve all \(.applicationName) requests"
            ],
            shortTitle: "Approve All",
            systemImageName: "checkmark.shield"
        )

        AppShortcut(
            intent: CheckAgentStatusIntent(),
            phrases: [
                "Check \(.applicationName) status",
                "Is \(.applicationName) running",
                "Agent status"
            ],
            shortTitle: "Agent Status",
            systemImageName: "heart.text.square"
        )
    }
}

// MARK: - Run Task Intent

struct RunTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Agent Task"
    static let description = IntentDescription("Run a task with the AI agent")

    @Parameter(title: "Prompt", description: "What would you like the agent to do?")
    var prompt: String

    @Parameter(title: "Wait for Completion", default: false)
    var waitForCompletion: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$prompt)") {
            \.$waitForCompletion
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // In a real implementation, this would connect to the agent
        // For now, return a placeholder response

        let response: String
        if waitForCompletion {
            response = "Task submitted: \(prompt). Waiting for completion..."
            // Would await actual task completion here
        } else {
            response = "Task submitted: \(prompt)"
        }

        return .result(
            value: response,
            dialog: IntentDialog(stringLiteral: response)
        )
    }
}

// MARK: - Approve All Intent

struct ApproveAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Approve All Pending"
    static let description = IntentDescription("Approve all pending tool executions")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // In a real implementation, this would call the approval manager
        let approvedCount = 0  // Would get actual count

        let message =
            approvedCount > 0
            ? "Approved \(approvedCount) pending requests"
            : "No pending requests to approve"

        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Check Status Intent

struct CheckAgentStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Agent Status"
    static let description = IntentDescription("Check the status of the AI agent")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // In a real implementation, this would check actual agent status
        let status = "Local agent: Disconnected\nRemote agents: 0 connected"

        return .result(
            value: status,
            dialog: IntentDialog(stringLiteral: status)
        )
    }
}

// MARK: - Get Pending Approvals Intent

struct GetPendingApprovalsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Pending Approvals"
    static let description = IntentDescription("List pending approval requests")

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        // In a real implementation, this would fetch actual pending approvals
        let approvals: [String] = []

        let message =
            approvals.isEmpty
            ? "No pending approvals"
            : "Pending: \(approvals.joined(separator: ", "))"

        return .result(
            value: approvals,
            dialog: IntentDialog(stringLiteral: message)
        )
    }
}

// MARK: - Cancel Task Intent

struct CancelTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Cancel Task"
    static let description = IntentDescription("Cancel a running task")

    @Parameter(title: "Task ID")
    var taskId: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Cancel task \(\.$taskId)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let taskId = taskId {
            // Would cancel specific task
            return .result(dialog: IntentDialog(stringLiteral: "Cancelled task: \(taskId)"))
        } else {
            // Would cancel most recent task
            return .result(dialog: IntentDialog(stringLiteral: "Cancelled most recent task"))
        }
    }
}

// MARK: - Respond to Approval Intent

struct RespondToApprovalIntent: AppIntent {
    static let title: LocalizedStringResource = "Respond to Approval"
    static let description = IntentDescription("Approve or deny a specific request")

    @Parameter(title: "Approval ID")
    var approvalId: String

    @Parameter(title: "Approve")
    var approve: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$approve, .equalTo, true) {
            Summary("Approve \(\.$approvalId)")
        } otherwise: {
            Summary("Deny \(\.$approvalId)")
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let action = approve ? "Approved" : "Denied"
        return .result(dialog: IntentDialog(stringLiteral: "\(action) request: \(approvalId)"))
    }
}

// MARK: - Connect Agent Intent

struct ConnectAgentIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect to Agent"
    static let description = IntentDescription("Connect to an AI agent")

    @Parameter(title: "Agent URL")
    var url: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Connect to \(\.$url)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let url = url {
            // Would connect to specified agent
            return .result(dialog: IntentDialog(stringLiteral: "Connecting to \(url)..."))
        } else {
            // Would connect to local agent
            return .result(dialog: IntentDialog(stringLiteral: "Connecting to local agent..."))
        }
    }
}
