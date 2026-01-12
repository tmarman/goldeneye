import AgentKit
import SwiftUI

// MARK: - Reviews List View

/// Lists all reviews with filtering and status
struct ReviewsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var reviews: [ReviewIndexEntry] = []
    @State private var selectedReviewId: ReviewID?
    @State private var filterStatus: ReviewStatus?
    @State private var searchText = ""
    @State private var isLoading = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let reviewId = selectedReviewId {
                ReviewDetailView(reviewId: reviewId)
            } else {
                emptyState
            }
        }
        .task {
            await loadReviews()
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search and filter
            HStack(spacing: 8) {
                GlassTextField(placeholder: "Search reviews...", text: $searchText, icon: "magnifyingglass")
                    .onChange(of: searchText) { _, _ in
                        Task { await loadReviews() }
                    }

                Menu {
                    Button("All") { filterStatus = nil }
                    Divider()
                    ForEach(ReviewStatus.allCases, id: \.self) { status in
                        Button(status.displayName) { filterStatus = status }
                    }
                } label: {
                    Image(systemName: filterStatus == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(filterStatus == nil ? .secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Review list
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if reviews.isEmpty {
                emptyListState
            } else {
                List(selection: $selectedReviewId) {
                    ForEach(reviews) { review in
                        ReviewRow(entry: review)
                            .tag(review.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Reviews")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { /* TODO: Create review */ }) {
                    Image(systemName: "plus")
                }
            }
        }
        .onChange(of: filterStatus) { _, _ in
            Task { await loadReviews() }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            Text("Select a Review")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Choose a review from the sidebar to see details")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var emptyListState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)

            Text("No Reviews")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Reviews from agent work will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadReviews() async {
        isLoading = true
        defer { isLoading = false }

        // TODO: Load from ReviewManager
        // For now, simulate empty state
        reviews = []
    }
}

// MARK: - Review Row

struct ReviewRow: View {
    let entry: ReviewIndexEntry
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                ReviewStatusBadge(status: entry.status)
            }

            HStack(spacing: 12) {
                Label(entry.author, systemImage: "person")
                Text(entry.updatedAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Review Status Badge

struct ReviewStatusBadge: View {
    let status: ReviewStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.15))
            .foregroundStyle(status.color)
            .clipShape(Capsule())
    }
}

// MARK: - Review Detail View

struct ReviewDetailView: View {
    let reviewId: ReviewID
    @EnvironmentObject private var appState: AppState
    @State private var review: Review?
    @State private var comments: [CommentThread] = []
    @State private var isLoading = true
    @State private var selectedTab: ReviewTab = .changes

    enum ReviewTab: String, CaseIterable {
        case changes = "Changes"
        case comments = "Comments"
        case activity = "Activity"
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let review {
                reviewContent(review)
            } else {
                Text("Review not found")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await loadReview()
        }
    }

    @ViewBuilder
    private func reviewContent(_ review: Review) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                reviewHeader(review)

                // Summary card
                if let summary = review.summary {
                    ReviewSummaryCard(summary: summary)
                }

                // Tab picker
                Picker("View", selection: $selectedTab) {
                    ForEach(ReviewTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                // Tab content
                switch selectedTab {
                case .changes:
                    changesView(review)
                case .comments:
                    commentsView
                case .activity:
                    activityView(review)
                }
            }
            .padding(24)
        }
        .background(Color(.textBackgroundColor))
        .toolbar {
            reviewToolbar(review)
        }
    }

    @ViewBuilder
    private func reviewHeader(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(review.title)
                    .font(.title.bold())

                Spacer()

                ReviewStatusBadge(status: review.status)
            }

            if !review.description.isEmpty {
                Text(review.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label(review.author.name, systemImage: review.author.avatar ?? "person")
                Label("\(review.sourceBranch) → \(review.targetBranch)", systemImage: "arrow.triangle.branch")
                Label(review.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func changesView(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(review.changes) { change in
                ReviewChangeCard(change: change)
            }
        }
    }

    @ViewBuilder
    private var commentsView: some View {
        if comments.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title)
                    .foregroundStyle(.quaternary)
                Text("No comments yet")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(40)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(comments, id: \.root.id) { thread in
                    CommentThreadView(thread: thread)
                }
            }
        }
    }

    @ViewBuilder
    private func activityView(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(review.approvals) { approval in
                ReviewApprovalRow(approval: approval)
            }

            if review.approvals.isEmpty {
                Text("No approvals yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(40)
            }
        }
    }

    @ToolbarContentBuilder
    private func reviewToolbar(_ review: Review) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if review.status == .draft {
                Button("Open for Review") {
                    // TODO: Open review
                }
                .buttonStyle(GlassButtonStyle(isProminent: true))
            } else if review.status == .open {
                Button("Approve") {
                    // TODO: Approve
                }
                .buttonStyle(GlassButtonStyle(isProminent: true))

                Button("Request Changes") {
                    // TODO: Request changes
                }
                .buttonStyle(GlassButtonStyle())
            } else if review.status == .approved {
                Button("Merge") {
                    // TODO: Merge
                }
                .buttonStyle(GlassButtonStyle(isProminent: true))
            }
        }
    }

    private func loadReview() async {
        isLoading = true
        do {
            // TODO: Load from ReviewManager
            // review = try await reviewManager.getReview(reviewId)
            // comments = try await reviewManager.getCommentThreads(for: reviewId)
        }
        isLoading = false
    }
}

// MARK: - Review Summary Card

struct ReviewSummaryCard: View {
    let summary: ReviewSummary

    var body: some View {
        GlassCard(cornerRadius: 12, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(summary.overview)
                    .font(.body)

                HStack(spacing: 24) {
                    StatItem(
                        value: "\(summary.filesChanged)",
                        label: "files",
                        icon: "doc"
                    )
                    StatItem(
                        value: "+\(summary.additions)",
                        label: "additions",
                        icon: "plus",
                        color: .green
                    )
                    StatItem(
                        value: "-\(summary.deletions)",
                        label: "deletions",
                        icon: "minus",
                        color: .red
                    )
                    Spacer()
                    ImpactBadge(impact: summary.impact)
                }

                if !summary.keyChanges.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Key Changes")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        ForEach(summary.keyChanges) { change in
                            HStack(spacing: 8) {
                                Image(systemName: change.type.icon)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(change.description)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(color)
    }
}

private struct ImpactBadge: View {
    let impact: ImpactLevel

    var body: some View {
        Text(impact.rawValue.capitalized)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(impact.color.opacity(0.15))
            .foregroundStyle(impact.color)
            .clipShape(Capsule())
    }
}

// MARK: - Review Change Card

struct ReviewChangeCard: View {
    let change: ReviewChange
    @State private var isExpanded = false
    @State private var showDiff = false

    var body: some View {
        GlassCard(cornerRadius: 10, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                // File header
                HStack {
                    Image(systemName: change.changeType.icon)
                        .foregroundStyle(changeColor)

                    Text(change.path)
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    if let analysis = change.contentAnalysis {
                        Text(analysis.wordCountDelta >= 0 ? "+\(analysis.wordCountDelta)" : "\(analysis.wordCountDelta)")
                            .font(.caption)
                            .foregroundStyle(analysis.wordCountDelta >= 0 ? .green : .red)
                        Text("words")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                // Expanded content
                if isExpanded {
                    Divider()

                    HStack {
                        Button(showDiff ? "Preview" : "Diff") {
                            showDiff.toggle()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)

                        Spacer()
                    }

                    if showDiff {
                        // Diff view
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(change.diff)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 300)
                        .padding(8)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        // Preview (rendered content)
                        if let after = change.afterContent {
                            Text(after.prefix(500) + (after.count > 500 ? "..." : ""))
                                .font(.caption)
                                .lineLimit(10)
                        }
                    }

                    // Content analysis
                    if let analysis = change.contentAnalysis {
                        if !analysis.sectionsAdded.isEmpty || !analysis.sectionsRemoved.isEmpty {
                            HStack(spacing: 16) {
                                if !analysis.sectionsAdded.isEmpty {
                                    Label("\(analysis.sectionsAdded.count) sections added", systemImage: "plus.circle")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                                if !analysis.sectionsRemoved.isEmpty {
                                    Label("\(analysis.sectionsRemoved.count) sections removed", systemImage: "minus.circle")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var changeColor: Color {
        switch change.changeType {
        case .added: return .green
        case .modified: return .orange
        case .deleted: return .red
        case .renamed: return .blue
        }
    }
}

// MARK: - Comment Thread View

struct CommentThreadView: View {
    let thread: CommentThread

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentRow(comment: thread.root, isRoot: true)

            if !thread.replies.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(thread.replies) { reply in
                        CommentRow(comment: reply, isRoot: false)
                            .padding(.leading, 32)
                    }
                }
            }
        }
        .padding(12)
        .background(thread.isResolved ? Color.green.opacity(0.03) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

struct CommentRow: View {
    let comment: ReviewComment
    let isRoot: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            Circle()
                .fill(comment.type.color)
                .frame(width: isRoot ? 32 : 24, height: isRoot ? 32 : 24)
                .overlay {
                    Image(systemName: comment.type.icon)
                        .font(isRoot ? .caption : .caption2)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.author.name)
                        .font(.caption.weight(.medium))

                    Text(comment.createdAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if comment.resolved {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                Text(comment.content)
                    .font(.subheadline)

                if let suggestion = comment.suggestion {
                    SuggestionView(suggestion: suggestion)
                }
            }
        }
    }
}

struct SuggestionView: View {
    let suggestion: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Suggestion")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            Text(suggestion)
                .font(.caption)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.top, 4)
    }
}

// MARK: - Approval Row

struct ReviewApprovalRow: View {
    let approval: Approval

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: approval.status.icon)
                .foregroundStyle(approval.status.color)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(approval.reviewer.name)
                        .font(.subheadline.weight(.medium))
                    Text(approval.status.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let comment = approval.comment {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(approval.timestamp, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Extensions

extension ReviewStatus {
    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .open: return "Open"
        case .approved: return "Approved"
        case .changesRequested: return "Changes Requested"
        case .merged: return "Merged"
        case .closed: return "Closed"
        }
    }

    var color: Color {
        switch self {
        case .draft: return .secondary
        case .open: return .blue
        case .approved: return .green
        case .changesRequested: return .orange
        case .merged: return .purple
        case .closed: return .secondary
        }
    }
}

extension ChangeType {
    var icon: String {
        switch self {
        case .content: return "doc.text"
        case .structure: return "list.bullet.indent"
        case .metadata: return "tag"
        case .media: return "photo"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

extension ImpactLevel {
    var color: Color {
        switch self {
        case .minor: return .secondary
        case .moderate: return .orange
        case .major: return .red
        }
    }
}

extension CommentType {
    var color: Color {
        switch self {
        case .comment: return .blue
        case .question: return .orange
        case .suggestion: return .green
        case .praise: return .purple
        case .concern: return .red
        }
    }
}

extension ApprovalStatus {
    var icon: String {
        switch self {
        case .approved: return "checkmark.circle.fill"
        case .changesRequested: return "xmark.circle.fill"
        case .commented: return "bubble.left.fill"
        }
    }

    var displayName: String {
        switch self {
        case .approved: return "approved"
        case .changesRequested: return "requested changes"
        case .commented: return "commented"
        }
    }

    var color: Color {
        switch self {
        case .approved: return .green
        case .changesRequested: return .orange
        case .commented: return .blue
        }
    }
}
