import AgentKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Space Detail View

/// Slack-like view of a Space with channel messages, rich content, and input
struct SpaceDetailView: View {
    let spaceId: SpaceID
    @EnvironmentObject private var appState: AppState
    @State private var messageInput = ""
    @State private var showProfilePanel = false
    @State private var selectedMemberId: String?
    @State private var showSearchSheet = false
    @State private var searchQuery = ""
    @State private var showEmojiPicker = false
    @State private var showFilePicker = false
    @FocusState private var isInputFocused: Bool

    var space: SpaceViewModel? {
        // Only use actual spaces
        appState.spaces.first { SpaceID($0.id) == spaceId }
    }

    var selectedChannel: ChannelViewModel? {
        guard let channelId = appState.selectedChannelId else { return nil }
        return space?.channels.first { $0.id == channelId }
    }

    /// Get threads for this space/channel
    var channelThreads: [AgentKit.Thread] {
        // Filter threads that belong to this space
        appState.workspace.threads.filter { $0.container == .space(spaceId.rawValue) }
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
        .sheet(isPresented: $showSearchSheet) {
            SearchMessagesSheet(
                threads: channelThreads,
                spaceId: spaceId,
                searchQuery: $searchQuery
            )
        }
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

                Button(action: { showSearchSheet = true }) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Search messages")

                Menu {
                    Button(action: { appState.showAgentRecruitment = true }) {
                        Label("Invite Agent", systemImage: "person.badge.plus")
                    }
                    Button(action: { appState.showNewDocumentSheet = true }) {
                        Label("New Document", systemImage: "doc.badge.plus")
                    }
                    Divider()
                    Button(action: { appState.selectedSidebarItem = .settings }) {
                        Label("Settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
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
                    if channelThreads.isEmpty {
                        welcomeMessage
                    } else {
                        // Group messages by date
                        ForEach(channelThreads) { thread in
                            // Each thread shows its messages
                            ForEach(thread.messages) { message in
                                ThreadMessageRow(
                                    message: message,
                                    threadTitle: thread.title,
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
                Button(action: { insertMention() }) {
                    Image(systemName: "at")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Mention someone")

                Button(action: { showEmojiPicker = true }) {
                    Image(systemName: "face.smiling")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEmojiPicker) {
                    EmojiPickerView { emoji in
                        messageInput += emoji
                        showEmojiPicker = false
                    }
                }
                .help("Add emoji")

                Button(action: { showFilePicker = true }) {
                    Image(systemName: "paperclip")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        // Add file reference to message
                        messageInput += " [\(url.lastPathComponent)](\(url.path))"
                    }
                }
                .help("Attach file")
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
            ("bold", "Bold", { wrapSelection(with: "**") }),
            ("italic", "Italic", { wrapSelection(with: "_") }),
            ("strikethrough", "Strikethrough", { wrapSelection(with: "~~") }),
            ("link", "Link", { insertLink() }),
            ("list.bullet", "Bullet list", { insertPrefix("- ") }),
            ("list.number", "Numbered list", { insertPrefix("1. ") }),
            ("chevron.left.forwardslash.chevron.right", "Code", { wrapSelection(with: "`") }),
        ]
    }

    // MARK: - Formatting Helpers

    private func wrapSelection(with wrapper: String) {
        // For simplicity, wrap the entire input or add placeholder
        if messageInput.isEmpty {
            messageInput = "\(wrapper)text\(wrapper)"
        } else {
            messageInput = "\(wrapper)\(messageInput)\(wrapper)"
        }
    }

    private func insertPrefix(_ prefix: String) {
        if messageInput.isEmpty {
            messageInput = prefix
        } else {
            messageInput = prefix + messageInput
        }
    }

    private func insertLink() {
        messageInput += "[link text](url)"
    }

    private func insertMention() {
        messageInput += "@"
        isInputFocused = true
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

                    // Action buttons - Message and Huddle
                    HStack(spacing: 12) {
                        Button(action: { startDirectMessage(with: memberId) }) {
                            Label("Message", systemImage: "bubble.left.fill")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)

                        Button(action: { startHuddle(with: memberId) }) {
                            Label("Huddle", systemImage: "phone.fill")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                    .padding(.horizontal)

                    Divider()

                    // Contact info
                    VStack(alignment: .leading, spacing: 12) {
                        ProfileInfoRow(icon: "envelope", label: "Email", value: "agent@local")
                        ProfileInfoRow(icon: "clock", label: "Local time", value: Date().formatted(date: .omitted, time: .shortened))
                        ProfileInfoRow(icon: "calendar", label: "Status", value: "Active")
                    }
                    .padding(.horizontal)

                }
                .padding()
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Direct Message & Huddle Actions

    /// Start a direct message thread with the selected member
    private func startDirectMessage(with memberId: String) {
        // Create a DM thread with this member
        let memberName = memberId == "user" ? "You" : "Technical Agent"
        let dmTitle = "DM with \(memberName)"

        Task {
            // Check if a DM thread already exists with this member
            let existingDM = appState.workspace.threads.first { thread in
                if case .global = thread.container {
                    return thread.title.contains(memberName) && thread.title.hasPrefix("DM")
                }
                return false
            }

            if let existing = existingDM {
                // Navigate to existing DM
                appState.selectedThreadId = existing.id
            } else {
                // Create new DM thread
                var thread = AgentKit.Thread(
                    title: dmTitle,
                    container: .global  // DMs are global, not space-scoped
                )
                thread.addMessage(ThreadMessage.system("Started a conversation with \(memberName)"))
                appState.workspace.threads.insert(thread, at: 0)

                // Persist the new thread
                if let store = appState.threadStore {
                    try? await store.save(thread)
                }

                // Navigate to the new DM
                appState.selectedThreadId = thread.id
            }

            // Close the profile panel
            showProfilePanel = false
        }
    }

    /// Start a huddle (voice/video call) with the selected member
    private func startHuddle(with memberId: String) {
        let memberName = memberId == "user" ? "You" : "Technical Agent"

        // For now, create a system message indicating huddle intent
        // In future, this would integrate with WebRTC or similar
        Task {
            // Find or create a thread for huddle notifications
            var thread = appState.workspace.threads.first { thread in
                if case .space(let id) = thread.container {
                    return id == spaceId.rawValue
                }
                return false
            }

            if thread == nil {
                // Create new thread for this space
                thread = AgentKit.Thread(
                    title: "Space Activity",
                    container: .space(spaceId.rawValue)
                )
                appState.workspace.threads.insert(thread!, at: 0)
            }

            // Add huddle notification message
            let huddleMessage = ThreadMessage.system("🎙️ \(UserDefaults.standard.string(forKey: "userName") ?? "You") started a huddle with \(memberName). Voice/video calls coming soon!")
            thread!.addMessage(huddleMessage)

            // Update the thread
            if let index = appState.workspace.threads.firstIndex(where: { $0.id == thread!.id }) {
                appState.workspace.threads[index] = thread!
            }

            // Persist
            if let store = appState.threadStore {
                try? await store.save(thread!)
            }

            // Close the profile panel
            showProfilePanel = false
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageInput.isEmpty else { return }

        // Create new thread message
        Task {
            // Find existing thread in this space, or create new one
            if var thread = channelThreads.first {
                let message = ThreadMessage.user(messageInput)
                thread.addMessage(message)

                // Update the thread in workspace
                if let index = appState.workspace.threads.firstIndex(where: { $0.id == thread.id }) {
                    appState.workspace.threads[index] = thread
                }

                // Persist the update
                if let store = appState.threadStore {
                    try? await store.save(thread)
                }
            } else {
                // Create new thread scoped to this space
                var thread = AgentKit.Thread(
                    title: String(messageInput.prefix(50)),
                    container: .space(spaceId.rawValue)
                )
                thread.addMessage(ThreadMessage.user(messageInput))
                appState.workspace.threads.insert(thread, at: 0)

                // Persist the new thread
                if let store = appState.threadStore {
                    try? await store.save(thread)
                }
            }

            messageInput = ""
        }
    }
}

// MARK: - Thread Message Row

private struct ThreadMessageRow: View {
    let message: ThreadMessage
    let threadTitle: String
    let onMemberTap: (String) -> Void

    @State private var isHovered = false
    @State private var showReactionPicker = false
    @State private var isBookmarked = false

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
                Text(message.textContent)
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
                    MessageActionButton(icon: "face.smiling", tooltip: "React") {
                        showReactionPicker = true
                    }
                    .popover(isPresented: $showReactionPicker) {
                        EmojiPickerView { emoji in
                            // In a full implementation, this would add the reaction to the message
                            showReactionPicker = false
                        }
                    }

                    MessageActionButton(icon: "arrowshape.turn.up.left", tooltip: "Reply") {
                        // Copy message content to clipboard for easy reply reference
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.textContent, forType: .string)
                    }

                    MessageActionButton(
                        icon: isBookmarked ? "bookmark.fill" : "bookmark",
                        tooltip: isBookmarked ? "Remove bookmark" : "Bookmark"
                    ) {
                        isBookmarked.toggle()
                    }

                    Menu {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.textContent, forType: .string)
                        }) {
                            Label("Copy text", systemImage: "doc.on.doc")
                        }
                        Divider()
                        Button(role: .destructive, action: {}) {
                            Label("Delete message", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
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
        message.sender.displayName
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

// MARK: - Search Messages Sheet

private struct SearchMessagesSheet: View {
    let threads: [AgentKit.Thread]
    let spaceId: SpaceID?
    @Binding var searchQuery: String
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool

    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    /// Search result combining memory search with message data
    struct SearchResult: Identifiable {
        let id: String
        let message: AgentKit.ThreadMessage
        let threadTitle: String
        let score: Float
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search messages...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onChange(of: searchQuery) { _, newValue in
                        performSearch(query: newValue)
                    }

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Results
            if searchQuery.isEmpty {
                ContentUnavailableView(
                    "Semantic Search",
                    systemImage: "sparkle.magnifyingglass",
                    description: Text("Type to search semantically through messages")
                )
            } else if isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("No messages match \"\(searchQuery)\"")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(searchResults) { result in
                            SearchResultRow(
                                message: result.message,
                                threadTitle: result.threadTitle,
                                query: searchQuery,
                                score: result.score
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear { isSearchFocused = true }
    }

    private func performSearch(query: String) {
        // Cancel any existing search
        searchTask?.cancel()

        guard !query.isEmpty else {
            searchResults = []
            return
        }

        // Debounce: wait a bit before searching
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            await MainActor.run { isSearching = true }

            // Try vector search first if memoryStore is available
            if let memoryStore = appState.memoryStore {
                do {
                    // Build filter for this space
                    let filter = spaceId.map { id in
                        MemoryFilter(
                            spaceIds: [id.rawValue],
                            sourceTypes: [MemoryFilter.SourceType.thread]
                        )
                    } ?? MemoryFilter(sourceTypes: [MemoryFilter.SourceType.thread])

                    let vectorResults = try await memoryStore.search(
                        query: query,
                        limit: 20,
                        threshold: 0.3,
                        filter: filter
                    )

                    // Map vector results back to messages
                    var results: [SearchResult] = []
                    for vectorResult in vectorResults {
                        // Extract thread/message IDs from source
                        if case .thread(let sessionId, let messageId) = vectorResult.item.source {
                            let msgId = messageId
                            // Find the matching message in our threads
                            for thread in threads {
                                if let message = thread.messages.first(where: {
                                    $0.id.uuidString == msgId || thread.id.rawValue == sessionId
                                }) {
                                    results.append(SearchResult(
                                        id: msgId,
                                        message: message,
                                        threadTitle: thread.title,
                                        score: vectorResult.score
                                    ))
                                    break
                                }
                            }
                        }
                    }

                    // If vector search returned results, use them
                    if !results.isEmpty {
                        await MainActor.run {
                            self.searchResults = results
                            self.isSearching = false
                        }
                        return
                    }
                } catch {
                    print("Vector search failed, falling back to text: \(error)")
                }
            }

            // Fallback to simple text search
            let lowerQuery = query.lowercased()
            var fallbackResults: [SearchResult] = []

            for thread in threads {
                for message in thread.messages {
                    if message.textContent.lowercased().contains(lowerQuery) {
                        fallbackResults.append(SearchResult(
                            id: message.id.uuidString,
                            message: message,
                            threadTitle: thread.title,
                            score: 1.0  // Exact match
                        ))
                    }
                }
            }

            await MainActor.run {
                self.searchResults = fallbackResults
                self.isSearching = false
            }
        }
    }
}

private struct SearchResultRow: View {
    let message: AgentKit.ThreadMessage
    let threadTitle: String
    let query: String
    let score: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.sender.displayName)
                    .font(.caption.weight(.medium))
                Text("in \(threadTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Show relevance score for semantic search
                if score < 1.0 {
                    Text("\(Int(score * 100))% match")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }

                Spacer()
                Text(message.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(message.textContent)
                .font(.subheadline)
                .lineLimit(3)
        }
        .padding(10)
        .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Emoji Picker View

private struct EmojiPickerView: View {
    let onSelect: (String) -> Void

    private let commonEmojis = [
        "👍", "👎", "❤️", "🎉", "🚀", "✅", "❌", "💡",
        "🔥", "⭐", "💪", "🙌", "👀", "💬", "📝", "🎯",
        "✨", "💯", "🤔", "😊", "😂", "🙏", "👏", "🤝"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Reactions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 8), spacing: 4) {
                ForEach(commonEmojis, id: \.self) { emoji in
                    Button(action: { onSelect(emoji) }) {
                        Text(emoji)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 36, height: 36)
                }
            }
            .padding(8)
        }
        .padding(8)
        .frame(width: 320)
    }
}
