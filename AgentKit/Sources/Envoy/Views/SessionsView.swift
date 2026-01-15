import AgentKit
import SwiftUI

// MARK: - Sessions View

/// View for managing CLI agent sessions across local and remote devices
struct SessionsView: View {
    @State private var sessions: [DeviceSession] = []
    @State private var selectedSessionId: String?
    @State private var isLoading = true
    @State private var showingConnectSheet = false
    @State private var deviceFilter: DeviceFilter = .all

    enum DeviceFilter: String, CaseIterable {
        case all = "All Devices"
        case local = "This Mac"
        case remote = "Remote"
    }

    var filteredSessions: [DeviceSession] {
        switch deviceFilter {
        case .all: return sessions
        case .local: return sessions.filter { $0.isLocal }
        case .remote: return sessions.filter { !$0.isLocal }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let sessionId = selectedSessionId,
               let session = sessions.first(where: { $0.id == sessionId }) {
                CLISessionDetailView(session: session)
            } else {
                emptyState
            }
        }
        .task {
            await loadSessions()
        }
        .sheet(isPresented: $showingConnectSheet) {
            ConnectRemoteSheet()
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Filter and actions
            HStack(spacing: 8) {
                Picker("Device", selection: $deviceFilter) {
                    ForEach(DeviceFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button {
                    showingConnectSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help("Connect to remote device")
            }
            .padding()

            Divider()

            // Session list
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSessions.isEmpty {
                emptySessionsList
            } else {
                List(selection: $selectedSessionId) {
                    ForEach(groupedSessions, id: \.device) { group in
                        Section(header: deviceHeader(group.device, group.deviceName)) {
                            ForEach(group.sessions) { session in
                                CLISessionRow(session: session)
                                    .tag(session.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Sessions")
        .frame(minWidth: 280)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadSessions() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var groupedSessions: [(device: String, deviceName: String, sessions: [DeviceSession])] {
        let grouped = Dictionary(grouping: filteredSessions) { $0.deviceId }
        return grouped.map { (device: $0.key, deviceName: $0.value.first?.deviceName ?? "Unknown", sessions: $0.value) }
            .sorted { $0.deviceName < $1.deviceName }
    }

    @ViewBuilder
    private func deviceHeader(_ deviceId: String, _ deviceName: String) -> some View {
        HStack {
            Image(systemName: sessions.first(where: { $0.deviceId == deviceId })?.isLocal == true
                  ? "laptopcomputer" : "desktopcomputer")
                .foregroundStyle(.secondary)
            Text(deviceName)
            Spacer()
            if sessions.first(where: { $0.deviceId == deviceId })?.isLocal == false {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }
        }
    }

    @ViewBuilder
    private var emptySessionsList: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Sessions")
                .font(.headline)

            Text("Start a CLI agent task to create a session, or connect to a remote device")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Select a Session")
                .font(.headline)

            Text("Choose a session to view its output and interact with the agent")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadSessions() async {
        isLoading = true

        // Load from SessionManager - no mock data
        let allSessions = await SessionManager.shared.listAllSessions()
        sessions = allSessions
        isLoading = false
    }

    private func mockSessions() -> [DeviceSession] {
        [
            DeviceSession(
                info: SessionInfo(
                    id: "session-1",
                    taskId: "task-abc",
                    cli: .claudeCode,
                    status: .running,
                    createdAt: Date().addingTimeInterval(-1800),
                    outputSize: 15420,
                    exitCode: nil
                ),
                deviceId: "local-device",
                deviceName: "Tim's MacBook Pro",
                isLocal: true
            ),
            DeviceSession(
                info: SessionInfo(
                    id: "session-2",
                    taskId: "task-def",
                    cli: .claudeCode,
                    status: .completed,
                    createdAt: Date().addingTimeInterval(-86400),
                    outputSize: 45230,
                    exitCode: 0
                ),
                deviceId: "local-device",
                deviceName: "Tim's MacBook Pro",
                isLocal: true
            ),
            DeviceSession(
                info: SessionInfo(
                    id: "session-3",
                    taskId: "task-ghi",
                    cli: .claudeCode,
                    status: .running,
                    createdAt: Date().addingTimeInterval(-3600),
                    outputSize: 8920,
                    exitCode: nil
                ),
                deviceId: "home-mac",
                deviceName: "Home Mac Studio",
                isLocal: false
            )
        ]
    }
}

// MARK: - CLI Session Row

struct CLISessionRow: View {
    let session: DeviceSession

    var body: some View {
        HStack(spacing: 12) {
            // CLI icon
            Image(systemName: session.info.cli.icon)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.info.taskId.prefix(8))
                        .fontWeight(.medium)
                        .fontDesign(.monospaced)

                    if session.info.status == .running {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    }
                }

                HStack(spacing: 8) {
                    Text(session.info.cli.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text(session.info.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Status badge
            CLISessionStatusBadge(status: session.info.status)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch session.info.status {
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .pending: return .orange
        case .terminated: return .gray
        }
    }
}

// MARK: - Status Badge

struct CLISessionStatusBadge: View {
    let status: SessionStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.15))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .pending: return .orange
        case .terminated: return .gray
        }
    }
}

// MARK: - CLI Session Detail View

struct CLISessionDetailView: View {
    let session: DeviceSession
    @State private var outputText: String = ""
    @State private var inputText: String = ""
    @State private var isStreaming = false
    @State private var scrollToBottom = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sessionHeader

            Divider()

            // Terminal output
            terminalView

            // Input bar (for interactive sessions)
            if session.info.status == .running {
                inputBar
            }
        }
        .task {
            await loadOutput()
        }
    }

    @ViewBuilder
    private var sessionHeader: some View {
        HStack(spacing: 16) {
            // CLI info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: session.info.cli.icon)
                        .foregroundStyle(.secondary)
                    Text(session.info.cli.displayName)
                        .font(.headline)

                    CLISessionStatusBadge(status: session.info.status)
                }

                HStack(spacing: 12) {
                    Label(session.info.taskId, systemImage: "number")
                        .font(.caption)
                        .fontDesign(.monospaced)

                    Label(session.deviceName, systemImage: session.isLocal ? "laptopcomputer" : "desktopcomputer")
                        .font(.caption)

                    if !session.isLocal {
                        Text("Remote")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.purple.opacity(0.2))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                if session.info.status == .running {
                    Button {
                        // Send Ctrl+C
                    } label: {
                        Label("Interrupt", systemImage: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                Button {
                    // Copy output
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(outputText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Menu {
                    Button("View in Terminal") {
                        // Open in native Terminal
                    }
                    Button("Export Output...") {
                        // Save to file
                    }
                    Divider()
                    Button("Kill Session", role: .destructive) {
                        // Force kill
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.background)
    }

    @ViewBuilder
    private var terminalView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(outputText.isEmpty ? "Waiting for output..." : outputText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
                    .id("output-bottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: outputText) { _, _ in
                if scrollToBottom {
                    withAnimation {
                        proxy.scrollTo("output-bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.caption)

            TextField("Send input to session...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    sendInput()
                }

            Button("Send") {
                sendInput()
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputText.isEmpty)

            // Control characters
            Menu {
                Button("Ctrl+C (Interrupt)") {
                    // Send interrupt
                }
                Button("Ctrl+D (EOF)") {
                    // Send EOF
                }
                Button("Ctrl+L (Clear)") {
                    // Send clear
                }
            } label: {
                Image(systemName: "keyboard")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.background)
    }

    private func loadOutput() async {
        // Mock output for development
        outputText = """
        \u{001B}[36m╭─────────────────────────────────────────────╮\u{001B}[0m
        \u{001B}[36m│\u{001B}[0m  \u{001B}[1m\u{001B}[35mClaude Code\u{001B}[0m                                \u{001B}[36m│\u{001B}[0m
        \u{001B}[36m╰─────────────────────────────────────────────╯\u{001B}[0m

        \u{001B}[90m>\u{001B}[0m Reading file: \u{001B}[33mPackage.swift\u{001B}[0m
        \u{001B}[90m>\u{001B}[0m Analyzing project structure...

        I'll help you implement the CLI Runner Agent. Let me start by
        examining the existing codebase structure.

        \u{001B}[32m✓\u{001B}[0m Found AgentKit module
        \u{001B}[32m✓\u{001B}[0m Found existing Review system
        \u{001B}[32m✓\u{001B}[0m Found A2A protocol implementation

        \u{001B}[90m>\u{001B}[0m Creating new files...

        \u{001B}[36m┌─ CLIRunnerTypes.swift ─────────────────────────┐\u{001B}[0m
        \u{001B}[36m│\u{001B}[0m public enum CLIType: String, Codable {        \u{001B}[36m│\u{001B}[0m
        \u{001B}[36m│\u{001B}[0m     case claudeCode = "claude-code"           \u{001B}[36m│\u{001B}[0m
        \u{001B}[36m│\u{001B}[0m     case codex = "codex"                      \u{001B}[36m│\u{001B}[0m
        \u{001B}[36m│\u{001B}[0m     case geminiCLI = "gemini-cli"             \u{001B}[36m│\u{001B}[0m
        \u{001B}[36m│\u{001B}[0m }                                             \u{001B}[36m│\u{001B}[0m
        \u{001B}[36m└─────────────────────────────────────────────────┘\u{001B}[0m

        """

        // In real implementation, would stream from CLISession
        if session.info.status == .running {
            // Start streaming
            isStreaming = true
        }
    }

    private func sendInput() {
        guard !inputText.isEmpty else { return }
        // Would send to CLISession
        outputText += "\n> \(inputText)\n"
        inputText = ""
    }
}

// MARK: - Connect Remote Sheet

struct ConnectRemoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host: String = ""
    @State private var port: String = "8080"
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Connect to Remote Device")
                    .font(.headline)

                Text("Enter the address of a device running AgentKit Console")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Form
            Form {
                TextField("Host", text: $host, prompt: Text("192.168.1.100 or hostname.local"))

                TextField("Port", text: $port)
                    .frame(width: 100)

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Connect") {
                    connect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.isEmpty || isConnecting)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil

        Task {
            do {
                let portNum = Int(port) ?? 8080
                _ = try await SessionManager.shared.connectToRemote(host: host, port: portNum)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }
}

// MARK: - Legacy Support Types

struct SessionListItem: Identifiable, Hashable {
    let id: String
    let name: String?
    let createdAt: Date
    let taskCount: Int
    let isActive: Bool
}
