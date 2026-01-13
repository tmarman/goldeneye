import AgentKit
import SwiftUI

// MARK: - Agent Panel View

/// Slide-in panel for ambient agent interaction.
/// The agent is context-aware based on the current view/document.
struct AgentPanelView: View {
    @EnvironmentObject private var appState: AppState
    @State private var message = ""
    @State private var messages: [PanelMessage] = []
    @State private var isLoading = false
    @State private var streamingContent = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header with connection status
            headerView

            Divider()

            // Connection status banner (if not connected)
            if !appState.isAgentConnected {
                connectionBanner
            }

            // Context indicator
            if let context = currentContext {
                contextIndicator(context)
            }

            // Error banner
            if let error = errorMessage {
                errorBanner(error)
            }

            // Messages
            messagesView

            Divider()

            // Quick actions
            quickActions

            // Input
            inputBar
        }
        .frame(width: 380, height: 600)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse, options: .repeating, isActive: isLoading)

                Text(contextualAgentName)
                    .font(.headline)
            }

            Spacer()

            // Connection indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.isAgentConnected ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(appState.isAgentConnected ? "Online" : "Offline")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.05)))

            Button(action: { appState.isAgentPanelVisible = false }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Connection Banner

    private var connectionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Not connected to agent")
                    .font(.caption.weight(.medium))
                Text("Connect to enable AI features")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Connect") {
                Task {
                    await appState.connectToLocalAgent()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Context Indicator

    private func contextIndicator(_ context: ContextInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: context.icon)
            Text(context.description)
            Spacer()
            if context.hasContent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(error)
                .font(.caption)
                .lineLimit(2)

            Spacer()

            Button(action: { errorMessage = nil }) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.red.opacity(0.1))
    }

    // MARK: - Messages View

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty && !isLoading {
                        welcomeMessage
                    }

                    ForEach(messages) { msg in
                        PanelMessageView(message: msg)
                            .id(msg.id)
                    }

                    // Streaming response display
                    if isLoading && !streamingContent.isEmpty {
                        StreamingPanelMessageView(content: streamingContent)
                            .id("streaming")
                    } else if isLoading {
                        loadingIndicator
                            .id("loading")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: streamingContent) { _, _ in
                if !streamingContent.isEmpty {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var loadingIndicator: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .frame(width: 24)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.purple.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(isLoading ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(i) * 0.15),
                            value: isLoading
                        )
                }
                Text("Thinking...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastId = messages.last?.id {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask anything...", text: $message, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onSubmit { sendMessage() }

            Button(action: { sendMessage() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }

    private var canSend: Bool {
        !message.isEmpty && !isLoading && appState.isAgentConnected
    }

    // MARK: - Context & Agent Name

    private var contextualAgentName: String {
        switch appState.selectedSidebarItem {
        case .openSpace:
            return "Capture Assistant"
        case .spaces:
            return "Space Navigator"
        case .documents:
            return "Writing Assistant"
        case .conversations:
            return "Assistant"
        case .tasks:
            return "Task Manager"
        case .decisions:
            return "Decision Advisor"
        default:
            return "Agent"
        }
    }

    private var currentContext: ContextInfo? {
        switch appState.selectedSidebarItem {
        case .openSpace:
            return ContextInfo(
                icon: "square.and.pencil",
                description: "Open Space • Quick capture & timeline",
                hasContent: false
            )
        case .spaces:
            return ContextInfo(
                icon: "folder",
                description: "Browsing your Spaces",
                hasContent: false
            )
        case .documents:
            if let docId = appState.selectedDocumentId,
               let doc = appState.workspace.documents.first(where: { $0.id == docId }) {
                return ContextInfo(
                    icon: "doc.text",
                    description: "Working with: \(doc.title.isEmpty ? "Untitled" : doc.title)",
                    hasContent: true,
                    documentContent: doc.blocks.map { $0.previewText }.joined(separator: "\n")
                )
            }
            return ContextInfo(
                icon: "doc.text",
                description: "Documents",
                hasContent: false
            )
        case .conversations:
            if let convId = appState.selectedConversationId,
               let conv = appState.workspace.conversations.first(where: { $0.id == convId }) {
                return ContextInfo(
                    icon: "bubble.left",
                    description: "In conversation: \(conv.title)",
                    hasContent: true
                )
            }
            return nil
        case .tasks:
            return ContextInfo(
                icon: "checklist",
                description: "Managing tasks across Spaces",
                hasContent: false
            )
        case .decisions:
            let count = appState.pendingDecisionCount
            return ContextInfo(
                icon: "checkmark.seal",
                description: count > 0 ? "\(count) pending decisions" : "No pending decisions",
                hasContent: count > 0
            )
        default:
            return nil
        }
    }

    // MARK: - Welcome Message

    private var welcomeMessage: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 64, height: 64)

                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(.purple.opacity(0.8))
            }

            VStack(spacing: 6) {
                Text("How can I help?")
                    .font(.headline)

                Text("I'm aware of your current context and can help with:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                CapabilityRow(icon: "pencil", text: "Writing and editing")
                CapabilityRow(icon: "magnifyingglass", text: "Research and analysis")
                CapabilityRow(icon: "lightbulb", text: "Brainstorming ideas")
                CapabilityRow(icon: "questionmark.circle", text: "Answering questions")
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(contextualQuickActions, id: \.self) { action in
                    Button(action: { performQuickAction(action) }) {
                        Text(action)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!appState.isAgentConnected)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var contextualQuickActions: [String] {
        switch appState.selectedSidebarItem {
        case .openSpace:
            return ["Process my notes", "What's upcoming?", "Create a task", "Link to event"]
        case .spaces:
            return ["Create new Space", "Find documents", "Recent activity"]
        case .documents:
            return ["Improve writing", "Summarize", "Expand this", "Fix grammar", "Suggest structure"]
        case .conversations:
            return ["Continue", "Summarize thread", "Find action items"]
        case .tasks:
            return ["What's due today?", "Prioritize tasks", "Delegate this"]
        case .decisions:
            return ["Show context", "Compare options", "Approve all"]
        default:
            return ["Help me with...", "Explain this", "What can you do?"]
        }
    }

    private func performQuickAction(_ action: String) {
        message = action
        sendMessage()
    }

    // MARK: - Send Message (Real A2A Integration)

    private func sendMessage() {
        guard !message.isEmpty, appState.isAgentConnected else { return }

        let userMessage = PanelMessage(role: .user, content: message)
        messages.append(userMessage)

        // Build context-aware prompt
        let contextualPrompt = buildContextualPrompt(message)
        message = ""
        isLoading = true
        streamingContent = ""
        errorMessage = nil

        Task {
            await sendToAgent(contextualPrompt)
        }
    }

    private func buildContextualPrompt(_ userInput: String) -> String {
        var prompt = userInput

        // Inject document context if available
        if let context = currentContext, context.hasContent {
            if let docContent = context.documentContent, !docContent.isEmpty {
                let truncatedContent = String(docContent.prefix(2000))
                prompt = """
                Context: I'm currently working on a document with the following content:
                ---
                \(truncatedContent)
                ---

                User request: \(userInput)
                """
            }
        }

        return prompt
    }

    private func sendToAgent(_ prompt: String) async {
        // Use streaming via AppState's A2A client
        if let response = await appState.sendAgentMessage(prompt) {
            // For now, display the full response (streaming will be added to AppState)
            let assistantMessage = PanelMessage(role: .assistant, content: response)
            messages.append(assistantMessage)
        } else {
            errorMessage = "Failed to get response from agent"
        }

        isLoading = false
        streamingContent = ""
    }
}

// MARK: - Supporting Types

struct ContextInfo {
    let icon: String
    let description: String
    var hasContent: Bool = false
    var documentContent: String? = nil
}

struct PanelMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp = Date()
}

// MARK: - Capability Row

private struct CapabilityRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.purple)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Panel Message View

struct PanelMessageView: View {
    let message: PanelMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .frame(width: 24)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(message.role == .user ? Color.accentColor : Color(.controlBackgroundColor))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - Streaming Panel Message View

struct StreamingPanelMessageView: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .bottomTrailing) {
                        // Typing indicator
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 6, height: 6)
                            .opacity(0.6)
                            .padding(6)
                    }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
