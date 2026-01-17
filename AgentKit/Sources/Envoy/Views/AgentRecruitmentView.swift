import AgentKit
import MarkdownUI
import SwiftUI

// MARK: - Agent Recruitment View

/// Conversational interface for creating agents through natural chat
/// The user describes what they need, and together we build the agent
struct AgentRecruitmentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(ChatService.self) private var chatService
    @Environment(\.dismiss) private var dismiss

    // Chat state
    @State private var messages: [AgentChatMessage] = []
    @State private var userInput = ""
    @State private var isGenerating = false
    @State private var streamingResponse = ""
    @FocusState private var inputFocused: Bool

    // Agent being built
    @State private var agentDraft = RecruitmentAgentDraft()
    @State private var showPreview = false
    @State private var canCreate = false

    // System prompt for the agent-building conversation
    private var systemPrompt: String {
        """
        You are helping the user create a custom AI agent for their personal workspace.

        Your job is to have a natural conversation to understand what they need, then help shape the agent's:
        - Purpose and capabilities
        - Communication style (formal, casual, encouraging, direct, etc.)
        - Key skills and expertise areas

        Guidelines:
        - Be conversational and helpful, not formal or stiff
        - Ask clarifying questions to understand their needs
        - Suggest ideas but let them drive the direction
        - Keep responses concise (2-4 sentences)
        - After 2-3 exchanges, start suggesting a name and summarizing what you've learned
        - When they seem satisfied, tell them they can click "Create Agent" to finish

        When you have enough information, include a summary block like this:
        ---
        **Agent Summary**
        - Name: [suggested name]
        - Role: [one-line description]
        - Style: [communication style]
        - Skills: [comma-separated list]
        ---

        Current draft state:
        - Name: \(agentDraft.name.isEmpty ? "Not set" : agentDraft.name)
        - Role: \(agentDraft.role.isEmpty ? "Not set" : agentDraft.role)
        - Skills: \(agentDraft.skills.isEmpty ? "None yet" : agentDraft.skills.joined(separator: ", "))
        """
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main chat area
            VStack(spacing: 0) {
                // Header
                headerView

                Divider()

                // Chat messages
                chatArea

                // Starter suggestions (only when empty)
                if messages.isEmpty {
                    starterSuggestions
                }

                Divider()

                // Input area
                inputArea
            }

            // Preview panel (slides in when we have draft info)
            if showPreview {
                Divider()
                previewPanel
                    .frame(width: 280)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(width: showPreview ? 780 : 500, height: 560)
        .animation(.spring(response: 0.3), value: showPreview)
        .onAppear {
            startConversation()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.gradient)
                    .frame(width: 36, height: 36)

                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Create an Agent")
                    .font(.headline)

                Text("Describe what you need help with")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if canCreate {
                Button(action: createAgent) {
                    Text("Create Agent")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        AgentChatBubble(message: message)
                            .id(message.id)
                    }

                    // Streaming response
                    if isGenerating && !streamingResponse.isEmpty {
                        AgentChatBubble(
                            message: AgentChatMessage(
                                role: .assistant,
                                content: streamingResponse
                            )
                        )
                        .id("streaming")
                    } else if isGenerating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 44)
                        .id("loading")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: streamingResponse) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    // MARK: - Starter Suggestions

    private var starterSuggestions: some View {
        VStack(spacing: 12) {
            Text("Or start with an idea:")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StarterButton(
                    icon: "pencil.and.outline",
                    title: "Writing helper",
                    description: "Improve my writing"
                ) {
                    sendInitialMessage("I want an agent that helps me write better - emails, documents, that kind of thing")
                }

                StarterButton(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Code assistant",
                    description: "Review and improve code"
                ) {
                    sendInitialMessage("I need a coding assistant that can review my code and suggest improvements")
                }

                StarterButton(
                    icon: "magnifyingglass",
                    title: "Research helper",
                    description: "Find and summarize info"
                ) {
                    sendInitialMessage("I want an agent that helps me research topics and summarize what it finds")
                }

                StarterButton(
                    icon: "lightbulb",
                    title: "Brainstorm partner",
                    description: "Generate and refine ideas"
                ) {
                    sendInitialMessage("I need an agent that helps me brainstorm and develop ideas")
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Describe what you want your agent to do...", text: $userInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($inputFocused)
                .onSubmit {
                    sendMessage()
                }
                .disabled(isGenerating || !chatService.isReady)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        userInput.isEmpty || isGenerating || !chatService.isReady
                            ? .secondary
                            : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(userInput.isEmpty || isGenerating || !chatService.isReady)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Preview Panel

    private var previewPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preview")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding()
            .background(Color.primary.opacity(0.03))

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(agentDraft.accentColor.gradient)
                            .frame(width: 64, height: 64)

                        if let emoji = agentDraft.emoji {
                            Text(emoji)
                                .font(.largeTitle)
                        } else {
                            Image(systemName: "person.crop.circle")
                                .font(.title)
                                .foregroundStyle(.white)
                        }
                    }

                    VStack(spacing: 4) {
                        Text(agentDraft.name.isEmpty ? "Your Agent" : agentDraft.name)
                            .font(.headline)

                        Text(agentDraft.role.isEmpty ? "Role TBD" : agentDraft.role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !agentDraft.skills.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Skills")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(agentDraft.skills, id: \.self) { skill in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                    Text(skill)
                                        .font(.caption)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if let style = agentDraft.communicationStyle {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left")
                                .font(.caption2)
                            Text(style)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
                .padding()
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func startConversation() {
        guard chatService.isReady else {
            // No model configured - show helpful message
            messages.append(AgentChatMessage(
                role: .assistant,
                content: """
                    Hi! I can help you create a custom agent, but you'll need to configure a model first.

                    Go to **Settings → Models** to set one up, then come back here.
                    """
            ))
            return
        }

        // Generate initial greeting
        Task {
            await generateInitialGreeting()
        }
    }

    private func generateInitialGreeting() async {
        isGenerating = true
        streamingResponse = ""

        let initialPrompt = """
            The user just opened the agent creation dialog. Greet them briefly and ask what kind of agent they'd like to create.
            Keep it short and friendly - one or two sentences max.
            """

        do {
            let stream = chatService.chat(
                prompt: initialPrompt,
                systemPrompt: systemPrompt,
                history: []
            )

            for try await chunk in stream {
                streamingResponse += chunk
            }

            if !streamingResponse.isEmpty {
                messages.append(AgentChatMessage(
                    role: .assistant,
                    content: streamingResponse
                ))
            }
        } catch {
            messages.append(AgentChatMessage(
                role: .assistant,
                content: "Hi! What kind of agent would you like to create? Tell me what you want help with."
            ))
        }

        streamingResponse = ""
        isGenerating = false
    }

    private func sendInitialMessage(_ text: String) {
        userInput = text
        sendMessage()
    }

    private func sendMessage() {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, chatService.isReady else { return }

        messages.append(AgentChatMessage(role: .user, content: text))
        userInput = ""

        // Extract info from the message
        extractAgentInfo(from: text)

        Task {
            await generateResponse(for: text)
        }
    }

    private func generateResponse(for userMessage: String) async {
        isGenerating = true
        streamingResponse = ""

        let history = messages.map { msg in
            ChatMessage(
                content: msg.content,
                isUser: msg.role == .user
            )
        }

        do {
            let stream = chatService.chat(
                prompt: userMessage,
                systemPrompt: systemPrompt,
                history: history
            )

            for try await chunk in stream {
                streamingResponse += chunk
                // Check for agent summary in streaming response
                parseAgentSummary(from: streamingResponse)
            }

            if !streamingResponse.isEmpty {
                messages.append(AgentChatMessage(
                    role: .assistant,
                    content: streamingResponse
                ))
                // Final parse
                parseAgentSummary(from: streamingResponse)
            }
        } catch {
            // Silent fail
        }

        streamingResponse = ""
        isGenerating = false
    }

    private func extractAgentInfo(from text: String) {
        let lowercased = text.lowercased()

        // Detect purpose/role hints
        if lowercased.contains("writ") {
            agentDraft.role = "Writing Assistant"
            agentDraft.emoji = "✍️"
            agentDraft.accentColor = Color.purple
            if !agentDraft.skills.contains("Writing improvement") {
                agentDraft.skills.append("Writing improvement")
            }
        }
        if lowercased.contains("code") || lowercased.contains("programming") {
            agentDraft.role = "Code Assistant"
            agentDraft.emoji = "💻"
            agentDraft.accentColor = Color.green
            if !agentDraft.skills.contains("Code review") {
                agentDraft.skills.append("Code review")
            }
        }
        if lowercased.contains("research") {
            agentDraft.role = "Research Assistant"
            agentDraft.emoji = "🔬"
            agentDraft.accentColor = Color.cyan
            if !agentDraft.skills.contains("Research") {
                agentDraft.skills.append("Research")
            }
        }
        if lowercased.contains("brainstorm") || lowercased.contains("idea") {
            agentDraft.role = "Creative Partner"
            agentDraft.emoji = "💡"
            agentDraft.accentColor = Color.orange
            if !agentDraft.skills.contains("Brainstorming") {
                agentDraft.skills.append("Brainstorming")
            }
        }

        // Communication style hints
        if lowercased.contains("formal") || lowercased.contains("professional") {
            agentDraft.communicationStyle = "Professional"
        }
        if lowercased.contains("casual") || lowercased.contains("friendly") {
            agentDraft.communicationStyle = "Friendly & Casual"
        }
        if lowercased.contains("direct") || lowercased.contains("concise") {
            agentDraft.communicationStyle = "Direct & Concise"
        }

        // Show preview when we have some info
        if !agentDraft.role.isEmpty || !agentDraft.skills.isEmpty {
            showPreview = true
        }
    }

    private func parseAgentSummary(from text: String) {
        // Look for structured summary in model's response
        if text.contains("**Agent Summary**") || text.contains("Agent Summary") {
            canCreate = true

            // Try to extract name
            if let nameMatch = text.range(of: "Name: ([^\n]+)", options: .regularExpression) {
                let nameLine = String(text[nameMatch])
                let name = nameLine.replacingOccurrences(of: "Name: ", with: "")
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !name.isEmpty && name != "Not set" {
                    agentDraft.name = name
                }
            }

            // Try to extract role
            if let roleMatch = text.range(of: "Role: ([^\n]+)", options: .regularExpression) {
                let roleLine = String(text[roleMatch])
                let role = roleLine.replacingOccurrences(of: "Role: ", with: "")
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !role.isEmpty && role != "Not set" {
                    agentDraft.role = role
                }
            }

            // Try to extract skills
            if let skillsMatch = text.range(of: "Skills: ([^\n]+)", options: .regularExpression) {
                let skillsLine = String(text[skillsMatch])
                let skillsStr = skillsLine.replacingOccurrences(of: "Skills: ", with: "")
                    .replacingOccurrences(of: "*", with: "")
                let skills = skillsStr.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if !skills.isEmpty {
                    agentDraft.skills = skills
                }
            }

            // Try to extract style
            if let styleMatch = text.range(of: "Style: ([^\n]+)", options: .regularExpression) {
                let styleLine = String(text[styleMatch])
                let style = styleLine.replacingOccurrences(of: "Style: ", with: "")
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !style.isEmpty {
                    agentDraft.communicationStyle = style
                }
            }

            showPreview = true
        }
    }

    private func createAgent() {
        // Generate a name if we don't have one
        if agentDraft.name.isEmpty {
            agentDraft.name = "Custom Agent"
        }

        // Build system prompt from what we learned
        let systemPromptText = """
            You are \(agentDraft.name), a \(agentDraft.role.isEmpty ? "helpful assistant" : agentDraft.role.lowercased()).

            \(agentDraft.communicationStyle.map { "Communication style: \($0)" } ?? "")

            \(agentDraft.skills.isEmpty ? "" : "Your expertise includes: \(agentDraft.skills.joined(separator: ", "))")

            Be helpful, clear, and focused on the user's needs.
            """

        let template = AgentTemplate(
            id: UUID().uuidString,
            name: agentDraft.name,
            role: agentDraft.role.isEmpty ? "Assistant" : agentDraft.role,
            tagline: "",
            backstory: "",
            skills: agentDraft.skills,
            personality: AgentPersonality(
                trait: agentDraft.communicationStyle ?? "Helpful",
                communicationStyle: .friendly,
                emoji: agentDraft.emoji ?? "🤖"
            ),
            icon: "sparkles",
            accentColor: agentDraft.accentColor,
            category: .productivity,
            systemPrompt: systemPromptText
        )

        let recruitedAgent = RecruitedAgent(
            id: UUID().uuidString,
            name: agentDraft.name,
            templateId: template.id,
            template: template,
            model: "default",
            createdAt: Date()
        )

        appState.recruitedAgents.append(recruitedAgent)
        dismiss()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if !streamingResponse.isEmpty {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let lastId = messages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

// MARK: - Data Models

private struct AgentChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
}

// MARK: - UI Components

private struct AgentChatBubble: View {
    let message: AgentChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser {
                Spacer(minLength: 50)
            }

            if !isUser {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.gradient)
                        .frame(width: 24, height: 24)

                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
            }

            if isUser {
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Markdown(message.content)
                    .markdownTextStyle(\.text) {
                        FontSize(14)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if !isUser {
                Spacer(minLength: 50)
            }
        }
    }
}

private struct StarterButton: View {
    let icon: String
    let title: String
    let description: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(10)
            .background(isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Recruitment Agent Draft

private struct RecruitmentAgentDraft {
    var name = ""
    var role = ""
    var skills: [String] = []
    var emoji: String?
    var accentColor: Color = Color.blue
    var communicationStyle: String?
    var systemPrompt = ""
}

// MARK: - Legacy Support

// Keep RecruitedAgent for compatibility
struct RecruitedAgent: Identifiable, Hashable {
    let id: String
    let name: String
    let templateId: String
    let template: AgentTemplate
    let model: String
    let createdAt: Date

    static func == (lhs: RecruitedAgent, rhs: RecruitedAgent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
