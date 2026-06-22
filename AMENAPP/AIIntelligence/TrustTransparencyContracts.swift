// TrustTransparencyContracts.swift
// AMENAPP
//
// Swift mirror of Contracts/trustTransparency.ts (TS is the source of truth).
// Keep shapes aligned: amend the TS file first, then regenerate this mirror.
//
// NON-NEGOTIABLE (build brief §2): every field here is fed by a REAL signal or
// omitted. No hardcoded metrics, no decorative confidence, no back-filled
// provenance. Where a shape extends an existing system, the canonical runtime
// type is named in the comment so we EXTEND rather than duplicate (a prior
// duplicate-type collision has broken a build before).
//
// All types are value types, Codable + Sendable, and use String for ISO-8601
// dates to preserve exact wire-shape parity with the TypeScript contract.

import Foundation

// MARK: - Constitutional Principles
//
// NEW — no pre-existing enum carries these named principles. NOT the same as
// BereanConstitutionalMode (ask/discern/build/guard/reflect), which is an
// epistemic mode and is deliberately not reused here.

enum ConstitutionalPrinciple: String, Codable, Sendable, CaseIterable {
    case truthBeforeVirality
    case contextBeforeOutrage
    case dignityBeforeEngagement
    case restorationBeforePunishment
    case humansBeforeAlgorithms
    case safetyScalesWithCapability
}

// MARK: - Shared Confidence Primitive
//
// A band MUST carry the basis that produced it (brief §2.2). `score` is present
// only when a principled numeric signal exists; otherwise omitted, never invented.

enum ConfidenceBand: String, Codable, Sendable {
    case low
    case medium
    case high
}

struct ReceiptConfidence: Codable, Sendable, Equatable {
    let band: ConfidenceBand
    /// Human-readable basis, e.g. "3 sources agree" / "limited sources". REQUIRED.
    let basis: String
    /// Optional principled numeric signal in [0,1]. Omit when no real signal exists.
    let score: Double?

    init(band: ConfidenceBand, basis: String, score: Double? = nil) {
        self.band = band
        self.basis = basis
        self.score = score
    }
}

// MARK: - AIReceipt (Wave 1)
//
// DERIVED from the real BereanPipelineResponse (BereanConstitutionalPipeline.swift):
// sources ← evidence[], confidence ← trustScore + evidence agreement,
// unknowns ← unknowns[], safetyChecksPassed ← pipeline review stages.
// Never fabricates sources.

enum ReceiptSourceType: String, Codable, Sendable {
    case scripture
    case commentary
    case userNote
    case web
}

struct ReceiptSource: Codable, Sendable, Identifiable, Equatable {
    /// Stable identity for SwiftUI lists; locator is unique per receipt.
    var id: String { locator }
    let title: String
    let type: ReceiptSourceType
    /// Real locator: verse ref, chunk id, URL, or note id.
    let locator: String
    /// Real retrieval score in [0,1] when available; nil if the pipeline returned none.
    let retrievalScore: Double?

    init(title: String, type: ReceiptSourceType, locator: String, retrievalScore: Double? = nil) {
        self.title = title
        self.type = type
        self.locator = locator
        self.retrievalScore = retrievalScore
    }
}

struct AIReceipt: Codable, Sendable, Identifiable, Equatable {
    /// Maps to BereanPipelineResponse.traceId.
    var id: String { responseId }
    let responseId: String
    let mode: String
    let sources: [ReceiptSource]
    let confidence: ReceiptConfidence
    let unknowns: [String]
    /// ISO-8601 string.
    let lastUpdated: String
    /// Names of pipeline review stages that passed (real, not decorative).
    let safetyChecksPassed: [String]
}

// MARK: - ModerationReceipt (Wave 2)
//
// COMPLEMENTS the existing append-only ModerationAuditEntry (ModerationAuditLog.swift)
// and ModerationAppeal. User-facing projection that names the principle invoked.

enum ModerationAction: String, Codable, Sendable {
    case hidden
    case downranked
    case warned
    case removed
    case allowed
}

enum AppealStatus: String, Codable, Sendable {
    case none
    case available
    case submitted
    case underReview
    case upheld
    case overturned
}

