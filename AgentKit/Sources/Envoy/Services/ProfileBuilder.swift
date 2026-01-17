import AgentKit
import Foundation

// MARK: - Profile Builder

/// Agentic workflow for building a user profile by exploring their file system.
///
/// Works like Claude Code exploring a codebase - the agent decides what to look at,
/// forms hypotheses, and records learnings about the user.
@MainActor
public class ProfileBuilder: ObservableObject {

    // MARK: - Properties

    /// Current status message
    @Published public var status: String = "Ready"

    /// Detailed activity log
    @Published public var activityLog: [ActivityLogEntry] = []

    /// Whether building is in progress
    @Published public var isBuilding = false

    /// Learnings discovered during this session
    @Published public var discoveredLearnings: [DiscoveredLearning] = []

    private let profileStore: UserProfileStore
    private var agentKit: AgentKitBootstrap?

    // MARK: - Initialization

    public init(profileStore: UserProfileStore) {
        self.profileStore = profileStore
    }

    // MARK: - Profile Building

    /// Build a profile by having the agent explore the file system
    public func buildProfile(using agentKit: AgentKitBootstrap) async {
        guard !isBuilding else { return }

        self.agentKit = agentKit
        isBuilding = true
        status = "Starting profile exploration..."
        activityLog = []
        discoveredLearnings = []

        log(.info, "Starting agentic profile building")

        // Create the file exploration tools
        let tools = createExplorationTools()

        // Create the exploration prompt
        let systemPrompt = createExplorationPrompt()

        // Run the agent loop
        do {
            try await runExplorationLoop(
                systemPrompt: systemPrompt,
                tools: tools
            )
        } catch {
            log(.error, "Profile building failed: \(error.localizedDescription)")
        }

        // Save any discovered learnings
        await saveLearnings()

        status = "Profile building complete"
        isBuilding = false
        log(.complete, "Profile building complete - \(discoveredLearnings.count) learnings discovered")
    }

    // MARK: - Tool Creation

    private func createExplorationTools() -> [any Tool] {
        [
            ListDirectoryTool(),
            AnalyzeFolderTool(),
            ReadFileNamesTool(),
            SaveProfileLearningTool { [weak self] category, title, description, evidence, confidence in
                await self?.recordLearning(
                    category: category,
                    title: title,
                    description: description,
                    evidence: evidence,
                    confidence: confidence
                )
            }
        ]
    }

    // MARK: - Exploration Prompt

    private func createExplorationPrompt() -> String {
        """
        You are exploring a user's file system to understand who they are - their work, interests, \
        and patterns. Your goal is to build a meaningful profile that will help personalize their experience.

        ## Your Approach

        1. **Start with key directories** - Begin with ~/Documents, ~/Downloads, ~/Desktop, and look for \
           iCloud Drive at ~/Library/Mobile Documents/com~apple~CloudDocs

        2. **Look for patterns** - Don't just count files. Look at:
           - Folder names that reveal interests (Travel, Projects, Hobbies)
           - Document titles that show what they work on
           - File organization that reveals work style

        3. **Form hypotheses** - When you see something interesting, explore deeper:
           - "There's a Japan folder - let me see what's inside"
           - "Many PDF files - are these work documents or personal reading?"

        4. **Record meaningful learnings** - Use save_profile_learning when you discover something \
           substantive about the user. Don't record trivial observations.

        ## What Makes a Good Learning

        ✅ Good learnings:
        - "Software Developer" - evidence: multiple code projects in ~/dev
        - "Japan Travel Enthusiast" - evidence: Japan 2024 folder with photos and itineraries
        - "Active Reader" - evidence: 50+ PDFs in Reading folder organized by topic

        ❌ Bad learnings:
        - "Has Documents folder" - everyone does
        - "Uses a Mac" - obvious
        - "Has 99 PDFs" - numbers without meaning

        ## Confidence Guidelines

        - 0.9+ : Clear, direct evidence (e.g., "Developer" when ~/dev has many code projects)
        - 0.7-0.8 : Strong indirect evidence (e.g., "Travel enthusiast" from organized travel folders)
        - 0.5-0.6 : Reasonable inference (e.g., "Photography interest" from large photo collection)
        - Below 0.5 : Don't record - too speculative

        ## Available Tools

        - list_directory: See what's in a folder
        - analyze_folder: Get statistics and patterns for a folder
        - read_file_names: See file names (useful for understanding document topics)
        - save_profile_learning: Record something meaningful you've learned

        Begin exploring now. Start with ~/Documents to get a sense of how this user organizes their files.
        """
    }

    // MARK: - Exploration Loop

