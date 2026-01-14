import Foundation

// MARK: - Embedding Provider

/// Protocol for generating text embeddings
public protocol EmbeddingProvider: Sendable {
    /// Generate embedding for a single text
    func embed(text: String) async throws -> [Float]

    /// Generate embeddings for multiple texts (batched for efficiency)
    func embed(texts: [String]) async throws -> [[Float]]

    /// The dimensionality of embeddings produced
    var dimensions: Int { get }
}

// MARK: - Simple Embedding Provider

/// A simple embedding provider using basic text features
/// This is a placeholder implementation - can be replaced with MLX-based models
public actor SimpleEmbeddingProvider: EmbeddingProvider {
    public let dimensions: Int = 384 // Standard dimension for small models

    private let vocabulary: [String: Int]
    private let idf: [String: Float]

    public init() {
        // Initialize with empty vocabulary (will build on first use)
        self.vocabulary = [:]
        self.idf = [:]
    }

    public func embed(text: String) async throws -> [Float] {
        // Simple TF-IDF based embedding
        // This is a placeholder - in production would use a proper embedding model

        let tokens = tokenize(text)
        var embedding = [Float](repeating: 0.0, count: dimensions)

        // Use a simple hashing approach to map tokens to dimensions
        for token in tokens {
            let hash = abs(token.hashValue % dimensions)
            embedding[hash] += 1.0
        }

        // Normalize to unit length
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            embedding = embedding.map { $0 / magnitude }
        }

        return embedding
    }

    public func embed(texts: [String]) async throws -> [[Float]] {
        // Batch embedding (currently just sequential)
        var embeddings: [[Float]] = []
        for text in texts {
            let embedding = try await embed(text: text)
            embeddings.append(embedding)
        }
        return embeddings
    }

    private func tokenize(_ text: String) -> [String] {
        // Simple word tokenization
        let lowercased = text.lowercased()
        let words = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return words.filter { !$0.isEmpty }
    }
}

// MARK: - Vector Operations

public enum VectorOperations {
    /// Calculate cosine similarity between two vectors
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        let dotProduct = zip(a, b).reduce(0.0) { $0 + ($1.0 * $1.1) }
        let magnitudeA = sqrt(a.reduce(0.0) { $0 + ($1 * $1) })
        let magnitudeB = sqrt(b.reduce(0.0) { $0 + ($1 * $1) })

        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    /// Calculate L2 (Euclidean) distance between two vectors
    public static func l2Distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return Float.infinity }

        let sumSquares = zip(a, b).reduce(0.0) { $0 + pow($1.0 - $1.1, 2) }
        return sqrt(sumSquares)
    }
}
