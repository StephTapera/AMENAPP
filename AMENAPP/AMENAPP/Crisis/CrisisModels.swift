// CrisisModels.swift
// AMENAPP
//
// All data models, enums, and value types for the Crisis Help & Support system.
// Privacy-first: no social visibility, no feed signals, no public state.
//

import Foundation

// MARK: - Crisis State

enum CrisisState: String, CaseIterable, Codable {
    case inDanger           = "in_danger"
    case overwhelmedButSafe = "overwhelmed_but_safe"
    case checkingIn         = "checking_in"

    var shortLabel: String {
        switch self {
        case .inDanger:           return "In danger"
        case .overwhelmedButSafe: return "Overwhelmed"
        case .checkingIn:         return "Checking in"
        }
    }

    var heroTitleLines: [String] {
        switch self {
        case .inDanger:           return ["Stay", "with us."]
        case .overwhelmedButSafe: return ["You are", "not alone."]
        case .checkingIn:         return ["You are", "seen."]
        }
    }

    var heroBody: String {
        switch self {
        case .inDanger:
            return "Immediate help comes first. Hold on — support is one tap away."
        case .overwhelmedButSafe:
            return "Confidential support is here, adapted to how you feel right now."
        case .checkingIn:
            return "Quiet support, planning tools, and privacy-first care."
        }
    }

    var heroGradientColors: [HeroGradientColor] {
        switch self {
        case .inDanger:
            return [
                HeroGradientColor(r: 0.165, g: 0.024, b: 0.024),
                HeroGradientColor(r: 0.435, g: 0.055, b: 0.055),
                HeroGradientColor(r: 0.710, g: 0.078, b: 0.078)
            ]
        case .overwhelmedButSafe:
            return [
                HeroGradientColor(r: 0.169, g: 0.047, b: 0.071),
                HeroGradientColor(r: 0.384, g: 0.067, b: 0.176),
                HeroGradientColor(r: 0.541, g: 0.071, b: 0.243)
            ]
        case .checkingIn:
            return [
                HeroGradientColor(r: 0.149, g: 0.067, b: 0.149),
                HeroGradientColor(r: 0.357, g: 0.102, b: 0.318),
                HeroGradientColor(r: 0.545, g: 0.157, b: 0.369)
            ]
        }
    }

    var defaultOpenSections: Set<CrisisSection> {
        switch self {
        case .inDanger:           return [.immediateHelp]
        case .overwhelmedButSafe: return [.groundingTools]
        case .checkingIn:         return [.safetyPlan]
        }
    }

    var isDanger: Bool { self == .inDanger }
}

// Lightweight color storage to avoid SwiftUI import in models
struct HeroGradientColor {
    let r: Double
    let g: Double
    let b: Double
}

// MARK: - Crisis Section

enum CrisisSection: String, CaseIterable, Identifiable {
    case immediateHelp   = "immediate_help"
    case groundingTools  = "grounding_tools"
    case bereanReflect   = "berean_reflect"
    case safetyPlan      = "safety_plan"
    case faithAndPrayer  = "faith_and_prayer"
    case recoverySupport = "recovery_support"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .immediateHelp:   return "Immediate Help"
        case .groundingTools:  return "Grounding Tools"
        case .bereanReflect:   return "Berean Reflect"
        case .safetyPlan:      return "Safety Plan"
        case .faithAndPrayer:  return "Faith & Prayer"
        case .recoverySupport: return "Recovery Support"
        }
    }

    var subtitle: String {
        switch self {
        case .immediateHelp:   return "Fastest actions first"
        case .groundingTools:  return "Adaptive calm tools"
        case .bereanReflect:   return "Private, gentle support"
        case .safetyPlan:      return "Your personal plan"
        case .faithAndPrayer:  return "Spiritual care and presence"
        case .recoverySupport: return "Ongoing wellbeing"
        }
    }

    var systemImage: String {
        switch self {
        case .immediateHelp:   return "phone.fill"
        case .groundingTools:  return "circle.dotted"
        case .bereanReflect:   return "sparkles"
        case .safetyPlan:      return "checkmark.shield.fill"
        case .faithAndPrayer:  return "hands.sparkles.fill"
        case .recoverySupport: return "heart.fill"
        }
    }

    var accentColorHex: SectionAccentColor {
        switch self {
        case .immediateHelp:   return SectionAccentColor(bg: (1.00, 0.93, 0.93), icon: (0.78, 0.10, 0.10))
        case .groundingTools:  return SectionAccentColor(bg: (0.93, 0.95, 1.00), icon: (0.15, 0.40, 0.85))
        case .bereanReflect:   return SectionAccentColor(bg: (0.96, 0.93, 1.00), icon: (0.45, 0.20, 0.80))
        case .safetyPlan:      return SectionAccentColor(bg: (0.93, 0.97, 0.94), icon: (0.13, 0.60, 0.29))
        case .faithAndPrayer:  return SectionAccentColor(bg: (1.00, 0.96, 0.90), icon: (0.70, 0.42, 0.05))
        case .recoverySupport: return SectionAccentColor(bg: (1.00, 0.94, 0.96), icon: (0.80, 0.20, 0.40))
        }
    }

    func priority(for state: CrisisState) -> Int {
        let orderings: [CrisisState: [CrisisSection]] = [
            .inDanger:           [.immediateHelp, .groundingTools, .bereanReflect, .safetyPlan, .faithAndPrayer, .recoverySupport],
            .overwhelmedButSafe: [.groundingTools, .bereanReflect, .immediateHelp, .safetyPlan, .faithAndPrayer, .recoverySupport],
            .checkingIn:         [.safetyPlan, .faithAndPrayer, .bereanReflect, .recoverySupport, .groundingTools, .immediateHelp]
        ]
        return orderings[state]?.firstIndex(of: self) ?? 99
    }
}

