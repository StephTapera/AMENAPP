// BereanVoiceFeatureFlags.swift
// AMENAPP
//
// Berean Live Voice — Feature flags (all off by default)
//
// Thin façade over the canonical AMENFeatureFlags Remote Config registry.
// Previously these flags were hardcoded to `true`, which silently bypassed the
// Remote Config kill switch — production voice could only be disabled by an App
// Store update. Each accessor now reads AMENFeatureFlags.shared (RC-backed,
// default OFF). Sub-flags are additionally gated by the master so none can be
// live while voice is killed.

import Foundation

// MARK: - Feature Flags

/// Central feature-flag façade for Berean Live Voice.
///
/// Usage:
/// ```swift
/// guard BereanVoiceFeatureFlags.bereanVoiceEnabled else {
///     // show "Coming Soon" overlay
///     return
/// }
/// ```
@MainActor
struct BereanVoiceFeatureFlags {

    /// Master switch — gates all Live Voice entry points. Remote-Config backed.
    static var bereanVoiceEnabled: Bool {
        AMENFeatureFlags.shared.bereanVoiceEnabled
    }

    /// Full-duplex streaming (simultaneous listen + speak).
    static var bereanVoiceDuplexEnabled: Bool {
        bereanVoiceEnabled && AMENFeatureFlags.shared.bereanVoiceDuplexEnabled
    }

    /// Barge-in / interrupt while Berean is speaking.
    static var bereanVoiceInterruptEnabled: Bool {
        bereanVoiceEnabled && AMENFeatureFlags.shared.bereanVoiceInterruptEnabled
    }

    /// Empathy mode — emotionally adaptive responses and pacing.
    static var bereanVoiceEmpathyMode: Bool {
        bereanVoiceEnabled && AMENFeatureFlags.shared.bereanVoiceEmpathyMode
    }

    /// Church Notes capture mode (live sermon transcription).
    static var bereanVoiceChurchMode: Bool {
        bereanVoiceEnabled && AMENFeatureFlags.shared.bereanVoiceChurchMode
    }

    /// Prayer mode — guided prayer with gentle TTS pacing.
    static var bereanVoicePrayerMode: Bool {
        bereanVoiceEnabled && AMENFeatureFlags.shared.bereanVoicePrayerMode
    }
}
