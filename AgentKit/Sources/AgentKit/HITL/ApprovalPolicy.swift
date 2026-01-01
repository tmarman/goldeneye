import Foundation

// MARK: - Approval Policy

/// Configurable rules for when to require approval
public struct ApprovalPolicy: Sendable, Codable {
    /// Tools that always require approval
    public var alwaysApprove: Set<String>

    /// Tools that never require approval (trusted)
    public var neverApprove: Set<String>

    /// Auto-approve after N successful approvals for a tool
    public var trustAfterCount: Int?

    /// Auto-approve if action matches pattern
    public var autoApprovePatterns: [String]

    /// Always require approval for these patterns
    public var alwaysRequirePatterns: [String]

    /// Maximum risk level that can be auto-approved
    public var maxAutoApproveRisk: RiskLevel

    /// Default timeout before auto-denying
    public var defaultTimeout: Duration?

    public init(
        alwaysApprove: Set<String> = [],
        neverApprove: Set<String> = [],
        trustAfterCount: Int? = nil,
        autoApprovePatterns: [String] = [],
        alwaysRequirePatterns: [String] = [],
        maxAutoApproveRisk: RiskLevel = .low,
        defaultTimeout: Duration? = nil
    ) {
        self.alwaysApprove = alwaysApprove
        self.neverApprove = neverApprove
        self.trustAfterCount = trustAfterCount
        self.autoApprovePatterns = autoApprovePatterns
        self.alwaysRequirePatterns = alwaysRequirePatterns
        self.maxAutoApproveRisk = maxAutoApproveRisk
        self.defaultTimeout = defaultTimeout
    }

    // MARK: - Presets

    /// Default policy: require approval for high-risk actions
    public static let `default` = ApprovalPolicy(
        alwaysApprove: ["Bash", "Write"],
        neverApprove: ["Read", "Glob", "Grep"],
        maxAutoApproveRisk: .low,
        defaultTimeout: .seconds(300)
    )

    /// Strict policy: require approval for everything
    public static let strict = ApprovalPolicy(
        alwaysApprove: [],
        neverApprove: [],
        maxAutoApproveRisk: .low,
        defaultTimeout: .seconds(120)
    )

    /// Permissive policy: approve most actions automatically
    public static let permissive = ApprovalPolicy(
        alwaysApprove: [],
        neverApprove: ["Read", "Glob", "Grep", "Write", "Bash"],
        maxAutoApproveRisk: .high,
        defaultTimeout: nil
    )

    // MARK: - Evaluation

    /// Determine if a tool requires approval
    public func requiresApproval(
        toolName: String,
        riskLevel: RiskLevel,
        actionDescription: String? = nil
    ) -> Bool {
        // Check explicit lists first
        if neverApprove.contains(toolName) {
            return false
        }

        if alwaysApprove.contains(toolName) {
            return true
        }

        // Check patterns
        if let desc = actionDescription {
            for pattern in alwaysRequirePatterns {
                if desc.range(of: pattern, options: .regularExpression) != nil {
                    return true
                }
            }

            for pattern in autoApprovePatterns {
                if desc.range(of: pattern, options: .regularExpression) != nil {
                    return false
                }
            }
        }

        // Check risk level
        return riskLevel > maxAutoApproveRisk
    }
}

// MARK: - Trust Tracker

/// Tracks approval history to enable trust-based auto-approval
public actor ApprovalTrustTracker {
    private var approvalCounts: [String: Int] = [:]
    private let policy: ApprovalPolicy

    public init(policy: ApprovalPolicy) {
        self.policy = policy
    }

    /// Record an approval
    public func recordApproval(toolName: String) {
        approvalCounts[toolName, default: 0] += 1
    }

    /// Check if tool has earned trust through repeated approvals
    public func isTrusted(toolName: String) -> Bool {
        guard let threshold = policy.trustAfterCount else { return false }
        return approvalCounts[toolName, default: 0] >= threshold
    }

    /// Reset trust for a tool
    public func resetTrust(toolName: String) {
        approvalCounts.removeValue(forKey: toolName)
    }

    /// Reset all trust
    public func resetAllTrust() {
        approvalCounts.removeAll()
    }
}
