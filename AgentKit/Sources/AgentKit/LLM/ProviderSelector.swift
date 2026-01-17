import Foundation
import Logging

// MARK: - Provider Selector

/// Selects the best available LLM provider based on configuration and availability.
///
/// The ProviderSelector implements a fallback chain:
/// 1. **Apple Foundation Models** - Preferred when available (macOS 26+, Apple Silicon)
/// 2. **Ollama** - Local inference fallback (always available if running)
/// 3. **LM Studio** - Alternative local provider
/// 4. **Cloud providers** - Anthropic, OpenAI (requires API keys)
///
/// Usage:
/// ```swift
/// let selector = ProviderSelector()
/// let provider = await selector.selectProvider()
/// // provider is the best available option
/// ```
public actor ProviderSelector {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        /// Preferred provider order (first available wins)
        public var preferredOrder: [ProviderType]

        /// Ollama configuration
        public var ollamaURL: URL
        public var ollamaModel: String

        /// LM Studio configuration
        public var lmStudioURL: URL
        public var lmStudioModel: String

        /// Cloud API keys (optional)
        public var anthropicAPIKey: String?
        public var openAIAPIKey: String?

        /// Whether to allow cloud providers
        public var allowCloudProviders: Bool

        public static let `default` = Configuration(
            preferredOrder: [.foundationModels, .ollama, .lmStudio],
            ollamaURL: URL(string: "http://localhost:11434")!,
            ollamaModel: "llama3.1",
            lmStudioURL: URL(string: "http://localhost:1234")!,
            lmStudioModel: "default",
            anthropicAPIKey: nil,
            openAIAPIKey: nil,
            allowCloudProviders: false
        )

        public init(
            preferredOrder: [ProviderType] = [.foundationModels, .ollama, .lmStudio],
            ollamaURL: URL = URL(string: "http://localhost:11434")!,
            ollamaModel: String = "llama3.1",
            lmStudioURL: URL = URL(string: "http://localhost:1234")!,
            lmStudioModel: String = "default",
            anthropicAPIKey: String? = nil,
            openAIAPIKey: String? = nil,
            allowCloudProviders: Bool = false
        ) {
            self.preferredOrder = preferredOrder
            self.ollamaURL = ollamaURL
            self.ollamaModel = ollamaModel
            self.lmStudioURL = lmStudioURL
            self.lmStudioModel = lmStudioModel
            self.anthropicAPIKey = anthropicAPIKey
            self.openAIAPIKey = openAIAPIKey
            self.allowCloudProviders = allowCloudProviders
        }
    }

    public enum ProviderType: String, Sendable, CaseIterable {
        case foundationModels = "apple-foundation-models"
        case ollama = "ollama"
        case lmStudio = "lm-studio"
        case anthropic = "anthropic"
        case openai = "openai"

        public var displayName: String {
            switch self {
            case .foundationModels: return "Apple Intelligence"
            case .ollama: return "Ollama"
            case .lmStudio: return "LM Studio"
            case .anthropic: return "Claude (Anthropic)"
            case .openai: return "OpenAI"
            }
        }

        public var isLocal: Bool {
            switch self {
            case .foundationModels, .ollama, .lmStudio: return true
            case .anthropic, .openai: return false
            }
        }
    }

    // MARK: - Properties

    private let config: Configuration
    private var cachedProviders: [ProviderType: any LLMProvider] = [:]
    private var availabilityCache: [ProviderType: (available: Bool, checkedAt: Date)] = [:]
    private let logger = Logger(label: "AgentKit.ProviderSelector")

    /// Cache duration for availability checks
    private let cacheDuration: TimeInterval = 30

    // MARK: - Initialization

    public init(config: Configuration = .default) {
        self.config = config
    }

    // MARK: - Provider Selection

    /// Select the best available provider based on configuration
    public func selectProvider() async -> (any LLMProvider)? {
        for providerType in config.preferredOrder {
            // Skip cloud providers if not allowed
            if !providerType.isLocal && !config.allowCloudProviders {
                continue
            }

            // Check availability (with caching)
            if await isProviderAvailable(providerType) {
                let provider = getOrCreateProvider(providerType)
                logger.info("Selected provider", metadata: [
                    "type": "\(providerType.rawValue)",
                    "name": "\(provider.name)"
                ])
                return provider
            }
        }

        logger.warning("No providers available")
        return nil
    }

    /// Get a specific provider type (creates if needed)
    public func getProvider(_ type: ProviderType) -> (any LLMProvider)? {
        // Check if allowed
        if !type.isLocal && !config.allowCloudProviders {
            return nil
        }

        return getOrCreateProvider(type)
    }

    /// Check availability of all configured providers
    public func checkAvailability() async -> [ProviderType: Bool] {
        var results: [ProviderType: Bool] = [:]

        for providerType in config.preferredOrder {
            results[providerType] = await isProviderAvailable(providerType)
        }

        return results
    }

    /// Get detailed status of all providers
    public func getProviderStatus() async -> [ProviderStatus] {
        var statuses: [ProviderStatus] = []

        for providerType in ProviderType.allCases {
            let available = await isProviderAvailable(providerType)
            let provider = available ? getOrCreateProvider(providerType) : nil

            statuses.append(ProviderStatus(
                type: providerType,
                isAvailable: available,
                isConfigured: isConfigured(providerType),
                isPreferred: config.preferredOrder.contains(providerType),
                providerName: provider?.name
            ))
        }

        return statuses
    }

    // MARK: - Private Helpers

    private func isProviderAvailable(_ type: ProviderType) async -> Bool {
        // Check cache first
        if let cached = availabilityCache[type],
           Date().timeIntervalSince(cached.checkedAt) < cacheDuration {
            return cached.available
        }

        // Check if configured
        guard isConfigured(type) else {
            availabilityCache[type] = (false, Date())
            return false
        }

        // Actually check availability
        let provider = getOrCreateProvider(type)
        let available = await provider.isAvailable()

        availabilityCache[type] = (available, Date())

        logger.debug("Checked availability", metadata: [
            "provider": "\(type.rawValue)",
            "available": "\(available)"
        ])

        return available
    }

    private func isConfigured(_ type: ProviderType) -> Bool {
        switch type {
        case .foundationModels:
            return true  // Always "configured", availability check handles eligibility
        case .ollama:
            return true  // Uses default localhost
        case .lmStudio:
            return true  // Uses default localhost
        case .anthropic:
            return config.anthropicAPIKey != nil
        case .openai:
            return config.openAIAPIKey != nil
        }
    }

    private func getOrCreateProvider(_ type: ProviderType) -> any LLMProvider {
        if let cached = cachedProviders[type] {
            return cached
        }

        let provider: any LLMProvider

        switch type {
        case .foundationModels:
            provider = FoundationModelsProvider()

        case .ollama:
            provider = OllamaProvider(
                baseURL: config.ollamaURL,
                model: config.ollamaModel
            )

        case .lmStudio:
            // LMStudioProvider takes host/port, extract from URL
            let host = config.lmStudioURL.host ?? "localhost"
            let port = config.lmStudioURL.port ?? 1234
            provider = LMStudioProvider(
                host: host,
                port: port,
                defaultModel: config.lmStudioModel
            )

        case .anthropic:
            provider = AnthropicProvider(
                apiKey: config.anthropicAPIKey ?? "",
                model: "claude-sonnet-4-20250514"
            )

        case .openai:
            provider = OpenAICompatibleProvider(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                apiKey: config.openAIAPIKey,
                defaultModel: "gpt-4o",
                name: "OpenAI"
            )
        }

        cachedProviders[type] = provider
        return provider
    }

    /// Clear availability cache (force re-check)
    public func clearCache() {
        availabilityCache.removeAll()
    }
}

