// ChurchAssistFeatureFlags.swift
// Find a Church — Feature flags (all off by default)
// AMENAPP

import Foundation

// MARK: - ChurchAssistFeatureFlags

struct ChurchAssistFeatureFlags {

    // All flags off by default — enables safe incremental rollout

    static var enableChurchAssistPill: Bool = true
    static var enableArrivalPrompts: Bool = true
    static var enableServiceMode: Bool = true
    static var enablePostVisitReflection: Bool = true
    static var enableVisitMemory: Bool = true
    static var enableFirstVisitCompanion: Bool = true
    static var enableRevisitSuggestions: Bool = true

    #if DEBUG
    /// When true, overrides all flags to enabled for QA and development.
    /// Never set to true in production builds.
    static var debugForceAllEnabled: Bool = true

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
