//
//  DemoDataManager.swift
//  Envoy
//
//  Manages demo data loading from configurable paths.
//  Allows pointing to different data folders for demos, testing, or production.
//

import AgentKit
import Foundation

/// Manager for loading and managing demo data from configurable paths
@MainActor
public final class DemoDataManager: ObservableObject {
    public static let shared = DemoDataManager()

    // MARK: - Configuration

    /// Whether demo mode is enabled (loads from demo folder instead of default)
    @Published public var isDemoMode: Bool = false

    /// Custom base path for demo data (nil = use default app data path)
    @Published public var demoBasePath: URL?

    /// Current data path being used
    public var currentDataPath: URL {
        if isDemoMode, let demoPath = demoBasePath {
            return demoPath
        }
        return defaultDataPath
    }

    /// Default data path (~/Library/Application Support/Envoy)
    private var defaultDataPath: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Envoy", isDirectory: true)
    }

    private init() {
        // Check for demo mode environment variable
        if ProcessInfo.processInfo.environment["ENVOY_DEMO_MODE"] == "1" {
            isDemoMode = true
        }

        // Check for custom demo path environment variable
        if let pathString = ProcessInfo.processInfo.environment["ENVOY_DEMO_PATH"],
           !pathString.isEmpty {
            demoBasePath = URL(fileURLWithPath: pathString)
            isDemoMode = true
        }
    }

    // MARK: - Data Loading

    /// Load threads from the data folder
    public func loadThreads() async -> [AgentKit.Thread] {
        let threadsPath = currentDataPath.appendingPathComponent("threads.json")

        guard FileManager.default.fileExists(atPath: threadsPath.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: threadsPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([AgentKit.Thread].self, from: data)
        } catch {
            print("Failed to load threads: \(error)")
            return []
        }
    }

    /// Save threads to the data folder
    public func saveThreads(_ threads: [AgentKit.Thread]) async {
        let threadsPath = currentDataPath.appendingPathComponent("threads.json")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: currentDataPath, withIntermediateDirectories: true)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(threads)
            try data.write(to: threadsPath)
        } catch {
            print("Failed to save threads: \(error)")
        }
    }

    /// Load documents from the data folder
    public func loadDocuments() async -> [Document] {
        let documentsPath = currentDataPath.appendingPathComponent("documents.json")

        guard FileManager.default.fileExists(atPath: documentsPath.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: documentsPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Document].self, from: data)
        } catch {
            print("Failed to load documents: \(error)")
            return []
        }
    }

    // MARK: - Demo Data Generation

    /// Initialize a demo data folder with empty data files
    public func initializeDemoFolder(at path: URL) async throws {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        // Create empty conversations file
        let conversationsPath = path.appendingPathComponent("conversations.json")
        try "[]".data(using: .utf8)?.write(to: conversationsPath)

        // Create empty documents file
        let documentsPath = path.appendingPathComponent("documents.json")
        try "[]".data(using: .utf8)?.write(to: documentsPath)

        print("Initialized demo folder at: \(path.path)")
    }
}
