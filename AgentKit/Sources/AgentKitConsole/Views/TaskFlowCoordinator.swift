import AgentKit
import SwiftUI

// MARK: - Task Flow Coordinator

/// Coordinates the full task flow: creation → routing → session viewing
/// This is the main entry point for creating and monitoring tasks
@MainActor
public class TaskFlowCoordinator: ObservableObject {
    @Published public var currentView: TaskFlowView = .idle
    @Published public var activeTask: RoutedTask?
    @Published public var activeSession: CLISession?
    @Published public var error: TaskFlowError?

    private let taskRouter: TaskRouter
    private let sessionManager: SessionManager
    private let spaceRegistry: SpaceRegistry

    public init(
        taskRouter: TaskRouter = TaskRouter(),
        sessionManager: SessionManager = .shared,
        spaceRegistry: SpaceRegistry = .shared
    ) {
        self.taskRouter = taskRouter
        self.sessionManager = sessionManager
        self.spaceRegistry = spaceRegistry
    }

    // MARK: - Flow Control

    /// Start the task creation flow
    public func startTaskCreation(in space: LinkedSpace? = nil) {
        currentView = .creating(space: space)
    }

    /// Submit a task and transition to session view if it's a CLI task
    public func submitTask(_ submission: TaskSubmission) async {
        currentView = .submitting

        do {
            let task = try await taskRouter.submitTask(
                prompt: submission.prompt,
                runner: submission.runner,
                spaceId: submission.spaceId,
                priority: submission.priority
            )

            activeTask = task

            // If this is a CLI task, get the session and show it
            if let sessionId = task.sessionId,
               let session = await sessionManager.getSession(sessionId) {
                activeSession = session
                currentView = .viewingSession
            } else {
                // Content agent task - show pending view
                currentView = .taskPending
            }
        } catch {
            self.error = TaskFlowError.submissionFailed(error.localizedDescription)
            currentView = .error
        }
    }

    /// Cancel the current flow and return to idle
    public func cancel() {
        currentView = .idle
        activeTask = nil
        activeSession = nil
        error = nil
    }

    /// Close the session view and return to idle
    public func closeSession() {
        currentView = .idle
        activeSession = nil
        // Note: We keep activeTask for reference
    }

    /// Retry after an error
    public func retry() {
        error = nil
        currentView = .idle
    }
}

// MARK: - View State

public enum TaskFlowView: Equatable {
    case idle
    case creating(space: LinkedSpace?)
    case submitting
    case viewingSession
    case taskPending
    case error

    public static func == (lhs: TaskFlowView, rhs: TaskFlowView) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.creating(let a), .creating(let b)): return a?.id == b?.id
        case (.submitting, .submitting): return true
        case (.viewingSession, .viewingSession): return true
        case (.taskPending, .taskPending): return true
        case (.error, .error): return true
        default: return false
        }
    }
}

public enum TaskFlowError: Error, LocalizedError {
    case submissionFailed(String)
    case sessionNotFound
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .submissionFailed(let message):
            return "Failed to submit task: \(message)"
        case .sessionNotFound:
            return "CLI session not found"
        case .cancelled:
            return "Task was cancelled"
        }
    }
}

// MARK: - Task Flow Container View

/// Container view that renders the appropriate UI based on flow state
public struct TaskFlowContainerView: View {
    @ObservedObject var coordinator: TaskFlowCoordinator
    let space: LinkedSpace?

    public init(coordinator: TaskFlowCoordinator, space: LinkedSpace? = nil) {
        self.coordinator = coordinator
        self.space = space
    }

    public var body: some View {
        Group {
            switch coordinator.currentView {
            case .idle:
                idleView

            case .creating(let space):
                TaskCreationView(
                    space: space,
                    onSubmit: { submission in
                        Task {
                            await coordinator.submitTask(submission)
                        }
                    },
                    onCancel: {
                        coordinator.cancel()
                    }
                )

            case .submitting:
                submittingView

            case .viewingSession:
                if let session = coordinator.activeSession {
                    SessionView(
                        session: session,
                        onClose: {
                            coordinator.closeSession()
                        }
                    )
                } else {
                    errorView(message: "Session not available")
                }

            case .taskPending:
                taskPendingView

            case .error:
                if let error = coordinator.error {
                    errorView(message: error.localizedDescription)
                } else {
                    errorView(message: "An unknown error occurred")
                }
            }
        }
    }

    // MARK: - Idle View

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "plus.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Create a Task")
                .font(.title2)
                .fontWeight(.medium)

            Text("Start a new task to run with Claude Code or a content agent")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                coordinator.startTaskCreation(in: space)
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }

    // MARK: - Submitting View

    private var submittingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Submitting task...")
                .font(.headline)

            Text("Routing to the appropriate agent")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }

    // MARK: - Task Pending View

    private var taskPendingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Task Submitted")
                .font(.title2)
                .fontWeight(.medium)

            if let task = coordinator.activeTask {
                Text("Routed to: \(task.runner.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Task ID: \(task.id.prefix(8))...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button("Done") {
                coordinator.cancel()
            }
            .buttonStyle(.bordered)
            .padding(.top)
        }
        .padding(40)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Error")
                .font(.title2)
                .fontWeight(.medium)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Dismiss") {
                    coordinator.cancel()
                }
                .buttonStyle(.bordered)

                Button("Retry") {
                    coordinator.retry()
                    coordinator.startTaskCreation(in: space)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top)
        }
        .padding(40)
    }
}

// MARK: - Quick Task Button

/// A floating button to quickly create a new task
public struct QuickTaskButton: View {
    @ObservedObject var coordinator: TaskFlowCoordinator
    let space: LinkedSpace?

    public init(coordinator: TaskFlowCoordinator, space: LinkedSpace? = nil) {
        self.coordinator = coordinator
        self.space = space
    }

    public var body: some View {
        Button {
            coordinator.startTaskCreation(in: space)
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
    }
}
