// BereanIntelligenceAPIContract.swift
// AMEN Intelligence Layer Phase 0
//
// FROZEN CONTRACT: The only client-facing API surface for Berean Intelligence.

import Foundation

enum BereanCallableName: String, Codable, CaseIterable, Hashable, Sendable {
    case recall = "bereanRecallProxy"
    case summarizeContext = "bereanSummarizeContextProxy"
    case suggestFollowUp = "bereanSuggestFollowUpProxy"
    case linkThoughts = "bereanLinkThoughtsProxy"
    case detectNeed = "bereanDetectNeedProxy"
    case verifySource = "bereanVerifySourceProxy"
}

enum BereanCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case recall
    case summarizeContext
    case suggestFollowUp
    case linkThoughts
    case detectNeed
    case verifySource
}

struct BereanRequestEnvelope<Payload: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var requestID: String
    var requesterUserID: String
    var trustBoundaryID: AmenTrustBoundaryID
    var capability: BereanCapability
    var appCheckRequired: Bool
    var authRequired: Bool
    var payload: Payload
}

struct BereanResponseEnvelope<Payload: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var requestID: String
    var payload: Payload
    var provenance: [ProvenanceChain]
    var requiresHumanPreview: Bool
    var generatedAt: Date
}

struct BereanRecallPayload: Codable, Hashable, Sendable {
    var request: MemoryRecallRequest
}

struct BereanRecallResponse: Codable, Hashable, Sendable {
    var results: [MemoryRecallResult]
}

struct BereanSummarizeContextPayload: Codable, Hashable, Sendable {
    var rootNodeID: ContextGraphNodeID
    var graphSnapshot: ContextGraphSnapshot
    var purpose: ContextSummaryPurpose
}

enum ContextSummaryPurpose: String, Codable, CaseIterable, Hashable, Sendable {
    case contextBeforeReply
    case churchNotesDecisionTrail
    case creatorCommunityHealth
    case travelPreparation
    case notebookReview
}

struct BereanSummaryResponse: Codable, Hashable, Sendable {
    var summary: String
    var citedClaimIDs: [String]
    var suggestedNextActions: [HumanPreviewAction]
}

struct BereanSuggestFollowUpPayload: Codable, Hashable, Sendable {
    var conversationNodeID: ContextGraphNodeID
    var recentMessages: [String]
    var participantNodeIDs: [ContextGraphNodeID]
}

struct BereanFollowUpResponse: Codable, Hashable, Sendable {
    var suggestions: [HumanPreviewAction]
}

struct BereanLinkThoughtsPayload: Codable, Hashable, Sendable {
    var noteNodeID: ContextGraphNodeID
    var candidateNodeIDs: [ContextGraphNodeID]
    var queryText: String
}

struct BereanLinkThoughtsResponse: Codable, Hashable, Sendable {
    var proposedEdges: [ContextGraphEdge]
}

struct BereanDetectNeedPayload: Codable, Hashable, Sendable {
    var surface: AmenIntelligenceSurface
    var graphSnapshot: ContextGraphSnapshot
    var userVisibleContext: String
}

struct BereanDetectNeedResponse: Codable, Hashable, Sendable {
    var needs: [DetectedNeed]
}

struct DetectedNeed: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var kind: DetectedNeedKind
    var explanation: String
    var suggestedAction: HumanPreviewAction?
    var provenance: ProvenanceChain
}

enum DetectedNeedKind: String, Codable, CaseIterable, Hashable, Sendable {
    case unansweredQuestion
    case driftingMember
    case potentialMentor
    case newMemberConfusion
    case reminderCandidate
    case sourceVerificationNeeded
    case leaveNowTravelNudge
    case duplicateThought
}

struct BereanVerifySourcePayload: Codable, Hashable, Sendable {
    var claimText: String
    var candidateSources: [ProvenanceOriginalSource]
    var trustBoundaryID: AmenTrustBoundaryID
}

struct BereanVerifySourceResponse: Codable, Hashable, Sendable {
    var verification: SourceVerificationResult
}

struct SourceVerificationResult: Codable, Hashable, Sendable {
    var status: SourceVerificationStatus
    var matchedSource: ProvenanceOriginalSource?
    var provenance: ProvenanceChain?
    var explanation: String
}

enum SourceVerificationStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case verified
    case partial
    case unsupported
    case conflicting
}

enum AmenIntelligenceSurface: String, Codable, CaseIterable, Hashable, Sendable {
    case personalMemory
    case relationship
    case creatorSpace
    case lifeNavigation
    case collaborativeDocument
    case glassShell
}

struct HumanPreviewAction: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var kind: HumanPreviewActionKind
    var title: String
    var diffPreview: String
    var targetNodeID: ContextGraphNodeID?
    var requiresExplicitConfirmation: Bool
}

enum HumanPreviewActionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case sendMessage
    case postToSpace
    case scheduleReminder
    case shareDocument
    case mergeNotes
    case createContextEdge
    case startNavigation
    case dismiss
}

protocol BereanIntelligenceClientProtocol {
    func recall(_ envelope: BereanRequestEnvelope<BereanRecallPayload>) async throws -> BereanResponseEnvelope<BereanRecallResponse>
    func summarizeContext(_ envelope: BereanRequestEnvelope<BereanSummarizeContextPayload>) async throws -> BereanResponseEnvelope<BereanSummaryResponse>
    func suggestFollowUp(_ envelope: BereanRequestEnvelope<BereanSuggestFollowUpPayload>) async throws -> BereanResponseEnvelope<BereanFollowUpResponse>
    func linkThoughts(_ envelope: BereanRequestEnvelope<BereanLinkThoughtsPayload>) async throws -> BereanResponseEnvelope<BereanLinkThoughtsResponse>
    func detectNeed(_ envelope: BereanRequestEnvelope<BereanDetectNeedPayload>) async throws -> BereanResponseEnvelope<BereanDetectNeedResponse>
    func verifySource(_ envelope: BereanRequestEnvelope<BereanVerifySourcePayload>) async throws -> BereanResponseEnvelope<BereanVerifySourceResponse>
}
