// BereanVoiceTrustGate.swift
// AMEN App — Berean Voice Notes (Agent 1)
//
// Gates who may add a voice note to prayer/testimony posts.
// Checks: feature flag, per-post author disable, minor safety mode, trust score.
//
// POLICY DECISION: "minimumTrustForSensitivePosts" is currently .emailVerified.
// Change via Remote Config "berean_voice_trust_minimum" = "basic"|"email_verified"|etc.

import Foundation

// MARK: - Decision

enum VoiceTrustDecision: Equatable {
    case allowed
    case blockedFeatureOff
    case blockedDisabledByAuthor(authorDisplayName: String)
    case blockedMinorAccount
    case blockedLowTrust           // not enough trust for sensitive post
}

// MARK: - Post Sensitivity Classification

enum VoicePostSensitivity {
    case normal
    case sensitive    // prayer requests, raw testimony, abuse-related disclosures
}

// MARK: - Trust Gate

@MainActor
final class BereanVoiceTrustGate {

    static let shared = BereanVoiceTrustGate()

    // POLICY: minimum trust level to voice-reply on sensitive posts (prayer, raw testimony).
    // IdentityTrustLevel conforms to Comparable: basic < emailVerified < phoneVerified < trustedDevice < humanChallengePassed
    private let minimumTrustForSensitivePosts: IdentityTrustLevel = .emailVerified

    // MARK: - Evaluate

    func evaluate(
        postAuthorUid: String,
        postSensitivity: VoicePostSensitivity,
        voiceRepliesDisabled: Bool,
        authorDisplayName: String = "the author"
    ) async -> VoiceTrustDecision {

        // 1. Feature flag master kill switch
        guard AMENFeatureFlags.shared.voicePrayerCommentsEnabled ||
              AMENFeatureFlags.shared.voiceTestimonyCommentsEnabled else {
            return .blockedFeatureOff
        }

        // 2. Per-post author opt-out
        guard !voiceRepliesDisabled else {
            return .blockedDisabledByAuthor(authorDisplayName: authorDisplayName)
        }

        // 3. Minor safety mode — gated unless community-safe mode is explicitly on
        if AMENFeatureFlags.shared.minorSafetyModeEnabled && isCurrentUserMinor() {
            return .blockedMinorAccount
        }

        // 4. Trust score for sensitive posts — low-trust accounts cannot voice-note
        //    raw prayer requests or testimonies (too easy to abuse)
        if postSensitivity == .sensitive {
            let profile = await AmenIdentityTrustService.shared.trustProfile(for: postAuthorUid)
            if let trustLevel = profile?.trustLevel, trustLevel < minimumTrustForSensitivePosts {
                return .blockedLowTrust
            }
        }

        return .allowed
    }

    // MARK: - User-facing message

    func userMessage(for decision: VoiceTrustDecision) -> String {
        switch decision {
        case .allowed:
            return ""
        case .blockedFeatureOff:
            return "Voice replies are not available right now."
        case .blockedDisabledByAuthor(let name):
            return "\(name) has turned off voice replies on this post."
        case .blockedMinorAccount:
            return "Voice replies require an adult account. If this is incorrect, update your account settings."
        case .blockedLowTrust:
            return "Voice replies on prayer and testimony posts are available after your account is verified."
        }
    }

    // MARK: - Private

    // Minor flag is set server-side during onboarding and cached locally.
    // The server also enforces this — the client check is UI-only.
    private func isCurrentUserMinor() -> Bool {
        UserDefaults.standard.bool(forKey: "amen_user_is_minor")
    }
}
