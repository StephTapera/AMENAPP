// AmenContentSafetyModels.swift
// AMEN App — CommunityOS / ContentSafety
//
// Phase 4 Agent TS-b — AI Content Safety
//
// Risk classification models, content check request/response types,
// and the PrePostDecision contract used by AmenContentSafetyService.
//
// These types are intentionally separate from the Camera OS CameraContextRiskLevel
// and ModerationTier in TransformEngine — those govern object-transform pipelines
// and camera pre-publish flows. The types here govern text + media content submitted
// to the moderatePost / checkContentSafety cloud pipeline.
//
// INTEGRATION NOTE:
//   The moderatePost Cloud Function uses NVIDIA_API_KEY and the
//   nvidia/llama-3.1-nemoguard-8b-content-safety model. It is already deployed.
//   iOS never calls NIM directly — it calls the Firebase callable "checkContentSafety"
//   (gen1, functions/moderationGateway.js) for pre-post inline checks.
//
// Fail-closed invariant (mirrors CF contract C4-cf-signatures.md):
//   CF unreachable → tier .high, requiresModerationReview true.
//   CSAM → immediate escalation, no silent swallow.
//   Crisis language → AmenCrisisInterventionView always shown.

import Foundation

// MARK: - RiskTier

/// Four-level risk ladder used to drive post/review/block decisions.
/// Mirrors the CF-side `status` field values for consistency.
///
/// - low:    Post is safe; no intervention needed.
/// - medium: Concern worth surfacing; user may proceed after seeing suggestion.
/// - high:   Routed to moderation queue; user can edit; no hard block.
/// - severe: Hard block. User cannot post; admin review required.
enum RiskTier: Int, Codable, CaseIterable, Comparable, Sendable {
    case low    = 0
    case medium = 1
    case high   = 2
    case severe = 3

    static func < (lhs: RiskTier, rhs: RiskTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Whether the tier permits the post to be submitted (even if held in queue).
    /// Only `.severe` hard-blocks. All others can proceed (with moderation routing if needed).
    var allowsPost: Bool {
        self != .severe
    }

    /// Whether the result must be routed to the server-side moderation queue for human review.
    var requiresReview: Bool {
        self == .high || self == .severe
    }

    /// Whether a user-facing suggestion should be shown before the post button is tapped.
    var showsSuggestion: Bool {
        self == .medium || self == .high
    }

    /// Human-readable label for UI and accessibility.
    var displayLabel: String {
        switch self {
        case .low:    return "Looks good"
        case .medium: return "Heads up"
        case .high:   return "Review needed"
        case .severe: return "Post blocked"
        }
    }
}

// MARK: - ContentRiskCategory

/// Violation categories that the NeMo Guard / NIM pipeline can return.
/// The iOS layer maps CF response strings into these typed cases for routing.
/// CSAM is always `.escalateImmediately` regardless of any other factor.
enum ContentRiskCategory: String, Codable, CaseIterable, Sendable {
    case safe
    case spam
    case harassment
    case hateSpeech
    case misinformation
    case scam
    case doxxing
    case violentExtremism
    case sexualContent
    case csam                   // escalate immediately — no user-facing message
    case selfHarmRisk
    case crisisLanguage
}

// MARK: - ContentSafetyResult

/// The full resolved result of a content safety check.
/// Produced by AmenContentSafetyService after combining the quick local scan
/// and/or the CF response. All fields are required at the decision layer —
/// there is no partial result; a CF failure must produce a well-formed
/// fail-closed result (see AmenContentSafetyService.failClosedResult).
struct ContentSafetyResult: Codable, Sendable {
    /// Overall risk tier driving the PrePostDecision.
    var tier: RiskTier

    /// All violation categories detected. May be empty for `.low` results.
    var categories: [ContentRiskCategory]

    /// Classifier confidence in the tier assignment (0.0–1.0).
    /// 0.0 is used for fail-closed fallback results where confidence is unknown.
    var confidence: Double

    /// Human-readable suggestion shown when `tier >= .medium`.
    /// nil for `.low` results.
    var suggestion: String?

    /// True only when `tier == .severe`. Drives the hard-block UI path.
    var hardBlocked: Bool

    /// True when result must be forwarded to the server-side moderation queue.
    var requiresModerationReview: Bool

    /// True for CSAM or active self-harm crisis — triggers immediate escalation path.
    var escalateImmediately: Bool

    /// Timestamp of the check. Used for audit log correlation.
    var checkedAt: Date
}

// MARK: - ContentCheckRequest

/// Parameters sent to AmenContentSafetyService for a full content check.
/// The service constructs the CF request payload from this struct.
struct ContentCheckRequest: Sendable {
    /// The text body of the post, comment, or message being checked.
    var text: String

    /// Any media asset URLs attached to the content.
    /// Image moderation is handled separately by the Storage trigger pipeline;
    /// these URLs are logged in the check for correlation only.
    var mediaUrls: [String]

    /// Firebase Auth UID of the author.
    var authorId: String

    /// Content surface type: "post" | "comment" | "message".
    var objectType: String

    /// Optional Firestore reference to the church or space context.
    /// Passed to the CF for context-aware strictness rules.
    var contextRef: String?

    /// True if the author is under 18. Triggers minor-content rules on the CF side.
    var isMinorAuthor: Bool
}

// MARK: - PrePostDecision

/// The decision produced by `AmenContentSafetyService.checkBeforePost`.
/// Combines the quick local scan and CF full-check into a single action signal
/// that drives the post-compose UI.
struct PrePostDecision: Sendable {

    // MARK: - Action

    /// The action the compose UI should take after receiving a decision.
    enum Action: Sendable {
        /// Content is safe — proceed immediately without any UI intervention.
        case allow

        /// Show `AmenPrePostReviewSheet` with the given suggestion text.
        /// User may edit or proceed.
        case showSuggestion(String)

        /// Show `AmenPrePostReviewSheet` in blocked mode.
        /// User cannot proceed; message explains why.
        case blockWithMessage(String)

        /// Content contains crisis/self-harm language.
        /// Show `AmenCrisisInterventionView` — never suppress.
        case crisisIntervene
    }

    let action: Action

    /// The underlying safety result for audit logging and detailed UI display.
    let safetyResult: ContentSafetyResult
}
