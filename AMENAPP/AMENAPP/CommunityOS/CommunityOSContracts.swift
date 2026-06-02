// CommunityOSContracts.swift
// AMEN App — Community Around Content OS
//
// FROZEN — Phase 0 shared contracts.
// Do not edit without Lead Orchestrator authorization and rebroadcast to all dependent agents.
// Frozen on 2026-06-02.
//
// Import contract: every CommunityOS agent imports ONLY this file for shared types.
// Do NOT redeclare anything defined here.

import Foundation
import FirebaseFirestore

let CommunityOSContractsVersion = "2026-06-02-v1"

// MARK: - ContentObjectKind

/// The type of content at the center of a community node.
enum ContentObjectKind: String, CaseIterable, Codable {
    case song            = "song"
    case podcast         = "podcast"
    case book            = "book"
    case bibleVerse      = "bible_verse"
    case sermon          = "sermon"
    case video           = "video"
    case course          = "course"
    case event           = "event"
    case prayerRequest   = "prayer_request"
    case article         = "article"
    case testimony       = "testimony"
    case userPost        = "user_post"

    var displayName: String {
        switch self {
        case .song:          return "Song"
        case .podcast:       return "Podcast"
        case .book:          return "Book"
        case .bibleVerse:    return "Bible Verse"
        case .sermon:        return "Sermon"
        case .video:         return "Video"
        case .course:        return "Course"
        case .event:         return "Event"
        case .prayerRequest: return "Prayer Request"
        case .article:       return "Article"
        case .testimony:     return "Testimony"
        case .userPost:      return "Post"
        }
    }

    var systemImage: String {
        switch self {
        case .song:          return "music.note"
        case .podcast:       return "mic.fill"
        case .book:          return "book.closed.fill"
        case .bibleVerse:    return "book.fill"
        case .sermon:        return "waveform.and.person.filled"
        case .video:         return "play.rectangle.fill"
        case .course:        return "graduationcap.fill"
        case .event:         return "calendar"
        case .prayerRequest: return "hands.sparkles.fill"
        case .article:       return "doc.text.fill"
        case .testimony:     return "star.bubble.fill"
        case .userPost:      return "bubble.left.and.bubble.right.fill"
        }
    }

    /// The community layers that make sense for each content kind.
    var defaultCommunityLayers: [CommunityLayer] {
        switch self {
        case .song:
            return [.worship, .discussion, .reflection]
        case .podcast:
            return [.discussion, .study, .reflection]
        case .book:
            return [.study, .discussion, .reflection, .mentorship]
        case .bibleVerse:
            return [.study, .prayer, .reflection, .discussion]
        case .sermon:
            return [.discussion, .study, .reflection, .prayer]
        case .video:
            return [.discussion, .reflection]
        case .course:
            return [.study, .mentorship, .discussion, .realWorld]
        case .event:
            return [.realWorld, .prayer, .discussion]
        case .prayerRequest:
            return [.prayer, .mentorship]
        case .article:
            return [.discussion, .reflection, .study]
        case .testimony:
            return [.discussion, .prayer, .reflection]
        case .userPost:
            return [.discussion, .reflection, .prayer]
        }
    }
}

// MARK: - ContentSource

/// Where a piece of content originates from.
enum ContentSource: String, Codable {
    case spotify       = "spotify"
    case appleMusic    = "apple_music"
    case youtubeMusic  = "youtube_music"
    case youtube       = "youtube"
    case podcast       = "podcast"
    case amazonBook    = "amazon_book"
    case kindle        = "kindle"
    case sermonLink    = "sermon_link"
    case bibleRef      = "bible_ref"
    case churchEvent   = "church_event"
    case amenPost      = "amen_post"
    case unknown       = "unknown"

    var displayName: String {
        switch self {
        case .spotify:      return "Spotify"
        case .appleMusic:   return "Apple Music"
        case .youtubeMusic: return "YouTube Music"
        case .youtube:      return "YouTube"
        case .podcast:      return "Podcast"
        case .amazonBook:   return "Amazon Books"
        case .kindle:       return "Kindle"
        case .sermonLink:   return "Sermon"
        case .bibleRef:     return "Bible"
        case .churchEvent:  return "Church Event"
        case .amenPost:     return "AMEN Post"
        case .unknown:      return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .spotify:      return "music.note.list"
        case .appleMusic:   return "music.note"
        case .youtubeMusic: return "music.quarternote.3"
        case .youtube:      return "play.circle.fill"
        case .podcast:      return "mic.circle.fill"
        case .amazonBook:   return "cart.fill"
        case .kindle:       return "books.vertical.fill"
        case .sermonLink:   return "link.circle.fill"
        case .bibleRef:     return "book.closed.circle.fill"
        case .churchEvent:  return "building.columns.fill"
        case .amenPost:     return "bubble.left.fill"
        case .unknown:      return "questionmark.circle"
        }
    }
}

