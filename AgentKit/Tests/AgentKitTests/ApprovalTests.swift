import Foundation
import Testing
@testable import AgentKit

// MARK: - ApprovalPolicy Tests

@Suite("ApprovalPolicy Tests")
struct ApprovalPolicyTests {

    // MARK: - Preset Tests

    @Test("Default policy requires approval for high-risk tools")
    func defaultPolicyHighRisk() {
        let policy = ApprovalPolicy.default

        // Bash is in alwaysApprove
        #expect(policy.requiresApproval(toolName: "Bash", riskLevel: .high) == true)
        // Write is in alwaysApprove
        #expect(policy.requiresApproval(toolName: "Write", riskLevel: .medium) == true)
        // Read is in neverApprove
        #expect(policy.requiresApproval(toolName: "Read", riskLevel: .low) == false)
        // Glob is in neverApprove
        #expect(policy.requiresApproval(toolName: "Glob", riskLevel: .low) == false)
    }

    @Test("Strict policy requires approval for everything")
    func strictPolicy() {
        let policy = ApprovalPolicy.strict

        // Everything requires approval (except low risk)
        #expect(policy.requiresApproval(toolName: "Read", riskLevel: .medium) == true)
        #expect(policy.requiresApproval(toolName: "Bash", riskLevel: .high) == true)
        #expect(policy.requiresApproval(toolName: "AnyTool", riskLevel: .critical) == true)

        // Only low risk can be auto-approved
        #expect(policy.requiresApproval(toolName: "AnyTool", riskLevel: .low) == false)
    }

    @Test("Permissive policy auto-approves most actions")
    func permissivePolicy() {
        let policy = ApprovalPolicy.permissive

        // Common tools are in neverApprove
        #expect(policy.requiresApproval(toolName: "Read", riskLevel: .low) == false)
        #expect(policy.requiresApproval(toolName: "Write", riskLevel: .medium) == false)
        #expect(policy.requiresApproval(toolName: "Bash", riskLevel: .high) == false)

        // Only critical risk requires approval for unknown tools
        #expect(policy.requiresApproval(toolName: "UnknownTool", riskLevel: .high) == false)
        #expect(policy.requiresApproval(toolName: "UnknownTool", riskLevel: .critical) == true)
    }

    // MARK: - Always/Never Approve Lists

    @Test("AlwaysApprove list takes precedence")
    func alwaysApproveList() {
        let policy = ApprovalPolicy(
            alwaysApprove: ["DangerousTool"],
            maxAutoApproveRisk: .high
        )

        // Even with high auto-approve risk, alwaysApprove wins
        #expect(policy.requiresApproval(toolName: "DangerousTool", riskLevel: .low) == true)
        #expect(policy.requiresApproval(toolName: "DangerousTool", riskLevel: .high) == true)
    }

    @Test("NeverApprove list bypasses approval")
    func neverApproveList() {
        let policy = ApprovalPolicy(
            neverApprove: ["SafeTool"],
            maxAutoApproveRisk: .low
        )

        // Even with low auto-approve risk, neverApprove bypasses
        #expect(policy.requiresApproval(toolName: "SafeTool", riskLevel: .high) == false)
        #expect(policy.requiresApproval(toolName: "SafeTool", riskLevel: .critical) == false)
    }

    @Test("NeverApprove takes precedence over alwaysApprove")
    func neverOverAlways() {
        let policy = ApprovalPolicy(
            alwaysApprove: ["TestTool"],
            neverApprove: ["TestTool"]
        )

        // neverApprove is checked first
        #expect(policy.requiresApproval(toolName: "TestTool", riskLevel: .high) == false)
    }

    // MARK: - Risk Level Tests

    @Test("Risk level threshold enforcement")
    func riskLevelThreshold() {
        let policy = ApprovalPolicy(maxAutoApproveRisk: .medium)

        // Low and medium are auto-approved
        #expect(policy.requiresApproval(toolName: "Tool", riskLevel: .low) == false)
        #expect(policy.requiresApproval(toolName: "Tool", riskLevel: .medium) == false)

        // High and critical require approval
        #expect(policy.requiresApproval(toolName: "Tool", riskLevel: .high) == true)
        #expect(policy.requiresApproval(toolName: "Tool", riskLevel: .critical) == true)
    }

