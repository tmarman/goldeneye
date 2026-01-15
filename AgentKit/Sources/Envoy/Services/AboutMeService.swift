import AgentKit
import Foundation
import SwiftUI

// MARK: - About Me Service

/// Service managing the special "About Me" space.
///
/// The About Me space is owned by the Concierge agent and serves as:
/// - Personal knowledge base about the user
/// - Learning center for user preferences and patterns
/// - Hub for suggesting new Space setups based on work history
///
/// Key features:
/// - Auto-creates on first launch if not present
/// - Indexes user content: iCloud files, Mail, Messages, Reminders, Calendar
/// - Tracks work patterns and suggests relevant Spaces
/// - Provides conversational interface for feedback
@MainActor
public class AboutMeService: ObservableObject {
    // MARK: - Properties

    /// Whether the About Me space exists
    @Published public private(set) var isInitialized = false

    /// The About Me space ID (nil if not created yet)
    @Published public private(set) var spaceId: SpaceID?

    /// Indexing progress (0.0 to 1.0)
    @Published public var indexingProgress: Double = 0.0

    /// Current indexing status message
    @Published public var indexingStatus: String = "Not started"

    /// Discovered user insights
    @Published public var insights: [UserInsight] = []

    /// Suggested spaces based on user patterns
    @Published public var suggestedSpaces: [SpaceSuggestion] = []

    /// The Concierge conversation for this space
    @Published public var conciergeConversationId: ConversationID?

    // MARK: - Constants

    public static let aboutMeSpaceId = SpaceID("about-me")
    public static let aboutMeSpaceName = "About Me"

    // MARK: - Initialization

    public init() {}

    // MARK: - Setup

    /// Initialize the About Me space if it doesn't exist
    public func initializeIfNeeded(appState: AppState) async {
        // Check if About Me space already exists
        if appState.spaces.contains(where: { $0.id == Self.aboutMeSpaceId.rawValue }) {
            spaceId = Self.aboutMeSpaceId
            isInitialized = true

            // Find the Concierge conversation
            if let conv = appState.workspace.conversations.first(where: {
                $0.spaceId == Self.aboutMeSpaceId && $0.agentName == "Concierge"
            }) {
                conciergeConversationId = conv.id
            }
            return
        }

        // Create the About Me space
        await createAboutMeSpace(appState: appState)
    }

    private func createAboutMeSpace(appState: AppState) async {
        // Create the special About Me space
        let aboutMeSpace = SpaceViewModel(
            id: Self.aboutMeSpaceId.rawValue,
            name: Self.aboutMeSpaceName,
            description: "Your personal profile space, managed by Concierge",
            icon: "person.crop.circle.fill",
            color: .blue,
            path: nil,  // Virtual space, not file-backed
            channels: [
                ChannelViewModel(id: "insights", name: "Insights", icon: "lightbulb.fill", unreadCount: 0),
                ChannelViewModel(id: "suggestions", name: "Suggestions", icon: "sparkles", unreadCount: 0),
                ChannelViewModel(id: "preferences", name: "Preferences", icon: "slider.horizontal.3", unreadCount: 0)
            ]
        )

        appState.spaces.insert(aboutMeSpace, at: 0)
        spaceId = Self.aboutMeSpaceId

        // Create the Concierge conversation
        var conciergeConv = Conversation(
            title: "Chat with Concierge",
            messages: [
                ConversationMessage(
                    role: .assistant,
                    content: """
                    👋 **Welcome to your About Me space!**

                    I'm your **Concierge** - I help you get the most out of Envoy by learning about your work and suggesting ways to organize it.

                    Here's what I can do for you:
                    - 📁 **Index your files** from iCloud, Documents, and Downloads
                    - 📧 **Learn from your communications** (Mail, Messages)
                    - 📅 **Understand your schedule** from Calendar and Reminders
                    - 💡 **Suggest new Spaces** based on your work patterns

                    Would you like me to start learning about you? I can begin indexing your content to provide personalized suggestions.

                    **Quick actions:**
                    - Say "**Start indexing**" to begin
                    - Say "**Show suggestions**" to see Space recommendations
                    - Say "**Privacy settings**" to control what I access
                    """
                )
            ],
            agentName: "Concierge"
        )
        conciergeConv.spaceId = Self.aboutMeSpaceId

        appState.workspace.conversations.insert(conciergeConv, at: 0)
        conciergeConversationId = conciergeConv.id

        // Persist
        await appState.saveConversation(conciergeConv)

        isInitialized = true
        indexingStatus = "Ready to start"
    }

