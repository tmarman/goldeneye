import AgentKit
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
    case models
    case server
    case extensions
    case integrations
    case approvals
    case systemHealth
    case advanced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "General"
        case .models: "Models"
        case .server: "Server"
        case .extensions: "Extensions"
        case .integrations: "Integrations"
        case .approvals: "Approvals"
        case .systemHealth: "System Health"
        case .advanced: "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .models: "cube.box"
        case .server: "server.rack"
        case .extensions: "puzzlepiece.extension"
        case .integrations: "link"
        case .approvals: "checkmark.shield"
        case .systemHealth: "heart.text.square"
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
        content
            .onAppear {
                // Navigate to target category if set
                if let target = appState.targetSettingsCategory,
                   let category = SettingsCategory(rawValue: target) {
                    selectedCategory = category
                    appState.targetSettingsCategory = nil
                }
            }
    }

    private var content: some View {
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
                Button(action: { appState.selectedSidebarItem = .headspace }) {
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
        case .models:
            ModelsSettingsContent()
        case .server:
            ServerSettingsContent()
        case .extensions:
            ExtensionsSettingsContent()
        case .integrations:
            IntegrationsSettingsContent()
        case .approvals:
            ApprovalSettingsContent()
        case .systemHealth:
            SystemHealthView()
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
    @EnvironmentObject private var appState: AppState
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

            SettingsCard(title: "Getting Started", icon: "sparkles") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("View the onboarding guide to learn about Envoy's features.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(action: { appState.showOnboarding = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                            Text("Show Onboarding")
                        }
                    }
                    .buttonStyle(.borderedProminent)
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

// MARK: - Models Settings

/// Unified models settings - everything inline, no popups
struct ModelsSettingsContent: View {
    @State private var selectedSection: ModelsSection = .providers
    @State private var editingProvider: ProviderConfig?
    @State private var showAddOllamaServer = false
    @State private var showImportHuggingFace = false

    enum ModelsSection: String, CaseIterable {
        case providers = "Providers"
        case onDevice = "On-Device (MLX)"

        var icon: String {
            switch self {
            case .providers: return "server.rack"
            case .onDevice: return "apple.logo"
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Section tabs
            HStack(spacing: 8) {
                ForEach(ModelsSection.allCases, id: \.self) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.rawValue, systemImage: section.icon)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedSection == section ? Color.accentColor : Color.secondary.opacity(0.1))
                            )
                            .foregroundStyle(selectedSection == section ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Import from HuggingFace button (for MLX)
                if selectedSection == .onDevice {
                    Button(action: { showImportHuggingFace = true }) {
                        Label("Import from HuggingFace", systemImage: "square.and.arrow.down")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            // Content based on section
            switch selectedSection {
            case .providers:
                ProvidersSettingsSection(
                    editingProvider: $editingProvider,
                    showAddOllamaServer: $showAddOllamaServer
                )
            case .onDevice:
                OnDeviceModelsSection(showImportHuggingFace: $showImportHuggingFace)
            }
        }
        .sheet(item: $editingProvider) { provider in
            ProviderEditSheet(provider: provider)
        }
        .sheet(isPresented: $showAddOllamaServer) {
            AddOllamaServerSheet()
        }
        .sheet(isPresented: $showImportHuggingFace) {
            HuggingFaceImportSheet()
        }
    }
}

// MARK: - Providers Settings Section

struct ProvidersSettingsSection: View {
    @Binding var editingProvider: ProviderConfig?
    @Binding var showAddOllamaServer: Bool

    /// Access the shared provider manager
    private var providerManager: ProviderConfigManager { ProviderConfigManager.shared }

    /// Extract model count from provider status
    private func modelCount(for provider: ProviderConfig) -> Int? {
        if case .available(let count) = providerManager.providerStatus[provider.id] {
            return count
        }
        return nil
    }

    /// Available providers that are enabled and have models
    private var availableProviders: [ProviderConfig] {
        providerManager.providers.filter { provider in
            guard provider.isEnabled else { return false }
            if case .available = providerManager.providerStatus[provider.id] {
                return true
            }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Default Orchestrator Model - shown when providers are available
            if !availableProviders.isEmpty {
                DefaultModelSection(availableProviders: availableProviders)
            }

            // Configured providers from real ProviderConfigManager
            SettingsCard(title: "Configured Providers", icon: "checkmark.circle") {
                VStack(spacing: 0) {
                    if providerManager.providers.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "cpu")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                                Text("No providers configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            Spacer()
                        }
                    } else {
                        ForEach(Array(providerManager.providers.enumerated()), id: \.element.id) { index, provider in
                            ProviderSettingsRow(
                                name: provider.name,
                                icon: provider.type.icon,
                                iconColor: provider.type.color,
                                subtitle: provider.type.description,
                                modelCount: modelCount(for: provider),
                                isEnabled: provider.isEnabled,
                                selectedModel: provider.selectedModel,
                                onConfigure: {
                                    editingProvider = provider
                                }
                            )

                            if index < providerManager.providers.count - 1 {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                }
            }
            .task {
                // Check provider status on appear
                await providerManager.checkAllProviders()
            }

            // Add more providers
            SettingsCard(title: "Add Provider", icon: "plus.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect to additional AI services")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                        AddProviderButton(name: "Google AI", icon: "globe", color: .blue)
                        AddProviderButton(name: "OpenRouter", icon: "arrow.triangle.branch", color: .purple)
                        AddProviderButton(name: "Custom", icon: "server.rack", color: .gray)

                        // Special: Add another Ollama instance
                        Button(action: { showAddOllamaServer = true }) {
                            VStack(spacing: 6) {
                                Image(systemName: "plus.circle")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                Text("Add Ollama")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .help("Add another Ollama server (local or remote)")
                    }
                }
            }

            // Ollama note
            SettingsCard(title: "About Ollama", icon: "info.circle") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ollama servers expose all their models. You can add multiple Ollama providers to:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Use different models from the same server", systemImage: "checkmark")
                        Label("Connect to remote Ollama servers", systemImage: "checkmark")
                        Label("Separate work and personal models", systemImage: "checkmark")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Default Model Section

/// Section for selecting the default orchestrator model
struct DefaultModelSection: View {
    let availableProviders: [ProviderConfig]
    @Environment(ChatService.self) private var chatService
    @AppStorage("defaultProviderId") private var defaultProviderId: String = ""

    var body: some View {
        SettingsCard(title: "Default Model", icon: "star.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("This model will be used for new conversations and the onboarding experience.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Default Provider", selection: $defaultProviderId) {
                    Text("Auto (first available)").tag("")
                    ForEach(availableProviders) { provider in
                        HStack {
                            Image(systemName: provider.type.icon)
                            Text(provider.name)
                            if let model = provider.selectedModel {
                                Text("(\(model))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(provider.id.uuidString)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: defaultProviderId) { _, newValue in
                    Task {
                        await selectDefaultProvider(id: newValue)
                    }
                }

                // Current status
                HStack {
                    if chatService.isReady {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Using: \(chatService.providerDescription)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                        Text("No model selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func selectDefaultProvider(id: String) async {
        if id.isEmpty {
            // Auto-select first available
            if let first = availableProviders.first {
                try? await chatService.selectProvider(first)
            }
        } else if let provider = availableProviders.first(where: { $0.id.uuidString == id }) {
            try? await chatService.selectProvider(provider)
        }
    }
}

// MARK: - Provider Settings Row

struct ProviderSettingsRow: View {
    let name: String
    let icon: String
    let iconColor: Color
    let subtitle: String
    var modelCount: Int? = nil
    var isEnabled: Bool = true
    var selectedModel: String? = nil
    var onConfigure: (() -> Void)? = nil

    @State private var enabled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(name)
                        .fontWeight(.medium)

                    if let count = modelCount, count > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("\(count) models")
                                .font(.caption)
                        }
                        .foregroundStyle(.green)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let model = selectedModel {
                    Text("Model: \(model)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Configure menu before toggle for consistent alignment
            if onConfigure != nil {
                Menu {
                    Button("Configure") { onConfigure?() }
                    Button("Check Status") { }
                    Divider()
                    Button("Remove", role: .destructive) { }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
            }

            Toggle("", isOn: $enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 10)
        .onAppear { enabled = isEnabled }
    }
}

// MARK: - Add Provider Button

struct AddProviderButton: View {
    let name: String
    let icon: String
    let color: Color

    var body: some View {
        Button(action: { /* Add provider */ }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(name)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Ollama Server Sheet

struct AddOllamaServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var serverName = ""
    @State private var serverURL = "http://localhost:11434"
    @State private var isChecking = false
    @State private var availableModels: [String] = []
    @State private var selectedModel = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Ollama Server")
                .font(.headline)

            Form {
                Section("Server Details") {
                    TextField("Name (e.g., 'Work Ollama')", text: $serverName)
                    TextField("Server URL", text: $serverURL)
                }

                Section("Connection") {
                    if isChecking {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Checking connection...")
                        }
                    } else if !availableModels.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("\(availableModels.count) models available")
                        }

                        Picker("Default Model", selection: $selectedModel) {
                            Text("None").tag("")
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    } else {
                        Button("Test Connection") {
                            Task { await checkConnection() }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Add Server") {
                    // Add the server
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(serverName.isEmpty || availableModels.isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 400)
    }

    private func checkConnection() async {
        isChecking = true
        defer { isChecking = false }

        // Simulate checking - in production, call Ollama API
        try? await Task.sleep(for: .seconds(1))
        availableModels = ["llama3.2:latest", "qwen2.5:7b", "codellama:latest", "mistral:latest"]
        if !availableModels.isEmpty {
            selectedModel = availableModels.first ?? ""
        }
    }
}

// MARK: - On-Device Models Section

struct OnDeviceModelsSection: View {
    @Binding var showImportHuggingFace: Bool

    /// Calculate actual storage used by models
    private var modelsStorageSize: String {
        let modelsPath = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Envoy/Models")

        guard FileManager.default.fileExists(atPath: modelsPath.path) else {
            return "0 MB"
        }

        var totalSize: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: modelsPath,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }

    var body: some View {
        VStack(spacing: 16) {
            // System info banner
            systemInfoBanner

            // Installed models
            SettingsCard(title: "Installed Models", icon: "checkmark.circle.fill") {
                VStack(spacing: 0) {
                    if modelsStorageSize == "0 MB" || modelsStorageSize == "Zero KB" {
                        // No models installed
                        HStack {
                            Image(systemName: "tray")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No models installed")
                                    .font(.subheadline)
                                Text("Download a model below to get started")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        // Show actual storage as placeholder until we have model enumeration
                        InstalledModelRow(
                            name: "Local Models",
                            size: modelsStorageSize,
                            isRecommended: false
                        )
                    }
                }
            }

            // Browse more models
            SettingsCard(title: "Download Models", icon: "arrow.down.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Download AI models to run locally on your Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Model family cards
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                        ModelFamilyCard(
                            name: "Qwen 2.5",
                            provider: "Alibaba",
                            description: "Versatile multilingual model",
                            modelCount: 4,
                            tags: ["Chat", "Code"]
                        )

                        ModelFamilyCard(
                            name: "Llama 3.2",
                            provider: "Meta",
                            description: "Fast and capable",
                            modelCount: 3,
                            tags: ["Chat"]
                        )

                        ModelFamilyCard(
                            name: "DeepSeek Coder",
                            provider: "DeepSeek",
                            description: "Optimized for coding",
                            modelCount: 2,
                            tags: ["Code"]
                        )

                        ModelFamilyCard(
                            name: "Vision Models",
                            provider: "Various",
                            description: "Image understanding",
                            modelCount: 3,
                            tags: ["Vision"]
                        )
                    }

                    // Import custom
                    Button(action: { showImportHuggingFace = true }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Import from HuggingFace...")
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Storage info
            SettingsCard(title: "Storage", icon: "externaldrive") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(modelsStorageSize) used")
                            .font(.subheadline.weight(.medium))
                        Text("Models stored in ~/Library/Application Support/Envoy/Models")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Show in Finder") {
                        let modelsPath = FileManager.default.urls(
                            for: .applicationSupportDirectory,
                            in: .userDomainMask
                        ).first!.appendingPathComponent("Envoy/Models")
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: modelsPath.path)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var systemInfoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "memorychip")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(systemRecommendation)
                    .font(.subheadline)

                Text("Models marked with ✓ are optimized for your system")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
    }

    private var systemRecommendation: String {
        let ram = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        if ram >= 64 {
            return "Your Mac has \(ram)GB RAM - you can run large models (70B+)"
        } else if ram >= 32 {
            return "Your Mac has \(ram)GB RAM - recommended models up to 32B"
        } else if ram >= 16 {
            return "Your Mac has \(ram)GB RAM - recommended models up to 8B"
        } else {
            return "Your Mac has \(ram)GB RAM - recommended models up to 4B"
        }
    }
}

// MARK: - Installed Model Row

struct InstalledModelRow: View {
    let name: String
    let size: String
    var isRecommended: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.box.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .fontWeight(.medium)

                    if isRecommended {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }

                Text(size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("Use as Default") { }
                Divider()
                Button("Delete", role: .destructive) { }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Model Family Card

struct ModelFamilyCard: View {
    let name: String
    let provider: String
    let description: String
    let modelCount: Int
    let tags: [String]

    @State private var isHovered = false

    var body: some View {
        Button(action: { /* Show model family details */ }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.headline)
                        Text("by \(provider)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(modelCount)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Provider Edit Sheet

struct ProviderEditSheet: View {
    let provider: ProviderConfig
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var isEnabled: Bool = true
    @State private var apiKey: String = ""
    @State private var serverURL: String = ""
    @State private var selectedModel: String = ""
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus = .unknown

    enum ConnectionStatus {
        case unknown, success, failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configure \(provider.type.rawValue)")
                        .font(.headline)
                    Text(provider.type.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Button("Save") { saveChanges() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Provider icon and status
                    HStack(spacing: 16) {
                        Image(systemName: provider.type.icon)
                            .font(.largeTitle)
                            .foregroundStyle(provider.type.color)
                            .frame(width: 48, height: 48)
                            .background(provider.type.color.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Provider Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .font(.headline)

                            Toggle("Enabled", isOn: $isEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }

                    Divider()

                    // Connection settings (for providers that need them)
                    if provider.type.requiresServerURL {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Server URL")
                                .font(.subheadline.weight(.medium))
                            TextField("http://localhost:11434", text: $serverURL)
                                .textFieldStyle(.roundedBorder)
                            Text("The URL where the \(provider.type.rawValue) server is running")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // API Key (for cloud providers)
                    if provider.type.requiresAPIKey {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key")
                                .font(.subheadline.weight(.medium))
                            SecureField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                            Text("Your \(provider.type.rawValue) API key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Model selection
                    if !provider.availableModels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Default Model")
                                .font(.subheadline.weight(.medium))
                            Picker("Model", selection: $selectedModel) {
                                Text("None").tag("")
                                ForEach(provider.availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Divider()

                    // Connection test
                    HStack {
                        Button(action: testConnection) {
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Label("Test Connection", systemImage: "network")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isTestingConnection)

                        Spacer()

                        switch connectionStatus {
                        case .unknown:
                            EmptyView()
                        case .success:
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failed(let error):
                            Label(error, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }

                    // Provider info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Provider Info")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("Created: \(provider.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if let lastUsed = provider.lastUsed {
                            Text("Last used: \(lastUsed.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 450, height: 500)
        .onAppear {
            // Initialize state from provider
            name = provider.name
            isEnabled = provider.isEnabled
            apiKey = provider.apiKey ?? ""
            serverURL = provider.serverURL ?? provider.type.defaultServerURL ?? ""
            selectedModel = provider.selectedModel ?? ""
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionStatus = .unknown

        Task {
            // Simulate connection test
            try? await Task.sleep(for: .seconds(1))

            await MainActor.run {
                // For local providers, check if server is reachable
                if provider.type == .ollama || provider.type == .lmStudio {
                    // Simple check - in a real implementation, we'd ping the server
                    if !serverURL.isEmpty && serverURL.hasPrefix("http") {
                        connectionStatus = .success
                    } else {
                        connectionStatus = .failed("Invalid URL")
                    }
                } else if provider.type == .appleFoundation {
                    connectionStatus = .success
                } else if provider.type.requiresAPIKey {
                    if apiKey.isEmpty {
                        connectionStatus = .failed("API key required")
                    } else {
                        connectionStatus = .success
                    }
                } else {
                    connectionStatus = .success
                }
                isTestingConnection = false
            }
        }
    }

    private func saveChanges() {
        // Create updated provider config
        var updatedProvider = provider
        updatedProvider.name = name
        updatedProvider.isEnabled = isEnabled
        updatedProvider.apiKey = apiKey.isEmpty ? nil : apiKey
        updatedProvider.serverURL = serverURL.isEmpty ? nil : serverURL
        updatedProvider.selectedModel = selectedModel.isEmpty ? nil : selectedModel

        // Update in provider manager
        ProviderConfigManager.shared.updateProvider(updatedProvider)

        dismiss()
    }
}


// MARK: - Legacy LLM Settings (for backwards compatibility)

struct LLMSettingsContent: View {
    @ObservedObject private var serverManager = ServerManager.shared

    @AppStorage("llmProvider") private var llmProvider = "apple-intelligence"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("lmStudioURL") private var lmStudioURL = "http://localhost:1234"
    @AppStorage("selectedModel") private var selectedModel = "llama3.2"
    @AppStorage("configuratorModel") private var configuratorModel = "llama3.2"

    @State private var customModelName = ""
    @State private var isPullingModel = false
    @State private var pullError: String?

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Provider", icon: "cube.box") {
                Picker("Provider", selection: $llmProvider) {
                    Text("Apple Intelligence").tag("apple-intelligence")
                    Text("Ollama").tag("ollama")
                    Text("LM Studio").tag("lmstudio")
                }
                .pickerStyle(.segmented)
                .onChange(of: llmProvider) { _, _ in
                    Task { await serverManager.refreshOllamaModels() }
                }
            }

            if llmProvider == "apple-intelligence" {
                appleIntelligenceSettings
            } else if llmProvider == "ollama" {
                ollamaSettings
            } else if llmProvider == "lmstudio" {
                lmStudioSettings
            }
        }
        .onAppear {
            Task { await serverManager.refreshOllamaModels() }
        }
    }

    @ViewBuilder
    private var appleIntelligenceSettings: some View {
        SettingsCard(title: "Status", icon: "apple.logo") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "apple.logo")
                        .foregroundStyle(.secondary)
                    Text("Apple Intelligence")
                        .fontWeight(.medium)
                    Spacer()
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Uses on-device LLM for fast, private inference. Larger requests may use Private Cloud Compute with end-to-end encryption.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        SettingsCard(title: "Model Configuration", icon: "cpu") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Configurator Model")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("Configurator Model", selection: $configuratorModel) {
                        Text("Default (Apple Intelligence)").tag("apple-intelligence")
                        if llmProvider == "ollama" {
                            ForEach(serverManager.availableModels) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                    }

                    Text("Used for the agent configuration chat interface. More powerful models provide better configuration assistance.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Agent Runtime Model")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("Agent Model", selection: $selectedModel) {
                        Text("Default (Apple Intelligence)").tag("apple-intelligence")
                        if llmProvider == "ollama" {
                            ForEach(serverManager.availableModels) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                    }

                    Text("Used by your configured agents at runtime. Faster models improve response time.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }

        SettingsCard(title: "Privacy", icon: "hand.raised") {
            VStack(alignment: .leading, spacing: 8) {
                Label("On-device processing", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)

                Text("Your data never leaves your device unless using Private Cloud Compute, which uses end-to-end encryption and stateless computation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
    @AppStorage("localAgentHost") private var localHost = "0.0.0.0"  // Bind to all interfaces by default
    @AppStorage("dataDirectory") private var dataDirectory = "~/AgentKit"
    @AppStorage("autoConnectLocal") private var autoConnectLocal = true
    @AppStorage("enableBonjour") private var enableBonjour = true

    @State private var isStarting = false
    @State private var showLogs = false
    @State private var availableHosts: [String] = []

    var body: some View {
        VStack(spacing: 16) {
            // Description card explaining what this is
            SettingsCard(title: "Agent-to-Agent Server", icon: "antenna.radiowaves.left.and.right") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The A2A (Agent-to-Agent) server enables communication between AI agents using Google's open protocol.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Link(destination: URL(string: "https://github.com/google/A2A")!) {
                        Label("Learn more about A2A Protocol", systemImage: "arrow.up.forward.square")
                            .font(.caption)
                    }
                }
            }

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
                        Text("Bind Address")
                            .frame(width: 100, alignment: .leading)

                        Picker("Host", selection: $localHost) {
                            Text("All Interfaces (0.0.0.0)").tag("0.0.0.0")
                            ForEach(availableHosts, id: \.self) { host in
                                Text(host).tag(host)
                            }
                        }
                        .labelsHidden()
                    }

                    // Show accessible addresses when server is running
                    if serverManager.isRunning && !availableHosts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Accessible at:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(availableHosts.filter { $0 != "127.0.0.1" }, id: \.self) { host in
                                HStack {
                                    Text("http://\(host):\(localPort)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.blue)

                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString("http://\(host):\(localPort)", forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
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
            .onAppear {
                availableHosts = getNetworkInterfaces()
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

    /// Get available network interfaces (excluding loopback)
    private func getNetworkInterfaces() -> [String] {
        var addresses: [String] = []

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return addresses }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }

            // Only IPv4 addresses
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }

            // Get the interface name
            let name = String(cString: interface.ifa_name)

            // Skip loopback
            guard name != "lo0" else { continue }

            // Convert address to string
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            // Convert CChar array to String, truncating at null terminator
            let address = hostname.withUnsafeBufferPointer { buffer in
                let nullIndex = buffer.firstIndex(of: 0) ?? buffer.endIndex
                return String(decoding: buffer[..<nullIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            if !address.isEmpty && address != "127.0.0.1" {
                addresses.append(address)
            }
        }

        return addresses.sorted()
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
    @State private var nativeTools: [ExtensionItem] = ExtensionItem.nativeTools
    @State private var shortcuts: [ExtensionItem] = []
    @State private var isDiscoveringShortcuts = false

    var body: some View {
        VStack(spacing: 16) {
            // Native Tools Section
            SettingsCard(title: "Native Tools", icon: "wrench.and.screwdriver") {
                VStack(spacing: 0) {
                    ForEach($nativeTools) { $tool in
                        ExtensionToggleRow(item: $tool)
                        if tool.id != nativeTools.last?.id {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }

            // System Integrations Section
            SettingsCard(title: "System Integrations", icon: "apple.logo") {
                VStack(spacing: 0) {
                    SystemIntegrationToggleRow(
                        name: "Calendar & Reminders",
                        icon: "calendar",
                        description: "Create events and reminders",
                        permissionStatus: .granted
                    )
                    Divider().padding(.leading, 44)
                    SystemIntegrationToggleRow(
                        name: "Safari Reading List",
                        icon: "book",
                        description: "Import saved articles",
                        permissionStatus: .granted
                    )
                    Divider().padding(.leading, 44)
                    SystemIntegrationToggleRow(
                        name: "Shared with You",
                        icon: "person.2",
                        description: "Access shared links from Messages",
                        permissionStatus: .needsPermission,
                        onRequestPermission: requestSharedWithYouPermission
                    )
                }
            }

            // Shortcuts Section
            SettingsCard(title: "Shortcuts", icon: "bolt.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Allow agents to run your Shortcuts")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(action: { Task { await discoverShortcuts() } }) {
                            HStack(spacing: 4) {
                                if isDiscoveringShortcuts {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Refresh")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isDiscoveringShortcuts)
                    }

                    if shortcuts.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "bolt.circle")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                                Text("No shortcuts discovered")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Open Shortcuts App") {
                                    NSWorkspace.shared.open(URL(string: "shortcuts://")!)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding()
                            Spacer()
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach($shortcuts) { $shortcut in
                                ShortcutToggleRow(item: $shortcut)
                                if shortcut.id != shortcuts.last?.id {
                                    Divider()
                                        .padding(.leading, 44)
                                }
                            }
                        }
                    }
                }
            }

            // App Integration Info
            SettingsCard(title: "Third-Party Apps", icon: "app.badge") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("App Integration via Shortcuts")
                                .font(.subheadline.weight(.medium))
                            Text("To integrate third-party apps, create Shortcuts in the Shortcuts app that perform the actions you want, then enable them above.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Divider()

                    HStack {
                        Text("macOS does not allow apps to discover other apps' capabilities directly. Use Shortcuts as the bridge between Envoy and your favorite apps.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Spacer()

                        Button("Open Shortcuts") {
                            NSWorkspace.shared.open(URL(string: "shortcuts://")!)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .task {
            await discoverShortcuts()
        }
    }

    private func discoverShortcuts() async {
        isDiscoveringShortcuts = true
        defer { isDiscoveringShortcuts = false }

        let shortcutsPath = "/usr/bin/shortcuts"
        guard FileManager.default.fileExists(atPath: shortcutsPath) else { return }

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
            guard let output = String(data: data, encoding: .utf8) else { return }

            let shortcutNames = output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            shortcuts = shortcutNames.map { name in
                // Preserve enabled state if already exists
                let existing = shortcuts.first { $0.name == name }
                return ExtensionItem(
                    id: "shortcut.\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
                    name: name,
                    description: "User Shortcut",
                    category: "shortcuts",
                    icon: "bolt.circle.fill",
                    isEnabled: existing?.isEnabled ?? false,
                    source: .shortcuts
                )
            }
        } catch {
            print("Failed to discover shortcuts: \(error)")
        }
    }

    private func requestSharedWithYouPermission() {
        // Open System Preferences to the relevant pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ShareKit") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Integrations Settings

struct IntegrationsSettingsContent: View {
    @EnvironmentObject private var appState: AppState

    // Slack tokens (bot + user)
    @AppStorage("slackBotToken") private var slackBotToken: String = ""
    @AppStorage("slackUserToken") private var slackUserToken: String = ""
    // Legacy migration
    @AppStorage("slackToken") private var legacySlackToken: String = ""

    @AppStorage("quipToken") private var quipToken: String = ""

    @State private var tempSlackBotToken: String = ""
    @State private var tempSlackUserToken: String = ""
    @State private var tempQuipToken: String = ""
    @State private var slackStatus: IntegrationStatus = .notConfigured
    @State private var slackHasBotToken = false
    @State private var slackHasUserToken = false
    @State private var quipStatus: IntegrationStatus = .notConfigured
    @State private var isTesting = false

    // Apple integration toggles
    @AppStorage("appleRemindersEnabled") private var remindersEnabled: Bool = false
    @AppStorage("appleNotesEnabled") private var notesEnabled: Bool = false
    @AppStorage("appleMailEnabled") private var mailEnabled: Bool = false
    @AppStorage("appleMessagesEnabled") private var messagesEnabled: Bool = false

    enum IntegrationStatus {
        case notConfigured
        case configured
        case testing
        case error(String)

        var color: Color {
            switch self {
            case .notConfigured: return .secondary
            case .configured: return .green
            case .testing: return .blue
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .notConfigured: return "circle"
            case .configured: return "checkmark.circle.fill"
            case .testing: return "arrow.clockwise"
            case .error: return "exclamationmark.circle.fill"
            }
        }

        var label: String {
            switch self {
            case .notConfigured: return "Not Configured"
            case .configured: return "Connected"
            case .testing: return "Testing..."
            case .error(let msg): return "Error: \(msg)"
            }
        }

        var isConfigured: Bool {
            if case .configured = self { return true }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Slack Integration
            SettingsCard(title: "Slack", icon: "bubble.left.and.bubble.right") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect to Slack with bot and/or user tokens. Bot tokens post as your app; user tokens access DMs and post as you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Bot Token
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Bot Token")
                                .font(.caption.weight(.medium))
                            if slackHasBotToken {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                        SecureField("xoxb-...", text: $tempSlackBotToken)
                            .textFieldStyle(.roundedBorder)
                    }

                    // User Token
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("User Token")
                                .font(.caption.weight(.medium))
                            Text("(optional)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if slackHasUserToken {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                        SecureField("xoxp-...", text: $tempSlackUserToken)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Get tokens from")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Link("api.slack.com/apps", destination: URL(string: "https://api.slack.com/apps")!)
                                .font(.caption)
                        }

                        Spacer()

                        statusBadge(slackStatus)

                        Button("Save & Test") {
                            Task { await saveAndTestSlack() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled((tempSlackBotToken.isEmpty && tempSlackUserToken.isEmpty) || isTesting)
                    }

                    // Available tools when connected
                    if slackStatus.isConfigured {
                        toolsList(tools: [
                            ("Send Message", "arrow.up.message"),
                            ("List Channels", "list.bullet"),
                            ("Channel History", "clock"),
                            ("Add Reaction", "face.smiling"),
                            ("Search Messages", "magnifyingglass"),
                            ("User Info", "person.crop.circle")
                        ])
                    }
                }
            }

            // Quip Integration
            SettingsCard(title: "Quip", icon: "doc.text") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect to Quip to create documents, edit content, and collaborate with your team.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        SecureField("Access Token", text: $tempQuipToken)
                            .textFieldStyle(.roundedBorder)

                        statusBadge(quipStatus)
                    }

                    HStack {
                        Text("Get a token from Quip settings → API")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Spacer()

                        Button("Save & Test") {
                            Task { await saveAndTestQuip() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(tempQuipToken.isEmpty || isTesting)
                    }

                    // Available tools when connected
                    if quipStatus.isConfigured {
                        toolsList(tools: [
                            ("Create Document", "doc.badge.plus"),
                            ("Get Document", "doc.text"),
                            ("Edit Document", "pencil"),
                            ("List Folders", "folder"),
                            ("Add Comment", "text.bubble"),
                            ("Search", "magnifyingglass")
                        ])
                    }
                }
            }

            // Apple Integrations
            SettingsCard(title: "Apple Integrations", icon: "apple.logo") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enable native Apple app integrations. These use system APIs and may require permission prompts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Reminders
                    appleIntegrationToggle(
                        title: "Reminders",
                        icon: "checklist",
                        description: "Create, list, and complete reminders",
                        isEnabled: $remindersEnabled,
                        tools: [
                            ("Create Reminder", "plus.circle"),
                            ("List Reminders", "list.bullet"),
                            ("Complete", "checkmark.circle"),
                            ("Search", "magnifyingglass")
                        ]
                    )

                    Divider()

                    // Notes
                    appleIntegrationToggle(
                        title: "Notes",
                        icon: "note.text",
                        description: "Create, search, and append to notes",
                        isEnabled: $notesEnabled,
                        tools: [
                            ("Create Note", "square.and.pencil"),
                            ("Search Notes", "magnifyingglass"),
                            ("Get Note", "doc.text"),
                            ("Append", "text.append")
                        ]
                    )

                    Divider()

                    // Mail
                    appleIntegrationToggle(
                        title: "Mail",
                        icon: "envelope",
                        description: "Compose emails and search mailboxes",
                        isEnabled: $mailEnabled,
                        tools: [
                            ("Compose", "square.and.pencil"),
                            ("Search", "magnifyingglass"),
                            ("Unread Count", "envelope.badge"),
                            ("Mailboxes", "tray.2")
                        ]
                    )

                    Divider()

                    // Messages
                    appleIntegrationToggle(
                        title: "Messages",
                        icon: "message",
                        description: "Open compose windows for iMessage/SMS",
                        isEnabled: $messagesEnabled,
                        tools: [
                            ("iMessage", "message.fill"),
                            ("SMS", "phone.bubble")
                        ]
                    )
                }
            }

            // Info Card
            SettingsCard(title: "About Integrations", icon: "info.circle") {
                Text("Native integrations provide tools that agents can use during conversations. When configured, agents can automatically use these tools to complete tasks like sending Slack messages or creating Quip documents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .onAppear {
            // Migrate legacy single token to bot token if needed
            if !legacySlackToken.isEmpty && slackBotToken.isEmpty {
                slackBotToken = legacySlackToken
                legacySlackToken = ""
            }

            tempSlackBotToken = slackBotToken
            tempSlackUserToken = slackUserToken
            tempQuipToken = quipToken
            updateStatuses()

            // Configure Apple integrations based on stored preferences
            Task {
                await appState.configureAppleIntegrations(
                    reminders: remindersEnabled,
                    notes: notesEnabled,
                    mail: mailEnabled,
                    messages: messagesEnabled
                )
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: IntegrationStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.caption)
            Text(status.label)
                .font(.caption)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.1))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func toolsList(tools: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Available Tools:")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(tools, id: \.0) { tool in
                    HStack(spacing: 4) {
                        Image(systemName: tool.1)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text(tool.0)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func appleIntegrationToggle(
        title: String,
        icon: String,
        description: String,
        isEnabled: Binding<Bool>,
        tools: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isEnabled.wrappedValue ? .blue : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .onChange(of: isEnabled.wrappedValue) { _, newValue in
                        Task {
                            await configureAppleIntegration(title, enabled: newValue)
                        }
                    }
            }

            if isEnabled.wrappedValue {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(tools, id: \.0) { tool in
                        HStack(spacing: 4) {
                            Image(systemName: tool.1)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text(tool.0)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 32)
            }
        }
    }

    private func configureAppleIntegration(_ name: String, enabled: Bool) async {
        switch name {
        case "Reminders":
            await appState.configureReminders(enabled: enabled)
        case "Notes":
            await appState.configureNotes(enabled: enabled)
        case "Mail":
            await appState.configureMail(enabled: enabled)
        case "Messages":
            await appState.configureMessages(enabled: enabled)
        default:
            break
        }
    }

    private func updateStatuses() {
        let hasAnySlackToken = !slackBotToken.isEmpty || !slackUserToken.isEmpty
        slackStatus = hasAnySlackToken ? .configured : .notConfigured
        slackHasBotToken = !slackBotToken.isEmpty
        slackHasUserToken = !slackUserToken.isEmpty
        quipStatus = quipToken.isEmpty ? .notConfigured : .configured
    }

    private func saveAndTestSlack() async {
        isTesting = true
        slackStatus = .testing

        // Save tokens
        slackBotToken = tempSlackBotToken
        slackUserToken = tempSlackUserToken

        // Configure integration with both tokens
        await appState.configureSlack(
            botToken: tempSlackBotToken.isEmpty ? nil : tempSlackBotToken,
            userToken: tempSlackUserToken.isEmpty ? nil : tempSlackUserToken
        )

        // Verify by checking if tools are available
        let tools = await appState.nativeIntegrations.allTools()
        let hasSlackTools = tools.contains { $0.name.hasPrefix("slack_") }

        // Get token status
        let tokenStatus = await appState.nativeIntegrations.slackTokenStatus()

        await MainActor.run {
            slackHasBotToken = tokenStatus.hasBot
            slackHasUserToken = tokenStatus.hasUser
            slackStatus = hasSlackTools ? .configured : .error("Failed to connect")
            isTesting = false
        }
    }

    private func saveAndTestQuip() async {
        isTesting = true
        quipStatus = .testing

        // Save token
        quipToken = tempQuipToken

        // Configure integration
        await appState.configureQuip(token: tempQuipToken)

        // Verify by checking if tools are available
        let tools = await appState.nativeIntegrations.allTools()
        let hasQuipTools = tools.contains { $0.name.hasPrefix("quip_") }

        await MainActor.run {
            quipStatus = hasQuipTools ? .configured : .error("Failed to connect")
            isTesting = false
        }
    }
}

// MARK: - Extension Toggle Row

struct ExtensionToggleRow: View {
    @Binding var item: ExtensionItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(item.isEnabled ? .blue : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .fontWeight(.medium)

                    if item.requiresApproval {
                        Text("APPROVAL")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $item.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - System Integration Toggle Row

struct SystemIntegrationToggleRow: View {
    let name: String
    let icon: String
    let description: String
    let permissionStatus: PermissionStatus
    var onRequestPermission: (() -> Void)? = nil

    @State private var isEnabled = true

    enum PermissionStatus {
        case granted
        case needsPermission
        case denied
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(permissionStatus == .granted ? .blue : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if permissionStatus == .needsPermission {
                Button(action: { onRequestPermission?() }) {
                    Text("Grant Access")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Shortcut Toggle Row

struct ShortcutToggleRow: View {
    @Binding var item: ExtensionItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.circle.fill")
                .font(.title3)
                .foregroundStyle(item.isEnabled ? .orange : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .fontWeight(.medium)
                Text("Shortcut")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Open in Shortcuts button
            Button(action: {
                let encodedName = item.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.name
                if let url = URL(string: "shortcuts://open-shortcut?name=\(encodedName)") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open in Shortcuts")

            Toggle("", isOn: $item.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - App Toggle Row

struct AppToggleRow: View {
    @Binding var item: ExtensionItem
    @State private var showConfig = false

    var body: some View {
        HStack(spacing: 12) {
            // App icon (would load from bundle in production)
            RoundedRectangle(cornerRadius: 8)
                .fill(.blue.gradient)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "app")
                        .font(.caption)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .fontWeight(.medium)
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.requiresApproval {
                Button(action: { showConfig = true }) {
                    Image(systemName: "gear")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Configure")
            }

            Toggle("", isOn: $item.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 8)
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

    /// Native tools that are built into the app
    static let nativeTools: [ExtensionItem] = [
        ExtensionItem(
            id: "native.calendar",
            name: "Calendar",
            description: "Create events and check availability",
            category: "calendar",
            icon: "calendar",
            isEnabled: true,
            source: .builtIn
        ),
        ExtensionItem(
            id: "native.reminders",
            name: "Reminders",
            description: "Create and manage tasks",
            category: "tasks",
            icon: "checklist",
            isEnabled: true,
            source: .builtIn
        ),
        ExtensionItem(
            id: "native.filesystem",
            name: "File System",
            description: "Read and write files",
            category: "files",
            icon: "folder",
            isEnabled: true,
            source: .builtIn,
            requiresApproval: true
        ),
        ExtensionItem(
            id: "native.web",
            name: "Web Fetch",
            description: "Fetch and parse web content",
            category: "other",
            icon: "globe",
            isEnabled: true,
            source: .builtIn
        ),
        ExtensionItem(
            id: "native.shell",
            name: "Shell Commands",
            description: "Execute terminal commands",
            category: "system",
            icon: "terminal",
            isEnabled: false,
            source: .builtIn,
            requiresApproval: true
        ),
        ExtensionItem(
            id: "native.memory",
            name: "Memory (RAG)",
            description: "Semantic search across content",
            category: "other",
            icon: "brain",
            isEnabled: true,
            source: .builtIn
        )
    ]

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
    @AppStorage("autoApproveRead") private var autoApproveRead = true
    @AppStorage("autoApproveGlob") private var autoApproveGlob = true
    @AppStorage("autoApproveGrep") private var autoApproveGrep = true
    @AppStorage("requireApprovalForWrite") private var requireWrite = true
    @AppStorage("requireApprovalForBash") private var requireBash = true

    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Auto-Approve (Low Risk)", icon: "checkmark.circle") {
                VStack(spacing: 16) {
                    Text("These tools run without asking for permission each time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ApprovalToggleRow(
                        title: "Read",
                        description: "Read file contents",
                        isOn: $autoApproveRead
                    )
                    ApprovalToggleRow(
                        title: "Glob",
                        description: "Search for files by name pattern",
                        isOn: $autoApproveGlob
                    )
                    ApprovalToggleRow(
                        title: "Grep",
                        description: "Search file contents",
                        isOn: $autoApproveGrep
                    )
                }
            }

            SettingsCard(title: "Require Approval (High Risk)", icon: "exclamationmark.shield") {
                VStack(spacing: 16) {
                    Text("These tools always ask for your approval before running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ApprovalToggleRow(
                        title: "Write",
                        description: "Create or modify files",
                        isOn: $requireWrite
                    )
                    ApprovalToggleRow(
                        title: "Bash",
                        description: "Execute shell commands",
                        isOn: $requireBash
                    )
                }
            }
        }
    }
}

// MARK: - Approval Toggle Row

struct ApprovalToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
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
                ModelsSettingsContent()
                    .padding()
            }
            .tabItem {
                Label("Models", systemImage: "cube.box")
            }
            .tag(SettingsCategory.models)

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

// MARK: - System Health View

/// Health check status indicator
enum HealthStatus: String {
    case healthy = "Healthy"
    case warning = "Warning"
    case unhealthy = "Unhealthy"
    case checking = "Checking..."
    case unknown = "Unknown"

    var color: Color {
        switch self {
        case .healthy: return .green
        case .warning: return .orange
        case .unhealthy: return .red
        case .checking: return .blue
        case .unknown: return .gray
        }
    }

    var icon: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .unhealthy: return "xmark.circle.fill"
        case .checking: return "arrow.clockwise"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Individual health check item
struct HealthCheckItem: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    var status: HealthStatus
    var detail: String
    var lastChecked: Date?
}

/// Result of an end-to-end agent test
struct E2ETestResult {
    let success: Bool
    let testMessage: String
    let response: String?
    let latencyMs: Int?
    let tokensGenerated: Int?
    let modelUsed: String?
    let error: String?
    let timestamp: Date
}

/// System health dashboard view
struct SystemHealthView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(ChatService.self) private var chatService
    @Environment(ProviderConfigManager.self) private var providerManager

    @State private var healthChecks: [HealthCheckItem] = []
    @State private var isRunningChecks = false
    @State private var lastFullCheck: Date?
    @State private var overallStatus: HealthStatus = .unknown
    @State private var mcpConnectionCount: Int = 0
    @State private var nativeToolCount: Int = 0

    // End-to-end test state
    @State private var isRunningE2ETest = false
    @State private var e2eTestResult: E2ETestResult?
    @State private var e2eTestThreadId: AgentKit.ThreadID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Overall Status Banner
                overallStatusBanner

                // Run Health Check Button
                HStack {
                    Button(action: runAllHealthChecks) {
                        Label(
                            isRunningChecks ? "Running Checks..." : "Run Health Check",
                            systemImage: isRunningChecks ? "arrow.clockwise" : "heart.text.square"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunningChecks)

                    if let lastCheck = lastFullCheck {
                        Text("Last checked: \(lastCheck, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.bottom, 8)

                // Health Check Categories
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    // LLM Providers Section
                    healthSection(title: "LLM Providers", icon: "cpu", checks: healthChecks.filter { $0.category == "provider" })

                    // Agent Connections Section
                    healthSection(title: "Agent Connections", icon: "person.2", checks: healthChecks.filter { $0.category == "agent" })

                    // MCP Tools Section
                    healthSection(title: "MCP Extensions", icon: "puzzlepiece.extension", checks: healthChecks.filter { $0.category == "mcp" })

                    // Native Integrations Section
                    healthSection(title: "Native Integrations", icon: "bolt.horizontal", checks: healthChecks.filter { $0.category == "integration" })

                    // Data & Storage Section
                    healthSection(title: "Data & Storage", icon: "externaldrive", checks: healthChecks.filter { $0.category == "data" })
                }

                // Detailed Issues (if any)
                let issues = healthChecks.filter { $0.status == .unhealthy || $0.status == .warning }
                if !issues.isEmpty {
                    issuesSection(issues: issues)
                }

                // System Info
                systemInfoSection

                // End-to-End Agent Test Section
                e2eTestSection
            }
            .padding()
        }
        .onAppear {
            initializeHealthChecks()
            runAllHealthChecks()
        }
        .task {
            mcpConnectionCount = await appState.mcpManager.connectionCount
            nativeToolCount = await appState.nativeIntegrations.allTools().count
        }
    }

    // MARK: - End-to-End Test Section

    private var e2eTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "testtube.2")
                    .foregroundStyle(.purple)
                Text("End-to-End Agent Test")
                    .font(.headline)
            }

            Text("Run a real conversation with the agent to verify the complete pipeline works.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(action: runE2ETest) {
                    Label(
                        isRunningE2ETest ? "Testing..." : "Run Agent Test",
                        systemImage: isRunningE2ETest ? "arrow.clockwise" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isRunningE2ETest || !chatService.isReady)

                if let result = e2eTestResult {
                    HStack(spacing: 6) {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.success ? .green : .red)
                        Text(result.success ? "Passed" : "Failed")
                            .font(.subheadline.weight(.medium))
                    }
                }

                Spacer()

                if let threadId = e2eTestThreadId {
                    Button("View Thread") {
                        // Navigate to the test thread
                        appState.selectedThreadId = threadId
                        appState.selectedSidebarItem = .threads
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let result = e2eTestResult {
                e2eTestResultView(result)
            }

            if !chatService.isReady {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Select a model/provider first to run the agent test")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
        )
    }

    private func e2eTestResultView(_ result: E2ETestResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 4)

            // Test details
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Test Message")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(result.testMessage)
                        .font(.caption)
                        .lineLimit(2)
                }
                Spacer()
            }

            if let response = result.response {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent Response")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(response)
                            .font(.caption)
                            .lineLimit(3)
                    }
                    Spacer()
                }
            }

            // Stats
            HStack(spacing: 16) {
                if let latency = result.latencyMs {
                    statBadge("Latency", "\(latency)ms")
                }
                if let tokens = result.tokensGenerated {
                    statBadge("Tokens", "\(tokens)")
                }
                if let model = result.modelUsed {
                    statBadge("Model", model)
                }
            }

            if let error = result.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Text("Tested: \(result.timestamp, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func statBadge(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.controlBackgroundColor).opacity(0.5))
        )
    }

    private func runE2ETest() {
        isRunningE2ETest = true
        e2eTestResult = nil

        Task {
            let startTime = Date()
            let testMessage = "Hello! Please respond with a brief greeting and confirm you're working properly."

            do {
                // Find or create the health check thread
                let threadId = findOrCreateHealthCheckThread()
                await MainActor.run { e2eTestThreadId = threadId }

                // Add the test message to the thread
                let userMsg = AgentKit.ThreadMessage.user(testMessage)
                if let index = appState.workspace.threads.firstIndex(where: { $0.id == threadId }) {
                    await MainActor.run {
                        appState.workspace.threads[index].messages.append(userMsg)
                        appState.workspace.threads[index].updatedAt = Date()
                    }
                }

                // Send the message and collect response
                var responseText = ""
                let stream = chatService.chat(
                    prompt: testMessage,
                    systemPrompt: "You are a helpful assistant performing a system health check. Respond briefly to confirm you're working.",
                    history: []
                )

                for try await chunk in stream {
                    responseText += chunk
                }

                let endTime = Date()
                let latencyMs = Int((endTime.timeIntervalSince(startTime)) * 1000)

                // Add response to thread
                let assistantMsg = AgentKit.ThreadMessage.assistant(responseText)
                if let index = appState.workspace.threads.firstIndex(where: { $0.id == threadId }) {
                    await MainActor.run {
                        appState.workspace.threads[index].messages.append(assistantMsg)
                        appState.workspace.threads[index].updatedAt = Date()
                    }
                }

                // Determine success
                let success = !responseText.isEmpty && responseText.count > 10

                await MainActor.run {
                    e2eTestResult = E2ETestResult(
                        success: success,
                        testMessage: testMessage,
                        response: responseText.isEmpty ? nil : String(responseText.prefix(200)),
                        latencyMs: latencyMs,
                        tokensGenerated: chatService.generationStats?.tokensGenerated,
                        modelUsed: chatService.loadedModelId?.components(separatedBy: "/").last,
                        error: success ? nil : "Response too short or empty",
                        timestamp: Date()
                    )
                    isRunningE2ETest = false
                }

            } catch {
                await MainActor.run {
                    e2eTestResult = E2ETestResult(
                        success: false,
                        testMessage: testMessage,
                        response: nil,
                        latencyMs: nil,
                        tokensGenerated: nil,
                        modelUsed: nil,
                        error: error.localizedDescription,
                        timestamp: Date()
                    )
                    isRunningE2ETest = false
                }
            }
        }
    }

    private func findOrCreateHealthCheckThread() -> AgentKit.ThreadID {
        // Look for existing health check thread
        if let existing = appState.workspace.threads.first(where: { $0.title == "🏥 System Health Check" }) {
            return existing.id
        }

        // Create new health check thread
        let thread = AgentKit.Thread(
            title: "🏥 System Health Check",
            container: .global,
            modelId: chatService.loadedModelId,
            providerId: chatService.selectedProvider?.id.uuidString
        )

        appState.workspace.threads.insert(thread, at: 0)
        return thread.id
    }

    // MARK: - Components

    private var overallStatusBanner: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(overallStatus.color.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: overallStatus.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(overallStatus.color)
                    .symbolEffect(.pulse, options: .speed(0.5), isActive: overallStatus == .checking)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("System Status")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(overallStatus.rawValue)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(overallStatus.color)

                if overallStatus == .healthy {
                    Text("All systems operational")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if overallStatus == .warning {
                    Text("Some components need attention")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if overallStatus == .unhealthy {
                    Text("Critical issues detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(overallStatus.color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(overallStatus.color.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func healthSection(title: String, icon: String, checks: [HealthCheckItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Spacer()

                // Section status indicator
                let worstStatus = checks.map { $0.status }.min { s1, s2 in
                    statusPriority(s1) > statusPriority(s2)
                } ?? .unknown

                Circle()
                    .fill(worstStatus.color)
                    .frame(width: 10, height: 10)
            }

            VStack(spacing: 8) {
                if checks.isEmpty {
                    Text("No checks available")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    ForEach(checks) { check in
                        healthCheckRow(check)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
        )
    }

    private func healthCheckRow(_ check: HealthCheckItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: check.status.icon)
                .font(.system(size: 14))
                .foregroundStyle(check.status.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(check.name)
                    .font(.subheadline.weight(.medium))

                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func issuesSection(issues: [HealthCheckItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Issues Detected")
                    .font(.headline)
            }

            ForEach(issues) { issue in
                HStack(spacing: 12) {
                    Image(systemName: issue.status.icon)
                        .foregroundStyle(issue.status.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.name)
                            .font(.subheadline.weight(.medium))
                        Text(issue.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Suggestion button
                    Button("Fix") {
                        // TODO: Implement fix suggestions
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(issue.status.color.opacity(0.1))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
        )
    }

    private var systemInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("System Information")
                    .font(.headline)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                infoRow("Threads", "\(appState.workspace.threads.count)")
                infoRow("Documents", "\(appState.workspace.documents.count)")
                infoRow("Providers", "\(providerManager.providers.count) configured")
                infoRow("MCP Connections", "\(mcpConnectionCount)")
                infoRow("Native Tools", "\(nativeToolCount) available")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
        )
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
        }
        .padding(.vertical, 2)
    }

    // MARK: - Health Check Logic

    private func initializeHealthChecks() {
        healthChecks = [
            // Provider checks
            HealthCheckItem(name: "Chat Service", category: "provider", status: .unknown, detail: "Checking..."),
            HealthCheckItem(name: "Selected Provider", category: "provider", status: .unknown, detail: "Checking..."),
            HealthCheckItem(name: "Model Loaded", category: "provider", status: .unknown, detail: "Checking..."),

            // Agent checks
            HealthCheckItem(name: "Local Agent", category: "agent", status: .unknown, detail: "Checking..."),
            HealthCheckItem(name: "A2A Protocol", category: "agent", status: .unknown, detail: "Checking..."),

            // MCP checks
            HealthCheckItem(name: "MCP Manager", category: "mcp", status: .unknown, detail: "Checking..."),

            // Native Integration checks
            HealthCheckItem(name: "Slack Integration", category: "integration", status: .unknown, detail: "Checking..."),
            HealthCheckItem(name: "Quip Integration", category: "integration", status: .unknown, detail: "Checking..."),

            // Data checks
            HealthCheckItem(name: "Workspace", category: "data", status: .unknown, detail: "Checking..."),
            HealthCheckItem(name: "Memory Store", category: "data", status: .unknown, detail: "Checking..."),
        ]
    }

    private func runAllHealthChecks() {
        isRunningChecks = true
        overallStatus = .checking

        Task {
            // Chat Service Check
            await updateCheck(name: "Chat Service") { _ in
                if chatService.isReady {
                    return (.healthy, "Ready - \(chatService.providerDescription)")
                } else if chatService.isLoadingModel {
                    return (.warning, "Loading model...")
                } else {
                    return (.warning, "No provider selected")
                }
            }

            // Selected Provider Check
            await updateCheck(name: "Selected Provider") { _ in
                if let provider = chatService.selectedProvider {
                    return (.healthy, provider.name)
                } else {
                    return (.warning, "No provider configured")
                }
            }

            // Model Loaded Check
            await updateCheck(name: "Model Loaded") { _ in
                if let modelId = chatService.loadedModelId {
                    let shortName = modelId.components(separatedBy: "/").last ?? modelId
                    return (.healthy, shortName)
                } else if chatService.selectedProvider?.type == .mlx {
                    return (.warning, "No MLX model loaded")
                } else {
                    return (.healthy, "Using API provider")
                }
            }

            // Local Agent Check
            await updateCheck(name: "Local Agent") { _ in
                if let agent = appState.localAgent {
                    switch agent.status {
                    case .connected:
                        return (.healthy, "Connected to \(agent.name)")
                    case .connecting:
                        return (.warning, "Connecting...")
                    case .error(let msg):
                        return (.unhealthy, msg)
                    case .disconnected:
                        return (.warning, "Disconnected")
                    }
                } else {
                    return (.warning, "No agent connected")
                }
            }

            // A2A Protocol Check
            await updateCheck(name: "A2A Protocol") { _ in
                if appState.hasAgentClient {
                    let result = await appState.checkA2AHealth()
                    if result.isHealthy {
                        return (.healthy, "Server responding")
                    } else {
                        return (.unhealthy, result.error ?? "Server not responding")
                    }
                } else {
                    return (.warning, "No A2A client configured")
                }
            }

            // MCP Manager Check
            await updateCheck(name: "MCP Manager") { _ in
                let count = await appState.mcpManager.connectionCount
                await MainActor.run { mcpConnectionCount = count }
                if count == 0 {
                    return (.warning, "No MCP servers configured")
                } else {
                    return (.healthy, "\(count) server(s) configured")
                }
            }

            // Slack Integration Check
            await updateCheck(name: "Slack Integration") { _ in
                let hasSlack = await appState.nativeIntegrations.hasSlack
                if hasSlack {
                    let tools = await appState.nativeIntegrations.allTools().filter { $0.name.hasPrefix("slack_") }
                    return (.healthy, "\(tools.count) tools available")
                } else {
                    return (.warning, "Not configured - add token in Settings")
                }
            }

            // Quip Integration Check
            await updateCheck(name: "Quip Integration") { _ in
                let hasQuip = await appState.nativeIntegrations.hasQuip
                if hasQuip {
                    let tools = await appState.nativeIntegrations.allTools().filter { $0.name.hasPrefix("quip_") }
                    return (.healthy, "\(tools.count) tools available")
                } else {
                    return (.warning, "Not configured - add token in Settings")
                }
            }

            // Workspace Check
            await updateCheck(name: "Workspace") { _ in
                let threadCount = appState.workspace.threads.count
                let docCount = appState.workspace.documents.count
                return (.healthy, "\(threadCount) threads, \(docCount) documents")
            }

            // Memory Store Check
            await updateCheck(name: "Memory Store") { _ in
                if appState.memoryStore != nil {
                    return (.healthy, "Initialized with embeddings")
                } else {
                    return (.warning, "Memory store not initialized")
                }
            }

            // Calculate overall status
            await MainActor.run {
                isRunningChecks = false
                lastFullCheck = Date()
                calculateOverallStatus()
            }
        }
    }

    @MainActor
    private func updateCheck(name: String, check: @escaping (HealthCheckItem) async -> (HealthStatus, String)) async {
        if let index = healthChecks.firstIndex(where: { $0.name == name }) {
            let result = await check(healthChecks[index])
            healthChecks[index].status = result.0
            healthChecks[index].detail = result.1
            healthChecks[index].lastChecked = Date()
        }
    }

    private func calculateOverallStatus() {
        let statuses = healthChecks.map { $0.status }

        if statuses.contains(.unhealthy) {
            overallStatus = .unhealthy
        } else if statuses.contains(.warning) {
            overallStatus = .warning
        } else if statuses.allSatisfy({ $0 == .healthy }) {
            overallStatus = .healthy
        } else {
            overallStatus = .unknown
        }
    }

    private func statusPriority(_ status: HealthStatus) -> Int {
        switch status {
        case .unhealthy: return 0
        case .warning: return 1
        case .unknown: return 2
        case .checking: return 3
        case .healthy: return 4
        }
    }
}
