//
//  MLXModelsView.swift
//  Envoy
//
//  Main view for browsing and downloading MLX models.
//

import SwiftUI

// MARK: - System Memory Helper

struct SystemMemory {
    /// Total physical memory in bytes
    static var totalMemoryBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// Total physical memory in GB
    static var totalMemoryGB: Int {
        Int(totalMemoryBytes / (1024 * 1024 * 1024))
    }

    /// Recommended max model size based on system memory
    /// Rule of thumb: model should use no more than 75% of RAM for comfortable usage
    static var recommendedMaxModelGB: Int {
        max(4, Int(Double(totalMemoryGB) * 0.75))
    }

    /// Whether a model of given size (in GB) is recommended for this system
    static func isRecommended(modelSizeGB: Double) -> Bool {
        modelSizeGB <= Double(recommendedMaxModelGB)
    }

    /// Get recommendation text based on system memory
    static var recommendationText: String {
        if totalMemoryGB >= 64 {
            return "Your Mac has \(totalMemoryGB)GB RAM - you can run large models like 70B parameter models"
        } else if totalMemoryGB >= 32 {
            return "Your Mac has \(totalMemoryGB)GB RAM - you can run most models up to 32B parameters"
        } else if totalMemoryGB >= 16 {
            return "Your Mac has \(totalMemoryGB)GB RAM - recommended models up to 8B parameters"
        } else {
            return "Your Mac has \(totalMemoryGB)GB RAM - recommended models up to 4B parameters"
        }
    }
}

// MARK: - MLX Models View

/// Main view for browsing, downloading, and managing MLX models
struct MLXModelsView: View {
    @State private var downloadManager = MLXModelDownloadManager.shared
    @State private var searchText: String = ""
    @State private var selectedTagFilter: MLXModelTag? = nil
    @State private var showDeleteAllConfirmation = false
    @State private var showImportSheet = false
    @State private var navigationPath = NavigationPath()

    // MARK: - Computed Properties

    private var filteredFamilies: [MLXModelFamily] {
        var families = MLXModelCatalog.families

        // Filter by tag (matches family tags OR any variant tags)
        if let tag = selectedTagFilter {
            families = families.filter { family in
                family.tags.contains(tag) ||
                family.variants.contains { $0.tags.contains(tag) }
            }
        }

        // Filter by search
        if !searchText.isEmpty {
            families = families.filter { family in
                family.displayName.localizedCaseInsensitiveContains(searchText) ||
                family.description.localizedCaseInsensitiveContains(searchText) ||
                family.provider.localizedCaseInsensitiveContains(searchText) ||
                family.variants.contains { variant in
                    variant.displayName.localizedCaseInsensitiveContains(searchText) ||
                    variant.description.localizedCaseInsensitiveContains(searchText)
                }
            }
        }

        return families
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Single search bar at top
                    searchBar

                    // System recommendation banner
                    systemRecommendationBanner

                    // Tag filter chips
                    MLXTagFilterChips(selectedTag: $selectedTagFilter)

                    // Active filter indicator
                    if selectedTagFilter != nil {
                        activeFilterBanner
                    }

                    // Model families list
                    modelFamiliesList

                    // Storage section
                    storageSection

                    // Footer
                    MLXModelsFooterView()
                }
                .padding()
            }
            .navigationTitle("On-Device Models")
            .navigationDestination(for: MLXModelFamily.self) { family in
                MLXModelFamilyDetailView(family: family)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        Button(action: { showImportSheet = true }) {
                            Label("Import from HuggingFace", systemImage: "square.and.arrow.down")
                        }

                        MLXTagFilterMenu(selectedTag: $selectedTagFilter)
                    }
                }
            }
            .confirmationDialog(
                "Delete All Models",
                isPresented: $showDeleteAllConfirmation
            ) {
                Button("Delete All", role: .destructive) {
                    Task {
                        try? await downloadManager.deleteAllModels()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete all downloaded models? This will free up \(downloadManager.formattedStorageUsed) of storage. This action cannot be undone.")
            }
            .sheet(isPresented: $showImportSheet) {
                HuggingFaceImportSheet()
            }
            .task {
                await downloadManager.refreshInstalledStates()
            }
            .refreshable {
                await downloadManager.refreshInstalledStates()
            }
        }
    }

    // MARK: - Search Bar (single, unified)

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search models...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - System Recommendation Banner

    private var systemRecommendationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "memorychip")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(SystemMemory.recommendationText)
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

    // MARK: - Info Header

    private var infoHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "apple.logo")
                    .font(.largeTitle)
                    .foregroundStyle(.primary)
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("On-Device AI with MLX")
                        .font(.headline)

                    Text("Run powerful models directly on Apple Silicon")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Download and run AI models locally. No internet required after download, no API costs, complete privacy. Your data never leaves your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            FeaturePills(features: [
                ("Private", "lock.shield.fill", .green),
                ("Offline", "wifi.slash", .blue),
                ("Free", "dollarsign.circle.fill", .orange),
                ("Fast", "bolt.fill", .purple)
            ])
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Active Filter Banner

    private var activeFilterBanner: some View {
        HStack {
            MLXTagBadge(tag: selectedTagFilter!)
            Text("filter active")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Clear") {
                selectedTagFilter = nil
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedTagFilter!.color.opacity(0.1))
        )
    }

    // MARK: - Model Families List

    private var modelFamiliesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Model Families",
                subtitle: "\(MLXModelCatalog.families.count) families available"
            )

            if filteredFamilies.isEmpty {
                MLXEmptyStateView(hasFilter: selectedTagFilter != nil || !searchText.isEmpty)
            } else {
                ForEach(filteredFamilies) { family in
                    MLXModelFamilyRow(
                        family: family,
                        downloadedCount: downloadManager.downloadedCount(for: family),
                        onSelect: {
                            navigationPath.append(family)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Storage",
                subtitle: "Manage downloaded models",
                systemImage: "externaldrive"
            )

            MLXStorageInfoView(
                storageUsed: downloadManager.totalStorageUsed,
                onOpenInFinder: {
                    #if os(macOS)
                    downloadManager.openInFinder()
                    #endif
                },
                onDeleteAll: {
                    showDeleteAllConfirmation = true
                }
            )
        }
    }
}

