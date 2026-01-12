import Foundation

// MARK: - Worktree Manager

/// Manages git worktree lifecycle for isolated development tasks
public actor WorktreeManager {
    private let baseRepo: URL
    private let worktreeBase: URL
    private var activeWorktrees: [String: WorktreeInfo] = [:]

    public init(baseRepo: URL, worktreeBase: String = "worktrees/") {
        self.baseRepo = baseRepo
        self.worktreeBase = baseRepo.appendingPathComponent(worktreeBase)
    }

    // MARK: - Worktree Lifecycle

    /// Create a new worktree for a task
    public func createWorktree(
        taskId: String,
        baseBranch: String = "main"
    ) async throws -> URL {
        // Ensure worktree base directory exists
        try FileManager.default.createDirectory(
            at: worktreeBase,
            withIntermediateDirectories: true
        )

        // Create unique branch name
        let timestamp = Int(Date().timeIntervalSince1970)
        let branchName = "agent/\(taskId)/\(timestamp)"

        // Create the branch from base
        try await runGit(["checkout", "-b", branchName, baseBranch], at: baseRepo)

        // Go back to original branch
        try await runGit(["checkout", "-"], at: baseRepo)

        // Create worktree directory path
        let worktreePath = worktreeBase.appendingPathComponent("task-\(taskId)")

        // Create the worktree
        try await runGit([
            "worktree", "add",
            worktreePath.path,
            branchName
        ], at: baseRepo)

        // Track the worktree
        let info = WorktreeInfo(
            path: worktreePath,
            branch: branchName,
            taskId: taskId
        )
        activeWorktrees[taskId] = info

        return worktreePath
    }

    /// Get worktree info for a task
    public func getWorktree(_ taskId: String) -> WorktreeInfo? {
        activeWorktrees[taskId]
    }

    /// Update worktree status
    public func updateWorktreeStatus(
        _ taskId: String,
        status: WorktreeStatus
    ) {
        guard var info = activeWorktrees[taskId] else { return }
        info.status = status
        info.lastActivityAt = Date()
        activeWorktrees[taskId] = info
    }

    /// Clean up a worktree
    public func cleanupWorktree(
        _ taskId: String,
        keepBranch: Bool = false
    ) async throws {
        guard let info = activeWorktrees[taskId] else {
            throw CLIRunnerError.worktreeNotFound(taskId)
        }

        // Remove the worktree
        try await runGit(["worktree", "remove", info.path.path, "--force"], at: baseRepo)

        // Optionally delete the branch
        if !keepBranch {
            try await runGit(["branch", "-D", info.branch], at: baseRepo)
        }

        // Remove from tracking
        activeWorktrees.removeValue(forKey: taskId)
    }

    /// Archive a worktree (keep branch, remove worktree)
    public func archiveWorktree(_ taskId: String) async throws {
        try await cleanupWorktree(taskId, keepBranch: true)
    }

    // MARK: - Branch Management

    /// Get diff between worktree branch and base
    public func getBranchDiff(
        taskId: String,
        base: String = "main"
    ) async throws -> String {
        guard let info = activeWorktrees[taskId] else {
            throw CLIRunnerError.worktreeNotFound(taskId)
        }

        return try await runGit([
            "diff",
            "\(base)...\(info.branch)"
        ], at: baseRepo)
    }

    /// Get list of commits in worktree branch not in base
    public func getBranchCommits(
        taskId: String,
        base: String = "main"
    ) async throws -> [String] {
        guard let info = activeWorktrees[taskId] else {
            throw CLIRunnerError.worktreeNotFound(taskId)
        }

        let output = try await runGit([
            "log",
            "--oneline",
            "\(base)..\(info.branch)",
            "--format=%H"
        ], at: baseRepo)

        return output.split(separator: "\n").map(String.init)
    }

    /// Get the current HEAD commit of a worktree
    public func getHeadCommit(taskId: String) async throws -> String {
        guard let info = activeWorktrees[taskId] else {
            throw CLIRunnerError.worktreeNotFound(taskId)
        }

        return try await runGit(["rev-parse", "HEAD"], at: info.path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get changed files in worktree
    public func getChangedFiles(
        taskId: String,
        base: String = "main"
    ) async throws -> [String] {
        guard let info = activeWorktrees[taskId] else {
            throw CLIRunnerError.worktreeNotFound(taskId)
        }

        let output = try await runGit([
            "diff",
            "--name-only",
            "\(base)...\(info.branch)"
        ], at: baseRepo)

        return output.split(separator: "\n").map(String.init)
    }

    // MARK: - Cleanup

    /// Clean up stale worktrees older than specified time
    public func cleanupStaleWorktrees(
        olderThan interval: TimeInterval
    ) async throws -> Int {
        let cutoff = Date().addingTimeInterval(-interval)
        var cleaned = 0

        for (taskId, info) in activeWorktrees {
            if info.lastActivityAt < cutoff &&
               info.status != .active {
                try await cleanupWorktree(taskId, keepBranch: info.status == .completed)
                cleaned += 1
            }
        }

        return cleaned
    }

    /// List all active worktrees
    public func listActiveWorktrees() -> [WorktreeInfo] {
        Array(activeWorktrees.values).sorted { $0.createdAt > $1.createdAt }
    }

    /// List worktrees from git (refresh from disk)
    public func refreshWorktreeList() async throws {
        let output = try await runGit(["worktree", "list", "--porcelain"], at: baseRepo)

        var currentPath: URL?
        var currentBranch: String?

        for line in output.split(separator: "\n") {
            let lineStr = String(line)

            if lineStr.hasPrefix("worktree ") {
                currentPath = URL(fileURLWithPath: String(lineStr.dropFirst(9)))
            } else if lineStr.hasPrefix("branch refs/heads/") {
                currentBranch = String(lineStr.dropFirst(18))
            } else if lineStr.isEmpty, let path = currentPath, let branch = currentBranch {
                // Check if this is one of our task worktrees
                if path.lastPathComponent.hasPrefix("task-") {
                    let taskId = String(path.lastPathComponent.dropFirst(5))

                    if activeWorktrees[taskId] == nil {
                        // Found a worktree we weren't tracking
                        activeWorktrees[taskId] = WorktreeInfo(
                            path: path,
                            branch: branch,
                            taskId: taskId
                        )
                    }
                }

                currentPath = nil
                currentBranch = nil
            }
        }
    }

    // MARK: - Git Operations

    @discardableResult
    private func runGit(_ args: [String], at directory: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            throw CLIRunnerError.gitOperationFailed("\(args.joined(separator: " ")): \(errorOutput)")
        }

        return output
    }
}
