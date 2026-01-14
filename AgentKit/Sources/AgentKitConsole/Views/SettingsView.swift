import AppKit
import SwiftUI

// MARK: - Settings Sidebar Item

struct SettingsSidebarItem: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.body)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 20)

                Text(category.label)
                    .font(.body)
                    .foregroundStyle(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.06) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Settings Categories

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case llm
    case server
    case extensions
    case approvals
    case advanced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "General"
        case .llm: "LLM"
        case .server: "Server"
        case .extensions: "Extensions"
        case .approvals: "Approvals"
        case .advanced: "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .llm: "cpu"
        case .server: "server.rack"
        case .extensions: "puzzlepiece.extension"
        case .approvals: "checkmark.shield"
        case .advanced: "gearshape.2"
        }
    }
}

// MARK: - Settings Detail View (for main content area)

struct SettingsDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCategory: SettingsCategory = .general
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Clean header with title and close button
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .bold))
                    Text(selectedCategory.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Close button (Esc or click)
                Button(action: { appState.selectedSidebarItem = .openSpace }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help("Close Settings (Esc)")
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(.ultraThinMaterial)

            Divider()

            HStack(spacing: 0) {
                // Sidebar navigation
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(SettingsCategory.allCases) { category in
                            SettingsSidebarItem(
                                category: category,
                                isSelected: selectedCategory == category,
                                action: { selectedCategory = category }
                            )
                        }
                    }
                    .padding(12)
                }
                .frame(width: 200)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                // Settings content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        selectedCategoryView
                    }
                    .frame(maxWidth: 700, alignment: .leading)
                    .padding(32)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
            }
        }
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private var selectedCategoryView: some View {
        switch selectedCategory {
        case .general:
            GeneralSettingsContent()
        case .llm:
            LLMSettingsContent()
        case .server:
            ServerSettingsContent()
        case .extensions:
            ExtensionsSettingsContent()
        case .approvals:
            ApprovalSettingsContent()
        case .advanced:
            AdvancedSettingsContent()
        }
    }
}

// MARK: - Settings Card Component

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String?
    @ViewBuilder let content: Content

    init(title: String, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.headline)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}

// MARK: - General Settings

struct GeneralSettingsContent: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Appearance", icon: "paintbrush") {
                VStack(spacing: 12) {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }

                    Toggle("Show in Menu Bar", isOn: $showInMenuBar)
                        .help("Note: Menu bar visibility change requires app restart")

                    Toggle("Show in Dock", isOn: $showInDock)
                        .onChange(of: showInDock) { _, newValue in
                            setShowInDock(newValue)
                        }
                }
            }

            SettingsCard(title: "Notifications", icon: "bell") {
                VStack(spacing: 12) {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                    Toggle("Play Sounds", isOn: $soundEnabled)
                        .disabled(!notificationsEnabled)
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // Use SMAppService for modern macOS login items (macOS 13+)
        // For compatibility, we just store the preference and let the system handle it
        // via Login Items in System Settings → General → Login Items
        // Note: Full implementation would use SMAppService.mainApp.register()/unregister()
        #if DEBUG
        print("Launch at Login set to: \(enabled)")
        #endif
    }

    private func setShowInDock(_ show: Bool) {
        // Change app activation policy
        Task { @MainActor in
            if show {
                NSApp.setActivationPolicy(.regular)
            } else {
                // When hiding from dock, the app becomes an accessory app
                // Only do this if menu bar is enabled, otherwise app becomes invisible
                if showInMenuBar {
                    NSApp.setActivationPolicy(.accessory)
                } else {
                    // Keep in dock if menu bar is also hidden
                    NSApp.setActivationPolicy(.regular)
                }
            }
        }
    }
}

// MARK: - LLM Settings

struct LLMSettingsContent: View {
    @ObservedObject private var serverManager = ServerManager.shared

    @AppStorage("llmProvider") private var llmProvider = "ollama"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("lmStudioURL") private var lmStudioURL = "http://localhost:1234"
    @AppStorage("selectedModel") private var selectedModel = "llama3.2"

