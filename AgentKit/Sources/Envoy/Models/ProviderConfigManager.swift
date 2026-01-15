//
//  ProviderConfigManager.swift
//  Envoy
//
//  Unified manager for all LLM provider configurations.
//  Supports MLX, Ollama, LM Studio, OpenAI, Anthropic, and more.
//

import Foundation
import SwiftUI

// MARK: - Provider Type

/// Types of LLM providers supported
public enum ProviderType: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleFoundation = "Apple Foundation"
    case mlx = "MLX"
    case ollama = "Ollama"
    case lmStudio = "LM Studio"
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case googleAI = "Google AI"
    case openRouter = "OpenRouter"
    case custom = "Custom"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .appleFoundation: return "apple.intelligence"
        case .mlx: return "apple.logo"
        case .ollama: return "cube"
        case .lmStudio: return "laptopcomputer"
        case .openai: return "brain.head.profile"
        case .anthropic: return "sparkles"
        case .googleAI: return "globe"
        case .openRouter: return "arrow.triangle.branch"
        case .custom: return "server.rack"
        }
    }

    public var color: Color {
        switch self {
        case .appleFoundation: return Color(red: 0.4, green: 0.6, blue: 1.0) // Apple Intelligence blue
        case .mlx: return .gray
        case .ollama: return .white
        case .lmStudio: return .blue
        case .openai: return .green
        case .anthropic: return .orange
        case .googleAI: return .blue
        case .openRouter: return .purple
        case .custom: return .secondary
        }
    }

    public var description: String {
        switch self {
        case .appleFoundation: return "Apple Intelligence models (on-device)"
        case .mlx: return "Run models locally on Apple Silicon"
        case .ollama: return "Local models via Ollama server"
        case .lmStudio: return "Local models via LM Studio"
        case .openai: return "GPT-4, GPT-3.5, and more"
        case .anthropic: return "Claude Sonnet, Opus, Haiku"
        case .googleAI: return "Gemini Pro, Flash, and more"
        case .openRouter: return "Access many models via one API"
        case .custom: return "Custom OpenAI-compatible endpoint"
        }
    }

    public var requiresAPIKey: Bool {
        switch self {
        case .appleFoundation, .mlx, .ollama, .lmStudio:
            return false
        case .openai, .anthropic, .googleAI, .openRouter, .custom:
            return true
        }
    }

    public var requiresServerURL: Bool {
        switch self {
        case .ollama, .lmStudio, .custom:
            return true
        case .appleFoundation, .mlx, .openai, .anthropic, .googleAI, .openRouter:
            return false
        }
    }

    public var defaultServerURL: String? {
        switch self {
        case .ollama: return "http://localhost:11434"
        case .lmStudio: return "http://localhost:1234"
        default: return nil
        }
    }

    /// Whether this provider runs completely on-device (private)
    public var isOnDevice: Bool {
        switch self {
        case .appleFoundation, .mlx:
            return true
        default:
            return false
        }
    }
}

// MARK: - Provider Configuration

/// Configuration for a specific provider instance
public struct ProviderConfig: Identifiable, Codable, Sendable {
    public let id: UUID
    public var type: ProviderType
    public var name: String
    public var isEnabled: Bool
    public var apiKey: String?
    public var serverURL: String?
    public var selectedModel: String?
    public var availableModels: [String]
    public var createdAt: Date
    public var lastUsed: Date?

    public init(
        id: UUID = UUID(),
        type: ProviderType,
        name: String? = nil,
        isEnabled: Bool = true,
        apiKey: String? = nil,
        serverURL: String? = nil,
        selectedModel: String? = nil,
        availableModels: [String] = []
    ) {
        self.id = id
        self.type = type
        self.name = name ?? type.rawValue
        self.isEnabled = isEnabled
        self.apiKey = apiKey
        self.serverURL = serverURL ?? type.defaultServerURL
        self.selectedModel = selectedModel
        self.availableModels = availableModels
        self.createdAt = Date()
        self.lastUsed = nil
    }

    /// Check if configuration is valid
    public var isValid: Bool {
        if type.requiresAPIKey && (apiKey?.isEmpty ?? true) {
            return false
        }
        if type.requiresServerURL && (serverURL?.isEmpty ?? true) {
            return false
        }
        return true
    }
}

// MARK: - Provider Status

