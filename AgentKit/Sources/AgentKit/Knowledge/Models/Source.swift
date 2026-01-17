//
//  Source.swift
//  AgentKit
//
//  Source definitions for the Knowledge Backbone.
//  Sources represent where documents come from (Slack, files, RSS, etc.)
//

import Foundation

// MARK: - Source Type

/// Types of knowledge sources
public enum KSourceType: String, Sendable, Codable, CaseIterable {
    case slack          // Slack workspace
    case quip           // Quip documents
    case localFile      // Local files (txt, md, pdf, etc.)
    case notes          // Apple Notes
    case mail           // Apple Mail
    case rss            // RSS/Atom feeds
    case web            // Web pages
    case calendar       // Calendar events
    case reminders      // Apple Reminders
    case obsidian       // Obsidian vault
    case manual         // Manually added content

    public var displayName: String {
        switch self {
        case .slack: return "Slack"
        case .quip: return "Quip"
        case .localFile: return "Local Files"
        case .notes: return "Apple Notes"
        case .mail: return "Apple Mail"
        case .rss: return "RSS Feeds"
        case .web: return "Web Pages"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .obsidian: return "Obsidian"
        case .manual: return "Manual"
        }
    }

    public var icon: String {
        switch self {
        case .slack: return "bubble.left.and.bubble.right"
        case .quip: return "doc.text"
        case .localFile: return "folder"
        case .notes: return "note.text"
        case .mail: return "envelope"
        case .rss: return "dot.radiowaves.up.forward"
        case .web: return "globe"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .obsidian: return "brain"
        case .manual: return "square.and.pencil"
        }
    }
}

// MARK: - Source

/// A configured knowledge source
public struct KSource: Sendable, Identifiable, Codable {
    public let id: String
    public let type: KSourceType
    public let name: String
    public var config: KSourceConfig
    public var lastSync: Date?
    public var syncCursor: String?      // For incremental sync (e.g., Slack oldest ts)
    public var status: KSourceStatus
    public var errorMessage: String?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        type: KSourceType,
        name: String,
        config: KSourceConfig = KSourceConfig(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.config = config
        self.lastSync = nil
        self.syncCursor = nil
        self.status = .active
        self.errorMessage = nil
        self.createdAt = createdAt
    }
}

// MARK: - Source Status

/// Current status of a source
public enum KSourceStatus: String, Sendable, Codable {
    case active         // Ready to sync
    case syncing        // Currently syncing
    case paused         // Temporarily disabled
    case error          // Has errors
    case disabled       // Permanently disabled
}

// MARK: - Source Config

/// Configuration for a knowledge source
public struct KSourceConfig: Sendable, Codable {
    // Common settings
    public var syncInterval: TimeInterval?      // Auto-sync interval (nil = manual only)
    public var maxDocuments: Int?               // Limit number of documents
    public var includePatterns: [String]?       // Glob patterns to include
    public var excludePatterns: [String]?       // Glob patterns to exclude

    // Slack-specific
    public var slackChannels: [String]?         // Channel IDs to index (nil = all)
    public var slackIncludeDMs: Bool?
    public var slackIncludeThreads: Bool?

    // File-specific
    public var filePaths: [String]?             // Paths to index
    public var fileTypes: [String]?             // Extensions to include

    // RSS-specific
    public var rssUrls: [String]?               // Feed URLs

    // Web-specific
    public var webUrls: [String]?               // URLs to crawl
    public var webDepth: Int?                   // Crawl depth

    // Custom settings
    public var custom: [String: String]

    public init(
        syncInterval: TimeInterval? = nil,
        maxDocuments: Int? = nil,
        includePatterns: [String]? = nil,
        excludePatterns: [String]? = nil,
        custom: [String: String] = [:]
    ) {
        self.syncInterval = syncInterval
        self.maxDocuments = maxDocuments
        self.includePatterns = includePatterns
        self.excludePatterns = excludePatterns
        self.custom = custom
    }
}

// MARK: - Source Reference

/// Reference to a source from a document
public struct KSourceReference: Sendable, Codable {
    public let type: KSourceType
    public let sourceId: String
    public let ref: String?         // Source-specific reference

    public init(type: KSourceType, sourceId: String, ref: String? = nil) {
        self.type = type
        self.sourceId = sourceId
        self.ref = ref
    }
}

// MARK: - Sync Progress

/// Progress of a source sync operation
public struct KSyncProgress: Sendable {
    public let sourceId: String
    public let phase: SyncPhase
    public let documentsProcessed: Int
    public let documentsTotal: Int?
    public let chunksGenerated: Int
    public let embeddingsGenerated: Int
    public let startedAt: Date
    public var error: String?

    public var progress: Double? {
        guard let total = documentsTotal, total > 0 else { return nil }
        return Double(documentsProcessed) / Double(total)
    }

    public enum SyncPhase: String, Sendable {
        case fetching       // Getting documents from source
        case processing     // Chunking and preparing
        case embedding      // Generating embeddings
        case storing        // Saving to database
        case complete
        case failed
    }
}
