//
//  MLXModelsSubviews.swift
//  Envoy
//
//  Beautiful UI components for the MLX models browser.
//

import SwiftUI

// MARK: - Tag Badge

/// A small colored badge for model tags
struct MLXTagBadge: View {
    let tag: MLXModelTag

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tag.icon)
                .font(.caption2)
            Text(tag.rawValue)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tag.color.opacity(0.2))
        .foregroundColor(tag.color)
        .clipShape(Capsule())
        .accessibilityLabel("\(tag.rawValue) tag")
    }
}

// MARK: - Model Family Row

/// Row displaying an MLX model family with icon, description, and download count
struct MLXModelFamilyRow: View {
    let family: MLXModelFamily
    let downloadedCount: Int
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: family.icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    // Title with tags
                    HStack(spacing: 6) {
                        Text(family.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        ForEach(family.tags.prefix(2)) { tag in
                            MLXTagBadge(tag: tag)
                        }
                    }

                    // Description
                    Text(family.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    // Provider and model count
                    HStack(spacing: 8) {
                        Text(family.provider)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text("•")
                            .foregroundStyle(.tertiary)

                        Text("\(family.variants.count) models")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if downloadedCount > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)

                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                Text("\(downloadedCount) installed")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.green)
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel("\(family.displayName), \(family.variants.count) models, \(downloadedCount) downloaded")
        .accessibilityHint("Double tap to view model variants")
    }
}

// MARK: - Model Variant Row

/// Row displaying a specific model variant with download/delete actions
struct MLXModelVariantRow: View {
    let variant: MLXModelVariant
    let state: MLXDownloadState
    let onDownload: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    private var hasEnoughRAM: Bool {
        MLXModelDownloadManager.systemRAMGB >= variant.minimumRAMGB
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    // Title with tags
                    HStack(spacing: 6) {
                        Text(variant.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        ForEach(variant.tags.prefix(3)) { tag in
                            MLXTagBadge(tag: tag)
                        }
                    }

                    // Description
                    Text(variant.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)

                    // Size and RAM requirement
                    HStack(spacing: 12) {
                        Label(formattedSize, systemImage: "externaldrive")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Label("\(variant.minimumRAMGB)GB RAM", systemImage: "memorychip")
                            .font(.caption2)
                            .foregroundColor(hasEnoughRAM ? .secondary : .orange)
                    }

                    if !hasEnoughRAM {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("Your Mac has \(MLXModelDownloadManager.systemRAMGB)GB RAM. This model requires \(variant.minimumRAMGB)GB.")
                                .font(.caption2)
                        }
                        .foregroundStyle(.orange)
                    }
                }

                Spacer()

                // Action button based on state
                actionButton
            }

            // Progress bar when downloading
            if case .downloading(let progress) = state {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)

                    HStack {
                        Text("Downloading...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                    }
                }
                .accessibilityLabel("Downloading \(Int(progress * 100)) percent complete")
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

    private var formattedSize: String {
        switch state {
        case .downloaded(let sizeBytes):
            return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        default:
            return variant.formattedSize
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state {
        case .notDownloaded:
            Button(action: onDownload) {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!hasEnoughRAM)
            .accessibilityHint(hasEnoughRAM ? "Download this model" : "Not enough RAM to run this model")

        case .downloading:
            Button(action: {}) {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Downloading")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)

        case .downloaded:
            HStack(spacing: 8) {
                // Installed badge
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Installed")
                }
                .font(.caption)
                .foregroundStyle(.green)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Delete model")
            }

        case .error(let message):
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Error")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Download failed")

                Button(action: onDownload) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .accessibilityLabel("Download failed: \(message). Double tap to retry.")
        }
    }
}

// MARK: - Storage Info View

/// Shows storage usage and management options
struct MLXStorageInfoView: View {
    let storageUsed: Int64
    let onOpenInFinder: () -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Storage used row
            HStack {
                Label("Storage Used", systemImage: "externaldrive.fill")
                    .font(.subheadline)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Storage used: \(ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file))")

