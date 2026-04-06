// ChurchAssistFeatureFlags.swift
// Find a Church — Feature flags (all off by default)
// AMENAPP

import Foundation

// MARK: - ChurchAssistFeatureFlags

struct ChurchAssistFeatureFlags {

    // All flags off by default — enables safe incremental rollout

    static var enableChurchAssistPill: Bool = false
    static var enableArrivalPrompts: Bool = false
    static var enableServiceMode: Bool = false
    static var enablePostVisitReflection: Bool = false
    static var enableVisitMemory: Bool = false
    static var enableFirstVisitCompanion: Bool = false
    static var enableRevisitSuggestions: Bool = false

    #if DEBUG
    /// When true, overrides all flags to enabled for QA and development.
    /// Never set to true in production builds.
    static var debugForceAllEnabled: Bool = false

    /// Returns the effective value of a flag — if debugForceAllEnabled is set,
    /// all flags return true regardless of their individual values.
    static func effective(_ flag: Bool) -> Bool {
        debugForceAllEnabled ? true : flag
    }
    #else
    @inline(__always)
    static func effective(_ flag: Bool) -> Bool {
        flag
    }
    #endif
}
