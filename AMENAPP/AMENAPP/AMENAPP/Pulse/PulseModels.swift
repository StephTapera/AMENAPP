//
//  PulseModels.swift
//  AMEN — Amen Pulse (Personalized Daily Surface)
//
//  FROZEN CONTRACTS — Phase 1. Mirrors Backend pulse.contracts (TypeScript).
//  Bind to these; do not fork. Amen Pulse is a *bounded* daily surface, not a feed:
//    • hard card cap (config-driven, default 7) + a visible terminus card
//    • no streaks, no velocity/popularity framing, no guilt strings
//    • weather / location / proximity cards are minor-unsafe (resolved server-side)
//    • PulseScore selects a finite set — it is NEVER displayed
//
//  These types are Codable for on-device caching. Firestore decode is performed
//  manually in PulseService (Timestamps), mirroring the BereanPulse pattern.
//

import Foundation

// MARK: - Card kind

/// The fixed set of card kinds Amen Pulse can render. `terminus` is appended
/// client-side as the visible "that's everything for today" end of the surface.
public enum PulseCardKind: String, Codable, CaseIterable, Hashable, Sendable {
    case dailyBriefHero  = "daily_brief_hero"
    case scriptureHero   = "scripture_hero"
    case prayerFollowup  = "prayer_followup"
    case occasion        = "occasion"
    case churchEvent     = "church_event"
    case spaceActivity   = "space_activity"
    case sermon          = "sermon"
    case whatsNew        = "whats_new"
    case terminus        = "terminus"
}

// MARK: - Hero

public enum PulseScrim: String, Codable, Hashable, Sendable {
    case light
    case dark
}

/// Visual style key for a card's hero. When `imageUrl` is nil the surface renders
/// a CSS-grade gradient identified by `style` (see PulseHeroStyle in the UI layer).
public struct PulseHero: Codable, Hashable, Sendable {
    public var imageUrl: String?
    public var videoUrl: String?
    public var scrim: PulseScrim
    /// Gradient catalog key: "brief" | "whatsnew" | "prayer" | "event" | "verse" | "occasion" | "space".
    public var style: String

    public init(imageUrl: String? = nil, videoUrl: String? = nil, scrim: PulseScrim, style: String) {
        self.imageUrl = imageUrl
        self.videoUrl = videoUrl
        self.scrim = scrim
        self.style = style
    }
}

// MARK: - Action

/// Exactly one primary action per card. The verb that converts attention into action.
public enum PulseActionKind: String, Codable, Hashable, Sendable {
    case openBrief
    case pray
    case checkIn
    case rsvp
    case read
    case sendLove
    case openSpace
    case openSermon
    case tryFeature
    case seeWhatsNew
    case none
}

public struct PulseAction: Codable, Hashable, Sendable {
    public var kind: PulseActionKind
    public var label: String
    /// Optional in-app deeplink the action routes to (e.g. "amen://prayer/{id}").
    public var deeplink: String?
    public var payload: [String: String]

    public init(kind: PulseActionKind, label: String, deeplink: String? = nil, payload: [String: String] = [:]) {
        self.kind = kind
        self.label = label
        self.deeplink = deeplink
        self.payload = payload
    }

    public static let none = PulseAction(kind: .none, label: "")
}

// MARK: - Score (selection only — never displayed)

/// Composite scoring used SERVER-SIDE to select the finite card set. The client
/// never ranks and never renders these numbers.
public struct PulseScore: Codable, Hashable, Sendable {
    public var relationship: Double
    public var spiritual: Double
    public var community: Double
    public var urgency: Double
    public var interest: Double
    public var composite: Double

    public init(relationship: Double = 0, spiritual: Double = 0, community: Double = 0,
                urgency: Double = 0, interest: Double = 0, composite: Double = 0) {
        self.relationship = relationship
        self.spiritual = spiritual
        self.community = community
        self.urgency = urgency
        self.interest = interest
        self.composite = composite
    }
}

// MARK: - Supporting content

/// An icon + text fact line (Daily Brief fact rows, church event meta rows).
public struct PulseFact: Codable, Hashable, Identifiable, Sendable {
    public var id: String { systemImage + "|" + text }
    public var systemImage: String
    public var text: String

    public init(systemImage: String, text: String) {
        self.systemImage = systemImage
        self.text = text
    }
}

