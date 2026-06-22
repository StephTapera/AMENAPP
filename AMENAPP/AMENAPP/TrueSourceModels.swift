//
//  TrueSourceModels.swift
//  AMENAPP
//
//  Canonical True Source data models for posts and media.
//  These sub-objects are the authoritative safety, provenance, context,
//  and ranking metadata for every piece of content in the system.
//
//  IMPORTANT: All fields in these structs are written exclusively by the
//  backend (Cloud Functions / moderation pipeline). Firestore rules must
//  deny client writes to the parent post document fields that map here.
//  Clients may read labels and safety status for visible posts.
//  Private audit details (riskScores, moderatorReason) are admin-only.
//

import Foundation
import FirebaseFirestore

// MARK: - Provenance Status

enum ProvenanceStatus: String, Codable, CaseIterable {
    case original       = "original"
    case repost         = "repost"
    case edited         = "edited"
    case aiGenerated    = "ai_generated"
    case unknown        = "unknown"
}

// MARK: - Distribution Decision

enum DistributionDecision: String, Codable, CaseIterable {
    case allow                  = "allow"
    case allowWithLabel         = "allow_with_label"
    case reduceReach            = "reduce_reach"
    case askToRevise            = "ask_to_revise"
    case limitComments          = "limit_comments"
    case limitShares            = "limit_shares"
    case humanReview            = "human_review"
    case ageGate                = "age_gate"
    case crisisIntervention     = "crisis_intervention"
    case remove                 = "remove"

    var isVisible: Bool {
        switch self {
        case .remove, .humanReview: return false
        default: return true
        }
    }

    var reducesReach: Bool {
        switch self {
        case .reduceReach, .limitComments, .limitShares, .ageGate: return true
        default: return false
        }
    }
}

// MARK: - Moderation Status

enum ContentModerationStatus: String, Codable, CaseIterable {
    case pending            = "pending"
    case approved           = "approved"
    case approvedLimited    = "approved_limited"
    case needsRevision      = "needs_revision"
    case humanReview        = "human_review"
    case removed            = "removed"

    var isPubliclyVisible: Bool {
        switch self {
        case .approved, .approvedLimited: return true
        default: return false
        }
    }
}

// MARK: - Reviewer Type

enum ReviewerType: String, Codable {
    case ai     = "ai"
    case human  = "human"
    case hybrid = "hybrid"
}

// MARK: - Content Type

enum ContentContextType: String, Codable, CaseIterable {
    case educational            = "educational"
    case personalStory          = "personal_story"
    case satire                 = "satire"
    case sensitiveNews          = "sensitive_news"
    case faithBeliefContent     = "faith_belief_content"
    case healthClaim            = "health_claim"
    case publicFigure           = "public_figure"
    case privatePerson          = "private_person"
    case graphicContext         = "graphic_context"
    case unverifiedClaim        = "unverified_claim"
    case unknown                = "unknown"
}

// MARK: - TrueSourceMetadata

/// Provenance and authenticity metadata for a post or media item.
/// Written exclusively by the backend moderation pipeline.
struct TrueSourceMetadata: Codable, Equatable {
    /// Composite score (0–1.0): how likely the content is authentic and unmanipulated
    var sourceIntegrityScore: Double
    /// Score (0–1.0): likelihood the content originated from this author
    var originalityScore: Double
    /// Score (0–1.0): overall authenticity signal
    var authenticityScore: Double
    /// Score (0–1.0): probability of meaningful manipulation
    var manipulationRisk: Double
    /// Confidence in the context interpretation (0–1.0)
    var contextConfidence: Double
    /// Author's account-level trust score (0–1.0)
    var accountTrustScore: Double
    /// Chain of post IDs this content has been reposted from
    var repostLineage: [String]
    /// How this content was produced
    var provenanceStatus: ProvenanceStatus
    /// Primary media type of the post
    var mediaType: String // "photo" | "video" | "audio" | "text" | "mixed"
    /// True if the entire post was AI-generated (no original human text/media)
    var aiGenerated: Bool
    /// True if AI tools materially shaped the content (tone, caption, translation, etc.)
    var aiAssisted: Bool
    /// True if attached media was edited/altered from an original
    var editedMedia: Bool
    /// True if the source of the content cannot be verified
    var sourceUnclear: Bool
    /// True if a human moderator has reviewed this post
    var humanReviewed: Bool
    /// True if community fact-checking has reviewed this post
    var communityReviewed: Bool
    /// When this record was first written
    var createdAt: Timestamp?
    /// When this record was last updated
    var updatedAt: Timestamp?
}

// MARK: - SafetyMetadata

