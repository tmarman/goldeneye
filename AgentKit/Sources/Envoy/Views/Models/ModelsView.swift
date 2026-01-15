//
//  ModelsView.swift
//  Envoy
//
//  Unified view for managing all LLM providers and models.
//  This is the main entry point for model/provider configuration.
//

import SwiftUI

// MARK: - Models View

/// Main view for managing all LLM providers and models
/// Accessible from Settings and as a standalone view
struct ModelsView: View {
    @State private var providerManager = ProviderConfigManager.shared
    @State private var downloadManager = MLXModelDownloadManager.shared
    @State private var selectedSection: ModelsSection = .providers
    @State private var showAddProviderSheet = false
    @State private var editingProvider: ProviderConfig?

    enum ModelsSection: String, CaseIterable {
        case providers = "Providers"
        case mlxModels = "On-Device Models"

        var icon: String {
            switch self {
            case .providers: return "server.rack"
            case .mlxModels: return "apple.logo"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar with sections
            List(ModelsSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
            }
            .navigationTitle("Models")
            .listStyle(.sidebar)
        } detail: {
            switch selectedSection {
            case .providers:
                providersView
            case .mlxModels:
                MLXModelsView()
            }
        }
        .sheet(isPresented: $showAddProviderSheet) {
            AddProviderSheet()
        }
        .sheet(item: $editingProvider) { provider in
            EditProviderSheet(provider: provider)
        }
        .task {
            await providerManager.checkAllProviders()
        }
    }

    // MARK: - Providers View

    private var providersView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                providersHeader

                // Configured providers
                configuredProvidersSection

                // Add more providers
                addProvidersSection
            }
            .padding()
        }
        .navigationTitle("Providers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showAddProviderSheet = true }) {
                    Label("Add Provider", systemImage: "plus")
                }
            }
        }
    }

    private var providersHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configure LLM Providers")
                .font(.headline)

            Text("Set up connections to AI services. Agents can use any configured provider for their tasks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var configuredProvidersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configured")
                .font(.headline)

            if providerManager.providers.isEmpty {
                emptyProvidersState
            } else {
                ForEach(providerManager.providers) { provider in
                    ProviderCard(
                        provider: provider,
                        status: providerManager.providerStatus[provider.id] ?? .unknown,
                        onToggle: { enabled in
                            var updated = provider
                            updated.isEnabled = enabled
                            providerManager.updateProvider(updated)
                        },
                        onEdit: {
                            editingProvider = provider
                        },
                        onDelete: {
                            providerManager.removeProvider(provider.id)
                        },
                        onRefresh: {
                            Task {
                                await providerManager.checkProvider(provider.id)
                            }
                        }
                    )
                }
            }
        }
    }

    private var emptyProvidersState: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No Providers Configured")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Add a provider to start using AI models")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Add Provider") {
                showAddProviderSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var addProvidersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Provider")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200))], spacing: 12) {
                ForEach(ProviderType.allCases.filter { type in
                    !providerManager.providers.contains { $0.type == type }
                }) { type in
                    AddProviderCard(type: type) {
                        let config = ProviderConfig(type: type)
                        providerManager.addProvider(config)
                        editingProvider = config
                    }
                }
            }
        }
    }
}

// MARK: - Provider Card

