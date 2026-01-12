import Foundation

// MARK: - CLI Runner Agent

/// An A2A-compatible agent that wraps coding CLIs and manages isolated worktrees
public actor CLIRunnerAgent {
    private let config: CLIRunnerConfig
    private let worktreeManager: WorktreeManager
    private let cliExecutor: CLIExecutor
    private var reviewBridge: ReviewBridge?

    // Active tasks
    private var activeTasks: [String: CLITask] = [:]
    private var taskResults: [String: CLITaskResult] = [:]

    public init(config: CLIRunnerConfig) {
        self.config = config
        self.worktreeManager = WorktreeManager(
            baseRepo: config.workspaceRoot,
            worktreeBase: config.worktreeBase
        )
        self.cliExecutor = CLIExecutor()
    }

    /// Set the review manager for creating reviews from task results
    public func setReviewManager(_ reviewManager: ReviewManager) {
        self.reviewBridge = ReviewBridge(
            reviewManager: reviewManager,
            worktreeManager: worktreeManager
        )
    }

    // MARK: - Task Execution

    /// Execute a CLI task with full lifecycle management
    public func executeTask(_ task: CLITask) async throws -> CLITaskResult {
        // Track task
        activeTasks[task.id] = task

        let startTime = Date()
        var result: CLITaskResult

        do {
            // Create isolated worktree
            let worktreePath = try await worktreeManager.createWorktree(
                taskId: task.id,
                baseBranch: task.context.baseBranch
            )

            // Build execution config
            let execConfig = ExecutionConfig(
                cli: task.cli,
                prompt: task.prompt,
                workingDirectory: worktreePath,
                environment: task.context.environment,
                timeout: task.context.timeout
            )

            // Execute CLI
            let execResult = try await cliExecutor.execute(
                taskId: task.id,
                config: execConfig
            ) { output in
                // Progress callback - could emit stream events here
            }

            // Get commits made by CLI
            let commits = try await worktreeManager.getBranchCommits(
                taskId: task.id,
                base: task.context.baseBranch
            )

            // Get changed files count
            let changedFiles = try await worktreeManager.getChangedFiles(
                taskId: task.id,
                base: task.context.baseBranch
            )

            // Create review if changes were made
            var reviewId: ReviewID? = nil
            if !commits.isEmpty, let bridge = reviewBridge {
                let title = try await bridge.generateTitle(
                    taskId: task.id,
                    prompt: task.prompt
                )
                let description = try await bridge.generateDescription(
                    taskId: task.id,
                    cliOutput: execResult.stdout,
                    cliType: task.cli
                )
                let review = try await bridge.createReview(
                    taskId: task.id,
                    title: title,
                    description: description,
                    spaceId: task.context.spaceId,
                    cliType: task.cli
                )
                reviewId = review.id
            }

            // Update worktree status
            await worktreeManager.updateWorktreeStatus(
                task.id,
                status: execResult.success ? .completed : .failed
            )

            result = CLITaskResult(
                taskId: task.id,
                success: execResult.success,
                worktreePath: worktreePath.path,
                branch: (await worktreeManager.getWorktree(task.id))?.branch,
                commits: commits,
                reviewId: reviewId,
                output: execResult.stdout,
                error: execResult.stderr.isEmpty ? nil : execResult.stderr,
                duration: Date().timeIntervalSince(startTime),
                filesChanged: changedFiles.count
            )

        } catch {
            // Mark worktree as failed if it exists
            await worktreeManager.updateWorktreeStatus(task.id, status: .failed)

            result = CLITaskResult(
                taskId: task.id,
                success: false,
                error: error.localizedDescription,
                duration: Date().timeIntervalSince(startTime)
            )
        }

        // Store result and clean up
        taskResults[task.id] = result
        activeTasks.removeValue(forKey: task.id)

        return result
    }

    /// Execute a task with streaming events
    public func executeTaskWithStream(
        _ task: CLITask
    ) -> AsyncThrowingStream<CLIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Track task
                await self.trackTask(task)

                let startTime = Date()

                do {
                    // Create worktree
                    let worktreePath = try await self.worktreeManager.createWorktree(
                        taskId: task.id,
                        baseBranch: task.context.baseBranch
                    )

                    let branch = await self.worktreeManager.getWorktree(task.id)?.branch ?? ""
                    continuation.yield(.started(worktreePath: worktreePath.path, branch: branch))

                    // Execute with progress streaming
                    let execConfig = ExecutionConfig(
                        cli: task.cli,
                        prompt: task.prompt,
                        workingDirectory: worktreePath,
                        environment: task.context.environment,
                        timeout: task.context.timeout
                    )

                    let execResult = try await self.cliExecutor.execute(
                        taskId: task.id,
                        config: execConfig
                    ) { output in
                        continuation.yield(.progress(output: output))
                    }

                    // Get results
                    let commits = try await self.worktreeManager.getBranchCommits(
                        taskId: task.id,
                        base: task.context.baseBranch
                    )

                    let changedFiles = try await self.worktreeManager.getChangedFiles(
                        taskId: task.id,
                        base: task.context.baseBranch
                    )

                    // Create review
                    var reviewId: ReviewID? = nil
                    if !commits.isEmpty, let bridge = await self.getReviewBridge() {
                        let title = try await bridge.generateTitle(
                            taskId: task.id,
                            prompt: task.prompt
                        )
                        let description = try await bridge.generateDescription(
                            taskId: task.id,
                            cliOutput: execResult.stdout,
                            cliType: task.cli
                        )
                        let review = try await bridge.createReview(
                            taskId: task.id,
                            title: title,
                            description: description,
                            spaceId: task.context.spaceId,
                            cliType: task.cli
                        )
                        reviewId = review.id
                    }

                    // Update status
                    await self.worktreeManager.updateWorktreeStatus(
                        task.id,
                        status: execResult.success ? .completed : .failed
                    )

                    let result = CLITaskResult(
                        taskId: task.id,
                        success: execResult.success,
                        worktreePath: worktreePath.path,
                        branch: branch,
                        commits: commits,
                        reviewId: reviewId,
                        output: execResult.stdout,
                        error: execResult.stderr.isEmpty ? nil : execResult.stderr,
                        duration: Date().timeIntervalSince(startTime),
                        filesChanged: changedFiles.count
                    )

                    await self.storeResult(result)
                    continuation.yield(.completed(result: result))
                    continuation.finish()

                } catch {
                    await self.worktreeManager.updateWorktreeStatus(task.id, status: .failed)
                    continuation.yield(.error(message: error.localizedDescription))
                    continuation.finish(throwing: error)
                }

                await self.removeActiveTask(task.id)
            }
        }
    }

    // MARK: - Task Management

    /// Cancel a running task
    public func cancelTask(_ taskId: String) async throws {
        try await cliExecutor.cancel(taskId: taskId)
        await worktreeManager.updateWorktreeStatus(taskId, status: .failed)
        activeTasks.removeValue(forKey: taskId)
    }

    /// Get result of a completed task
    public func getTaskResult(_ taskId: String) -> CLITaskResult? {
        taskResults[taskId]
    }

    /// List active tasks
    public func listActiveTasks() -> [CLITask] {
        Array(activeTasks.values)
    }

    /// List completed task results
    public func listTaskResults() -> [CLITaskResult] {
        Array(taskResults.values)
    }

    // MARK: - Worktree Management

    /// List all worktrees
    public func listWorktrees() async -> [WorktreeInfo] {
        await worktreeManager.listActiveWorktrees()
    }

    /// Clean up a task's worktree
    public func cleanupTask(_ taskId: String, keepBranch: Bool = false) async throws {
        try await worktreeManager.cleanupWorktree(taskId, keepBranch: keepBranch)
        taskResults.removeValue(forKey: taskId)
    }

    /// Clean up old worktrees
    public func cleanupStaleWorktrees() async throws -> Int {
        let maxAge = TimeInterval(config.cleanupPolicy.keepWorktreeDays * 24 * 60 * 60)
        return try await worktreeManager.cleanupStaleWorktrees(olderThan: maxAge)
    }

    // MARK: - CLI Info

    /// Get available CLIs
    public func availableCLIs() async -> [CLIType: String] {
        await cliExecutor.detectInstalledCLIs()
    }

    /// Get CLI version
    public func cliVersion(_ cli: CLIType) async throws -> String {
        try await cliExecutor.getCLIVersion(cli)
    }

    // MARK: - Private Helpers

    private func trackTask(_ task: CLITask) {
        activeTasks[task.id] = task
    }

    private func removeActiveTask(_ taskId: String) {
        activeTasks.removeValue(forKey: taskId)
    }

    private func storeResult(_ result: CLITaskResult) {
        taskResults[result.taskId] = result
    }

    private func getReviewBridge() -> ReviewBridge? {
        reviewBridge
    }
}

// MARK: - Convenience Factory

extension CLIRunnerAgent {
    /// Create a CLI Runner Agent for a workspace
    public static func create(
        workspaceRoot: URL,
        worktreeBase: String = "worktrees/"
    ) -> CLIRunnerAgent {
        let config = CLIRunnerConfig(
            workspaceRoot: workspaceRoot,
            worktreeBase: worktreeBase
        )
        return CLIRunnerAgent(config: config)
    }
}
