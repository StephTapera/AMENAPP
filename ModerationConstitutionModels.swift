
//
//  ModerationConstitutionModels.swift
//  AMENAPP
//
//  Unified data model for the AMEN safety & moderation "constitution".
//  Matches the Firestore schema defined in the architecture blueprint.
//  All writes to these collections are performed by Cloud Functions (admin SDK)
//  or the ModerationIngestService — never by raw client code.
//

import Foundation
import FirebaseFirestore

// MARK: - Content Type

enum ModerationContentType: String, Codable {
    case post
    case comment
    case dm         // direct message
    case profile    // bio / display name / profile photo
    case prayer
    case churchNote = "church_note"
    case testimony
}

// MARK: - Policy Categories (from constitution taxonomy)

/// Category A: Zero-tolerance — always remove + escalate
enum ZeroToleranceViolation: String, Codable, CaseIterable {
    case csam                       // Child sexual abuse material
    case groomingMinor = "grooming_minor"
    case sexualSolicitationMinor = "sexual_solicitation_minor"
    case credibleViolenceThreat = "credible_violence_threat"
    case explicitDoxxing = "explicit_doxxing"
    case selfHarmInstructional = "self_harm_instructional"
    case traffickingorExploitation = "trafficking_exploitation"

    var severity: Int { 5 }
}

/// Category B: High-risk — strong enforcement default
enum HighRiskViolation: String, Codable, CaseIterable {
    case hateSlurs = "hate_slurs"
    case adultSexualContent = "adult_sexual_content"
    case graphicViolence = "graphic_violence"
    case bullyingHarassment = "bullying_harassment"
    case coordinated_harassment = "coordinated_harassment"
    case selfHarmPromotion = "self_harm_promotion"
    case disinformationHarmful = "disinformation_harmful"
    case scamFinancialFraud = "scam_financial_fraud"

    var severity: Int { 4 }
}

/// Category C: Sensitive but allowed with guardrails
enum SensitiveContentCategory: String, Codable, CaseIterable {
    case mentalHealthDisclosure = "mental_health_disclosure"
    case politicalDebate = "political_debate"
    case theologicalControversy = "theological_controversy"
    case mildProfanity = "mild_profanity"
    case heatedLanguage = "heated_language"

    var severity: Int { 2 }
}

// MARK: - Enforcement Actions (Ladder levels 0–5)

enum EnforcementActionType: String, Codable, CaseIterable {
    case allow          // Level 0 — clean
    case nudge          // Level 1 — soft prompt to revise
    case requireEdit = "require_edit"   // Level 2 — block submit until edited
    case holdReview = "hold_review"     // Level 3 — held pending human/AI review
    case shadowRestrict = "shadow_restrict" // Level 4 — visible only to author
    case removePermanent = "remove_permanent"   // Level 5 — removed
    case strikeIssued = "strike_issued"     // strike against account
    case accountCooldown = "account_cooldown"
    case accountFreeze = "account_freeze"   // temp suspension
    case accountBan = "account_ban"         // permanent ban

    /// Human-readable description for user-facing transparency
    var displayName: String {
        switch self {
        case .allow:             return "Allowed"
        case .nudge:             return "Revision Suggested"
        case .requireEdit:       return "Edit Required"
        case .holdReview:        return "Under Review"
        case .shadowRestrict:    return "Visibility Reduced"
        case .removePermanent:   return "Removed"
        case .strikeIssued:      return "Strike Issued"
        case .accountCooldown:   return "Posting Cooldown"
        case .accountFreeze:     return "Account Suspended"
        case .accountBan:        return "Account Banned"
        }
    }
}

/// Actor that made the enforcement decision
enum EnforcementActor: String, Codable {
    case aiAutomatic = "ai_automatic"       // ML pipeline, no human
    case aiWithHuman = "ai_with_human"      // AI suggested, human approved
    case humanModerator = "human_moderator"
    case systemRule = "system_rule"         // deterministic rule (e.g. word filter)
    case userReport = "user_report"         // outcome of a user report
}

// MARK: - Moderation Job (content/{id} → moderation_jobs/{id})

/// A single moderation pass for a piece of content.
/// Created by the moderation-ingest service when content is submitted.
/// Linked to the source content via `contentId` and `contentType`.
struct ModerationJob: Identifiable, Codable {
    @DocumentID var id: String?

    // Source content pointer
    let contentId: String
    let contentType: ModerationContentType
    let authorId: String

    // Pipeline stage scores (0.0–1.0)
    var toxicityScore: Double?
    var spamScore: Double?
    var aiSuspicionScore: Double?
    var groomingScore: Double?
    var doxxingScore: Double?
    var selfHarmScore: Double?
    var cseSafetyScore: Double?         // child safety exploitation score
    var overallRiskScore: Double?

    // Detected signals
    var signals: [String]               // SafetySignal raw values

