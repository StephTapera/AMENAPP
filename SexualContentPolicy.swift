//
//  SexualContentPolicy.swift
//  AMENAPP
//
//  Hard policy document + enforcement ladder for sexual content, solicitation,
//  minors protection, and grooming prevention.
//
//  Design principles:
//   - Clear policy: every action maps to a named reason code
//   - Progressive enforcement: first violation ≠ permanent ban
//   - Transparent to users: every enforcement has a user-visible reason + appeal path
//   - Minors-first defaults: anything ambiguous is treated as if a minor could see it
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Policy Document

/// The canonical policy statement shown to users in Settings → Community Guidelines.
/// Used by `AppealFlowView` and the moderation console.
enum SexualContentPolicyDocument {
    static let title = "Sexual Content Policy"

    static let summary = """
    AMEN is a faith community for people of all ages. Sexual, explicit, and sexually \
    soliciting content is not allowed anywhere on the platform — in posts, comments, \
    profiles, or direct messages.
    """

    static let notAllowed: [String] = [
        "Pornographic or sexually explicit content",
        "Sexual solicitation (advertising or requesting sexual services or content)",
        "Fetish content",
        "\"Meet / DM for…\" sexual offers",
        "Unsolicited sexual messages or images",
        "Content that sexualises minors in any way",
        "Grooming: attempts to manipulate or exploit a young person",
        "Sharing another person's sexual images without consent"
    ]

    static let grayAreas: [String] = [
        "Anatomical/educational references (allowed if educational, not explicit)",
        "Relationship advice (allowed if non-explicit)",
        "Dating/romantic content (allowed if tasteful and non-explicit)"
    ]

    static let enforcement = """
    Violations are reviewed and actioned based on severity. \
    Repeat violations result in escalating restrictions up to and including permanent removal. \
    You may appeal any enforcement action within 30 days.
    """
}

// MARK: - Enforcement Reason Codes

/// Standardised reason codes for every enforcement action.
/// Maps 1:1 to policy violations. Used in audit logs, user-facing notices, and appeals.
enum SexualPolicyViolationCode: String, CaseIterable, Codable {
    // ── Hard violations (single strike = immediate action) ────────────────────
    case csam                    = "CSAM"               // Child sexual abuse material
    case groomingMinor           = "GROOMING_MINOR"     // Grooming a person under 18
    case sexualExploitation      = "SEXUAL_EXPLOIT"     // Coercion, blackmail, image-based abuse
    case solicitation            = "SEXUAL_SOLICIT"     // Advertising/requesting sexual services
    case explicitContent         = "EXPLICIT_CONTENT"   // Pornographic media (images/video)
    case explicitText            = "EXPLICIT_TEXT"      // Graphic sexual text content
    case nonconsensualImage      = "NONCONSENT_IMAGE"   // Sharing intimate images without consent

    // ── Moderate violations (warning → restriction ladder) ───────────────────
    case sexualHarassment        = "SEXUAL_HARASS"      // Unwanted sexual messages/comments
    case offPlatformMigration    = "OFF_PLATFORM"       // Soliciting move to unmonitored apps
    case adultPlatformPromotion  = "ADULT_PROMO"        // Advertising OnlyFans/adult sites
    case contactExchangeSexual   = "CONTACT_SEXUAL"     // Sharing contact info in sexual context

    // ── Minor / borderline ────────────────────────────────────────────────────
    case suggestiveContent       = "SUGGESTIVE"         // Suggestive but not explicit
    case inappropriateForContext = "CONTEXT_VIOLATION"  // Otherwise allowable content on wrong surface

    // MARK: Severity

    var severity: SexualViolationSeverity {
        switch self {
        case .csam, .groomingMinor, .sexualExploitation, .nonconsensualImage:
            return .critical
        case .solicitation, .explicitContent, .explicitText:
            return .severe
        case .sexualHarassment, .offPlatformMigration, .adultPlatformPromotion, .contactExchangeSexual:
            return .moderate
        case .suggestiveContent, .inappropriateForContext:
            return .minor
        }
    }