    // MARK: - Indexing

    /// Start indexing user content
    public func startIndexing(appState: AppState) async {
        indexingStatus = "Starting..."
        indexingProgress = 0.0

        // Phase 1: Scan file system
        indexingStatus = "Scanning files..."
        await scanFileSystem()
        indexingProgress = 0.25

        // Phase 2: Scan communications (if permitted)
        indexingStatus = "Analyzing communications..."
        await scanCommunications()
        indexingProgress = 0.50

        // Phase 3: Scan calendar and reminders
        indexingStatus = "Checking calendar..."
        await scanCalendarAndReminders()
        indexingProgress = 0.75

        // Phase 4: Generate insights
        indexingStatus = "Generating insights..."
        await generateInsights()
        indexingProgress = 0.90

        // Phase 5: Generate space suggestions
        indexingStatus = "Creating suggestions..."
        await generateSpaceSuggestions(appState: appState)
        indexingProgress = 1.0

        indexingStatus = "Complete!"

        // Update the Concierge conversation with results
        await postIndexingResults(appState: appState)
    }

    private func scanFileSystem() async {
        // Scan common directories for patterns
        let directories = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
        ]

        // Run file enumeration synchronously to avoid async iterator issues
        let (fileTypes, _) = await Task.detached {
            var types: [String: Int] = [:]
            var indicators: [String] = []

            for directory in directories {
                guard let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                var count = 0
                while let fileURL = enumerator.nextObject() as? URL, count < 1000 {
                    count += 1
                    let ext = fileURL.pathExtension.lowercased()
                    types[ext, default: 0] += 1

                    // Look for project indicators
                    let filename = fileURL.lastPathComponent.lowercased()
                    if filename == "package.json" { indicators.append("Node.js project") }
                    if filename == "cargo.toml" { indicators.append("Rust project") }
                    if filename == "package.swift" { indicators.append("Swift project") }
                    if filename == "requirements.txt" { indicators.append("Python project") }
                    if filename == ".git" { indicators.append("Git repository") }
                }
            }
            return (types, indicators)
        }.value

