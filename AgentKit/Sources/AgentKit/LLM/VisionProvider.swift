import CoreImage
import Foundation

// MARK: - Vision Provider Protocol

/// Protocol for vision understanding capabilities.
///
/// VisionProvider defines the interface for image understanding as a tool/skill
/// that agents can use. Implementations may use:
/// - On-device MLX VLM models (Qwen2.5-VL, Gemma 3, SmolVLM)
/// - Apple Foundation Models (via FoundationModels framework)
/// - Cloud APIs (OpenAI, Anthropic, etc.)
///
/// This abstraction allows agents to analyze images without being tied to
/// a specific implementation.
public protocol VisionProvider: Sendable {
    /// Unique identifier for this provider
    var id: String { get }

    /// Human-readable name
    var name: String { get }

    /// Whether the provider is currently available
    func isAvailable() async -> Bool

    /// Describe an image with a custom prompt
    /// - Parameters:
    ///   - url: URL to the image file
    ///   - prompt: Prompt describing what to look for
    /// - Returns: Text description from the vision model
    func describeImage(at url: URL, prompt: String) async throws -> String

    /// Analyze an image for structured information
    /// - Parameter url: URL to the image file
    /// - Returns: Structured analysis result
    func analyzeImage(at url: URL) async throws -> ImageAnalysis
}

// MARK: - Default Implementations

extension VisionProvider {
    /// Default prompt for image description
    public static var defaultDescriptionPrompt: String {
        "Describe this image concisely. Focus on the main subject and any notable details."
    }

    /// Default prompt for profile-focused analysis
    public static var defaultProfilePrompt: String {
        """
        Analyze this image briefly. Identify:
        1. Main subject (person, place, object, activity)
        2. Context (work, hobby, travel, family, etc.)
        3. Any interests or themes visible

        Be concise - one sentence per point.
        """
    }
}

// MARK: - Image Analysis Result

/// Structured result of image analysis
public struct ImageAnalysis: Sendable {
    /// Textual description of the image
    public let description: String

    /// Inferred category for the image content
    public let suggestedCategory: ImageCategory

    /// Confidence level of the analysis (0.0 to 1.0)
    public let confidence: Double

    /// Source URL of the analyzed image
    public let sourceURL: URL?

    public init(
        description: String,
        suggestedCategory: ImageCategory,
        confidence: Double,
        sourceURL: URL? = nil
    ) {
        self.description = description
        self.suggestedCategory = suggestedCategory
        self.confidence = min(1.0, max(0.0, confidence))
        self.sourceURL = sourceURL
    }
}

// MARK: - Image Category

/// Categories for classifying image content
public enum ImageCategory: String, Sendable, CaseIterable {
    /// Work-related content (office, code, meetings, professional)
    case work

    /// Personal interests (hobbies, travel, sports, art)
    case interest

    /// Patterns and routines (daily activities, habits)
    case pattern

    /// General/uncategorized content
    case general

    /// Infer category from description text
    public static func infer(from description: String) -> ImageCategory {
        let lowercased = description.lowercased()

        // Work-related keywords
        let workKeywords = [
            "office", "computer", "work", "meeting", "code", "programming",
            "desk", "professional", "business", "laptop", "conference"
        ]
        if workKeywords.contains(where: { lowercased.contains($0) }) {
            return .work
        }

        // Interest keywords
        let interestKeywords = [
            "hobby", "travel", "vacation", "sport", "music", "art",
            "photography", "hiking", "cooking", "reading", "beach",
            "mountain", "concert", "game"
        ]
        if interestKeywords.contains(where: { lowercased.contains($0) }) {
            return .interest
        }

        // Pattern keywords (routine activities)
        let patternKeywords = [
            "morning", "routine", "daily", "regular", "exercise",
            "gym", "coffee", "breakfast", "commute"
        ]
        if patternKeywords.contains(where: { lowercased.contains($0) }) {
            return .pattern
        }

        return .general
    }
}

// MARK: - Vision Errors

/// Errors that can occur during vision operations
public enum VisionError: Error, LocalizedError, Sendable {
    case modelNotLoaded
    case imageLoadFailed(URL)
    case analysisTimeout
    case providerUnavailable(String)
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Vision model is not loaded"
        case .imageLoadFailed(let url):
            return "Failed to load image from: \(url.path)"
        case .analysisTimeout:
            return "Image analysis timed out"
        case .providerUnavailable(let reason):
            return "Vision provider unavailable: \(reason)"
        case .unsupportedFormat(let format):
            return "Unsupported image format: \(format)"
        }
    }
}

// MARK: - Vision Model Info

/// Metadata about a vision model
public struct VisionModelInfo: Sendable {
    public let id: String
    public let name: String
    public let size: String
    public let description: String
    public let provider: String

    public init(id: String, name: String, size: String, description: String, provider: String = "MLX") {
        self.id = id
        self.name = name
        self.size = size
        self.description = description
        self.provider = provider
    }
}

// MARK: - Placeholder Vision Provider

/// Placeholder provider used when no vision model is available.
/// Returns descriptive text indicating vision is not yet enabled.
public actor PlaceholderVisionProvider: VisionProvider {
    public let id = "placeholder"
    public let name = "Placeholder Vision"

    public init() {}

    public func isAvailable() async -> Bool {
        false
    }

    public func describeImage(at url: URL, prompt: String) async throws -> String {
        throw VisionError.providerUnavailable("Vision models not yet configured. Install a VLM to enable image understanding.")
    }

    public func analyzeImage(at url: URL) async throws -> ImageAnalysis {
        // Return a minimal analysis based on file metadata
        let filename = url.lastPathComponent.lowercased()

        // Infer category from filename
        var category: ImageCategory = .general
        if filename.contains("work") || filename.contains("office") || filename.contains("meeting") {
            category = .work
        } else if filename.contains("vacation") || filename.contains("travel") || filename.contains("trip") {
            category = .interest
        }

        return ImageAnalysis(
            description: "Image: \(url.lastPathComponent) (vision analysis not available)",
            suggestedCategory: category,
            confidence: 0.3,
            sourceURL: url
        )
    }
}
