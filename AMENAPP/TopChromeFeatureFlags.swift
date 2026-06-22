// TopChromeFeatureFlags.swift
// Smart Header Orchestrator — Feature flags

import Foundation

struct TopChromeFeatureFlags {
    // Master switch — false = system completely disabled, existing headers unchanged
    // Backed by a published property on AMENFeatureFlags once added; hardcoded
    // to false until Remote Config key "smart_header_orchestrator" is enabled.
    static var smartHeaderEnabled: Bool {
        #if DEBUG
        if debugForceEnabled { return true }
        #endif
        return true
    }

    // Sub-flags (only evaluated when master is on)
    static var greetingEnabled: Bool        { smartHeaderEnabled && true }
    static var verseIntegrationEnabled: Bool { smartHeaderEnabled && true }
    static var compactModeEnabled: Bool     { smartHeaderEnabled && true }
    static var intentAdaptationEnabled: Bool { smartHeaderEnabled && true }

    // A/B — verse-first vs greeting-first ordering
    static var verseFirstOrder: Bool        { false }

    // Development override (set to true in DEBUG to force-enable)
    #if DEBUG
    static var debugForceEnabled = true
    #endif
}
