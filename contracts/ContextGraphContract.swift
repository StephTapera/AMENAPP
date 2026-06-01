// ContextGraphContract.swift
// AMEN Intelligence Layer Phase 0
//
// FROZEN CONTRACT: Context Graph schema. Do not edit without Lead Orchestrator approval.

import Foundation

// MARK: - Identity

struct ContextGraphNodeID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct ContextGraphEdgeID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct AmenTrustBoundaryID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - Nodes

enum ContextGraphNodeKind: String, Codable, CaseIterable, Hashable, Sendable {
    case person
    case place
    case community
    case note
    case conversation
    case document
    case event
    case scriptureReference
}

struct ContextGraphNode: Identifiable, Codable, Hashable, Sendable {
    let id: ContextGraphNodeID
    let kind: ContextGraphNodeKind
    var displayName: String
    var summary: String?
    var trustBoundaryID: AmenTrustBoundaryID
    var createdAt: Date
    var updatedAt: Date
    var payload: ContextGraphNodePayload
}

enum ContextGraphNodePayload: Codable, Hashable, Sendable {
    case person(PersonNodePayload)
    case place(PlaceNodePayload)
    case community(CommunityNodePayload)
    case note(NoteNodePayload)
    case conversation(ConversationNodePayload)
    case document(DocumentNodePayload)
    case event(EventNodePayload)
    case scriptureReference(ScriptureReferenceNodePayload)
}

struct PersonNodePayload: Codable, Hashable, Sendable {
    var userID: String?
    var contactID: String?
    var relationshipLabels: [String]
}

struct PlaceNodePayload: Codable, Hashable, Sendable {
    var placeID: String?
    var latitude: Double?
    var longitude: Double?
    var address: String?
    var churchPublishedDataID: String?
}

struct CommunityNodePayload: Codable, Hashable, Sendable {
    var communityID: String
    var ownerUserID: String?
    var spaceID: String?
}

struct NoteNodePayload: Codable, Hashable, Sendable {
    var notebookHint: NoteNotebookHint
    var sourceObjectID: String?
    var authorUserID: String?
}

enum NoteNotebookHint: String, Codable, CaseIterable, Hashable, Sendable {
    case church
    case work
    case meeting
    case idea
    case journal
    case recipe
    case relationship
    case uncategorized
}

struct ConversationNodePayload: Codable, Hashable, Sendable {
    var conversationID: String
    var participantNodeIDs: [ContextGraphNodeID]
    var channelKind: ConversationChannelKind
}

enum ConversationChannelKind: String, Codable, CaseIterable, Hashable, Sendable {
    case amenMessage
    case groupThread
    case voiceSession
    case externalImport
}

struct DocumentNodePayload: Codable, Hashable, Sendable {
    var documentID: String
    var documentKind: DocumentNodeKind
    var ownerUserID: String?
}

enum DocumentNodeKind: String, Codable, CaseIterable, Hashable, Sendable {
    case churchNotes
    case decisionTrail
    case lessonPlan
    case sharedDraft
    case sourcePacket
}

struct EventNodePayload: Codable, Hashable, Sendable {
    var eventID: String
    var startsAt: Date?
    var endsAt: Date?
    var calendarID: String?
}

struct ScriptureReferenceNodePayload: Codable, Hashable, Sendable {
    var translation: String
    var book: String
    var chapter: Int
    var startVerse: Int?
    var endVerse: Int?
}

// MARK: - Edges

enum ContextGraphEdgeKind: String, Codable, CaseIterable, Hashable, Sendable {
    case mentionedIn
    case attended
    case authored
    case derivedFrom
    case repliedTo
    case scheduledFor
    case locatedAt
    case memberOf
    case relatedTo
    case citesScripture
    case decidedIn
    case assignedTo
}

struct ContextGraphEdge: Identifiable, Codable, Hashable, Sendable {
    let id: ContextGraphEdgeID
    let kind: ContextGraphEdgeKind
    let sourceNodeID: ContextGraphNodeID
    let targetNodeID: ContextGraphNodeID
    var confidence: Double
    var createdAt: Date
    var provenance: ProvenanceChain
    var requiresHumanConfirmation: Bool
}

struct ContextGraphSnapshot: Codable, Hashable, Sendable {
    var nodes: [ContextGraphNode]
    var edges: [ContextGraphEdge]
}

protocol ContextGraphStoreProtocol {
    func upsertNode(_ node: ContextGraphNode) async throws
    func upsertEdge(_ edge: ContextGraphEdge) async throws
    func node(id: ContextGraphNodeID, within trustBoundaryID: AmenTrustBoundaryID) async throws -> ContextGraphNode?
    func neighbors(of nodeID: ContextGraphNodeID, within trustBoundaryID: AmenTrustBoundaryID) async throws -> ContextGraphSnapshot
}
