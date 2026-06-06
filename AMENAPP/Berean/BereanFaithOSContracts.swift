// BereanFaithOSContracts.swift
// AMENAPP — Berean Intelligence OS
//
// Frozen Swift contract types matching faithos.contracts.ts.
// Pure value types — no business logic here.

import Foundation

// MARK: - Capability Tier

enum BereanCapabilityTier: String, Codable, CaseIterable, Comparable {
    case free = "FREE"
    case plus = "PLUS"
    case pro  = "PRO"

    private var sortOrder: Int {
        switch self { case .free: return 0; case .plus: return 1; case .pro: return 2 }
    }

    static func < (lhs: BereanCapabilityTier, rhs: BereanCapabilityTier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var displayName: String {
        switch self { case .free: return "Free"; case .plus: return "Amen+"; case .pro: return "Amen Pro" }
    }
}

// MARK: - Memory Node

struct BereanMemoryNode: Codable, Identifiable {
    let id: String
    let uid: String
    let kind: Kind
    let data: [String: String]
    let sensitivity: Sensitivity
    let createdAt: TimeInterval
    let userControlled: Bool

    enum Kind: String, Codable, CaseIterable {
        case prayer     = "PRAYER"
        case study      = "STUDY"
        case attendance = "ATTENDANCE"
        case note       = "NOTE"
        case teacher    = "TEACHER"
        case topic      = "TOPIC"
        case goal       = "GOAL"
        case milestone  = "MILESTONE"
        case person     = "PERSON"
        case formation  = "FORMATION"
        case mentorship = "MENTORSHIP"
    }

    enum Sensitivity: String, Codable {
        case normal    = "NORMAL"
        case sensitive = "SENSITIVE"
    }

    init(uid: String, kind: Kind, data: [String: String], sensitivity: Sensitivity = .normal) {
        self.id           = UUID().uuidString
        self.uid          = uid
        self.kind         = kind
        self.data         = data
        self.sensitivity  = sensitivity
        self.createdAt    = Date().timeIntervalSince1970
        self.userControlled = true
    }

    func toFirestore() -> [String: Any] {
        ["id": id, "uid": uid, "kind": kind.rawValue, "data": data,
         "sensitivity": sensitivity.rawValue, "createdAt": createdAt, "userControlled": true]
    }
}

// MARK: - Workspace

struct BereanWorkspaceModel: Codable, Identifiable {
    let id: String
    let ownerUid: String
    let kind: Kind
    var title: String
    var items: [String]
    let createdAt: TimeInterval

    enum Kind: String, Codable, CaseIterable {
        case study      = "STUDY"
        case theology   = "THEOLOGY"
        case leadership = "LEADERSHIP"
        case marriage   = "MARRIAGE"
        case custom     = "CUSTOM"
        case formation  = "FORMATION"
        case mentorship = "MENTORSHIP"

        var displayName: String {
            switch self {
            case .study: return "Study"; case .theology: return "Theology"
            case .leadership: return "Leadership"; case .marriage: return "Marriage"
            case .custom: return "Custom"; case .formation: return "Formation"
            case .mentorship: return "Mentorship"
            }
        }

        var systemImage: String {
            switch self {
            case .study: return "book.open"; case .theology: return "cross"
            case .leadership: return "star.circle"; case .marriage: return "heart.circle"
            case .custom: return "folder"; case .formation: return "figure.walk"
            case .mentorship: return "person.2"
            }
        }
    }
}

// MARK: - Berean Agent

struct BereanAgentModel: Codable, Identifiable {
    let id: String
    let kind: Kind
    let ownerUid: String
    var tools: [String]
    let tier: BereanCapabilityTier

    enum Kind: String, Codable, CaseIterable {
        case prayer    = "PRAYER"
        case study     = "STUDY"
        case church    = "CHURCH"
        case mentor    = "MENTOR"
        case formation = "FORMATION"

        var minimumTier: BereanCapabilityTier {
            switch self {
            case .prayer, .study, .formation: return .free
            case .church, .mentor: return .plus
            }
        }
    }
}

// MARK: - Artifact

struct BereanArtifactModel: Codable, Identifiable {
    let id: String
    let kind: Kind
    var title: String
    var shareScope: String
    let ownerUid: String
    let createdAt: TimeInterval

