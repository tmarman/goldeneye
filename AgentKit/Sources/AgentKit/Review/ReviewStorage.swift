import Foundation

// MARK: - Review Storage

/// Stores reviews in git-tracked JSON files
///
/// File structure:
/// .goldeneye/
///   reviews/
///     index.json              (all review metadata for quick listing)
///     {review-id}/
///       review.json           (full review data)
///       comments.json         (all comments)
public actor ReviewStorage {
    private let basePath: URL  // .goldeneye/reviews/

    private var reviewIndex: ReviewIndex = ReviewIndex()
    private var loadedReviews: [ReviewID: Review] = [:]
    private var loadedComments: [ReviewID: [ReviewComment]] = [:]

    public init(basePath: URL) {
        self.basePath = basePath
    }

    /// Initialize storage at a repo path (creates .goldeneye/reviews/ if needed)
    public static func create(at repoPath: URL) async throws -> ReviewStorage {
        let basePath = repoPath
            .appendingPathComponent(".goldeneye")
            .appendingPathComponent("reviews")

        try FileManager.default.createDirectory(
            at: basePath,
            withIntermediateDirectories: true
        )

        let storage = ReviewStorage(basePath: basePath)
        try await storage.loadIndex()
        return storage
    }

    // MARK: - Index Management

    private func loadIndex() throws {
        let indexPath = basePath.appendingPathComponent("index.json")

        guard FileManager.default.fileExists(atPath: indexPath.path) else {
            reviewIndex = ReviewIndex()
            return
        }

        let data = try Data(contentsOf: indexPath)
        reviewIndex = try JSONDecoder().decode(ReviewIndex.self, from: data)
    }

    private func saveIndex() throws {
        let indexPath = basePath.appendingPathComponent("index.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(reviewIndex)
        try data.write(to: indexPath)
    }

    // MARK: - Review CRUD

    public func save(_ review: Review) async throws {
        let reviewDir = basePath.appendingPathComponent(review.id)
        try FileManager.default.createDirectory(
            at: reviewDir,
            withIntermediateDirectories: true
        )

        // Save full review
        let reviewPath = reviewDir.appendingPathComponent("review.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(review)
        try data.write(to: reviewPath)

        // Update cache
        loadedReviews[review.id] = review

        // Update index
        reviewIndex.entries[review.id] = ReviewIndexEntry(
            id: review.id,
            title: review.title,
            author: review.author.name,
            status: review.status,
            spaceId: review.spaceId,
            createdAt: review.createdAt,
            updatedAt: review.updatedAt
        )
        try saveIndex()
    }

    public func load(_ id: ReviewID) async throws -> Review {
        // Check cache first
        if let cached = loadedReviews[id] {
            return cached
        }

        let reviewPath = basePath
            .appendingPathComponent(id)
            .appendingPathComponent("review.json")

        guard FileManager.default.fileExists(atPath: reviewPath.path) else {
            throw ReviewStorageError.reviewNotFound(id)
        }

        let data = try Data(contentsOf: reviewPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let review = try decoder.decode(Review.self, from: data)

        // Cache it
        loadedReviews[id] = review
        return review
    }

    public func delete(_ id: ReviewID) async throws {
        let reviewDir = basePath.appendingPathComponent(id)

        guard FileManager.default.fileExists(atPath: reviewDir.path) else {
            throw ReviewStorageError.reviewNotFound(id)
        }

        try FileManager.default.removeItem(at: reviewDir)

        // Update cache and index
        loadedReviews.removeValue(forKey: id)
        loadedComments.removeValue(forKey: id)
        reviewIndex.entries.removeValue(forKey: id)
        try saveIndex()
    }

    public func exists(_ id: ReviewID) -> Bool {
        let reviewPath = basePath
            .appendingPathComponent(id)
            .appendingPathComponent("review.json")
        return FileManager.default.fileExists(atPath: reviewPath.path)
    }

    // MARK: - Listing & Filtering

    public func list(
        spaceId: SpaceID? = nil,
        status: ReviewStatus? = nil,
        author: String? = nil,
        limit: Int? = nil,
        offset: Int = 0
    ) async throws -> [ReviewIndexEntry] {
        var entries = Array(reviewIndex.entries.values)

        // Filter
        if let spaceId {
            entries = entries.filter { $0.spaceId == spaceId }
        }
        if let status {
            entries = entries.filter { $0.status == status }
        }
        if let author {
            entries = entries.filter { $0.author.lowercased().contains(author.lowercased()) }
        }

        // Sort by updatedAt (newest first)
        entries.sort { $0.updatedAt > $1.updatedAt }

        // Pagination
        let startIndex = min(offset, entries.count)
        let endIndex = limit.map { min(startIndex + $0, entries.count) } ?? entries.count
        return Array(entries[startIndex..<endIndex])
    }

    public func listOpen() async throws -> [ReviewIndexEntry] {
        try await list(status: .open)
    }

    public func search(query: String) async throws -> [ReviewIndexEntry] {
        let lowercased = query.lowercased()
        return reviewIndex.entries.values.filter {
            $0.title.lowercased().contains(lowercased) ||
            $0.author.lowercased().contains(lowercased)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Comments

    public func saveComments(_ comments: [ReviewComment], for reviewId: ReviewID) async throws {
        let reviewDir = basePath.appendingPathComponent(reviewId)
        let commentsPath = reviewDir.appendingPathComponent("comments.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(comments)
        try data.write(to: commentsPath)

        loadedComments[reviewId] = comments
    }

    public func loadComments(for reviewId: ReviewID) async throws -> [ReviewComment] {
        if let cached = loadedComments[reviewId] {
            return cached
        }

        let commentsPath = basePath
            .appendingPathComponent(reviewId)
            .appendingPathComponent("comments.json")

        guard FileManager.default.fileExists(atPath: commentsPath.path) else {
            return []
        }

        let data = try Data(contentsOf: commentsPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let comments = try decoder.decode([ReviewComment].self, from: data)

        loadedComments[reviewId] = comments
        return comments
    }

    public func addComment(_ comment: ReviewComment) async throws {
        var comments = try await loadComments(for: comment.reviewId)
        comments.append(comment)
        try await saveComments(comments, for: comment.reviewId)
    }

    public func updateComment(_ comment: ReviewComment) async throws {
        var comments = try await loadComments(for: comment.reviewId)
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else {
            throw ReviewStorageError.commentNotFound(comment.id)
        }
        comments[index] = comment
        try await saveComments(comments, for: comment.reviewId)
    }

    // MARK: - Utilities

    public func rebuildIndex() async throws {
        var newIndex = ReviewIndex()

        let contents = try FileManager.default.contentsOfDirectory(
            at: basePath,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for item in contents {
            guard item.lastPathComponent != "index.json" else { continue }

            let reviewPath = item.appendingPathComponent("review.json")
            guard FileManager.default.fileExists(atPath: reviewPath.path) else { continue }

            do {
                let data = try Data(contentsOf: reviewPath)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let review = try decoder.decode(Review.self, from: data)

                newIndex.entries[review.id] = ReviewIndexEntry(
                    id: review.id,
                    title: review.title,
                    author: review.author.name,
                    status: review.status,
                    spaceId: review.spaceId,
                    createdAt: review.createdAt,
                    updatedAt: review.updatedAt
                )
            } catch {
                // Skip invalid reviews
                continue
            }
        }

        reviewIndex = newIndex
        try saveIndex()
    }

    public func clearCache() {
        loadedReviews.removeAll()
        loadedComments.removeAll()
    }
}

// MARK: - Index Types

struct ReviewIndex: Codable {
    var entries: [ReviewID: ReviewIndexEntry] = [:]
}

public struct ReviewIndexEntry: Codable, Identifiable, Sendable {
    public let id: ReviewID
    public let title: String
    public let author: String
    public let status: ReviewStatus
    public let spaceId: SpaceID?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: ReviewID,
        title: String,
        author: String,
        status: ReviewStatus,
        spaceId: SpaceID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.status = status
        self.spaceId = spaceId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Errors

public enum ReviewStorageError: Error, Sendable {
    case reviewNotFound(ReviewID)
    case commentNotFound(UUID)
    case invalidPath
    case encodingFailed
    case decodingFailed
}
