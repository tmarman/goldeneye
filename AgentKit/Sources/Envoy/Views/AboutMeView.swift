import AgentKit
import MarkdownUI
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

    /// Local state to track indexing progress (synced from service)
    @State private var indexingProgress: Double = 0.0
    @State private var indexingStatus: String = "Not started"
    @State private var insights: [UserInsight] = []
    @State private var suggestedSpaces: [SpaceSuggestion] = []

    private var aboutMeService: AboutMeService {
        appState.aboutMeService
    }

    /// The Concierge thread
    private var conciergeThread: AgentKit.Thread? {
        guard let threadId = aboutMeService.conciergeThreadId else { return nil }
        return appState.workspace.threads.first { $0.id == threadId }
    }

    var body: some View {
        HSplitView {
            // Main chat area
            VStack(spacing: 0) {
                // Header
                header

                Divider()

                // Messages
                if let thread = conciergeThread {
                    messageList(thread)
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
                    .font(.title3.weight(.medium))
                Text("Your personal assistant")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                .font(.title2.weight(.medium))

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

    private func messageList(_ thread: AgentKit.Thread) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(thread.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: thread.messages.count) { _, _ in
                if let lastMessage = thread.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageRow(_ message: AgentKit.ThreadMessage) -> some View {
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
                        .font(.subheadline.weight(.medium))
                    Text(message.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Render markdown content using MarkdownUI for proper formatting
                Markdown(message.textContent)
                    .markdownTheme(.assistantMessage)
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Live indexing section (shown during indexing)
                    if aboutMeService.isIndexing {
                        liveIndexingView
                    }

                    // Progress section
                    if aboutMeService.indexingProgress > 0 {
                        progressSection
                    }

                    // File types discovered
                    if !aboutMeService.fileTypeCounts.isEmpty {
                        fileTypesSection
                    }

                    // Insights section
                    if !aboutMeService.insights.isEmpty {
                        insightsSection
                    }

                    // Suggestions section
                    if !aboutMeService.suggestedSpaces.isEmpty {
                        suggestionsSection
                    }

                    // Activity Log (collapsible)
                    if !aboutMeService.indexingLog.isEmpty {
                        activityLogSection
                    }

                    // Empty state
                    if !aboutMeService.isIndexing && aboutMeService.insights.isEmpty && aboutMeService.suggestedSpaces.isEmpty {
                        emptyStateView
                    }
                }
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Live Indexing View

    private var liveIndexingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Indexing in Progress")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }

            // Current file being scanned
            if !aboutMeService.currentlyScanning.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.blue)
                    Text(aboutMeService.currentlyScanning)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Status
            Text(aboutMeService.indexingStatus)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Progress bar
            ProgressView(value: aboutMeService.indexingProgress)
                .tint(.blue)

            Text("\(Int(aboutMeService.indexingProgress * 100))% complete")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Progress", systemImage: aboutMeService.indexingProgress >= 1.0 ? "checkmark.circle.fill" : "chart.bar.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(aboutMeService.indexingProgress >= 1.0 ? .green : .primary)
                Spacer()
                Text("\(Int(aboutMeService.indexingProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if aboutMeService.indexingProgress < 1.0 {
                ProgressView(value: aboutMeService.indexingProgress)
            }

            Text(aboutMeService.indexingStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - File Types Section

    private var fileTypesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Files Indexed", systemImage: "doc.on.doc.fill")
                .font(.subheadline.weight(.medium))

            // Top file types as chips
            let sortedTypes = aboutMeService.fileTypeCounts.sorted { $0.value > $1.value }.prefix(8)
            FlowLayout(spacing: 6) {
                ForEach(Array(sortedTypes), id: \.key) { ext, count in
                    HStack(spacing: 4) {
                        Text(".\(ext)")
                            .font(.caption.weight(.medium))
                        Text("\(count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(colorForExtension(ext).opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            // Total count
            let total = aboutMeService.fileTypeCounts.values.reduce(0, +)
            Text("\(total) files total")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Insights Section

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Insights", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.yellow)

            ForEach(aboutMeService.insights) { insight in
                insightCard(insight)
            }
        }
    }

    // MARK: - Suggestions Section

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Suggested Spaces", systemImage: "sparkles")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.purple)

            ForEach(aboutMeService.suggestedSpaces) { suggestion in
                suggestionCard(suggestion)
            }
        }
    }

    // MARK: - Activity Log Section

    @State private var showFullLog = false

    private var activityLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { showFullLog.toggle() }) {
                HStack {
                    Label("Activity Log", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: showFullLog ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showFullLog {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(aboutMeService.indexingLog.suffix(20).reversed()) { entry in
                        logEntryRow(entry)
                    }
                }
                .padding(.top, 4)
            } else {
                // Show just the last 3 entries
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(aboutMeService.indexingLog.suffix(3).reversed()) { entry in
                        logEntryRow(entry)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func logEntryRow(_ entry: IndexingLogEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconForLogType(entry.type))
                .font(.caption)
                .foregroundStyle(colorForLogType(entry.type))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.message)
                    .font(.caption)
                    .lineLimit(1)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(entry.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func iconForLogType(_ type: IndexingLogEntry.LogType) -> String {
        switch type {
        case .directory: return "folder.fill"
        case .file: return "doc.fill"
        case .insight: return "lightbulb.fill"
        case .suggestion: return "sparkles"
        case .complete: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func colorForLogType(_ type: IndexingLogEntry.LogType) -> Color {
        switch type {
        case .directory: return .blue
        case .file: return .gray
        case .insight: return .yellow
        case .suggestion: return .purple
        case .complete: return .green
        case .info: return .secondary
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No insights yet")
                .font(.subheadline.weight(.medium))
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

    // MARK: - Helpers

    private func colorForExtension(_ ext: String) -> Color {
        switch ext {
        case "swift", "m", "h": return .orange
        case "ts", "tsx", "js", "jsx": return .blue
        case "py": return .green
        case "rs": return .red
        case "go": return .cyan
        case "md", "txt": return .purple
        case "pdf": return .red
        case "json", "yaml", "yml": return .yellow
        default: return .gray
        }
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
                    .font(.subheadline.weight(.medium))

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

            // Sync state from service after indexing completes
            await MainActor.run {
                indexingProgress = aboutMeService.indexingProgress
                indexingStatus = aboutMeService.indexingStatus
                insights = aboutMeService.insights
                suggestedSpaces = aboutMeService.suggestedSpaces
                isIndexing = false
            }
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
        guard let threadId = aboutMeService.conciergeThreadId,
              let index = appState.workspace.threads.firstIndex(where: { $0.id == threadId }) else {
            return
        }

        // Add user message
        let userMessage = AgentKit.ThreadMessage.user(content)
        appState.workspace.threads[index].messages.append(userMessage)

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
        let assistantMessage = AgentKit.ThreadMessage.assistant(response, agentName: "Concierge")
        appState.workspace.threads[index].messages.append(assistantMessage)
        appState.workspace.threads[index].updatedAt = Date()

        await appState.saveThread(appState.workspace.threads[index])
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