// MARK: - PurityRating

/// Community-sourced purity assessment for content.
enum PurityRating: String, Codable, Comparable {
    case familySafe      = "family_safe"
    case someConcerns    = "some_concerns"
    case notRecommended  = "not_recommended"
    case unreviewed      = "unreviewed"

    private var sortOrder: Int {
        switch self {
        case .familySafe:     return 0
        case .someConcerns:   return 1
        case .notRecommended: return 2
        case .unreviewed:     return 3
        }
    }

    static func < (lhs: PurityRating, rhs: PurityRating) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var label: String {
        switch self {
        case .familySafe:     return "Family Safe"
        case .someConcerns:   return "Some Concerns"
        case .notRecommended: return "Not Recommended"
        case .unreviewed:     return "Unreviewed"
        }
    }

    var systemImage: String {
        switch self {
        case .familySafe:     return "checkmark.seal.fill"
        case .someConcerns:   return "exclamationmark.triangle.fill"
        case .notRecommended: return "xmark.seal.fill"
        case .unreviewed:     return "questionmark.circle.fill"
        }
    }

    /// Semantic color name — map to actual Color in the view layer.
    var colorName: String {
        switch self {
        case .familySafe:     return "green"
        case .someConcerns:   return "yellow"
        case .notRecommended: return "red"
        case .unreviewed:     return "gray"
        }
    }
}

// MARK: - CommunityLayer

/// The kind of spiritual activity happening inside a community node.
enum CommunityLayer: String, CaseIterable, Codable {
    case discussion  = "discussion"
    case reflection  = "reflection"
    case prayer      = "prayer"
    case study       = "study"
    case mentorship  = "mentorship"
    case realWorld   = "real_world"
    case worship     = "worship"

    var displayName: String {
        switch self {
        case .discussion: return "Discussion"
        case .reflection: return "Reflection"
        case .prayer:     return "Prayer"
        case .study:      return "Study"
        case .mentorship: return "Mentorship"
        case .realWorld:  return "Real-World"
        case .worship:    return "Worship"
        }
    }

    var systemImage: String {
        switch self {
        case .discussion: return "bubble.left.and.bubble.right.fill"
        case .reflection: return "sparkles"
        case .prayer:     return "hands.sparkles.fill"
        case .study:      return "text.book.closed.fill"
        case .mentorship: return "person.2.fill"
        case .realWorld:  return "map.fill"
        case .worship:    return "music.note"
        }
    }

    /// Seed prompt for the layer — drives Berean and UI copy.
    var prompt: String {
        switch self {
        case .discussion:
            return "What are your thoughts on this?"
        case .reflection:
            return "How has this impacted your faith journey?"
        case .prayer:
            return "How can we pray together about this?"
        case .study:
            return "What does the Bible say about this?"
        case .mentorship:
            return "Who is guiding you through this?"
        case .realWorld:
            return "How is this changing what you do day-to-day?"
        case .worship:
            return "How does this draw you closer to God in worship?"
        }
    }
}

// MARK: - ContentObject

