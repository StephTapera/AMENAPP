// IntelligenceModels.swift — AMEN Living Intelligence
// Canonical Swift types for the "What Needs Your Attention" surface.
// All backend contracts mirror these definitions exactly.

import Foundation

// MARK: - IntelligenceTier

enum IntelligenceTier: String, Codable, CaseIterable {
    case spiritual = "SPIRITUAL"
    case community = "COMMUNITY"
    case family    = "FAMILY"
    case local     = "LOCAL"
    case global    = "GLOBAL"

    var displayName: String {
        switch self {
        case .spiritual: return "For Your Spiritual Formation"
        case .community: return "In Your Community"
        case .family:    return "For Your Family"
        case .local:     return "Happening Near You"
        case .global:    return "In the World"
        }
    }

    var displayOrder: Int {
        switch self {
        case .spiritual: return 0
        case .community: return 1
        case .family:    return 2
        case .local:     return 3
        case .global:    return 4
        }
    }
}

// MARK: - TruthLevel

enum TruthLevel: String, Codable, CaseIterable {
    case verified           = "VERIFIED"
    case churchConfirmed    = "CHURCH_CONFIRMED"
    case communityConfirmed = "COMMUNITY_CONFIRMED"
    case developing         = "DEVELOPING"

    var displayLabel: String {
        switch self {
        case .verified:           return "Verified"
        case .churchConfirmed:    return "Church Confirmed"
        case .communityConfirmed: return "Community Confirmed"
        case .developing:         return "Developing"
        }
    }
}

// MARK: - ActionRung

enum ActionRung: String, Codable, CaseIterable, Comparable {
    case notice   = "NOTICE"
    case pray     = "PRAY"
    case learn    = "LEARN"
    case discuss  = "DISCUSS"
    case give     = "GIVE"
    case showUp   = "SHOW_UP"
    case start    = "START"

    private var order: Int {
        switch self {
        case .notice:  return 0
        case .pray:    return 1
        case .learn:   return 2
        case .discuss: return 3
        case .give:    return 4
        case .showUp:  return 5
        case .start:   return 6
        }
    }

    static func < (lhs: ActionRung, rhs: ActionRung) -> Bool {
        lhs.order < rhs.order
    }
}

// MARK: - BackingKind

enum BackingKind: String, Codable, CaseIterable {
    case church        = "CHURCH"
    case org           = "ORG"
    case event         = "EVENT"
    case prayerRequest = "PRAYER_REQUEST"
    case study         = "STUDY"
    case need          = "NEED"
}

// MARK: - Supporting Structs

struct BackingEntity: Codable {
    let kind: BackingKind
    let id: String
    let verified: Bool
}

struct CardAction: Codable, Identifiable {
    let rung: ActionRung
    let label: String
    let handler: String    // CF callable name
    let target: String     // entity id
    var id: String { handler + target }
}

struct CardFormation: Codable {
    let finite: Bool               // always true
    let spectacleCounters: Bool    // always false
    let lamentFrame: Bool?
    let loopParentId: String?
}

/// Backward-compatibility alias for views that still use IntelligenceFormation.
typealias IntelligenceFormation = CardFormation

struct CardGeo: Codable {
    let lat: Double
    let lng: Double
    let coarse: Bool  // always true
}

/// Backward-compatibility alias for views that still use IntelligenceGeo.
typealias IntelligenceGeo = CardGeo

// MARK: - IntelligenceCard

struct IntelligenceCard: Codable, Identifiable {
    let id: String
    let tier: IntelligenceTier
    let title: String
    let summary: [String]               // <=3 bullets
    let backingEntity: BackingEntity    // REQUIRED
    let truthLevel: TruthLevel
    let matchScore: Double?
    let matchReasons: [String]?
    let actions: [CardAction]
    let rankScore: Double
    let rankReasons: [String]           // REQUIRED — legible
    let geo: CardGeo?
    let formation: CardFormation
    let source: String?                 // required for .global tier
    let createdAt: Double
    let expiresAt: Double
}

// MARK: - IntelligenceBrief

struct IntelligenceBrief: Codable {
    let userId: String
    let cards: [IntelligenceCard]
    let generatedAt: Double
    let expiresAt: Double
}

// MARK: - UI State Enum (used by IntelligenceBriefViewModel)

enum IntelligenceUIState: Equatable {
    case loading
    case populated
    case empty
    case error(String)
    case offlineStale
    case sensitive
}