// MARK: - Provider Status

public struct ProviderStatus: Sendable {
    public let type: ProviderSelector.ProviderType
    public let isAvailable: Bool
    public let isConfigured: Bool
    public let isPreferred: Bool
    public let providerName: String?

    public var statusDescription: String {
        if !isConfigured {
            return "Not configured"
        } else if isAvailable {
            return "Available"
        } else {
            return "Unavailable"
        }
    }
}

// MARK: - Convenience Extensions

extension ProviderSelector {
    /// Create a selector preferring local providers only
    public static func localOnly(
        ollamaModel: String = "llama3.1"
    ) -> ProviderSelector {
        ProviderSelector(config: Configuration(
            preferredOrder: [.foundationModels, .ollama, .lmStudio],
            ollamaModel: ollamaModel,
            allowCloudProviders: false
        ))
    }

    /// Create a selector with Anthropic fallback
    public static func withAnthropicFallback(
        apiKey: String,
        ollamaModel: String = "llama3.1"
    ) -> ProviderSelector {
        ProviderSelector(config: Configuration(
            preferredOrder: [.foundationModels, .ollama, .anthropic],
            ollamaModel: ollamaModel,
            anthropicAPIKey: apiKey,
            allowCloudProviders: true
        ))
    }

    /// Quick check if any provider is available
    public func hasAvailableProvider() async -> Bool {
        await selectProvider() != nil
    }
}
