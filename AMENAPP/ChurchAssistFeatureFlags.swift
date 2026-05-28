// ChurchAssistFeatureFlags.swift
// Find a Church — Feature flags
// AMENAPP

import Foundation

// MARK: - ChurchAssistFeatureFlags

struct ChurchAssistFeatureFlags {

    static var enableChurchAssistPill: Bool = true
    static var enableArrivalPrompts: Bool = true
    static var enableServiceMode: Bool = true
    static var enablePostVisitReflection: Bool = true
    static var enableVisitMemory: Bool = true
    static var enableFirstVisitCompanion: Bool = true
    static var enableRevisitSuggestions: Bool = true

    #if DEBUG
    static var debugForceAllEnabled: Bool = true

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
