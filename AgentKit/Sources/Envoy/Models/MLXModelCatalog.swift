//
//  MLXModelCatalog.swift
//  Envoy
//
//  Model catalog for MLX on-device models that can be downloaded from HuggingFace.
//

import SwiftUI

// MARK: - Model Tags

/// Tags for categorizing MLX models
public enum MLXModelTag: String, CaseIterable, Identifiable, Codable, Sendable {
    case new = "New"
    case vision = "Vision"
    case thinking = "Thinking"
    case recommended = "Recommended"
    case best = "Best"
    case tools = "Tools"
    case code = "Code"
    case fast = "Fast"

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .new: return .yellow
        case .vision: return .purple
        case .thinking: return .orange
        case .recommended: return .green
        case .best: return .green
        case .tools: return .teal
        case .code: return .blue
        case .fast: return .cyan
        }
    }

    public var icon: String {
        switch self {
        case .new: return "sparkles"
        case .vision: return "eye"
        case .thinking: return "lightbulb.fill"
        case .recommended: return "checkmark.seal.fill"
        case .best: return "crown.fill"
        case .tools: return "wrench.and.screwdriver"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .fast: return "hare"
        }
    }
}

// MARK: - Model Variant

/// A specific variant of an MLX model (e.g., 4-bit, 8-bit, different sizes)
public struct MLXModelVariant: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let modelId: String  // HuggingFace model ID
    public let estimatedSizeBytes: Int64
    public let tags: [MLXModelTag]
    public let minimumRAMGB: Int  // Recommended minimum RAM

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: estimatedSizeBytes, countStyle: .file)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: MLXModelVariant, rhs: MLXModelVariant) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Model Family

/// A family of related MLX models (e.g., Llama, Qwen, Gemma)
public struct MLXModelFamily: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let icon: String  // SF Symbol name
    public let tags: [MLXModelTag]
    public let variants: [MLXModelVariant]
    public let provider: String  // Company/org (e.g., "Meta", "Google", "Alibaba")

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: MLXModelFamily, rhs: MLXModelFamily) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Model Catalog

/// Static catalog of available MLX models
public struct MLXModelCatalog {

    // MARK: - Llama (Meta)

    public static let llama = MLXModelFamily(
        id: "llama",
        displayName: "Llama",
        description: "Meta's open-source Llama models. Strong general-purpose capabilities with excellent instruction following.",
        icon: "brain.head.profile",
        tags: [.recommended, .tools],
        variants: [
            MLXModelVariant(
                id: "llama-3.2-1b",
                displayName: "Llama 3.2 (1B)",
                description: "Ultra-compact 1B parameter model. Fast and efficient for simple tasks.",
                modelId: "mlx-community/Llama-3.2-1B-Instruct-4bit",
                estimatedSizeBytes: 700_000_000,
                tags: [.fast],
                minimumRAMGB: 4
            ),
            MLXModelVariant(
                id: "llama-3.2-3b",
                displayName: "Llama 3.2 (3B)",
                description: "Compact 3B parameter model with good balance of speed and capability.",
                modelId: "mlx-community/Llama-3.2-3B-Instruct-4bit",
                estimatedSizeBytes: 2_000_000_000,
                tags: [.recommended],
                minimumRAMGB: 8
            ),
            MLXModelVariant(
                id: "llama-3.2-8b",
                displayName: "Llama 3.2 (8B)",
                description: "8B parameter model with strong reasoning and coding abilities.",
                modelId: "mlx-community/Llama-3.2-8B-Instruct-4bit",
                estimatedSizeBytes: 5_000_000_000,
                tags: [.tools],
                minimumRAMGB: 16
            ),
            MLXModelVariant(
                id: "llama-3.3-70b",
                displayName: "Llama 3.3 (70B)",
                description: "Meta's most powerful open model. Requires 64GB+ RAM.",
                modelId: "mlx-community/Llama-3.3-70B-Instruct-4bit",
                estimatedSizeBytes: 40_000_000_000,
                tags: [.best],
                minimumRAMGB: 64
            )
        ],
        provider: "Meta"
    )

    // MARK: - Qwen (Alibaba)

