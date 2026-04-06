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

    // Behavioral signals
    case supportContentDwell
    case lateNightUsageCluster
    case deletedDraftDistress
    case distressPersistence
    case abruptBehaviorShift
    case repeatedSupportSearch

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

    // Meta
    case noSignalsSufficient
    case multipleSignalsConcurrent
    case escalationFromPreviousTier
}
