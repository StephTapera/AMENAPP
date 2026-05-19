import Foundation

struct AmenDiscoverFeedResponse {
    let sessionId: String
    let items: [AmenDiscoverItem]
    let nextCursor: String?
    let rankingContext: [String: String]
}

enum AmenDiscoverItemType: String, Codable, CaseIterable {
    case church
    case testimony
    case prayerSafePost
    case sermonClip
    case scriptureReflection
    case creator
    case localCommunity
    case selahMedia
    case churchNotesMoment
}

enum AmenDiscoverBadge: String, Codable, Hashable {
    case prayerSafe = "prayer_safe"
    case aiAssisted = "ai_assisted"
    case local = "local"
    case scriptureLinked = "scripture_linked"
    case bereanReviewed = "berean_reviewed"
    case testimonySafe = "testimony_safe"
}

struct AmenDiscoverMedia: Codable, Hashable {
    let thumbnailURL: String?
    let mediaURL: String?
    let durationSeconds: Int?
}

struct AmenDiscoverActor: Codable, Hashable {
    let id: String
    let name: String
    let avatarURL: String?
}

struct AmenDiscoverItem: Identifiable, Codable, Hashable {
    let id: String
    let sourceId: String
    let sourceType: String
    let type: AmenDiscoverItemType
    let title: String
    let subtitle: String?
    let caption: String?
    let media: AmenDiscoverMedia
    let author: AmenDiscoverActor?
    let church: AmenDiscoverActor?
    let topics: [String]
    let scriptureRefs: [String]
    let badges: Set<AmenDiscoverBadge>
    let reasonPreview: String?
    let createdAt: Date
}

enum AmenDiscoverFeedbackType: String, CaseIterable {
    case notForMe = "not_for_me"
    case tooIntense = "too_intense"
    case repetitive
    case theologicallyUnclear = "theologically_unclear"
    case hideCreator = "hide_creator"
    case hideTopic = "hide_topic"
    case report
    case reduceLocal = "reduce_local"
    case reduceAiAssisted = "reduce_ai_assisted"
}

struct AmenDiscoverReasonResponse {
    let itemId: String
    let reason: String
}