    private func runExplorationLoop(
        systemPrompt: String,
        tools: [any Tool]
    ) async throws {
        guard let agentKit = agentKit else {
            throw ProfileBuilderError.noAgentKit
        }

        // Get a provider
        guard let provider = await agentKit.providerSelector.selectProvider() else {
            throw ProfileBuilderError.noProvider
        }

        log(.info, "Using provider: \(provider.name)")

        // Build messages for the exploration
        var messages: [Message] = [
            Message(role: .system, content: .text(systemPrompt)),
            Message(role: .user, content: .text("Please explore my file system and learn about me. Start with ~/Documents."))
        ]

        // Convert tools to definitions for the LLM
        let toolDefinitions = tools.map { ToolDefinition(from: $0) }

        let maxIterations = 15
        var iteration = 0

        while iteration < maxIterations {
            iteration += 1
            status = "Exploring... (step \(iteration))"
            log(.info, "Exploration step \(iteration)")

            // Call the LLM and collect the streamed response
            let options = CompletionOptions(
                maxTokens: 2000,
                temperature: 0.3,
                stream: false  // Non-streaming for simplicity in agent loop
            )

            let stream = try await provider.complete(messages, tools: toolDefinitions, options: options)

            // Collect response from stream
            var responseText = ""
            var toolCalls: [LLMToolCall] = []

            for try await event in stream {
                switch event {
                case .text(let text):
                    responseText = text
                case .textDelta(let delta):
                    responseText += delta
                case .toolCall(let toolCall):
                    toolCalls.append(toolCall)
                case .done, .usage, .error:
                    break
                }
            }

            // Process response
            if !responseText.isEmpty {
                log(.assistant, responseText)
            }

            // Check for tool calls
            guard !toolCalls.isEmpty else {
                // No more tool calls - agent is done
                log(.info, "Agent finished exploration")
                break
            }

            // Build assistant message content
            var assistantContent: [MessageContent] = []
            if !responseText.isEmpty {
                assistantContent.append(.text(responseText))
            }
            for toolCall in toolCalls {
                assistantContent.append(.toolUse(ToolUse(
                    id: toolCall.id,
                    name: toolCall.name,
                    input: toolCall.input
                )))
            }
            messages.append(Message(role: .assistant, content: assistantContent))

            // Execute tool calls and add results
            for toolCall in toolCalls {
                log(.tool, "Using: \(toolCall.name)")

                // Find the tool
                guard let tool = tools.first(where: { $0.name == toolCall.name }) else {
                    messages.append(Message(
                        role: .user,
                        content: .toolResult(ToolResult(
                            toolUseId: toolCall.id,
                            content: "Error: Unknown tool \(toolCall.name)",
                            isError: true
                        ))
                    ))
                    continue
                }

                // Execute the tool
                do {
                    let workingDir = FileManager.default.homeDirectoryForCurrentUser
                    let context = ToolContext(
                        session: Session(workingDirectory: workingDir),
                        workingDirectory: workingDir
                    )
                    let output = try await tool.execute(toolCall.input, context: context)

                    // Add result to messages
                    messages.append(Message(
                        role: .user,
                        content: .toolResult(ToolResult(
                            toolUseId: toolCall.id,
                            content: output.content
                        ))
                    ))

                    // Log tool result (truncated)
                    let truncated = output.content.prefix(200)
                    log(.toolResult, String(truncated) + (output.content.count > 200 ? "..." : ""))

                } catch {
                    messages.append(Message(
                        role: .user,
                        content: .toolResult(ToolResult(
                            toolUseId: toolCall.id,
                            content: "Error: \(error.localizedDescription)",
                            isError: true
                        ))
                    ))
                }
            }
        }

        if iteration >= maxIterations {
            log(.info, "Reached maximum exploration steps")
        }
    }

    // MARK: - Learning Management

    private func recordLearning(
        category: String,
        title: String,
        description: String,
        evidence: String?,
        confidence: Double
    ) async {
        let learning = DiscoveredLearning(
            category: category,
            title: title,
            description: description,
            evidence: evidence,
            confidence: confidence
        )

        await MainActor.run {
            discoveredLearnings.append(learning)
            log(.learning, "Discovered: \(title) (\(category), \(Int(confidence * 100))%)")
        }
    }

    private func saveLearnings() async {
        try? await profileStore.load()

        for learning in discoveredLearnings {
            guard let category = LearningCategory(rawValue: learning.category) else { continue }

            await profileStore.addFromIndexing(
                category: category,
                title: learning.title,
                description: learning.description,
                evidence: learning.evidence.map { [$0] } ?? [],
                confidence: learning.confidence
            )
        }

        await profileStore.markIndexingComplete()
        try? await profileStore.save()
    }

    // MARK: - Logging

    private func log(_ type: ActivityLogEntry.EntryType, _ message: String) {
        let entry = ActivityLogEntry(type: type, message: message)
        activityLog.append(entry)
    }
}

// MARK: - Supporting Types

public struct ActivityLogEntry: Identifiable {
    public let id = UUID()
    public let timestamp = Date()
    public let type: EntryType
    public let message: String

    public enum EntryType {
        case info
        case assistant
        case tool
        case toolResult
        case learning
        case error
        case complete
    }
}

public struct DiscoveredLearning: Identifiable {
    public let id = UUID()
    public let category: String
    public let title: String
    public let description: String
    public let evidence: String?
    public let confidence: Double
}

public enum ProfileBuilderError: Error {
    case noAgentKit
    case noProvider
    case explorationFailed(String)
}
