import Foundation

// MARK: - Review Bridge

/// Creates Reviews from worktree changes after CLI execution
public actor ReviewBridge {
    private let reviewManager: ReviewManager
    private let worktreeManager: WorktreeManager

    public init(
        reviewManager: ReviewManager,
        worktreeManager: WorktreeManager
    ) {
        self.reviewManager = reviewManager
        self.worktreeManager = worktreeManager
    }

    // MARK: - Review Creation

    /// Create a review from completed CLI work in a worktree
    public func createReview(
        taskId: String,
        title: String,
        description: String = "",
        spaceId: SpaceID? = nil,
        cliType: CLIType,
        author: Author? = nil
    ) async throws -> Review {
        guard let worktreeInfo = await worktreeManager.getWorktree(taskId) else {
            throw CLIRunnerError.worktreeNotFound(taskId)
        }

        // Get base and head commits
        let headCommit = try await worktreeManager.getHeadCommit(taskId: taskId)

        // Extract base branch from branch name
        // Branch format: agent/{taskId}/{timestamp}
        let baseBranch = "main"  // Default, could parse from worktree info

        // Get base commit (merge-base with main)
        let baseCommit = try await getBaseCommit(
            worktreePath: worktreeInfo.path,
            baseBranch: baseBranch
        )

        // Create agent author
        let reviewAuthor = author ?? Author.agent("\(cliType.displayName) Agent")

        // Create the review
        let review = try await reviewManager.createReview(
            title: title,
            description: description,
            author: reviewAuthor,
            baseCommit: baseCommit,
            headCommit: headCommit,
            targetBranch: baseBranch,
            sourceBranch: worktreeInfo.branch,
            spaceId: spaceId
        )

        return review
    }

    /// Generate a review title from diff summary
    public func generateTitle(
        taskId: String,
        prompt: String
    ) async throws -> String {
        // For now, use a simple approach based on the prompt
        // In production, could use LLM to summarize

        let maxLength = 72

        // Clean up prompt for title
        var title = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        if title.count > maxLength {
            title = String(title.prefix(maxLength - 3)) + "..."
        }

        return title
    }

    /// Generate description from CLI output and changes
    public func generateDescription(
        taskId: String,
        cliOutput: String,
        cliType: CLIType
    ) async throws -> String {
        var description = """
        ## Agent Task

        Executed by **\(cliType.displayName)** agent.

        """

        // Add changed files summary
        let changedFiles = try await worktreeManager.getChangedFiles(
            taskId: taskId,
            base: "main"
        )

        if !changedFiles.isEmpty {
            description += """

            ## Files Changed

            """
            for file in changedFiles.prefix(20) {
                description += "- `\(file)`\n"
            }
            if changedFiles.count > 20 {
                description += "- ... and \(changedFiles.count - 20) more\n"
            }
        }

        // Add truncated CLI output
        if !cliOutput.isEmpty {
            description += """

            ## Agent Output

            <details>
            <summary>Show output</summary>

            ```
            \(String(cliOutput.suffix(2000)))
            ```

            </details>
            """
        }

        return description
    }

    // MARK: - Change Analysis

    /// Analyze changes in a worktree for summary
    public func analyzeChanges(taskId: String) async throws -> ChangeAnalysis {
        let changedFiles = try await worktreeManager.getChangedFiles(
            taskId: taskId,
            base: "main"
        )

        var analysis = ChangeAnalysis()

        for file in changedFiles {
            let ext = (file as NSString).pathExtension.lowercased()

            switch ext {
            case "md", "txt", "rst", "adoc":
                analysis.documentFiles.append(file)
            case "swift", "ts", "js", "py", "go", "rs", "java", "kt":
                analysis.codeFiles.append(file)
            case "json", "yaml", "yml", "toml", "xml":
                analysis.configFiles.append(file)
            case "png", "jpg", "jpeg", "gif", "svg", "webp":
                analysis.mediaFiles.append(file)
            default:
                analysis.otherFiles.append(file)
            }
        }

        return analysis
    }

    // MARK: - Private Helpers

    private func getBaseCommit(
        worktreePath: URL,
        baseBranch: String
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["merge-base", baseBranch, "HEAD"]
        process.currentDirectoryURL = worktreePath

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

// MARK: - Supporting Types

/// Analysis of changes in a worktree
public struct ChangeAnalysis: Sendable {
    public var documentFiles: [String] = []
    public var codeFiles: [String] = []
    public var configFiles: [String] = []
    public var mediaFiles: [String] = []
    public var otherFiles: [String] = []

    public var totalFiles: Int {
        documentFiles.count + codeFiles.count + configFiles.count +
        mediaFiles.count + otherFiles.count
    }

    /// Determine primary change type
    public var primaryType: ChangeType {
        let counts = [
            (ChangeType.content, documentFiles.count),
            (ChangeType.code, codeFiles.count),
            (ChangeType.metadata, configFiles.count),
            (ChangeType.media, mediaFiles.count)
        ]
        return counts.max(by: { $0.1 < $1.1 })?.0 ?? .content
    }
}
