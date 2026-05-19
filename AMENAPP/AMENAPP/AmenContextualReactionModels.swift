import SwiftUI
import Foundation

enum AmenContextualTriggerType: String, Codable, CaseIterable {
    case like
    case doubleTap
    case longPress
    case commentText
    case replyText
    case scriptureReference
    case prayerPhrase
    case testimonyPhrase
    case gratitudePhrase
    case save
    case share
    case seasonal
    case culturalMoment
    case relationshipPattern
}

enum AmenContextualEffectType: String, Codable, CaseIterable {
    case amenPulse
    case prayerGlow
    case scriptureShimmer
    case gratitudeBloom
    case heartMorph
    case hiddenReactionRing
    case seasonalIconMorph
    case shareWithCareChip
    case saveForStudyChip
    case softFirework
    case none
}

enum AmenReactionKind: String, Codable, CaseIterable {
    case amen
    case praying
    case encouraged
    case wisdom
    case praiseGod
    case heart

    var title: String {
        switch self {
        case .amen: "Amen"
        case .praying: "Praying"
        case .encouraged: "Encouraged"
        case .wisdom: "Wisdom"
        case .praiseGod: "Praise God"
        case .heart: "Heart"
        }
    }

    var systemImage: String {
        switch self {
        case .amen: "hands.sparkles"
        case .praying: "sparkles"
        case .encouraged: "sun.max"
        case .wisdom: "book.closed"
        case .praiseGod: "hands.clap"
        case .heart: "heart.fill"
        }
    }
}

struct AmenContextualReactionResult: Identifiable, Codable, Equatable {
    let id: String
    let triggerType: AmenContextualTriggerType
    let effectType: AmenContextualEffectType
    let title: String
    let microcopy: String
    let priority: Int
    let durationMs: Int
    let shouldReturnToNormalState: Bool
}

struct AmenContextualReactionPresentation: Equatable {
    let result: AmenContextualReactionResult
    let morphSystemImage: String?

    init(result: AmenContextualReactionResult, morphSystemImage: String? = nil) {
        self.result = result
        self.morphSystemImage = morphSystemImage
    }
}
