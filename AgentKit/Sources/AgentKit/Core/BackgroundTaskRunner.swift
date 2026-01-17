//
//  BackgroundTaskRunner.swift
//  AgentKit
//
//  Runs background tasks like knowledge indexing, sync operations,
//  and scheduled agent jobs. Supports progress tracking and cancellation.
//

import Foundation

// MARK: - Background Task Runner

/// Runs and manages long-running background tasks
public actor BackgroundTaskRunner {
    /// Active tasks
    private var tasks: [String: BackgroundTask] = [:]

    /// Completed task results (kept for retrieval)
    private var completedTasks: [String: BGTaskResult] = [:]
    private let maxCompletedTasks = 100

    /// Task execution queue
    private var taskQueue: [BackgroundTask] = []
    private var isProcessingQueue = false

    /// Maximum concurrent tasks
    private let maxConcurrentTasks: Int

    /// Progress observers
    private var progressObservers: [String: @Sendable (BGTaskProgress) -> Void] = [:]

    public init(maxConcurrentTasks: Int = 3) {
        self.maxConcurrentTasks = maxConcurrentTasks
    }

    // MARK: - Task Submission

    /// Submit a task for background execution
    public func submit(_ task: BackgroundTask) async -> String {
        tasks[task.id] = task
        taskQueue.append(task)
        await processQueue()
        return task.id
    }

    /// Submit and wait for completion
    public func submitAndWait(_ task: BackgroundTask) async throws -> BGTaskResult {
        let taskId = await submit(task)
        return try await waitForCompletion(taskId)
    }

    /// Wait for a task to complete
    public func waitForCompletion(_ taskId: String, timeout: TimeInterval = 3600) async throws -> BGTaskResult {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let result = completedTasks[taskId] {
                return result
            }
            if let task = tasks[taskId], case .failed(let error) = task.status {
                throw error
            }
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        throw BackgroundTaskError.timeout(taskId)
    }

    // MARK: - Task Management

    /// Get task status
    public func getStatus(_ taskId: String) -> BGTaskStatus? {
        if let result = completedTasks[taskId] {
            return result.status
        }
        return tasks[taskId]?.status
    }

    /// Get task progress
    public func getProgress(_ taskId: String) -> BGTaskProgress? {
        tasks[taskId]?.progress
    }

    /// Cancel a task
    public func cancel(_ taskId: String) {
        if var task = tasks[taskId] {
            task.cancellationToken?.cancel()
            task.status = .cancelled
            tasks[taskId] = task
        }
    }

    /// List all active tasks
    public func listActiveTasks() -> [BackgroundTaskInfo] {
        tasks.values.map { task in
            BackgroundTaskInfo(
                id: task.id,
                name: task.name,
                type: task.type,
                status: task.status,
                progress: task.progress,
                startedAt: task.startedAt,
                submittedAt: task.submittedAt
            )
        }
    }

    /// List completed tasks
    public func listCompletedTasks(limit: Int = 20) -> [BGTaskResult] {
        Array(completedTasks.values.sorted { $0.completedAt > $1.completedAt }.prefix(limit))
    }

    /// Observe task progress
    public func observeProgress(_ taskId: String, handler: @escaping @Sendable (BGTaskProgress) -> Void) {
        progressObservers[taskId] = handler
    }

    // MARK: - Queue Processing

    private func processQueue() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true

        defer { isProcessingQueue = false }

        while !taskQueue.isEmpty {
            // Check if we can run more tasks
            let runningCount = tasks.values.filter { task in
                if case .running = task.status { return true }
                return false
            }.count

            guard runningCount < maxConcurrentTasks else {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }

            // Get next task
            guard var task = taskQueue.first else { break }
            taskQueue.removeFirst()

            // Start execution
            task.status = .running
            task.startedAt = Date()
            task.cancellationToken = CancellationToken()
            tasks[task.id] = task

            // Run in separate task
            let taskId = task.id
            let work = task.work
            let token = task.cancellationToken!

            Task {
                await self.executeTask(taskId: taskId, work: work, token: token)
            }
        }
    }

    private func executeTask(
        taskId: String,
        work: @escaping @Sendable (BGTaskContext) async throws -> BGTaskOutput,
        token: CancellationToken
    ) async {
        let context = BGTaskContext(
            taskId: taskId,
            reportProgress: { [weak self] progress in
                await self?.updateProgress(taskId, progress: progress)
            },
            isCancelled: { token.isCancelled }
        )

        let startTime = Date()

        do {
            let output = try await work(context)

            // Complete successfully
            let result = BGTaskResult(
                taskId: taskId,
                status: .completed,
                output: output,
                startedAt: startTime,
                completedAt: Date()
            )

            await completeTask(taskId, result: result)

        } catch {
            if token.isCancelled {
                let result = BGTaskResult(
                    taskId: taskId,
                    status: .cancelled,
                    output: BGTaskOutput(message: "Task was cancelled"),
                    startedAt: startTime,
                    completedAt: Date(),
                    error: error
                )
                await completeTask(taskId, result: result)
            } else {
                let result = BGTaskResult(
                    taskId: taskId,
                    status: .failed(error),
                    output: BGTaskOutput(message: "Task failed: \(error.localizedDescription)"),
                    startedAt: startTime,
                    completedAt: Date(),
                    error: error
                )
                await completeTask(taskId, result: result)
            }
        }
    }

    private func updateProgress(_ taskId: String, progress: BGTaskProgress) {
        if var task = tasks[taskId] {
            task.progress = progress
            tasks[taskId] = task
        }

        // Notify observer
        if let observer = progressObservers[taskId] {
            observer(progress)
        }
    }

    private func completeTask(_ taskId: String, result: BGTaskResult) {
        tasks.removeValue(forKey: taskId)
        completedTasks[taskId] = result
        progressObservers.removeValue(forKey: taskId)

        // Prune old completed tasks
        if completedTasks.count > maxCompletedTasks {
            let sorted = completedTasks.sorted { $0.value.completedAt < $1.value.completedAt }
            for (key, _) in sorted.prefix(completedTasks.count - maxCompletedTasks) {
                completedTasks.removeValue(forKey: key)
            }
        }
    }
}

