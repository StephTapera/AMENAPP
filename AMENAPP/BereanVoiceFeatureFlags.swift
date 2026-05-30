// BereanVoiceFeatureFlags.swift
// AMENAPP
//
// Berean Live Voice — Feature flags
// B-22: bereanVoiceEnabled is now gated behind AMENFeatureFlags.shared.bereanVoiceEnabled
// (defaults false until bereanVoiceProxy + ttsProxy CFs are deployed).

import Foundation

// MARK: - Feature Flags

/// Central feature-flag registry for Berean Live Voice.
struct BereanVoiceFeatureFlags {

    // B-22: reads from the central AMENFeatureFlags so Remote Config can flip it on.
    // nonisolated(unsafe) allows access from non-async/non-MainActor contexts (e.g. SwiftUI body).
    // The underlying property is a simple Bool read — safe to access from any thread.
    static var bereanVoiceEnabled: Bool {
        // AMENFeatureFlags is @MainActor; access via MainActor.assumeIsolated when
        // called from the SwiftUI main thread, or default to false for safety.
        if Thread.isMainThread {
            return MainActor.assumeIsolated { AMENFeatureFlags.shared.bereanVoiceEnabled }
        }
        return false
    }
    static var bereanVoiceDuplexEnabled: Bool { return true }
    static var bereanVoiceInterruptEnabled: Bool { return true }
    static var bereanVoiceEmpathyMode: Bool { return true }
    static var bereanVoiceChurchMode: Bool { return true }
    static var bereanVoicePrayerMode: Bool { return true }

    #if DEBUG
    static var debugForceEnabled = true
    #endif
}
