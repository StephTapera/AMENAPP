//
//  SupportProfile.swift
//  AMENAPP
//
//  The primary derived support state document for a user.
//  Stored at users/{userId}/support_profile/current.
//  Read by the app to make intervention decisions.
//

import Foundation

struct SupportProfile: Codable, Sendable {
    // MARK: - Risk
    var riskTier: SupportRiskTier
    var riskScore: Double                      // 0.0–1.0
    var supportNeedScore: Double               // 0.0–1.0
    var helpingOthersScore: Double             // 0.0–1.0 (offsets self-risk)
    var recoveryScore: Double                  // 0.0–1.0 (higher = improving)
    var confidenceScore: Double                // Model confidence

    // MARK: - Themes
    var activeThemes: [SupportTheme]
    var themeConfidences: [String: Double]     // SupportTheme.rawValue → confidence

    // MARK: - Prompt State
    var eligibleForPrompt: Bool
    var promptCooldownUntil: Date?
    var promptFatigueScore: Double             // 0.0–1.0

    // MARK: - Resource Priority
    var resourcePriority: [String]             // Ordered list of resource type keys
    var recommendedDomains: [ResourceSupportDomain]
    var suggestedActions: [SupportAction]

    // MARK: - Mode
    var givingSuppressed: Bool
    var supportMode: SupportMode
    var forFriendModeEligible: Bool
    var trustedContactsEnabled: Bool
    var followUpsEnabled: Bool

    // MARK: - Meta
    var lastAnalyzedAt: Date?
    var lastEscalatedAt: Date?
    var lastDeescalatedAt: Date?
    var lastModelVersion: String
    var updatedAt: Date?

    // MARK: - Defaults

    static var empty: SupportProfile {
        SupportProfile(
            riskTier: .none,
            riskScore: 0.0,
            supportNeedScore: 0.0,
            helpingOthersScore: 0.0,
            recoveryScore: 0.5,
            confidenceScore: 0.0,
            activeThemes: [],
            themeConfidences: [:],
            eligibleForPrompt: false,
            promptCooldownUntil: nil,
            promptFatigueScore: 0.0,
            resourcePriority: [],
            recommendedDomains: [],
            suggestedActions: [],
            givingSuppressed: false,
            supportMode: .quietMonitoring,
            forFriendModeEligible: false,
            trustedContactsEnabled: false,
            followUpsEnabled: false,
            lastAnalyzedAt: nil,
            lastEscalatedAt: nil,
            lastDeescalatedAt: nil,
            lastModelVersion: "support-v1.0.0",
            updatedAt: nil
        )
    }
}
