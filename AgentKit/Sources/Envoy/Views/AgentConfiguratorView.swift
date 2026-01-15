import AgentKit
import SwiftUI

// MARK: - Agent Configurator View

/// Custom GPT-style interface for creating/editing agents through conversation.
///
/// The view is split into:
/// - Left: Chat interface for natural language configuration
/// - Right: Live preview of the agent configuration
struct AgentConfiguratorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [ConfigMessage] = []
    @State private var inputText = ""
    @State private var config = ChatAgentConfig()
    @State private var isProcessing = false
    @State private var showingAdvanced = false

    /// Existing config to edit, or nil for new agent
    var existingConfig: ChatAgentConfig?

    var body: some View {
        HSplitView {
            // Left: Chat interface
            chatPanel

            // Right: Config preview
            configPanel
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            if let existing = existingConfig {
                config = existing
                messages.append(ConfigMessage(
                    role: .assistant,
                    content: "Welcome back! I'm ready to help you update \(existing.name.isEmpty ? "your agent" : existing.name). What would you like to change?"
                ))
            } else {
                messages.append(ConfigMessage(
                    role: .assistant,
                    content: "Hi! I'll help you create a custom AI agent. Just describe what you want it to do, and I'll configure it for you.\n\nFor example, you could say:\n• \"I want a writing assistant that helps me draft emails\"\n• \"Create an agent that manages my calendar and reminds me of tasks\"\n• \"I need a research helper that can search the web and summarize articles\""
                ))
            }
        }
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("Agent Configurator")
                    .font(.headline)

                Spacer()

                Button("Advanced") {
                    showingAdvanced.toggle()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Messages
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            ConfigMessageView(message: message)
                                .id(message.id)
                        }

                        if isProcessing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Thinking...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                    .onChange(of: messages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 12) {
                TextField("Describe what you want your agent to do...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .onSubmit {
                        if !inputText.isEmpty {
                            sendMessage()
                        }
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.accentColor)
                .disabled(inputText.isEmpty || isProcessing)
            }
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 400)
    }

    // MARK: - Config Panel

    private var configPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with icon preview
                HStack(spacing: 16) {
                    // Icon
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorFromString(config.color).gradient)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Image(systemName: config.icon)
                                .font(.system(size: 32))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: colorFromString(config.color).opacity(0.4), radius: 8)

                    VStack(alignment: .leading, spacing: 4) {
                        if config.name.isEmpty {
                            Text("Your Agent")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(config.name)
                                .font(.title2.weight(.semibold))
                        }

                        if config.description.isEmpty {
                            Text("Describe what your agent does to get started")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(config.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 8)

                Divider()

                // Configuration sections
                ConfigSection(title: "Personality", icon: "face.smiling") {
                    if config.personality.isEmpty {
                        Text("Not configured yet")
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(config.personality)
                    }
                }

                ConfigSection(title: "Skills", icon: "star") {
                    if config.skills.isEmpty {
                        Text("No skills added")
                            .foregroundStyle(.tertiary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(config.skills, id: \.self) { skill in
                                Text(skill)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                ConfigSection(title: "Enabled Tools", icon: "wrench.and.screwdriver") {
                    if config.enabledTools.isEmpty {
                        Text("No tools enabled")
                            .foregroundStyle(.tertiary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(config.enabledTools, id: \.self) { tool in
                                HStack(spacing: 8) {
                                    Image(systemName: toolIcon(for: tool))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                    Text(toolName(for: tool))
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }

                ConfigSection(title: "Knowledge Sources", icon: "book.closed") {
                    if config.knowledgeSources.isEmpty {
                        Text("No knowledge sources")
                            .foregroundStyle(.tertiary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(config.knowledgeSources, id: \.self) { source in
                                Text("• \(source)")
                            }
                        }
                    }
                }

                if !config.customInstructions.isEmpty {
                    ConfigSection(title: "Custom Instructions", icon: "text.alignleft") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(config.customInstructions, id: \.self) { instruction in
                                Text("• \(instruction)")
                            }
                        }
                    }
                }

                Spacer()

                // Actions
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)

                    Spacer()

                    Button("Save Agent") {
                        saveAgent()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(config.name.isEmpty)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 350, idealWidth: 400)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !inputText.isEmpty else { return }

        let userMessage = inputText
        inputText = ""

        messages.append(ConfigMessage(role: .user, content: userMessage))
        isProcessing = true

        // Use real LLM for agent configuration
        Task {
            await processWithLLM(userMessage)
        }
    }

    private func processWithLLM(_ userMessage: String) async {
        // Get the configurator model from settings
        let configuratorModel = UserDefaults.standard.string(forKey: "configuratorModel") ?? "apple-intelligence"
        let provider = await getConfiguratorProvider()

        // Build conversation history for context
        let conversationMessages = messages.map { msg -> Message in
            switch msg.role {
            case .user:
                return Message(role: .user, content: .text(msg.content))
            case .assistant:
                return Message(role: .assistant, content: .text(msg.content))
            }
        }

        // Add system prompt for agent configuration
        let systemPrompt = """
        You are an expert AI agent configurator. Your role is to help users create custom AI agents through conversation.

        Based on the user's description, update the agent configuration by suggesting:
        - A clear name for the agent
        - A concise description of what it does
        - Relevant skills/capabilities
        - Required tools (calendar, reminders, web, filesystem, git, shell, memory)
        - Personality traits (friendly, professional, casual, formal, etc.)

        Always:
        - Ask clarifying questions when requirements are unclear
        - Provide helpful suggestions based on the user's needs
        - Explain what each tool or capability enables
        - Be conversational and encouraging

        Current configuration state:
        Name: \(config.name.isEmpty ? "(not set)" : config.name)
        Description: \(config.description.isEmpty ? "(not set)" : config.description)
        Skills: \(config.skills.isEmpty ? "(none)" : config.skills.joined(separator: ", "))
        Tools: \(config.enabledTools.isEmpty ? "(none)" : config.enabledTools.joined(separator: ", "))
        Personality: \(config.personality.isEmpty ? "(not set)" : config.personality)
        """

        let options = CompletionOptions(
            model: configuratorModel == "apple-intelligence" ? nil : configuratorModel,
            systemPrompt: systemPrompt,
            stream: true
        )

        do {
            let stream = try await provider.complete(conversationMessages, tools: [], options: options)
            var fullResponse = ""

            for try await event in stream {
                switch event {
                case .textDelta(let delta):
                    fullResponse += delta
                case .text(let text):
                    fullResponse = text
                case .done:
                    // Parse response and extract config updates
                    updateConfigFromResponse(fullResponse)
                    messages.append(ConfigMessage(role: .assistant, content: fullResponse))
                    isProcessing = false
                case .error(let error):
                    print("LLM Error: \(error)")
                    messages.append(ConfigMessage(
                        role: .assistant,
                        content: "I encountered an error processing your request. Please try again."
                    ))
                    isProcessing = false
                default:
                    break
                }
            }
        } catch {
            print("Failed to get LLM response: \(error)")
            messages.append(ConfigMessage(
                role: .assistant,
                content: "I'm having trouble connecting to the LLM. Please check your settings."
            ))
            isProcessing = false
        }
    }

    private func getConfiguratorProvider() async -> any LLMProvider {
        let providerType = UserDefaults.standard.string(forKey: "llmProvider") ?? "apple-intelligence"

        switch providerType {
        case "apple-intelligence":
            return FoundationModelsProvider()
        case "ollama":
            let urlString = UserDefaults.standard.string(forKey: "ollamaURL") ?? "http://localhost:11434"
            let url = URL(string: urlString)!
            let model = UserDefaults.standard.string(forKey: "configuratorModel") ?? "llama3.2"
            return OllamaProvider(baseURL: url, model: model)
        case "lmstudio":
            let urlString = UserDefaults.standard.string(forKey: "lmStudioURL") ?? "http://localhost:1234"
            let url = URL(string: urlString)!
            let model = UserDefaults.standard.string(forKey: "configuratorModel") ?? "llama3.2"
            // Parse host and port from URL
            let host = url.host ?? "localhost"
            let port = url.port ?? 1234
            return LMStudioProvider(host: host, port: port, defaultModel: model)
        default:
            return MockLLMProvider()
        }
    }

    private func updateConfigFromResponse(_ response: String) {
        // Simple heuristic parsing to extract config updates from natural language
        // In a production system, you might use structured output or function calling
        let lowercased = response.lowercased()

        // Extract name suggestions
        if let nameMatch = response.range(of: #"(?:name|call|named)\s+(?:it\s+)?["""']([^"""']+)["""']"#, options: .regularExpression) {
            let name = String(response[nameMatch]).replacingOccurrences(of: #"["""']"#, with: "", options: .regularExpression)
            if !name.isEmpty {
                config.name = name
            }
        }

        // Detect tool mentions
        let toolKeywords = [
            ("calendar", "calendar"),
            ("reminder", "reminders"),
            ("task", "reminders"),
            ("web", "web"),
            ("search", "web"),
            ("file", "filesystem"),
            ("git", "git"),
            ("shell", "shell"),
            ("memory", "memory"),
            ("rag", "memory")
        ]

        for (keyword, tool) in toolKeywords {
            if lowercased.contains(keyword) && !config.enabledTools.contains(tool) {
                config.enabledTools.append(tool)
            }
        }

        // Detect personality
        if lowercased.contains("friendly") || lowercased.contains("casual") {
            config.personality = "Friendly, casual, and approachable"
        } else if lowercased.contains("professional") || lowercased.contains("formal") {
            config.personality = "Professional, concise, and formal"
        }
    }

    private func processUserIntent(_ message: String) -> String {
        let lowercased = message.lowercased()

        // Simple intent detection (would be LLM-powered in production)
        if lowercased.contains("writing") || lowercased.contains("write") || lowercased.contains("blog") {
            config.name = "Writing Assistant"
            config.description = "Helps create engaging content and blog posts"
            config.skills.append("Content writing")
            config.skills.append("Editing")
            return "I've set up a Writing Assistant for you! It can help create engaging content. Would you like to add any specific capabilities, like SEO optimization or a particular writing style?"
        }

        if lowercased.contains("calendar") || lowercased.contains("schedule") {
            config.enabledTools.append("calendar")
            return "I've enabled calendar access. Your agent can now create events and check availability. What else would you like it to do?"
        }

        if lowercased.contains("reminder") || lowercased.contains("task") {
            config.enabledTools.append("reminders")
            return "I've enabled reminders/tasks. Your agent can now create and manage your to-do list. Anything else?"
        }

        if lowercased.contains("web") || lowercased.contains("search") || lowercased.contains("research") {
            config.enabledTools.append("web")
            config.skills.append("Web research")
            return "I've enabled web search for research capabilities. Your agent can now fetch and summarize web content."
        }

        if lowercased.contains("friendly") || lowercased.contains("casual") {
            config.personality = "Friendly, casual, and approachable"
            return "I've set a friendly, casual communication style. Your agent will be warm and approachable in its responses."
        }

        if lowercased.contains("professional") || lowercased.contains("formal") {
            config.personality = "Professional, concise, and formal"
            return "I've set a professional communication style. Your agent will be formal and to-the-point."
        }

        if lowercased.contains("name") {
            // Extract potential name from message
            let words = message.components(separatedBy: " ")
            if let nameIndex = words.firstIndex(where: { $0.lowercased() == "name" || $0.lowercased() == "called" }),
               nameIndex + 1 < words.count {
                let potentialName = words[(nameIndex + 1)...].joined(separator: " ")
                    .trimmingCharacters(in: .punctuationCharacters)
                config.name = potentialName
                return "I've named your agent '\(potentialName)'. What should it be able to do?"
            }
        }

        return "Got it! Tell me more about what you'd like your agent to help with. For example:\n• What tasks should it handle?\n• What tools does it need? (calendar, web search, files)\n• What personality should it have?"
    }

    private func saveAgent() {
        // Save to AppState
        // appState.saveAgentConfig(config)
        dismiss()
    }

    // MARK: - Helpers

    private func colorFromString(_ color: String) -> Color {
        switch color.lowercased() {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "pink": return .pink
        case "cyan": return .cyan
        case "red": return .red
        default: return .blue
        }
    }

    private func toolIcon(for tool: String) -> String {
        switch tool {
        case "calendar": return "calendar"
        case "reminders": return "checklist"
        case "filesystem": return "folder"
        case "git": return "arrow.triangle.branch"
        case "shell": return "terminal"
        case "web": return "globe"
        case "memory": return "brain"
        default: return "puzzlepiece"
        }
    }

    private func toolName(for tool: String) -> String {
        switch tool {
        case "calendar": return "Calendar"
        case "reminders": return "Reminders"
        case "filesystem": return "File System"
        case "git": return "Git"
        case "shell": return "Shell Commands"
        case "web": return "Web Search"
        case "memory": return "Memory (RAG)"
        default: return tool.capitalized
        }
    }
}

// MARK: - Config Message

struct ConfigMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp = Date()

    enum MessageRole {
        case user
        case assistant
    }
}

// MARK: - Config Message View

struct ConfigMessageView: View {
    let message: ConfigMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.purple)
                    .frame(width: 28, height: 28)
                    .background(.purple.opacity(0.15))
                    .clipShape(Circle())
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
        }
    }
}

// MARK: - Config Section

struct ConfigSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            content
                .font(.subheadline)
        }
    }
}

// MARK: - Flow Layout (for tags)

struct ConfigFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowLayoutResult(in: proposal.width ?? 0, spacing: spacing, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowLayoutResult(in: bounds.width, spacing: spacing, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    struct FlowLayoutResult {
        var positions: [CGPoint] = []
        var size: CGSize = .zero

        init(in width: CGFloat, spacing: CGFloat, subviews: Subviews) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + rowHeight)
        }
    }
}
