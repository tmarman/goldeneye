//
//  Entity.swift
//  AgentKit
//
//  Entity models for the Knowledge Backbone.
//  Entities are extracted from documents and linked to form a knowledge graph.
//

import Foundation

// MARK: - Entity

/// An entity extracted from documents (person, project, concept, etc.)
public struct KEntity: Sendable, Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let type: KEntityType
    public var canonicalName: String?       // Normalized/deduplicated name
    public var attributes: [String: String]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        type: KEntityType,
        canonicalName: String? = nil,
        attributes: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.canonicalName = canonicalName
        self.attributes = attributes
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// Display name (canonical if available, otherwise original)
    public var displayName: String {
        canonicalName ?? name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: KEntity, rhs: KEntity) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Entity Type

/// Types of entities we extract
public enum KEntityType: String, Sendable, Codable, CaseIterable {
    case person         // People (colleagues, contacts)
    case organization   // Companies, teams, groups
    case project        // Projects, initiatives
    case product        // Products, features
    case concept        // Technical concepts, ideas
    case decision       // Decisions made
    case event          // Events, meetings
    case location       // Places
    case date           // Dates, deadlines
    case url            // Links
    case file           // File references
    case other

    public var displayName: String {
        switch self {
        case .person: return "Person"
        case .organization: return "Organization"
        case .project: return "Project"
        case .product: return "Product"
        case .concept: return "Concept"
        case .decision: return "Decision"
        case .event: return "Event"
        case .location: return "Location"
        case .date: return "Date"
        case .url: return "URL"
        case .file: return "File"
        case .other: return "Other"
        }
    }

    public var icon: String {
        switch self {
        case .person: return "person"
        case .organization: return "building.2"
        case .project: return "folder"
        case .product: return "shippingbox"
        case .concept: return "lightbulb"
        case .decision: return "checkmark.seal"
        case .event: return "calendar"
        case .location: return "location"
        case .date: return "clock"
        case .url: return "link"
        case .file: return "doc"
        case .other: return "tag"
        }
    }
}

// MARK: - Entity Mention

/// A mention of an entity in a specific chunk
public struct KEntityMention: Sendable, Identifiable, Codable {
    public let id: String
    public let entityId: String
    public let chunkId: String
    public let startChar: Int?
    public let endChar: Int?
    public let context: String?         // Surrounding text for context
    public let confidence: Float

    public init(
        id: String = UUID().uuidString,
        entityId: String,
        chunkId: String,
        startChar: Int? = nil,
        endChar: Int? = nil,
        context: String? = nil,
        confidence: Float = 1.0
    ) {
        self.id = id
        self.entityId = entityId
        self.chunkId = chunkId
        self.startChar = startChar
        self.endChar = endChar
        self.context = context
        self.confidence = confidence
    }
}

// MARK: - Entity Relation

/// A relationship between two entities
public struct KEntityRelation: Sendable, Identifiable, Codable {
    public let id: String
    public let sourceEntityId: String
    public let targetEntityId: String
    public let relationType: KRelationType
    public let confidence: Float
    public let evidenceChunkId: String?     // Chunk that contains evidence
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        sourceEntityId: String,
        targetEntityId: String,
        relationType: KRelationType,
        confidence: Float = 1.0,
        evidenceChunkId: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sourceEntityId = sourceEntityId
        self.targetEntityId = targetEntityId
        self.relationType = relationType
        self.confidence = confidence
        self.evidenceChunkId = evidenceChunkId
        self.metadata = metadata
    }
}

// MARK: - Relation Type

/// Types of relationships between entities
public enum KRelationType: String, Sendable, Codable, CaseIterable {
    case worksOn        // person works on project
    case memberOf       // person is member of organization
    case manages        // person manages person/project
    case relatedTo      // generic relation
    case mentions       // document mentions entity
    case decidedBy      // decision made by person
    case createdBy      // created by person
    case partOf         // is part of (project part of initiative)
    case dependsOn      // depends on
    case blocks         // blocks
    case references     // references (doc references another)

    public var displayName: String {
        switch self {
        case .worksOn: return "works on"
        case .memberOf: return "member of"
        case .manages: return "manages"
        case .relatedTo: return "related to"
        case .mentions: return "mentions"
        case .decidedBy: return "decided by"
        case .createdBy: return "created by"
        case .partOf: return "part of"
        case .dependsOn: return "depends on"
        case .blocks: return "blocks"
        case .references: return "references"
        }
    }

    /// Whether this relation is directional
    public var isDirectional: Bool {
        switch self {
        case .relatedTo: return false
        default: return true
        }
    }
}

// MARK: - Entity with Relations

/// An entity with its related entities
public struct KEntityWithRelations: Sendable {
    public let entity: KEntity
    public let mentions: [KEntityMention]
    public let outgoingRelations: [(relation: KEntityRelation, target: KEntity)]
    public let incomingRelations: [(relation: KEntityRelation, source: KEntity)]

    public var allRelatedEntities: [KEntity] {
        let outgoing = outgoingRelations.map { $0.target }
        let incoming = incomingRelations.map { $0.source }
        return Array(Set(outgoing + incoming))
    }
}
