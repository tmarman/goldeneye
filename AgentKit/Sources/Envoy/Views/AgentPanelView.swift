import AgentKit
import SwiftUI

// MARK: - Agent Panel View

/// Slide-in panel for ambient agent interaction.
/// The agent is context-aware based on the current view/document.
/// Supports MLX, Ollama, OpenAI, Anthropic, and A2A agents.
struct AgentPanelView: View {
    @EnvironmentObject private var appState: AppState
    @State private var chatService = ChatService.shared
    @State private var providerManager = ProviderConfigManager.shared
    @State private var message = ""
    @State private var messages: [PanelMessage] = []
    @State private var isLoading = false
    @State private var streamingContent = ""
    @State private var errorMessage: String?

    /// Whether a provider is ready for chat
    private var hasProvider: Bool {
        chatService.isReady
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with connection status
            headerView

            Divider()

            // Provider selection banner (if no provider selected)
            if !hasProvider && !appState.isAgentConnected {
                providerSelectionBanner
            }

            // Model loading progress
            if chatService.isLoadingModel {
                modelLoadingBanner
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
                    .fill(connectionStatusColor)
                    .frame(width: 6, height: 6)
                Text(connectionStatusText)
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

    // MARK: - Provider Selection Banner

    private var providerSelectionBanner: some View {
        VStack(spacing: 8) {
            Text("Select a Model Provider")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Show configured providers
            ForEach(providerManager.enabledProviders) { config in
                providerRow(config)
            }

            // Quick MLX models (always available on Apple Silicon)
            mlxQuickLoadSection

            Divider()

            // A2A option at the bottom
            a2aConnectionRow
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private func providerRow(_ config: ProviderConfig) -> some View {
        Button(action: {
            Task {
                try? await chatService.selectProvider(config)
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: config.type.icon)
                    .foregroundStyle(config.type.color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                        .font(.caption.weight(.medium))
                    if let model = config.selectedModel {
                        Text(model)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Status indicator
                if let status = providerManager.providerStatus[config.id] {
                    providerStatusBadge(status)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(config.type.color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func providerStatusBadge(_ status: ProviderStatus) -> some View {
        switch status {
        case .available(let count):
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                if count > 0 {
                    Text("\(count)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .checking:
            ProgressView().scaleEffect(0.5)
        case .unavailable, .error:
            Circle().fill(.orange).frame(width: 6, height: 6)
        case .unknown:
            EmptyView()
        }
    }

    private var mlxQuickLoadSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("On-Device (MLX)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(recommendedMLXModels, id: \.self) { modelId in
                    Button(action: {
                        Task {
                            try? await chatService.loadMLXModel(modelId)
                        }
                    }) {
                        Text(mlxModelShortName(modelId))
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recommendedMLXModels: [String] {
        [
            "mlx-community/Qwen2.5-3B-Instruct-4bit",
            "mlx-community/Llama-3.2-3B-Instruct-4bit"
        ]
    }

    private func mlxModelShortName(_ modelId: String) -> String {
        let name = modelId.components(separatedBy: "/").last ?? modelId
        return name
            .replacingOccurrences(of: "-Instruct-4bit", with: "")
            .replacingOccurrences(of: "mlx-community/", with: "")
    }

    private var a2aConnectionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Server (A2A)")
                    .font(.caption.weight(.medium))
                Text("Multi-agent orchestration")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Connect") {
                Task {
                    await appState.connectToLocalAgent()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.05))
        )
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

                    // Generation stats (show after last message if available)
                    if let stats = chatService.generationStats, !isLoading {
                        generationStatsView(stats)
                            .id("stats")
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
        !message.isEmpty && !isLoading && (hasProvider || appState.isAgentConnected)
    }

    // MARK: - Connection Status

    private var connectionStatusColor: Color {
        if hasProvider {
            return chatService.isGenerating ? .purple : .green
        } else if appState.isAgentConnected {
            return .green
        }
        return .orange
    }

    private var connectionStatusText: String {
        if hasProvider {
            if chatService.isGenerating {
                return "Generating..."
            }
            return chatService.providerDescription
        } else if appState.isAgentConnected {
            return "A2A Online"
        }
        return "No Provider"
    }

    // MARK: - Model Loading Banner

    private var modelLoadingBanner: some View {
        HStack(spacing: 8) {
            ProgressView(value: chatService.loadProgress)
                .progressViewStyle(.linear)
                .frame(width: 100)

            Text("Loading model...")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(Int(chatService.loadProgress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.purple.opacity(0.1))
    }

    // MARK: - Generation Stats View

    private func generationStatsView(_ stats: GenerationStats) -> some View {
        HStack(spacing: 16) {
            Spacer()

            Label(stats.formattedTPS, systemImage: "bolt.fill")
                .font(.caption2)
                .foregroundStyle(.purple)

            Label(stats.formattedTTFT + " first token", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Label("\(stats.tokensGenerated) tokens", systemImage: "text.word.spacing")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Context & Agent Name

    private var contextualAgentName: String {
        switch appState.selectedSidebarItem {
        case .headspace:
            return "Capture Assistant"
        case .spaces:
            return "Space Navigator"
        case .documents:
            return "Writing Assistant"
        case .threads:
            return "Assistant"
        case .tasks:
            return "Task Manager"
        case .reviews:
            return "Review Advisor"
        default:
            return "Agent"
        }
    }

    private var currentContext: ContextInfo? {
        switch appState.selectedSidebarItem {
        case .headspace:
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
        case .threads:
            if let threadId = appState.selectedThreadId,
               let thread = appState.workspace.threads.first(where: { $0.id == threadId }) {
                return ContextInfo(
                    icon: "bubble.left",
                    description: "In thread: \(thread.title)",
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
        case .reviews:
            let count = appState.pendingDecisionCount + appState.pendingApprovals.count
            return ContextInfo(
                icon: "checkmark.seal",
                description: count > 0 ? "\(count) pending reviews" : "No pending reviews",
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
                    .disabled(!hasProvider && !appState.isAgentConnected)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var contextualQuickActions: [String] {
        switch appState.selectedSidebarItem {
        case .headspace:
            return ["Process my notes", "What's upcoming?", "Create a task", "Link to event"]
        case .spaces:
            return ["Create new Space", "Find documents", "Recent activity"]
        case .documents:
            return ["Improve writing", "Summarize", "Expand this", "Fix grammar", "Suggest structure"]
        case .threads:
            return ["Continue", "Summarize thread", "Find action items"]
        case .tasks:
            return ["What's due today?", "Prioritize tasks", "Delegate this"]
        case .reviews:
            return ["Show context", "Compare options", "Approve all"]
        default:
            return ["Help me with...", "Explain this", "What can you do?"]
        }
    }

    private func performQuickAction(_ action: String) {
        message = action
        sendMessage()
    }

    // MARK: - Send Message

    private func sendMessage() {
        guard canSend else { return }

        let userMessage = PanelMessage(role: .user, content: message)
        messages.append(userMessage)

        // Build context-aware prompt
        let contextualPrompt = buildContextualPrompt(message)
        message = ""
        isLoading = true
        streamingContent = ""
        errorMessage = nil

        Task {
            if hasProvider {
                await sendToProvider(contextualPrompt)
            } else {
                await sendToAgent(contextualPrompt)
            }
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

    // MARK: - Provider Chat

    private func sendToProvider(_ prompt: String) async {
        // Build chat history for context
        let history = messages.dropLast().map { msg in
            ChatMessage(content: msg.content, isUser: msg.role == .user)
        }

        // System prompt based on current context
        let systemPrompt = contextualSystemPrompt

        // Stream response from selected provider
        let stream = chatService.chat(
            prompt: prompt,
            systemPrompt: systemPrompt,
            history: Array(history)
        )

        var fullResponse = ""

        do {
            for try await chunk in stream {
                fullResponse += chunk
                await MainActor.run {
                    streamingContent = fullResponse
                }
            }

            // Add completed message
            let assistantMessage = PanelMessage(role: .assistant, content: fullResponse)
            messages.append(assistantMessage)

        } catch {
            errorMessage = "Generation failed: \(error.localizedDescription)"
        }

        isLoading = false
        streamingContent = ""
    }

    private var contextualSystemPrompt: String {
        let basePrompt = "You are a helpful AI assistant in Envoy, an ambient intelligence app. Be concise and direct."

        switch appState.selectedSidebarItem {
        case .headspace:
            return "\(basePrompt) You help with quick capture, notes, and timeline organization."
        case .documents:
            return "\(basePrompt) You are a writing assistant helping with document editing, writing improvement, and content organization."
        case .tasks:
            return "\(basePrompt) You help manage tasks, set priorities, and track progress."
        case .reviews:
            return "\(basePrompt) You help analyze options and make informed decisions."
        default:
            return basePrompt
        }
    }

    // MARK: - A2A Agent

    private func sendToAgent(_ prompt: String) async {
        // Use streaming via AppState's A2A client
        if let response = await appState.sendAgentMessage(prompt) {
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
