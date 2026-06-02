//
//  AmenSafetyModels.swift
//  AMENAPP
//
//  Unified model layer for the Amen Trust + Safety OS.
//  All safety decisions, provenance, bot scores, identity trust,
//  ranking, wellness, reporting, enforcement, and AI transparency
//  objects live here.
//
//  Firestore write rules: backend-only. Clients read via labeled UI.
//

import Foundation
import SwiftUI

// MARK: - Policy Version

let AmenTrustSafetyOSVersion = "2026-05-25-v1"

// MARK: - Safety Decision

enum SafetyDecisionOutcome: String, Codable, Equatable {
    case allow               = "allow"
    case allowWithLabel      = "allow_with_label"
    case limitDistribution   = "limit_distribution"
    case quarantine          = "quarantine"
    case block               = "block"
    case escalate            = "escalate"

    var isPublishable: Bool {
        self == .allow || self == .allowWithLabel
    }

    var requiresHumanReview: Bool {
        self == .quarantine || self == .escalate
    }
}

enum RiskCategory: String, Codable, Equatable, CaseIterable {
    case sexual             = "sexual"
    case nudity             = "nudity"
    case csamIndicator      = "csam_indicator"
    case grooming           = "grooming"
    case sextortion         = "sextortion"
    case trafficking        = "trafficking"
    case violence           = "violence"
    case gore               = "gore"
    case extremism          = "extremism"
    case hate               = "hate"
    case harassment         = "harassment"
    case scam               = "scam"
    case impersonation      = "impersonation"
    case misinformation     = "misinformation"
    case syntheticMedia     = "synthetic_media"
    case botBehavior        = "bot_behavior"
    case spam               = "spam"
    case manipulation       = "manipulation"
    case selfHarm           = "self_harm"
    case privacyViolation   = "privacy_violation"
    case unknown            = "unknown"
}

enum ContentSurface: String, Codable {
    case post                = "post"
    case comment             = "comment"
    case reply               = "reply"
    case dm                  = "dm"
    case groupMessage        = "group_message"
    case profileBio          = "profile_bio"
    case username            = "username"
    case banner              = "banner"
    case churchPage          = "church_page"
    case creatorPage         = "creator_page"
    case event               = "event"
    case review              = "review"
    case testimonial         = "testimonial"
    case livestreamMetadata  = "livestream_metadata"
    case thumbnail           = "thumbnail"
    case caption             = "caption"
    case altText             = "alt_text"
    case aiSummary           = "ai_summary"
}

struct TSPreflightDecision: Codable, Equatable {
    let decision: SafetyDecisionOutcome
    let riskScore: Double
    let categories: [String: Double]
    let userFacingReason: String?
    let provenanceStatus: MediaAuthenticityStatus
    let aiGeneratedStatus: AIGeneratedStatus
    let enforcementAction: String
    let appealAllowed: Bool
    let policyVersion: String
    let contentId: String?
    let contentType: ContentSurface?

    // Client-facing derived properties
    var canPublish: Bool { decision.isPublishable }
    var showLabel: Bool { decision == .allowWithLabel }
    var isBlocked: Bool { decision == .block || decision == .escalate }
    var isLimited: Bool { decision == .limitDistribution }
    var isPendingReview: Bool { decision == .quarantine || decision == .escalate }

    // Default "checking" decision for UI loading state
    static let checking = TSPreflightDecision(
        decision: .quarantine,
        riskScore: 0,
        categories: [:],
        userFacingReason: "This post is being checked before it appears.",
        provenanceStatus: .unknown,
        aiGeneratedStatus: .unknown,
        enforcementAction: "none",
        appealAllowed: false,
        policyVersion: AmenTrustSafetyOSVersion,
        contentId: nil,
        contentType: nil
    )
}

// MARK: - Provenance

enum MediaAuthenticityStatus: String, Codable, Equatable {
    case original       = "original"
    case edited         = "edited"
    case aiAssisted     = "ai_assisted"
    case aiGenerated    = "ai_generated"
    case reposted       = "reposted"
    case sourceUncertain = "source_uncertain"
    case verifiedSource = "verified_source"
    case contextMissing = "context_missing"
    case unknown        = "unknown"

