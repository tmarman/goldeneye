import MarkdownUI
import SwiftUI

// MARK: - Onboarding View

/// Onboarding dialog with real LLM conversation and background indexing
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState
    @Environment(ChatService.self) private var chatService
    @ObservedObject private var aboutMeService = AboutMeService.shared

    // Chat state
    @State private var messages: [OnboardingChatMessage] = []
    @State private var userInput: String = ""
    @State private var isGenerating = false
    @State private var streamingResponse = ""
    @FocusState private var inputFocused: Bool

    // Onboarding state
    @State private var hasStarted = false
    @State private var canDismiss = false

    // System prompt for the onboarding conversation
    private var systemPrompt: String {
        """
        You are Envoy, a friendly AI assistant helping a new user set up their personal workspace.

        This is the first-time onboarding experience. Your goals:
        1. Welcome them warmly and introduce yourself
        2. Learn about them through natural conversation - their name, what they do, how they work
        3. Explain what's happening in the background (indexing their files, learning their patterns)
        4. Keep them engaged while setup completes

        Guidelines:
        - Be conversational, warm, and concise (2-3 sentences per response)
        - Ask one question at a time
        - Show genuine interest in their answers
        - Occasionally mention what you're learning/indexing in the background
        - When they share info, acknowledge it naturally before asking the next thing
        - After a few exchanges, let them know they can start exploring whenever they're ready

        Current indexing status: \(aboutMeService.indexingStatus)
        Indexing progress: \(Int(aboutMeService.indexingProgress * 100))%
        \(aboutMeService.isIndexing ? "Indexing is running in the background." : "")

        You're running locally on their Mac - everything stays private on their device.
        """
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with indexing status
            headerView

            Divider()

            // Chat area
            chatArea

            Divider()

            // Input area
            inputArea
        }
        .frame(width: 500, height: 520)
        .onAppear {
            if !hasStarted {
                startOnboarding()
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // Envoy icon with subtle animation during indexing
            ZStack {
                Image("EnvoyIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                if aboutMeService.isIndexing {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 44, height: 44)

                    Circle()
                        .trim(from: 0, to: aboutMeService.indexingProgress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: aboutMeService.indexingProgress)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Setting up Envoy")
                    .font(.headline)

                if aboutMeService.isIndexing {
                    Text(aboutMeService.indexingStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if aboutMeService.indexingProgress >= 1.0 {
                    Text("Ready to explore!")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text(chatService.isReady ? chatService.providerDescription : "Chat with Envoy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Dismiss button (appears after initial exchange)
            if canDismiss {
                Button(action: completeOnboarding) {
                    Text("Get Started")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
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
                        OnboardingBubble(message: message)
                            .id(message.id)
                    }

                    // Streaming response
                    if isGenerating && !streamingResponse.isEmpty {
                        OnboardingBubble(
                            message: OnboardingChatMessage(
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

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Say something...", text: $userInput, axis: .vertical)
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

    // MARK: - Actions

    private func startOnboarding() {
        hasStarted = true

        // Start indexing in background
        if !aboutMeService.isIndexing {
            Task {
                await aboutMeService.startIndexing(appState: appState)
            }
        }

        // Try to auto-configure a model if none is ready
        Task {
            await autoConfigureModelIfNeeded()
        }
    }

    /// Try to auto-configure Apple Foundation Models or find an available provider
    private func autoConfigureModelIfNeeded() async {
        // If already ready, start the conversation
        if chatService.isReady {
            await generateInitialGreeting()
            return
        }

        let providerManager = ProviderConfigManager.shared

        // First, try Apple Foundation Models (AFM) - zero config needed
        if let afmProvider = providerManager.providers.first(where: { $0.type == .appleFoundation }) {
            let status = providerManager.providerStatus[afmProvider.id]
            if case .available = status {
                do {
                    try await chatService.selectProvider(afmProvider)
                    await generateInitialGreeting()
                    return
                } catch {
                    print("Failed to select AFM: \(error)")
                }
            }
        }

        // Second, try Ollama if it's running
        if let ollamaProvider = providerManager.providers.first(where: { $0.type == .ollama }) {
            let status = providerManager.providerStatus[ollamaProvider.id]
            if case .available = status {
                do {
                    try await chatService.selectProvider(ollamaProvider)
                    await generateInitialGreeting()
                    return
                } catch {
                    print("Failed to select Ollama: \(error)")
                }
            }
        }

        // No model available - show static welcome with setup guidance
        await MainActor.run {
            messages.append(OnboardingChatMessage(
                role: .assistant,
                content: """
                    Hi! I'm **Envoy**, your personal AI workspace.

                    I'm setting things up in the background - scanning your files and learning your patterns. This helps me give you personalized suggestions later.

                    **To enable AI chat, you have a few options:**

                    🍎 **Apple Intelligence** (Recommended)
                    If you're on macOS 26+, Apple Intelligence works instantly with no setup.

                    🦙 **Ollama** (Local & Free)
                    Install [Ollama](https://ollama.com) and run a model like `llama3.2`.

                    ☁️ **Cloud Providers**
                    Add your API key for Anthropic, OpenAI, or others in Settings.

                    Click **Get Started** to explore, and configure models anytime in **Settings → Providers**.
                    """
            ))
            canDismiss = true
        }
    }

    private func generateInitialGreeting() async {
        isGenerating = true
        streamingResponse = ""

        // The model generates the greeting based on the system prompt
        let initialPrompt = """
            The user just opened Envoy for the first time. Greet them warmly and start getting to know them.
            Mention that you're setting things up in the background while you chat.
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
                messages.append(OnboardingChatMessage(
                    role: .assistant,
                    content: streamingResponse
                ))
            }
        } catch {
            messages.append(OnboardingChatMessage(
                role: .assistant,
                content: "Hi! I'm Envoy, your personal AI workspace. I'm setting up in the background. Feel free to tell me about yourself - what kind of work do you do?"
            ))
        }

        streamingResponse = ""
        isGenerating = false

        // Allow dismissal after first message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            canDismiss = true
        }
    }

    private func sendMessage() {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, chatService.isReady else { return }

        // Add user message
        messages.append(OnboardingChatMessage(role: .user, content: text))
        userInput = ""

        // Extract profile info from the message
        extractAndSaveProfileInfo(from: text)

        // Generate response
        Task {
            await generateResponse(for: text)
        }
    }

    private func generateResponse(for userMessage: String) async {
        isGenerating = true
        streamingResponse = ""

        // Build history
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
            }

            if !streamingResponse.isEmpty {
                messages.append(OnboardingChatMessage(
                    role: .assistant,
                    content: streamingResponse
                ))
            }
        } catch {
            // Silent fail - just stop generating
        }

        streamingResponse = ""
        isGenerating = false
    }

    private func extractAndSaveProfileInfo(from text: String) {
        let lowercased = text.lowercased()

        // Extract name
        let namePatterns = ["i'm ", "im ", "i am ", "my name is ", "call me ", "name's "]
        for pattern in namePatterns {
            if let range = lowercased.range(of: pattern) {
                let afterPattern = text[range.upperBound...]
                let words = afterPattern.split(separator: " ")
                if let firstName = words.first {
                    let name = String(firstName).trimmingCharacters(in: .punctuationCharacters)
                    if name.count > 1 && name.count < 20 {
                        UserDefaults.standard.set(name.capitalized, forKey: "userName")
                        break
                    }
                }
            }
        }

        // Extract role keywords
        let roleKeywords: [(String, String)] = [
            ("engineer", "Engineering"), ("developer", "Engineering"), ("programmer", "Engineering"),
            ("design", "Product/Design"), ("product", "Product/Design"),
            ("research", "Research"), ("scientist", "Research"),
            ("writ", "Writing"), ("content", "Writing"),
            ("business", "Business"), ("strateg", "Business")
        ]
        for (keyword, role) in roleKeywords {
            if lowercased.contains(keyword) {
                UserDefaults.standard.set(role, forKey: "userRole")
                break
            }
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        withAnimation {
            isPresented = false
        }

        // Note: Indexing continues in background even after dismissal
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

struct OnboardingChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String

    enum MessageRole {
        case user
        case assistant
    }
}

// MARK: - UI Components

struct OnboardingBubble: View {
    let message: OnboardingChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser {
                Spacer(minLength: 50)
            }

            if !isUser {
                Image("EnvoyIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
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

// MARK: - AboutMeService Extension

extension AboutMeService {
    static let shared = AboutMeService()
}

// MARK: - Preview

#Preview {
    OnboardingView(isPresented: .constant(true))
        .environmentObject(AppState.shared)
        .environment(ChatService.shared)
}
