import Foundation

// MARK: - CLI Types

/// Type of coding CLI to execute
public enum CLIType: String, Codable, Sendable, CaseIterable {
    case claudeCode = "claude-code"
    case codex = "codex"
    case geminiCLI = "gemini-cli"

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .geminiCLI: return "Gemini CLI"
        }
    }

    /// SF Symbol icon
    public var icon: String {
        switch self {
        case .claudeCode: return "sparkles"
        case .codex: return "brain"
        case .geminiCLI: return "star.fill"
        }
    }

    /// Default executable path
    public var defaultExecutable: String {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .geminiCLI: return "gemini"
        }
    }
}

// MARK: - CLI Task

/// A task to be executed by a CLI agent
public struct CLITask: Codable, Identifiable, Sendable {
    public let id: String
    public let prompt: String
    public let cli: CLIType
    public let context: TaskContext
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        prompt: String,
        cli: CLIType,
        context: TaskContext,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.cli = cli
        self.context = context
        self.createdAt = createdAt
    }
}

/// Context for task execution
public struct TaskContext: Codable, Sendable {
    public let spaceId: SpaceID?
    public let baseCommit: String
    public let baseBranch: String
    public let workingDirectory: String?
    public let environment: [String: String]
    public let timeout: TimeInterval?

    public init(
        spaceId: SpaceID? = nil,
        baseCommit: String = "HEAD",
        baseBranch: String = "main",
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) {
        self.spaceId = spaceId
        self.baseCommit = baseCommit
        self.baseBranch = baseBranch
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
    }
}

// MARK: - Task Result

/// Result of a CLI task execution
public struct CLITaskResult: Codable, Sendable {
    public let taskId: String
    public let success: Bool
    public let worktreePath: String?
    public let branch: String?
    public let commits: [String]
    public let reviewId: ReviewID?
    public let output: String
    public let error: String?
    public let duration: TimeInterval
    public let filesChanged: Int

    public init(
        taskId: String,
        success: Bool,
        worktreePath: String? = nil,
        branch: String? = nil,
        commits: [String] = [],
        reviewId: ReviewID? = nil,
        output: String = "",
        error: String? = nil,
        duration: TimeInterval = 0,
        filesChanged: Int = 0
    ) {
        self.taskId = taskId
        self.success = success
        self.worktreePath = worktreePath
        self.branch = branch
        self.commits = commits
        self.reviewId = reviewId
        self.output = output
        self.error = error
        self.duration = duration
        self.filesChanged = filesChanged
    }
}

// MARK: - Stream Events

/// Events streamed during CLI execution
public enum CLIStreamEvent: Sendable {
    case started(worktreePath: String, branch: String)
    case progress(output: String)
    case toolUse(tool: String, input: String)
    case commit(sha: String, message: String)
    case error(message: String)
    case completed(result: CLITaskResult)
}

// MARK: - Worktree Info

/// Information about a git worktree
public struct WorktreeInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let path: URL
    public let branch: String
    public let taskId: String
    public let createdAt: Date
    public var lastActivityAt: Date
    public var status: WorktreeStatus

    public init(
        id: String = UUID().uuidString,
        path: URL,
        branch: String,
        taskId: String,
        createdAt: Date = Date(),
        lastActivityAt: Date = Date(),
        status: WorktreeStatus = .active
    ) {
        self.id = id
        self.path = path
        self.branch = branch
        self.taskId = taskId
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.status = status
    }
}

public enum WorktreeStatus: String, Codable, Sendable {
    case active          // Currently in use
    case completed       // Task finished successfully
    case failed          // Task failed
    case archived        // Kept for reference
    case pendingCleanup  // Marked for deletion
}

// MARK: - Execution Config

/// Configuration for CLI execution
public struct ExecutionConfig: Sendable {
    public let cli: CLIType
    public let prompt: String
    public let workingDirectory: URL
    public let environment: [String: String]
    public let timeout: TimeInterval?
    public let additionalArgs: [String]

    public init(
        cli: CLIType,
        prompt: String,
        workingDirectory: URL,
        environment: [String: String] = [:],
        timeout: TimeInterval? = nil,
        additionalArgs: [String] = []
    ) {
        self.cli = cli
        self.prompt = prompt
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
        self.additionalArgs = additionalArgs
    }
}

/// Result of CLI execution
public struct ExecutionResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let duration: TimeInterval

    public var success: Bool { exitCode == 0 }

    public init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        duration: TimeInterval
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.duration = duration
    }
}

// MARK: - Configuration

/// Configuration for CLI Runner Agent
public struct CLIRunnerConfig: Codable, Sendable {
    public let workspaceRoot: URL
    public let worktreeBase: String
    public let defaultCLI: CLIType
    public let cleanupPolicy: CleanupPolicy
    public let githubIntegration: GitHubIntegrationConfig

    public init(
        workspaceRoot: URL,
        worktreeBase: String = "worktrees/",
        defaultCLI: CLIType = .claudeCode,
        cleanupPolicy: CleanupPolicy = CleanupPolicy(),
        githubIntegration: GitHubIntegrationConfig = GitHubIntegrationConfig()
    ) {
        self.workspaceRoot = workspaceRoot
        self.worktreeBase = worktreeBase
        self.defaultCLI = defaultCLI
        self.cleanupPolicy = cleanupPolicy
        self.githubIntegration = githubIntegration
    }
}

public struct CleanupPolicy: Codable, Sendable {
    public let keepWorktreeDays: Int
    public let archiveCompleted: Bool

    public init(
        keepWorktreeDays: Int = 7,
        archiveCompleted: Bool = true
    ) {
        self.keepWorktreeDays = keepWorktreeDays
        self.archiveCompleted = archiveCompleted
    }
}

public struct GitHubIntegrationConfig: Codable, Sendable {
    public let enabled: Bool
    public let autoCreatePR: Bool

    public init(
        enabled: Bool = false,
        autoCreatePR: Bool = false
    ) {
        self.enabled = enabled
        self.autoCreatePR = autoCreatePR
    }
}

// MARK: - Errors

public enum CLIRunnerError: Error, Sendable {
    case cliNotFound(CLIType)
    case cliVersionMismatch(CLIType, expected: String, found: String)
    case worktreeCreationFailed(String)
    case worktreeNotFound(String)
    case executionTimeout(taskId: String)
    case processInterrupted(taskId: String)
    case reviewCreationFailed(String)
    case gitOperationFailed(String)
    case invalidConfiguration(String)
    case taskNotFound(String)
    case taskAlreadyRunning(String)
}
