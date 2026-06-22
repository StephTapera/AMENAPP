// DiscoveryContracts.swift
// AMEN — Connect Discovery Engine
// Wave 0 FROZEN: 2026-06-14
// Any change requires a contract-change note + re-freeze.
// Swift mirror of Backend/functions/src/discovery/contracts.ts — field names must match.

import Foundation

// MARK: - Server-driven feed

struct DiscoveryFeed: Codable {
    let generatedAt: Date
    let hero: [HeroCandidate]
    let shelves: [DiscoveryShelf]
    let calmCap: CalmCap
    let feedToken: String
}

struct CalmCap: Codable {
    let maxShelves: Int
    let maxItemsPerShelf: Int
    let infiniteScroll: Bool        // ALWAYS false in v1; client asserts this
    let sessionSoftLimitSeconds: Int

    static let v1Default = CalmCap(
        maxShelves: 8,
        maxItemsPerShelf: 12,
        infiniteScroll: false,
        sessionSoftLimitSeconds: 900
    )
}

struct HeroCandidate: Codable, Identifiable {
    let id: String
    let card: DiscoveryCard
    let backgroundHint: AdaptiveBackground
}

struct DiscoveryShelf: Codable, Identifiable {
    let id: String
    let kind: ShelfKind
    let title: String
    let subtitle: String?
    let style: ShelfStyle
    let items: [DiscoveryCard]
}

enum ShelfKind: String, Codable {
    case liveNow, recommended, nearbyChurches, eventsThisWeek,
         friendsActive, trendingDiscussions, newCommunities, prayerRooms
}

enum ShelfStyle: String, Codable {
    case carousel, featured, grid, mapBacked
}

// MARK: - Adaptive card (data-driven morphing)

struct DiscoveryCard: Codable, Identifiable {
    let id: String
    let type: DiscoveryCardType
    let title: String
    let subtitle: String?
    let payload: DiscoveryCardPayload
    let reason: WhyShown
    let safety: SafetyStamp           // REQUIRED — client refuses to render any card without this
    let glassTint: GlassTint
}

enum DiscoveryCardType: String, Codable {
    case bibleStudy, prayerRoom, church, event, discussion, space, audioRoom
}

// MARK: - Typed payload (discriminated union — no [String:Any] escape hatch)

enum DiscoveryCardPayload: Codable {
    case bibleStudy(DiscBibleStudyPayload)
    case prayerRoom(DiscPrayerRoomPayload)
    case church(DiscChurchPayload)
    case event(DiscEventPayload)
    case discussion(DiscDiscussionPayload)
    case space(DiscSpacePayload)
    case audioRoom(DiscAudioRoomPayload)

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(DiscoveryCardType.self, forKey: .type)
        switch type {
        case .bibleStudy:  self = .bibleStudy(try c.decode(DiscBibleStudyPayload.self, forKey: .data))
        case .prayerRoom:  self = .prayerRoom(try c.decode(DiscPrayerRoomPayload.self, forKey: .data))
        case .church:      self = .church(try c.decode(DiscChurchPayload.self, forKey: .data))
        case .event:       self = .event(try c.decode(DiscEventPayload.self, forKey: .data))
        case .discussion:  self = .discussion(try c.decode(DiscDiscussionPayload.self, forKey: .data))
        case .space:       self = .space(try c.decode(DiscSpacePayload.self, forKey: .data))
        case .audioRoom:   self = .audioRoom(try c.decode(DiscAudioRoomPayload.self, forKey: .data))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bibleStudy(let v):
            try c.encode(DiscoveryCardType.bibleStudy, forKey: .type)
            try c.encode(v, forKey: .data)
        case .prayerRoom(let v):
            try c.encode(DiscoveryCardType.prayerRoom, forKey: .type)
            try c.encode(v, forKey: .data)
        case .church(let v):
            try c.encode(DiscoveryCardType.church, forKey: .type)
            try c.encode(v, forKey: .data)
        case .event(let v):
            try c.encode(DiscoveryCardType.event, forKey: .type)
            try c.encode(v, forKey: .data)
        case .discussion(let v):
            try c.encode(DiscoveryCardType.discussion, forKey: .type)
            try c.encode(v, forKey: .data)
        case .space(let v):
            try c.encode(DiscoveryCardType.space, forKey: .type)
            try c.encode(v, forKey: .data)
        case .audioRoom(let v):
            try c.encode(DiscoveryCardType.audioRoom, forKey: .type)
            try c.encode(v, forKey: .data)
        }
    }
}

// MARK: - Concrete payload types

struct DiscBibleStudyPayload: Codable {
    let verseRef: String
    let passagePreview: String
    let readingProgress: Double?    // 0.0 – 1.0; nil if no prior engagement
}

struct DiscPrayerRoomPayload: Codable {
    let liveCount: Int
    let activeRequests: Int
    let speakerIds: [String]
}

struct DiscChurchPayload: Codable {
    let serviceTimes: [String]
    let denomination: String?
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double?
}

struct DiscEventPayload: Codable {
    let startsAt: Date
    let rsvpState: RSVPState
    let speakerIds: [String]
}

enum RSVPState: String, Codable {
    case none, going, maybe, notGoing
}

struct DiscDiscussionPayload: Codable {
    let replyCount: Int
    let lastActivityAt: Date
    let topicTags: [String]
}

struct DiscSpacePayload: Codable {
    let memberCount: Int
    let growth7d: Int
    let latestTopic: String?
}

struct DiscAudioRoomPayload: Codable {
    let liveCount: Int
    let speakerIds: [String]
    let waveformSeed: Int
}

// MARK: - Explainability (every card explains itself)

struct WhyShown: Codable {
    let kind: ReasonKind
    let detail: String
}

enum ReasonKind: String, Codable {
    case followedInterest, nearYou, friendJoined, trending, freshForYou, continueReading
}

// MARK: - Safety (required on every card — client refuses to render without this)

struct SafetyStamp: Codable {
    let clearedBy: String           // "GUARDIAN" | "AEGIS"
    let registryVersion: String
    let clearedAt: Date

    var isValid: Bool {
        clearedBy == "GUARDIAN" || clearedBy == "AEGIS"
    }
}

// MARK: - Adaptive background

enum AdaptiveBackground: String, Codable {
    case prayerWarm, parchment, worshipGradient, eventBrand, neutral

    var color: (r: Double, g: Double, b: Double) {
        switch self {
        case .prayerWarm:       return (0.85, 0.70, 0.50)
        case .parchment:        return (0.92, 0.88, 0.76)
        case .worshipGradient:  return (0.42, 0.28, 0.72)
        case .eventBrand:       return (0.18, 0.42, 0.72)
        case .neutral:          return (0.07, 0.04, 0.04)
        }
    }
}

struct GlassTint: Codable {
    let hex: String
    let intensity: Double           // 0…1; applied to .glassEffect(.regular.tint(...))
}

// MARK: - Search

struct ConnectDiscoverySearchResult: Codable {
    let suggested: [DiscoveryCard]
    let browseShelves: [DiscoveryShelf]
    let matches: [DiscoveryCard]
}

// MARK: - Feed decoder factory

extension JSONDecoder {
    static var discoveryDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }
}