    @State private var customModelName = ""
    @State private var isPullingModel = false
    @State private var pullError: String?

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Provider", icon: "cube.box") {
                Picker("Provider", selection: $llmProvider) {
                    Text("Ollama").tag("ollama")
                    Text("LM Studio").tag("lmstudio")
                    Text("Mock (Testing)").tag("mock")
                }
                .pickerStyle(.segmented)
                .onChange(of: llmProvider) { _, _ in
                    Task { await serverManager.refreshOllamaModels() }
                }
            }

            if llmProvider == "ollama" {
                ollamaSettings
            } else if llmProvider == "lmstudio" {
                lmStudioSettings
            } else {
                mockProviderSettings
            }
        }
        .onAppear {
            Task { await serverManager.refreshOllamaModels() }
        }
    }

    @ViewBuilder
    private var ollamaSettings: some View {
        SettingsCard(title: "Connection", icon: "network") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Ollama URL", text: $ollamaURL)
                        .textFieldStyle(.roundedBorder)

                    Button(action: {
                        Task { await serverManager.refreshOllamaModels() }
                    }) {
                        if serverManager.isCheckingOllama {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(serverManager.isCheckingOllama)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(serverManager.ollamaAvailable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(serverManager.ollamaAvailable ? "Connected to Ollama" : "Ollama not available")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !serverManager.ollamaAvailable {
                        Link("Install Ollama", destination: URL(string: "https://ollama.ai")!)
                            .font(.caption)
                    }
                }

                if let error = serverManager.lastOllamaError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(8)
                    .background(.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }

        SettingsCard(title: "Model", icon: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                if serverManager.availableModels.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(serverManager.ollamaAvailable ? "No models detected" : "Connect to Ollama to see models")
                            .foregroundStyle(.secondary)
                            .font(.callout)

                        // Manual model name input when list is empty
                        if serverManager.ollamaAvailable {
                            HStack {
                                TextField("Enter model name (e.g., llama3.2)", text: $selectedModel)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Text("If you have models installed but they're not showing, enter the model name manually")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(serverManager.availableModels) { model in
                            HStack {
                                Text(model.name)
                                Spacer()
                                Text(model.formattedSize)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(model.name)
                        }
                        // Allow custom entry
                        if !serverManager.availableModels.contains(where: { $0.name == selectedModel }) && !selectedModel.isEmpty {
                            Text(selectedModel + " (custom)")
                                .tag(selectedModel)
                        }
                    }

                    // Manual override
                    DisclosureGroup("Use custom model") {
                        HStack {
                            TextField("Model name (e.g., custom:7b)", text: $selectedModel)
                                .textFieldStyle(.roundedBorder)
                        }
                        Text("Enter a model name that's not in the list above")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                }

                if serverManager.ollamaAvailable {
                    Divider()

                    Text("Popular Models")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 6) {
                        ForEach(popularModels, id: \.self) { model in
                            let isInstalled = serverManager.availableModels.contains { $0.name == model }
                            Button(action: {
                                if isInstalled {
                                    selectedModel = model
                                } else {
                                    customModelName = model
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(model)
                                        .font(.caption)
                                    if isInstalled {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }

        SettingsCard(title: "Pull Model", icon: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Model name (e.g., mistral, codellama)", text: $customModelName)
                        .textFieldStyle(.roundedBorder)

                    Button("Pull") {
                        Task { await pullModel(customModelName) }
                    }
                    .disabled(customModelName.isEmpty || isPullingModel)
                    .buttonStyle(.borderedProminent)
                }

                if isPullingModel {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Pulling model...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = pullError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("Downloads from the Ollama registry. May take several minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var lmStudioSettings: some View {
        SettingsCard(title: "Connection", icon: "network") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("LM Studio URL", text: $lmStudioURL)
                    .textFieldStyle(.roundedBorder)

                Text("Ensure a model is loaded in LM Studio before connecting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        SettingsCard(title: "Model", icon: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Model Name", text: $selectedModel)
                    .textFieldStyle(.roundedBorder)

                Text("Enter the model identifier as shown in LM Studio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var mockProviderSettings: some View {
        SettingsCard(title: "Testing Mode", icon: "testtube.2") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Mock provider enabled", systemImage: "info.circle")
                    .foregroundStyle(.orange)

                Text("Returns canned responses for testing the UI without a real LLM.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var popularModels: [String] {
        ["llama3.2", "llama3.2:1b", "mistral", "codellama", "qwen2.5-coder", "deepseek-coder", "phi3"]
    }

    private func pullModel(_ name: String) async {
        isPullingModel = true
        pullError = nil

        do {
            try await serverManager.pullModel(name)
            selectedModel = name
            customModelName = ""
        } catch {
            pullError = error.localizedDescription
        }

        isPullingModel = false
    }
}

// MARK: - Server Settings

struct ServerSettingsContent: View {
    @ObservedObject private var serverManager = ServerManager.shared

    @AppStorage("localAgentPort") private var localPort = 8080
    @AppStorage("localAgentHost") private var localHost = "127.0.0.1"
    @AppStorage("dataDirectory") private var dataDirectory = "~/AgentKit"
    @AppStorage("autoConnectLocal") private var autoConnectLocal = true
    @AppStorage("enableBonjour") private var enableBonjour = true

    @State private var isStarting = false
    @State private var showLogs = false

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Status", icon: "circle.fill") {
                HStack {
                    Circle()
                        .fill(serverManager.isRunning ? .green : .gray)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(serverManager.isRunning ? "Server Running" : "Server Stopped")
                            .fontWeight(.medium)

                        if let pid = serverManager.serverPID {
                            Text("PID: \(pid)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if serverManager.isRunning {
                        Link(destination: serverManager.serverURL) {
                            Label("Open", systemImage: "arrow.up.forward.square")
                        }
                        .font(.caption)
                    }
                }

                if let error = serverManager.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                    }
                    .padding(.top, 8)
                }
            }

            SettingsCard(title: "Controls", icon: "play.circle") {
                HStack(spacing: 12) {
                    Button(action: { Task { await startServer() } }) {
                        HStack {
                            if isStarting {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text("Start")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(serverManager.isRunning || isStarting)

                    Button(action: { serverManager.stopServer() }) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!serverManager.isRunning)

                    Spacer()

                    Button(action: { showLogs.toggle() }) {
                        Label("Logs", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                }
            }

            SettingsCard(title: "Configuration", icon: "slider.horizontal.3") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Host")
                            .frame(width: 100, alignment: .leading)
                        TextField("Host", text: $localHost)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Port")
                            .frame(width: 100, alignment: .leading)
                        Stepper("\(localPort)", value: $localPort, in: 1024...65535)
                    }

                    HStack {
                        Text("Data Directory")
                            .frame(width: 100, alignment: .leading)
                        TextField("Path", text: $dataDirectory)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    Toggle("Auto-start on Launch", isOn: $autoConnectLocal)
                }
            }

            SettingsCard(title: "Network Discovery", icon: "network") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Bonjour Discovery", isOn: $enableBonjour)

                    if enableBonjour {
                        Text("Discover other agents on your local network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showLogs) {
            ServerLogsView()
        }
    }

    private func startServer() async {
        isStarting = true
        defer { isStarting = false }

        do {
            try await serverManager.startServer()
        } catch {
            // Error is displayed via serverManager.lastError
        }
    }
}

// MARK: - Server Logs View

struct ServerLogsView: View {
    @ObservedObject private var serverManager = ServerManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Server Logs")
                    .font(.headline)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if serverManager.serverOutput.isEmpty {
                ContentUnavailableView(
                    "No Logs",
                    systemImage: "doc.text",
                    description: Text("Logs appear when the server is running")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(serverManager.serverOutput.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(logLineColor(line))
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 700, height: 500)
    }

    private func logLineColor(_ line: String) -> Color {
        if line.contains("error") || line.contains("ERROR") {
            return .red
        } else if line.contains("warning") || line.contains("WARN") {
            return .orange
        } else if line.contains("debug") || line.contains("DEBUG") {
            return .secondary
        }
        return .primary
    }
}

// MARK: - Extensions Settings

struct ExtensionsSettingsContent: View {
    @State private var extensions: [ExtensionItem] = ExtensionItem.builtInExtensions
    @State private var searchText = ""
    @State private var selectedCategory: ExtensionCategoryFilter = .all
    @State private var isDiscovering = false

    var filteredExtensions: [ExtensionItem] {
        var result = extensions

        // Filter by category
        if selectedCategory != .all {
            result = result.filter { $0.category == selectedCategory.rawValue }
        }

        // Filter by search
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 16) {
            // Discovery banner
            SettingsCard(title: "Discover Extensions", icon: "magnifyingglass") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Find and enable tools that agents can use, including Shortcuts, AppIntents, and MCP servers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(action: { Task { await discoverExtensions() } }) {
                            HStack {
                                if isDiscovering {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                Text("Discover Available Extensions")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDiscovering)

                        Spacer()
                    }
                }
            }

            // Search and filter
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search extensions...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Picker("Category", selection: $selectedCategory) {
                    ForEach(ExtensionCategoryFilter.allCases) { category in
                        Text(category.label).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }

            // Extensions list
            SettingsCard(title: "Available Extensions", icon: "puzzlepiece.extension") {
                if filteredExtensions.isEmpty {
                    ContentUnavailableView(
                        "No Extensions Found",
                        systemImage: "puzzlepiece.extension",
                        description: Text("Try discovering extensions or change your filter")
                    )
                    .frame(height: 150)
                } else {
                    VStack(spacing: 0) {
                        ForEach($extensions.filter { ext in
                            let matches = filteredExtensions.contains { $0.id == ext.wrappedValue.id }
                            return matches
                        }) { $item in
                            ExtensionRow(item: $item)
                            if item.id != filteredExtensions.last?.id {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
            }

            // System integrations info
            SettingsCard(title: "System Integrations", icon: "apple.logo") {
                VStack(alignment: .leading, spacing: 8) {
                    SystemIntegrationRow(
                        name: "Calendar & Reminders",
                        icon: "calendar",
                        status: .available,
                        description: "Access via EventKit"
                    )
                    Divider()
                    SystemIntegrationRow(
                        name: "Safari Reading List",
                        icon: "book",
                        status: .available,
                        description: "Auto-import to RAG"
                    )
                    Divider()
                    SystemIntegrationRow(
                        name: "Shared with You",
                        icon: "person.2",
                        status: .requiresPermission,
                        description: "Requires macOS 13+"
                    )
                    Divider()
                    SystemIntegrationRow(
                        name: "Shortcuts",
                        icon: "bolt.circle",
                        status: .available,
                        description: "Run any Shortcut"
                    )
                }
            }
        }
    }

    private func discoverExtensions() async {
        isDiscovering = true

        // Discover real shortcuts using the shortcuts CLI
        let discoveredShortcuts = await discoverShortcuts()

        // Add only new ones
        for shortcut in discoveredShortcuts {
            if !extensions.contains(where: { $0.id == shortcut.id }) {
                extensions.append(shortcut)
            }
        }

        isDiscovering = false
    }

    /// Discover user's Shortcuts using the macOS shortcuts CLI
    private func discoverShortcuts() async -> [ExtensionItem] {
        let shortcutsPath = "/usr/bin/shortcuts"

        guard FileManager.default.fileExists(atPath: shortcutsPath) else {
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shortcutsPath)
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            // Parse shortcut names (one per line)
            let shortcutNames = output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            return shortcutNames.map { name in
                ExtensionItem(
                    id: "shortcut.\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
                    name: name,
                    description: "User Shortcut",
                    category: "shortcuts",
                    icon: "bolt.circle.fill",
                    isEnabled: false,
                    source: .shortcuts
                )
            }
        } catch {
            print("Failed to discover shortcuts: \(error)")
            return []
        }
    }
}

// MARK: - Extension Item Model

struct ExtensionItem: Identifiable {
    let id: String
    let name: String
    let description: String
    let category: String
    let icon: String
    var isEnabled: Bool
    let source: ExtensionSource
    var requiresApproval: Bool = false

    enum ExtensionSource {
        case builtIn
        case shortcuts
        case mcp
        case appIntents
    }

    static let builtInExtensions: [ExtensionItem] = [
        ExtensionItem(
            id: "goldeneye.calendar",
            name: "Calendar",
            description: "Create events, check availability, manage calendars",
            category: "calendar",
            icon: "calendar",
            isEnabled: true,
            source: .builtIn
        ),
        ExtensionItem(
            id: "goldeneye.reminders",
            name: "Reminders",
            description: "Create and manage tasks and reminders",
            category: "tasks",
            icon: "checklist",
            isEnabled: true,
            source: .builtIn
        ),
        ExtensionItem(
            id: "goldeneye.reading-list",
            name: "Reading List",
            description: "Import and search Safari Reading List items",
            category: "documents",
            icon: "book",
            isEnabled: true,
            source: .builtIn
        ),
        ExtensionItem(
            id: "goldeneye.filesystem",
            name: "File System",
            description: "Read and write files (with approval)",
            category: "files",
            icon: "folder",
            isEnabled: true,
            source: .builtIn,
            requiresApproval: true
        ),
        ExtensionItem(
            id: "goldeneye.git",
            name: "Git",
            description: "Repository operations, commits, branches",
            category: "development",
            icon: "arrow.triangle.branch",
            isEnabled: true,
            source: .builtIn
        ),
        ExtensionItem(
            id: "goldeneye.shell",
            name: "Shell Commands",
            description: "Execute terminal commands (requires approval)",
            category: "system",
            icon: "terminal",
            isEnabled: false,
            source: .builtIn,
            requiresApproval: true
        ),
        ExtensionItem(
            id: "goldeneye.web",
            name: "Web Fetch",
            description: "Fetch and parse web content",
            category: "other",
            icon: "globe",
            isEnabled: true,
            source: .builtIn
        ),
        ExtensionItem(
            id: "goldeneye.memory",
            name: "Memory (RAG)",
            description: "Semantic search across all your content",
            category: "other",
            icon: "brain",
            isEnabled: true,
            source: .builtIn
        )
    ]
}

// MARK: - Extension Row

struct ExtensionRow: View {
    @Binding var item: ExtensionItem

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: item.icon)
                .font(.title2)
                .foregroundStyle(item.isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .fontWeight(.medium)

                    if item.requiresApproval {
                        Image(systemName: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if item.source == .shortcuts {
                        Text("SHORTCUT")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Toggle
            Toggle("", isOn: $item.isEnabled)
                .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - System Integration Row

struct SystemIntegrationRow: View {
    let name: String
    let icon: String
    let status: IntegrationStatus
    let description: String

    enum IntegrationStatus {
        case available
        case requiresPermission
        case unavailable
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status badge
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch status {
        case .available: return .green
        case .requiresPermission: return .orange
        case .unavailable: return .gray
        }
    }

    private var statusLabel: String {
        switch status {
        case .available: return "Available"
        case .requiresPermission: return "Needs Permission"
        case .unavailable: return "Unavailable"
        }
    }
}

// MARK: - Extension Category Filter

enum ExtensionCategoryFilter: String, CaseIterable, Identifiable {
    case all
    case calendar
    case tasks
    case communication
    case documents
    case files
    case development
    case system
    case shortcuts
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .calendar: return "Calendar"
        case .tasks: return "Tasks"
        case .communication: return "Communication"
        case .documents: return "Documents"
        case .files: return "Files"
        case .development: return "Development"
        case .system: return "System"
        case .shortcuts: return "Shortcuts"
        case .other: return "Other"
        }
    }
}

// MARK: - Approval Settings

struct ApprovalSettingsContent: View {
    @AppStorage("defaultApprovalTimeout") private var defaultTimeout = 300
    @AppStorage("autoApproveRead") private var autoApproveRead = true
    @AppStorage("autoApproveGlob") private var autoApproveGlob = true
    @AppStorage("autoApproveGrep") private var autoApproveGrep = true
    @AppStorage("requireApprovalForWrite") private var requireWrite = true
    @AppStorage("requireApprovalForBash") private var requireBash = true

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Timeout", icon: "clock") {
                Picker("Default Timeout", selection: $defaultTimeout) {
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("1 hour").tag(3600)
                    Text("Never").tag(0)
                }
            }

            SettingsCard(title: "Auto-Approve (Low Risk)", icon: "checkmark.circle") {
                VStack(spacing: 12) {
                    Toggle("Read (file reading)", isOn: $autoApproveRead)
                    Toggle("Glob (file search)", isOn: $autoApproveGlob)
                    Toggle("Grep (content search)", isOn: $autoApproveGrep)
                }
            }

            SettingsCard(title: "Require Approval (High Risk)", icon: "exclamationmark.shield") {
                VStack(spacing: 12) {
                    Toggle("Write (file modification)", isOn: $requireWrite)
                    Toggle("Bash (shell commands)", isOn: $requireBash)
                }
            }
        }
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsContent: View {
    @AppStorage("logLevel") private var logLevel = "info"
    @AppStorage("enableTelemetry") private var enableTelemetry = false
    @AppStorage("gitAutoCommit") private var gitAutoCommit = true
    @State private var showResetConfirmation = false
    @State private var showExportPanel = false
    @State private var showImportPanel = false

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Logging", icon: "doc.plaintext") {
                Picker("Log Level", selection: $logLevel) {
                    Text("Trace").tag("trace")
                    Text("Debug").tag("debug")
                    Text("Info").tag("info")
                    Text("Warning").tag("warning")
                    Text("Error").tag("error")
                }
            }

            SettingsCard(title: "Git Integration", icon: "arrow.triangle.branch") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto-commit Tool Executions", isOn: $gitAutoCommit)

                    Text("Each tool execution creates a git commit in the session repository")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "Privacy", icon: "hand.raised") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Anonymous Telemetry", isOn: $enableTelemetry)

                    Text("Help improve AgentKit by sending anonymous usage data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "Data", icon: "cylinder") {
                VStack(spacing: 12) {
                    Button("Reset All Settings", role: .destructive) {
                        showResetConfirmation = true
                    }

                    HStack(spacing: 12) {
                        Button("Export Configuration...") {
                            exportConfiguration()
                        }

                        Button("Import Configuration...") {
                            importConfiguration()
                        }
                    }
                }
            }
        }
        .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetAllSettings()
            }
        } message: {
            Text("This will reset all settings to their default values. This action cannot be undone.")
        }
    }

    // MARK: - Actions

    private func resetAllSettings() {
        // Reset all AppStorage values
        UserDefaults.standard.removeObject(forKey: "logLevel")
        UserDefaults.standard.removeObject(forKey: "enableTelemetry")
        UserDefaults.standard.removeObject(forKey: "gitAutoCommit")
        UserDefaults.standard.removeObject(forKey: "llmProvider")
        UserDefaults.standard.removeObject(forKey: "ollamaURL")
        UserDefaults.standard.removeObject(forKey: "selectedModel")
        UserDefaults.standard.removeObject(forKey: "localAgentPort")
        UserDefaults.standard.removeObject(forKey: "localAgentHost")
        UserDefaults.standard.removeObject(forKey: "dataDirectory")
        UserDefaults.standard.removeObject(forKey: "autoConnectLocal")
        // Refresh UI
        logLevel = "info"
        enableTelemetry = false
        gitAutoCommit = true
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "agentkit-config.json"
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            var config: [String: Any] = [:]
            config["logLevel"] = UserDefaults.standard.string(forKey: "logLevel") ?? "info"
            config["llmProvider"] = UserDefaults.standard.string(forKey: "llmProvider") ?? "ollama"
            config["ollamaURL"] = UserDefaults.standard.string(forKey: "ollamaURL") ?? "http://localhost:11434"
            config["selectedModel"] = UserDefaults.standard.string(forKey: "selectedModel") ?? "llama3.2"
            config["localAgentPort"] = UserDefaults.standard.integer(forKey: "localAgentPort")
            config["localAgentHost"] = UserDefaults.standard.string(forKey: "localAgentHost") ?? "127.0.0.1"

            if let data = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted) {
                try? data.write(to: url)
            }
        }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.urls.first,
           let data = try? Data(contentsOf: url),
           let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            if let value = config["logLevel"] as? String {
                UserDefaults.standard.set(value, forKey: "logLevel")
                logLevel = value
            }
            if let value = config["llmProvider"] as? String {
                UserDefaults.standard.set(value, forKey: "llmProvider")
            }
            if let value = config["ollamaURL"] as? String {
                UserDefaults.standard.set(value, forKey: "ollamaURL")
            }
            if let value = config["selectedModel"] as? String {
                UserDefaults.standard.set(value, forKey: "selectedModel")
            }
            if let value = config["localAgentPort"] as? Int {
                UserDefaults.standard.set(value, forKey: "localAgentPort")
            }
            if let value = config["localAgentHost"] as? String {
                UserDefaults.standard.set(value, forKey: "localAgentHost")
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))

            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX + size.width)
            currentX += size.width + spacing
        }

        totalHeight = currentY + lineHeight

        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}

// MARK: - Settings Window (for ⌘, Preferences)

struct SettingsView: View {
    var body: some View {
        TabView {
            ScrollView {
                GeneralSettingsContent()
                    .padding()
            }
            .tabItem {
                Label("General", systemImage: "gear")
            }
            .tag(SettingsCategory.general)

            ScrollView {
                LLMSettingsContent()
                    .padding()
            }
            .tabItem {
                Label("LLM", systemImage: "cpu")
            }
            .tag(SettingsCategory.llm)

            ScrollView {
                ServerSettingsContent()
                    .padding()
            }
            .tabItem {
                Label("Server", systemImage: "server.rack")
            }
            .tag(SettingsCategory.server)

            ScrollView {
                ExtensionsSettingsContent()
                    .padding()
            }
            .tabItem {
                Label("Extensions", systemImage: "puzzlepiece.extension")
            }
            .tag(SettingsCategory.extensions)

            ScrollView {
                ApprovalSettingsContent()
                    .padding()
            }
            .tabItem {
                Label("Approvals", systemImage: "checkmark.shield")
            }
            .tag(SettingsCategory.approvals)

            ScrollView {
                AdvancedSettingsContent()
                    .padding()
            }
            .tabItem {
                Label("Advanced", systemImage: "gearshape.2")
            }
            .tag(SettingsCategory.advanced)
        }
        .frame(width: 550, height: 450)
    }
}