    /// Human-readable explanation shown to the user in an enforcement notice.
    var userFacingReason: String {
        switch self {
        case .csam:
            return "This content violates our most serious policy — the protection of children — and has been removed and reported."
        case .groomingMinor:
            return "This content appears to target or exploit a young person and is not allowed."
        case .sexualExploitation:
            return "This content involves sexual coercion, blackmail, or non-consensual sharing and has been removed."
        case .solicitation:
            return "Sexual solicitation — advertising or requesting sexual services — is not allowed on AMEN."
        case .explicitContent:
            return "Pornographic or explicit sexual media is not allowed on AMEN."
        case .explicitText:
            return "Graphic sexual text content is not allowed on AMEN."
        case .nonconsensualImage:
            return "Sharing someone's intimate images without their consent is not allowed."
        case .sexualHarassment:
            return "Sending unwanted sexual messages or comments is not allowed."
        case .offPlatformMigration:
            return "Asking people to move to other apps for sexual purposes removes safety protections and is not allowed."
        case .adultPlatformPromotion:
            return "Promoting adult content platforms (e.g., OnlyFans) is not allowed on AMEN."
        case .contactExchangeSexual:
            return "Sharing personal contact information in a sexual context is not allowed."
        case .suggestiveContent:
            return "This content is too suggestive for our community. Please keep all content appropriate for a faith community of all ages."
        case .inappropriateForContext:
            return "This content isn't appropriate for this part of the app."
        }
    }

    /// Whether this violation mandates an emergency NCMEC / law enforcement report.
    var requiresMandatoryReport: Bool {
        return self == .csam
    }
}

/// Sexual-policy-specific severity — distinct from SafetyPolicyFramework.ViolationSeverity.
enum SexualViolationSeverity: Int, Comparable {
    case minor    = 1
    case moderate = 2
    case severe   = 3
    case critical = 4

    static func < (lhs: SexualViolationSeverity, rhs: SexualViolationSeverity) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Enforcement Ladder

/// Progressive sexual-policy enforcement actions.
/// Distinct from SafetyPolicyFramework.EnforcementAction (which handles general policy).
enum SexualEnforcementAction: String, Codable {
    case contentRemoved      = "content_removed"        // Content removed, no account action
    case warning             = "warning"                // First-time notice, no restriction
    case cooldown24h         = "cooldown_24h"           // 24-hour posting/messaging restriction
    case cooldown72h         = "cooldown_72h"           // 72-hour restriction
    case cooldown7d          = "cooldown_7d"            // 7-day restriction
    case postingRestricted   = "posting_restricted"     // Cannot post until appeal resolved
    case messagingRestricted = "messaging_restricted"   // Cannot DM until appeal resolved
    case accountSuspended    = "account_suspended"      // Full suspension (all features locked)
    case accountTerminated   = "account_terminated"     // Permanent ban
    case emergencyFreezeAndReport = "emergency_freeze"  // Freeze + mandatory NCMEC report
}

/// Determines the enforcement action given violation code + prior strike count.
enum SexualEnforcementLadder {
    static func action(
        for violation: SexualPolicyViolationCode,
        priorStrikes: Int,
        priorSameViolation: Int
    ) -> SexualEnforcementAction {
        switch violation.severity {

        case .critical:
            return .emergencyFreezeAndReport

        case .severe:
            switch priorStrikes {
            case 0:
                return priorSameViolation == 0 ? .warning : .cooldown24h
            case 1:
                return .cooldown72h
            case 2:
                return .cooldown7d
            case 3:
                return .postingRestricted
            default:
                return priorStrikes >= 5 ? .accountTerminated : .accountSuspended
            }

        case .moderate:
            switch priorStrikes {
            case 0:
                return .contentRemoved
            case 1:
                return .warning
            case 2:
                return .cooldown24h
            case 3:
                return .cooldown72h
            default:
                return priorStrikes >= 5 ? .accountSuspended : .cooldown7d
            }

        case .minor:
            switch priorStrikes {
            case 0, 1:
                return .contentRemoved
            case 2:
                return .warning
            default:
                return .cooldown24h
            }
        }
    }