    enum Kind: String, Codable, CaseIterable {
        case studyGuide       = "STUDY_GUIDE"
        case prayerPlan       = "PRAYER_PLAN"
        case eventPlan        = "EVENT_PLAN"
        case leadershipNotes  = "LEADERSHIP_NOTES"
        case discipleshipPlan = "DISCIPLESHIP_PLAN"
        case formationPlan    = "FORMATION_PLAN"
        case mentorshipPlan   = "MENTORSHIP_PLAN"

        var displayName: String {
            switch self {
            case .studyGuide: return "Study Guide"; case .prayerPlan: return "Prayer Plan"
            case .eventPlan: return "Event Plan"; case .leadershipNotes: return "Leadership Notes"
            case .discipleshipPlan: return "Discipleship Plan"
            case .formationPlan: return "Formation Plan"; case .mentorshipPlan: return "Mentorship Plan"
            }
        }
    }
}

// MARK: - Vault Item

struct BereanVaultItemModel: Codable, Identifiable {
    let id: String
    let ownerUid: String
    let kind: Kind
    var title: String
    var isIndexed: Bool
    let createdAt: TimeInterval

    enum Kind: String, Codable, CaseIterable {
        case pdf = "PDF"; case sermon = "SERMON"; case video = "VIDEO"
        case voice = "VOICE"; case doc = "DOC"
    }
}

// MARK: - Formation

/// Canonical formation card kinds matching BereanFormationCardViews.swift's 7 card types.
/// INVARIANT: .crisis kind NEVER triggers a callModel call anywhere.
enum FormationCardKind: String, Codable, CaseIterable {
    case scripture  = "SCRIPTURE"
    case reflection = "REFLECTION"
    case prayer     = "PRAYER"
    case habit      = "HABIT"
    case challenge  = "CHALLENGE"
    case testimony  = "TESTIMONY"
    case crisis     = "CRISIS"  // Real crisis resources only — NO AI reflection, ever.

    var allowsAIReflection: Bool { self != .crisis }
}

struct BereanFormationEntry: Codable, Identifiable {
    let id: String
    let uid: String
    let cardKind: FormationCardKind
    var completedAt: TimeInterval?
    var streakDay: Int

    var isCompleted: Bool { completedAt != nil }

    init(uid: String, cardKind: FormationCardKind, streakDay: Int) {
        self.id = UUID().uuidString
        self.uid = uid
        self.cardKind = cardKind
        self.streakDay = streakDay
    }
}

// MARK: - Mentorship Memory

enum MentorSignalKind: String, Codable, CaseIterable {
    case needsAttention    = "needsAttention"
    case openQuestion      = "openQuestion"
    case prayerRequest     = "prayerRequest"
    case upcomingSession   = "upcomingSession"
    case progressUpdate    = "progressUpdate"
    case suggestedResource = "suggestedResource"
}

/// All mentorship memory nodes are SENSITIVE — zero cross-user access.
struct MentorshipMemoryNode: Codable, Identifiable {
    let id: String
    let uid: String
    let mentorshipId: String
    let signalKind: MentorSignalKind
    let data: [String: String]
    let createdAt: TimeInterval
    // Immutable invariant — mentorship memory is always sensitive
    let sensitivity: String = "SENSITIVE"

    init(uid: String, mentorshipId: String, signalKind: MentorSignalKind, data: [String: String]) {
        self.id = UUID().uuidString
        self.uid = uid
        self.mentorshipId = mentorshipId
        self.signalKind = signalKind
        self.data = data
        self.createdAt = Date().timeIntervalSince1970
    }

    func toFirestore() -> [String: Any] {
        ["id": id, "uid": uid, "mentorshipId": mentorshipId,
         "signalKind": signalKind.rawValue, "data": data,
         "sensitivity": sensitivity, "createdAt": createdAt, "kind": "MENTORSHIP"]
    }
}

// MARK: - iOS Bridge Context

struct iOSBereanContext: Codable {
    let uid: String
    let surface: String
    let tier: BereanCapabilityTier
    var activeWorkspaceId: String?
    var formationDay: Int?
    var hasMentorship: Bool
}