/// Safety risk scores and distribution decision for a post.
/// Written exclusively by the backend moderation pipeline.
struct SafetyMetadata: Codable, Equatable {
    /// Risk that this content causes real-world harm (0–1.0)
    var harmRisk: Double
    /// Risk that this content spreads false information (0–1.0)
    var misinformationRisk: Double
    /// Risk this content exploits vulnerable users (0–1.0)
    var exploitationRisk: Double
    /// Risk this content promotes addictive consumption patterns (0–1.0)
    var doomscrollRisk: Double
    /// Risk this content is inappropriate for minors (0–1.0)
    var childSafetyRisk: Double
    /// Risk this content promotes or normalises self-harm (0–1.0)
    var selfHarmRisk: Double
    /// Risk this content is targeted harassment (0–1.0)
    var harassmentRisk: Double
    /// Risk this content promotes or glorifies violence (0–1.0)
    var violenceRisk: Double
    /// Risk this content contains non-consensual sexual material (0–1.0)
    var sexualSafetyRisk: Double
    /// Risk this content is a financial scam (0–1.0)
    var scamRisk: Double
    /// Risk this content manipulates religious belief for harm (0–1.0)
    var religiousAbuseRisk: Double
    /// Risk this content makes unverified medical claims (0–1.0)
    var medicalClaimRisk: Double
    /// Risk this content manipulates opinion through deceptive framing (0–1.0)
    var manipulationRisk: Double = 0.0
    /// Risk this content manipulates political opinion (0–1.0)
    var politicalManipulationRisk: Double
    /// The backend's distribution decision for this content
    var distributionDecision: DistributionDecision
    /// Human-readable safety labels shown to users (e.g. "Unverified claim")
    var labels: [String]
    /// Current moderation status
    var moderationStatus: ContentModerationStatus
    /// When this decision was made
    var reviewedAt: Timestamp?
    /// Who made the final decision
    var reviewerType: ReviewerType?

    /// Aggregate harm score for ranking engine (max of key risk signals)
    var aggregateHarmScore: Double {
        [harmRisk, misinformationRisk, exploitationRisk,
         doomscrollRisk, selfHarmRisk, harassmentRisk,
         violenceRisk, childSafetyRisk, scamRisk].max() ?? 0
    }

    /// True if this content should be hidden from public feeds
    var shouldBeHidden: Bool {
        moderationStatus == .removed || moderationStatus == .humanReview
        || distributionDecision == .remove || distributionDecision == .humanReview
    }

    /// True if this content has any flag that warrants reduced distribution
    var hasReducedReach: Bool {
        distributionDecision.reducesReach
    }
}

// MARK: - ContextMetadata

/// Contextual signals that help users understand what they are seeing.
/// Written by the backend enrichment pipeline.
struct ContextMetadata: Codable, Equatable {
    /// The primary type of content for display and filtering purposes
    var contentType: ContentContextType
    /// True when the post caption accurately describes the attached media
    var captionMatchesMedia: Bool
    /// Risk that a clip/screenshot has been clipped to remove important context (0–1.0)
    var clippedContextRisk: Double
    /// Risk that this content is being shared in a misleading context (0–1.0)
    var outOfContextRisk: Double
    /// Risk that content was created or shared without the subject's consent (0–1.0)
    var consentRisk: Double
    /// Risk that content reveals identifying location information (0–1.0)
    var locationExposureRisk: Double
}

// MARK: - RankingMetadata

/// Feed ranking scores computed by the backend ranking engine.
/// Written exclusively by the backend. Clients must never write these fields.
struct RankingMetadata: Codable, Equatable {
    /// How much this content contributes to healthy community discourse (0–1.0)
    var communityValueScore: Double
    /// Quality of conversation this post generates (0–1.0)
    var conversationHealthScore: Double
    /// Boost applied for original content vs reposts (0–1.0)
    var originalityBoost: Double
    /// Score for educational or creatively valuable content (0–1.0)
    var educationalCreativeValue: Double
    /// How relevant this post is to the viewing user (0–1.0)
    var userRelevanceScore: Double
    /// Safety-based penalty applied to the distribution score (0–1.0)
    var safetyPenalty: Double
    /// Final distribution score after all boosts and penalties applied
    var finalDistributionScore: Double
    /// Whether this post is eligible to appear in recommendation surfaces
    var eligibleForRecommendation: Bool
    /// Whether this post is eligible to appear in trending surfaces
    var eligibleForTrending: Bool
    /// Whether this post is eligible for autoplay in video feeds
    var eligibleForAutoplay: Bool