/// One section of the Daily Brief, available at one or more durations.
public struct PulseBriefSection: Codable, Hashable, Identifiable, Sendable {
    public var id: String { heading }
    public var heading: String
    public var body: String
    /// Minimum duration at which this section appears (30s shows fewer, 10m shows all).
    public var minimumDuration: PulseBriefDuration

    public init(heading: String, body: String, minimumDuration: PulseBriefDuration = .threeMin) {
        self.heading = heading
        self.body = body
        self.minimumDuration = minimumDuration
    }
}

public enum PulseBriefDuration: String, Codable, CaseIterable, Hashable, Sendable {
    case thirtySec = "30s"
    case threeMin  = "3m"
    case tenMin    = "10m"

    /// Rank for "section appears at or above this duration" comparisons.
    public var rank: Int {
        switch self {
        case .thirtySec: return 0
        case .threeMin:  return 1
        case .tenMin:    return 2
        }
    }
}

// MARK: - Card

public struct PulseCard: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: PulseCardKind
    /// Selection only — never displayed.
    public var score: PulseScore
    public var hero: PulseHero

    public var eyebrow: String          // "PRAYER UPDATE" / "TONIGHT · 7:00 PM" / "NEW IN AMEN"
    public var title: String            // NeMo-gated; guilt-lint enforced server-side
    public var subtitle: String?
    public var action: PulseAction      // exactly one primary action

    /// Resolved SERVER-SIDE. The client never decides minor-safety; it only trusts this.
    public var minorSafe: Bool
    /// Cards die; nothing lingers to nag.
    public var expiresAt: Date?
    /// Human-readable attribution shown in detail ("Summaries by Berean · cite-or-refuse").
    public var provenanceLabel: String?

    // Kind-specific optional content
    public var facts: [PulseFact]?              // daily_brief_hero fact rows
    public var meta: [PulseFact]?               // church_event meta rows
    public var briefSections: [PulseBriefSection]?  // daily_brief_hero body
    public var whatsNewStoryId: String?         // whats_new → WhatsNewStory reference

    public init(
        id: String,
        kind: PulseCardKind,
        score: PulseScore = PulseScore(),
        hero: PulseHero,
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        action: PulseAction = .none,
        minorSafe: Bool = true,
        expiresAt: Date? = nil,
        provenanceLabel: String? = nil,
        facts: [PulseFact]? = nil,
        meta: [PulseFact]? = nil,
        briefSections: [PulseBriefSection]? = nil,
        whatsNewStoryId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.score = score
        self.hero = hero
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.minorSafe = minorSafe
        self.expiresAt = expiresAt
        self.provenanceLabel = provenanceLabel
        self.facts = facts
        self.meta = meta
        self.briefSections = briefSections
        self.whatsNewStoryId = whatsNewStoryId
    }
}

// MARK: - Digest (one document the client reads — no client ranking, ever)

public struct PulseDigest: Codable, Hashable, Sendable {
    public var date: String                 // YYYY-MM-DD, user timezone
    public var cards: [PulseCard]           // length <= maxCards (config)
    public var generatedAt: Date?
    public var sabbath: Bool                // true => single still card
    public var briefDurations: [PulseBriefDuration]

    public init(
        date: String,
        cards: [PulseCard],
        generatedAt: Date? = nil,
        sabbath: Bool = false,
        briefDurations: [PulseBriefDuration] = [.thirtySec, .threeMin, .tenMin]
    ) {
        self.date = date
        self.cards = cards
        self.generatedAt = generatedAt
        self.sabbath = sabbath
        self.briefDurations = briefDurations
    }
}

// MARK: - What's New (editorial)

public enum WhatsNewAudience: String, Codable, Hashable, Sendable {
    case all
    /// Guardian-gated features never teased to minors (server-resolved).
    case adultOnly = "adult_only"
}

public enum WhatsNewLayout: String, Codable, Hashable, Sendable {
    case fullBleed   = "full_bleed"
    case split
    case captionOver = "caption_over"
}

public struct WhatsNewPage: Codable, Hashable, Identifiable, Sendable {
    public var id: String { headline }
    public var heroImageUrl: String?
    /// Gradient catalog key when heroImageUrl is nil.
    public var style: String?
    public var headline: String
    public var body: String
    public var layout: WhatsNewLayout

