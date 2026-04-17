//
//  SupportReasonCode.swift
//  AMENAPP
//
//  Explainability reason codes for support intervention decisions.
//  Used for audit trails, tuning, and false-positive detection.
//

import Foundation

enum SupportReasonCode: String, Codable, Sendable, CaseIterable {
    // Content signals
    case recentVulnerablePost
    case repeatedDistressLanguage
    case activeSelfHarmPhrase
    case hopelessnessWithRecency
    case prayerForPeacePattern
    case prayerForStrengthPattern
    case crisisLanguageStrong
    case crisisLanguageSoft
    case spiritualExhaustionLanguage
    case griefLanguage
    case lonelinessLanguage
    case burnoutLanguage
    case anxietyLanguage
    case hopelessnessLanguage
    case financialDistressPhrase
    case foodHousingDistressPhrase
    case churchHurtIntent
    case counselingSeekingPhrase
    case communitySeekingPhrase
    case indirectConcernForOtherPerson
    case prayerForUrgentNeed
    case notePatternHighDistress

    // Behavioral signals
    case supportContentDwell
    case lateNightUsageCluster
    case deletedDraftDistress
    case distressPersistence
    case abruptBehaviorShift
    case repeatedSupportSearch
    case repeatedDistressBehavior
    case repeatedLateNightUsage
    case rapidDeleteReeditPattern

    // Positive / recovery signals
    case groundingCompleted
    case hopefulLanguageDetected
    case recoveryTrendImproving
    case stableUsageCadence
    case supportiveReplyReceived

    // Social signals
    case trustedSupportAvailable
    case prayerPartnerEngaged
    case churchConnectionStrong

    // Modifiers
    case forFriendLanguage
    case helpingOthersContext
    case promptFatigueHigh
    case recentInterventionCooldown
    case recoveryBackoffActive
    case classifierLowConfidence
    case severityEscalatedBySurface
    case dismissedSimilarInterventionRecently
    case locationAwareChurchCareAvailable

    // Meta
    case noSignalsSufficient
    case multipleSignalsConcurrent
    case escalationFromPreviousTier
}
