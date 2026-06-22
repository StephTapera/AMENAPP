//
//  SupportEnums.swift
//  AMENAPP
//
//  Foundation enums for the Support Intelligence Layer.
//  All types are Codable, Sendable, and string-backed for Firestore compatibility.
//

import Foundation

// MARK: - Risk & Mode

/// Graduated risk tier. Conservative thresholds; one post alone cannot reach elevated/acute.
enum SupportRiskTier: String, Codable, Sendable, Comparable {
    case none      // 0.00–0.24
    case low       // 0.25–0.44
    case moderate  // 0.45–0.66
    case elevated  // 0.67–0.83
    case acute     // 0.84–1.00

    private var order: Int {
        switch self {
        case .none:     return 0
        case .low:      return 1
        case .moderate: return 2
        case .elevated: return 3
        case .acute:    return 4
        }
    }

    static func < (lhs: SupportRiskTier, rhs: SupportRiskTier) -> Bool {
        lhs.order < rhs.order
    }

    static func from(score: Double) -> SupportRiskTier {
        switch score {
        case ..<0.25:  return .none
        case ..<0.45:  return .low
        case ..<0.67:  return .moderate
        case ..<0.84:  return .elevated
        default:       return .acute
        }
    }

    var requiresImmediate: Bool { self >= .elevated }
    var suppressGiving: Bool    { self >= .elevated }
    var eligibleForPrompt: Bool { self == .moderate || self == .elevated || self == .acute }
}

/// The operational mode of the support system for this user.
enum SupportMode: String, Codable, Sendable {
    case quietMonitoring   // Low/none: content shaping only
    case gentleSupport     // Moderate: eligible for subtle prompts
    case activeSupport     // Elevated: clearer pathways, suppress giving
    case crisisReady       // Acute: immediate help pathways prioritized
    case recoveryBackoff   // Recovering: prompts backed off
}

// MARK: - Themes

/// Inferred emotional/situational themes from user content and behavior.
enum SupportTheme: String, Codable, Sendable, CaseIterable {
    case anxiety
    case stress
    case loneliness
    case grief
    case burnout
    case fear
    case prayerForPeace
    case prayerForStrength
    case depressionLikeLanguage
    case financialHardship
    case foodInsecurity
    case housingInsecurity
    case addictionRecovery
    case relationshipDistress
    case caregivingStress
    case spiritualExhaustion
    case gratitude
    case healingProgress
    case helpingSomeoneElse
    case crisisIndicatorsSoft
    case crisisIndicatorsStrong

    var isDistress: Bool {
        switch self {
        case .anxiety, .stress, .loneliness, .grief, .burnout, .fear,
             .depressionLikeLanguage, .financialHardship, .foodInsecurity,
             .housingInsecurity, .addictionRecovery, .relationshipDistress,
             .caregivingStress, .spiritualExhaustion,
             .crisisIndicatorsSoft, .crisisIndicatorsStrong:
            return true
        default:
            return false
        }
    }

    var isCrisis: Bool {
        self == .crisisIndicatorsSoft || self == .crisisIndicatorsStrong
    }

    var isPositive: Bool {
        self == .gratitude || self == .healingProgress
    }
}

// MARK: - Signals

/// The type of behavioral or semantic signal contributing to the support score.
enum SupportSignalType: String, Codable, Sendable {
    case postSemanticDistress       // Distress language detected in post
    case commentSemanticDistress    // Distress language in comment
    case prayerSupportNeed          // Prayer request implies support need
    case churchNoteStress           // Church note reflection with stress markers
    case searchIntentSupport        // Search query signals support seeking
    case supportContentDwell        // User dwelled on crisis/support content
    case lateNightUsageCluster      // Repeated late-night sessions
    case repeatedDraftDelete        // Draft started and deleted (distress indicator)
    case trustedOutreach            // Reached out to trusted support person
    case groundingCompleted         // Completed grounding exercise
    case hopefulLanguage            // Detected hopeful / healing language
    case forFriendDetected          // "My friend is struggling" pattern
    case givingIntentDetected       // Giving intent signal
    case supportiveReplyReceived    // Received meaningful reply
    case resourceOpened             // Opened wellness/support resource
    case resourceCompleted          // Completed a wellness resource
    case postAftercareDismissed     // Dismissed post-aftercare prompt