    var displayLabel: String {
        switch self {
        case .original:       return "Original media"
        case .edited:         return "Edited media"
        case .aiAssisted:     return "AI-assisted"
        case .aiGenerated:    return "AI-generated"
        case .reposted:       return "Reposted"
        case .sourceUncertain:return "Source uncertain"
        case .verifiedSource: return "Verified source"
        case .contextMissing: return "Context missing"
        case .unknown:        return "Source uncertain"
        }
    }

    var requiresLabel: Bool {
        switch self {
        case .aiGenerated, .aiAssisted, .sourceUncertain, .unknown, .contextMissing: return true
        default: return false
        }
    }

    var limitSharing: Bool {
        self == .sourceUncertain || self == .unknown || self == .contextMissing
    }
}

enum AIGeneratedStatus: String, Codable, Equatable {
    case notAI      = "not_ai"
    case aiAssisted = "ai_assisted"
    case aiGenerated = "ai_generated"
    case unknown    = "unknown"
}

struct MediaProvenanceRecord: Codable, Identifiable {
    var id: String { mediaId }
    let mediaId: String
    let uploaderUid: String
    let originalHash: String
    let perceptualHash: String
    let aiDetectionScore: Double
    let editingDetected: Bool
    let creatorDeclaration: CreatorDeclaration
    let provenanceStatus: MediaAuthenticityStatus
    let trendEligible: Bool
    let boostEligible: Bool
    let labelRequired: Bool
    let policyVersion: String

    var aiLabelType: AILabelType {
        switch provenanceStatus {
        case .aiGenerated:    return .aiGenerated
        case .aiAssisted:     return .aiAssisted
        case .sourceUncertain,
             .unknown:        return .mayBeAI
        default:              return .none
        }
    }
}

enum CreatorDeclaration: String, Codable, CaseIterable {
    case original    = "original"
    case edited      = "edited"
    case aiAssisted  = "ai_assisted"
    case aiGenerated = "ai_generated"
    case reposted    = "reposted"
    case unknown     = "unknown"

    var displayLabel: String {
        switch self {
        case .original:    return "I created this"
        case .edited:      return "I edited this"
        case .aiAssisted:  return "AI-assisted"
        case .aiGenerated: return "AI-generated"
        case .reposted:    return "Reposted from elsewhere"
        case .unknown:     return "Not sure"
        }
    }
}

enum AILabelType: String, Codable {
    case none           = "none"
    case aiGenerated    = "ai_generated"
    case aiAssisted     = "ai_assisted"
    case mayBeAI        = "may_be_ai"
    case sourceUncertain = "source_uncertain"
}

// MARK: - Bot Defense

enum BotScore: String, Codable, Equatable {
    case humanLikely  = "human_likely"
    case suspicious   = "suspicious"
    case coordinated  = "coordinated"
    case automated    = "automated"
    case malicious    = "malicious"

    var requiresChallenge: Bool {
        self == .automated || self == .malicious
    }

    var suppressFromRanking: Bool {
        self != .humanLikely
    }
}

struct BotDefenseResult: Codable {
    let uid: String
    let botScore: BotScore
    let confidence: Double
    let requiresChallenge: Bool
    let throttleActions: Bool
    let suppressFromRanking: Bool
    let policyVersion: String
}

// MARK: - Identity Trust

enum IdentityTrustLevel: String, Codable, CaseIterable, Comparable {
    case basic                  = "basic"
    case emailVerified          = "email_verified"
    case phoneVerified          = "phone_verified"
    case trustedDevice          = "trusted_device"
    case humanChallengePassed   = "human_challenge_passed"
    case communityVerified      = "community_verified"
    case churchVerified         = "church_verified"
    case creatorVerified        = "creator_verified"
    case professionalVerified   = "professional_verified"

    private static let order: [IdentityTrustLevel] = [
        .basic, .emailVerified, .phoneVerified, .trustedDevice,
        .humanChallengePassed, .communityVerified, .churchVerified,
        .creatorVerified, .professionalVerified
    ]
    static func < (lhs: IdentityTrustLevel, rhs: IdentityTrustLevel) -> Bool {
        let li = order.firstIndex(of: lhs) ?? 0
        let ri = order.firstIndex(of: rhs) ?? 0
        return li < ri
    }