    @Test("Critical risk always requires approval by default")
    func criticalRiskDefault() {
        let policy = ApprovalPolicy(maxAutoApproveRisk: .low)

        #expect(policy.requiresApproval(toolName: "AnyTool", riskLevel: .critical) == true)
    }

    // MARK: - Pattern Tests

    @Test("AlwaysRequire pattern forces approval")
    func alwaysRequirePattern() {
        let policy = ApprovalPolicy(
            alwaysRequirePatterns: ["rm -rf", "sudo"],
            maxAutoApproveRisk: .high
        )

        // Pattern match forces approval even for low risk
        #expect(policy.requiresApproval(
            toolName: "Bash",
            riskLevel: .low,
            actionDescription: "rm -rf /tmp/test"
        ) == true)

        #expect(policy.requiresApproval(
            toolName: "Bash",
            riskLevel: .low,
            actionDescription: "sudo apt install"
        ) == true)
    }

    @Test("AutoApprove pattern bypasses approval")
    func autoApprovePattern() {
        let policy = ApprovalPolicy(
            autoApprovePatterns: ["git status", "ls -la"],
            maxAutoApproveRisk: .low
        )

        // Pattern match bypasses approval even for high risk
        #expect(policy.requiresApproval(
            toolName: "Bash",
            riskLevel: .high,
            actionDescription: "git status"
        ) == false)

        #expect(policy.requiresApproval(
            toolName: "Bash",
            riskLevel: .high,
            actionDescription: "ls -la /home"
        ) == false)
    }

    @Test("AlwaysRequire pattern takes precedence over autoApprove")
    func patternPrecedence() {
        let policy = ApprovalPolicy(
            autoApprovePatterns: ["git"],
            alwaysRequirePatterns: ["git push"]
        )

        // git status matches autoApprove
        #expect(policy.requiresApproval(
            toolName: "Bash",
            riskLevel: .high,
            actionDescription: "git status"
        ) == false)

        // git push matches alwaysRequire which is checked first
        #expect(policy.requiresApproval(
            toolName: "Bash",
            riskLevel: .low,
            actionDescription: "git push origin main"
        ) == true)
    }

    @Test("Regex patterns work correctly")
    func regexPatterns() {
        let policy = ApprovalPolicy(
            alwaysRequirePatterns: ["rm\\s+-rf"],
            maxAutoApproveRisk: .high
        )

        #expect(policy.requiresApproval(
            toolName: "Bash",
            riskLevel: .low,
            actionDescription: "rm -rf /tmp"
        ) == true)

        // Doesn't match without the space
        #expect(policy.requiresApproval(
            toolName: "Bash",
            riskLevel: .low,
            actionDescription: "rm-rf"  // Not a real command, but tests regex
        ) == false)
    }

    // MARK: - No Action Description

    @Test("Policy works without action description")
    func noActionDescription() {
        let policy = ApprovalPolicy(
            alwaysRequirePatterns: ["dangerous"],
            maxAutoApproveRisk: .medium
        )

        // Without description, falls back to risk level check
        #expect(policy.requiresApproval(toolName: "Tool", riskLevel: .medium) == false)
        #expect(policy.requiresApproval(toolName: "Tool", riskLevel: .high) == true)
    }

    // MARK: - Encoding/Decoding

    @Test("Policy encoding and decoding")
    func policyCodable() throws {
        let original = ApprovalPolicy(
            alwaysApprove: ["Bash", "Write"],
            neverApprove: ["Read"],
            trustAfterCount: 5,
            autoApprovePatterns: ["git status"],
            alwaysRequirePatterns: ["rm -rf"],
            maxAutoApproveRisk: .medium,
            defaultTimeout: .seconds(60)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ApprovalPolicy.self, from: encoded)

        #expect(decoded.alwaysApprove == original.alwaysApprove)
        #expect(decoded.neverApprove == original.neverApprove)
        #expect(decoded.trustAfterCount == 5)
        #expect(decoded.maxAutoApproveRisk == .medium)
    }
}

