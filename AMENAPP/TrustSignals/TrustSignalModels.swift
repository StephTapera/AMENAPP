// TrustSignalModels.swift
// AMENAPP — Proof of Human + Proof of Care
//
// Domain models for internal trust signals. These are NEVER surfaced as
// public scores or gamified badges. They serve as inputs to eligibility,
// gating, ranking, and safety decisions.
//
import Foundation

// MARK: - Trust Signal Direction

/// Indicates whether a signal contributes positively or negatively to a trust score.
/// Distinct from SupportEnums.SignalDirection (which represents support need direction).
enum TrustSignalDirection: String, Codable {
    case positive = "positive"
    case negative = "negative"
}

// MARK: - Proof of Human

/// Aggregated score representing how likely a user is a genuine human.
/// Range: 0.0–1.0 where 1.0 = high confidence of authentic human behavior.
struct ProofOfHumanScore: Codable, Equatable {
    let userId: String
    let score: Double
    let confidence: Double
    let factors: [HumanSignalFactor]
    let computedAt: Date
    let snapshotId: String
    let version: String

    var meetsHumanThreshold: Bool {
        score >= 0.5 && confidence >= 0.3
    }
}

/// An individual signal factor contributing to the Proof of Human score.
struct HumanSignalFactor: Codable, Equatable {
    let factorType: HumanFactorType
    let value: Double
    let weight: Double
    let direction: TrustSignalDirection
    let source: String
    let measuredAt: Date

    var contribution: Double {
        value * weight * (direction == .positive ? 1.0 : -1.0)
    }
}

enum HumanFactorType: String, Codable, CaseIterable {
    case typedVsPastedRatio     = "typed_vs_pasted_ratio"
    case accountMaturity        = "account_maturity"
    case contentVariety         = "content_variety"
    case socialGraphDepth       = "social_graph_depth"
    case moderationHits         = "moderation_hits"
    case rapidPostingPattern    = "rapid_posting_pattern"
}

// MARK: - Proof of Care

struct ProofOfCareScore: Codable, Equatable {
    let userId: String
    let score: Double
    let confidence: Double
    let factors: [CareSignalFactor]
    let computedAt: Date
    let snapshotId: String
    let version: String

    var meetsCareThreshold: Bool {
        score >= 0.4 && confidence >= 0.3
    }
}

struct CareSignalFactor: Codable, Equatable {
    let factorType: CareFactorType
    let value: Double
    let weight: Double
    let direction: TrustSignalDirection
    let source: String
    let measuredAt: Date

    var contribution: Double {
        value * weight * (direction == .positive ? 1.0 : -1.0)
    }
}

enum CareFactorType: String, Codable, CaseIterable {
    case prayerFollowThrough      = "prayer_follow_through"
    case supportActionCompletion  = "support_action_completion"
    case meaningfulReplies        = "meaningful_replies"
    case checkInCompletion        = "check_in_completion"
    case consistentEngagement     = "consistent_engagement"
    case abandonedCommitments     = "abandoned_commitments"
    case driveByBehavior          = "drive_by_behavior"
}

// MARK: - Trust Event

struct TrustEvent: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let eventType: TrustEventType
    let category: TrustEventCategory
    let value: Double
    let source: String
    let relatedEntityId: String?
    let timestamp: Date
    let metadata: [String: String]?

    enum TrustEventType: String, Codable {
        case postCreated            = "post_created"
        case commentCreated         = "comment_created"
        case contentFlagged         = "content_flagged"
        case accountVerified        = "account_verified"
        case suspiciousPattern      = "suspicious_pattern"
        case composerIntegrity      = "composer_integrity"
        case prayerCommitment       = "prayer_commitment"
        case prayerFollowUp         = "prayer_follow_up"
        case checkInCompleted       = "check_in_completed"
        case actionStepCompleted    = "action_step_completed"
        case meaningfulReply        = "meaningful_reply"
        case supportThreadJoined    = "support_thread_joined"
        case commitmentAbandoned    = "commitment_abandoned"
        case moderationAction       = "moderation_action"
        case blockReceived          = "block_received"
        case reportReceived         = "report_received"
    }

    enum TrustEventCategory: String, Codable {
        case human = "human"
        case care  = "care"
        case both  = "both"
    }
}

// MARK: - Trust Score Snapshot

struct TrustScoreSnapshot: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let humanScore: ProofOfHumanScore
    let careScore: ProofOfCareScore
    let computedAt: Date
    let algorithmVersion: String
    let eventWindowStart: Date
    let eventWindowEnd: Date
    let eventCount: Int
    let previousSnapshotId: String?
}

// MARK: - Trust Eligibility

struct TrustEligibility: Codable, Equatable {
    let userId: String
    let feature: String
    let isEligible: Bool
    let reason: String
    let humanScoreRequired: Double
    let careScoreRequired: Double
    let actualHumanScore: Double
    let actualCareScore: Double
    let evaluatedAt: Date
}

// MARK: - Trust Action Constraint

struct TrustActionConstraint: Codable, Equatable {
    let action: String
    let minimumHumanScore: Double
    let minimumCareScore: Double
    let minimumAccountAgeDays: Int
    let requiresVerification: Bool
    let description: String

    static let createActionThread = TrustActionConstraint(
        action: "create_action_thread",
        minimumHumanScore: 0.3,
        minimumCareScore: 0.0,
        minimumAccountAgeDays: 3,
        requiresVerification: false,
        description: "Create a support workflow on a post"
    )

    static let inviteToThread = TrustActionConstraint(
        action: "invite_to_thread",
        minimumHumanScore: 0.4,
        minimumCareScore: 0.2,
        minimumAccountAgeDays: 7,
        requiresVerification: false,
        description: "Invite others to participate in a support flow"
    )

    static let suggestCareAction = TrustActionConstraint(
        action: "suggest_care_action",
        minimumHumanScore: 0.3,
        minimumCareScore: 0.3,
        minimumAccountAgeDays: 14,
        requiresVerification: true,
        description: "System suggests care actions based on user's history"
    )
}
