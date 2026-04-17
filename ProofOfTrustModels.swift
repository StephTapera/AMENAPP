//
//  ProofOfTrustModels.swift
//  AMENAPP
//
//  Domain models for Proof of Human and Proof of Care — internal trust signals
//  that measure authenticity and meaningful follow-through. These are NEVER
//  surfaced as public scores or gamified badges. They serve as inputs to
//  eligibility, gating, ranking, and safety decisions.
//
//  Firestore paths:
//    users/{userId}/trust/proofSnapshots/{snapshotId}
//    users/{userId}/trust/events/{eventId}
//    users/{userId}/trust/humanScore  (latest computed score)
//    users/{userId}/trust/careScore   (latest computed score)
//

import Foundation

// MARK: - Proof of Human

/// Aggregated score representing how likely a user is a genuine human.
/// Range: 0.0–1.0 where 1.0 = high confidence of authentic human behavior.
struct ProofOfHumanScore: Codable, Equatable {
    let userId: String
    let score: Double                     // 0.0–1.0
    let confidence: Double                // 0.0–1.0 how confident we are in this score
    let factors: [HumanSignalFactor]
    let computedAt: Date
    let snapshotId: String                // Links to the snapshot that produced this
    let version: String                   // Scoring algorithm version for auditability
    
    /// Whether this score meets the minimum threshold for "likely human".
    var meetsHumanThreshold: Bool {
        score >= 0.5 && confidence >= 0.3
    }
}

/// An individual signal factor contributing to the Proof of Human score.
struct HumanSignalFactor: Codable, Equatable {
    let factorType: HumanFactorType
    let value: Double                     // Raw signal value (0.0–1.0)
    let weight: Double                    // How much this factor counts
    let direction: SignalDirection         // Positive or negative indicator
    let source: String                    // Where this data came from
    let measuredAt: Date
    
    /// The weighted contribution of this factor to the overall score.
    var contribution: Double {
        value * weight * (direction == .positive ? 1.0 : -1.0)
    }
}

enum HumanFactorType: String, Codable, CaseIterable {
    // Positive signals
    case typedVsPastedRatio     = "typed_vs_pasted_ratio"       // From ComposerIntegrityTracker
    case accountMaturity        = "account_maturity"            // Days since account creation
    case deviceConsistency      = "device_consistency"          // Same device patterns
    case typingCadence          = "typing_cadence"              // Natural typing patterns
    case sessionBehavior        = "session_behavior"            // Human-like session patterns
    case emailVerified          = "email_verified"
    case phoneVerified          = "phone_verified"
    case profileCompleteness    = "profile_completeness"        // Has photo, bio, etc.
    case socialGraphDepth       = "social_graph_depth"          // Mutual connections
    case contentVariety         = "content_variety"             // Diverse post topics
    
    // Negative signals (reduce human score)
    case rapidPostingPattern    = "rapid_posting_pattern"       // Suspicious posting cadence
    case repetitiveContent      = "repetitive_content"          // Copy-paste behavior
    case bulkFollowUnfollow     = "bulk_follow_unfollow"        // Bot-like follow churn
    case moderationHits         = "moderation_hits"             // Content flagged by moderation
    case aiContentDetection     = "ai_content_detection"        // AI-generated content signals
    case suspiciousEditCadence  = "suspicious_edit_cadence"     // Rapid edit patterns
    case accountAgeVsActivity   = "account_age_vs_activity"     // New account + high activity

    var isPositive: Bool {
        switch self {
        case .typedVsPastedRatio, .accountMaturity, .deviceConsistency,
             .typingCadence, .sessionBehavior, .emailVerified, .phoneVerified,
             .profileCompleteness, .socialGraphDepth, .contentVariety:
            return true
        default:
            return false
        }
    }
}

// MARK: - Proof of Care

/// Aggregated score representing meaningful follow-through and care quality.
/// Range: 0.0–1.0 where 1.0 = consistently high-quality care engagement.
struct ProofOfCareScore: Codable, Equatable {
    let userId: String
    let score: Double                     // 0.0–1.0
    let confidence: Double                // 0.0–1.0
    let factors: [CareSignalFactor]
    let computedAt: Date
    let snapshotId: String
    let version: String
    
    /// Whether this score indicates reliable care behavior.
    var meetsCareThreshold: Bool {
        score >= 0.4 && confidence >= 0.3
    }
}

/// An individual signal factor contributing to the Proof of Care score.
struct CareSignalFactor: Codable, Equatable {
    let factorType: CareFactorType
    let value: Double                     // 0.0–1.0
    let weight: Double
    let direction: SignalDirection
    let source: String
    let measuredAt: Date
    
    var contribution: Double {
        value * weight * (direction == .positive ? 1.0 : -1.0)
    }
}

