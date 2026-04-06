// BereanVoiceFeatureFlags.swift
// AMENAPP
//
// Berean Live Voice — Feature flags (all off by default)
//
// All flags default to false so the Live Voice surface is
// invisible until explicitly enabled per environment or user tier.
// No existing files are modified.

import Foundation

// MARK: - Feature Flags

/// Central feature-flag registry for Berean Live Voice.
///
/// Usage:
/// ```swift
/// guard BereanVoiceFeatureFlags.bereanVoiceEnabled else {
///     // show "Coming Soon" overlay
///     return
/// }
/// ```
struct BereanVoiceFeatureFlags {

    // -------------------------------------------------------------------------
    // MARK: Production flags — all default off
    // -------------------------------------------------------------------------

    /// Master switch — gates all Live Voice entry points.
    static var bereanVoiceEnabled: Bool {
        #if DEBUG
        if debugForceEnabled { return true }
        #endif
        return false
    }

    /// Full-duplex streaming (simultaneous listen + speak).
    static var bereanVoiceDuplexEnabled: Bool {
        #if DEBUG
        if debugForceEnabled { return true }
        #endif
        return false
    }

    /// Barge-in / interrupt while Berean is speaking.
    static var bereanVoiceInterruptEnabled: Bool {
        #if DEBUG
        if debugForceEnabled { return true }
        #endif
        return false
    }

    /// Empathy mode — emotionally adaptive responses and pacing.
    static var bereanVoiceEmpathyMode: Bool {
        #if DEBUG
        if debugForceEnabled { return true }
        #endif
        return false
    }

    /// Church Notes capture mode (live sermon transcription).
    static var bereanVoiceChurchMode: Bool {
        #if DEBUG
        if debugForceEnabled { return true }
        #endif
        return false
    }

    /// Prayer mode — guided prayer with gentle TTS pacing.
    static var bereanVoicePrayerMode: Bool {
        #if DEBUG
        if debugForceEnabled { return true }
        #endif
        return false
    }

    // -------------------------------------------------------------------------
    // MARK: Debug override
    // -------------------------------------------------------------------------

    #if DEBUG
    /// Set to `true` in the Xcode scheme or a debug settings screen to enable
    /// all Live Voice flags at once during development.
    static var debugForceEnabled = false
    #endif
}