/// A piece of external or internal content that can have community built around it.
struct ContentObject: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var kind: ContentObjectKind
    var source: ContentSource
    var title: String
    var subtitle: String?
    var thumbnailURL: String?
    var contentURL: String?
    var rawURL: String
    /// Flexible key/value bag: artist, author, duration, isbn, channelName, publishedDate, etc.
    var metadata: [String: String]
    /// Normalized engagement score 0.0–1.0 derived by the server.
    var communityScore: Double
    var discussionCount: Int
    var prayerCount: Int
    var testimonyCount: Int
    var spaceCount: Int
    var purityRating: PurityRating
    var themes: [String]
    /// Scripture references attached to this content, e.g. "John 3:16".
    var linkedVerseRefs: [String]
    var createdAt: Date
    var updatedAt: Date

    // MARK: Computed

    var hasCommunity: Bool {
        totalEngagement > 0
    }

    var totalEngagement: Int {
        discussionCount + prayerCount + testimonyCount + spaceCount
    }

    // MARK: Init

    init(
        id: String = UUID().uuidString,
        kind: ContentObjectKind,
        source: ContentSource,
        title: String,
        subtitle: String? = nil,
        thumbnailURL: String? = nil,
        contentURL: String? = nil,
        rawURL: String,
        metadata: [String: String] = [:],
        communityScore: Double = 0.0,
        discussionCount: Int = 0,
        prayerCount: Int = 0,
        testimonyCount: Int = 0,
        spaceCount: Int = 0,
        purityRating: PurityRating = .unreviewed,
        themes: [String] = [],
        linkedVerseRefs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.thumbnailURL = thumbnailURL
        self.contentURL = contentURL
        self.rawURL = rawURL
        self.metadata = metadata
        self.communityScore = communityScore
        self.discussionCount = discussionCount
        self.prayerCount = prayerCount
        self.testimonyCount = testimonyCount
        self.spaceCount = spaceCount
        self.purityRating = purityRating
        self.themes = themes
        self.linkedVerseRefs = linkedVerseRefs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Convenience factory from a Firestore document data dictionary.
    init?(from data: [String: Any]) {
        guard
            let id = data["id"] as? String,
            let kindRaw = data["kind"] as? String,
            let kind = ContentObjectKind(rawValue: kindRaw),
            let sourceRaw = data["source"] as? String,
            let source = ContentSource(rawValue: sourceRaw),
            let title = data["title"] as? String,
            let rawURL = data["rawURL"] as? String
        else { return nil }

        self.id = id
        self.kind = kind
        self.source = source
        self.title = title
        self.subtitle = data["subtitle"] as? String
        self.thumbnailURL = data["thumbnailURL"] as? String
        self.contentURL = data["contentURL"] as? String
        self.rawURL = rawURL
        self.metadata = data["metadata"] as? [String: String] ?? [:]
        self.communityScore = data["communityScore"] as? Double ?? 0.0
        self.discussionCount = data["discussionCount"] as? Int ?? 0
        self.prayerCount = data["prayerCount"] as? Int ?? 0
        self.testimonyCount = data["testimonyCount"] as? Int ?? 0
        self.spaceCount = data["spaceCount"] as? Int ?? 0
        self.purityRating = (data["purityRating"] as? String).flatMap(PurityRating.init) ?? .unreviewed
        self.themes = data["themes"] as? [String] ?? []
        self.linkedVerseRefs = data["linkedVerseRefs"] as? [String] ?? []
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
    }

    // MARK: Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CommunityNode

/// The aggregate community that has formed around a ContentObject.
struct CommunityNode: Identifiable, Codable, Equatable {
    let id: String
    var contentObjectId: String
    var contentKind: ContentObjectKind
    var name: String
    var memberCount: Int
    var discussionCount: Int
    var prayerCount: Int
    var testimonyCount: Int
    var churchCount: Int
    var eventCount: Int
    var isAutoGenerated: Bool
    var activeLayers: [CommunityLayer]
    var createdAt: Date
    var lastActiveAt: Date

    // MARK: Computed

    /// Weighted score (0.0–1.0) reflecting how vibrant this community is.
    var healthScore: Double {
        guard memberCount > 0 else { return 0 }
        let rawScore = (Double(discussionCount) * 0.3)
            + (Double(prayerCount) * 0.25)
            + (Double(testimonyCount) * 0.2)
            + (Double(eventCount) * 0.15)
            + (Double(churchCount) * 0.1)
        let normalized = rawScore / max(Double(memberCount), 1.0)
        return min(normalized, 1.0)
    }

    /// A node is active if it had activity within the last 30 days.
    var isActive: Bool {
        Date().timeIntervalSince(lastActiveAt) < 30 * 24 * 3600
    }

    // MARK: Init

    init(
        id: String = UUID().uuidString,
        contentObjectId: String,
        contentKind: ContentObjectKind,
        name: String,
        memberCount: Int = 0,
        discussionCount: Int = 0,
        prayerCount: Int = 0,
        testimonyCount: Int = 0,
        churchCount: Int = 0,
        eventCount: Int = 0,
        isAutoGenerated: Bool = false,
        activeLayers: [CommunityLayer] = [],
        createdAt: Date = Date(),
        lastActiveAt: Date = Date()
    ) {
        self.id = id
        self.contentObjectId = contentObjectId
        self.contentKind = contentKind
        self.name = name
        self.memberCount = memberCount
        self.discussionCount = discussionCount
        self.prayerCount = prayerCount
        self.testimonyCount = testimonyCount
        self.churchCount = churchCount
        self.eventCount = eventCount
        self.isAutoGenerated = isAutoGenerated
        self.activeLayers = activeLayers
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
    }

    /// Convenience factory from a Firestore document data dictionary.
    init?(from data: [String: Any]) {
        guard
            let id = data["id"] as? String,
            let contentObjectId = data["contentObjectId"] as? String,
            let kindRaw = data["contentKind"] as? String,
            let contentKind = ContentObjectKind(rawValue: kindRaw),
            let name = data["name"] as? String
        else { return nil }

        self.id = id
        self.contentObjectId = contentObjectId
        self.contentKind = contentKind
        self.name = name
        self.memberCount = data["memberCount"] as? Int ?? 0
        self.discussionCount = data["discussionCount"] as? Int ?? 0
        self.prayerCount = data["prayerCount"] as? Int ?? 0
        self.testimonyCount = data["testimonyCount"] as? Int ?? 0
        self.churchCount = data["churchCount"] as? Int ?? 0
        self.eventCount = data["eventCount"] as? Int ?? 0
        self.isAutoGenerated = data["isAutoGenerated"] as? Bool ?? false
        self.activeLayers = (data["activeLayers"] as? [String] ?? [])
            .compactMap { CommunityLayer(rawValue: $0) }
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.lastActiveAt = (data["lastActiveAt"] as? Timestamp)?.dateValue() ?? Date()
    }
}

// MARK: - CommunityAffinityTopic

/// Spiritual interest dimensions used to personalize community discovery.
enum CommunityAffinityTopic: String, CaseIterable, Codable {
    case worship       = "worship"
    case prayer        = "prayer"
    case leadership    = "leadership"
    case discipleship  = "discipleship"
    case recovery      = "recovery"
    case marriage      = "marriage"
    case fatherhood    = "fatherhood"
    case motherhood    = "motherhood"
    case youth         = "youth"
    case missions      = "missions"
    case apologetics   = "apologetics"
    case theology      = "theology"

    var displayName: String {
        switch self {
        case .worship:      return "Worship"
        case .prayer:       return "Prayer"
        case .leadership:   return "Leadership"
        case .discipleship: return "Discipleship"
        case .recovery:     return "Recovery"
        case .marriage:     return "Marriage"
        case .fatherhood:   return "Fatherhood"
        case .motherhood:   return "Motherhood"
        case .youth:        return "Youth"
        case .missions:     return "Missions"
        case .apologetics:  return "Apologetics"
        case .theology:     return "Theology"
        }
    }
}

// MARK: - CommunityAffinityScore

/// A single user–topic affinity signal.
struct CommunityAffinityScore: Codable, Equatable {
    var userId: String
    var topic: CommunityAffinityTopic
    /// Normalized score 0.0–1.0 derived by the server from behavioural signals.
    var score: Double
    /// Human-readable signal keys that contributed, e.g. "saved_sermon_leadership".
    var signals: [String]
    var updatedAt: Date

    init(
        userId: String,
        topic: CommunityAffinityTopic,
        score: Double = 0.0,
        signals: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.topic = topic
        self.score = score
        self.signals = signals
        self.updatedAt = updatedAt
    }
}

// MARK: - CommunityDNAProfile

/// The full spiritual-interest fingerprint for a user.
struct CommunityDNAProfile: Codable, Equatable {
    var userId: String
    var worshipAffinity: Double
    var bibleAffinity: Double
    var prayerAffinity: Double
    var teachingAffinity: Double
    var recoveryAffinity: Double
    var leadershipAffinity: Double
    /// Top-scored affinity topics, sorted descending by score.
    var topAffinities: [CommunityAffinityScore]
    var updatedAt: Date

    // MARK: Computed

    /// Returns the highest-scoring affinity topic, or nil if no affinities have been computed.
    var primaryAffinity: CommunityAffinityTopic? {
        topAffinities.sorted { $0.score > $1.score }.first?.topic
    }

    // MARK: Init

    init(
        userId: String,
        worshipAffinity: Double = 0.0,
        bibleAffinity: Double = 0.0,
        prayerAffinity: Double = 0.0,
        teachingAffinity: Double = 0.0,
        recoveryAffinity: Double = 0.0,
        leadershipAffinity: Double = 0.0,
        topAffinities: [CommunityAffinityScore] = [],
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.worshipAffinity = worshipAffinity
        self.bibleAffinity = bibleAffinity
        self.prayerAffinity = prayerAffinity
        self.teachingAffinity = teachingAffinity
        self.recoveryAffinity = recoveryAffinity
        self.leadershipAffinity = leadershipAffinity
        self.topAffinities = topAffinities
        self.updatedAt = updatedAt
    }
}

// MARK: - CommunityEmergenceThresholds

/// Server-side thresholds that govern when a CommunityNode is auto-created or promoted.
/// These are intentionally conservative and designed to be raised over time.
struct CommunityEmergenceThresholds {
    static let minDiscussionsForAutoSpace: Int = 100
    static let minSavesForAutoSpace: Int = 1_000
    static let minSharesForAutoSpace: Int = 500
    static let minEngagementScoreForAutoSpace: Double = 0.65
    static let minMembersForEventSuggestion: Int = 50_000
    static let minMembersForChurchPartnership: Int = 10_000

    private init() {}
}

// MARK: - CommunityHealthTier

/// Categorical health level for a CommunityNode.
enum CommunityHealthTier: String, Codable {
    case thriving  = "thriving"
    case healthy   = "healthy"
    case growing   = "growing"
    case dormant   = "dormant"
    case atrisk    = "at_risk"

    var displayName: String {
        switch self {
        case .thriving: return "Thriving"
        case .healthy:  return "Healthy"
        case .growing:  return "Growing"
        case .dormant:  return "Dormant"
        case .atrisk:   return "At Risk"
        }
    }

    var systemImage: String {
        switch self {
        case .thriving: return "flame.fill"
        case .healthy:  return "heart.fill"
        case .growing:  return "arrow.up.heart.fill"
        case .dormant:  return "moon.zzz.fill"
        case .atrisk:   return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - CommunityHealthSignals

/// A snapshot of health-signal scores for a CommunityNode.
/// The `overallHealthScore` is a server-computed weighted average.
struct CommunityHealthSignals: Identifiable, Codable {
    /// Convenience: id == communityId for easy Firestore @DocumentID mapping.
    var id: String { communityId }
    var communityId: String
    var prayerActivityScore: Double
    var discussionQualityScore: Double
    var responseRateScore: Double
    var mentorshipEngagementScore: Double
    var eventAttendanceScore: Double
    var studyCompletionScore: Double
    var healthTier: CommunityHealthTier
    var updatedAt: Date

    // MARK: Computed

    /// Weighted average across all signal dimensions (0.0–1.0).
    var overallHealthScore: Double {
        let weights: [(Double, Double)] = [
            (prayerActivityScore, 0.20),
            (discussionQualityScore, 0.20),
            (responseRateScore, 0.15),
            (mentorshipEngagementScore, 0.20),
            (eventAttendanceScore, 0.10),
            (studyCompletionScore, 0.15)
        ]
        return weights.reduce(0.0) { $0 + ($1.0 * $1.1) }
    }

    // MARK: Init

    init(
        communityId: String,
        prayerActivityScore: Double = 0.0,
        discussionQualityScore: Double = 0.0,
        responseRateScore: Double = 0.0,
        mentorshipEngagementScore: Double = 0.0,
        eventAttendanceScore: Double = 0.0,
        studyCompletionScore: Double = 0.0,
        healthTier: CommunityHealthTier = .dormant,
        updatedAt: Date = Date()
    ) {
        self.communityId = communityId
        self.prayerActivityScore = prayerActivityScore
        self.discussionQualityScore = discussionQualityScore
        self.responseRateScore = responseRateScore
        self.mentorshipEngagementScore = mentorshipEngagementScore
        self.eventAttendanceScore = eventAttendanceScore
        self.studyCompletionScore = studyCompletionScore
        self.healthTier = healthTier
        self.updatedAt = updatedAt
    }

    // MARK: Codable — manual impl to exclude computed `id`

    enum CodingKeys: String, CodingKey {
        case communityId
        case prayerActivityScore
        case discussionQualityScore
        case responseRateScore
        case mentorshipEngagementScore
        case eventAttendanceScore
        case studyCompletionScore
        case healthTier
        case updatedAt
    }
}

// MARK: - ContentEngagementEventType

/// The kinds of interactions a user can have with a ContentObject.
enum ContentEngagementEventType: String, CaseIterable, Codable {
    case viewed          = "viewed"
    case saved           = "saved"
    case shared          = "shared"
    case discussed       = "discussed"
    case prayed          = "prayed"
    case testified       = "testified"
    case studyStarted    = "study_started"
    case studyCompleted  = "study_completed"
    case spaceJoined     = "space_joined"
    case spaceCreated    = "space_created"
    case eventAttended   = "event_attended"
}

// MARK: - ContentEngagementEvent

/// An immutable record of a single user interaction with a ContentObject.
/// Written by the client; counts are aggregated server-side.
struct ContentEngagementEvent: Codable {
    let id: String
    var contentObjectId: String
    var userId: String
    var eventType: ContentEngagementEventType
    var occurredAt: Date

    init(
        id: String = UUID().uuidString,
        contentObjectId: String,
        userId: String,
        eventType: ContentEngagementEventType,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.contentObjectId = contentObjectId
        self.userId = userId
        self.eventType = eventType
        self.occurredAt = occurredAt
    }
}