// MARK: - Model Family Detail View

/// Detail view showing all variants in a model family
struct MLXModelFamilyDetailView: View {
    let family: MLXModelFamily
    @State private var downloadManager = MLXModelDownloadManager.shared
    @State private var showDeleteConfirmation = false
    @State private var variantToDelete: MLXModelVariant?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Family header
                familyHeader

                // Variants list
                VStack(alignment: .leading, spacing: 12) {
                    Text("Available Models")
                        .font(.headline)

                    ForEach(family.variants) { variant in
                        MLXModelVariantRow(
                            variant: variant,
                            state: downloadManager.state(for: variant),
                            onDownload: {
                                Task {
                                    try? await downloadManager.downloadModel(variant)
                                }
                            },
                            onDelete: {
                                variantToDelete = variant
                                showDeleteConfirmation = true
                            }
                        )
                    }
                }
            }
            .padding()
        }
        .navigationTitle(family.displayName)
        .confirmationDialog(
            "Delete Model",
            isPresented: $showDeleteConfirmation,
            presenting: variantToDelete
        ) { variant in
            Button("Delete", role: .destructive) {
                Task {
                    try? await downloadManager.deleteModel(variant)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { variant in
            Text("Delete \(variant.displayName)? This will free up \(variant.formattedSize) of storage.")
        }
        .task {
            await downloadManager.refreshInstalledStates()
        }
    }

    private var familyHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: family.icon)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, height: 60)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(family.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)

                        ForEach(family.tags.prefix(2)) { tag in
                            MLXTagBadge(tag: tag)
                        }
                    }

                    Text("by \(family.provider)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(family.description)
                .font(.body)
                .foregroundStyle(.secondary)

            // Stats
            HStack(spacing: 16) {
                Label("\(family.variants.count) models", systemImage: "square.stack.3d.up")
                Label("\(downloadManager.downloadedCount(for: family)) installed", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("MLX Models View") {
    MLXModelsView()
}

#Preview("Model Family Detail") {
    NavigationStack {
        MLXModelFamilyDetailView(family: MLXModelCatalog.qwen)
    }
}

// MARK: - HuggingFace Import Sheet

/// Sheet for importing MLX models from HuggingFace by pasting a model ID
struct HuggingFaceImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var modelId: String = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var modelInfo: HFModelInfo?
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadManager = MLXModelDownloadManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import from HuggingFace")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Instructions
                    instructionsSection

                    // Model ID input
                    modelIdInputSection

                    // Validation result
                    if let info = modelInfo {
                        modelInfoSection(info)
                    }

                    // Error display
                    if let error = validationError {
                        errorSection(error)
                    }

                    // Popular MLX models
                    popularModelsSection
                }
                .padding()
            }
        }
        .frame(width: 550, height: 600)
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "text.page.badge.magnifyingglass")
                    .font(.title)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Paste a HuggingFace Model ID")
                        .font(.headline)

                    Text("Copy the model ID from any HuggingFace MLX model page")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Example: `mlx-community/Qwen2.5-7B-Instruct-4bit` or paste a full URL")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 48)
        }
    }

    // MARK: - Model ID Input

    private var modelIdInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)

                TextField("mlx-community/model-name or HuggingFace URL", text: $modelId)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await validateModel() }
                    }

                if isValidating {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if !modelId.isEmpty {
                    Button("Validate") {
                        Task { await validateModel() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Paste from clipboard button
            Button(action: pasteFromClipboard) {
                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Model Info Section

    private func modelInfoSection(_ info: HFModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Valid MLX Model Found")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(info.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Spacer()

                    if let size = info.size {
                        Text(size)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                if let description = info.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: 16) {
                    if let downloads = info.downloads {
                        Label("\(downloads) downloads", systemImage: "arrow.down.circle")
                    }
                    if let likes = info.likes {
                        Label("\(likes) likes", systemImage: "heart")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // System recommendation
                if let sizeGB = info.sizeGB {
                    let recommended = SystemMemory.isRecommended(modelSizeGB: sizeGB)
                    HStack {
                        Image(systemName: recommended ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(recommended ? .green : .orange)
                        Text(recommended ? "Recommended for your system" : "May be slow on your system (\(SystemMemory.totalMemoryGB)GB RAM)")
                            .font(.caption)
                            .foregroundStyle(recommended ? .green : .orange)
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Download button
            if isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: downloadProgress)
                    Text("Downloading... \(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(action: { Task { await downloadModel(info) } }) {
                    Label("Download Model", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Popular Models Section

    private var popularModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular MLX Models")
                .font(.headline)

            let popularModels = [
                ("mlx-community/Qwen2.5-7B-Instruct-4bit", "Qwen 2.5 7B", "Great all-rounder, 4-bit quantized"),
                ("mlx-community/Llama-3.2-3B-Instruct-4bit", "Llama 3.2 3B", "Fast and efficient"),
                ("mlx-community/Mistral-7B-Instruct-v0.3-4bit", "Mistral 7B", "Strong reasoning"),
                ("mlx-community/DeepSeek-Coder-V2-Lite-Instruct-4bit", "DeepSeek Coder", "Optimized for code"),
            ]

            ForEach(popularModels, id: \.0) { model in
                Button(action: {
                    modelId = model.0
                    Task { await validateModel() }
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.1)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(model.2)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func pasteFromClipboard() {
        #if os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) {
            modelId = extractModelId(from: string)
            Task { await validateModel() }
        }
        #endif
    }

    private func extractModelId(from input: String) -> String {
        // Handle full HuggingFace URLs
        if input.contains("huggingface.co/") {
            let components = input.components(separatedBy: "huggingface.co/")
            if let path = components.last {
                // Remove any query params or trailing slashes
                return path.components(separatedBy: "?").first?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? path
            }
        }
        return input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validateModel() async {
        guard !modelId.isEmpty else { return }

        isValidating = true
        validationError = nil
        modelInfo = nil

        let cleanId = extractModelId(from: modelId)

        // Call HuggingFace API to validate
        let urlString = "https://huggingface.co/api/models/\(cleanId)"
        guard let url = URL(string: urlString) else {
            validationError = "Invalid model ID format"
            isValidating = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                validationError = "Invalid response"
                isValidating = false
                return
            }

            if httpResponse.statusCode == 404 {
                validationError = "Model not found on HuggingFace"
                isValidating = false
                return
            }

            if httpResponse.statusCode != 200 {
                validationError = "HuggingFace returned error: \(httpResponse.statusCode)"
                isValidating = false
                return
            }

            // Parse response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check if it's an MLX model
                let tags = json["tags"] as? [String] ?? []
                let isMLX = tags.contains("mlx") || cleanId.lowercased().contains("mlx")

                if !isMLX {
                    validationError = "This model is not an MLX model. Look for models in the mlx-community organization."
                    isValidating = false
                    return
                }

                let modelName = (json["modelId"] as? String)?.components(separatedBy: "/").last ?? cleanId
                let downloads = json["downloads"] as? Int
                let likes = json["likes"] as? Int

                // Try to get size from siblings/files
                var sizeString: String?
                var sizeGB: Double?
                if let siblings = json["siblings"] as? [[String: Any]] {
                    let totalSize = siblings.compactMap { $0["size"] as? Int }.reduce(0, +)
                    if totalSize > 0 {
                        sizeGB = Double(totalSize) / (1024 * 1024 * 1024)
                        sizeString = String(format: "%.1f GB", sizeGB!)
                    }
                }

                modelInfo = HFModelInfo(
                    id: cleanId,
                    name: modelName,
                    description: json["description"] as? String,
                    downloads: downloads,
                    likes: likes,
                    size: sizeString,
                    sizeGB: sizeGB
                )
            }
        } catch {
            validationError = "Failed to validate: \(error.localizedDescription)"
        }

        isValidating = false
    }

    private func downloadModel(_ info: HFModelInfo) async {
        isDownloading = true
        downloadProgress = 0

        // Simulate download progress (in production, use actual download manager)
        for i in 1...100 {
            try? await Task.sleep(for: .milliseconds(50))
            downloadProgress = Double(i) / 100.0
        }

        isDownloading = false
        dismiss()
    }
}

// MARK: - HuggingFace Model Info

struct HFModelInfo {
    let id: String
    let name: String
    let description: String?
    let downloads: Int?
    let likes: Int?
    let size: String?
    let sizeGB: Double?
}

#Preview("HuggingFace Import") {
    HuggingFaceImportSheet()
}
