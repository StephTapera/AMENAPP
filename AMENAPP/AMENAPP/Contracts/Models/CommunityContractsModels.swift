import Foundation

// MARK: - CommitmentObject

struct CommitmentObject: Codable, Identifiable {
    var id: String
    var parties: [String]               // [uid, uid]
    var kind: CommitmentKind
    var loopState: CommitmentLoopState
    var closeTheLoopAt: Date?
    var liveActivityEligible: Bool
    var createdAt: Date
    var createdBy: String
    // tier: C
}

enum CommitmentKind: String, Codable {
    case prayFor, checkIn, readWith, custom
}

enum CommitmentLoopState: String, Codable {
    case open, nudged, closed, lapsedGracefully
}

// MARK: - Table

struct Table: Codable, Identifiable {
    var id: String
    var name: String
    var memberLimit: Int                // 8...12 hard cap
    var members: [String]              // [uid]
    var anchor: TableAnchor
    var sunsetAt: Date                 // required — Tables always end
    var notebookId: String?
    var spaceId: String?
    var createdAt: Date
    var createdBy: String
    // tier: C
}

enum TableAnchor: Codable {
    case study(studyRef: String)
    case season(seasonRef: String)
    case topic(String)

    enum CodingKeys: String, CodingKey {
        case type, studyRef, seasonRef, topic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(String.self, forKey: .type)
        switch type_ {
        case "study":
            let ref = try container.decode(String.self, forKey: .studyRef)
            self = .study(studyRef: ref)
        case "season":
            let ref = try container.decode(String.self, forKey: .seasonRef)
            self = .season(seasonRef: ref)
        default:
            let topic = try container.decode(String.self, forKey: .topic)
            self = .topic(topic)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .study(let ref):
            try container.encode("study", forKey: .type)
            try container.encode(ref, forKey: .studyRef)
        case .season(let ref):
            try container.encode("season", forKey: .type)
            try container.encode(ref, forKey: .seasonRef)
        case .topic(let t):
            try container.encode("topic", forKey: .type)
            try container.encode(t, forKey: .topic)
        }
    }
}

// MARK: - PrayerChain + ChainLink

struct PrayerChain: Codable, Identifiable {
    var id: String
    var requestRef: String
    var links: [ChainLink]
    var wovenArtifactRef: String?
    var deliveredAt: Date?
    var createdAt: Date
    // tier: C
}

struct ChainLink: Codable, Identifiable {
    var id: String
    var uid: String
    var kind: ChainLinkKind
    var createdAt: Date
}

enum ChainLinkKind: Codable {
    case audio(mediaRef: String)    // ≤20s
    case verse(verseRef: String)
    case text(String)              // ≤280 chars

    enum CodingKeys: String, CodingKey {
        case type, mediaRef, verseRef, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(String.self, forKey: .type)
        switch type_ {
        case "audio":
            let ref = try container.decode(String.self, forKey: .mediaRef)
            self = .audio(mediaRef: ref)
        case "verse":
            let ref = try container.decode(String.self, forKey: .verseRef)
            self = .verse(verseRef: ref)
        default:
            let t = try container.decode(String.self, forKey: .text)
            self = .text(t)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .audio(let ref):
            try container.encode("audio", forKey: .type)
            try container.encode(ref, forKey: .mediaRef)
        case .verse(let ref):
            try container.encode("verse", forKey: .type)
            try container.encode(ref, forKey: .verseRef)
        case .text(let t):
            try container.encode("text", forKey: .type)
            try container.encode(t, forKey: .text)
        }
    }
}

// MARK: - Testimony

struct CreationTestimony: Codable, Identifiable {
    var id: String
    var authorUid: String
    var before: TestimonySection
    var encounter: TestimonySection
    var after: TestimonySection
    var c2paManifestRef: String         // required — publish blocks without this
    var visibility: TestimonyVisibility
    var createdAt: Date
    // tier: C; citationCount is INTERNAL ONLY — never stored on this struct
}

struct TestimonySection: Codable {
    var richText: String
    var mediaRef: String?
}

enum TestimonyVisibility: String, Codable {
    case connections, community
    case public_ = "public"
}

// MARK: - RemixLineage

struct RemixLineage: Codable, Identifiable {
    var id: String
    var rootArtifactId: String
    var parentArtifactId: String
    var childArtifactId: String
    var creatorUid: String
    var createdAt: Date
    // No counters surfaced — attribution chain only
}

// MARK: - FeedExplanation

struct FeedExplanation: Codable, Identifiable {
    var id: String
    var feedItemId: String
    var reasons: [FeedReasonCode]
    var humanReadable: String           // generated server-side, cached
    // tier: S
}

enum FeedReasonCode: String, Codable {
    case followedAuthor, sharedInterests, prayerContext, groupActivity,
         friendEngaged, trendingInCommunity, liturgicalSeason, bookmarkedTopic
}

// MARK: - LiturgicalThemeSeason + SeasonTheme

enum LiturgicalThemeSeason: String, Codable {
    case advent, christmas, epiphany, lent, holyWeek, easter, pentecost, ordinaryTime
}

struct SeasonTheme: Codable {
    var season: LiturgicalThemeSeason
    var glassTintHex: String            // WCAG AA required against all text styles
    var iconVariantKey: String
    var heyFeedToneKey: String
    var bereanToneKey: String
}

// MARK: - YouthModeProfile

struct YouthModeProfile: Codable {
    var uid: String
    var feedPacing: FeedPacing
    var dmPolicy: DMPolicy
    var bereanToneKey: String
    var guardianVisibility: GuardianVisibility
}

enum FeedPacing: String, Codable {
    case slow, standard
}

enum DMPolicy: String, Codable {
    case verifiedAdultsBlocked, standard
}

enum GuardianVisibility: String, Codable {
    case categoriesOnly
    case none_ = "none"
}