struct ModerationReceipt: Codable, Sendable, Identifiable, Equatable {
    var id: String { eventId }
    let eventId: String
    let action: ModerationAction
    let principleInvoked: ConstitutionalPrinciple
    let confidence: ReceiptConfidence
    /// Real model identifier used for the decision, e.g. "nemo-guard" / "vision-llm".
    let modelUsed: String
    /// The concrete rule that triggered, from the existing policy framework.
    let ruleTriggered: String
    let appealStatus: AppealStatus
    let humanReviewAvailable: Bool
}

// MARK: - MemoryLedgerEntry (Wave 3)
//
// NEW — Living Memory UI is dormant. Entries reflect the user's real per-user
// namespace; delete/edit operations hit the real store.

struct MemoryLedgerEntry: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let summary: String
    /// Per-user isolation namespace, e.g. "users/{uid}/berean_memory".
    let namespace: String
    let whyStored: String
    /// ISO-8601.
    let storedAt: String
    /// ISO-8601; nil if never used since storage.
    let lastUsedAt: String?
    let usageCount: Int
    let editable: Bool
    let deletable: Bool
}

// MARK: - TrustProvenanceLabel (Wave 4)
//
// RECONCILES with the canonical runtime type MediaProvenance (SocialOSModels.swift)
// and ONEProvenanceLabel. Named distinctly to avoid a duplicate-type collision.
// Wave 4 maps this onto MediaProvenance rather than adding a second store.

enum ProvenanceOrigin: String, Codable, Sendable {
    case human
    case aiAssisted = "ai_assisted"
    case aiGenerated = "ai_generated"
}

enum ProvenanceActor: String, Codable, Sendable {
    case human
    case ai
}

struct ProvenanceEdit: Codable, Sendable, Equatable {
    let actor: ProvenanceActor
    /// ISO-8601.
    let at: String
    let summary: String
}

struct TrustProvenanceLabel: Codable, Sendable, Identifiable, Equatable {
    var id: String { contentId }
    let contentId: String
    /// Written at creation time from the real pipeline; never back-filled.
    let origin: ProvenanceOrigin
    let editHistory: [ProvenanceEdit]
}

// MARK: - FlourishingMetrics (Wave 5)
//
// NEW — anti-engagement. `eventSource` is MANDATORY: a signal with no real
// source is OMITTED, never zero-filled. No leaderboards, no streaks.

struct FlourishingSignal: Codable, Sendable, Identifiable, Equatable {
    var id: String { key }
    let key: String
    let value: Double
    /// REQUIRED real event source, e.g. "conversations.meaningful" Firestore counter.
    let eventSource: String
}

struct FlourishingMetrics: Codable, Sendable, Equatable {
    /// ISO-8601 date of the week start.
    let weekOf: String
    let signals: [FlourishingSignal]
}

// MARK: - RedTeamReport (Wave 6)
//
// NEW — registry starts EMPTY and fills with real submissions only.

enum RedTeamCategory: String, Codable, Sendable {
    case moderation
    case scam
    case jailbreak
    case aiFailure = "ai_failure"
}

enum RedTeamStatus: String, Codable, Sendable {
    case submitted
    case triaging
    case confirmed
    case rejected
    case fixed
}

struct RedTeamReport: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let category: RedTeamCategory
    let description: String
    let reproSteps: String
    let status: RedTeamStatus
    let reporterId: String
    /// True only after a human confirms the report is valid.
    let recognitionAwarded: Bool
}

// MARK: - RecommendationExplanation (Wave 6)
//
// BRIDGES the existing FeedExplanation / FeedReasonCode (CommunityContractsModels.swift).
// Factors and weights are real ranking inputs, never invented reasons.

enum RecommendationFactorKind: String, Codable, Sendable {
    case followedCreator
    case communityMembership
    case sharedInterest
    case recentActivity
}

struct RecommendationFactor: Codable, Sendable, Identifiable, Equatable {
    var id: String { factor.rawValue }
    let factor: RecommendationFactorKind
    /// Real contribution weight in [0,1].
    let weight: Double
}

struct RecommendationExplanation: Codable, Sendable, Identifiable, Equatable {
    var id: String { itemId }
    let itemId: String
    let factors: [RecommendationFactor]
}
