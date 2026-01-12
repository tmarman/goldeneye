import Foundation

// MARK: - Decision Card Manager

/// Orchestrates the lifecycle of Decision Cards across agents and user interactions.
///
/// Flow:
/// 1. Agent creates a decision card via `submit()`
/// 2. Card enters pending queue, UI shows notification
/// 3. User reviews: approves, requests changes, or dismisses
/// 4. Manager notifies the requesting agent of the outcome
/// 5. Agent takes action based on decision
///
/// This is the "PR workflow" for agent actions - agents propose, users review.
public actor DecisionCardManager {

    // MARK: - Properties

    /// All decision cards (pending and resolved)
    private var _cards: [DecisionCardID: DecisionCard] = [:]

    /// Callbacks waiting for decision outcomes
    private var _pendingCallbacks: [DecisionCardID: DecisionCallback] = [:]

    /// Observers for card state changes
    private var _observers: [DecisionObserver] = []

    // MARK: - Initialization

    public init() {}

    // MARK: - Card Submission

    /// Submit a new decision card for review
    /// - Parameters:
    ///   - card: The decision card to submit
    ///   - callback: Optional callback when decision is made
    /// - Returns: The submitted card ID
    @discardableResult
    public func submit(_ card: DecisionCard, callback: DecisionCallback? = nil) -> DecisionCardID {
        _cards[card.id] = card

        if let callback = callback {
            _pendingCallbacks[card.id] = callback
        }

        // Notify observers of new card
        notifyObservers(.cardSubmitted(card))

        return card.id
    }

    /// Convenience method for agents to create and submit a decision card
    public func requestDecision(
        title: String,
        description: String,
        sourceType: DecisionSourceType,
        sourceId: String? = nil,
        requestedBy agentId: AgentID,
        callback: DecisionCallback? = nil
    ) -> DecisionCardID {
        let card = DecisionCard(
            title: title,
            description: description,
            sourceType: sourceType,
            sourceId: sourceId,
            requestedBy: agentId.rawValue
        )
        return submit(card, callback: callback)
    }

    // MARK: - Card Actions

    /// Approve a decision card
    public func approve(_ cardId: DecisionCardID, by reviewer: String, comment: String? = nil) async {
        guard var card = _cards[cardId] else { return }

        card.approve(by: reviewer, comment: comment)
        _cards[cardId] = card

        // Execute callback
        if let callback = _pendingCallbacks.removeValue(forKey: cardId) {
            await callback.onDecision(.approved, card)
        }

        notifyObservers(.cardUpdated(card))
    }

    /// Request changes on a decision card
    public func requestChanges(_ cardId: DecisionCardID, by reviewer: String, comment: String) async {
        guard var card = _cards[cardId] else { return }

        card.requestChanges(by: reviewer, comment: comment)
        _cards[cardId] = card

        // Execute callback
        if let callback = _pendingCallbacks.removeValue(forKey: cardId) {
            await callback.onDecision(.changesRequested, card)
        }

        notifyObservers(.cardUpdated(card))
    }

    /// Dismiss a decision card
    public func dismiss(_ cardId: DecisionCardID, by reviewer: String, reason: String? = nil) async {
        guard var card = _cards[cardId] else { return }

        card.dismiss(by: reviewer, reason: reason)
        _cards[cardId] = card

        // Execute callback
        if let callback = _pendingCallbacks.removeValue(forKey: cardId) {
            await callback.onDecision(.dismissed, card)
        }

        notifyObservers(.cardUpdated(card))
    }

    /// Add a comment to a decision card
    public func addComment(_ cardId: DecisionCardID, comment: DecisionComment) {
        guard var card = _cards[cardId] else { return }

        card.addComment(comment)
        _cards[cardId] = card

        notifyObservers(.commentAdded(card, comment))
    }

    /// Resubmit a card after making requested changes
    public func resubmit(_ cardId: DecisionCardID, updatedDescription: String? = nil) {
        guard var card = _cards[cardId], card.status == .changesRequested else { return }

        if let description = updatedDescription {
            card.description = description
        }
        card.status = .pending
        card.updatedAt = Date()

        // Add resubmission to history
        let review = DecisionReview(
            action: .reopened,
            reviewer: card.requestedBy ?? "Agent",
            comment: "Resubmitted with changes"
        )
        card.reviewHistory.append(review)

        _cards[cardId] = card
        notifyObservers(.cardUpdated(card))
    }

    // MARK: - Card Queries

    /// Get all cards
    public var cards: [DecisionCard] {
        Array(_cards.values).sorted { $0.createdAt > $1.createdAt }
    }

    /// Get cards that need action
    public var pendingCards: [DecisionCard] {
        cards.filter { $0.isActionable }
    }

    /// Get a specific card
    public func card(_ id: DecisionCardID) -> DecisionCard? {
        _cards[id]
    }

    /// Get cards by status
    public func cards(withStatus status: DecisionStatus) -> [DecisionCard] {
        cards.filter { $0.status == status }
    }

    /// Get cards from a specific agent
    public func cards(from agentId: AgentID) -> [DecisionCard] {
        cards.filter { $0.requestedBy == agentId.rawValue }
    }

    /// Get cards for a specific source
    public func cards(forSource sourceId: String) -> [DecisionCard] {
        cards.filter { $0.sourceId == sourceId }
    }

    // MARK: - Observers

    /// Add an observer for card events
    public func addObserver(_ observer: DecisionObserver) {
        _observers.append(observer)
    }

    /// Remove an observer
    public func removeObserver(_ id: String) {
        _observers.removeAll { $0.id == id }
    }

    private func notifyObservers(_ event: DecisionEvent) {
        for observer in _observers {
            Task {
                await observer.onEvent(event)
            }
        }
    }

    // MARK: - Batch Operations

    /// Approve all pending cards from a specific agent (bulk action)
    public func approveAll(from agentId: AgentID, by reviewer: String) async {
        let agentCards = cards(from: agentId).filter { $0.isActionable }
        for card in agentCards {
            await approve(card.id, by: reviewer, comment: "Bulk approved")
        }
    }

    /// Get statistics about decisions
    public var statistics: DecisionStatistics {
        let allCards = cards
        return DecisionStatistics(
            total: allCards.count,
            pending: allCards.filter { $0.status == .pending }.count,
            approved: allCards.filter { $0.status == .approved }.count,
            changesRequested: allCards.filter { $0.status == .changesRequested }.count,
            dismissed: allCards.filter { $0.status == .dismissed }.count
        )
    }
}

