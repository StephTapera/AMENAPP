import Foundation

public enum MomentType: String, Codable, CaseIterable, Sendable {
    case prayer
    case scripture
    case sermon
    case event
    case creator
    case study
    case mission
    case thread
}

public enum TemporalState: String, Codable, CaseIterable, Sendable {
    case upcoming
    case live
    case recap
    case evergreen
}

public enum VerbFamily: String, Codable, CaseIterable, Sendable {
    case gather
    case deepen
    case invite
    case follow
}

public struct Moment: Codable, Equatable, Sendable {
    public let id: String
    public let type: MomentType
    public let temporalState: TemporalState
    public let refId: String
    public let ownerId: String
    public let createdAt: Int64

    public init(
        id: String,
        type: MomentType,
        temporalState: TemporalState,
        refId: String,
        ownerId: String,
        createdAt: Int64
    ) {
        self.id = id
        self.type = type
        self.temporalState = temporalState
        self.refId = refId
        self.ownerId = ownerId
        self.createdAt = createdAt
    }
}

public struct MomentFlags: Codable, Equatable, Sendable {
    public let momentSystemEnabled: Bool
    public let deepenActionsEnabled: Bool
    public let gatherLiveEnabled: Bool

    public static let off = MomentFlags(
        momentSystemEnabled: false,
        deepenActionsEnabled: false,
        gatherLiveEnabled: false
    )
}

public enum DeepenActionKind: String, Codable, CaseIterable, Sendable {
    case summarize
    case crossReference
    case generatePrayer
    case generateStudyGuide
    case generateDiscussion
    case generateDevotional
    case saveTo
}

public enum GatherActionKind: String, Codable, CaseIterable, Sendable {
    case prayLive
    case joinAudio
    case joinDiscussion
}

public enum ActionKind: Codable, Equatable, Sendable {
    case deepen(DeepenActionKind)
    case gather(GatherActionKind)
    case invite
    case follow
}

public struct MomentAction: Codable, Equatable, Sendable {
    public let id: ActionKind
    public let family: VerbFamily
    public let enabled: Bool
    public let reason: String?
}

public func availableActions(for moment: Moment, flags: MomentFlags) -> [MomentAction] {
    guard flags.momentSystemEnabled else {
        return []
    }

    var actions: [MomentAction] = []

    if flags.deepenActionsEnabled {
        actions.append(contentsOf: DeepenActionKind.allCases.map {
            MomentAction(id: .deepen($0), family: .deepen, enabled: true, reason: nil)
        })
    }

    if moment.temporalState == .live && flags.gatherLiveEnabled {
        actions.append(contentsOf: GatherActionKind.allCases.map {
            MomentAction(id: .gather($0), family: .gather, enabled: true, reason: nil)
        })
    }

    actions.append(MomentAction(id: .invite, family: .invite, enabled: false, reason: "uiDeferred"))
    actions.append(MomentAction(id: .follow, family: .follow, enabled: false, reason: "uiDeferred"))

    return actions
}

public enum BereanMode: String, Codable, CaseIterable, Sendable {
    case ask
    case discern
    case build
}

public enum SaveTarget: String, Codable, CaseIterable, Sendable {
    case prayerJournal
    case studyJournal
    case churchNotes
    case sermonCollection
    case savedTeachings
}

public struct DeepenRequest: Codable, Equatable, Sendable {
    public let moment: Moment
    public let action: DeepenActionKind
    public let requesterId: String
    public let bereanMode: BereanMode
    public let saveTarget: SaveTarget?
    public let locale: String?
}

public struct GuardianReview: Codable, Equatable, Sendable {
    public let passed: Bool
    public let policyVersion: String
    public let reason: String?
}

public struct DeepenResult: Codable, Equatable, Sendable {
    public let momentId: String
    public let action: DeepenActionKind
    public let output: String
    public let citations: [String]
    public let savedTo: SaveTarget?
    public let guardian: GuardianReview
    public let createdAt: Int64
}

public struct GatherRequest: Codable, Equatable, Sendable {
    public let moment: Moment
    public let action: GatherActionKind
    public let requesterId: String
}

public enum GatherStatus: String, Codable, Sendable {
    case gated
    case notImplemented
}

public enum GatherReason: String, Codable, Sendable {
    case complianceGateRequired
    case flagDisabled
    case v1StubOnly
}

public struct GatherResult: Codable, Equatable, Sendable {
    public let momentId: String
    public let action: GatherActionKind
    public let status: GatherStatus
    public let reason: GatherReason
}

public let momentFunctionRegion = "us-east1"

public let deepenFunctionNames = [
    "momentSummarize",
    "momentCrossReference",
    "momentGeneratePrayer",
    "momentGenerateStudyGuide",
    "momentGenerateDiscussion",
    "momentGenerateDevotional",
    "momentSaveTo",
]

public let gatherFunctionNames = [
    "momentPrayLive",
    "momentJoinAudio",
    "momentJoinDiscussion",
]