    var direction: SignalDirection {
        switch self {
        case .groundingCompleted, .hopefulLanguage, .supportiveReplyReceived,
             .resourceCompleted, .givingIntentDetected:
            return .decreaseSupportNeed
        default:
            return .increaseSupportNeed
        }
    }

    var defaultWeight: Double {
        switch self {
        case .postSemanticDistress:    return 0.38
        case .prayerSupportNeed:       return 0.32
        case .lateNightUsageCluster:   return 0.18
        case .supportContentDwell:     return 0.14
        case .repeatedDraftDelete:     return 0.22
        case .commentSemanticDistress: return 0.20
        case .churchNoteStress:        return 0.16
        case .searchIntentSupport:     return 0.25
        case .trustedOutreach:         return 0.12
        case .groundingCompleted:      return 0.20
        case .hopefulLanguage:         return 0.18
        case .forFriendDetected:       return 0.10
        case .givingIntentDetected:    return 0.08
        case .supportiveReplyReceived: return 0.15
        case .resourceOpened:          return 0.08
        case .resourceCompleted:       return 0.20
        case .postAftercareDismissed:  return 0.06
        }
    }
}

enum SignalDirection: String, Codable, Sendable {
    case increaseSupportNeed
    case decreaseSupportNeed
}

// MARK: - Prompts & Surfaces

/// The specific prompt category to show the user.
enum SupportPromptType: String, Codable, Sendable {
    case wellnessGroundingSubtle      // "A grounding exercise is here if you want it"
    case postAftercareGentle          // After vulnerable post: gentle check-in
    case prayerSupportBridge          // Prayer → support resource connection
    case reachOutTrustedSoft          // "Want to reach out to someone you trust?"
    case forFriendGuideSoft           // "For a friend" mode guidance
    case crisisHelpRespectful         // Respectful immediate help offer (elevated/acute)
    case giveRelevantPrivate          // Giving recommendation (only when stable)
    case recoveryReinforcementSoft    // Gentle recovery acknowledgment
    case noteCareSummary              // Post-save care summary for notes / church notes
    case churchCareRoute              // Find a Church routing from support context
    case practicalAidBridge           // Financial / food / housing aid bridge
}

/// The in-app surface where a support intervention may occur.
enum SupportSurface: String, Codable, Sendable {
    case postComposer
    case postDraft
    case postSubmitSheet
    case postPublished
    case commentDraft
    case commentPublished
    case dmDraft
    case dmThread
    case prayerComposer
    case prayerRequest
    case prayerRequestCard
    case notesComposer
    case note
    case churchNote
    case testimony
    case bereanChat
    case search
    case findChurch
    case resourcesTab
    case crisisScreen
    case givingScreen
    case notification
    case reportFlow
    case profileSupportSheet
    case feedWhileScrolling
}

/// What happened with a given intervention.
enum InterventionOutcome: String, Codable, Sendable {
    case shown
    case dismissed
    case engaged
    case suppressed
    case expired
}

// MARK: - Graph & Giving

enum SupportGraphEdgeType: String, Codable, Sendable {
    case prayerPartner
    case meaningfulReplier
    case trustedDM
    case supportGiver
    case mutualSupport
}

enum GivingCauseCategory: String, Codable, Sendable, CaseIterable {
    case mentalHealth
    case recovery
    case foodSecurity
    case housingSecurity
    case childrenYouth
    case disasterRelief
    case christianCounseling
    case communitySupport
    case churchMinistry
    case generalWellness
}

// MARK: - Stability Trend

enum StabilityTrend: String, Codable, Sendable {
    case improving
    case stable
    case declining
    case volatile
}
