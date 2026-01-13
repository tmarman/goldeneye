import Foundation

// MARK: - Task Router

/// Routes task submissions to the appropriate runner (Claude Code CLI or content agent)
public actor TaskRouter {
    private let sessionManager: SessionManager
    private let spaceRegistry: SpaceRegistry

    public init(
        sessionManager: SessionManager = .shared,
        spaceRegistry: SpaceRegistry = .shared
    ) {
        self.sessionManager = sessionManager
        self.spaceRegistry = spaceRegistry
    }

    // MARK: - Task Submission

    /// Submit a task and route it to the appropriate runner
    public func submitTask(
        prompt: String,
        runner: TaskRunner,
        spaceId: String?,
        priority: TaskPriority = .normal
    ) async throws -> RoutedTask {
        // Get space info if provided
        let space: LinkedSpace?
        if let id = spaceId {
            space = await spaceRegistry.getSpace(id)
        } else {
            space = nil
        }

        // Determine working directory
        let workingDirectory = space?.path ?? FileManager.default.homeDirectoryForCurrentUser

        // Create task ID
        let taskId = UUID().uuidString

        // Route based on runner type
        switch runner {
        case .claudeCode:
            return try await routeToCLI(
                taskId: taskId,
                prompt: prompt,
                workingDirectory: workingDirectory,
                space: space
            )

        case .contentAgent:
            return try await routeToContentAgent(
                taskId: taskId,
                prompt: prompt,
                space: space
            )

        case .auto:
            // Determine best runner based on space and prompt
            let effectiveRunner = determineRunner(prompt: prompt, space: space)
            return try await submitTask(
                prompt: prompt,
                runner: effectiveRunner,
                spaceId: spaceId,
                priority: priority
            )
        }
    }

    // MARK: - CLI Routing

    private func routeToCLI(
        taskId: String,
        prompt: String,
        workingDirectory: URL,
        space: LinkedSpace?
    ) async throws -> RoutedTask {
        // Create CLI session
        let session = try await sessionManager.createSession(
            taskId: taskId,
            cli: .claudeCode,
            prompt: prompt,
            workingDirectory: workingDirectory
        )

        return RoutedTask(
            id: taskId,
            prompt: prompt,
            runner: .claudeCode,
            spaceId: space?.id,
            sessionId: session.id,
            status: .running,
            createdAt: Date()
        )
    }

    // MARK: - Content Agent Routing

    private func routeToContentAgent(
        taskId: String,
        prompt: String,
        space: LinkedSpace?
    ) async throws -> RoutedTask {
        // TODO: Implement content agent routing
        // For now, this is a placeholder that creates a task record
        // In the full implementation, this would connect to the A2A agent system

        return RoutedTask(
            id: taskId,
            prompt: prompt,
            runner: .contentAgent,
            spaceId: space?.id,
            sessionId: nil,  // Content agents don't use CLI sessions
            status: .pending,
            createdAt: Date()
        )
    }

    // MARK: - Runner Determination

    private func determineRunner(prompt: String, space: LinkedSpace?) -> TaskRunner {
        // If space has an explicit default (non-auto), use it
        if let space = space, space.defaultRunner != .auto {
            return space.defaultRunner
        }

        // Otherwise, analyze the prompt
        return analyzePromptForRunner(prompt)
    }

    private func analyzePromptForRunner(_ prompt: String) -> TaskRunner {
        let lowercased = prompt.lowercased()

        // Code-related keywords
        let codeKeywords = [
            "implement", "fix", "refactor", "debug", "test", "build",
            "code", "function", "class", "bug", "error", "compile",
            "deploy", "api", "endpoint", "database", "migration",
            "git", "commit", "branch", "merge", "pr", "pull request"
        ]

        // Content-related keywords
        let contentKeywords = [
            "write", "draft", "edit", "review", "summarize", "explain",
            "blog", "article", "document", "email", "message", "report",
            "outline", "brainstorm", "research", "analyze"
        ]

        let codeScore = codeKeywords.filter { lowercased.contains($0) }.count
        let contentScore = contentKeywords.filter { lowercased.contains($0) }.count

        if codeScore > contentScore {
            return .claudeCode
        } else if contentScore > codeScore {
            return .contentAgent
        } else {
            // Default to Claude Code for ambiguous cases in code spaces
            return .claudeCode
        }
    }
}

// MARK: - Routed Task

/// A task that has been routed to a specific runner
public struct RoutedTask: Identifiable, Sendable {
    public let id: String
    public let prompt: String
    public let runner: TaskRunner
    public let spaceId: String?
    public let sessionId: String?  // Only for CLI tasks
    public var status: RoutedTaskStatus
    public let createdAt: Date
    public var completedAt: Date?
    public var result: TaskResult?

    public init(
        id: String,
        prompt: String,
        runner: TaskRunner,
        spaceId: String?,
        sessionId: String?,
        status: RoutedTaskStatus,
        createdAt: Date,
        completedAt: Date? = nil,
        result: TaskResult? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.runner = runner
        self.spaceId = spaceId
        self.sessionId = sessionId
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.result = result
    }
}

public enum RoutedTaskStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

// MARK: - Task Priority (re-export for convenience)

public enum TaskPriority: String, Codable, Sendable, CaseIterable {
    case low
    case normal
    case high

    public var displayName: String {
        rawValue.capitalized
    }
}