    public static let qwen = MLXModelFamily(
        id: "qwen",
        displayName: "Qwen 2.5",
        description: "Alibaba's latest generation models. Excellent for coding, math, and multilingual tasks.",
        icon: "globe.asia.australia",
        tags: [.recommended, .tools, .code],
        variants: [
            MLXModelVariant(
                id: "qwen-2.5-0.5b",
                displayName: "Qwen 2.5 (0.5B)",
                description: "Tiny 500M parameter model for ultra-fast responses.",
                modelId: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
                estimatedSizeBytes: 350_000_000,
                tags: [.fast],
                minimumRAMGB: 4
            ),
            MLXModelVariant(
                id: "qwen-2.5-1.5b",
                displayName: "Qwen 2.5 (1.5B)",
                description: "Compact model with strong coding capabilities.",
                modelId: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                estimatedSizeBytes: 1_000_000_000,
                tags: [.code],
                minimumRAMGB: 4
            ),
            MLXModelVariant(
                id: "qwen-2.5-3b",
                displayName: "Qwen 2.5 (3B)",
                description: "Balanced model for general tasks and coding.",
                modelId: "mlx-community/Qwen2.5-3B-Instruct-4bit",
                estimatedSizeBytes: 2_000_000_000,
                tags: [.code],
                minimumRAMGB: 8
            ),
            MLXModelVariant(
                id: "qwen-2.5-7b",
                displayName: "Qwen 2.5 (7B)",
                description: "Strong all-around model with excellent code generation.",
                modelId: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                estimatedSizeBytes: 4_500_000_000,
                tags: [.recommended, .tools, .code],
                minimumRAMGB: 16
            ),
            MLXModelVariant(
                id: "qwen-2.5-14b",
                displayName: "Qwen 2.5 (14B)",
                description: "Enhanced reasoning and coding capabilities.",
                modelId: "mlx-community/Qwen2.5-14B-Instruct-4bit",
                estimatedSizeBytes: 9_000_000_000,
                tags: [.tools, .code],
                minimumRAMGB: 24
            ),
            MLXModelVariant(
                id: "qwen-2.5-32b",
                displayName: "Qwen 2.5 (32B)",
                description: "Excellent for complex reasoning tasks.",
                modelId: "mlx-community/Qwen2.5-32B-Instruct-4bit",
                estimatedSizeBytes: 18_000_000_000,
                tags: [.tools],
                minimumRAMGB: 48
            ),
            MLXModelVariant(
                id: "qwen-2.5-72b",
                displayName: "Qwen 2.5 (72B)",
                description: "Top-tier model for demanding applications. Requires 64GB+ RAM.",
                modelId: "mlx-community/Qwen2.5-72B-Instruct-4bit",
                estimatedSizeBytes: 40_000_000_000,
                tags: [.best, .tools],
                minimumRAMGB: 64
            )
        ],
        provider: "Alibaba"
    )

    // MARK: - Qwen Coder

    public static let qwenCoder = MLXModelFamily(
        id: "qwen-coder",
        displayName: "Qwen 2.5 Coder",
        description: "Specialized coding models from Alibaba. State-of-the-art code generation and understanding.",
        icon: "chevron.left.forwardslash.chevron.right",
        tags: [.code, .tools],
        variants: [
            MLXModelVariant(
                id: "qwen-coder-1.5b",
                displayName: "Qwen Coder (1.5B)",
                description: "Compact code assistant for quick tasks.",
                modelId: "mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit",
                estimatedSizeBytes: 1_000_000_000,
                tags: [.code, .fast],
                minimumRAMGB: 4
            ),
            MLXModelVariant(
                id: "qwen-coder-7b",
                displayName: "Qwen Coder (7B)",
                description: "Strong code generation with good balance of speed and quality.",
                modelId: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
                estimatedSizeBytes: 4_500_000_000,
                tags: [.recommended, .code, .tools],
                minimumRAMGB: 16
            ),
            MLXModelVariant(
                id: "qwen-coder-14b",
                displayName: "Qwen Coder (14B)",
                description: "Advanced code generation for complex projects.",
                modelId: "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit",
                estimatedSizeBytes: 9_000_000_000,
                tags: [.code, .tools],
                minimumRAMGB: 24
            ),
            MLXModelVariant(
                id: "qwen-coder-32b",
                displayName: "Qwen Coder (32B)",
                description: "Excellent for complex codebases and refactoring.",
                modelId: "mlx-community/Qwen2.5-Coder-32B-Instruct-4bit",
                estimatedSizeBytes: 18_000_000_000,
                tags: [.best, .code, .tools],
                minimumRAMGB: 48
            )
        ],
        provider: "Alibaba"
    )

