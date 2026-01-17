import AgentKit
import SwiftUI

// MARK: - Agent Builder View

/// A conversational interface for creating custom agents - like ChatGPT's GPT Builder
/// You chat about what you want, and it generates the agent's personality, skills, and system prompt
struct AgentBuilderView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var builder = AgentBuilderState()

    var body: some View {
        HSplitView {
            // Left: Conversation
            conversationPane
                .frame(minWidth: 400)

            // Right: Live preview of the agent being built
            previewPane
                .frame(minWidth: 350, maxWidth: 400)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            builder.startConversation()
        }
    }

    // MARK: - Conversation Pane

    private var conversationPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent Builder")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Tell me about the agent you want to create")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(BuilderPhase.allCases, id: \.self) { phase in
                        Circle()
                            .fill(builder.currentPhase.rawValue >= phase.rawValue
                                  ? Color.accentColor
                                  : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(builder.messages) { message in
                            BuilderMessageBubble(message: message)
                                .id(message.id)
                        }

                        if builder.isThinking {
                            ThinkingIndicator()
                                .id("thinking")
                        }
                    }
                    .padding()
                }
                .onChange(of: builder.messages.count) { _, _ in
                    if let lastId = builder.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: builder.isThinking) { _, isThinking in
                    if isThinking {
                        withAnimation {
                            proxy.scrollTo("thinking", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Suggestion chips (contextual based on phase)
            if !builder.suggestions.isEmpty {
                suggestionChips
            }

            // Input
            inputBar
        }
    }

    // MARK: - Suggestion Chips

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(builder.suggestions, id: \.self) { suggestion in
                    Button(action: {
                        builder.userInput = suggestion
                        builder.sendMessage()
                    }) {
                        Text(suggestion)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Describe your agent...", text: $builder.userInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onSubmit {
                    builder.sendMessage()
                }

            Button(action: { builder.sendMessage() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(builder.userInput.isEmpty ? Color.secondary : Color.accentColor)
            }
            .disabled(builder.userInput.isEmpty || builder.isThinking)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Preview Pane

    private var previewPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preview")
                    .font(.headline)

                Spacer()

                if builder.isComplete {
                    Button(action: createAgent) {
                        Label("Create Agent", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Agent identity
                    agentIdentityCard

                    if !builder.draft.skills.isEmpty {
                        skillsSection
                    }

                    if !builder.draft.systemPrompt.isEmpty {
                        systemPromptSection
                    }

                    if builder.draft.name.isEmpty {
                        emptyPreviewState
                    }
                }
                .padding()
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Agent Identity Card

    private var agentIdentityCard: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(builder.draft.accentColor.gradient)
                    .frame(width: 80, height: 80)

                if let emoji = builder.draft.emoji {
                    Text(emoji)
                        .font(.system(size: 40))
                } else {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            VStack(spacing: 4) {
                Text(builder.draft.name.isEmpty ? "Your Agent" : builder.draft.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(builder.draft.role.isEmpty ? "Role TBD" : builder.draft.role)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !builder.draft.tagline.isEmpty {
                Text("\"\(builder.draft.tagline)\"")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Personality badge
            if let style = builder.draft.communicationStyle {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                    Text(style)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Skills Section

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skills")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(builder.draft.skills, id: \.self) { skill in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(builder.draft.accentColor)
                            .font(.caption)
                        Text(skill)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - System Prompt Section

    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("System Prompt")
                    .font(.headline)

                Spacer()

                Button(action: { builder.showPromptEditor = true }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
            }

            Text(builder.draft.systemPrompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .lineLimit(10)
        }
    }

    // MARK: - Empty State

    private var emptyPreviewState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("Start chatting to build your agent")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func createAgent() {
        // Create the agent from the draft
        let template = AgentTemplate(
            id: UUID().uuidString,
            name: builder.draft.name,
            role: builder.draft.role,
            tagline: builder.draft.tagline,
            backstory: builder.draft.backstory,
            skills: builder.draft.skills,
            personality: AgentPersonality(
                trait: builder.draft.personalityTrait ?? "Helpful",
                communicationStyle: .friendly,
                emoji: builder.draft.emoji ?? "🤖"
            ),
            icon: "sparkles",
            accentColor: builder.draft.accentColor,
            category: .productivity,
            systemPrompt: builder.draft.systemPrompt
        )

        let recruitedAgent = RecruitedAgent(
            id: UUID().uuidString,
            name: builder.draft.name,
            templateId: template.id,
            template: template,
            model: "claude-3-opus",
            createdAt: Date()
        )

        appState.recruitedAgents.append(recruitedAgent)
        dismiss()
    }
}

// MARK: - Builder State

@MainActor
class AgentBuilderState: ObservableObject {
    @Published var messages: [BuilderMessage] = []
    @Published var userInput = ""
    @Published var isThinking = false
    @Published var currentPhase: BuilderPhase = .introduction
    @Published var draft = AgentDraft()
    @Published var suggestions: [String] = []
    @Published var showPromptEditor = false
    @Published var isComplete = false

    func startConversation() {
        let intro = BuilderMessage(
            role: .assistant,
            content: """
            👋 Hi! I'm here to help you create a custom agent.

            Let's start with the basics: **What do you want your agent to help you with?**

            For example:
            • "I want an agent that helps me write better emails"
            • "I need a coding assistant that knows Swift and SwiftUI"
            • "Create a fitness coach that keeps me accountable"
            """
        )
        messages.append(intro)

        suggestions = [
            "Help me write better",
            "Code review assistant",
            "Personal fitness coach",
            "Research helper"
        ]
    }

    func sendMessage() {
        guard !userInput.isEmpty else { return }

        let userMessage = BuilderMessage(role: .user, content: userInput)
        messages.append(userMessage)

        let input = userInput
        userInput = ""
        isThinking = true
        suggestions = []

        // Process the message and generate response
        Task {
            await processUserInput(input)
            isThinking = false
        }
    }

    private func processUserInput(_ input: String) async {
        // Simulate thinking
        try? await Task.sleep(for: .milliseconds(800))

        switch currentPhase {
        case .introduction:
            await handleIntroduction(input)
        case .personality:
            await handlePersonality(input)
        case .skills:
            await handleSkills(input)
        case .refinement:
            await handleRefinement(input)
        case .complete:
            await handleComplete(input)
        }
    }

    private func handleIntroduction(_ input: String) async {
        // Extract initial purpose from input
        draft.purpose = input

        // Infer some initial values
        if input.lowercased().contains("write") || input.lowercased().contains("writing") {
            draft.role = "Writing Assistant"
            draft.emoji = "✍️"
            draft.accentColor = .purple
        } else if input.lowercased().contains("code") || input.lowercased().contains("programming") {
            draft.role = "Code Assistant"
            draft.emoji = "💻"
            draft.accentColor = .green
        } else if input.lowercased().contains("fitness") || input.lowercased().contains("workout") {
            draft.role = "Fitness Coach"
            draft.emoji = "💪"
            draft.accentColor = .orange
        } else if input.lowercased().contains("research") {
            draft.role = "Research Assistant"
            draft.emoji = "🔬"
            draft.accentColor = .cyan
        } else {
            draft.role = "Personal Assistant"
            draft.emoji = "🤖"
            draft.accentColor = .blue
        }

        let response = BuilderMessage(
            role: .assistant,
            content: """
            Great! So you want **\(draft.role.lowercased())** that \(input.lowercased()).

            Now let's give your agent some personality. **How should your agent communicate?**

            Think about:
            • Should they be formal or casual?
            • Encouraging or direct?
            • Brief or detailed?
            """
        )
        messages.append(response)

        suggestions = [
            "Friendly and encouraging",
            "Professional and concise",
            "Casual and fun",
            "Detailed and thorough"
        ]

        currentPhase = .personality
    }

    private func handlePersonality(_ input: String) async {
        // Extract personality from input
        draft.communicationStyle = input
        draft.personalityTrait = input

        let response = BuilderMessage(
            role: .assistant,
            content: """
            Perfect! Your agent will be **\(input.lowercased())**.

            Now let's define their expertise. **What specific skills should your agent have?**

            List the things they should be great at. For a \(draft.role.lowercased()), this might include:
            """
        )
        messages.append(response)

        // Generate skill suggestions based on role
        if draft.role.contains("Writing") {
            suggestions = ["Grammar & style", "Tone adjustment", "Structure & flow", "Concise editing"]
            draft.skills = ["Grammar correction", "Tone adaptation", "Content structuring"]
        } else if draft.role.contains("Code") {
            suggestions = ["Code review", "Bug fixing", "Best practices", "Documentation"]
            draft.skills = ["Code review", "Debugging", "Best practices guidance"]
        } else if draft.role.contains("Fitness") {
            suggestions = ["Workout plans", "Nutrition advice", "Progress tracking", "Motivation"]
            draft.skills = ["Workout planning", "Form guidance", "Progress tracking"]
        } else {
            suggestions = ["Research", "Summarization", "Analysis", "Recommendations"]
            draft.skills = ["Research", "Summarization", "Analysis"]
        }

        currentPhase = .skills
    }

    private func handleSkills(_ input: String) async {
        // Add mentioned skills
        let newSkills = input.components(separatedBy: CharacterSet(charactersIn: ",;."))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if !newSkills.isEmpty {
            draft.skills.append(contentsOf: newSkills)
        }

        // Generate name suggestion
        let nameSuggestion = generateAgentName()
        draft.name = nameSuggestion

        // Generate tagline
        draft.tagline = generateTagline()

        // Generate backstory
        draft.backstory = generateBackstory()

        // Generate system prompt
        draft.systemPrompt = generateSystemPrompt()

        let response = BuilderMessage(
            role: .assistant,
            content: """
            Excellent! I've created a draft of your agent.

            Meet **\(draft.name)** - "\(draft.tagline)"

            Take a look at the preview on the right. You can:
            • **Adjust the name** - just tell me a different one
            • **Refine the personality** - let me know what to change
            • **Edit the system prompt** - click the pencil icon
            • **Create the agent** - when you're happy with it!

            What would you like to change?
            """
        )
        messages.append(response)

        suggestions = [
            "Change the name",
            "Make it more formal",
            "Add more skills",
            "Looks great, create it!"
        ]

        currentPhase = .refinement
        isComplete = true
    }

    private func handleRefinement(_ input: String) async {
        let lowercased = input.lowercased()

        if lowercased.contains("create") || lowercased.contains("looks great") || lowercased.contains("done") {
            let response = BuilderMessage(
                role: .assistant,
                content: """
                🎉 Awesome! Click **"Create Agent"** in the preview panel to bring \(draft.name) to life!

                You can always refine them later through the Agents view.
                """
            )
            messages.append(response)
            currentPhase = .complete
        } else if lowercased.contains("name") {
            let response = BuilderMessage(
                role: .assistant,
                content: "Sure! What would you like to name your agent?"
            )
            messages.append(response)
            suggestions = [generateAgentName(), generateAgentName(), generateAgentName()]
        } else if lowercased.contains("formal") || lowercased.contains("casual") || lowercased.contains("personality") {
            draft.communicationStyle = input
            draft.systemPrompt = generateSystemPrompt()

            let response = BuilderMessage(
                role: .assistant,
                content: "Got it! I've updated the personality. Check the preview - anything else?"
            )
            messages.append(response)
        } else {
            // Treat as a name change or general refinement
            if input.split(separator: " ").count <= 3 && !input.contains("?") {
                draft.name = input
                let response = BuilderMessage(
                    role: .assistant,
                    content: "Great name! **\(input)** it is. Anything else you'd like to adjust?"
                )
                messages.append(response)
            } else {
                // General feedback - regenerate prompt
                draft.systemPrompt = generateSystemPrompt() + "\n\nAdditional instruction: \(input)"
                let response = BuilderMessage(
                    role: .assistant,
                    content: "I've incorporated that feedback into the system prompt. Take a look!"
                )
                messages.append(response)
            }
        }
    }

    private func handleComplete(_ input: String) async {
        let response = BuilderMessage(
            role: .assistant,
            content: "Your agent is ready! Click **Create Agent** whenever you're ready. 🚀"
        )
        messages.append(response)
    }

    // MARK: - Generation Helpers

    private func generateAgentName() -> String {
        let firstNames = ["Alex", "Sam", "Jordan", "Morgan", "Casey", "Riley", "Quinn", "Sage", "Blake", "Drew"]
        let lastNames: [String]

        switch draft.role {
        case let r where r.contains("Writing"):
            lastNames = ["Prose", "Quill", "Words", "Story", "Edit"]
        case let r where r.contains("Code"):
            lastNames = ["Debug", "Stack", "Logic", "Code", "Dev"]
        case let r where r.contains("Fitness"):
            lastNames = ["Strong", "Fit", "Active", "Power", "Motion"]
        case let r where r.contains("Research"):
            lastNames = ["Scholar", "Search", "Insight", "Data", "Learn"]
        default:
            lastNames = ["Helper", "Guide", "Pro", "Assist", "Support"]
        }

        return "\(firstNames.randomElement()!) \(lastNames.randomElement()!)"
    }

    private func generateTagline() -> String {
        let purpose = draft.purpose.lowercased()

        if purpose.contains("write") {
            return "Making your words shine"
        } else if purpose.contains("code") {
            return "Your pair programming partner"
        } else if purpose.contains("fitness") {
            return "Your journey to better health starts here"
        } else if purpose.contains("research") {
            return "Finding answers, faster"
        } else {
            return "Here to help, always"
        }
    }

    private func generateBackstory() -> String {
        return """
        \(draft.name) was created to be your personal \(draft.role.lowercased()). \
        With expertise in \(draft.skills.prefix(3).joined(separator: ", ")), \
        they're ready to help you \(draft.purpose.lowercased()).
        """
    }

    private func generateSystemPrompt() -> String {
        let style = draft.communicationStyle ?? "helpful and friendly"

        return """
        You are \(draft.name), a \(draft.role.lowercased()).

        Your personality: \(style)

        Your expertise includes:
        \(draft.skills.map { "• \($0)" }.joined(separator: "\n"))

        Your purpose: Help the user \(draft.purpose.lowercased())

        Guidelines:
        - Be \(style.lowercased())
        - Focus on being genuinely helpful
        - Ask clarifying questions when needed
        - Provide actionable advice
        - Celebrate progress and wins
        """
    }
}

// MARK: - Builder Phase

enum BuilderPhase: Int, CaseIterable {
    case introduction = 0
    case personality = 1
    case skills = 2
    case refinement = 3
    case complete = 4
}

// MARK: - Agent Draft

struct AgentDraft {
    var name = ""
    var role = ""
    var tagline = ""
    var backstory = ""
    var purpose = ""
    var skills: [String] = []
    var emoji: String?
    var accentColor: Color = .blue
    var communicationStyle: String?
    var personalityTrait: String?
    var systemPrompt = ""
}

// MARK: - Builder Message

struct BuilderMessage: Identifiable {
    let id = UUID()
    let role: MessageSenderRole
    let content: String
    let timestamp = Date()
}

// MARK: - Builder Message Bubble

private struct BuilderMessageBubble: View {
    let message: BuilderMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                // Builder avatar
                ZStack {
                    Circle()
                        .fill(Color.purple.gradient)
                        .frame(width: 32, height: 32)

                    Image(systemName: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(LocalizedStringKey(message.content))
                    .textSelection(.enabled)
                    .padding(12)
                    .background(message.role == .user ? Color.accentColor : Color(.controlBackgroundColor))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            if message.role == .user {
                // User avatar
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - Thinking Indicator

private struct ThinkingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.gradient)
                    .frame(width: 32, height: 32)

                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.white)
            }

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.purple.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .offset(y: animating ? -4 : 4)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(12)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .onAppear { animating = true }
    }
}
