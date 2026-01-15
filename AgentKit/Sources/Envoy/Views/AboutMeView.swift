import AgentKit
import SwiftUI

// MARK: - About Me View

/// Special view for the About Me space.
///
/// Displays:
/// - Concierge chat interface
/// - Indexing progress and controls
/// - User insights discovered
/// - Space suggestions based on work patterns
struct AboutMeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var messageInput = ""
    @State private var isIndexing = false
    @FocusState private var isInputFocused: Bool

    private var aboutMeService: AboutMeService {
        appState.aboutMeService
    }

    /// The Concierge conversation
    private var conciergeConversation: Conversation? {
        guard let convId = aboutMeService.conciergeConversationId else { return nil }
        return appState.workspace.conversations.first { $0.id == convId }
    }

    var body: some View {
        HSplitView {
            // Main chat area
            VStack(spacing: 0) {
                // Header
                header

                Divider()

                // Messages
                if let conversation = conciergeConversation {
                    messageList(conversation)
                } else {
                    welcomeView
                }

                Divider()

                // Input area
                inputArea
            }
            .frame(minWidth: 400)

            // Sidebar with insights and suggestions
            insightsSidebar
                .frame(minWidth: 280, maxWidth: 350)
        }
        .navigationTitle("About Me")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            // Concierge avatar
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Concierge")
                    .font(.title3.weight(.semibold))
                Text("Your personal assistant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Indexing status
            if aboutMeService.indexingProgress > 0 && aboutMeService.indexingProgress < 1 {
                HStack(spacing: 8) {
                    ProgressView(value: aboutMeService.indexingProgress)
                        .frame(width: 100)
                    Text(aboutMeService.indexingStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !isIndexing {
                Button(action: startIndexing) {
                    Label("Start Indexing", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Menu {
                Button(action: { appState.selectedSidebarItem = .settings }) {
                    Label("Privacy Settings", systemImage: "lock.shield")
                }
                Button(action: startIndexing) {
                    Label("Re-index", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding()
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to About Me")
                .font(.title2.weight(.semibold))

            Text("Your Concierge is ready to help you organize your work.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button(action: startIndexing) {
                Label("Get Started", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Message List

    private func messageList(_ conversation: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(conversation.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: conversation.messages.count) { _, _ in
                if let lastMessage = conversation.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageRow(_ message: ConversationMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                // Concierge avatar
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
            } else {
                // User avatar
                Circle()
                    .fill(Color.gray.gradient)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.role == .assistant ? "Concierge" : "You")
                        .font(.subheadline.weight(.semibold))
                    Text(message.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Render markdown content
                Text(LocalizedStringKey(message.content))
                    .textSelection(.enabled)
            }

            Spacer()
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Message Concierge...", text: $messageInput)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(messageInput.isEmpty)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    // MARK: - Insights Sidebar

    private var insightsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Progress section
                if aboutMeService.indexingProgress > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Indexing Progress", systemImage: "chart.bar.fill")
                            .font(.headline)

                        ProgressView(value: aboutMeService.indexingProgress)
                        Text(aboutMeService.indexingStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Insights section
                if !aboutMeService.insights.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Insights", systemImage: "lightbulb.fill")
                            .font(.headline)

                        ForEach(aboutMeService.insights) { insight in
                            insightCard(insight)
                        }
                    }
                }

                // Suggestions section
                if !aboutMeService.suggestedSpaces.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Suggested Spaces", systemImage: "sparkles")
                            .font(.headline)

                        ForEach(aboutMeService.suggestedSpaces) { suggestion in
                            suggestionCard(suggestion)
                        }
                    }
                }

                // Empty state
                if aboutMeService.insights.isEmpty && aboutMeService.suggestedSpaces.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        Text("No insights yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Start indexing to discover patterns in your work")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)

                        Button(action: startIndexing) {
                            Label("Start Indexing", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func insightCard(_ insight: UserInsight) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconForInsightType(insight.type))
                .font(.title3)
                .foregroundStyle(colorForInsightType(insight.type))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.subheadline.weight(.medium))
                Text(insight.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Confidence indicator
            Circle()
                .fill(confidenceColor(insight.confidence))
                .frame(width: 8, height: 8)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func suggestionCard(_ suggestion: SpaceSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: suggestion.icon)
                    .font(.title3)
                    .foregroundStyle(colorForSuggestion(suggestion.color))

                Text(suggestion.name)
                    .font(.subheadline.weight(.semibold))

                Spacer()
            }

            Text(suggestion.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("_\(suggestion.reason)_")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack {
                // Suggested agents
                ForEach(suggestion.suggestedAgents, id: \.self) { agent in
                    Text(agent)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1), in: Capsule())
                }

                Spacer()

                Button(action: { createSpace(suggestion) }) {
                    Text("Create")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorForSuggestion(suggestion.color).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func startIndexing() {
        isIndexing = true
        Task {
            await aboutMeService.startIndexing(appState: appState)
            isIndexing = false
        }
    }

    private func sendMessage() {
        guard !messageInput.isEmpty else { return }
        let content = messageInput
        messageInput = ""

        Task {
            await handleUserMessage(content)
        }
    }

    private func handleUserMessage(_ content: String) async {
        guard let convId = aboutMeService.conciergeConversationId,
              let index = appState.workspace.conversations.firstIndex(where: { $0.id == convId }) else {
            return
        }

        // Add user message
        let userMessage = ConversationMessage(role: .user, content: content)
        appState.workspace.conversations[index].messages.append(userMessage)

        // Handle common commands
        let lowercased = content.lowercased()
        var response: String

        if lowercased.contains("start indexing") || lowercased.contains("index") {
            response = "Starting to index your files and learn about your work patterns..."
            Task { await aboutMeService.startIndexing(appState: appState) }
        } else if lowercased.contains("show suggestions") || lowercased.contains("suggest") {
            if aboutMeService.suggestedSpaces.isEmpty {
                response = "I haven't discovered any patterns yet. Would you like me to start indexing your files first?"
            } else {
                response = "I've found \(aboutMeService.suggestedSpaces.count) space suggestions based on your work. Check the sidebar to see them!"
            }
        } else if lowercased.contains("privacy") || lowercased.contains("settings") {
            response = "You can control what I access in **Settings → Extensions**. I respect your privacy - all analysis happens on-device."
        } else if lowercased.contains("create all") {
            for suggestion in aboutMeService.suggestedSpaces {
                await aboutMeService.createSuggestedSpace(suggestion, appState: appState)
            }
            response = "Done! I've created all the suggested spaces for you. You can find them in the sidebar."
        } else if lowercased.starts(with: "create ") {
            let spaceName = String(content.dropFirst(7))
            if let suggestion = aboutMeService.suggestedSpaces.first(where: {
                $0.name.localizedCaseInsensitiveContains(spaceName)
            }) {
                await aboutMeService.createSuggestedSpace(suggestion, appState: appState)
                return  // createSuggestedSpace posts its own message
            } else {
                response = "I couldn't find a suggestion matching '\(spaceName)'. Check the sidebar for available suggestions."
            }
        } else {
            response = """
            I can help you with:
            - **Start indexing** - Analyze your files and work patterns
            - **Show suggestions** - See recommended Spaces
            - **Create [Space Name]** - Create a suggested Space
            - **Create all** - Create all suggested Spaces
            - **Privacy settings** - Control what I can access

            What would you like to do?
            """
        }

        // Add assistant response
        let assistantMessage = ConversationMessage(role: .assistant, content: response)
        appState.workspace.conversations[index].messages.append(assistantMessage)
        appState.workspace.conversations[index].updatedAt = Date()

        await appState.saveConversation(appState.workspace.conversations[index])
    }

    private func createSpace(_ suggestion: SpaceSuggestion) {
        Task {
            await aboutMeService.createSuggestedSpace(suggestion, appState: appState)
        }
    }

    // MARK: - Helpers

    private func iconForInsightType(_ type: UserInsight.InsightType) -> String {
        switch type {
        case .technology: return "cpu"
        case .workStyle: return "desktopcomputer"
        case .communication: return "envelope.fill"
        case .schedule: return "calendar"
        case .general: return "info.circle"
        }
    }

    private func colorForInsightType(_ type: UserInsight.InsightType) -> Color {
        switch type {
        case .technology: return .blue
        case .workStyle: return .purple
        case .communication: return .green
        case .schedule: return .orange
        case .general: return .gray
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence > 0.8 { return .green }
        if confidence > 0.5 { return .yellow }
        return .orange
    }

    private func colorForSuggestion(_ color: SpaceSuggestion.SuggestedColor) -> Color {
        switch color {
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
