import AgentKit
import Combine
import Foundation
import SwiftUI

// MARK: - Agent Service

/// Service layer connecting SwiftUI views to AgentKit SDK.
///
/// This observable class manages agent lifecycle, executes tasks,
/// and surfaces events to the UI through Combine publishers.
@MainActor
public final class AgentService: ObservableObject {
    // MARK: - Published State

    @Published public var isProcessing = false
    @Published public var currentTaskState: TaskState = .submitted
    @Published public var lastError: AgentError?
    @Published public var streamingContent: String = ""

    // MARK: - Private Properties

    private var activeAgent: AgentLoop?
    private var activeSession: Session?
    private var eventTask: Task<Void, Never>?
    private var llmProvider: (any LLMProvider)?

    // MARK: - Initialization

    public init(llmProvider: (any LLMProvider)? = nil) {
        self.llmProvider = llmProvider
    }

    /// Set the LLM provider (must be called before sending messages)
    public func setProvider(_ provider: any LLMProvider) {
        self.llmProvider = provider
    }

    // MARK: - Public API

    /// Send a message and get a streaming response
    public func sendMessage(
        _ content: String,
        systemPrompt: String? = nil,
        onEvent: @escaping (AgentEvent) -> Void
    ) async throws {
        guard let provider = llmProvider else {
            throw AgentError.invalidConfiguration("No LLM provider configured")
        }

        isProcessing = true
        streamingContent = ""
        lastError = nil
        currentTaskState = .submitted

        defer { isProcessing = false }

        // Create session if needed
        if activeSession == nil {
            activeSession = Session(
                workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            )
        }

        guard let session = activeSession else {
            throw AgentError.invalidConfiguration("Failed to create session")
        }

        // Create agent configuration
        let config = AgentConfiguration(
            name: "Assistant",
            systemPrompt: systemPrompt ?? defaultSystemPrompt,
            llmProvider: provider,
            maxIterations: 10
        )

        // Create and run agent
        let agent = AgentLoop(
            configuration: config,
            session: session
        )
        activeAgent = agent

        // Create task with user message
        let userMessage = Message(role: .user, content: .text(content))
        let task = AgentTask(message: userMessage)

        // Stream events (await to cross actor boundary)
        let eventStream = await agent.execute(task)
        for try await event in eventStream {
            await handleEvent(event, callback: onEvent)
        }
    }

    /// Cancel the current operation
    public func cancel() async {
        await activeAgent?.cancel()
        eventTask?.cancel()
        isProcessing = false
        currentTaskState = .cancelled
    }

    // MARK: - Private Methods

    private func handleEvent(_ event: AgentEvent, callback: (AgentEvent) -> Void) async {
        callback(event)

        switch event {
        case .stateChanged(let state):
            currentTaskState = state

        case .textDelta(let delta):
            streamingContent += delta.delta

        case .toolCall(let toolCall):
            // Surface tool use for potential approval
            print("Tool call: \(toolCall.toolName)")

        case .failed(let failed):
            lastError = failed.error
            currentTaskState = .failed

        case .completed:
            currentTaskState = .completed

        default:
            break
        }
    }

    private var defaultSystemPrompt: String {
        """
        You are a helpful assistant in a knowledge workspace application.
        You help users with documents, research, planning, and general tasks.
        Be concise and helpful. When working with documents, maintain context
        across the conversation.
        """
    }
}

// MARK: - Thread Service Extension

extension AgentService {
    /// Continue an existing thread with a new message
    public func continueThread(
        _ thread: AgentKit.Thread,
        with newMessage: String,
        onEvent: @escaping (AgentEvent) -> Void
    ) async throws -> AgentKit.ThreadMessage {
        // Build context from thread history
        let historyContext = thread.messages.map { msg in
            let role = msg.role == .user ? "User" : "Assistant"
            return "\(role): \(msg.textContent)"
        }.joined(separator: "\n")

        let contextPrompt = """
        Previous conversation:
        \(historyContext)

        Continue the conversation naturally. Respond to the user's latest message.
        """

        try await sendMessage(newMessage, systemPrompt: contextPrompt, onEvent: onEvent)

        // Return the assistant's response
        return AgentKit.ThreadMessage.assistant(streamingContent)
    }
}

// MARK: - Decision Card Integration

extension AgentService {
    /// Create a decision card for agent-generated content
    public func createDecisionCard(
        title: String,
        content: String,
        sourceType: DecisionSourceType,
        sourceId: String? = nil
    ) -> DecisionCard {
        DecisionCard(
            title: title,
            description: content,
            sourceType: sourceType,
            sourceId: sourceId,
            requestedBy: "Agent"
        )
    }
}