    // Decision
    var decision: EnforcementActionType
    var decisionActor: EnforcementActor
    var decisionReason: String?
    var decisionConfidence: Double?     // 0.0–1.0

    // Violations detected
    var zeroToleranceViolations: [String]   // ZeroToleranceViolation raw values
    var highRiskViolations: [String]        // HighRiskViolation raw values
    var sensitiveCategories: [String]       // SensitiveContentCategory raw values

    // Processing metadata
    let createdAt: Timestamp
    var completedAt: Timestamp?
    var reviewedBy: String?             // moderator uid if human review
    var reviewedAt: Timestamp?
    var appealId: String?               // linked appeal if one was filed

    enum CodingKeys: String, CodingKey {
        case id
        case contentId = "content_id"
        case contentType = "content_type"
        case authorId = "author_id"
        case toxicityScore = "toxicity_score"
        case spamScore = "spam_score"
        case aiSuspicionScore = "ai_suspicion_score"
        case groomingScore = "grooming_score"
        case doxxingScore = "doxxing_score"
        case selfHarmScore = "self_harm_score"
        case cseSafetyScore = "cse_safety_score"
        case overallRiskScore = "overall_risk_score"
        case signals
        case decision
        case decisionActor = "decision_actor"
        case decisionReason = "decision_reason"
        case decisionConfidence = "decision_confidence"
        case zeroToleranceViolations = "zero_tolerance_violations"
        case highRiskViolations = "high_risk_violations"
        case sensitiveCategories = "sensitive_categories"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case appealId = "appeal_id"
    }
}

// MARK: - Enforcement Action (enforcement_actions/{id})

/// An immutable record of a moderation enforcement action.
/// Written by Cloud Functions only (admin SDK). Append-only.
/// Named `ConstitutionEnforcementAction` to avoid collision with
/// `EnforcementAction` in SafetyPolicyFramework.swift.
struct ConstitutionEnforcementAction: Identifiable, Codable {
    @DocumentID var id: String?

    // Target
    let targetUserId: String
    let contentId: String?              // nil for account-level actions
    let contentType: ModerationContentType?
    let jobId: String?                  // linked ModerationJob

    // Action
    let action: EnforcementActionType
    let actor: EnforcementActor
    let reasonCode: String              // violation enum raw value
    let reasonSummary: String           // human-readable, shown in transparency centre
    let confidence: Double              // 0.0–1.0

    // Duration (for timed restrictions)
    let durationSeconds: Int?           // nil = permanent

    // Appeal window
    let appealDeadline: Timestamp?      // nil = not appealable

    // Metadata
    let createdAt: Timestamp
    let expiresAt: Timestamp?           // auto-lifts when past

    enum CodingKeys: String, CodingKey {
        case id
        case targetUserId = "target_user_id"
        case contentId = "content_id"
        case contentType = "content_type"
        case jobId = "job_id"
        case action
        case actor
        case reasonCode = "reason_code"
        case reasonSummary = "reason_summary"
        case confidence
        case durationSeconds = "duration_seconds"
        case appealDeadline = "appeal_deadline"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

// MARK: - User Trust Profile (user_trust/{uid})

/// Per-user trust state managed by the trust-level-service Cloud Function.
/// Combines `userSafetyRecords` + `ReputationScore` into a single canonical doc.
/// Clients read this to check their own status. Writes are server-only.
struct UserTrustProfile: Identifiable, Codable {
    @DocumentID var id: String?         // = uid

    // Trust tier (maps to TrustLevel in ReputationScoringService)
    let trustLevel: TrustLevelCode

    // Strikes
    let strikes: Int                    // current active strikes (resets on timed expiry)
    let lifetimeStrikes: Int            // never decrements

    // Restrictions
    let accountStatus: AccountStatus
    let cooldownExpiresAt: Timestamp?   // nil = no active cooldown
    let freezeExpiresAt: Timestamp?     // nil = not frozen

    // Capabilities (derived from trust + age tier)
    let canPost: Bool
    let canComment: Bool
    let canDM: Bool
    let canFollowNew: Bool
    let canMentionNonFollowers: Bool
    let canShareLinks: Bool
    let canUploadMedia: Bool

    // Minor safety
    let ageTier: String                 // blocked / tierB / tierC / tierD
    let minorProtectionsActive: Bool

    // Metadata
    let updatedAt: Timestamp
    let lastReviewedAt: Timestamp?

    enum CodingKeys: String, CodingKey {
        case id
        case trustLevel = "trust_level"
        case strikes
        case lifetimeStrikes = "lifetime_strikes"
        case accountStatus = "account_status"
        case cooldownExpiresAt = "cooldown_expires_at"
        case freezeExpiresAt = "freeze_expires_at"
        case canPost = "can_post"
        case canComment = "can_comment"
        case canDM = "can_dm"
        case canFollowNew = "can_follow_new"
        case canMentionNonFollowers = "can_mention_non_followers"
        case canShareLinks = "can_share_links"
        case canUploadMedia = "can_upload_media"
        case ageTier = "age_tier"
        case minorProtectionsActive = "minor_protections_active"
        case updatedAt = "updated_at"
        case lastReviewedAt = "last_reviewed_at"
    }