    public init(heroImageUrl: String? = nil, style: String? = nil, headline: String,
                body: String, layout: WhatsNewLayout = .fullBleed) {
        self.heroImageUrl = heroImageUrl
        self.style = style
        self.headline = headline
        self.body = body
        self.layout = layout
    }
}

public struct WhatsNewTryAction: Codable, Hashable, Sendable {
    public var deeplink: String
    public var label: String
    public init(deeplink: String, label: String) {
        self.deeplink = deeplink
        self.label = label
    }
}

public struct WhatsNewStory: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var version: String
    public var title: String
    public var tagline: String
    public var pages: [WhatsNewPage]
    public var tryAction: WhatsNewTryAction?
    public var videoUrl: String?
    public var audience: WhatsNewAudience
    public var publishedAt: Date?
    /// Stories are bookmarkable into /users/{uid}/bookmarks.
    public var bookmarkable: Bool

    public init(
        id: String,
        version: String,
        title: String,
        tagline: String,
        pages: [WhatsNewPage],
        tryAction: WhatsNewTryAction? = nil,
        videoUrl: String? = nil,
        audience: WhatsNewAudience = .all,
        publishedAt: Date? = nil,
        bookmarkable: Bool = true
    ) {
        self.id = id
        self.version = version
        self.title = title
        self.tagline = tagline
        self.pages = pages
        self.tryAction = tryAction
        self.videoUrl = videoUrl
        self.audience = audience
        self.publishedAt = publishedAt
        self.bookmarkable = bookmarkable
    }

    /// A story is "fresh" (eligible as a Pulse card) within 14 days of publishing.
    public func isFresh(asOf now: Date = Date()) -> Bool {
        guard let publishedAt else { return false }
        return now.timeIntervalSince(publishedAt) <= 14 * 24 * 60 * 60
    }
}

// MARK: - Preferences (user-owned)

public enum PulseStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case spiritualFirst = "spiritual_first"
    case communityFirst = "community_first"
    case churchFirst    = "church_first"
    case familyFirst    = "family_first"
    case minimal
    case discover

    public var displayName: String {
        switch self {
        case .spiritualFirst: return String(localized: "Spiritual first")
        case .communityFirst: return String(localized: "Community first")
        case .churchFirst:    return String(localized: "Church first")
        case .familyFirst:    return String(localized: "Family first")
        case .minimal:        return String(localized: "Minimal")
        case .discover:       return String(localized: "Discover")
        }
    }
}

public struct PulseSources: Codable, Hashable, Sendable {
    public var friends: Bool
    public var church: Bool
    public var spaces: Bool
    public var following: Bool
    public var local: Bool       // adult-only; server enforces regardless of this flag
    public var global: Bool

    public init(friends: Bool = true, church: Bool = true, spaces: Bool = true,
                following: Bool = true, local: Bool = false, global: Bool = true) {
        self.friends = friends
        self.church = church
        self.spaces = spaces
        self.following = following
        self.local = local
        self.global = global
    }
}

public struct PulsePrefs: Codable, Hashable, Sendable {
    public var interests: [String]      // theology, parenting, worship, ...
    public var sources: PulseSources
    public var style: PulseStyle
    /// User may LOWER the cap, never raise it above the server/config maximum.
    public var maxCards: Int?

    public init(interests: [String] = [], sources: PulseSources = PulseSources(),
                style: PulseStyle = .spiritualFirst, maxCards: Int? = nil) {
        self.interests = interests
        self.sources = sources
        self.style = style
        self.maxCards = maxCards
    }

    public static let `default` = PulsePrefs()

    /// Catalog of selectable interests surfaced in the prefs UI.
    public static let interestCatalog: [String] = [
        "theology", "prayer", "worship", "parenting", "marriage",
        "discipleship", "missions", "service", "study", "rest"
    ]
}

// MARK: - Config (client mirror of amen.routing.config — server is source of truth)

public enum PulseConfig {
    /// Hard ceiling on rendered cards (excluding the terminus). Server is authoritative;
    /// this is the client fallback when the digest doc omits a cap.
    public static let defaultMaxCards = 7
    /// Absolute floor a user may lower their cap to.
    public static let minUserCards = 3
}
