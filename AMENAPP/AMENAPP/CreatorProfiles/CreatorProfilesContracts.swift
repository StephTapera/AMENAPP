// CreatorProfilesContracts.swift
// AMEN — Creator Profiles (ministry hubs: Apple Music Artist Page + Threads + Liquid Glass)
// Wave 0 FROZEN: 2026-06-18
// Swift mirror of Backend/functions/src/creatorProfiles/creatorProfileTypes.ts — field names MUST match.
// Any change requires a contract-change note + re-freeze in WAVE0_FREEZE.md.
//
// Namespacing: the `CreatorHub*` prefix avoids existing taken names — `CreatorProfile`
// (AMENAPP/CreatorProfile.swift, economic graph), `CommunityPost`
// (AMENAPP/Media/AmenMediaCommunityRoomView.swift), `PrayerRequest`
// (AMENAPP/AMENAPP/CommunityOS/Prayer/PrayerModels.swift).
//
// Reuse: the existing `CalmCap` (AMENAPP/AMENAPP/DiscoveryOS/DiscoveryContracts.swift)
// has identical fields to the wire's calm-cap shape and is used directly here.
//
// Wire conventions: timestamps are ISO-8601 strings → decode with `.creatorHubDecoder` (.iso8601).

import Foundation

// MARK: - Shared primitives

enum CreatorHubModerationStatus: String, Codable {
    case quarantined, pending, approved, rejected, hidden
}

enum CreatorHubAudienceTag: String, Codable {
    case general, youth, kids, mixed
}

struct CreatorHubMediaRef: Codable, Equatable {
    enum Kind: String, Codable { case image, video, audio }
    let kind: Kind
    let storagePath: String
    let aspectRatio: String?
    let durationSec: Double?
    let moderation: CreatorHubModerationStatus

    /// Client refuses to render media that MEDIA-GATE / moderation has not approved.
    var isServable: Bool { moderation == .approved }
}

struct CreatorHubLink: Codable, Equatable {
    enum Kind: String, Codable { case website, giving, youtube, podcast, social, app, other }
    let label: String
    let url: String
    let kind: Kind
}

struct CreatorHubGeo: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let locationName: String?
}

struct CreatorHubTicketing: Codable, Equatable {
    let isTicketed: Bool
    let priceCents: Int?
    let currency: String?
    let url: String?
}

// MARK: - Profile

enum CreatorHubBadge: String, Codable {
    case live, nextEvent, prayer, resource, verified
}

struct CreatorHubProfile: Codable, Identifiable {
    let id: String
    let displayName: String
    let handle: String
    let roleLabels: [String]
    let verified: Bool
    let heroMedia: CreatorHubMediaRef?
    let badges: [CreatorHubBadge]
    let links: [CreatorHubLink]
    let audienceTag: CreatorHubAudienceTag
    let calmCapProfile: CalmCap          // reuses existing CalmCap (DiscoveryContracts.swift)
}

// MARK: - Events

enum CreatorHubEventType: String, Codable {
    case sermon, bibleStudy, worshipNight, conference, `class`,
         prayerMeeting, livestream, revival, webinar, mentorship, smallGroup
}

enum CreatorHubEventStatus: String, Codable {
    case draft, scheduled, live, ended, canceled
}

struct CreatorHubEvent: Codable, Identifiable {
    let id: String
    let creatorId: String
    let type: CreatorHubEventType
    let title: String
    let startsAt: Date
    let timeZone: String
    let endsAt: Date?
    let geo: CreatorHubGeo?
    let registrationUrl: String?
    let ticketing: CreatorHubTicketing?
    let livestreamRef: String?
    let capacity: Int?
    let speakers: [String]
    let status: CreatorHubEventStatus
}

// MARK: - Teachings

struct CreatorHubTeaching: Codable, Identifiable {
    let id: String
    let creatorId: String
    let title: String
    let video: CreatorHubMediaRef?
    let audio: CreatorHubMediaRef?
    let transcriptRef: String?
    let notes: String?
    let outline: [String]
    let scriptureRefs: [String]
    let topics: [String]
    let series: String?
    let speakers: [String]
    let aiSummaryRef: String?
    let durationSec: Double
}

// MARK: - Resources

enum CreatorHubResourceKind: String, Codable {
    case pdf, book, worksheet, slides, devotional,
         readingPlan, studyGuide, course, link
}

struct CreatorHubResource: Codable, Identifiable {
    let id: String
    let creatorId: String
    let kind: CreatorHubResourceKind
    let title: String
    let fileRef: CreatorHubMediaRef?
    let externalUrl: String?
    let topics: [String]
}

// MARK: - Courses

enum CreatorHubProgressModel: String, Codable {
    case linear, freeform
}

struct CreatorHubLesson: Codable, Identifiable {
    let id: String
    let title: String
    let teachingRef: String?
    let durationSec: Double?
}

struct CreatorHubCourseModule: Codable, Identifiable {
    let id: String
    let title: String
    let lessons: [CreatorHubLesson]
}

