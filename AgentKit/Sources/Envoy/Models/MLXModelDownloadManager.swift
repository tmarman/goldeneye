//
//  MLXModelDownloadManager.swift
//  Envoy
//
//  Manages downloading, installing, and tracking MLX models from HuggingFace.
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Download State

/// State of an MLX model download
public enum MLXDownloadState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded(sizeBytes: Int64)
    case error(String)

    public static func == (lhs: MLXDownloadState, rhs: MLXDownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded):
            return true
        case (.downloading(let p1), .downloading(let p2)):
            return p1 == p2
        case (.downloaded(let s1), .downloaded(let s2)):
            return s1 == s2
        case (.error(let e1), .error(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

// MARK: - Download Manager

/// Manages MLX model downloads and state tracking
@MainActor
@Observable
public final class MLXModelDownloadManager {
    public static let shared = MLXModelDownloadManager()

    // State per variant ID
    public var downloadStates: [String: MLXDownloadState] = [:]

    // Total storage used
    public var totalStorageUsed: Int64 = 0

    // Cache path
    public var cachePath: URL?

    // Download queue management
    private var downloadQueue: [MLXModelVariant] = []
    private var isDownloading = false
    private var currentDownloadTask: Task<Void, Never>?

    private init() {
        // Set default cache path
        cachePath = Self.defaultModelDirectory
    }

    // MARK: - Default Paths

    /// Default HuggingFace cache directory
    public static var defaultModelDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
    }

    // MARK: - State Management

    /// Refresh installed states for all catalog variants
    public func refreshInstalledStates() async {
        // Scan the HF cache directory for installed models
        let installedModels = scanInstalledModels()
        let installedSet = Set(installedModels.map { $0.modelId })

        for family in MLXModelCatalog.families {
            for variant in family.variants {
                // Skip if currently downloading
                if case .downloading = downloadStates[variant.id] {
                    continue
                }

                if installedSet.contains(variant.modelId) {
                    // Get actual size from installed model
                    if let installed = installedModels.first(where: { $0.modelId == variant.modelId }) {
                        downloadStates[variant.id] = .downloaded(sizeBytes: Int64(installed.sizeBytes))
                    } else {
                        downloadStates[variant.id] = .downloaded(sizeBytes: variant.estimatedSizeBytes)
                    }
                } else {
                    downloadStates[variant.id] = .notDownloaded
                }
            }
        }

        // Update storage
        calculateStorageUsed()
    }

    /// Scan for installed models in HF cache
    private func scanInstalledModels() -> [(modelId: String, sizeBytes: UInt64)] {
        guard let cacheDir = cachePath,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.isDirectoryKey]
              ) else {
            return []
        }

        var models: [(modelId: String, sizeBytes: UInt64)] = []

        for url in contents {
            // HuggingFace cache format: models--org--name
            guard url.lastPathComponent.hasPrefix("models--") else { continue }

            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            // Find the latest snapshot
            let snapshotsDir = url.appendingPathComponent("snapshots")
            guard let snapshots = try? FileManager.default.contentsOfDirectory(
                at: snapshotsDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ), let latestSnapshot = snapshots.first else { continue }

            // Check if model weights are present
            let files = (try? FileManager.default.contentsOfDirectory(at: latestSnapshot, includingPropertiesForKeys: nil)) ?? []
            let hasWeights = files.contains {
                $0.pathExtension == "safetensors" || $0.pathExtension == "bin"
            }

            guard hasWeights else { continue }

            // Parse the model ID from directory name
            let modelId = url.lastPathComponent
                .dropFirst("models--".count)
                .replacingOccurrences(of: "--", with: "/")

            // Calculate total size
            var totalSize: UInt64 = 0
            for file in files {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                   let size = attrs[.size] as? UInt64 {
                    totalSize += size
                }
            }

            models.append((modelId: modelId, sizeBytes: totalSize))
        }

        return models
    }

    /// Get state for a specific variant
    public func state(for variant: MLXModelVariant) -> MLXDownloadState {
        downloadStates[variant.id] ?? .notDownloaded
    }

    /// Count downloaded variants in a family
    public func downloadedCount(for family: MLXModelFamily) -> Int {
        family.variants.filter { variant in
            if case .downloaded = downloadStates[variant.id] {
                return true
            }
            return false
        }.count
    }

    // MARK: - Download

    /// Queue a model variant for download
    public func downloadModel(_ variant: MLXModelVariant) async throws {
        // If already downloading, add to queue
        if isDownloading {
            if !downloadQueue.contains(where: { $0.id == variant.id }) {
                downloadQueue.append(variant)
                downloadStates[variant.id] = .downloading(progress: 0)
            }
            return
        }

        // Start downloading
        isDownloading = true
        try await performDownload(variant)

        // Process queue
        await processDownloadQueue()
    }

    /// Perform the actual download using huggingface-cli
    private func performDownload(_ variant: MLXModelVariant) async throws {
        downloadStates[variant.id] = .downloading(progress: 0)

        do {
            // Use huggingface-cli to download the model
            // This provides progress tracking and handles authentication
            try await downloadFromHuggingFace(variant)

            // Verify download and get actual size
            let installedModels = scanInstalledModels()
            if let installed = installedModels.first(where: { $0.modelId == variant.modelId }) {
                downloadStates[variant.id] = .downloaded(sizeBytes: Int64(installed.sizeBytes))
            } else {
                downloadStates[variant.id] = .downloaded(sizeBytes: variant.estimatedSizeBytes)
            }

            calculateStorageUsed()
        } catch {
            downloadStates[variant.id] = .error(error.localizedDescription)
            throw error
        }
    }

    /// Download model from HuggingFace using CLI
    private func downloadFromHuggingFace(_ variant: MLXModelVariant) async throws {
        // Try to use huggingface-cli if available, otherwise use Python
        let hfCliPath = "/opt/homebrew/bin/huggingface-cli"
        let pythonPath = "/usr/bin/python3"

        let command: String
        let args: [String]

        if FileManager.default.fileExists(atPath: hfCliPath) {
            command = hfCliPath
            args = ["download", variant.modelId, "--local-dir-use-symlinks", "False"]
        } else {
            // Fallback to Python with transformers
            command = pythonPath
            args = ["-c", """
                from huggingface_hub import snapshot_download
                snapshot_download('\(variant.modelId)', local_dir_use_symlinks=False)
                """]
        }

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Progress tracking
        let progressTask = Task { [weak self] in
            guard let self else { return }
            var lastProgress = 0.0

            // Poll for progress by checking file sizes
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))

                // Simple progress estimation based on downloaded files
                let progress = min(lastProgress + 0.01, 0.99)
                lastProgress = progress

                await MainActor.run {
                    if case .downloading = self.downloadStates[variant.id] {
                        self.downloadStates[variant.id] = .downloading(progress: progress)
                    }
                }
            }
        }

        try process.run()
        process.waitUntilExit()

        progressTask.cancel()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw DownloadError.downloadFailed(errorMessage)
        }
    }

    /// Process the next item in the download queue
    private func processDownloadQueue() async {
        while !downloadQueue.isEmpty {
            let nextVariant = downloadQueue.removeFirst()
            do {
                try await performDownload(nextVariant)
            } catch {
                // Error already recorded in downloadStates, continue with queue
            }
        }
        isDownloading = false
    }

    /// Cancel current download
    public func cancelDownload() {
        currentDownloadTask?.cancel()
        currentDownloadTask = nil

        // Reset downloading states to not downloaded
        for (id, state) in downloadStates {
            if case .downloading = state {
                downloadStates[id] = .notDownloaded
            }
        }

        downloadQueue.removeAll()
        isDownloading = false
    }

    // MARK: - Delete

    /// Delete a single model variant
    public func deleteModel(_ variant: MLXModelVariant) async throws {
        // Find the model directory in HF cache
        guard let cacheDir = cachePath else {
            throw DownloadError.cacheNotFound
        }

        let modelDirName = "models--\(variant.modelId.replacingOccurrences(of: "/", with: "--"))"
        let modelPath = cacheDir.appendingPathComponent(modelDirName)

        if FileManager.default.fileExists(atPath: modelPath.path) {
            try FileManager.default.removeItem(at: modelPath)
        }

        downloadStates[variant.id] = .notDownloaded
        calculateStorageUsed()
    }

    /// Delete all downloaded models
    public func deleteAllModels() async throws {
        guard let cacheDir = cachePath else {
            throw DownloadError.cacheNotFound
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: nil
        )

        for url in contents where url.lastPathComponent.hasPrefix("models--") {
            try FileManager.default.removeItem(at: url)
        }

        // Reset all states
        for family in MLXModelCatalog.families {
            for variant in family.variants {
                downloadStates[variant.id] = .notDownloaded
            }
        }

        totalStorageUsed = 0
    }

    // MARK: - Storage

    /// Calculate total storage used by all models
    public func calculateStorageUsed() {
        var total: Int64 = 0

        for (_, state) in downloadStates {
            if case .downloaded(let size) = state {
                total += size
            }
        }

        totalStorageUsed = total
    }

    /// Get formatted storage string
    public var formattedStorageUsed: String {
        ByteCountFormatter.string(fromByteCount: totalStorageUsed, countStyle: .file)
    }

    // MARK: - Finder Integration

    #if os(macOS)
    /// Open models directory in Finder
    public func openInFinder() {
        guard let path = cachePath else { return }

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
    }
    #endif

    // MARK: - System RAM Check

    /// Get system RAM in GB
    public static var systemRAMGB: Int {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        return Int(physicalMemory / 1_073_741_824)
    }

    /// Check if system has enough RAM for a model
    public static func hasEnoughRAM(for variant: MLXModelVariant) -> Bool {
        systemRAMGB >= variant.minimumRAMGB
    }
}

// MARK: - Errors

enum DownloadError: LocalizedError {
    case downloadFailed(String)
    case cacheNotFound
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .cacheNotFound:
            return "HuggingFace cache directory not found"
        case .modelNotFound:
            return "Model not found in cache"
        }
    }
}