    var badgeLabel: String {
        switch self {
        case .basic:                return ""
        case .emailVerified:        return "Verified"
        case .phoneVerified:        return "Verified"
        case .trustedDevice:        return "Verified"
        case .humanChallengePassed: return "Human Verified"
        case .communityVerified:    return "Community Verified"
        case .churchVerified:       return "Church Verified"
        case .creatorVerified:      return "Creator Verified"
        case .professionalVerified: return "Professionally Verified"
        }
    }

    var showBadge: Bool { self >= .emailVerified }
}

struct IdentityTrustProfile: Codable {
    let uid: String
    let trustLevel: IdentityTrustLevel
    let verifiedAt: Date?
    let verificationSource: String?
    let claimedRoles: [String]
    let unverifiedClaims: [String]
    let isSuspectedImpersonation: Bool
    let trustScore: Int     // 0–100
    let policyVersion: String
}

// MARK: - Ranking

struct RankingDecision: Codable {
    let contentId: String
    let finalScore: Double
    let trendEligible: Bool
    let boostEligible: Bool
    let suppressedReason: String?
    let policyVersion: String
}

// MARK: - Wellness

enum WellnessTrigger: String, Codable {
    case doomscrolling            = "doomscrolling"
    case repeatedAngerContent     = "repeated_anger_content"
    case lateNightUsage           = "late_night_usage"
    case repeatedConflictReplies  = "repeated_conflict_replies"
    case aboutToPostHarmful       = "about_to_post_harmful"
    case receivingHarassment      = "receiving_harassment"
    case repeatedTraumaticContent = "repeated_traumatic_content"
}

typealias TSWellnessIntervention = WellnessIntervention

enum WellnessIntervention: String, Codable, CaseIterable {
    case selahPause              = "selah_pause"
    case reflectionPrompt        = "reflection_prompt"
    case postConfirmation        = "post_confirmation"
    case conflictWarning         = "conflict_warning"
    case replyReflection         = "reply_reflection"
    case muteSuggestion          = "mute_suggestion"
    case disableNotifications    = "disable_notifications"
    case switchToReflectionMode  = "switch_to_reflection_mode"

    var title: String {
        switch self {
        case .selahPause:             return "Take a Selah"
        case .reflectionPrompt:       return "A moment to reflect"
        case .postConfirmation:       return "Before you post"
        case .conflictWarning:        return "This may escalate"
        case .replyReflection:        return "Take a moment before replying"
        case .muteSuggestion:         return "Mute this thread?"
        case .disableNotifications:   return "Quiet this conversation"
        case .switchToReflectionMode: return "Switch to prayer & reflection?"
        }
    }

    var message: String {
        switch self {
        case .selahPause:
            return "You've been scrolling for a while. Take a breath."
        case .reflectionPrompt:
            return "You seem to be engaging with difficult content. How are you doing?"
        case .postConfirmation:
            return "Do you want to post this? It looks like it might be difficult content."
        case .conflictWarning:
            return "This reply may escalate the conversation."
        case .replyReflection:
            return "Take a moment before replying."
        case .muteSuggestion:
            return "This thread seems to be causing stress. Mute it to take a break."
        case .disableNotifications:
            return "Temporarily disable notifications for this conversation?"
        case .switchToReflectionMode:
            return "Would you like to take a break with scripture or prayer?"
        }
    }

    var isOptional: Bool { true }
}

struct WellnessEvent: Codable, Identifiable {
    var id: String { "\(uid)-\(trigger.rawValue)-\(createdAt.timeIntervalSince1970)" }
    let uid: String
    let trigger: WellnessTrigger
    let intervention: WellnessIntervention
    let dismissed: Bool
    let actedOn: Bool
    let createdAt: Date
}

// MARK: - Reporting