struct CreatorHubCourse: Codable, Identifiable {
    let id: String
    let creatorId: String
    let title: String
    let modules: [CreatorHubCourseModule]
    let progressModel: CreatorHubProgressModel
}

// MARK: - Prayer board (moderated)

struct CreatorHubPrayerRequest: Codable, Identifiable {
    let id: String
    let creatorId: String
    let authorId: String
    let body: String
    let isPrivate: Bool
    let status: CreatorHubModerationStatus
    let prayedCount: Int
    let praiseReport: String?

    /// Public only when approved and not private. Client honours this; rules enforce it server-side.
    var isPubliclyVisible: Bool { status == .approved && !isPrivate }
}

// MARK: - Community (moderated)

enum CreatorHubCommunityKind: String, Codable {
    case question, testimony, studyNote, eventDiscussion
}

struct CreatorHubCommunityPost: Codable, Identifiable {
    let id: String
    let creatorId: String
    let authorId: String
    let kind: CreatorHubCommunityKind
    let body: String
    let parentRef: String?
    let status: CreatorHubModerationStatus

    var isPubliclyVisible: Bool { status == .approved }
}

// MARK: - Follow / subscription

enum CreatorHubFollowCategory: String, Codable {
    case teachings, events, prayer, resources, music, courses, livestreams
}

struct CreatorHubFollow: Codable {
    let userId: String
    let creatorId: String
    let categories: [CreatorHubFollowCategory]
}

// MARK: - Kingdom Metrics (derived, server-write only)

struct CreatorHubMetrics: Codable {
    let creatorId: String
    let peopleDiscipled: Int
    let prayersReceived: Int
    let prayersPrayed: Int
    let answeredReports: Int
    let plansCompleted: Int
    let notesCreated: Int
    let studySessions: Int
    let groupsLaunched: Int
    let resourcesDownloaded: Int
    let retentionSignal: Double
    let communityHealthSignal: Double
}

// MARK: - Assembly payload (single round trip)

enum CreatorHubModuleKind: String, Codable {
    case overview, events, teachings, resources, prayer, community, courses, askAI
}

/// Server-resolved hero state. Discriminated union { type, data } — mirrors DiscoveryCardPayload pattern.
enum CreatorHubHeroState: Codable {
    case live(event: CreatorHubEvent)
    case nextEvent(event: CreatorHubEvent)
    case latestTeaching(teaching: CreatorHubTeaching)
    case prayer(openRequests: Int)
    case resource(resource: CreatorHubResource)
    case idle

    private enum CodingKeys: String, CodingKey { case type, data }
    private enum Tag: String, Codable { case live, nextEvent, latestTeaching, prayer, resource, idle }

    private struct EventData: Codable { let event: CreatorHubEvent }
    private struct TeachingData: Codable { let teaching: CreatorHubTeaching }
    private struct ResourceData: Codable { let resource: CreatorHubResource }
    private struct PrayerData: Codable { let openRequests: Int }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .live:            self = .live(event: try c.decode(EventData.self, forKey: .data).event)
        case .nextEvent:       self = .nextEvent(event: try c.decode(EventData.self, forKey: .data).event)
        case .latestTeaching:  self = .latestTeaching(teaching: try c.decode(TeachingData.self, forKey: .data).teaching)
        case .prayer:          self = .prayer(openRequests: try c.decode(PrayerData.self, forKey: .data).openRequests)
        case .resource:        self = .resource(resource: try c.decode(ResourceData.self, forKey: .data).resource)
        case .idle:            self = .idle
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .live(let event):
            try c.encode(Tag.live, forKey: .type); try c.encode(EventData(event: event), forKey: .data)
        case .nextEvent(let event):
            try c.encode(Tag.nextEvent, forKey: .type); try c.encode(EventData(event: event), forKey: .data)
        case .latestTeaching(let teaching):
            try c.encode(Tag.latestTeaching, forKey: .type); try c.encode(TeachingData(teaching: teaching), forKey: .data)
        case .prayer(let openRequests):
            try c.encode(Tag.prayer, forKey: .type); try c.encode(PrayerData(openRequests: openRequests), forKey: .data)
        case .resource(let resource):
            try c.encode(Tag.resource, forKey: .type); try c.encode(ResourceData(resource: resource), forKey: .data)
        case .idle:
            try c.encode(Tag.idle, forKey: .type); try c.encode([String: String](), forKey: .data)
        }
    }
}

/// Server-selected featured module — "what matters right now". Discriminated union { type, data }.
enum CreatorHubFeaturedModule: Codable {
    case live(event: CreatorHubEvent)
    case nextEvent(event: CreatorHubEvent)
    case latestTeaching(teaching: CreatorHubTeaching)
    case newResource(resource: CreatorHubResource)
    case featuredCourse(course: CreatorHubCourse)

    private enum CodingKeys: String, CodingKey { case type, data }
    private enum Tag: String, Codable { case live, nextEvent, latestTeaching, newResource, featuredCourse }