    // MARK: - Gemma (Google)

    public static let gemma = MLXModelFamily(
        id: "gemma",
        displayName: "Gemma 2",
        description: "Google's efficient open models. Excellent performance across reasoning, math, and coding.",
        icon: "sparkle",
        tags: [.recommended],
        variants: [
            MLXModelVariant(
                id: "gemma-2-2b",
                displayName: "Gemma 2 (2B)",
                description: "Compact model with good general capabilities.",
                modelId: "mlx-community/gemma-2-2b-it-4bit",
                estimatedSizeBytes: 1_500_000_000,
                tags: [],
                minimumRAMGB: 4
            ),
            MLXModelVariant(
                id: "gemma-2-9b",
                displayName: "Gemma 2 (9B)",
                description: "Strong all-around model for most tasks.",
                modelId: "mlx-community/gemma-2-9b-it-4bit",
                estimatedSizeBytes: 6_000_000_000,
                tags: [.recommended],
                minimumRAMGB: 16
            ),
            MLXModelVariant(
                id: "gemma-2-27b",
                displayName: "Gemma 2 (27B)",
                description: "Google's largest Gemma model with excellent reasoning.",
                modelId: "mlx-community/gemma-2-27b-it-4bit",
                estimatedSizeBytes: 16_000_000_000,
                tags: [.best],
                minimumRAMGB: 32
            )
        ],
        provider: "Google"
    )

    // MARK: - Phi (Microsoft)

    public static let phi = MLXModelFamily(
        id: "phi",
        displayName: "Phi",
        description: "Microsoft's small but powerful models. Excellent for reasoning and coding with MIT license.",
        icon: "function",
        tags: [.thinking, .code],
        variants: [
            MLXModelVariant(
                id: "phi-3.5-mini",
                displayName: "Phi-3.5 Mini (3.8B)",
                description: "Compact reasoning model optimized for logic and coding.",
                modelId: "mlx-community/Phi-3.5-mini-instruct-4bit",
                estimatedSizeBytes: 2_300_000_000,
                tags: [.thinking],
                minimumRAMGB: 8
            ),
            MLXModelVariant(
                id: "phi-4-mini",
                displayName: "Phi-4 Mini (3.8B)",
                description: "Latest Phi model with enhanced capabilities.",
                modelId: "mlx-community/Phi-4-mini-instruct-4bit",
                estimatedSizeBytes: 2_300_000_000,
                tags: [.new, .thinking],
                minimumRAMGB: 8
            ),
            MLXModelVariant(
                id: "phi-4-mini-reasoning",
                displayName: "Phi-4 Mini Reasoning",
                description: "Phi-4 optimized for chain-of-thought reasoning.",
                modelId: "mlx-community/Phi-4-mini-reasoning-4bit",
                estimatedSizeBytes: 2_300_000_000,
                tags: [.new, .thinking],
                minimumRAMGB: 8
            )
        ],
        provider: "Microsoft"
    )

    // MARK: - DeepSeek

