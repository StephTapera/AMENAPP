//
//  AmenSafetyFeatureFlags.swift
//  AMENAPP
//
//  Feature flags for the Amen Trust + Safety OS.
//  All safety flags default ON (fail-safe).
//  Kill switches default OFF.
//
//  Safety-critical flags are server-authoritative:
//  jailbroken devices can modify Remote Config values,
//  so enforcement decisions NEVER rely on client flags alone.
//  Backend callables enforce independently.
//

import Foundation
import FirebaseRemoteConfig

@MainActor
final class AmenSafetyFeatureFlags: ObservableObject {

    static let shared = AmenSafetyFeatureFlags()
    private let remoteConfig = RemoteConfig.remoteConfig()

    // ── Content Preflight ─────────────────────────────────────────────────

    /// Run text preflight before publishing any UGC. Default ON.
    @Published var contentPreflightEnabled: Bool = true
    /// Run image preflight on every uploaded image. Default ON.
    @Published var imagePreflightEnabled: Bool = true
    /// Run video preflight on every uploaded video. Default ON.
    @Published var videoPreflightEnabled: Bool = true
    /// Run audio preflight on transcripts. Default ON.
    @Published var audioPreflightEnabled: Bool = true

    // ── True Source / Provenance ──────────────────────────────────────────

    /// Register provenance on every media upload. Default ON.
    @Published var mediaProvenanceEnabled: Bool = true
    /// Show True Source badge in feed. Default ON.
    @Published var trueSourceBadgeEnabled: Bool = true
    /// Show AI-generated label when detected. Default ON.
    @Published var aiGeneratedLabelEnabled: Bool = true
    /// Show "Source uncertain" label when provenance unknown. Default ON.
    @Published var sourceUncertainLabelEnabled: Bool = true
    /// Add friction (confirmation sheet) before sharing uncertain-source media. Default ON.
    @Published var shareUncertainFrictionEnabled: Bool = true
    /// Prevent uncertain-source media from trending. Default ON.
    @Published var provenanceTrendGateEnabled: Bool = true

    // ── Bot Defense ───────────────────────────────────────────────────────

    /// Evaluate bot score before high-velocity actions. Default ON.
    @Published var botDefenseEnabled: Bool = true
    /// Show challenge (CAPTCHA-style) to suspected bots. Default ON.
    @Published var botChallengeEnabled: Bool = true
    /// Suppress bot engagement from ranking. Default ON.
    @Published var botRankingSuppressionEnabled: Bool = true

    // ── Identity Trust ────────────────────────────────────────────────────

    /// Show verified identity badge. Default ON.
    @Published var identityBadgeEnabled: Bool = true
    /// Label unverified authority claims (pastor, doctor, etc). Default ON.
    @Published var unverifiedClaimLabelEnabled: Bool = true
    /// Flag suspected impersonation accounts. Default ON.
    @Published var impersonationDetectionEnabled: Bool = true

    // ── Ranking Safety ────────────────────────────────────────────────────

    /// Use safety-first ranking. Default ON.
    @Published var rankingSafetyEnabled: Bool = true
    /// Hide vanity metrics (likes/views) by default. Default ON.
    @Published var hideVanityMetricsEnabled: Bool = true
    /// Trend gate: require trust + provenance for trending. Default ON.
    @Published var trendGateEnabled: Bool = true

    // ── Wellness ──────────────────────────────────────────────────────────

    /// Show wellness interventions. Default ON.
    @Published var wellnessInterventionsEnabled: Bool = true
    /// Selah pause for doomscrolling detection. Default ON.
    @Published var selahPauseEnabled: Bool = true
    /// Post confirmation for borderline content. Default ON.
    @Published var postConfirmationEnabled: Bool = true

    // ── Reporting ─────────────────────────────────────────────────────────

    /// Enable abuse reporting. Default ON (non-negotiable).
    @Published var reportingEnabled: Bool = true
    /// One-tap report button in feed. Default ON.
    @Published var oneTapReportEnabled: Bool = true

    // ── AI Transparency ───────────────────────────────────────────────────

    /// Show "Why am I seeing this?" on posts. Default ON.
    @Published var whyThisPostEnabled: Bool = true
    /// Show AI transparency sheet. Default ON.
    @Published var aiTransparencySheetEnabled: Bool = true

    // ── Kill Switches (default OFF = safe) ────────────────────────────────

    /// Emergency kill: disable all Trust+Safety preflight (NEVER enable in prod).
    @Published var trustSafetyKillSwitch: Bool = false

    // ─────────────────────────────────────────────────────────────────────

    private init() { fetchRemoteConfig() }

