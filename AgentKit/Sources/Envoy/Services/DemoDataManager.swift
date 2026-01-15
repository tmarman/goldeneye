//
//  DemoDataManager.swift
//  Envoy
//
//  Manages demo data loading from configurable paths.
//  Allows pointing to different data folders for demos, testing, or production.
//

import AgentKit
import Foundation

/// Manager for loading and managing demo data from configurable paths
@MainActor
public final class DemoDataManager: ObservableObject {
    public static let shared = DemoDataManager()

    // MARK: - Configuration

    /// Whether demo mode is enabled (loads from demo folder instead of default)
    @Published public var isDemoMode: Bool = false

    /// Custom base path for demo data (nil = use default app data path)
    @Published public var demoBasePath: URL?

    /// Current data path being used
    public var currentDataPath: URL {
        if isDemoMode, let demoPath = demoBasePath {
            return demoPath
        }
        return defaultDataPath
    }

    /// Default data path (~/Library/Application Support/Envoy)
    private var defaultDataPath: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Envoy", isDirectory: true)
    }

    private init() {
        // Check for demo mode environment variable
        if ProcessInfo.processInfo.environment["ENVOY_DEMO_MODE"] == "1" {
            isDemoMode = true
        }

        // Check for custom demo path environment variable
        if let pathString = ProcessInfo.processInfo.environment["ENVOY_DEMO_PATH"],
           !pathString.isEmpty {
            demoBasePath = URL(fileURLWithPath: pathString)
            isDemoMode = true
        }
    }

    // MARK: - Data Loading

    /// Load conversations from the data folder
    public func loadConversations() async -> [Conversation] {
        let conversationsPath = currentDataPath.appendingPathComponent("conversations.json")

        guard FileManager.default.fileExists(atPath: conversationsPath.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: conversationsPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Conversation].self, from: data)
        } catch {
            print("Failed to load conversations: \(error)")
            return []
        }
    }

    /// Save conversations to the data folder
    public func saveConversations(_ conversations: [Conversation]) async {
        let conversationsPath = currentDataPath.appendingPathComponent("conversations.json")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: currentDataPath, withIntermediateDirectories: true)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(conversations)
            try data.write(to: conversationsPath)
        } catch {
            print("Failed to save conversations: \(error)")
        }
    }

    /// Load documents from the data folder
    public func loadDocuments() async -> [Document] {
        let documentsPath = currentDataPath.appendingPathComponent("documents.json")

        guard FileManager.default.fileExists(atPath: documentsPath.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: documentsPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Document].self, from: data)
        } catch {
            print("Failed to load documents: \(error)")
            return []
        }
    }

    // MARK: - Demo Data Generation

    /// Generate sample demo data for a new demo folder
    public func generateDemoData(at path: URL) async throws {
        // Create the directory
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        // Generate conversations
        let conversations = generateDemoConversations()
        let conversationsPath = path.appendingPathComponent("conversations.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let conversationData = try encoder.encode(conversations)
        try conversationData.write(to: conversationsPath)

        print("Generated demo data at: \(path.path)")
    }

    // MARK: - Demo Conversations

    private func generateDemoConversations() -> [Conversation] {
        [
            // Recent coding assistance conversation
            Conversation(
                title: "Refactoring UserService",
                messages: [
                    ConversationMessage(
                        role: .user,
                        content: "Can you help me refactor the UserService class? It's gotten too large and handles too many responsibilities.",
                        timestamp: Date().addingTimeInterval(-3600)
                    ),
                    ConversationMessage(
                        role: .assistant,
                        content: """
                        I'd be happy to help you refactor UserService. Based on what you've described, it sounds like the class violates the Single Responsibility Principle.

                        Here's my suggested approach:

                        1. **Split by domain**: Extract authentication logic into `AuthenticationService`
                        2. **Separate concerns**: Move profile management to `UserProfileService`
                        3. **Extract validation**: Create `UserValidationService` for validation rules

                        Would you like me to start with the authentication extraction? That's usually the most impactful change.
                        """,
                        timestamp: Date().addingTimeInterval(-3500)
                    ),
                    ConversationMessage(
                        role: .user,
                        content: "Yes, let's start with authentication. The class currently handles login, logout, token refresh, and password reset.",
                        timestamp: Date().addingTimeInterval(-3400)
                    ),
                    ConversationMessage(
                        role: .assistant,
                        content: """
                        Here's a clean `AuthenticationService` extraction:

                        ```swift
                        final class AuthenticationService {
                            private let tokenStore: TokenStore
                            private let apiClient: APIClient

                            func login(email: String, password: String) async throws -> User
                            func logout() async throws
                            func refreshToken() async throws -> Token
                            func requestPasswordReset(email: String) async throws
                        }
                        ```

                        This gives you:
                        - Clear single responsibility
                        - Easy to test in isolation
                        - Injectable dependencies

                        Should I also show the interface changes needed in UserService?
                        """,
                        metadata: MessageMetadata(model: "Qwen2.5-7B-Instruct-4bit", provider: "MLX", tokens: 156, latency: 2.3),
                        timestamp: Date().addingTimeInterval(-3300)
                    )
                ],
                agentName: nil,
                modelId: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                providerId: nil
            ),

            // Quick questions conversation
            Conversation(
                title: "Swift async/await questions",
                messages: [
                    ConversationMessage(
                        role: .user,
                        content: "What's the difference between Task and TaskGroup in Swift?",
                        timestamp: Date().addingTimeInterval(-86400)
                    ),
                    ConversationMessage(
                        role: .assistant,
                        content: """
                        **Task** - Creates a single concurrent unit of work:
                        ```swift
                        Task {
                            await doSomething()
                        }
                        ```

                        **TaskGroup** - Manages multiple concurrent child tasks that you can await together:
                        ```swift
                        await withTaskGroup(of: Result.self) { group in
                            for item in items {
                                group.addTask { await process(item) }
                            }
                            // Collect results...
                        }
                        ```

                        Key differences:
                        - Task: fire-and-forget or await a single result
                        - TaskGroup: coordinate multiple parallel tasks, collect results
                        - TaskGroup automatically cancels children if parent is cancelled
                        """,
                        metadata: MessageMetadata(model: "Qwen2.5-7B-Instruct-4bit", provider: "MLX", tokens: 134, latency: 1.8),
                        timestamp: Date().addingTimeInterval(-86300)
                    )
                ],
                modelId: "mlx-community/Qwen2.5-7B-Instruct-4bit"
            ),

            // Planning conversation
            Conversation(
                title: "Q1 product roadmap brainstorm",
                messages: [
                    ConversationMessage(
                        role: .user,
                        content: "Help me brainstorm features for our Q1 product roadmap. We're building a developer productivity tool.",
                        timestamp: Date().addingTimeInterval(-172800)
                    ),
                    ConversationMessage(
                        role: .assistant,
                        content: """
                        Here are feature ideas organized by impact and effort:

                        **High Impact, Lower Effort:**
                        - Keyboard shortcuts customization
                        - Command palette (Cmd+K) with fuzzy search
                        - Quick project switching

                        **High Impact, Higher Effort:**
                        - AI-powered code suggestions
                        - Integrated terminal with session persistence
                        - Git workflow automation

                        **Nice to Have:**
                        - Theme customization
                        - Snippet library with sync
                        - Integration with popular tools (Jira, Linear)

                        Which area interests you most? I can dive deeper.
                        """,
                        metadata: MessageMetadata(model: "Llama-3.2-3B-Instruct-4bit", provider: "MLX", tokens: 142, latency: 1.2),
                        timestamp: Date().addingTimeInterval(-172700)
                    )
                ],
                modelId: "mlx-community/Llama-3.2-3B-Instruct-4bit"
            )
        ]
    }
}