    enum TrustLevelCode: String, Codable {
        case new        // 0–7 days, limited capabilities
        case basic      // passed email verify
        case trusted    // 30+ days, no strikes
        case verified   // identity or phone verified
        case exemplary  // community leader / no violations

        /// Minimum days on platform
        var minDays: Int {
            switch self {
            case .new: return 0
            case .basic: return 1
            case .trusted: return 30
            case .verified: return 0
            case .exemplary: return 90
            }
        }
    }

    enum AccountStatus: String, Codable {
        case active
        case warned
        case restricted     // limited reach / DMs
        case cooldown       // timed posting suspension
        case frozen         // full suspension
        case banned         // permanent
        case blocked        // under-13 hard block
    }
}

// MARK: - Ingest Event (client → server hand-off)

/// Lightweight event created by ModerationIngestService before content is submitted.
/// The Cloud Function reads this and creates a ModerationJob.
struct ModerationIngestEvent: Codable {
    let contentId: String
    let contentType: ModerationContentType
    let authorId: String
    let contentSnapshot: String         // text/caption — truncated to 4000 chars
    let mediaUrls: [String]
    let clientSignals: ClientIntegritySignals
    let createdAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case contentId = "content_id"
        case contentType = "content_type"
        case authorId = "author_id"
        case contentSnapshot = "content_snapshot"
        case mediaUrls = "media_urls"
        case clientSignals = "client_signals"
        case createdAt = "created_at"
    }
}

/// Client-side integrity signals passed to the server pipeline.
/// Mirrors the existing `ContentModerationService` authenticity signals.
struct ClientIntegritySignals: Codable {
    let typingDurationMs: Int?
    let pastedContent: Bool
    let editCount: Int
    let deviceId: String?
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case typingDurationMs = "typing_duration_ms"
        case pastedContent = "pasted_content"
        case editCount = "edit_count"
        case deviceId = "device_id"
        case appVersion = "app_version"
    }
}

// MARK: - Appeal (moderation_appeals/{id})

/// User-initiated appeal of an enforcement action.
/// Extends the existing moderationAppeals collection in Firestore.
struct ModerationAppeal: Identifiable, Codable {
    @DocumentID var id: String?

    let userId: String
    let enforcementActionId: String  // references ConstitutionEnforcementAction.id
    let contentId: String?
    let contentType: ModerationContentType?

    var status: AppealStatus
    let userStatement: String           // ≤ 1000 chars
    let submittedAt: Timestamp

    var reviewedBy: String?
    var reviewedAt: Timestamp?
    var outcome: AppealOutcome?
    var moderatorNote: String?          // optional feedback shown to user

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case enforcementActionId = "enforcement_action_id"
        case contentId = "content_id"
        case contentType = "content_type"
        case status
        case userStatement = "user_statement"
        case submittedAt = "submitted_at"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case outcome
        case moderatorNote = "moderator_note"
    }

    enum AppealStatus: String, Codable {
        case pending
        case underReview = "under_review"
        case resolved
    }

    enum AppealOutcome: String, Codable {
        case upheld         // original action stands
        case overturned     // action reversed, content restored
        case modified       // action reduced (e.g. ban → cooldown)
    }
}

// MARK: - Doxxing Detection Result

/// Produced by the pre-submit doxxing scanner in ModerationIngestService.
struct DoxxingCheckResult {
    /// Whether doxxing signals were found
    let detected: Bool
    /// The specific PII categories found
    let detectedCategories: [PIICategory]
    /// Score 0–1 (confidence)
    let confidence: Double
    /// Redacted version of the input text (PII replaced with placeholder)
    let redactedText: String?

    enum PIICategory: String, CaseIterable {
        case homeAddress = "home_address"
        case personalPhoneNumber = "personal_phone_number"
        case personalEmail = "personal_email"
        case ssn = "ssn"
        case bankAccount = "bank_account"
        case governmentId = "government_id"
        case licencePlate = "licence_plate"
        case workplaceDetails = "workplace_details"
    }
}

// MARK: - Grooming Detection Result

/// Produced by the on-device grooming signal scanner (mirrors MessageSafetyGateway signals).
struct GroomingCheckResult {
    let detected: Bool
    let signals: [GroomingSignal]
    let riskScore: Double   // 0.0–1.0

    enum GroomingSignal: String, CaseIterable {
        case ageMentionWithSexual = "age_mention_with_sexual"
        case isolationLanguage = "isolation_language"
        case secretKeeping = "secret_keeping"
        case giftOffering = "gift_offering"
        case offPlatformMigration = "off_platform_migration"
        case locationRequest = "location_request"
        case urgencyPressure = "urgency_pressure"
        case loveBombing = "love_bombing"
    }
}