// MARK: - ApprovalTrustTracker Tests

@Suite("ApprovalTrustTracker Tests")
struct ApprovalTrustTrackerTests {

    @Test("Trust accumulates with approvals")
    func trustAccumulation() async {
        let policy = ApprovalPolicy(trustAfterCount: 3)
        let tracker = ApprovalTrustTracker(policy: policy)

        // Not trusted initially
        var trusted = await tracker.isTrusted(toolName: "Bash")
        #expect(trusted == false)

        // Record approvals
        await tracker.recordApproval(toolName: "Bash")
        await tracker.recordApproval(toolName: "Bash")

        // Still not trusted (need 3)
        trusted = await tracker.isTrusted(toolName: "Bash")
        #expect(trusted == false)

        // Third approval
        await tracker.recordApproval(toolName: "Bash")

        // Now trusted
        trusted = await tracker.isTrusted(toolName: "Bash")
        #expect(trusted == true)
    }

    @Test("Trust is per-tool")
    func trustPerTool() async {
        let policy = ApprovalPolicy(trustAfterCount: 2)
        let tracker = ApprovalTrustTracker(policy: policy)

        // Build trust for Bash
        await tracker.recordApproval(toolName: "Bash")
        await tracker.recordApproval(toolName: "Bash")

        // Bash is trusted
        let bashTrusted = await tracker.isTrusted(toolName: "Bash")
        #expect(bashTrusted == true)

        // Write is not trusted
        let writeTrusted = await tracker.isTrusted(toolName: "Write")
        #expect(writeTrusted == false)
    }

    @Test("Reset trust for specific tool")
    func resetToolTrust() async {
        let policy = ApprovalPolicy(trustAfterCount: 2)
        let tracker = ApprovalTrustTracker(policy: policy)

        // Build trust
        await tracker.recordApproval(toolName: "Bash")
        await tracker.recordApproval(toolName: "Bash")
        await tracker.recordApproval(toolName: "Write")
        await tracker.recordApproval(toolName: "Write")

        // Both trusted
        var bashTrusted = await tracker.isTrusted(toolName: "Bash")
        var writeTrusted = await tracker.isTrusted(toolName: "Write")
        #expect(bashTrusted == true)
        #expect(writeTrusted == true)

        // Reset Bash only
        await tracker.resetTrust(toolName: "Bash")

        bashTrusted = await tracker.isTrusted(toolName: "Bash")
        writeTrusted = await tracker.isTrusted(toolName: "Write")
        #expect(bashTrusted == false)
        #expect(writeTrusted == true)
    }

    @Test("Reset all trust")
    func resetAllTrust() async {
        let policy = ApprovalPolicy(trustAfterCount: 2)
        let tracker = ApprovalTrustTracker(policy: policy)

        // Build trust for multiple tools
        await tracker.recordApproval(toolName: "Bash")
        await tracker.recordApproval(toolName: "Bash")
        await tracker.recordApproval(toolName: "Write")
        await tracker.recordApproval(toolName: "Write")

        // Reset all
        await tracker.resetAllTrust()

        // Nothing is trusted
        let bashTrusted = await tracker.isTrusted(toolName: "Bash")
        let writeTrusted = await tracker.isTrusted(toolName: "Write")
        #expect(bashTrusted == false)
        #expect(writeTrusted == false)
    }

    @Test("No trust threshold means never trusted")
    func noTrustThreshold() async {
        let policy = ApprovalPolicy(trustAfterCount: nil)
        let tracker = ApprovalTrustTracker(policy: policy)

        // Record many approvals
        for _ in 0..<10 {
            await tracker.recordApproval(toolName: "Bash")
        }

        // Still not trusted (no threshold set)
        let trusted = await tracker.isTrusted(toolName: "Bash")
        #expect(trusted == false)
    }
}