// MARK: - Decision Callback

/// Callback for when a decision is made on a card
public struct DecisionCallback: Sendable {
    public let id: String
    public let onDecision: @Sendable (DecisionStatus, DecisionCard) async -> Void

    public init(id: String = UUID().uuidString, onDecision: @escaping @Sendable (DecisionStatus, DecisionCard) async -> Void) {
        self.id = id
        self.onDecision = onDecision
    }
}

// MARK: - Decision Observer

/// Observer for decision card events
public struct DecisionObserver: Sendable {
    public let id: String
    public let onEvent: @Sendable (DecisionEvent) async -> Void

    public init(id: String = UUID().uuidString, onEvent: @escaping @Sendable (DecisionEvent) async -> Void) {
        self.id = id
        self.onEvent = onEvent
    }
}

// MARK: - Decision Event

/// Events emitted by the DecisionCardManager
public enum DecisionEvent: Sendable {
    case cardSubmitted(DecisionCard)
    case cardUpdated(DecisionCard)
    case commentAdded(DecisionCard, DecisionComment)
}

// MARK: - Decision Statistics

public struct DecisionStatistics: Sendable {
    public let total: Int
    public let pending: Int
    public let approved: Int
    public let changesRequested: Int
    public let dismissed: Int

    public var approvalRate: Double {
        guard total > 0 else { return 0 }
        return Double(approved) / Double(total - pending)
    }
}

// MARK: - Agent Decision Request

/// Represents a decision request from an agent, with context about what happens next
public struct AgentDecisionRequest: Sendable {
    public let card: DecisionCard
    public let onApproved: @Sendable () async -> Void
    public let onRejected: @Sendable (String?) async -> Void
    public let onChangesRequested: @Sendable (String) async -> Void

    public init(
        card: DecisionCard,
        onApproved: @escaping @Sendable () async -> Void,
        onRejected: @escaping @Sendable (String?) async -> Void = { _ in },
        onChangesRequested: @escaping @Sendable (String) async -> Void = { _ in }
    ) {
        self.card = card
        self.onApproved = onApproved
        self.onRejected = onRejected
        self.onChangesRequested = onChangesRequested
    }

    /// Create a callback that routes to the appropriate handler
    public func asCallback() -> DecisionCallback {
        DecisionCallback(id: card.id.rawValue) { status, updatedCard in
            switch status {
            case .approved:
                await self.onApproved()
            case .dismissed, .expired:
                let reason = updatedCard.reviewHistory.last?.comment
                await self.onRejected(reason)
            case .changesRequested:
                let comment = updatedCard.reviewHistory.last?.comment ?? ""
                await self.onChangesRequested(comment)
            case .pending:
                break // Still pending, no action
            }
        }
    }
}

// MARK: - Convenience Extensions

extension DecisionCardManager {
    /// Submit a decision request from an agent with typed callbacks
    public func submit(_ request: AgentDecisionRequest) -> DecisionCardID {
        submit(request.card, callback: request.asCallback())
    }
}