    func fetchRemoteConfig() {
        let defaults: [String: NSObject] = [
            "trustSafety_contentPreflightEnabled":      true as NSNumber,
            "trustSafety_imagePreflightEnabled":         true as NSNumber,
            "trustSafety_videoPreflightEnabled":         true as NSNumber,
            "trustSafety_audioPreflightEnabled":         true as NSNumber,
            "trustSafety_mediaProvenanceEnabled":        true as NSNumber,
            "trustSafety_trueSourceBadgeEnabled":        true as NSNumber,
            "trustSafety_aiGeneratedLabelEnabled":       true as NSNumber,
            "trustSafety_sourceUncertainLabelEnabled":   true as NSNumber,
            "trustSafety_shareUncertainFrictionEnabled": true as NSNumber,
            "trustSafety_provenanceTrendGateEnabled":    true as NSNumber,
            "trustSafety_botDefenseEnabled":             true as NSNumber,
            "trustSafety_botChallengeEnabled":           true as NSNumber,
            "trustSafety_botRankingSuppressionEnabled":  true as NSNumber,
            "trustSafety_identityBadgeEnabled":          true as NSNumber,
            "trustSafety_unverifiedClaimLabelEnabled":   true as NSNumber,
            "trustSafety_impersonationDetectionEnabled": true as NSNumber,
            "trustSafety_rankingSafetyEnabled":          true as NSNumber,
            "trustSafety_hideVanityMetricsEnabled":      true as NSNumber,
            "trustSafety_trendGateEnabled":              true as NSNumber,
            "trustSafety_wellnessInterventionsEnabled":  true as NSNumber,
            "trustSafety_selahPauseEnabled":             true as NSNumber,
            "trustSafety_postConfirmationEnabled":       true as NSNumber,
            "trustSafety_reportingEnabled":              true as NSNumber,
            "trustSafety_oneTapReportEnabled":           true as NSNumber,
            "trustSafety_whyThisPostEnabled":            true as NSNumber,
            "trustSafety_aiTransparencySheetEnabled":    true as NSNumber,
            "trustSafety_killSwitch":                    false as NSNumber,
        ]
        remoteConfig.setDefaults(defaults)

        remoteConfig.fetchAndActivate { [weak self] _, error in
            guard let self, error == nil else { return }
            Task { @MainActor in
                self.applyRemoteConfig()
            }
        }
    }

    private func applyRemoteConfig() {
        contentPreflightEnabled      = remoteConfig.configValue(forKey: "trustSafety_contentPreflightEnabled").boolValue
        imagePreflightEnabled        = remoteConfig.configValue(forKey: "trustSafety_imagePreflightEnabled").boolValue
        videoPreflightEnabled        = remoteConfig.configValue(forKey: "trustSafety_videoPreflightEnabled").boolValue
        audioPreflightEnabled        = remoteConfig.configValue(forKey: "trustSafety_audioPreflightEnabled").boolValue
        mediaProvenanceEnabled       = remoteConfig.configValue(forKey: "trustSafety_mediaProvenanceEnabled").boolValue
        trueSourceBadgeEnabled       = remoteConfig.configValue(forKey: "trustSafety_trueSourceBadgeEnabled").boolValue
        aiGeneratedLabelEnabled      = remoteConfig.configValue(forKey: "trustSafety_aiGeneratedLabelEnabled").boolValue
        sourceUncertainLabelEnabled  = remoteConfig.configValue(forKey: "trustSafety_sourceUncertainLabelEnabled").boolValue
        shareUncertainFrictionEnabled = remoteConfig.configValue(forKey: "trustSafety_shareUncertainFrictionEnabled").boolValue
        provenanceTrendGateEnabled   = remoteConfig.configValue(forKey: "trustSafety_provenanceTrendGateEnabled").boolValue
        botDefenseEnabled            = remoteConfig.configValue(forKey: "trustSafety_botDefenseEnabled").boolValue
        botChallengeEnabled          = remoteConfig.configValue(forKey: "trustSafety_botChallengeEnabled").boolValue
        botRankingSuppressionEnabled = remoteConfig.configValue(forKey: "trustSafety_botRankingSuppressionEnabled").boolValue
        identityBadgeEnabled         = remoteConfig.configValue(forKey: "trustSafety_identityBadgeEnabled").boolValue
        unverifiedClaimLabelEnabled  = remoteConfig.configValue(forKey: "trustSafety_unverifiedClaimLabelEnabled").boolValue
        impersonationDetectionEnabled = remoteConfig.configValue(forKey: "trustSafety_impersonationDetectionEnabled").boolValue
        rankingSafetyEnabled         = remoteConfig.configValue(forKey: "trustSafety_rankingSafetyEnabled").boolValue
        hideVanityMetricsEnabled     = remoteConfig.configValue(forKey: "trustSafety_hideVanityMetricsEnabled").boolValue
        trendGateEnabled             = remoteConfig.configValue(forKey: "trustSafety_trendGateEnabled").boolValue
        wellnessInterventionsEnabled = remoteConfig.configValue(forKey: "trustSafety_wellnessInterventionsEnabled").boolValue
        selahPauseEnabled            = remoteConfig.configValue(forKey: "trustSafety_selahPauseEnabled").boolValue
        postConfirmationEnabled      = remoteConfig.configValue(forKey: "trustSafety_postConfirmationEnabled").boolValue
        reportingEnabled             = remoteConfig.configValue(forKey: "trustSafety_reportingEnabled").boolValue
        oneTapReportEnabled          = remoteConfig.configValue(forKey: "trustSafety_oneTapReportEnabled").boolValue
        whyThisPostEnabled           = remoteConfig.configValue(forKey: "trustSafety_whyThisPostEnabled").boolValue
        aiTransparencySheetEnabled   = remoteConfig.configValue(forKey: "trustSafety_aiTransparencySheetEnabled").boolValue
        trustSafetyKillSwitch        = remoteConfig.configValue(forKey: "trustSafety_killSwitch").boolValue
    }
}