    private struct EventData: Codable { let event: CreatorHubEvent }
    private struct TeachingData: Codable { let teaching: CreatorHubTeaching }
    private struct ResourceData: Codable { let resource: CreatorHubResource }
    private struct CourseData: Codable { let course: CreatorHubCourse }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .live:            self = .live(event: try c.decode(EventData.self, forKey: .data).event)
        case .nextEvent:       self = .nextEvent(event: try c.decode(EventData.self, forKey: .data).event)
        case .latestTeaching:  self = .latestTeaching(teaching: try c.decode(TeachingData.self, forKey: .data).teaching)
        case .newResource:     self = .newResource(resource: try c.decode(ResourceData.self, forKey: .data).resource)
        case .featuredCourse:  self = .featuredCourse(course: try c.decode(CourseData.self, forKey: .data).course)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .live(let event):
            try c.encode(Tag.live, forKey: .type); try c.encode(EventData(event: event), forKey: .data)
        case .nextEvent(let event):
            try c.encode(Tag.nextEvent, forKey: .type); try c.encode(EventData(event: event), forKey: .data)
        case .latestTeaching(let teaching):
            try c.encode(Tag.latestTeaching, forKey: .type); try c.encode(TeachingData(teaching: teaching), forKey: .data)
        case .newResource(let resource):
            try c.encode(Tag.newResource, forKey: .type); try c.encode(ResourceData(resource: resource), forKey: .data)
        case .featuredCourse(let course):
            try c.encode(Tag.featuredCourse, forKey: .type); try c.encode(CourseData(course: course), forKey: .data)
        }
    }
}

struct CreatorHubPillCounts: Codable {
    let events: Int
    let teachings: Int
    let resources: Int
    let prayer: Int
    let community: Int
    let courses: Int
}

struct CreatorHubFirstPages: Codable {
    let events: [CreatorHubEvent]
    let teachings: [CreatorHubTeaching]
    let resources: [CreatorHubResource]
    let prayer: [CreatorHubPrayerRequest]
    let community: [CreatorHubCommunityPost]
    let courses: [CreatorHubCourse]
    let cursors: [String: String]        // CreatorHubModuleKind.rawValue → next-page cursor
}

/// The single object returned by assembleCreatorProfile.
struct CreatorHubProfilePayload: Codable {
    let profile: CreatorHubProfile
    let heroState: CreatorHubHeroState
    let featuredModule: CreatorHubFeaturedModule?
    let pillCounts: CreatorHubPillCounts
    let firstPages: CreatorHubFirstPages
    let calmCap: CalmCap                  // reuses existing CalmCap
    let viewerFollows: Bool
    let assembledAt: Date
}

/// Cursor-paginated module page (pageCreatorModule).
struct CreatorHubModulePage<T: Codable>: Codable {
    let module: CreatorHubModuleKind
    let items: [T]
    let nextCursor: String?
}

// MARK: - AI Creator Assistant (grounded, cited, refuse-on-unsupported)

enum CreatorHubCitationSource: String, Codable {
    case teaching, resource, event, course
}

struct CreatorHubCitation: Codable, Identifiable {
    var id: String { "\(sourceType.rawValue):\(sourceId):\(timestampSec.map { String($0) } ?? path ?? "")" }
    let sourceType: CreatorHubCitationSource
    let sourceId: String
    let path: String?
    let timestampSec: Double?
}

struct CreatorHubAssistantQuery: Codable {
    let creatorId: String
    let query: String
    let sessionId: String?
}

struct CreatorHubAssistantAnswer: Codable {
    let answer: String
    let citations: [CreatorHubCitation]   // required whenever refused == false
    let refused: Bool
    let refusalReason: String?
}

// MARK: - Feature-flag manifest — ALL DEFAULT OFF

/// Remote Config keys. Mirrors CREATOR_HUB_FLAGS in creatorProfileTypes.ts.
/// Wiring into AMENFeatureFlags.swift + remoteconfig.template.json is a later (human) step — see WAVE0_FREEZE.md.
enum CreatorHubFlags {
    static let profilesEnabled        = "creator_profiles_enabled"
    static let eventsEnabled          = "creator_events_enabled"
    static let teachingSearchEnabled  = "creator_teaching_search_enabled"
    static let resourcesEnabled       = "creator_resources_enabled"
    static let prayerBoardEnabled     = "creator_prayer_board_enabled"
    static let communityEnabled       = "creator_community_enabled"
    static let aiAssistantEnabled     = "creator_ai_assistant_enabled"
    static let liveModeEnabled        = "creator_live_mode_enabled"
    static let supportDonationsEnabled = "creator_support_donations_enabled"
    static let voiceConsumptionEnabled = "creator_voice_consumption_enabled"

    /// All Creator-Hub flag keys; every one defaults OFF until human flag-flip.
    static let allKeys: [String] = [
        profilesEnabled, eventsEnabled, teachingSearchEnabled, resourcesEnabled,
        prayerBoardEnabled, communityEnabled, aiAssistantEnabled, liveModeEnabled,
        supportDonationsEnabled, voiceConsumptionEnabled,
    ]
}

// MARK: - Decoder factory (matches discoveryDecoder convention)

extension JSONDecoder {
    static var creatorHubDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }
}