enum CareFactorType: String, Codable, CaseIterable {
    // Positive signals
    case meaningfulReplies        = "meaningful_replies"          // Substantive (not "lol") replies
    case prayerFollowThrough      = "prayer_follow_through"      // Committed to prayer + followed up
    case checkInCompletion        = "check_in_completion"         // Completed check-in flows
    case supportActionCompletion  = "support_action_completion"   // Completed action thread steps
    case consistentEngagement     = "consistent_engagement"       // Regular, not bursty, activity
    case reciprocalInteractions   = "reciprocal_interactions"     // Gives as much as receives
    case communityHelpfulness     = "community_helpfulness"       // Helpful answers, shared resources
    case healthyResponsePatterns  = "healthy_response_patterns"   // Not reactive, measured
    case longTermRelationships    = "long_term_relationships"     // Sustained connections over time
    case actionThreadParticipation = "action_thread_participation" // Active in support workflows
    
    // Negative signals
    case driveByBehavior          = "drive_by_behavior"           // One-off interactions, no follow-through
    case brigading                = "brigading"                   // Coordinated negative behavior
    case pileOnBehavior           = "pile_on_behavior"            // Joining dog-piles on posts
    case fakeCarePatterns         = "fake_care_patterns"          // Performative care (AI-generated, copy-paste)
    case abandonedCommitments     = "abandoned_commitments"       // Started but never completed care flows
    case spamInteractions         = "spam_interactions"           // Low-quality mass interactions

    var isPositive: Bool {
        switch self {
        case .meaningfulReplies, .prayerFollowThrough, .checkInCompletion,
             .supportActionCompletion, .consistentEngagement, .reciprocalInteractions,
             .communityHelpfulness, .healthyResponsePatterns, .longTermRelationships,
             .actionThreadParticipation:
            return true
        default:
            return false
        }
    }
}

// MARK: - Shared Signal Types

enum SignalDirection: String, Codable {
    case positive = "positive"
    case negative = "negative"
}

// MARK: - Trust Event

/// An immutable record of a trust-relevant event. Events are the raw data that
/// feeds into score computation. They are append-only.
struct TrustEvent: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let eventType: TrustEventType
    let category: TrustEventCategory      // human, care, or both
    let value: Double                     // Magnitude of the event
    let source: String                    // Service that created this event
    let relatedEntityId: String?          // Post ID, thread ID, etc.
    let timestamp: Date
    let metadata: [String: String]?
    
    enum TrustEventType: String, Codable {
        // Human events
        case postCreated            = "post_created"
        case commentCreated         = "comment_created"
        case contentFlagged         = "content_flagged"
        case accountVerified        = "account_verified"
        case suspiciousPattern      = "suspicious_pattern"
        case composerIntegrity      = "composer_integrity"
        
        // Care events
        case prayerCommitment       = "prayer_commitment"
        case prayerFollowUp         = "prayer_follow_up"
        case checkInCompleted       = "check_in_completed"
        case actionStepCompleted    = "action_step_completed"
        case meaningfulReply        = "meaningful_reply"
        case supportThreadJoined    = "support_thread_joined"
        case commitmentAbandoned    = "commitment_abandoned"
        
        // Combined
        case moderationAction       = "moderation_action"
        case blockReceived          = "block_received"
        case reportReceived         = "report_received"
    }
    
    enum TrustEventCategory: String, Codable {
        case human     = "human"
        case care      = "care"
        case both      = "both"
    }
}

// MARK: - Trust Score Snapshot

/// A point-in-time snapshot of all trust scores. Snapshots are the audit trail
/// that makes trust computation transparent and reversible.
struct TrustScoreSnapshot: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let humanScore: ProofOfHumanScore
    let careScore: ProofOfCareScore
    let computedAt: Date
    let algorithmVersion: String          // For reproducibility
    let eventWindowStart: Date            // Oldest event considered
    let eventWindowEnd: Date              // Newest event considered
    let eventCount: Int                   // How many events were in the window
    let previousSnapshotId: String?       // Links to prior snapshot for diffing
}

// MARK: - Trust Eligibility

/// A computed eligibility gate based on trust scores. Used to determine whether
/// a user qualifies for certain features or privileges.
struct TrustEligibility: Codable, Equatable {
    let userId: String
    let feature: String                   // Feature being gated
    let isEligible: Bool
    let reason: String                    // Why eligible or not
    let humanScoreRequired: Double        // Minimum human score needed
    let careScoreRequired: Double         // Minimum care score needed
    let actualHumanScore: Double
    let actualCareScore: Double
    let evaluatedAt: Date
}

// MARK: - Trust Action Constraint

/// Defines constraints on user actions based on trust scores. These are
/// configurable and can be adjusted without code changes.
struct TrustActionConstraint: Codable, Equatable {
    let action: String                    // "create_action_thread", "invite_participants", etc.
    let minimumHumanScore: Double         // 0.0–1.0
    let minimumCareScore: Double          // 0.0–1.0
    let minimumAccountAgeDays: Int
    let requiresVerification: Bool        // Email or phone verified
    let description: String               // Human-readable explanation
    
    /// Default constraints for common actions.
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
