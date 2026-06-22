import Foundation

public enum AmenMomentType: String, CaseIterable, Codable, Sendable {
    case prayer
    case scripture
    case sermon
    case event
    case creator
    case study
    case mission
    case thread
}

public enum AmenMomentTemporalState: String, CaseIterable, Codable, Sendable {
    case upcoming
    case live
    case recap
    case evergreen
}

public enum AmenMomentDeepenAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case summarize
    case crossReference
    case generatePrayer
    case generateStudyGuide
    case generateDiscussion
    case generateDevotional
    case saveTo

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .summarize: return "Summarize"
        case .crossReference: return "Cross-reference"
        case .generatePrayer: return "Generate Prayer"
        case .generateStudyGuide: return "Study Guide"
        case .generateDiscussion: return "Discussion"
        case .generateDevotional: return "Devotional"
        case .saveTo: return "Save"
        }
    }

    var systemImage: String {
        switch self {
        case .summarize: return "text.alignleft"
        case .crossReference: return "point.3.connected.trianglepath.dotted"
        case .generatePrayer: return "hands.sparkles"
        case .generateStudyGuide: return "book.closed"
        case .generateDiscussion: return "quote.bubble"
        case .generateDevotional: return "sunrise"
        case .saveTo: return "tray.and.arrow.down"
        }
    }
}

public enum AmenMomentSaveTarget: String, CaseIterable, Codable, Sendable {
    case prayerJournal
    case studyJournal
    case churchNotes
    case sermonCollection
    case savedTeachings
}

public enum AmenMomentBereanMode: String, Codable, Sendable {
    case ask
    case discern
    case build
}

public struct AmenMoment: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let type: AmenMomentType
    public let temporalState: AmenMomentTemporalState
    public let refId: String
    public let ownerId: String
    public let createdAt: Int64
    public let title: String
    public let summary: String

    public init(
        id: String,
        type: AmenMomentType,
        temporalState: AmenMomentTemporalState,
        refId: String,
        ownerId: String,
        createdAt: Int64,
        title: String,
        summary: String
    ) {
        self.id = id
        self.type = type
        self.temporalState = temporalState
        self.refId = refId
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.title = title
        self.summary = summary
    }
}

public struct AmenMomentFlags: Equatable, Sendable {
    public let momentSystemEnabled: Bool
    public let deepenActionsEnabled: Bool
    public let gatherLiveEnabled: Bool
    public let gatherComplianceGateCleared: Bool

    public static let off = AmenMomentFlags(
        momentSystemEnabled: false,
        deepenActionsEnabled: false,
        gatherLiveEnabled: false,
        gatherComplianceGateCleared: false
    )
}

public struct AmenMomentDeepenResult: Equatable, Sendable {
    public let momentId: String
    public let action: AmenMomentDeepenAction
    public let output: String
    public let citations: [String]
    public let savedTo: AmenMomentSaveTarget?
    public let guardianPassed: Bool
    public let guardianReason: String?
}
