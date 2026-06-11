import Foundation

enum Tier: String, Codable, CaseIterable, Sendable {
    case free
    case premium
    case church
    case creator
}

enum Capability: String, Codable, CaseIterable, Sendable {
    case signalBus
    case permissionsCenter
    case crisisDampening
    case gentleCheckIns
    case rhythmEngine
    case offlineCapture
    case basicContinuity
    case noteToGiveBridge
    case messagePrayerExtraction
    case visitVerification
    case givingReceipts
    case constellationModel
    case basicMatchFeedback
    case groupSuggestionsJoin
    case bereanContextInjection
    case verseResonance
    case cohortResonance
    case givingPortfolio
    case continuityCrossDevice
    case seasonsInsights
    case matchFeedbackExplained
    case volunteerNeedsPosting
    case groupFormationAnalytics
    case communityHealth
    case teachingAnalytics
}

enum GateReason: Codable, Equatable, Sendable {
    case entitled
    case flagOff
    case tierRequired(Tier)
    case gracePreview(remainingDays: Int)
    case crisisSuppressed
}

protocol EntitlementGating {
    func canAccess(_ capability: Capability) async -> GateDecision
}

struct GateDecision: Codable, Equatable, Sendable {
    let allowed: Bool
    let reason: GateReason

    static let entitled = GateDecision(allowed: true, reason: .entitled)
    static let flagOff = GateDecision(allowed: false, reason: .flagOff)
    static let crisisSuppressed = GateDecision(allowed: false, reason: .crisisSuppressed)

    static func tierRequired(_ tier: Tier) -> GateDecision {
        GateDecision(allowed: false, reason: .tierRequired(tier))
    }

    static func gracePreview(remainingDays: Int) -> GateDecision {
        GateDecision(allowed: true, reason: .gracePreview(remainingDays: remainingDays))
    }
}