enum ReportCategory: String, Codable, CaseIterable, Identifiable {
    case sexualContent        = "sexual_content"
    case minorSafety          = "minor_safety"
    case grooming             = "grooming"
    case impersonation        = "impersonation"
    case scam                 = "scam"
    case trafficking          = "trafficking"
    case violence             = "violence"
    case harassment           = "harassment"
    case fakeAIMedia          = "fake_ai_media"
    case misinformation       = "misinformation"
    case hateExtremism        = "hate_extremism"
    case selfHarmConcern      = "self_harm_concern"
    case privacyViolation     = "privacy_violation"
    case fakeChurchProfile    = "fake_church_profile"
    case fakeReviewTestimonial = "fake_review_testimonial"
    case botActivity          = "bot_activity"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .sexualContent:         return "Sexual content"
        case .minorSafety:           return "Child safety"
        case .grooming:              return "Grooming"
        case .impersonation:         return "Impersonation"
        case .scam:                  return "Scam or fraud"
        case .trafficking:           return "Trafficking"
        case .violence:              return "Violence"
        case .harassment:            return "Harassment"
        case .fakeAIMedia:           return "Fake or AI media"
        case .misinformation:        return "Misinformation"
        case .hateExtremism:         return "Hate or extremism"
        case .selfHarmConcern:       return "Self-harm concern"
        case .privacyViolation:      return "Privacy violation"
        case .fakeChurchProfile:     return "Fake church or profile"
        case .fakeReviewTestimonial: return "Fake review or testimonial"
        case .botActivity:           return "Bot or fake account"
        }
    }

    var isCritical: Bool {
        self == .minorSafety || self == .grooming || self == .trafficking
    }
}

enum SafetyReportStatus: String, Codable {
    case submitted          = "submitted"
    case queued             = "queued"
    case underReview        = "under_review"
    case escalated          = "escalated"
    case resolvedActioned   = "resolved_actioned"
    case resolvedNoAction   = "resolved_no_action"
    case appealed           = "appealed"
}

struct AbuseReportResult: Codable, Identifiable {
    var id: String { reportId }
    let reportId: String
    let status: SafetyReportStatus
    let contentQuarantined: Bool
    let escalated: Bool
    let policyVersion: String
}

// MARK: - Enforcement

enum SafetyAccountStatus: String, Codable, Equatable {
    case active     = "active"
    case warned     = "warned"
    case restricted = "restricted"
    case suspended  = "suspended"
    case banned     = "banned"

    var canPost: Bool { self == .active || self == .warned }
}

struct EnforcementProfile: Codable {
    let uid: String
    let strikePoints: Int
    let trustScore: Int     // 0–100
    let accountStatus: SafetyAccountStatus
    let policyVersion: String

    var canPost: Bool { accountStatus.canPost }
}

// MARK: - AI Transparency

struct AITransparencyRecord: Codable, Identifiable {
    var id: String { contentId }
    let contentId: String
    let contentType: ContentSurface
    let wasAIGenerated: Bool
    let wasAIAssisted: Bool
    let aiModelsUsed: [String]
    let labelShown: Bool
    let labelType: AILabelType
}

typealias TSAITransparencyRecord = AITransparencyRecord

// MARK: - Preflight State (iOS UI state machine)

enum ContentPreflightState: Equatable {
    case idle
    case checking
    case clean
    case labeled(reason: String)
    case limited(reason: String)
    case blocked(reason: String)
    case quarantined(reason: String)
    case underReview
    case appealAvailable(strikeId: String)
    case error(String)

    var canPublish: Bool {
        switch self {
        case .clean, .labeled: return true
        default: return false
        }
    }

    var publishButtonLabel: String {
        switch self {
        case .idle:       return "Post"
        case .checking:   return "Checking..."
        case .clean:      return "Post"
        case .labeled:    return "Post with label"
        case .blocked:    return "Cannot Post"
        case .quarantined:return "Under Review"
        default:          return "Post"
        }
    }

    var statusMessage: String? {
        switch self {
        case .checking:             return "This post is being checked before it appears."
        case .labeled(let r):       return r
        case .limited(let r):       return "Source uncertain — sharing is limited. \(r)"
        case .blocked(let r):       return r
        case .quarantined(let r):   return r
        case .underReview:          return "Your post is being reviewed."
        default:                    return nil
        }
    }
}

