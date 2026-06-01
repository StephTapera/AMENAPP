// MemoryProvenanceContract.swift
// AMEN Intelligence Layer Phase 0
//
// FROZEN CONTRACT: Memory storage, retrieval, Pinecone namespace rules, and four-layer provenance.

import Foundation

// MARK: - Provenance

struct ProvenanceChain: Codable, Hashable, Sendable {
    var claimID: String
    var layers: FourLayerProvenance
    var generatedAt: Date

    var isComplete: Bool {
        layers.originalSource != nil &&
        layers.captureRecord != nil &&
        layers.processingRecord != nil &&
        layers.retrievalRecord != nil
    }
}

struct FourLayerProvenance: Codable, Hashable, Sendable {
    var originalSource: ProvenanceOriginalSource?
    var captureRecord: ProvenanceCaptureRecord?
    var processingRecord: ProvenanceProcessingRecord?
    var retrievalRecord: ProvenanceRetrievalRecord?
}

struct ProvenanceOriginalSource: Codable, Hashable, Sendable {
    var sourceID: String
    var sourceKind: ProvenanceSourceKind
    var title: String
    var authorNodeID: ContextGraphNodeID?
    var sourceURL: URL?
    var sourceTimestamp: Date?
    var scriptureReference: ScriptureReferenceNodePayload?
}

enum ProvenanceSourceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case humanNote
    case conversationMessage
    case audioRecording
    case document
    case churchPublishedData
    case calendarEvent
    case scriptureText
    case importedFile
}

struct ProvenanceCaptureRecord: Codable, Hashable, Sendable {
    var capturedByUserID: String?
    var capturedAt: Date
    var deviceID: String?
    var appVersion: String?
    var trustBoundaryID: AmenTrustBoundaryID
}

struct ProvenanceProcessingRecord: Codable, Hashable, Sendable {
    var processor: IntelligenceProcessorKind
    var callableProxyName: String?
    var modelName: String?
    var transform: ProvenanceTransformKind
    var processedAt: Date
    var humanReviewed: Bool
}

enum IntelligenceProcessorKind: String, Codable, CaseIterable, Hashable, Sendable {
    case human
    case bereanCallableProxy
    case deterministicParser
    case firestoreIndexer
    case pineconeIndexer
    case algoliaIndexer
}

enum ProvenanceTransformKind: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case transcription
    case translation
    case summary
    case embedding
    case sourceVerification
    case contextLinking
    case simplification
}

struct ProvenanceRetrievalRecord: Codable, Hashable, Sendable {
    var retrievedAt: Date
    var queryID: String
    var namespace: PineconeNamespace
    var rankingSignals: [MemoryRankingSignal]
    var confidence: Double
}

struct MemoryRankingSignal: Codable, Hashable, Sendable {
    var name: String
    var weight: Double
    var value: String
}

// MARK: - Memory

struct MemoryRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var nodeID: ContextGraphNodeID
    var trustBoundaryID: AmenTrustBoundaryID
    var ownerUserID: String
    var visibility: MemoryVisibility
    var claimText: String
    var embeddingText: String
    var tags: [String]
    var provenance: ProvenanceChain
    var createdAt: Date
    var updatedAt: Date
}

enum MemoryVisibility: String, Codable, CaseIterable, Hashable, Sendable {
    case privateToUser
    case sharedWithExplicitParticipants
    case creatorPrivateDashboard
    case churchPublished
}

struct MemoryWriteRequest: Codable, Hashable, Sendable {
    var record: MemoryRecord
    var namespace: PineconeNamespace
    var requiresHumanReview: Bool
}

struct MemoryRecallRequest: Codable, Hashable, Sendable {
    var query: String
    var requesterUserID: String
    var trustBoundaryID: AmenTrustBoundaryID
    var namespaces: [PineconeNamespace]
    var filters: MemoryRecallFilters
    var limit: Int
}

struct MemoryRecallFilters: Codable, Hashable, Sendable {
    var nodeKinds: [ContextGraphNodeKind]
    var startDate: Date?
    var endDate: Date?
    var minimumConfidence: Double
}

struct MemoryRecallResult: Identifiable, Codable, Hashable, Sendable {
    var id: String { memory.id }
    var memory: MemoryRecord
    var relevanceScore: Double
    var provenance: ProvenanceChain
}

struct PineconeNamespace: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static func personal(userID: String) -> PineconeNamespace {
        PineconeNamespace(rawValue: "personal_\(userID)")
    }

    static func conversation(conversationID: String, trustBoundaryID: AmenTrustBoundaryID) -> PineconeNamespace {
        PineconeNamespace(rawValue: "conversation_\(trustBoundaryID.rawValue)_\(conversationID)")
    }

    static func creatorPrivate(spaceID: String, creatorUserID: String) -> PineconeNamespace {
        PineconeNamespace(rawValue: "creator_private_\(creatorUserID)_\(spaceID)")
    }

    static func churchPublished(churchID: String) -> PineconeNamespace {
        PineconeNamespace(rawValue: "church_published_\(churchID)")
    }
}

protocol MemoryProvenanceStoreProtocol {
    func writeMemory(_ request: MemoryWriteRequest) async throws -> MemoryRecord
    func recall(_ request: MemoryRecallRequest) async throws -> [MemoryRecallResult]
    func provenance(for claimID: String, within trustBoundaryID: AmenTrustBoundaryID) async throws -> ProvenanceChain?
}
