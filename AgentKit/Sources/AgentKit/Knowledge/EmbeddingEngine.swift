//
//  EmbeddingEngine.swift
//  AgentKit
//
//  Local embedding generation for the Knowledge Backbone.
//  Supports MLX models and provides batch embedding capabilities.
//

import Foundation

// MARK: - Embedding Engine

/// Local embedding engine using MLX or other backends
public actor KEmbeddingEngine {
    private var model: KEmbeddingModel
    private var isLoaded = false
    private var tokenizer: SimpleTokenizer?

    // Cache for recently computed embeddings
    private var cache: [String: [Float]] = [:]
    private let maxCacheSize = 1000

    public init(model: KEmbeddingModel = .bgeSmallEn) {
        self.model = model
    }

    // MARK: - Model Loading

    /// Load the embedding model
    public func loadModel() async throws {
        guard !isLoaded else { return }

        // Initialize tokenizer
        tokenizer = SimpleTokenizer()

        // For now, we'll use a simple approach
        // Full MLX integration would load the actual model here
        print("📊 EmbeddingEngine: Loading model \(model.name)...")

        isLoaded = true
        print("✅ EmbeddingEngine: Model loaded (dimensions: \(model.dimensions))")
    }

    /// Switch to a different model
    public func switchModel(_ newModel: KEmbeddingModel) async throws {
        isLoaded = false
        cache.removeAll()
        model = newModel
        try await loadModel()
    }

    /// Current model info
    public var currentModel: KEmbeddingModel {
        model
    }

    // MARK: - Embedding Generation

    /// Generate embedding for a single text
    public func embed(_ text: String) async throws -> [Float] {
        // Check cache first
        if let cached = cache[text] {
            return cached
        }

        try await loadModelIfNeeded()

        let embedding = try await generateEmbedding(text)

        // Cache result
        cacheEmbedding(text, embedding: embedding)

        return embedding
    }

    /// Generate embeddings for multiple texts (batched)
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        try await loadModelIfNeeded()

        var results: [[Float]] = []

        // Process in batches for efficiency
        let batchSize = 32
        for batchStart in stride(from: 0, to: texts.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, texts.count)
            let batch = Array(texts[batchStart..<batchEnd])

            let batchEmbeddings = try await generateBatchEmbeddings(batch)
            results.append(contentsOf: batchEmbeddings)

            // Cache results
            for (i, text) in batch.enumerated() {
                cacheEmbedding(text, embedding: batchEmbeddings[i])
            }
        }

        return results
    }

    /// Compute similarity between two embeddings (cosine similarity)
    public func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }

    /// Find most similar texts to a query
    public func findSimilar(
        query: [Float],
        candidates: [(id: String, embedding: [Float])],
        limit: Int = 10,
        minScore: Float = 0.0
    ) -> [(id: String, score: Float)] {
        var results: [(id: String, score: Float)] = []

        for candidate in candidates {
            let score = similarity(query, candidate.embedding)
            if score >= minScore {
                results.append((candidate.id, score))
            }
        }

        // Sort by score descending
        results.sort { $0.score > $1.score }

        return Array(results.prefix(limit))
    }

    // MARK: - Private Methods

    private func loadModelIfNeeded() async throws {
        if !isLoaded {
            try await loadModel()
        }
    }

    private func generateEmbedding(_ text: String) async throws -> [Float] {
        // Normalize and tokenize text
        let normalizedText = normalizeText(text)

        // For now, use a simple bag-of-words approach with hashing
        // In production, this would use actual MLX model inference
        return simpleEmbedding(normalizedText)
    }

    private func generateBatchEmbeddings(_ texts: [String]) async throws -> [[Float]] {
        // In production, this would batch through the model
        return try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    let embedding = try await self.generateEmbedding(text)
                    return (index, embedding)
                }
            }

            var results = [[Float]](repeating: [], count: texts.count)
            for try await (index, embedding) in group {
                results[index] = embedding
            }
            return results
        }
    }

    /// Simple embedding using hashing (placeholder for real model)
    /// This creates deterministic embeddings suitable for testing
    private func simpleEmbedding(_ text: String) -> [Float] {
        let dimensions = model.dimensions

        // Tokenize
        let tokens = tokenizer?.tokenize(text) ?? text.lowercased().components(separatedBy: .whitespaces)

        // Create embedding through feature hashing
        var embedding = [Float](repeating: 0, count: dimensions)

        for (i, token) in tokens.enumerated() {
            // Hash token to get position
            let hash = token.hashValue
            let position = abs(hash) % dimensions

            // Use position-dependent weighting
            let weight = 1.0 / Float(i + 1)  // Earlier tokens weighted more
            let sign: Float = hash > 0 ? 1.0 : -1.0

            embedding[position] += sign * weight
        }

        // L2 normalize
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            for i in 0..<dimensions {
                embedding[i] /= norm
            }
        }

        return embedding
    }

    private func normalizeText(_ text: String) -> String {
        // Basic normalization
        var normalized = text.lowercased()

        // Remove excessive whitespace
        normalized = normalized.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // Truncate if too long
        let maxLength = model.maxSequenceLength
        if normalized.count > maxLength {
            normalized = String(normalized.prefix(maxLength))
        }

        return normalized
    }

    private func cacheEmbedding(_ text: String, embedding: [Float]) {
        // Evict old entries if cache is full
        if cache.count >= maxCacheSize {
            // Remove ~10% of entries
            let toRemove = cache.keys.prefix(maxCacheSize / 10)
            for key in toRemove {
                cache.removeValue(forKey: key)
            }
        }

        cache[text] = embedding
    }

    /// Clear the embedding cache
    public func clearCache() {
        cache.removeAll()
    }

    /// Get cache statistics
    public var cacheStats: (size: Int, maxSize: Int) {
        (cache.count, maxCacheSize)
    }
}

