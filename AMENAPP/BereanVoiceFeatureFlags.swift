// BereanVoiceFeatureFlags.swift
// AMENAPP
//
// Berean Live Voice — Feature flags (all ON)

import Foundation

// MARK: - Feature Flags

/// Central feature-flag registry for Berean Live Voice.
struct BereanVoiceFeatureFlags {

    static var bereanVoiceEnabled: Bool { return true }
    static var bereanVoiceDuplexEnabled: Bool { return true }
    static var bereanVoiceInterruptEnabled: Bool { return true }
    static var bereanVoiceEmpathyMode: Bool { return true }
    static var bereanVoiceChurchMode: Bool { return true }
    static var bereanVoicePrayerMode: Bool { return true }

    #if DEBUG
    static var debugForceEnabled = true
    #endif
}
