import Foundation

// MARK: - Review Manager

/// Manages the lifecycle of reviews including creation, comments, and approvals
public actor ReviewManager {
    private let storage: ReviewStorage
    private let repoPath: URL

    public init(storage: ReviewStorage, repoPath: URL) {
        self.storage = storage
        self.repoPath = repoPath
    }

    /// Initialize a ReviewManager for a repository path
    public static func create(at repoPath: URL) async throws -> ReviewManager {
        let storage = try await ReviewStorage.create(at: repoPath)
        return ReviewManager(storage: storage, repoPath: repoPath)
    }

    // MARK: - Review Lifecycle

    /// Create a new review from git commits
    public func createReview(
        title: String,
        description: String = "",
        author: Author,
        baseCommit: String,
        headCommit: String,
        targetBranch: String = "main",
        sourceBranch: String,
        spaceId: SpaceID? = nil
    ) async throws -> Review {
        // Analyze changes between commits
        let changes = try await analyzeChanges(
            baseCommit: baseCommit,
            headCommit: headCommit
        )

        // Create review
        var review = Review(
            spaceId: spaceId,
            title: title,
            description: description,
            author: author,
            baseCommit: baseCommit,
            headCommit: headCommit,
            targetBranch: targetBranch,
            sourceBranch: sourceBranch,
            status: .draft,
            changes: changes
        )

        // Generate summary
        review.summary = try await generateSummary(for: changes)

        // Save
        try await storage.save(review)

        return review
    }

    /// Open a review for comments and approvals
    public func openReview(_ reviewId: ReviewID) async throws -> Review {
        var review = try await storage.load(reviewId)
        guard review.status == .draft else {
            throw ReviewError.invalidStatusTransition(from: review.status, to: .open)
        }
        review.status = .open
        review.updatedAt = Date()
        try await storage.save(review)
        return review
    }

    /// Close a review without merging
    public func closeReview(_ reviewId: ReviewID, reason: String? = nil) async throws -> Review {
        var review = try await storage.load(reviewId)
        guard review.status != .merged && review.status != .closed else {
            throw ReviewError.invalidStatusTransition(from: review.status, to: .closed)
        }
        review.status = .closed
        review.closedAt = Date()
        review.updatedAt = Date()
        if let reason {
            review.metadata["close_reason"] = reason
        }
        try await storage.save(review)
        return review
    }

    /// Merge a review into the target branch
    public func mergeReview(_ reviewId: ReviewID) async throws -> Review {
        var review = try await storage.load(reviewId)
        guard review.status == .approved else {
            throw ReviewError.notApproved(reviewId)
        }

        // Perform git merge
        try await performMerge(
            sourceBranch: review.sourceBranch,
            targetBranch: review.targetBranch,
            message: "Merge review: \(review.title)"
        )

        review.status = .merged
        review.mergedAt = Date()
        review.updatedAt = Date()
        try await storage.save(review)
        return review
    }

    /// Update a review's title or description
    public func updateReview(
        _ reviewId: ReviewID,
        title: String? = nil,
        description: String? = nil
    ) async throws -> Review {
        var review = try await storage.load(reviewId)

        if let title {
            review.title = title
        }
        if let description {
            review.description = description
        }
        review.updatedAt = Date()

        try await storage.save(review)
        return review
    }

    /// Refresh changes in a review (if head commit has changed)
    public func refreshChanges(_ reviewId: ReviewID, newHeadCommit: String? = nil) async throws -> Review {
        var review = try await storage.load(reviewId)

        let headCommit = newHeadCommit ?? review.headCommit
        review.changes = try await analyzeChanges(
            baseCommit: review.baseCommit,
            headCommit: headCommit
        )
        review.summary = try await generateSummary(for: review.changes)
        review.updatedAt = Date()

        try await storage.save(review)
        return review
    }

    // MARK: - Querying

    public func getReview(_ reviewId: ReviewID) async throws -> Review {
        try await storage.load(reviewId)
    }

    public func listReviews(
        spaceId: SpaceID? = nil,
        status: ReviewStatus? = nil,
        author: String? = nil,
        limit: Int? = nil,
        offset: Int = 0
    ) async throws -> [ReviewIndexEntry] {
        try await storage.list(
            spaceId: spaceId,
            status: status,
            author: author,
            limit: limit,
            offset: offset
        )
    }

    public func searchReviews(_ query: String) async throws -> [ReviewIndexEntry] {
        try await storage.search(query: query)
    }

    // MARK: - Comments

    /// Add a comment to a review
    public func addComment(
        to reviewId: ReviewID,
        position: CommentPosition,
        content: String,
        author: Author,
        type: CommentType = .comment,
        suggestion: String? = nil
    ) async throws -> ReviewComment {
        let comment = ReviewComment(
            reviewId: reviewId,
            author: author,
            position: position,
            content: content,
            type: type,
            suggestion: suggestion
        )

        try await storage.addComment(comment)
        return comment
    }

    /// Reply to an existing comment
    public func replyToComment(
        _ parentId: UUID,
        reviewId: ReviewID,
        content: String,
        author: Author
    ) async throws -> ReviewComment {
        let comments = try await storage.loadComments(for: reviewId)
        guard let parent = comments.first(where: { $0.id == parentId }) else {
            throw ReviewError.commentNotFound(parentId)
        }

        let reply = ReviewComment(
            reviewId: reviewId,
            author: author,
            position: parent.position,
            content: content,
            replyTo: parentId
        )

        try await storage.addComment(reply)
        return reply
    }

    /// Resolve a comment thread
    public func resolveComment(_ commentId: UUID, reviewId: ReviewID, by resolver: Author) async throws {
        var comments = try await storage.loadComments(for: reviewId)
        guard let index = comments.firstIndex(where: { $0.id == commentId }) else {
            throw ReviewError.commentNotFound(commentId)
        }

        var comment = comments[index]
        comment.resolved = true
        comment.resolvedBy = resolver
        comment.resolvedAt = Date()
        comment.updatedAt = Date()

        try await storage.updateComment(comment)
    }

    /// Get all comments for a review
    public func getComments(for reviewId: ReviewID) async throws -> [ReviewComment] {
        try await storage.loadComments(for: reviewId)
    }

    /// Get comments organized into threads
    public func getCommentThreads(for reviewId: ReviewID) async throws -> [CommentThread] {
        let comments = try await storage.loadComments(for: reviewId)

        // Find root comments (not replies)
        let roots = comments.filter { $0.replyTo == nil }

        return roots.map { root in
            let replies = comments.filter { $0.replyTo == root.id }
                .sorted { $0.createdAt < $1.createdAt }
            return CommentThread(root: root, replies: replies)
        }
        .sorted { $0.root.createdAt < $1.root.createdAt }
    }

    // MARK: - Approvals

    /// Submit an approval or request changes
    public func submitApproval(
        for reviewId: ReviewID,
        status: ApprovalStatus,
        comment: String?,
        reviewer: Author
    ) async throws -> Review {
        var review = try await storage.load(reviewId)

        let approval = Approval(
            reviewer: reviewer,
            status: status,
            comment: comment
        )

        review.approvals.append(approval)

        // Update review status based on approval
        switch status {
        case .approved:
            // Check if all required approvals are met (simple: 1 approval = approved)
            if !review.approvals.contains(where: { $0.status == .changesRequested }) {
                review.status = .approved
            }
        case .changesRequested:
            review.status = .changesRequested
        case .commented:
            // No status change
            break
        }

        review.updatedAt = Date()
        try await storage.save(review)
        return review
    }

    // MARK: - Change Analysis

    /// Analyze changes between two commits
    private func analyzeChanges(
        baseCommit: String,
        headCommit: String
    ) async throws -> [ReviewChange] {
        // Get diff from git
        let diff = try await runGit(["diff", "\(baseCommit)..\(headCommit)", "--stat"])
        let fullDiff = try await runGit(["diff", "\(baseCommit)..\(headCommit)"])

        // Get list of changed files
        let changedFilesOutput = try await runGit([
            "diff", "--name-status", "\(baseCommit)..\(headCommit)"
        ])

        var changes: [ReviewChange] = []

        for line in changedFilesOutput.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count >= 2 else { continue }

            let statusChar = String(parts[0].prefix(1))
            let path = String(parts[1])

            let changeType: ReviewFileChangeType
            switch statusChar {
            case "A": changeType = .added
            case "D": changeType = .deleted
            case "M": changeType = .modified
            case "R": changeType = .renamed
            default: changeType = .modified
            }

            // Get file-specific diff
            let fileDiff = try await runGit([
                "diff", "\(baseCommit)..\(headCommit)", "--", path
            ])

            // Get before/after content for text files
            var beforeContent: String?
            var afterContent: String?

            if changeType != .added {
                beforeContent = try? await runGit(["show", "\(baseCommit):\(path)"])
            }
            if changeType != .deleted {
                afterContent = try? await runGit(["show", "\(headCommit):\(path)"])
            }

            // Analyze content changes
            let contentAnalysis = analyzeDocumentContent(
                before: beforeContent,
                after: afterContent
            )

            changes.append(ReviewChange(
                path: path,
                changeType: changeType,
                beforeContent: beforeContent,
                afterContent: afterContent,
                diff: fileDiff,
                contentAnalysis: contentAnalysis
            ))
        }

        return changes
    }

    /// Analyze document content changes
    private func analyzeDocumentContent(
        before: String?,
        after: String?
    ) -> DocumentContentAnalysis? {
        let wordCountBefore = before?.split(whereSeparator: \.isWhitespace).count ?? 0
        let wordCountAfter = after?.split(whereSeparator: \.isWhitespace).count ?? 0

        // Extract sections (Markdown headings)
        let sectionsBefore = extractSections(from: before ?? "")
        let sectionsAfter = extractSections(from: after ?? "")

        let sectionsAdded = sectionsAfter.filter { !sectionsBefore.contains($0) }
        let sectionsRemoved = sectionsBefore.filter { !sectionsAfter.contains($0) }
        let sectionsModified = sectionsBefore.filter { sectionsAfter.contains($0) }  // Simplified

        return DocumentContentAnalysis(
            wordCountBefore: wordCountBefore,
            wordCountAfter: wordCountAfter,
            sectionsAdded: sectionsAdded,
            sectionsRemoved: sectionsRemoved,
            sectionsModified: sectionsModified
        )
    }

    /// Extract section headings from Markdown
    private func extractSections(from markdown: String) -> [String] {
        markdown.split(separator: "\n")
            .filter { $0.hasPrefix("#") }
            .map { line in
                String(line.drop(while: { $0 == "#" || $0 == " " }))
            }
    }

    /// Generate a summary of changes
    private func generateSummary(for changes: [ReviewChange]) async throws -> ReviewSummary {
        var totalAdditions = 0
        var totalDeletions = 0
        var keyChanges: [KeyChange] = []

        for change in changes {
            // Count additions/deletions from diff
            let additions = change.diff.split(separator: "\n")
                .filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }
                .count
            let deletions = change.diff.split(separator: "\n")
                .filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }
                .count

            totalAdditions += additions
            totalDeletions += deletions

            // Create key change entry
            let changeType: ChangeType = change.path.hasSuffix(".md") ? .content : .code
            let description = generateChangeDescription(for: change)

            keyChanges.append(KeyChange(
                type: changeType,
                description: description,
                files: [change.path]
            ))
        }

        // Determine impact level
        let impact: ImpactLevel
        if totalAdditions + totalDeletions > 500 {
            impact = .major
        } else if totalAdditions + totalDeletions > 100 {
            impact = .moderate
        } else {
            impact = .minor
        }

        // Generate overview
        let overview = generateOverview(changes: changes, additions: totalAdditions, deletions: totalDeletions)

        return ReviewSummary(
            overview: overview,
            filesChanged: changes.count,
            additions: totalAdditions,
            deletions: totalDeletions,
            keyChanges: keyChanges,
            impact: impact
        )
    }

    private func generateChangeDescription(for change: ReviewChange) -> String {
        switch change.changeType {
        case .added:
            return "Added \(change.path)"
        case .deleted:
            return "Removed \(change.path)"
        case .modified:
            if let analysis = change.contentAnalysis {
                if analysis.wordCountDelta > 0 {
                    return "Expanded \(change.path) (+\(analysis.wordCountDelta) words)"
                } else if analysis.wordCountDelta < 0 {
                    return "Condensed \(change.path) (\(analysis.wordCountDelta) words)"
                }
            }
            return "Modified \(change.path)"
        case .renamed:
            return "Renamed \(change.path)"
        }
    }

    private func generateOverview(changes: [ReviewChange], additions: Int, deletions: Int) -> String {
        let fileCount = changes.count
        let fileWord = fileCount == 1 ? "file" : "files"

        if additions > deletions * 2 {
            return "Added significant new content across \(fileCount) \(fileWord)"
        } else if deletions > additions * 2 {
            return "Removed content from \(fileCount) \(fileWord)"
        } else {
            return "Modified \(fileCount) \(fileWord) with balanced changes"
        }
    }

    // MARK: - Git Operations

    private func performMerge(
        sourceBranch: String,
        targetBranch: String,
        message: String
    ) async throws {
        // Checkout target branch
        _ = try await runGit(["checkout", targetBranch])

        // Merge source branch
        _ = try await runGit(["merge", sourceBranch, "-m", message])
    }

    @discardableResult
    private func runGit(_ args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = repoPath

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Errors

public enum ReviewError: Error, Sendable {
    case reviewNotFound(ReviewID)
    case commentNotFound(UUID)
    case notApproved(ReviewID)
    case invalidStatusTransition(from: ReviewStatus, to: ReviewStatus)
    case gitError(String)
    case mergeConflict(String)
}