        // Generate insights from file scan
        if fileTypes["swift", default: 0] > 10 {
            insights.append(UserInsight(
                type: .technology,
                title: "Swift Developer",
                description: "Found \(fileTypes["swift", default: 0]) Swift files",
                confidence: 0.9
            ))
        }
        if fileTypes["ts", default: 0] + fileTypes["tsx", default: 0] > 10 {
            insights.append(UserInsight(
                type: .technology,
                title: "TypeScript Developer",
                description: "Found TypeScript projects",
                confidence: 0.85
            ))
        }
        if fileTypes["md", default: 0] > 20 {
            insights.append(UserInsight(
                type: .workStyle,
                title: "Documentation Writer",
                description: "Strong focus on documentation",
                confidence: 0.8
            ))
        }
        if fileTypes["pdf", default: 0] > 50 {
            insights.append(UserInsight(
                type: .workStyle,
                title: "Document Reader",
                description: "Large PDF collection detected",
                confidence: 0.7
            ))
        }
    }

    private func scanCommunications() async {
        // Check for Mail access
        // In production, this would use MailKit or similar
        // For now, we'll add placeholder insights

        insights.append(UserInsight(
            type: .communication,
            title: "Communication Analysis",
            description: "Mail and Messages access not yet configured",
            confidence: 0.5
        ))
    }

    private func scanCalendarAndReminders() async {
        // This would integrate with EventKit
        // For now, add placeholder

        insights.append(UserInsight(
            type: .schedule,
            title: "Calendar Patterns",
            description: "Calendar access available via Extensions settings",
            confidence: 0.5
        ))
    }

    private func generateInsights() async {
        // Analyze collected data and generate high-level insights
        // This is where ML/LLM analysis would happen in production

        if insights.isEmpty {
            insights.append(UserInsight(
                type: .general,
                title: "Getting Started",
                description: "Grant permissions in Settings → Extensions to enable full analysis",
                confidence: 1.0
            ))
        }
    }

    private func generateSpaceSuggestions(appState: AppState) async {
        // Generate Space suggestions based on insights
        let existingSpaceNames = Set(appState.spaces.map { $0.name.lowercased() })

        // Suggest based on detected technologies
        if insights.contains(where: { $0.title.contains("Swift") }) &&
           !existingSpaceNames.contains("swift projects") {
            suggestedSpaces.append(SpaceSuggestion(
                name: "Swift Projects",
                description: "Organize your Swift and iOS/macOS development work",
                icon: "swift",
                color: .orange,
                reason: "Detected Swift files in your Documents",
                suggestedAgents: ["Coder", "Reviewer"]
            ))
        }

        if insights.contains(where: { $0.title.contains("TypeScript") }) &&
           !existingSpaceNames.contains("web development") {
            suggestedSpaces.append(SpaceSuggestion(
                name: "Web Development",
                description: "Frontend and fullstack web projects",
                icon: "globe",
                color: .blue,
                reason: "Detected TypeScript projects",
                suggestedAgents: ["Coder", "Designer"]
            ))
        }

        if insights.contains(where: { $0.title.contains("Documentation") }) &&
           !existingSpaceNames.contains("documentation") {
            suggestedSpaces.append(SpaceSuggestion(
                name: "Documentation",
                description: "Technical writing and documentation projects",
                icon: "doc.text",
                color: .purple,
                reason: "Found significant markdown files",
                suggestedAgents: ["Writer", "Editor"]
            ))
        }

        // Always suggest a Research space if not present
        if !existingSpaceNames.contains("research") {
            suggestedSpaces.append(SpaceSuggestion(
                name: "Research",
                description: "Collect and organize research materials",
                icon: "magnifyingglass",
                color: .green,
                reason: "Useful for organizing learning and exploration",
                suggestedAgents: ["Librarian", "Weaver"]
            ))
        }
    }

    private func postIndexingResults(appState: AppState) async {
        guard let convId = conciergeConversationId,
              let index = appState.workspace.conversations.firstIndex(where: { $0.id == convId }) else {
            return
        }

        // Build results message
        var message = "## Indexing Complete! 🎉\n\n"

        message += "### What I Learned\n"
        for insight in insights.prefix(5) {
            message += "- **\(insight.title)**: \(insight.description)\n"
        }

        if !suggestedSpaces.isEmpty {
            message += "\n### Suggested Spaces\n"
            message += "Based on your work patterns, I recommend creating these Spaces:\n\n"

            for suggestion in suggestedSpaces {
                message += "**\(suggestion.name)**\n"
                message += "_\(suggestion.reason)_\n"
                message += "Suggested agents: \(suggestion.suggestedAgents.joined(separator: ", "))\n\n"
            }

            message += "\nSay \"**Create [Space Name]**\" to set up any of these, or \"**Create all**\" to set them all up at once."
        }

        let resultMessage = ConversationMessage(
            role: .assistant,
            content: message
        )

        appState.workspace.conversations[index].messages.append(resultMessage)
        appState.workspace.conversations[index].updatedAt = Date()

        await appState.saveConversation(appState.workspace.conversations[index])
    }

    // MARK: - Actions

    /// Create a suggested space
    public func createSuggestedSpace(_ suggestion: SpaceSuggestion, appState: AppState) async {
        let newSpace = SpaceViewModel(
            id: UUID().uuidString,
            name: suggestion.name,
            description: suggestion.description,
            icon: suggestion.icon,
            color: colorFromName(suggestion.color),
            path: nil,
            channels: []
        )

        appState.spaces.append(newSpace)

        // Remove from suggestions
        suggestedSpaces.removeAll { $0.name == suggestion.name }

        // Post confirmation
        if let convId = conciergeConversationId,
           let index = appState.workspace.conversations.firstIndex(where: { $0.id == convId }) {
            let confirmMessage = ConversationMessage(
                role: .assistant,
                content: "✅ Created **\(suggestion.name)** space! You can find it in the sidebar. Would you like me to invite any agents to help you get started?"
            )
            appState.workspace.conversations[index].messages.append(confirmMessage)
            await appState.saveConversation(appState.workspace.conversations[index])
        }
    }

    private func colorFromName(_ name: SpaceSuggestion.SuggestedColor) -> Color {
        switch name {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .cyan: return .cyan
        case .red: return .red
        case .yellow: return .yellow
        }
    }
}

// MARK: - Supporting Types

public struct UserInsight: Identifiable, Sendable {
    public let id = UUID()
    public let type: InsightType
    public let title: String
    public let description: String
    public let confidence: Double

    public enum InsightType: String, Sendable {
        case technology
        case workStyle
        case communication
        case schedule
        case general
    }
}

public struct SpaceSuggestion: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let description: String
    public let icon: String
    public let color: SuggestedColor
    public let reason: String
    public let suggestedAgents: [String]

    public enum SuggestedColor: String, Sendable {
        case blue, purple, green, orange, pink, cyan, red, yellow
    }
}
