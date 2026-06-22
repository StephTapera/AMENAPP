import Foundation

typealias SocialV2Identifier = String

enum SocialV2PrivacyScope: String, CaseIterable, Identifiable, Codable, Hashable {
    case `public`
    case followers
    case friends
    case `private`
    case custom

    var id: String { rawValue }
}

enum SocialV2LocationScope: String, CaseIterable, Identifiable, Codable, Hashable {
    case approximate
    case city
    case region
    case hidden

    var id: String { rawValue }
}

enum SocialV2TrustSignal: String, CaseIterable, Identifiable, Codable, Hashable {
    case verified
    case contributor
    case moderator
    case creator
    case volunteer

    var id: String { rawValue }
}

enum SocialV2ModerationStatus: String, Codable, Hashable {
    case pending
    case approved
    case held
    case removed
}

struct SocialV2ModerationDecision: Identifiable, Codable, Hashable {
    let id: SocialV2Identifier
    let status: SocialV2ModerationStatus
    let policyReference: String
    let explanation: String
    let decidedAt: Date

    var isReadable: Bool {
        status == .approved
    }
}

enum SocialV2SpaceKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case `public`
    case `private`
    case local
    case organization
    case church
    case school
    case professional

    var id: String { rawValue }
}

struct SocialV2Space: Identifiable, Codable, Hashable {
    let id: SocialV2Identifier
    let name: String
    let summary: String
    let kind: SocialV2SpaceKind
    let locationScope: SocialV2LocationScope
    let trustSignals: [SocialV2TrustSignal]
}

enum SocialV2FeedKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case following
    case forYou
    case communities
    case local
    case learning
    case trending

    var id: String { rawValue }
}

enum SocialV2SearchEntity: String, CaseIterable, Identifiable, Codable, Hashable {
    case posts
    case videos
    case spaces
    case events
    case resources
    case churches
    case podcasts
    case people
    case messages
    case prayers
    case notes

    var id: String { rawValue }
}

struct SocialV2MessageThread: Identifiable, Codable, Hashable {
    let id: SocialV2Identifier
    let title: String
    let participantIDs: [SocialV2Identifier]
    let lastModerationDecision: SocialV2ModerationDecision?
    let updatedAt: Date

    var canDeliverLatestMessage: Bool {
        lastModerationDecision?.isReadable == true
    }
}

struct SocialV2AIPrivacyToggles: Codable, Hashable {
    var recommendationsEnabled: Bool
    var personalizationEnabled: Bool
    var assistantsEnabled: Bool
    var searchEnabled: Bool

    static let allOff = SocialV2AIPrivacyToggles(
        recommendationsEnabled: false,
        personalizationEnabled: false,
        assistantsEnabled: false,
        searchEnabled: false
    )
}