            // System RAM info
            HStack {
                Label("System RAM", systemImage: "memorychip")
                    .font(.subheadline)
                Spacer()
                Text("\(MLXModelDownloadManager.systemRAMGB) GB")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Actions
            HStack {
                #if os(macOS)
                Button(action: onOpenInFinder) {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                #endif

                Spacer()

                if storageUsed > 0 {
                    Button(role: .destructive, action: onDeleteAll) {
                        Label("Delete All", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
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

// MARK: - Tag Filter Menu

/// Menu for filtering models by tag
struct MLXTagFilterMenu: View {
    @Binding var selectedTag: MLXModelTag?

    var body: some View {
        Menu {
            Button {
                selectedTag = nil
            } label: {
                HStack {
                    Text("All Models")
                    if selectedTag == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(MLXModelCatalog.usedTags) { tag in
                Button {
                    selectedTag = tag
                } label: {
                    HStack {
                        Image(systemName: tag.icon)
                        Text(tag.rawValue)
                        if selectedTag == tag {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                if let tag = selectedTag {
                    MLXTagBadge(tag: tag)
                }
            }
        }
        .accessibilityLabel("Filter by tag")
        .accessibilityHint(selectedTag == nil ? "No filter applied" : "Filtering by \(selectedTag!.rawValue)")
    }
}

// MARK: - Tag Filter Chips

/// Horizontal scrolling tag filter chips
struct MLXTagFilterChips: View {
    @Binding var selectedTag: MLXModelTag?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All button
                Button {
                    selectedTag = nil
                } label: {
                    Text("All")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTag == nil ? Color.accentColor : Color.secondary.opacity(0.2))
                        .foregroundColor(selectedTag == nil ? .white : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Tag buttons
                ForEach(MLXModelCatalog.usedTags) { tag in
                    Button {
                        selectedTag = tag
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tag.icon)
                                .font(.caption2)
                            Text(tag.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTag == tag ? tag.color : tag.color.opacity(0.2))
                        .foregroundColor(selectedTag == tag ? .white : tag.color)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Empty State View

/// Empty state when no models match filters
struct MLXEmptyStateView: View {
    let hasFilter: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasFilter ? "line.3.horizontal.decrease.circle" : "square.stack.3d.down.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text(hasFilter ? "No Models Match Filter" : "No Models Available")
                .font(.headline)
                .foregroundColor(.secondary)

            Text(hasFilter ? "Try selecting a different filter or clearing the search." : "Check your network connection and try again.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Footer View

/// Footer with legal and attribution info
struct MLXModelsFooterView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On-device AI models may produce inaccurate or incomplete responses. Please verify critical information.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Text("Models are provided by")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Link("huggingface.co", destination: URL(string: "https://huggingface.co")!)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding()
    }
}

// MARK: - Previews

#Preview("Tag Badges") {
    HStack {
        MLXTagBadge(tag: .new)
        MLXTagBadge(tag: .vision)
        MLXTagBadge(tag: .thinking)
        MLXTagBadge(tag: .recommended)
        MLXTagBadge(tag: .code)
    }
    .padding()
}

#Preview("Model Family Row") {
    MLXModelFamilyRow(
        family: MLXModelCatalog.qwen,
        downloadedCount: 2,
        onSelect: {}
    )
    .padding()
}

#Preview("Model Variant Row - Not Downloaded") {
    MLXModelVariantRow(
        variant: MLXModelCatalog.qwen.variants[3],
        state: .notDownloaded,
        onDownload: {},
        onDelete: {}
    )
    .padding()
}

#Preview("Model Variant Row - Downloading") {
    MLXModelVariantRow(
        variant: MLXModelCatalog.qwen.variants[3],
        state: .downloading(progress: 0.45),
        onDownload: {},
        onDelete: {}
    )
    .padding()
}

#Preview("Model Variant Row - Downloaded") {
    MLXModelVariantRow(
        variant: MLXModelCatalog.qwen.variants[3],
        state: .downloaded(sizeBytes: 4_500_000_000),
        onDownload: {},
        onDelete: {}
    )
    .padding()
}

#Preview("Storage Info") {
    MLXStorageInfoView(
        storageUsed: 12_500_000_000,
        onOpenInFinder: {},
        onDeleteAll: {}
    )
    .padding()
}

#Preview("Tag Filter Chips") {
    @Previewable @State var selectedTag: MLXModelTag? = nil
    MLXTagFilterChips(selectedTag: $selectedTag)
        .padding()
}
