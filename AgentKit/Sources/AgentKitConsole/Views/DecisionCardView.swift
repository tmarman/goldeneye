import AgentKit
import SwiftUI

// MARK: - Decision Cards List View

/// Dashboard-style view showing pending decisions
struct DecisionCardsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCardId: DecisionCardID?
    @State private var filter: DecisionFilter = .actionable

    var filteredCards: [DecisionCard] {
        switch filter {
        case .actionable:
            return appState.decisionCards.filter { $0.isActionable }
        case .all:
            return appState.decisionCards
        case .approved:
            return appState.decisionCards.filter { $0.status == .approved }
        case .dismissed:
            return appState.decisionCards.filter { $0.status == .dismissed }
        }
    }

    var body: some View {
        HSplitView {
            // Cards list
            VStack(alignment: .leading, spacing: 0) {
                // Filter picker
                Picker("Filter", selection: $filter) {
                    ForEach(DecisionFilter.allCases, id: \.self) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if filteredCards.isEmpty {
                    EmptyDecisionListView(filter: filter)
                } else {
                    List(selection: $selectedCardId) {
                        ForEach(filteredCards) { card in
                            DecisionCardRow(card: card)
                                .tag(card.id)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 300, maxWidth: 400)

            // Selected card detail
            if let selectedId = selectedCardId,
               let card = appState.decisionCards.first(where: { $0.id == selectedId }) {
                DecisionCardDetailView(
                    card: binding(for: card),
                    onApprove: { approveCard(card) },
                    onRequestChanges: { comment in requestChanges(card, comment: comment) },
                    onDismiss: { dismissCard(card) }
                )
            } else {
                EmptyDecisionView()
            }
        }
        .navigationTitle("Decisions")
        .task {
            await appState.loadDecisionCards()
        }
    }

    private func binding(for card: DecisionCard) -> Binding<DecisionCard> {
        Binding(
            get: { appState.decisionCards.first { $0.id == card.id } ?? card },
            set: { newValue in
                if let index = appState.decisionCards.firstIndex(where: { $0.id == card.id }) {
                    appState.decisionCards[index] = newValue
                }
            }
        )
    }

    private func approveCard(_ card: DecisionCard) {
        Task {
            await appState.approveDecisionCard(card.id)
        }
    }

    private func requestChanges(_ card: DecisionCard, comment: String) {
        Task {
            await appState.requestChangesOnCard(card.id, comment: comment)
        }
    }

    private func dismissCard(_ card: DecisionCard) {
        Task {
            await appState.dismissDecisionCard(card.id)
        }
    }
}

// MARK: - Empty List View

struct EmptyDecisionListView: View {
    let filter: DecisionFilter

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: filter == .actionable ? "checkmark.seal" : "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text(filter == .actionable ? "All Caught Up!" : "No Decisions")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(filter == .actionable ? "No pending decisions need your review." : "No decisions match this filter.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum DecisionFilter: String, CaseIterable {
    case actionable
    case all
    case approved
    case dismissed

    var displayName: String {
        switch self {
        case .actionable: return "Needs Review"
        case .all: return "All"
        case .approved: return "Approved"
        case .dismissed: return "Dismissed"
        }
    }
}

// MARK: - Decision Card Row

struct DecisionCardRow: View {
    let card: DecisionCard

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(card.sourceType.displayName, systemImage: card.sourceType.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !card.comments.isEmpty {
                        Label("\(card.comments.count)", systemImage: "bubble.left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let requestedBy = card.requestedBy {
                    Text("from \(requestedBy)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(card.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch card.status {
        case .pending: return .orange
        case .approved: return .green
        case .changesRequested: return .yellow
        case .dismissed: return .gray
        case .expired: return .secondary
        }
    }
}

// MARK: - Decision Card Detail View

struct DecisionCardDetailView: View {
    @Binding var card: DecisionCard
    let onApprove: () -> Void
    let onRequestChanges: (String) -> Void
    let onDismiss: () -> Void

    @State private var newComment = ""
    @State private var showRequestChangesSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    statusBadge

                    Spacer()

                    Text(card.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(card.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(card.description)
                    .font(.body)
                    .foregroundStyle(.secondary)

                if let requestedBy = card.requestedBy {
                    HStack(spacing: 4) {
                        Image(systemName: "person.circle")
                        Text("Requested by \(requestedBy)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            // Content area with comments
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Source info
                    if let sourceId = card.sourceId {
                        HStack {
                            Image(systemName: card.sourceType.icon)
                            Text("Related: \(sourceId)")
                        }
                        .font(.caption)
                        .padding(8)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // Comments section
                    if !card.comments.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Comments")
                                .font(.headline)

                            ForEach(card.comments) { comment in
                                CommentBubble(comment: comment)
                            }
                        }
                    }

                    // Review history
                    if !card.reviewHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("History")
                                .font(.headline)

                            ForEach(card.reviewHistory) { review in
                                ReviewHistoryItem(review: review)
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Action bar
            if card.isActionable {
                actionBar
            }
        }
        .sheet(isPresented: $showRequestChangesSheet) {
            RequestChangesSheet(onSubmit: onRequestChanges)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(card.status.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch card.status {
        case .pending: return .orange
        case .approved: return .green
        case .changesRequested: return .yellow
        case .dismissed: return .gray
        case .expired: return .secondary
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            // Add comment
            TextField("Add a comment...", text: $newComment)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if !newComment.isEmpty {
                        let comment = DecisionComment(
                            content: newComment,
                            author: "User"
                        )
                        card.addComment(comment)
                        newComment = ""
                    }
                }

            Divider()
                .frame(height: 24)

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .help("Dismiss")

            // Request changes button
            Button(action: { showRequestChangesSheet = true }) {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Request changes")

            // Approve button
            Button(action: onApprove) {
                Label("Approve", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - Comment Bubble

struct CommentBubble: View {
    let comment: DecisionComment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.author)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(comment.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if comment.isResolved {
                    Label("Resolved", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            Text(comment.content)
                .font(.body)

            if let ref = comment.lineReference, let snippet = ref.snippet {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Review History Item

struct ReviewHistoryItem: View {
    let review: DecisionReview

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: review.action.icon)
                .foregroundStyle(review.action.color)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(review.reviewer)
                        .fontWeight(.medium)
                    Text(review.action.displayName)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                if let comment = review.comment {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(review.timestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Request Changes Sheet

struct RequestChangesSheet: View {
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var comment = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Request Changes")
                .font(.headline)

            Text("Describe what changes are needed:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $comment)
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Submit") {
                    onSubmit(comment)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(comment.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Empty State

struct EmptyDecisionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Decision Selected")
                .font(.title2)
                .fontWeight(.medium)

            Text("Select a decision from the list to review.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Extensions

extension DecisionStatus {
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .approved: return "Approved"
        case .changesRequested: return "Changes Requested"
        case .dismissed: return "Dismissed"
        case .expired: return "Expired"
        }
    }
}

extension DecisionSourceType {
    var displayName: String {
        switch self {
        case .document: return "Document"
        case .agentAction: return "Agent Action"
        case .generatedContent: return "Generated Content"
        case .workflowStep: return "Workflow"
        case .suggestion: return "Suggestion"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .document: return "doc.text"
        case .agentAction: return "sparkles"
        case .generatedContent: return "wand.and.stars"
        case .workflowStep: return "arrow.triangle.branch"
        case .suggestion: return "lightbulb"
        case .other: return "questionmark.circle"
        }
    }
}

extension ReviewAction {
    var displayName: String {
        switch self {
        case .approved: return "approved"
        case .changesRequested: return "requested changes"
        case .commented: return "commented"
        case .dismissed: return "dismissed"
        case .reopened: return "reopened"
        }
    }

    var icon: String {
        switch self {
        case .approved: return "checkmark.circle.fill"
        case .changesRequested: return "arrow.counterclockwise.circle.fill"
        case .commented: return "bubble.left.fill"
        case .dismissed: return "xmark.circle.fill"
        case .reopened: return "arrow.uturn.backward.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .approved: return .green
        case .changesRequested: return .orange
        case .commented: return .blue
        case .dismissed: return .gray
        case .reopened: return .purple
        }
    }
}

