import AgentKit
import SwiftUI

// MARK: - Conversations View

struct ConversationsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return appState.workspace.conversations
        }
        return appState.workspace.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.messages.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        HSplitView {
            // Conversation list
            conversationList
                .frame(minWidth: 250, maxWidth: 350)

            // Selected conversation detail
            if let selectedId = appState.selectedConversationId,
               let conversation = appState.workspace.conversations.first(where: { $0.id == selectedId }) {
                ConversationDetailView(conversation: conversation)
            } else {
                EmptyConversationDetailView()
            }
        }
        .navigationTitle("Conversations")
        .searchable(text: $searchText, prompt: "Search conversations...")
        .toolbar {
            ToolbarItem {
                Button(action: { appState.showNewConversationSheet = true }) {
                    Label("New Conversation", systemImage: "plus")
                }
            }
        }
    }

    private var conversationList: some View {
        List(selection: $appState.selectedConversationId) {
            if !appState.workspace.conversations.filter({ $0.isPinned }).isEmpty {
                Section("Pinned") {
                    ForEach(filteredConversations.filter { $0.isPinned }) { conversation in
                        ConversationRow(conversation: conversation)
                            .tag(conversation.id)
                    }
                }
            }

            Section("Recent") {
                ForEach(filteredConversations.filter { !$0.isPinned }) { conversation in
                    ConversationRow(conversation: conversation)
                        .tag(conversation.id)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if conversation.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }

                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            if let agentName = conversation.agentName {
                HStack(spacing: 4) {
                    Image(systemName: "person.circle")
                    Text(agentName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(conversation.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(conversation.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Conversation Detail View

struct ConversationDetailView: View {
    let conversation: Conversation
    @EnvironmentObject private var appState: AppState
    @State private var newMessage = ""
    @State private var isLoading = false
    @State private var streamingResponse = ""  // For real-time display of agent response
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(conversation.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let agentName = conversation.agentName {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(appState.isAgentConnected ? .green : .orange)
                                .frame(width: 8, height: 8)
                            Text(agentName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !appState.isAgentConnected {
                                Text("(disconnected)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Spacer()

                Menu {
                    Button(action: {}) {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(action: {}) {
                        Label(conversation.isPinned ? "Unpin" : "Pin", systemImage: conversation.isPinned ? "pin.slash" : "pin")
                    }
                    Button(action: {}) {
                        Label(conversation.isStarred ? "Remove Star" : "Add Star", systemImage: conversation.isStarred ? "star.slash" : "star")
                    }
                    Divider()
                    Button(role: .destructive, action: {}) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            // Error banner
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") {
                        errorMessage = nil
                    }
                    .font(.caption)
                }
                .padding(8)
                .background(.orange.opacity(0.1))
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(conversation.messages) { message in
                            ConversationMessageBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming response (shown while agent is responding)
                        if isLoading && !streamingResponse.isEmpty {
                            StreamingMessageView(content: streamingResponse)
                                .id("streaming")
                        } else if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Agent is thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    if let lastId = conversation.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: streamingResponse) { _, _ in
                    // Scroll as streaming content comes in
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input area
            HStack(spacing: 12) {
                TextField("Type a message...", text: $newMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: { sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(newMessage.isEmpty || isLoading)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding()
            .background(Color(.controlBackgroundColor))
        }
    }

    private func sendMessage() {
        guard !newMessage.isEmpty else { return }

        // Check connection status
        guard appState.isAgentConnected else {
            errorMessage = "Not connected to agent. Please connect first from the Connections tab."
            return
        }

        let messageContent = newMessage
        let userMessage = ConversationMessage(role: .user, content: messageContent)

        // Add user message to conversation
        if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
            appState.workspace.conversations[index].messages.append(userMessage)
            appState.workspace.conversations[index].updatedAt = Date()
        }

        newMessage = ""
        streamingResponse = ""
        isLoading = true
        errorMessage = nil

        // Send via A2A protocol
        Task {
            do {
                let stream = try await appState.sendConversationMessage(
                    conversationId: conversation.id,
                    content: messageContent
                )

                // Consume streaming deltas for real-time display
                for try await delta in stream {
                    streamingResponse += delta
                }

                // Response is already added to conversation by AppState
            } catch {
                // Handle error - add error message to conversation
                let errMsg = ConversationMessage(
                    role: .assistant,
                    content: "Sorry, I encountered an error: \(error.localizedDescription)"
                )
                if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
                    appState.workspace.conversations[index].messages.append(errMsg)
                }
                errorMessage = error.localizedDescription
            }

            streamingResponse = ""
            isLoading = false
        }
    }
}

// MARK: - Streaming Message View

/// Displays a message that's being streamed in real-time
struct StreamingMessageView: View {
    let content: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                    Text("Agent")
                        .fontWeight(.medium)
                }
                .font(.caption)

                Text(content)
                    .padding(12)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                // Typing indicator
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.accentColor.opacity(0.6))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.leading, 12)
            }

            Spacer(minLength: 60)
        }
    }
}

// MARK: - Conversation Message Bubble

struct ConversationMessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.accentColor : Color(.controlBackgroundColor))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Empty State

struct EmptyConversationDetailView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Select a Conversation")
                .font(.title2)
                .fontWeight(.medium)

            Text("Choose a conversation from the list or start a new one.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - New Conversation Sheet

struct NewConversationSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedAgentId: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("New Conversation")
                .font(.headline)

            TextField("Conversation Title", text: $title)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Agent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Agent", selection: $selectedAgentId) {
                    Text("Primary Agent").tag("primary" as String?)
                    if let local = appState.localAgent {
                        Text(local.name).tag(local.id as String?)
                    }
                    ForEach(appState.connectedAgents) { agent in
                        Text(agent.name).tag(agent.id as String?)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Create") {
                    createConversation()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            selectedAgentId = "primary"
        }
    }

    private func createConversation() {
        let conversation = Conversation(
            title: title.isEmpty ? "New Conversation" : title,
            agentName: selectedAgentId == "primary" ? "Primary Agent" : selectedAgentId
        )
        appState.workspace.conversations.insert(conversation, at: 0)
        appState.selectedConversationId = conversation.id
        dismiss()
    }
}