struct SectionAccentColor {
    let bg: (Double, Double, Double)
    let icon: (Double, Double, Double)
}

// MARK: - Grounding Mode

enum CrisisGroundingMode: String, CaseIterable, Identifiable {
    case sensory54321     = "5_4_3_2_1"
    case boxBreathing     = "box_breathing"
    case temperatureReset = "temperature_reset"
    case scriptureCalm    = "scripture_calm"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sensory54321:     return "5-4-3-2-1"
        case .boxBreathing:     return "Box breathing"
        case .temperatureReset: return "Cold water"
        case .scriptureCalm:    return "Psalm 23"
        }
    }

    var systemImage: String {
        switch self {
        case .sensory54321:     return "eye"
        case .boxBreathing:     return "wind"
        case .temperatureReset: return "drop"
        case .scriptureCalm:    return "book.closed"
        }
    }

    var prompt: String {
        switch self {
        case .sensory54321:
            return "Name 5 things you can see.\n4 you can feel.\n3 you can hear.\n2 you can smell.\n1 you can taste."
        case .boxBreathing:
            return "Breathe in for 4 counts.\nHold for 4.\nBreathe out for 4.\nHold for 4.\nLet's go slowly, one breath at a time."
        case .temperatureReset:
            return "Cold water on your wrists or face can interrupt acute distress. No pressure — just a gentle suggestion."
        case .scriptureCalm:
            return "\"The Lord is my shepherd; I shall not want.\nHe makes me lie down in green pastures.\nHe leads me beside still waters.\"\n— Psalm 23:1–2"
        }
    }
}

// MARK: - Escalation Intent

enum CrisisEscalationIntent {
    case none
    case hotline
    case trustedContact
    case pastorContact
}

// MARK: - Crisis Resource

struct CrisisResource: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let channel: Channel
    let target: String
    let tint: ResourceTint

    enum Channel: String { case call, text, web }
    enum ResourceTint: String { case red, purple, orange, blue, green }

    static let defaults: [CrisisResource] = [
        CrisisResource(id: "988", title: "988 Suicide & Crisis Lifeline", subtitle: "Call or text 24/7", channel: .call, target: "988", tint: .purple),
        CrisisResource(id: "cct", title: "Crisis Text Line", subtitle: "Text HOME to 741741", channel: .text, target: "741741", tint: .blue),
        CrisisResource(id: "nami", title: "NAMI Helpline", subtitle: "1-800-950-NAMI (6264)", channel: .call, target: "1-800-950-6264", tint: .green)
    ]
}

// MARK: - Safety Plan

struct CrisisSafetyPlan: Codable {
    var warningSigns: [String]          = []
    var groundingStrategies: [String]   = []
    var trustedPeople: [String]         = []
    var professionalResources: [String] = []
    var safePlaces: [String]            = []
    var environmentSteps: [String]      = []
    var faithReminders: [String]        = []
    var updatedAt: Date                 = Date()

    var isEmpty: Bool {
        warningSigns.isEmpty &&
        groundingStrategies.isEmpty &&
        trustedPeople.isEmpty &&
        professionalResources.isEmpty
    }
}

// MARK: - Trusted Contact

struct CrisisTrustedContact: Codable, Identifiable {
    var id: String       = UUID().uuidString
    var name: String
    var phoneNumber: String
    var relationship: String
    var isPastor: Bool   = false
    var shareTemplate: String = "Hey — I could use some support right now. Can we talk?"
}

// MARK: - Session Event (privacy-minimized analytics)

struct CrisisSessionEvent: Codable {
    var userId: String
    var enteredAt: Date
    var selectedState: String          = ""
    var bereanInvoked: Bool            = false
    var escalatedToHotline: Bool       = false
    var escalatedToTrustedContact: Bool = false
    var followUpScheduled: Bool        = false
    var localeResolved: String         = ""
    var highRiskSignalsDetected: Bool  = false
    var endedAt: Date?
    // NOTE: modulesOpened and groundingToolsUsed intentionally omitted
    // to minimize sensitive behavior logging. Aggregate counts only.
}