// MARK: - Background Task

/// A background task to execute
public struct BackgroundTask: Sendable {
    public let id: String
    public let name: String
    public let type: BGTaskType
    public let submittedAt: Date
    public var startedAt: Date?
    public var status: BGTaskStatus
    public var progress: BGTaskProgress?
    public var cancellationToken: CancellationToken?
    public let work: @Sendable (BGTaskContext) async throws -> BGTaskOutput

    public init(
        id: String = UUID().uuidString,
        name: String,
        type: BGTaskType,
        work: @escaping @Sendable (BGTaskContext) async throws -> BGTaskOutput
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.submittedAt = Date()
        self.status = .pending
        self.work = work
    }
}

/// Types of background tasks
public enum BGTaskType: String, Sendable, Codable {
    case indexing       // Knowledge indexing
    case sync           // Data sync
    case analysis       // Code/content analysis
    case generation     // Content generation
    case maintenance    // Cleanup, optimization
    case custom
}

/// Status of a task
public enum BGTaskStatus: Sendable {
    case pending
    case running
    case completed
    case cancelled
    case failed(Error)

    public var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed: return true
        default: return false
        }
    }

    public var description: String {
        switch self {
        case .pending: return "pending"
        case .running: return "running"
        case .completed: return "completed"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        }
    }
}

// MARK: - Task Progress

/// Progress information for a task
public struct BGTaskProgress: Sendable {
    public let phase: String
    public let current: Int
    public let total: Int
    public let message: String?

    public var percentComplete: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total) * 100
    }

    public init(phase: String, current: Int = 0, total: Int = 0, message: String? = nil) {
        self.phase = phase
        self.current = current
        self.total = total
        self.message = message
    }
}

// MARK: - Task Context

/// Context provided to running tasks
public struct BGTaskContext: Sendable {
    public let taskId: String
    public let reportProgress: @Sendable (BGTaskProgress) async -> Void
    public let isCancelled: @Sendable () -> Bool

    /// Report progress to the runner
    public func progress(_ phase: String, current: Int = 0, total: Int = 0, message: String? = nil) async {
        await reportProgress(BGTaskProgress(phase: phase, current: current, total: total, message: message))
    }

