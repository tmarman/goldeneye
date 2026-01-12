import Foundation
import Logging

// MARK: - Tool Execution Hook Protocol

/// Hook that fires before or after tool execution
public protocol ToolExecutionHook: Sendable {
    /// Called before a tool executes
    func beforeExecution(
        tool: any Tool,
        input: ToolInput,
        context: ToolContext
    ) async throws

    /// Called after a tool executes successfully
    func afterExecution(
        tool: any Tool,
        input: ToolInput,
        output: ToolOutput,
        context: ToolContext
    ) async throws
}

// Default implementations
public extension ToolExecutionHook {
    func beforeExecution(tool: any Tool, input: ToolInput, context: ToolContext) async throws {}
    func afterExecution(tool: any Tool, input: ToolInput, output: ToolOutput, context: ToolContext) async throws {}
}

// MARK: - Git Auto-Commit Hook

/// Automatically commits file changes after tool execution
public actor GitAutoCommitHook: ToolExecutionHook {
    /// Tools that modify files and should trigger commits
    private let fileModifyingTools: Set<String> = ["Write", "Edit"]

    /// Paths to track (if empty, tracks working directory)
    private var trackedPaths: Set<String> = []

    /// Whether auto-commit is enabled
    public var isEnabled: Bool = true

    /// Agent ID for commit attribution
    public var agentId: String?

    private let logger = Logger(label: "AgentKit.GitAutoCommit")

    public init(agentId: String? = nil) {
        self.agentId = agentId
    }

    /// Configure tracked paths
    public func setTrackedPaths(_ paths: [String]) {
        trackedPaths = Set(paths)
    }

    public nonisolated func beforeExecution(
        tool: any Tool,
        input: ToolInput,
        context: ToolContext
    ) async throws {
        // Nothing to do before execution
    }

    public nonisolated func afterExecution(
        tool: any Tool,
        input: ToolInput,
        output: ToolOutput,
        context: ToolContext
    ) async throws {
        // Check if enabled and tool modifies files
        guard await isEnabled else { return }
        guard await fileModifyingTools.contains(tool.name) else { return }
        guard !output.isError else { return }

        // Get the file path from input
        guard let filePath = input.get("file_path", as: String.self) else { return }

        // Check if file is in a tracked path or within working directory
        let isTracked = await shouldTrack(filePath: filePath, workingDir: context.workingDirectory)
        guard isTracked else { return }

        // Find git root
        guard let gitRoot = await findGitRoot(for: filePath) else {
            await logger.debug("No git repo found for \(filePath)")
            return
        }

        // Commit the change
        await commitChange(
            filePath: filePath,
            gitRoot: gitRoot,
            tool: tool,
            agentId: await agentId
        )
    }

    private func shouldTrack(filePath: String, workingDir: URL?) -> Bool {
        // If no tracked paths, track everything in working directory
        if trackedPaths.isEmpty {
            if let workDir = workingDir {
                return filePath.hasPrefix(workDir.path)
            }
            return true
        }

        // Check if file is in any tracked path
        return trackedPaths.contains { trackedPath in
            filePath.hasPrefix(trackedPath)
        }
    }

    private func findGitRoot(for filePath: String) async -> URL? {
        var current = URL(fileURLWithPath: filePath).deletingLastPathComponent()

        while current.path != "/" {
            let gitDir = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir.path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    private func commitChange(filePath: String, gitRoot: URL, tool: any Tool, agentId: String?) async {
        do {
            // Get relative path from git root
            let relativePath = filePath.replacingOccurrences(
                of: gitRoot.path + "/",
                with: ""
            )

            // Stage the file
            try await runGit(["add", relativePath], at: gitRoot)

            // Check if there are changes to commit
            let status = try await runGit(["status", "--porcelain"], at: gitRoot)
            guard !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                logger.debug("No changes to commit for \(relativePath)")
                return
            }

            // Generate commit message
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            let message = generateCommitMessage(tool: tool, fileName: fileName)

            // Build commit args
            var commitArgs = ["commit", "-m", message]
            if let agentId {
                commitArgs += ["--author", "Agent <\(agentId)@agent.local>"]
            }

            try await runGit(commitArgs, at: gitRoot)

            logger.info("Auto-committed: \(relativePath)", metadata: [
                "tool": "\(tool.name)",
                "agent": "\(agentId ?? "unknown")"
            ])

        } catch {
            logger.warning("Failed to auto-commit: \(error.localizedDescription)")
        }
    }

    private func generateCommitMessage(tool: any Tool, fileName: String) -> String {
        switch tool.name {
        case "Write":
            return "Update \(fileName)"
        case "Edit":
            return "Edit \(fileName)"
        default:
            return "Update \(fileName) via \(tool.name)"
        }
    }

    @discardableResult
    private func runGit(_ args: [String], at directory: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

// MARK: - Hook Manager

/// Manages tool execution hooks
public actor ToolHookManager {
    private var hooks: [any ToolExecutionHook] = []

    public init() {}

    /// Add a hook
    public func add(_ hook: any ToolExecutionHook) {
        hooks.append(hook)
    }

    /// Remove all hooks
    public func clear() {
        hooks.removeAll()
    }

    /// Run before hooks
    public func runBeforeHooks(
        tool: any Tool,
        input: ToolInput,
        context: ToolContext
    ) async throws {
        for hook in hooks {
            try await hook.beforeExecution(tool: tool, input: input, context: context)
        }
    }

    /// Run after hooks
    public func runAfterHooks(
        tool: any Tool,
        input: ToolInput,
        output: ToolOutput,
        context: ToolContext
    ) async throws {
        for hook in hooks {
            try await hook.afterExecution(tool: tool, input: input, output: output, context: context)
        }
    }

    // MARK: - Factory Methods

    /// Create a hook manager with git auto-commit enabled
    public static func withGitAutoCommit(agentId: String? = nil) -> ToolHookManager {
        let manager = ToolHookManager()
        Task {
            await manager.add(GitAutoCommitHook(agentId: agentId))
        }
        return manager
    }
}
