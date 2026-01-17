import AgentKit
import SwiftUI

// MARK: - Coaching View

struct CoachingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedDomain: CoachingDomain?

    var body: some View {
        HSplitView {
            // Sessions list
            coachingList
                .frame(minWidth: 250, maxWidth: 350)

            // Selected session or domain picker
            if let selectedId = appState.selectedCoachingSessionId,
               let session = appState.workspace.coachingSessions.first(where: { $0.id == selectedId }) {
                CoachingSessionDetailView(session: session)
            } else {
                CoachingDomainPicker()
            }
        }
        .navigationTitle("Coaching")
        .toolbar {
            ToolbarItem {
                Button(action: { appState.showNewCoachingSheet = true }) {
                    Label("New Session", systemImage: "plus")
                }
            }
        }
    }

    private var coachingList: some View {
        List(selection: $appState.selectedCoachingSessionId) {
            // Active sessions
            if !appState.workspace.activeCoachingSessions.isEmpty {
                Section("Active Sessions") {
                    ForEach(appState.workspace.activeCoachingSessions) { session in
                        CoachingSessionRow(session: session)
                            .tag(session.id)
                    }
                }
            }

            // Past sessions by domain
            ForEach(CoachingDomain.allCases.filter { domain in
                appState.workspace.coachingSessions.contains { $0.domain == domain && !$0.isActive }
            }, id: \.self) { domain in
                Section(domain.displayName) {
                    ForEach(appState.workspace.coachingSessions.filter { $0.domain == domain && !$0.isActive }) { session in
                        CoachingSessionRow(session: session)
                            .tag(session.id)
                    }
                }
            }

            if appState.workspace.coachingSessions.isEmpty {
                Section {
                    Text("No coaching sessions yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Coaching Session Row

struct CoachingSessionRow: View {
    let session: CoachingSession

    var body: some View {
        HStack(spacing: 12) {
            // Domain icon
            Image(systemName: session.domain.icon)
                .font(.title2)
                .foregroundStyle(domainColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(1)

                    if session.isActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                    }
                }

                HStack(spacing: 8) {
                    // Phase indicator
                    Label(session.phase.displayName, systemImage: session.phase.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Duration
                    Text(formatDuration(session.duration))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let goal = session.goal {
                    Text(goal)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var domainColor: Color {
        switch session.domain.color {
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "yellow": return .yellow
        case "pink": return .pink
        case "green": return .green
        case "teal": return .teal
        default: return .gray
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
}

// MARK: - Coaching Domain Picker

struct CoachingDomainPicker: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Start a Coaching Session")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Choose a domain to begin your personalized coaching experience")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200))], spacing: 16) {
                    ForEach(CoachingDomain.allCases.filter { $0 != .custom }, id: \.self) { domain in
                        CoachingDomainCard(domain: domain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Coaching Domain Card

struct CoachingDomainCard: View {
    let domain: CoachingDomain
    @EnvironmentObject private var appState: AppState
    @State private var isHovering = false

    var body: some View {
        Button(action: { startSession() }) {
            VStack(spacing: 12) {
                Image(systemName: domain.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(domainColor)

                Text(domain.displayName)
                    .font(.headline)

                Text(domainDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovering ? domainColor : Color.secondary.opacity(0.2), lineWidth: isHovering ? 2 : 1)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var domainColor: Color {
        switch domain.color {
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "yellow": return .yellow
        case "pink": return .pink
        case "green": return .green
        case "teal": return .teal
        default: return .gray
        }
    }

    private var domainDescription: String {
        switch domain {
        case .career: return "Job search, interviews, career growth"
        case .fitness: return "Workouts, form, motivation"
        case .writing: return "Style, editing, creative writing"
        case .skills: return "Learn any skill with structure"
        case .wellness: return "Mental health, stress, habits"
        case .finance: return "Budgeting, investing, planning"
        case .language: return "Language learning practice"
        case .custom: return "Define your own coaching area"
        }
    }

    private func startSession() {
        let session = CoachingSession(
            title: "\(domain.displayName) Session",
            domain: domain
        )
        appState.workspace.coachingSessions.insert(session, at: 0)
        appState.selectedCoachingSessionId = session.id
    }
}

// MARK: - Coaching Session Detail View

struct CoachingSessionDetailView: View {
    let session: CoachingSession
    @EnvironmentObject private var appState: AppState
    @State private var newMessage = ""
    @State private var isLoading = false
    @State private var showAddNoteAlert = false
    @State private var noteText = ""

    var body: some View {
        HSplitView {
            // Main conversation area
            VStack(spacing: 0) {
                // Header
                sessionHeader

                Divider()

                // Messages
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(session.messages) { message in
                            ThreadMessageBubble(message: message)
                        }

                        if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Coach is thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding()
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
                }
                .padding()
                .background(Color(.controlBackgroundColor))
            }

            // Session sidebar
            sessionSidebar
                .frame(width: 250)
        }
    }

    private var sessionHeader: some View {
        HStack {
            Image(systemName: session.domain.icon)
                .font(.title2)
                .foregroundStyle(domainColor)

            VStack(alignment: .leading) {
                Text(session.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    Label(session.phase.displayName, systemImage: session.phase.icon)
                    if session.isActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Active")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Phase controls
            Button(action: { advancePhase() }) {
                Label("Next Phase", systemImage: "arrow.right")
            }
            .disabled(!session.isActive)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }

    private var sessionSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Goals
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session Goals")
                        .font(.headline)

                    if let goal = session.goal {
                        Text(goal)
                            .font(.body)
                    } else {
                        Text("No goal set")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Phase progress
                VStack(alignment: .leading, spacing: 8) {
                    Text("Progress")
                        .font(.headline)

                    ForEach(CoachingPhase.allCases, id: \.self) { phase in
                        HStack {
                            Image(systemName: phase == session.phase ? "circle.fill" : (phaseIsComplete(phase) ? "checkmark.circle.fill" : "circle"))
                                .foregroundStyle(phase == session.phase ? Color.accentColor : (phaseIsComplete(phase) ? Color.green : Color.secondary))

                            Text(phase.displayName)
                                .fontWeight(phase == session.phase ? .semibold : .regular)
                        }
                        .font(.subheadline)
                    }
                }

                Divider()

                // Notes
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Notes")
                            .font(.headline)
                        Spacer()
                        Button(action: { showAddNoteAlert = true }) {
                            Image(systemName: "plus")
                        }
                        .help("Add note")
                    }

                    if session.notes.isEmpty {
                        Text("No notes yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.notes) { note in
                            Text(note.content)
                                .font(.caption)
                                .padding(8)
                                .background(Color(.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.windowBackgroundColor))
        .alert("Add Note", isPresented: $showAddNoteAlert) {
            TextField("Note", text: $noteText, axis: .vertical)
                .lineLimit(3...6)
            Button("Cancel", role: .cancel) {
                noteText = ""
            }
            Button("Add") {
                addNote()
            }
            .disabled(noteText.isEmpty)
        } message: {
            Text("Add a personal note about this coaching session.")
        }
    }

    private var domainColor: Color {
        switch session.domain.color {
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "yellow": return .yellow
        case "pink": return .pink
        case "green": return .green
        case "teal": return .teal
        default: return .gray
        }
    }

    private func phaseIsComplete(_ phase: CoachingPhase) -> Bool {
        // Simple check: phases before current are complete
        let phases = CoachingPhase.allCases
        guard let currentIndex = phases.firstIndex(of: session.phase),
              let checkIndex = phases.firstIndex(of: phase) else { return false }
        return checkIndex < currentIndex
    }

    private func advancePhase() {
        if let index = appState.workspace.coachingSessions.firstIndex(where: { $0.id == session.id }) {
            appState.workspace.coachingSessions[index].phase = session.phase.next
        }
    }

    private func addNote() {
        guard !noteText.isEmpty else { return }

        let note = CoachingNote(
            id: UUID(),
            content: noteText,
            type: .general
        )

        if let index = appState.workspace.coachingSessions.firstIndex(where: { $0.id == session.id }) {
            appState.workspace.coachingSessions[index].notes.append(note)
            appState.workspace.coachingSessions[index].updatedAt = Date()
        }

        noteText = ""
    }

    private func sendMessage() {
        guard !newMessage.isEmpty else { return }

        let userMessage = AgentKit.ThreadMessage.user(newMessage)

        if let index = appState.workspace.coachingSessions.firstIndex(where: { $0.id == session.id }) {
            appState.workspace.coachingSessions[index].messages.append(userMessage)
            appState.workspace.coachingSessions[index].updatedAt = Date()
        }

        let messageContent = newMessage
        newMessage = ""
        isLoading = true

        // Get real coaching response from LLM
        Task {
            // Build context from previous messages
            let previousMessages = session.messages.map { msg in
                "\(msg.role == .user ? "User" : "Coach"): \(msg.textContent)"
            }.joined(separator: "\n\n")

            let systemPrompt = """
            You are a supportive and insightful \(session.domain.displayName) coach. \
            Your goal is to help the user achieve: \(session.goal ?? "personal growth in \(session.domain.displayName.lowercased())")

            Be empathetic, ask thoughtful questions, and provide actionable advice. \
            Keep responses focused and under 200 words unless more detail is needed.
            """

            let prompt = """
            \(systemPrompt)

            Previous conversation:
            \(previousMessages.isEmpty ? "(This is the start of the conversation)" : previousMessages)

            User: \(messageContent)

            Coach:
            """

            var responseContent: String
            if let response = await appState.sendAgentMessage(prompt) {
                responseContent = response
            } else {
                // Fallback if no LLM available
                responseContent = "I'd love to help you with your \(session.domain.displayName.lowercased()) goals. Could you tell me more about what specific aspect you'd like to focus on today?"
            }

            let response = AgentKit.ThreadMessage.assistant(responseContent)

            if let index = appState.workspace.coachingSessions.firstIndex(where: { $0.id == session.id }) {
                appState.workspace.coachingSessions[index].messages.append(response)
            }

            isLoading = false
        }
    }
}

// MARK: - New Coaching Sheet

struct NewCoachingSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDomain: CoachingDomain = .career
    @State private var goal = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("New Coaching Session")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Domain")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Domain", selection: $selectedDomain) {
                    ForEach(CoachingDomain.allCases.filter { $0 != .custom }, id: \.self) { domain in
                        Label(domain.displayName, systemImage: domain.icon)
                            .tag(domain)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Goal (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("What would you like to achieve?", text: $goal)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Start Session") {
                    createSession()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func createSession() {
        let session = CoachingSession(
            title: "\(selectedDomain.displayName) Session",
            domain: selectedDomain,
            goal: goal.isEmpty ? nil : goal
        )
        appState.workspace.coachingSessions.insert(session, at: 0)
        appState.selectedCoachingSessionId = session.id
        dismiss()
    }
}