    static func userFacingDescription(for action: SexualEnforcementAction, violation: SexualPolicyViolationCode) -> String {
        switch action {
        case .contentRemoved:
            return "Your content was removed: \(violation.userFacingReason)"
        case .warning:
            return "Warning: \(violation.userFacingReason) This is your notice. Further violations will result in restrictions."
        case .cooldown24h:
            return "Your account has a 24-hour restriction. \(violation.userFacingReason) You can appeal this decision."
        case .cooldown72h:
            return "Your account has a 72-hour restriction due to repeated violations. You can appeal."
        case .cooldown7d:
            return "Your account has a 7-day restriction due to repeated violations. You can appeal."
        case .postingRestricted:
            return "Your posting ability has been restricted pending review. You can appeal."
        case .messagingRestricted:
            return "Your messaging ability has been restricted pending review. You can appeal."
        case .accountSuspended:
            return "Your account has been suspended. You can appeal within 30 days."
        case .accountTerminated:
            return "Your account has been terminated for repeated serious violations."
        case .emergencyFreezeAndReport:
            return "Your account has been suspended. This violation has been reported to the appropriate authorities."
        }
    }

    static func isAppealable(_ action: SexualEnforcementAction) -> Bool {
        switch action {
        case .emergencyFreezeAndReport, .accountTerminated:
            return false
        default:
            return true
        }
    }

    static func isAccountRestriction(_ action: SexualEnforcementAction) -> Bool {
        switch action {
        case .contentRemoved, .warning:
            return false
        default:
            return true
        }
    }
}

// MARK: - Enforcement Record (Firestore-persisted)

/// Written to `enforcement_actions/{actionId}` by Cloud Functions.
/// Clients can read their own records for the appeal flow.
struct SexualPolicyEnforcementRecord: Codable {
    let id: String
    let userId: String
    let violationCode: String            // SexualPolicyViolationCode.rawValue
    let action: String                   // SexualEnforcementAction.rawValue
    let contentId: String?              // Removed post/message/comment ID
    let contentType: String?            // "post", "comment", "dm", "profile", "media"
    let textHash: String?               // SHA-256 of flagged content (not raw text)
    let moderatorId: String?            // nil = automated; string = moderator UID
    let automated: Bool
    let timestamp: Date
    let expiresAt: Date?               // nil = permanent; date = restriction end
    let appealDeadline: Date?          // 30 days after enforcement
    let appealStatus: AppealStatus
    let appealId: String?

    enum AppealStatus: String, Codable {
        case notApplicable = "not_applicable"
        case pending       = "pending"
        case submitted     = "submitted"
        case underReview   = "under_review"
        case upheld        = "upheld"           // Enforcement stands
        case overturned    = "overturned"       // Enforcement reversed
    }
}

// MARK: - Appeal Flow Service

/// Manages the appeal flow for enforcement actions.
/// Users can submit an appeal within 30 days of any appealable enforcement.
@MainActor
final class AppealFlowService {
    static let shared = AppealFlowService()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Load Active Enforcement

    /// Returns all active (unexpired, not overturned) enforcement actions for the current user.
    func loadActiveEnforcements() async -> [SexualPolicyEnforcementRecord] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        do {
            let snap = try await db.collection("enforcement_actions")
                .whereField("userId", isEqualTo: uid)
                .whereField("appealStatus", in: ["not_applicable", "pending", "submitted", "under_review", "upheld"])
                .order(by: "timestamp", descending: true)
                .limit(to: 20)
                .getDocuments()
            return snap.documents.compactMap {
                try? Firestore.Decoder().decode(SexualPolicyEnforcementRecord.self, from: $0.data())
            }
        } catch {
            return []
        }
    }

    // MARK: - Submit Appeal

    struct AppealSubmission {
        let enforcementId: String
        let userStatement: String          // ≤ 1000 chars — user's side of the story
        let additionalContext: String?
    }