/// Status of a provider connection
public enum ProviderStatus: Equatable, Sendable {
    case unknown
    case checking
    case available(modelCount: Int)
    case unavailable(reason: String)
    case error(String)
}

// MARK: - Provider Config Manager

/// Manages all provider configurations
@MainActor
@Observable
public final class ProviderConfigManager {
    public static let shared = ProviderConfigManager()

    /// All configured providers
    public var providers: [ProviderConfig] = []

    /// Status for each provider
    public var providerStatus: [UUID: ProviderStatus] = [:]

    /// Currently checking providers
    private var checkingProviders: Set<UUID> = []

    private let configURL: URL

    private init() {
        // Store in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let envoyDir = appSupport.appendingPathComponent("Envoy")
        try? FileManager.default.createDirectory(at: envoyDir, withIntermediateDirectories: true)
        configURL = envoyDir.appendingPathComponent("providers.json")

        loadConfigurations()
        setupDefaultProviders()
    }

    // MARK: - Default Providers

    private func setupDefaultProviders() {
        // Add default providers if none exist
        if providers.isEmpty {
            providers = [
                // MLX (always available on Apple Silicon)
                ProviderConfig(type: .mlx, name: "Local MLX Models"),

                // Ollama (common local setup)
                ProviderConfig(type: .ollama, name: "Ollama"),

                // Cloud providers (require API keys)
                ProviderConfig(type: .anthropic, name: "Anthropic Claude", isEnabled: false),
                ProviderConfig(type: .openai, name: "OpenAI GPT", isEnabled: false),
            ]
            saveConfigurations()
        }
    }

    // MARK: - Persistence

    private func loadConfigurations() {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }

        do {
            let data = try Data(contentsOf: configURL)
            providers = try JSONDecoder().decode([ProviderConfig].self, from: data)
        } catch {
            print("Failed to load provider configs: \(error)")
        }
    }

    private func saveConfigurations() {
        do {
            let data = try JSONEncoder().encode(providers)
            try data.write(to: configURL)
        } catch {
            print("Failed to save provider configs: \(error)")
        }
    }

    // MARK: - CRUD Operations

    /// Add a new provider
    public func addProvider(_ config: ProviderConfig) {
        providers.append(config)
        saveConfigurations()
    }

    /// Update an existing provider
    public func updateProvider(_ config: ProviderConfig) {
        if let index = providers.firstIndex(where: { $0.id == config.id }) {
            providers[index] = config
            saveConfigurations()
        }
    }

    /// Remove a provider
    public func removeProvider(_ id: UUID) {
        providers.removeAll { $0.id == id }
        providerStatus.removeValue(forKey: id)
        saveConfigurations()
    }

    /// Get provider by ID
    public func provider(for id: UUID) -> ProviderConfig? {
        providers.first { $0.id == id }
    }

    /// Get enabled providers
    public var enabledProviders: [ProviderConfig] {
        providers.filter { $0.isEnabled && $0.isValid }
    }

    // MARK: - Status Checking

    /// Check status of all providers
    public func checkAllProviders() async {
        for provider in providers where provider.isEnabled {
            await checkProvider(provider.id)
        }
    }

    /// Check status of a specific provider
    public func checkProvider(_ id: UUID) async {
        guard let provider = provider(for: id),
              !checkingProviders.contains(id) else { return }

        checkingProviders.insert(id)
        providerStatus[id] = .checking

        do {
            let status = try await checkProviderStatus(provider)
            providerStatus[id] = status
        } catch {
            providerStatus[id] = .error(error.localizedDescription)
        }

        checkingProviders.remove(id)
    }

    private func checkProviderStatus(_ provider: ProviderConfig) async throws -> ProviderStatus {
        switch provider.type {
        case .appleFoundation:
            // Check if Foundation Models is available on this device
            return await checkAppleFoundationStatus()

        case .mlx:
            // Check for cached MLX models
            let models = scanMLXModels()
            if models.isEmpty {
                return .unavailable(reason: "No models downloaded")
            }
            return .available(modelCount: models.count)

        case .ollama:
            return try await checkOllamaStatus(provider)

        case .lmStudio:
            return try await checkLMStudioStatus(provider)

        case .openai, .anthropic, .googleAI, .openRouter, .custom:
            // For API providers, just check if key is set
            if provider.apiKey?.isEmpty ?? true {
                return .unavailable(reason: "API key not set")
            }
            return .available(modelCount: 0)
        }
    }

    private func checkAppleFoundationStatus() async -> ProviderStatus {
        // Check for macOS 26+ and Apple Silicon
        #if os(macOS)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        if osVersion.majorVersion < 26 {
            return .unavailable(reason: "Requires macOS 26+")
        }

        // Check for Apple Silicon
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else {
            return .unavailable(reason: "Cannot detect hardware")
        }

        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let machineString = String(
            decoding: machine.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )

        if !machineString.hasPrefix("arm64") {
            return .unavailable(reason: "Requires Apple Silicon")
        }

        return .available(modelCount: 1)  // Apple Intelligence
        #else
        return .unavailable(reason: "Requires macOS 26+")
        #endif
    }

    private func scanMLXModels() -> [String] {
        let cacheDir = MLXModelDownloadManager.defaultModelDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return contents
            .filter { $0.lastPathComponent.hasPrefix("models--") }
            .map { $0.lastPathComponent }
    }

    private func checkOllamaStatus(_ provider: ProviderConfig) async throws -> ProviderStatus {
        guard let urlString = provider.serverURL,
              let url = URL(string: urlString) else {
            return .unavailable(reason: "Invalid server URL")
        }

        let tagsURL = url.appendingPathComponent("api/tags")
        let request = URLRequest(url: tagsURL, timeoutInterval: 5)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return .unavailable(reason: "Server not responding")
            }

            // Parse model list
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                return .available(modelCount: models.count)
            }

            return .available(modelCount: 0)
        } catch {
            return .unavailable(reason: "Cannot connect to Ollama")
        }
    }

    private func checkLMStudioStatus(_ provider: ProviderConfig) async throws -> ProviderStatus {
        guard let urlString = provider.serverURL,
              let url = URL(string: urlString) else {
            return .unavailable(reason: "Invalid server URL")
        }

        let modelsURL = url.appendingPathComponent("v1/models")
        let request = URLRequest(url: modelsURL, timeoutInterval: 5)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return .unavailable(reason: "Server not responding")
            }

            // Parse model list
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["data"] as? [[String: Any]] {
                return .available(modelCount: models.count)
            }

            return .available(modelCount: 0)
        } catch {
            return .unavailable(reason: "Cannot connect to LM Studio")
        }
    }

    // MARK: - Fetch Available Models

    /// Fetch available models for a provider
    public func fetchModels(for providerId: UUID) async -> [String] {
        guard let provider = provider(for: providerId) else { return [] }

        switch provider.type {
        case .appleFoundation:
            // Apple Intelligence is a single integrated model
            return ["Apple Intelligence"]

        case .mlx:
            return scanMLXModels()

        case .ollama:
            return await fetchOllamaModels(provider)

        case .lmStudio:
            return await fetchLMStudioModels(provider)

        case .openai:
            return [
                "gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4",
                "gpt-3.5-turbo", "o1-preview", "o1-mini"
            ]

        case .anthropic:
            return [
                "claude-opus-4-5-20251101", "claude-sonnet-4-5-20251101",
                "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022",
                "claude-3-opus-20240229", "claude-3-haiku-20240307"
            ]

        case .googleAI:
            return [
                "gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash",
                "gemini-1.0-pro"
            ]

        case .openRouter:
            return [
                "anthropic/claude-3.5-sonnet", "openai/gpt-4o",
                "google/gemini-pro", "meta-llama/llama-3.1-70b-instruct"
            ]

        case .custom:
            return provider.availableModels
        }
    }

    private func fetchOllamaModels(_ provider: ProviderConfig) async -> [String] {
        guard let urlString = provider.serverURL,
              let url = URL(string: urlString) else { return [] }

        let tagsURL = url.appendingPathComponent("api/tags")

        do {
            let (data, _) = try await URLSession.shared.data(from: tagsURL)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                return models.compactMap { $0["name"] as? String }
            }
        } catch {
            print("Failed to fetch Ollama models: \(error)")
        }

        return []
    }

    private func fetchLMStudioModels(_ provider: ProviderConfig) async -> [String] {
        guard let urlString = provider.serverURL,
              let url = URL(string: urlString) else { return [] }

        let modelsURL = url.appendingPathComponent("v1/models")

        do {
            let (data, _) = try await URLSession.shared.data(from: modelsURL)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["data"] as? [[String: Any]] {
                return models.compactMap { $0["id"] as? String }
            }
        } catch {
            print("Failed to fetch LM Studio models: \(error)")
        }

        return []
    }
}
