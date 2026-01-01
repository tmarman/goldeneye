import Foundation
import Logging

// MARK: - Approval Manager

/// Manages approval requests and responses using async continuations
public actor ApprovalManager {
    private var pendingApprovals: [String: PendingApproval] = [:]
    private var continuations: [String: CheckedContinuation<ApprovalResponse, Error>] = [:]
    private let logger = Logger(label: "AgentKit.ApprovalManager")

    /// Delegate for notifications
    public weak var delegate: ApprovalDelegate?

    public init() {}

    // MARK: - Request Approval

    /// Request approval and suspend until response received
    public func requestApproval(
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

        logger.info("Requesting approval", metadata: [
            "id": "\(id)",
            "action": "\(request.action)",
            "risk": "\(request.riskLevel)",
        ])

        // Notify delegate
        await delegate?.approvalRequested(request)

        // Suspend until response or timeout
        return try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation

            // Set up timeout if specified
            if let timeout = timeout {
                Task {
                    try await Task.sleep(for: timeout)
                    if continuations[id] != nil {
                        respondToApproval(id: id, response: .timeout)
                    }
                }
            }
        }
    }

    // MARK: - Respond to Approval

    /// Called when user responds (from notification, widget, API, etc.)
    public func respondToApproval(id: String, response: ApprovalResponse) {
        guard let continuation = continuations.removeValue(forKey: id) else {
            logger.warning("No pending approval found", metadata: ["id": "\(id)"])
            return
        }

        let pending = pendingApprovals.removeValue(forKey: id)

        logger.info("Approval response", metadata: [
            "id": "\(id)",
            "response": "\(response)",
        ])

        // Notify delegate
        if let pending = pending {
            Task {
                await delegate?.approvalResponded(pending.request, response: response)
            }
        }

        continuation.resume(returning: response)
    }

    // MARK: - Query State

    /// Get all pending approvals
    public func pending() -> [ApprovalRequest] {
        pendingApprovals.values.map(\.request)
    }

    /// Get pending approval by ID
    public func get(_ id: String) -> ApprovalRequest? {
        pendingApprovals[id]?.request
    }

    /// Check if an approval is pending
    public func isPending(_ id: String) -> Bool {
        pendingApprovals[id] != nil
    }

    /// Cancel a pending approval
    public func cancel(_ id: String) {
        if let continuation = continuations.removeValue(forKey: id) {
            pendingApprovals.removeValue(forKey: id)
            continuation.resume(throwing: ApprovalError.cancelled)
        }
    }
}

// MARK: - Pending Approval

private struct PendingApproval: Sendable {
    let request: ApprovalRequest
    let createdAt: Date
    let timeout: Duration?
    let taskId: String
}

// MARK: - Approval Delegate

/// Delegate protocol for approval notifications
public protocol ApprovalDelegate: AnyObject, Sendable {
    /// Called when an approval is requested
    func approvalRequested(_ request: ApprovalRequest) async

    /// Called when an approval is responded to
    func approvalResponded(_ request: ApprovalRequest, response: ApprovalResponse) async
}

// MARK: - Errors

public enum ApprovalError: Error, Sendable {
    case cancelled
    case notFound(String)
    case alreadyResponded(String)
}