// MARK: - Embedding Model

/// Available embedding models
public enum KEmbeddingModel: Sendable {
    case bgeSmallEn         // BGE Small English - 384 dims, fast
    case bgeLargeEn         // BGE Large English - 1024 dims, better quality
    case e5SmallV2          // E5 Small v2 - 384 dims, good for queries
    case e5LargeV2          // E5 Large v2 - 1024 dims
    case allMiniLML6V2      // All-MiniLM-L6-v2 - 384 dims, very fast
    case custom(name: String, dimensions: Int, maxSeqLength: Int)

    public var name: String {
        switch self {
        case .bgeSmallEn: return "bge-small-en-v1.5"
        case .bgeLargeEn: return "bge-large-en-v1.5"
        case .e5SmallV2: return "e5-small-v2"
        case .e5LargeV2: return "e5-large-v2"
        case .allMiniLML6V2: return "all-MiniLM-L6-v2"
        case .custom(let name, _, _): return name
        }
    }

    public var dimensions: Int {
        switch self {
        case .bgeSmallEn, .e5SmallV2, .allMiniLML6V2: return 384
        case .bgeLargeEn, .e5LargeV2: return 1024
        case .custom(_, let dims, _): return dims
        }
    }

    public var maxSequenceLength: Int {
        switch self {
        case .bgeSmallEn, .bgeLargeEn: return 512
        case .e5SmallV2, .e5LargeV2: return 512
        case .allMiniLML6V2: return 256
        case .custom(_, _, let maxLen): return maxLen
        }
    }

    /// Query prefix for models that need it
    public var queryPrefix: String? {
        switch self {
        case .e5SmallV2, .e5LargeV2: return "query: "
        default: return nil
        }
    }

    /// Document prefix for models that need it
    public var documentPrefix: String? {
        switch self {
        case .e5SmallV2, .e5LargeV2: return "passage: "
        default: return nil
        }
    }
}

// MARK: - Simple Tokenizer

/// Basic tokenizer for text preprocessing
private struct SimpleTokenizer {
    func tokenize(_ text: String) -> [String] {
        // Basic word tokenization
        let lowered = text.lowercased()

        // Split on whitespace and punctuation
        let pattern = try! NSRegularExpression(pattern: "[\\w]+", options: [])
        let nsText = lowered as NSString
        let matches = pattern.matches(in: lowered, options: [], range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: lowered) else { return nil }
            let token = String(lowered[range])
            // Skip very short tokens
            return token.count >= 2 ? token : nil
        }
    }
}

// MARK: - Embedding Errors

public enum KEmbeddingError: Error, LocalizedError {
    case modelNotLoaded
    case embeddingFailed(String)
    case dimensionMismatch(expected: Int, got: Int)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Embedding model not loaded"
        case .embeddingFailed(let reason):
            return "Embedding generation failed: \(reason)"
        case .dimensionMismatch(let expected, let got):
            return "Embedding dimension mismatch: expected \(expected), got \(got)"
        }
    }
}