/// Card displaying a configured provider with status and actions
struct ProviderCard: View {
    let provider: ProviderConfig
    let status: ProviderStatus
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRefresh: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: provider.type.icon)
                .font(.title2)
                .foregroundStyle(provider.isEnabled ? provider.type.color : .secondary)
                .frame(width: 44, height: 44)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(provider.name)
                        .font(.headline)

                    statusBadge
                }

                Text(provider.type.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let model = provider.selectedModel {
                    Text("Model: \(model)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { provider.isEnabled },
                    set: { onToggle($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()

                Menu {
                    Button(action: onEdit) {
                        Label("Configure", systemImage: "gear")
                    }

                    Button(action: onRefresh) {
                        Label("Check Status", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    Button(role: .destructive, action: onDelete) {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .unknown:
            EmptyView()

        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 8, height: 8)
                Text("Checking...")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

        case .available(let count):
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                if count > 0 {
                    Text("\(count) models")
                        .font(.caption)
                } else {
                    Text("Available")
                        .font(.caption)
                }
            }
            .foregroundStyle(.green)

        case .unavailable(let reason):
            HStack(spacing: 4) {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                Text(reason)
                    .font(.caption)
            }
            .foregroundStyle(.orange)

        case .error(let message):
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text(message)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.red)
        }
    }
}

// MARK: - Add Provider Card

/// Card for adding a new provider type
struct AddProviderCard: View {
    let type: ProviderType
    let onAdd: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundStyle(type.color)

                Text(type.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? type.color.opacity(0.5) : Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Add Provider Sheet

/// Sheet for adding a new provider
struct AddProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var providerManager = ProviderConfigManager.shared
    @State private var selectedType: ProviderType = .ollama

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Provider")
                .font(.title2)
                .fontWeight(.semibold)

            // Provider type selection
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                ForEach(ProviderType.allCases) { type in
                    Button {
                        selectedType = type
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: type.icon)
                                .font(.title2)
                                .foregroundStyle(selectedType == type ? .white : type.color)

                            Text(type.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(selectedType == type ? .white : .primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedType == type ? type.color : Color(.controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Description
            Text(selectedType.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Add \(selectedType.rawValue)") {
                    let config = ProviderConfig(type: selectedType)
                    providerManager.addProvider(config)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 450, height: 400)
    }
}

// MARK: - Edit Provider Sheet

/// Sheet for editing a provider configuration
struct EditProviderSheet: View {
    let provider: ProviderConfig
    @Environment(\.dismiss) private var dismiss
    @State private var providerManager = ProviderConfigManager.shared

    @State private var name: String = ""
    @State private var apiKey: String = ""
    @State private var serverURL: String = ""
    @State private var selectedModel: String = ""
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var showAPIKey = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: provider.type.icon)
                    .font(.title)
                    .foregroundStyle(provider.type.color)

                Text("Configure \(provider.type.rawValue)")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Form {
                // Name
                Section("Name") {
                    TextField("Provider Name", text: $name)
                }

                // API Key (if required)
                if provider.type.requiresAPIKey {
                    Section("API Key") {
                        HStack {
                            if showAPIKey {
                                TextField("API Key", text: $apiKey)
                            } else {
                                SecureField("API Key", text: $apiKey)
                            }

                            Button(action: { showAPIKey.toggle() }) {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Server URL (if required)
                if provider.type.requiresServerURL {
                    Section("Server URL") {
                        TextField("http://localhost:11434", text: $serverURL)
                    }
                }

                // Model selection
                Section("Model") {
                    if isLoadingModels {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading models...")
                                .foregroundStyle(.secondary)
                        }
                    } else if availableModels.isEmpty {
                        Text("No models available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Select Model", selection: $selectedModel) {
                            Text("None").tag("")
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    }

                    Button("Refresh Models") {
                        Task {
                            await loadModels()
                        }
                    }
                    .disabled(isLoadingModels)
                }
            }
            .formStyle(.grouped)

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 450, height: 500)
        .onAppear {
            loadInitialValues()
        }
        .task {
            await loadModels()
        }
    }

    private func loadInitialValues() {
        name = provider.name
        apiKey = provider.apiKey ?? ""
        serverURL = provider.serverURL ?? provider.type.defaultServerURL ?? ""
        selectedModel = provider.selectedModel ?? ""
        availableModels = provider.availableModels
    }

    private func loadModels() async {
        isLoadingModels = true
        availableModels = await providerManager.fetchModels(for: provider.id)
        isLoadingModels = false
    }

    private func saveChanges() {
        var updated = provider
        updated.name = name
        updated.apiKey = apiKey.isEmpty ? nil : apiKey
        updated.serverURL = serverURL.isEmpty ? nil : serverURL
        updated.selectedModel = selectedModel.isEmpty ? nil : selectedModel
        updated.availableModels = availableModels
        providerManager.updateProvider(updated)
        dismiss()
    }
}

// MARK: - Previews

#Preview("Models View") {
    ModelsView()
}

#Preview("Provider Card") {
    ProviderCard(
        provider: ProviderConfig(type: .ollama, name: "Local Ollama"),
        status: .available(modelCount: 5),
        onToggle: { _ in },
        onEdit: {},
        onDelete: {},
        onRefresh: {}
    )
    .padding()
}

#Preview("Add Provider Sheet") {
    AddProviderSheet()
}
