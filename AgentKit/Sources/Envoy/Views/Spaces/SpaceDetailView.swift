import AgentKit
import SwiftUI

// MARK: - Space Detail View

/// Slack-like view of a Space with channel messages, rich content, and input
struct SpaceDetailView: View {
    let spaceId: SpaceID
    @EnvironmentObject private var appState: AppState
    @State private var messageInput = ""
    @State private var showProfilePanel = false
    @State private var selectedMemberId: String?
    @FocusState private var isInputFocused: Bool

    var space: SpaceViewModel? {
        // Only use actual spaces
        appState.spaces.first { SpaceID($0.id) == spaceId }
    }

    var selectedChannel: ChannelViewModel? {
        guard let channelId = appState.selectedChannelId else { return nil }
        return space?.channels.first { $0.id == channelId }
    }

    /// Get conversations for this space/channel
    var channelMessages: [Conversation] {
        // Filter conversations that belong to this space
        // For now, show all conversations if no space filter is set
        appState.workspace.conversations
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main content area
            VStack(spacing: 0) {
                // Channel header
                channelHeader

                Divider()

                // Message feed (main content)
                messageFeed

                Divider()

                // Input area
                messageInputArea
            }

            // Profile panel (optional, shown when clicking on a user)
            if showProfilePanel, let memberId = selectedMemberId {
                Divider()
                profilePanel(for: memberId)
                    .frame(width: 280)
            }
        }
        .navigationTitle(space?.name ?? "Space")
    }

    // MARK: - Channel Header

    private var channelHeader: some View {
        HStack(spacing: 12) {
            // Channel icon and name
            if let channel = selectedChannel {
                Image(systemName: channel.icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text(channel.name)
                    .font(.title2.weight(.semibold))
            } else if let space = space {
                RoundedRectangle(cornerRadius: 6)
                    .fill(space.color.gradient)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: space.icon)
                            .font(.caption)
                            .foregroundStyle(.white)
                    }

                Text(space.name)
                    .font(.title2.weight(.semibold))
            }

            Spacer()

            // Member count and actions
            HStack(spacing: 16) {
                if let channel = selectedChannel {
                    Label("\(channel.threadCount)", systemImage: "bubble.left.and.bubble.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button(action: { showProfilePanel.toggle() }) {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show members")

                Button(action: { /* TODO: Search */ }) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Search")

                Button(action: { /* TODO: More options */ }) {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("More options")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Message Feed

    private var messageFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // If no messages, show welcome message
                    if channelMessages.isEmpty {
                        welcomeMessage
                    } else {
                        // Group messages by date
                        ForEach(channelMessages) { conversation in
                            // Each conversation becomes a thread starter
                            ForEach(conversation.messages) { message in
                                MessageRow(
                                    message: message,
                                    conversationTitle: conversation.title,
                                    agentName: conversation.agentName,
                                    onMemberTap: { memberId in
                                        selectedMemberId = memberId
                                        showProfilePanel = true
                                    }
                                )
                                .id(message.id)
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
            }
        }
    }

    private var welcomeMessage: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Channel intro
            if let channel = selectedChannel {
                HStack {
                    Image(systemName: channel.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome to #\(channel.name)")
                            .font(.title.weight(.bold))

                        Text("This is the start of the \(channel.name) channel.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let space = space {
                HStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(space.color.gradient)
                        .frame(width: 64, height: 64)
                        .overlay {
                            Image(systemName: space.icon)
                                .font(.title)
                                .foregroundStyle(.white)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome to \(space.name)")
                            .font(.title.weight(.bold))

                        if let desc = space.description {
                            Text(desc)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Quick actions
            HStack(spacing: 12) {
                SpaceQuickAction(
                    icon: "bubble.left.and.bubble.right",
                    label: "Start a conversation",
                    color: .blue
                ) {
                    // TODO: Start new conversation
                }

                SpaceQuickAction(
                    icon: "doc.badge.plus",
                    label: "Create a document",
                    color: .green
                ) {
                    appState.showNewDocumentSheet = true
                }

                SpaceQuickAction(
                    icon: "person.badge.plus",
                    label: "Invite an agent",
                    color: .purple
                ) {
                    appState.showAgentRecruitment = true
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Message Input

    private var messageInputArea: some View {
        VStack(spacing: 0) {
            // Formatting toolbar
            HStack(spacing: 4) {
                ForEach(formattingButtons, id: \.icon) { button in
                    Button(action: button.action) {
                        Image(systemName: button.icon)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(button.label)
                }

                Spacer()

                // Mention and emoji
                Button(action: { /* TODO: Mention */ }) {
                    Image(systemName: "at")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: { /* TODO: Emoji */ }) {
                    Image(systemName: "face.smiling")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: { /* TODO: Attach */ }) {
                    Image(systemName: "paperclip")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Text input
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message \(selectedChannel?.name ?? space?.name ?? "channel")...", text: $messageInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        if !messageInput.isEmpty {
                            sendMessage()
                        }
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(messageInput.isEmpty ? Color.secondary : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(messageInput.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(.ultraThinMaterial)
    }

    private var formattingButtons: [(icon: String, label: String, action: () -> Void)] {
        [
            ("bold", "Bold", {}),
            ("italic", "Italic", {}),
            ("strikethrough", "Strikethrough", {}),
            ("link", "Link", {}),
            ("list.bullet", "Bullet list", {}),
            ("list.number", "Numbered list", {}),
            ("chevron.left.forwardslash.chevron.right", "Code", {}),
        ]
    }

    // MARK: - Profile Panel

    private func profilePanel(for memberId: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Profile")
                    .font(.headline)

                Spacer()

                Button(action: { showProfilePanel = false }) {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Avatar
                    Circle()
                        .fill(Color.purple.gradient)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Text("TA")
                                .font(.title)
                                .foregroundStyle(.white)
                        }

                    // Name and role
                    VStack(spacing: 4) {
                        Text("Technical Agent")
                            .font(.headline)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Contact info
                    VStack(alignment: .leading, spacing: 12) {
                        ProfileInfoRow(icon: "envelope", label: "Email", value: "agent@local")
                        ProfileInfoRow(icon: "clock", label: "Local time", value: "4:41 PM")
                        ProfileInfoRow(icon: "calendar", label: "Joined", value: "January 2025")
                    }
                    .padding(.horizontal)

                    Divider()

                    // Actions
                    HStack(spacing: 12) {
                        Button(action: { /* TODO: Message */ }) {
                            Label("Message", systemImage: "bubble.left")
                        }
                        .buttonStyle(.bordered)

                        Button(action: { /* TODO: Call */ }) {
                            Label("Huddle", systemImage: "phone")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageInput.isEmpty else { return }

        // Create new conversation message
        Task {
            // For now, add to first conversation or create new one
            if var conversation = appState.workspace.conversations.first {
                let message = ConversationMessage(
                    role: .user,
                    content: messageInput
                )
                conversation.messages.append(message)

                // Update the conversation in workspace
                if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
                    appState.workspace.conversations[index] = conversation
                }
            } else {
                // Create new conversation
                let conversation = Conversation(
                    title: messageInput.prefix(50).description,
                    messages: [
                        ConversationMessage(role: .user, content: messageInput)
                    ],
                    agentName: "Assistant"
                )
                appState.workspace.conversations.insert(conversation, at: 0)
            }

            messageInput = ""
        }
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    let message: ConversationMessage
    let conversationTitle: String
    let agentName: String?
    let onMemberTap: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Button(action: { onMemberTap(message.role == .user ? "user" : "agent") }) {
                Circle()
                    .fill(avatarGradient)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(avatarInitial)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                // Name and timestamp
                HStack(spacing: 8) {
                    Text(senderName)
                        .font(.subheadline.weight(.semibold))

                    Text(message.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Message content
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)

                // Tool indicator if applicable
                if let metadata = message.metadata, metadata.model != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text("via \(metadata.model ?? "AI")")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                }
            }

            Spacer()

            // Hover actions
            if isHovered {
                HStack(spacing: 4) {
                    MessageActionButton(icon: "face.smiling", tooltip: "React") {}
                    MessageActionButton(icon: "arrowshape.turn.up.left", tooltip: "Reply") {}
                    MessageActionButton(icon: "bookmark", tooltip: "Bookmark") {}
                    MessageActionButton(icon: "ellipsis", tooltip: "More") {}
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(isHovered ? Color.gray.opacity(0.05) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var senderName: String {
        message.role == .user ? "You" : (agentName ?? "Assistant")
    }

    private var avatarInitial: String {
        String(senderName.prefix(1))
    }

    private var avatarGradient: LinearGradient {
        let color: Color = message.role == .user ? .blue : .purple
        return LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Supporting Views

private struct SpaceQuickAction: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(label)
                    .font(.subheadline)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(isHovered ? 0.15 : 0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct ProfileInfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.subheadline)
            }
        }
    }
}