    /// Compute a final True Source distribution score from component signals.
    /// Formula: communityValue + sourceIntegrity + userRelevance + conversationHealth
    ///          + originality + educationalValue
    ///          - safetyPenalty - manipulationRisk - doomscrollRisk
    ///          - misinformationRisk - exploitationRisk
    static func computeFinalScore(
        communityValue: Double,
        sourceIntegrity: Double,
        userRelevance: Double,
        conversationHealth: Double,
        originality: Double,
        educationalValue: Double,
        safety: SafetyMetadata
    ) -> Double {
        let positive = communityValue + sourceIntegrity + userRelevance
                     + conversationHealth + originality + educationalValue
        let negative = safety.harmRisk + safety.manipulationRisk
                     + safety.doomscrollRisk + safety.misinformationRisk
                     + safety.exploitationRisk
        return max(0, min(1, (positive - negative) / 6.0))
    }
}

// MARK: - TrueSourceBundle

/// Convenience bundle grouping all four True Source sub-objects.
/// Used as a single optional on Post to avoid 4 separate optionals.
struct TrueSourceBundle: Codable, Equatable {
    var source: TrueSourceMetadata
    var safety: SafetyMetadata
    var context: ContextMetadata
    var ranking: RankingMetadata

    /// Whether this post should appear in any feed surface.
    /// Evaluated client-side as a secondary defence; backend is authoritative.
    var isEligibleForFeedDisplay: Bool {
        !safety.shouldBeHidden
        && safety.moderationStatus.isPubliclyVisible
        && safety.distributionDecision != .remove
        && safety.distributionDecision != .humanReview
    }
}

// MARK: - TrueSourceBundle + Defaults

extension TrueSourceBundle {
    /// A safe default bundle used before the backend has populated the real values.
    /// All risks are 0, moderation is pending — post is not shown until backend responds.
    static var pendingModeration: TrueSourceBundle {
        TrueSourceBundle(
            source: TrueSourceMetadata(
                sourceIntegrityScore: 0,
                originalityScore: 0,
                authenticityScore: 0,
                manipulationRisk: 0,
                contextConfidence: 0,
                accountTrustScore: 0,
                repostLineage: [],
                provenanceStatus: .unknown,
                mediaType: "text",
                aiGenerated: false,
                aiAssisted: false,
                editedMedia: false,
                sourceUnclear: true,
                humanReviewed: false,
                communityReviewed: false,
                createdAt: nil,
                updatedAt: nil
            ),
            safety: SafetyMetadata(
                harmRisk: 0,
                misinformationRisk: 0,
                exploitationRisk: 0,
                doomscrollRisk: 0,
                childSafetyRisk: 0,
                selfHarmRisk: 0,
                harassmentRisk: 0,
                violenceRisk: 0,
                sexualSafetyRisk: 0,
                scamRisk: 0,
                religiousAbuseRisk: 0,
                medicalClaimRisk: 0,
                politicalManipulationRisk: 0,
                distributionDecision: .humanReview,
                labels: [],
                moderationStatus: .pending,
                reviewedAt: nil,
                reviewerType: nil
            ),
            context: ContextMetadata(
                contentType: .unknown,
                captionMatchesMedia: true,
                clippedContextRisk: 0,
                outOfContextRisk: 0,
                consentRisk: 0,
                locationExposureRisk: 0
            ),
            ranking: RankingMetadata(
                communityValueScore: 0,
                conversationHealthScore: 0,
                originalityBoost: 0,
                educationalCreativeValue: 0,
                userRelevanceScore: 0,
                safetyPenalty: 0,
                finalDistributionScore: 0,
                eligibleForRecommendation: false,
                eligibleForTrending: false,
                eligibleForAutoplay: false
            )
        )
    }

    /// A safe approved bundle for pre-existing content created before True Source was deployed.
    /// Risk scores default to 0 (assume safe), moderation approved.
    static var legacyApproved: TrueSourceBundle {
        var bundle = pendingModeration
        bundle.safety.moderationStatus = .approved
        bundle.safety.distributionDecision = .allow
        bundle.ranking.eligibleForRecommendation = true
        bundle.ranking.eligibleForTrending = false
        bundle.ranking.eligibleForAutoplay = true
        bundle.source.provenanceStatus = .original
        bundle.source.sourceUnclear = false
        return bundle
    }
}

// MARK: - Post + True Source forwarding

extension Post {
    /// Whether this post may appear in any feed surface.
    /// Removed or flagged posts are never eligible. Posts carrying a True Source
    /// bundle defer to the bundle's eligibility; legacy posts without a bundle
    /// remain eligible for backwards compatibility.
    var isEligibleForFeedDisplay: Bool {
        if removed || flaggedForReview { return false }
        if let bundle = trueSource { return bundle.isEligibleForFeedDisplay }
        return true
    }

    /// Aggregate harm score from the True Source safety bundle (0 when absent).
    var aggregateHarmScore: Double {
        trueSource?.safety.aggregateHarmScore ?? 0
    }

    /// Whether the True Source bundle marks this post for reduced reach.
    var hasReducedReach: Bool {
        trueSource?.safety.hasReducedReach ?? false
    }
}