    public static let deepseek = MLXModelFamily(
        id: "deepseek",
        displayName: "DeepSeek",
        description: "Advanced reasoning and coding models with excellent performance.",
        icon: "scope",
        tags: [.thinking, .code],
        variants: [
            MLXModelVariant(
                id: "deepseek-r1-8b",
                displayName: "DeepSeek R1 (8B)",
                description: "Reasoning model with step-by-step thinking.",
                modelId: "mlx-community/DeepSeek-R1-0528-Qwen3-8B-4bit",
                estimatedSizeBytes: 4_600_000_000,
                tags: [.thinking],
                minimumRAMGB: 16
            ),
            MLXModelVariant(
                id: "deepseek-coder-6.7b",
                displayName: "DeepSeek Coder (6.7B)",
                description: "Specialized coding model with strong performance.",
                modelId: "mlx-community/deepseek-coder-6.7b-instruct-4bit",
                estimatedSizeBytes: 4_000_000_000,
                tags: [.code],
                minimumRAMGB: 16
            ),
            MLXModelVariant(
                id: "deepseek-coder-v2-lite",
                displayName: "DeepSeek Coder V2 Lite",
                description: "Efficient coding model with MoE architecture.",
                modelId: "mlx-community/DeepSeek-Coder-V2-Lite-Instruct-4bit",
                estimatedSizeBytes: 8_000_000_000,
                tags: [.code, .recommended],
                minimumRAMGB: 24
            )
        ],
        provider: "DeepSeek"
    )

    // MARK: - Mistral

    public static let mistral = MLXModelFamily(
        id: "mistral",
        displayName: "Mistral",
        description: "High-performance European models with strong reasoning and tool use.",
        icon: "wind",
        tags: [.tools],
        variants: [
            MLXModelVariant(
                id: "mistral-7b",
                displayName: "Mistral (7B)",
                description: "Efficient 7B model with excellent instruction following.",
                modelId: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
                estimatedSizeBytes: 4_500_000_000,
                tags: [.tools],
                minimumRAMGB: 16
            ),
            MLXModelVariant(
                id: "mistral-nemo-12b",
                displayName: "Mistral Nemo (12B)",
                description: "Enhanced model with 128K context window.",
                modelId: "mlx-community/Mistral-Nemo-Instruct-2407-4bit",
                estimatedSizeBytes: 7_500_000_000,
                tags: [.recommended, .tools],
                minimumRAMGB: 24
            )
        ],
        provider: "Mistral AI"
    )

    // MARK: - Vision Models

    public static let visionModels = MLXModelFamily(
        id: "vision",
        displayName: "Vision Models",
        description: "Multimodal models that can understand images alongside text.",
        icon: "eye",
        tags: [.vision],
        variants: [
            MLXModelVariant(
                id: "llava-1.5-7b",
                displayName: "LLaVA 1.5 (7B)",
                description: "Vision-language model for image understanding.",
                modelId: "mlx-community/llava-1.5-7b-4bit",
                estimatedSizeBytes: 4_500_000_000,
                tags: [.vision],
                minimumRAMGB: 16
            ),
            MLXModelVariant(
                id: "qwen-vl-2b",
                displayName: "Qwen VL (2B)",
                description: "Compact vision-language model from Alibaba.",
                modelId: "mlx-community/Qwen2-VL-2B-Instruct-4bit",
                estimatedSizeBytes: 1_500_000_000,
                tags: [.vision],
                minimumRAMGB: 8
            ),
            MLXModelVariant(
                id: "qwen-vl-7b",
                displayName: "Qwen VL (7B)",
                description: "Strong vision-language model for image analysis.",
                modelId: "mlx-community/Qwen2-VL-7B-Instruct-4bit",
                estimatedSizeBytes: 5_000_000_000,
                tags: [.vision, .recommended],
                minimumRAMGB: 16
            )
        ],
        provider: "Various"
    )

    // MARK: - All Families

    public static let families: [MLXModelFamily] = [
        llama,
        qwen,
        qwenCoder,
        gemma,
        phi,
        deepseek,
        mistral,
        visionModels
    ]

    /// Returns only the tags that are actually used in the catalog
    public static var usedTags: [MLXModelTag] {
        var tags = Set<MLXModelTag>()
        for family in families {
            tags.formUnion(family.tags)
            for variant in family.variants {
                tags.formUnion(variant.tags)
            }
        }
        return tags.sorted { $0.rawValue < $1.rawValue }
    }

    /// Find a variant by its model ID
    public static func findVariant(byModelId modelId: String) -> MLXModelVariant? {
        for family in families {
            if let variant = family.variants.first(where: { $0.modelId == modelId }) {
                return variant
            }
        }
        return nil
    }

    /// Find the family containing a variant
    public static func findFamily(for variant: MLXModelVariant) -> MLXModelFamily? {
        families.first { family in
            family.variants.contains { $0.id == variant.id }
        }
    }
}