    /// Check if task has been cancelled
    public func checkCancellation() throws {
        if isCancelled() {
            throw BackgroundTaskError.cancelled
        }
    }
}

// MARK: - Task Output

/// Output from a completed task
public struct BGTaskOutput: Sendable {
    public let message: String
    public let data: [String: String]
    public let artifacts: [String]

    public init(message: String, data: [String: String] = [:], artifacts: [String] = []) {
        self.message = message
        self.data = data
        self.artifacts = artifacts
    }
}

// MARK: - Task Result

/// Result of a completed task
public struct BGTaskResult: Sendable {
    public let taskId: String
    public let status: BGTaskStatus
    public let output: BGTaskOutput
    public let startedAt: Date
    public let completedAt: Date
    public let error: Error?

    public var duration: TimeInterval {
        completedAt.timeIntervalSince(startedAt)
    }

    public init(
        taskId: String,
        status: BGTaskStatus,
        output: BGTaskOutput,
        startedAt: Date,
        completedAt: Date,
        error: Error? = nil
    ) {
        self.taskId = taskId
        self.status = status
        self.output = output
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.error = error
    }
}

// MARK: - Task Info

/// Public info about a task
public struct BackgroundTaskInfo: Sendable {
    public let id: String
    public let name: String
    public let type: BGTaskType
    public let status: BGTaskStatus
    public let progress: BGTaskProgress?
    public let startedAt: Date?
    public let submittedAt: Date
}

// MARK: - Cancellation Token

/// Token for task cancellation
public final class CancellationToken: @unchecked Sendable {
    private var _isCancelled = false
    private let lock = NSLock()

    public var isCancelled: Bool {
        lock.withLock { _isCancelled }
    }

    public func cancel() {
        lock.withLock { _isCancelled = true }
    }
}

// MARK: - Errors

public enum BackgroundTaskError: Error, LocalizedError {
    case timeout(String)
    case cancelled
    case taskNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .timeout(let id):
            return "Task \(id) timed out"
        case .cancelled:
            return "Task was cancelled"
        case .taskNotFound(let id):
            return "Task not found: \(id)"
        }
    }
}

// MARK: - Knowledge Indexing Tasks

extension BackgroundTaskRunner {
    /// Create a Slack indexing task
    public static func slackIndexingTask(
        slack: SlackIntegration,
        store: KnowledgeStore,
        daysBack: Int = 90
    ) -> BackgroundTask {
        BackgroundTask(
            name: "Slack Workspace Indexing",
            type: .indexing
        ) { context in
            let indexer = SlackIndexer(slack: slack, store: store)

            try await indexer.indexAll(daysBack: daysBack) { progress in
                Task {
                    await context.progress(
                        progress.phase.description,
                        current: progress.channelIndex,
                        total: progress.totalChannels,
                        message: "Messages: \(progress.messagesProcessed)"
                    )
                }
            }

            let stats = await indexer.indexStats

            return BGTaskOutput(
                message: "Indexed \(stats.indexedChannels) channels, \(stats.totalMessages) messages",
                data: [
                    "channels": String(stats.indexedChannels),
                    "messages": String(stats.totalMessages),
                    "duration": String(format: "%.1f", stats.duration)
                ]
            )
        }
    }

    /// Create an incremental Slack sync task
    public static func slackIncrementalSync(
        slack: SlackIntegration,
        store: KnowledgeStore
    ) -> BackgroundTask {
        BackgroundTask(
            name: "Slack Incremental Sync",
            type: .sync
        ) { context in
            let indexer = SlackIndexer(slack: slack, store: store)

            try await indexer.incrementalSync { progress in
                Task {
                    await context.progress(
                        "Syncing",
                        current: progress.channelIndex,
                        total: progress.totalChannels
                    )
                }
            }

            let stats = await indexer.indexStats
            return BGTaskOutput(
                message: "Synced \(stats.totalMessages) new messages",
                data: ["messages": String(stats.totalMessages)]
            )
        }
    }
}

// Helper for IndexProgress
extension IndexProgress.Phase {
    var description: String {
        switch self {
        case .fetchingChannels: return "Fetching channels"
        case .indexingChannel(let name): return "Indexing #\(name)"
        case .complete: return "Complete"
        }
    }
}
