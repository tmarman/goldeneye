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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)

                Text(contextualAgentName)
                    .font(.headline)

                Spacer()

                Button(action: { appState.isAgentPanelVisible = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            // Context indicator
            if let context = currentContext {
                HStack(spacing: 8) {
                    Image(systemName: context.icon)
                    Text(context.description)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.1))
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            welcomeMessage
                        }

                        ForEach(messages) { message in
                            PanelMessageView(message: message)
                                .id(message.id)
                        }

                        if isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Quick actions
            quickActions

            // Input
            HStack(spacing: 8) {
                TextField("Ask anything...", text: $message)
                    .textFieldStyle(.plain)
                    .onSubmit { sendMessage() }

                Button(action: { sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .disabled(message.isEmpty || isLoading)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
        }
        .frame(width: 380, height: 600)
        .background(Color(.windowBackgroundColor))
    }

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
            return ContextInfo(icon: "square.and.pencil", description: "Open Space • Quick capture & timeline")
        case .spaces:
            return ContextInfo(icon: "folder", description: "Browsing your Spaces")
        case .documents:
            if let docId = appState.selectedDocumentId,
               let doc = appState.workspace.documents.first(where: { $0.id == docId }) {
                return ContextInfo(icon: "doc.text", description: "Working with: \(doc.title.isEmpty ? "Untitled" : doc.title)")
            }
        case .conversations:
            if let convId = appState.selectedConversationId,
               let conv = appState.workspace.conversations.first(where: { $0.id == convId }) {
                return ContextInfo(icon: "bubble.left", description: "In conversation: \(conv.title)")
            }
        case .tasks:
            return ContextInfo(icon: "checklist", description: "Managing tasks across Spaces")
        case .decisions:
            return ContextInfo(icon: "checkmark.seal", description: "Pending decisions to review")
        default:
            break
        }
        return nil
    }

    private var welcomeMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.purple.opacity(0.6))

            Text("How can I help?")
                .font(.headline)

            Text("I'm aware of your current context and can help with:\n• Writing and editing\n• Research and analysis\n• Brainstorming ideas\n• Answering questions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

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

    private func sendMessage() {
        guard !message.isEmpty else { return }

        let userMessage = PanelMessage(role: .user, content: message)
        messages.append(userMessage)
        let sentMessage = message
        message = ""
        isLoading = true

        // Simulate response
        Task {
            try? await Task.sleep(for: .milliseconds(800))

            let response = PanelMessage(
                role: .assistant,
                content: "This is a placeholder response to: \"\(sentMessage)\"\n\nIn the full implementation, this would use the AgentKit framework to process your request with full context awareness."
            )
            messages.append(response)
            isLoading = false
        }
    }
}

// MARK: - Supporting Types

struct ContextInfo {
    let icon: String
    let description: String
}

struct PanelMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp = Date()
}

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
