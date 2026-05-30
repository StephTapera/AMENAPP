// TopChromeFeatureFlags.swift
// Smart Header Orchestrator — Feature flags

import Foundation

struct TopChromeFeatureFlags {
    static var smartHeaderEnabled: Bool { return true }

    static var greetingEnabled: Bool        { true }
    static var verseIntegrationEnabled: Bool { true }
    static var compactModeEnabled: Bool     { true }
    static var intentAdaptationEnabled: Bool { true }

    static var verseFirstOrder: Bool        { true }

    #if DEBUG
    static var debugForceEnabled = true
    #endif
}