    func submitAppeal(_ submission: AppealSubmission) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppealError.notAuthenticated
        }

        // Verify the record exists and belongs to the current user
        let ref = db.collection("enforcement_actions").document(submission.enforcementId)
        let doc = try await ref.getDocument()
        guard doc.exists,
              let userId = doc.data()?["userId"] as? String,
              userId == uid else {
            throw AppealError.recordNotFound
        }

        // Check appeal deadline
        if let deadline = (doc.data()?["appealDeadline"] as? Timestamp)?.dateValue(),
           Date() > deadline {
            throw AppealError.deadlinePassed
        }

        // Check current appeal status
        if let status = doc.data()?["appealStatus"] as? String,
           status == SexualPolicyEnforcementRecord.AppealStatus.submitted.rawValue ||
           status == SexualPolicyEnforcementRecord.AppealStatus.underReview.rawValue {
            throw AppealError.alreadySubmitted
        }

        // Write appeal document
        let appealId = UUID().uuidString
        let appealData: [String: Any] = [
            "id": appealId,
            "enforcementId": submission.enforcementId,
            "userId": uid,
            "userStatement": String(submission.userStatement.prefix(1000)),
            "additionalContext": submission.additionalContext ?? NSNull(),
            "status": "submitted",
            "submittedAt": FieldValue.serverTimestamp(),
            "reviewedAt": NSNull(),
            "reviewerId": NSNull(),
            "outcome": NSNull()
        ]

        let batch = db.batch()
        // Create appeal record
        batch.setData(appealData, forDocument: db.collection("content_appeals").document(appealId))
        // Update enforcement record status
        batch.updateData([
            "appealStatus": SexualPolicyEnforcementRecord.AppealStatus.submitted.rawValue,
            "appealId": appealId
        ], forDocument: ref)
        try await batch.commit()
    }

    enum AppealError: LocalizedError {
        case notAuthenticated
        case recordNotFound
        case deadlinePassed
        case alreadySubmitted

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Please sign in to submit an appeal."
            case .recordNotFound:   return "Enforcement record not found."
            case .deadlinePassed:   return "The 30-day appeal window for this action has closed."
            case .alreadySubmitted: return "An appeal is already under review for this action."
            }
        }
    }

    // MARK: - User-facing Enforcement Notice

    /// Returns whether the current user has any active account restrictions.
    func hasActiveRestriction() async -> Bool {
        let enforcements = await loadActiveEnforcements()
        let now = Date()
        return enforcements.contains { record in
            guard let action = SexualEnforcementAction(rawValue: record.action) else { return false }
            guard SexualEnforcementLadder.isAccountRestriction(action) else { return false }
            // Check if restriction is still active
            if let expires = record.expiresAt {
                return expires > now
            }
            return true  // No expiry = permanent
        }
    }
}

// MARK: - Proactive UX Friction: Sexual Risk Score

/// Lightweight scorer that computes a sexual-risk signal for pre-post friction.
/// Does NOT block content — only raises the friction threshold in the UI.
/// Score 0.0 (clean) → 1.0 (clear violation).
enum SexualRiskScorer {

    /// Returns a 0–1 score for the given text.
    /// Intended for real-time UI feedback (e.g., typing hint) — must be synchronous and fast.
    static func score(_ text: String) -> Double {
        let plain = LocalContentGuard.normalise(text)
        var score: Double = 0.0

        // Hard signals (immediate high score)
        if LocalContentGuard.containsSexualSolicitation(plain) { return 1.0 }
        if LocalContentGuard.containsGroomingSignal(plain, isDM: false) { return 1.0 }

        // Keyword density
        let sexualKeywords = [
            "nude", "naked", "explicit", "xxx", "porn", "horny", "sexy", "nsfw",
            "onlyfans", "sex", "sexual", "erotic", "fetish", "hookup", "hook up",
            "fwb", "friends with benefits", "one night", "casual sex",
            "send pics", "send photos", "show me", "naughty", "dirty talk"
        ]
        let hits = sexualKeywords.filter { plain.contains($0) }.count
        score += min(0.8, Double(hits) * 0.25)

        // Off-platform migration (moderate signal)
        if LocalContentGuard.containsOffPlatformMigration(plain) { score += 0.3 }

        return min(1.0, score)
    }

    /// Returns a user-facing prompt string if the risk is above the soft-prompt threshold.
    /// Returns nil if content is clean.
    static func frictionMessage(for score: Double, isRepeatOffender: Bool) -> String? {
        if score >= 0.9 {
            return "This looks sexual or explicit. AMEN doesn't allow that. Please revise before posting."
        }
        if score >= 0.6 {
            return isRepeatOffender
                ? "Your content contains language that may violate our sexual content policy. Please revise it — repeated violations result in restrictions."
                : "This content may not be appropriate for our faith community. Please keep AMEN wholesome."
        }
        if score >= 0.35 {
            return "Does this keep AMEN's values? Consider revising to keep it faith-appropriate."
        }
        return nil
    }
}
