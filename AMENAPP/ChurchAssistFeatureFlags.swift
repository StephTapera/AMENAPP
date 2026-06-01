// ChurchAssistFeatureFlags.swift
// Find a Church — Feature flags
// AMENAPP

import Foundation

// TODO: Wire to AMENFeatureFlags.shared for Remote Config kill-switch support

// MARK: - ChurchAssistFeatureFlags

struct ChurchAssistFeatureFlags {

    static var enableChurchAssistPill: Bool = false
    static var enableArrivalPrompts: Bool = false
    static var enableServiceMode: Bool = false
    static var enablePostVisitReflection: Bool = false
    static var enableVisitMemory: Bool = false
    static var enableFirstVisitCompanion: Bool = false
    static var enableRevisitSuggestions: Bool = false

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