// MARK: - Enforcement Profile

enum TSAccountStatus: String, Codable, Equatable {
    case active     = "active"
    case warned     = "warned"
    case restricted = "restricted"
    case suspended  = "suspended"
    case banned     = "banned"

    var canPost: Bool {
        switch self {
        case .active, .warned: return true
        case .restricted, .suspended, .banned: return false
        }
    }
}

struct TSEnforcementProfile: Codable, Equatable {
    let uid: String
    let strikePoints: Int
    let trustScore: Int
    let accountStatus: TSAccountStatus
    let policyVersion: String
}

// MARK: - Reporting

typealias TSReportCategory = ReportCategory

enum TSReportStatus: String, Codable, CaseIterable {
    case submitted    = "submitted"
    case underReview  = "under_review"
    case resolved     = "resolved"
    case dismissed    = "dismissed"
}

struct TSAbuseReportResult: Codable, Identifiable {
    var id: String { reportId }
    let reportId: String
    let status: TSReportStatus
    let contentQuarantined: Bool
    let escalated: Bool
    let policyVersion: String
}

// MARK: - Media Provenance

enum TSCreatorDeclaration: String, Codable, CaseIterable, Equatable {
    case original         = "original"
    case humanOriginal    = "human_original"
    case edited           = "edited"
    case aiAssisted       = "ai_assisted"
    case aiGenerated      = "ai_generated"
    case editedOriginal   = "edited_original"
    case reposted         = "reposted"
    case unknown          = "unknown"

    var displayLabel: String {
        switch self {
        case .original:       return "I created this"
        case .humanOriginal:  return "Original human content"
        case .edited:         return "I edited this"
        case .aiAssisted:     return "Human-led, AI-assisted"
        case .aiGenerated:    return "AI-generated"
        case .editedOriginal: return "Edited original content"
        case .reposted:       return "Reposted from elsewhere"
        case .unknown:        return "Not specified"
        }
    }
}

enum TSProvenanceStatus: String, Codable, Equatable {
    case original = "original"
    case edited = "edited"
    case aiAssisted = "ai_assisted"
    case aiGenerated = "ai_generated"
    case reposted = "reposted"
    case sourceUncertain = "source_uncertain"
    case verifiedSource = "verified_source"
    case contextMissing = "context_missing"
    case verified = "verified"
    case pending  = "pending"
    case flagged  = "flagged"
    case unknown  = "unknown"

    var displayLabel: String {
        switch self {
        case .original: return "Original media"
        case .edited: return "Edited media"
        case .aiAssisted: return "AI-assisted"
        case .aiGenerated: return "AI-generated"
        case .reposted: return "Reposted"
        case .sourceUncertain: return "Source uncertain"
        case .verifiedSource, .verified: return "Verified source"
        case .contextMissing: return "Context missing"
        case .pending: return "Pending review"
        case .flagged: return "Flagged"
        case .unknown: return "Source uncertain"
        }
    }

    var requiresLabel: Bool {
        switch self {
        case .aiGenerated, .aiAssisted, .sourceUncertain, .contextMissing, .unknown:
            return true
        case .original, .edited, .reposted, .verifiedSource, .verified, .pending, .flagged:
            return false
        }
    }

    var limitSharing: Bool {
        self == .sourceUncertain || self == .unknown || self == .contextMissing
    }
}

struct TSMediaProvenance: Codable, Equatable {
    let mediaId: String
    let uploaderUid: String
    let originalHash: String
    let perceptualHash: String
    let aiDetectionScore: Double
    let editingDetected: Bool
    let creatorDeclaration: TSCreatorDeclaration
    let provenanceStatus: TSProvenanceStatus
    let trendEligible: Bool
    let boostEligible: Bool
    let labelRequired: Bool
    let policyVersion: String

    var aiLabelType: AILabelType {
        switch provenanceStatus {
        case .aiGenerated: return .aiGenerated
        case .aiAssisted: return .aiAssisted
        case .sourceUncertain, .unknown: return .mayBeAI
        default: return .none
        }
    }
}
