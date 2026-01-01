import Foundation

// MARK: - Approval Request

/// Request for human approval
public enum ApprovalRequest: Sendable, Identifiable {
    case action(ActionApproval)
    case plan(PlanApproval)
    case input(InputRequest)
    case confirmation(ConfirmationRequest)

    public var id: String {
        switch self {
        case .action(let a): return a.id
        case .plan(let p): return p.id
        case .input(let i): return i.id
        case .confirmation(let c): return c.id
        }
    }

    public var taskId: String {
        switch self {
        case .action(let a): return a.taskId
        case .plan(let p): return p.taskId
        case .input(let i): return i.taskId
        case .confirmation(let c): return c.taskId
        }
    }

    public var riskLevel: RiskLevel {
        switch self {
        case .action(let a): return a.risk
        case .plan: return .medium
        case .input: return .low
        case .confirmation(let c): return c.risk
        }
    }

    public var description: String {
        switch self {
        case .action(let a): return a.description
        case .plan(let p): return p.title
        case .input(let i): return i.question
        case .confirmation(let c): return c.message
        }
    }

    public var action: String {
        switch self {
        case .action(let a): return a.action
        case .plan: return "Review Plan"
        case .input: return "Provide Input"
        case .confirmation: return "Confirm"
        }
    }

    public var canModify: Bool {
        switch self {
        case .action: return true
        case .plan(let p): return p.canModify
        case .input: return false
        case .confirmation: return false
        }
    }
}

// MARK: - Action Approval

/// Approval for a potentially dangerous action
public struct ActionApproval: Sendable, Codable {
    public let id: String
    public let taskId: String
    public let action: String
    public let description: String
    public let parameters: [String: AnyCodable]
    public let risk: RiskLevel
    public let timeout: Duration?

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        action: String,
        description: String,
        parameters: [String: AnyCodable] = [:],
        risk: RiskLevel = .medium,
        timeout: Duration? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.action = action
        self.description = description
        self.parameters = parameters
        self.risk = risk
        self.timeout = timeout
    }
}

// MARK: - Plan Approval

/// Approval for a multi-step plan
public struct PlanApproval: Sendable, Codable {
    public let id: String
    public let taskId: String
    public let title: String
    public let steps: [PlanStep]
    public let estimatedDuration: Duration?
    public let canModify: Bool

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        title: String,
        steps: [PlanStep],
        estimatedDuration: Duration? = nil,
        canModify: Bool = true
    ) {
        self.id = id
        self.taskId = taskId
        self.title = title
        self.steps = steps
        self.estimatedDuration = estimatedDuration
        self.canModify = canModify
    }
}

public struct PlanStep: Sendable, Codable, Identifiable {
    public let id: String
    public let order: Int
    public let action: String
    public let description: String
    public let isOptional: Bool
    public var isApproved: Bool

    public init(
        id: String = UUID().uuidString,
        order: Int,
        action: String,
        description: String,
        isOptional: Bool = false,
        isApproved: Bool = true
    ) {
        self.id = id
        self.order = order
        self.action = action
        self.description = description
        self.isOptional = isOptional
        self.isApproved = isApproved
    }
}

// MARK: - Input Request

/// Request for additional information
public struct InputRequest: Sendable, Codable {
    public let id: String
    public let taskId: String
    public let question: String
    public let inputType: InputType
    public let required: Bool
    public let defaultValue: String?

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        question: String,
        inputType: InputType = .text,
        required: Bool = true,
        defaultValue: String? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.question = question
        self.inputType = inputType
        self.required = required
        self.defaultValue = defaultValue
    }
}

public enum InputType: Sendable, Codable {
    case text
    case number(min: Double?, max: Double?)
    case choice(options: [String])
    case multiChoice(options: [String])
    case date
    case file
}

// MARK: - Confirmation Request

/// Simple yes/no confirmation
public struct ConfirmationRequest: Sendable, Codable {
    public let id: String
    public let taskId: String
    public let message: String
    public let details: String?
    public let confirmLabel: String
    public let cancelLabel: String
    public let risk: RiskLevel

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        message: String,
        details: String? = nil,
        confirmLabel: String = "Confirm",
        cancelLabel: String = "Cancel",
        risk: RiskLevel = .medium
    ) {
        self.id = id
        self.taskId = taskId
        self.message = message
        self.details = details
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
        self.risk = risk
    }
}

// MARK: - Approval Response

/// Response to an approval request
public enum ApprovalResponse: Sendable {
    case approved
    case denied(reason: String?)
    case modified(ToolInput)
    case timeout
}
