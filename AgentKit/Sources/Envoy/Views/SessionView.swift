import AgentKit
import SwiftUI

// MARK: - Session View

/// Displays a CLI session with live terminal output and interaction controls
struct SessionView: View {
    let session: CLISession
    let onClose: () -> Void

    @State private var outputText: AttributedString = ""
    @State private var inputText: String = ""
    @State private var sessionInfo: SessionInfo?
    @State private var isConnected = true
    @State private var scrollProxy: ScrollViewProxy?

    // Terminal styling
    private let terminalFont = Font.system(.body, design: .monospaced)
    private let terminalBackground = Color.black
    private let terminalForeground = Color.green

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Terminal output
            terminalOutput

            Divider()

            // Input area (for interactive sessions)
            if sessionInfo?.status == .running {
                inputArea
            }

            // Status bar
            statusBar
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            await loadSessionInfo()
            await streamOutput()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .foregroundStyle(.green)

                    Text(sessionInfo?.cli.displayName ?? "CLI Session")
                        .font(.headline)

                    statusBadge
                }

                if let info = sessionInfo {
                    Text("Task: \(info.taskId.prefix(8))...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Control buttons
            HStack(spacing: 12) {
                if sessionInfo?.status == .running {
                    Button(action: sendInterrupt) {
                        Label("Interrupt", systemImage: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (color, text) = statusInfo
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var statusInfo: (Color, String) {
        guard let status = sessionInfo?.status else {
            return (.gray, "Unknown")
        }

        switch status {
        case .pending:
            return (.orange, "Pending")
        case .running:
            return (.green, "Running")
        case .completed:
            return (.blue, "Completed")
        case .failed:
            return (.red, "Failed")
        case .terminated:
            return (.gray, "Terminated")
        }
    }

    // MARK: - Terminal Output

    private var terminalOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(outputText)
                    .font(terminalFont)
                    .foregroundStyle(terminalForeground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .id("output")
            }
            .background(terminalBackground)
            .onChange(of: outputText) { _, _ in
                // Auto-scroll to bottom
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("output", anchor: .bottom)
                }
            }
            .onAppear {
                scrollProxy = proxy
            }
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(terminalFont)
                .foregroundStyle(.green)

            TextField("Enter command...", text: $inputText)
                .font(terminalFont)
                .textFieldStyle(.plain)
                .onSubmit {
                    Task { await sendInput() }
                }

            Button("Send") {
                Task { await sendInput() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputText.isEmpty)

            // Control character buttons
            HStack(spacing: 4) {
                controlButton("C", character: .c, tooltip: "Ctrl+C (Interrupt)")
                controlButton("D", character: .d, tooltip: "Ctrl+D (EOF)")
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }

    private func controlButton(_ label: String, character: ControlCharacter, tooltip: String) -> some View {
        Button {
            Task { await sendControl(character) }
        } label: {
            Text("^" + label)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .help(tooltip)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if let info = sessionInfo {
                // Output size
                Label(formatBytes(info.outputSize), systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Duration
                if let exitCode = info.exitCode {
                    Label("Exit: \(exitCode)", systemImage: exitCode == 0 ? "checkmark.circle" : "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(exitCode == 0 ? .green : .red)
                } else {
                    // Running duration
                    Text(formatDuration(since: info.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
    }

    // MARK: - Actions

    private func loadSessionInfo() async {
        sessionInfo = await session.getInfo()
    }

    private func streamOutput() async {
        // Get initial buffer
        let buffer = await session.getOutputBuffer()
        if !buffer.isEmpty, let text = String(data: buffer, encoding: .utf8) {
            outputText = AttributedString(text)
        }

        // Stream new output
        for await output in await session.outputStream() {
            switch output.type {
            case .stdout, .stderr:
                if let data = output.data,
                   let text = String(data: data, encoding: .utf8) {
                    outputText += AttributedString(text)
                }

            case .exit(let code):
                let exitMessage = "\n\n[Process exited with code \(code)]\n"
                outputText += AttributedString(exitMessage)
                await loadSessionInfo()

            case .terminated:
                outputText += AttributedString("\n\n[Session terminated]\n")
                isConnected = false
                await loadSessionInfo()
            }
        }
    }

    private func sendInput() async {
        guard !inputText.isEmpty else { return }
        let text = inputText + "\n"
        inputText = ""

        do {
            try await session.sendInput(text)
        } catch {
            outputText += AttributedString("\n[Error sending input: \(error.localizedDescription)]\n")
        }
    }

    private func sendControl(_ character: ControlCharacter) async {
        do {
            try await session.sendControl(character)
        } catch {
            outputText += AttributedString("\n[Error sending control: \(error.localizedDescription)]\n")
        }
    }

    private func sendInterrupt() {
        Task {
            await sendControl(.c)
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatDuration(since date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Session List View

/// Shows all active sessions across devices
struct SessionListView: View {
    @State private var sessions: [DeviceSession] = []
    @State private var selectedSession: CLISession?
    @State private var isLoading = true

    var body: some View {
        NavigationSplitView {
            // Session list
            List(selection: Binding(
                get: { selectedSession?.id },
                set: { id in
                    // Would need to fetch session by ID
                }
            )) {
                if sessions.isEmpty && !isLoading {
                    Text("No active sessions")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { deviceSession in
                        SessionRowView(session: deviceSession)
                            .tag(deviceSession.id)
                    }
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem {
                    Button(action: refresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        } detail: {
            if let session = selectedSession {
                SessionView(session: session, onClose: { selectedSession = nil })
            } else {
                ContentUnavailableView(
                    "Select a Session",
                    systemImage: "terminal",
                    description: Text("Choose a session from the list to view its output")
                )
            }
        }
        .task {
            await loadSessions()
        }
    }

    private func loadSessions() async {
        isLoading = true
        sessions = await SessionManager.shared.listAllSessions()
        isLoading = false
    }

    private func refresh() {
        Task {
            await loadSessions()
        }
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: DeviceSession

    var body: some View {
        HStack(spacing: 12) {
            // CLI icon
            Image(systemName: session.info.cli.icon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.info.cli.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if !session.isLocal {
                        Label(session.deviceName, systemImage: "desktopcomputer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Task: \(session.info.taskId.prefix(8))...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch session.info.status {
        case .running: return .green
        case .completed: return .blue
        case .failed: return .red
        case .pending: return .orange
        case .terminated: return .gray
        }
    }
}
