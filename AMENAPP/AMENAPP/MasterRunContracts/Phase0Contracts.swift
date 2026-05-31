// Phase0Contracts.swift
// AMENAPP/MasterRunContracts
//
// FROZEN — Phase 0 contracts. Do not edit without A0 authorization.
//
// Covers:
//   Phase 1 — Find a Church (ChurchRecord, ChurchSearchServiceProtocol)
//   Phase 3 — Posts Provenance (PostProvenance, PostProvenanceServiceProtocol)
//   Phase 5 — Selah Stories (SelahStory, SelahStoryServiceProtocol)
//   Cross-cutting — LiturgicalSeasonKind, MasterRunFeatureFlags stub
//
// Naming decisions (A1 gap reconciliation):
//   - Church: A `Church` struct already exists in FindChurchView.swift as a legacy
//     Google Maps–sourced simple struct (UUID id, no rating, no verified).
//     SmartChurch in SmartChurchModels.swift has richer fields but uses string
//     denomination, no distanceMeters, no rating/isOpenNow/verified booleans.
//     Neither is compatible with the master-run spec. Contract type is therefore
//     named `ChurchRecord` to avoid a redeclaration conflict with the legacy
//     `Church` struct. All Phase 1 agents must use `ChurchRecord`.
//   - ChurchSearchDenomination: new enum; SmartChurch uses a plain String for denomination.
//   - ServiceTime: `ChurchEntity.ServiceTime` in ChurchModels.swift is similar but
//     uses dayOfWeek:Int + time:String rather than weekday:Int + start:Date + label.
//     Contract defines `ChurchServiceTime` to avoid ambiguity.
//   - GeoPoint: `ChurchEntity.GeoPoint` in ChurchModels.swift already exists
//     (lat/lng Doubles). Reused via `ChurchGeoPoint` typealias below.
//   - ScriptureRef: `ScriptureRef` in SemanticTopicService.swift already exists
//     (book, chapter, verse?, endVerse?) and conforms to Equatable.
//     Contract extends it with Codable via an explicit extension.
//   - StoryMedia, StoryOverlay, StoryAudio: do NOT exist in the main project source.
//     Minimal stubs defined here so SelahStory compiles.
//   - FeedSource, ReasonKind: do NOT exist at top-level. `ReasonKind` exists as
//     a nested enum inside UserMiniReason (UserProfileMiniModel.swift) with different
//     cases. This contract defines top-level `FeedSource` and `ProvenanceReasonKind`
//     to avoid shadowing the nested type.
//   - LiturgicalSeasonKind: `LiturgicalSeasonKindType` already exists in LiturgicalCalendarEngine.swift
//     with finer granularity (ordinaryTimeEarly/Late split). Contract defines
//     `LiturgicalSeasonKind` as a simpler canonical enum for cross-phase use; it does NOT
//     replace LiturgicalSeasonKindType.
//   - Feature flags: `findAChurch`, `posts_liquidGlass`, `whySeeingThis`,
//     `selahStories`, `selahStoriesPremiumAI` do NOT exist in any flags file.
//     Stubs are noted here for A9 to wire into the appropriate flags provider.
//

import Foundation
import CoreLocation

// ─────────────────────────────────────────────────────────────────
// MARK: - Phase 1: Find a Church
// ─────────────────────────────────────────────────────────────────

// MARK: ChurchSearchDenomination

/// Canonical denomination taxonomy for Phase 1 church search.
/// SmartChurch uses a plain String; ChurchRecord uses this enum.
enum ChurchSearchDenomination: String, Codable, CaseIterable, Hashable {
    case nonChurchSearchDenominational
    case baptist
    case methodist
    case presbyterian
    case lutheran
    case pentecostal
    case catholic
    case anglican
    case reformed
    case adventist
    case orthodox
    case other
}

// MARK: ChurchJourneyServiceTime

/// A single recurring service time for a church, used in the journey/planning flow.
/// Uses Int weekday + Date start to support calendar scheduling.
/// Distinct from ChurchServiceTime (ChurchServiceTime.swift) which uses String fields.
struct ChurchJourneyServiceTime: Codable, Hashable {
    /// Day of week, 1 = Sunday … 7 = Saturday (ISO 8601 style: 1-based, Sunday = 1).
    let weekday: Int
    /// Absolute Date representing the scheduled start time (time components only; date portion is ignored at display time).
    let start: Date
    /// Human-readable label, e.g. "Sunday Morning Service" or "Spanish Service".
    let label: String
}

// MARK: ChurchGeoPoint

/// Reuses the shape of `ChurchEntity.GeoPoint` from ChurchModels.swift.
/// Defined here as a standalone type so Phase 1 agents don't import ChurchModels.
struct ChurchGeoPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: ChurchRecord

/// Canonical church model for the master-run Find a Church feature (Phase 1).
///
/// Named `ChurchRecord` (not `Church`) because a simpler `Church` struct already
/// exists in FindChurchView.swift. All Phase 1 agents use `ChurchRecord`.
struct ChurchRecord: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let denomination: ChurchSearchDenomination
    let coordinate: ChurchGeoPoint
    let address: String
    let serviceTimes: [ChurchJourneyServiceTime]
    let distanceMeters: Double?
    let rating: Double?
    let isOpenNow: Bool?
    let verified: Bool
}

// MARK: ChurchSearchFilters

struct ChurchSearchFilters: Codable {
    var openNow: Bool?
    var denomination: ChurchSearchDenomination?
    var maxDistanceMeters: Double?
    var sortBy: ChurchSortOrder
}

enum ChurchSortOrder: String, Codable {
    case bestMatch
    case distance
    case rating
}

// MARK: ChurchSearchServiceProtocol

/// Contract for church search. Implemented by SmartChurchSearchService (adapts results to ChurchRecord).
protocol ChurchSearchServiceProtocol {
    func search(
        query: String,
        coordinate: CLLocationCoordinate2D?,
        filters: ChurchSearchFilters
    ) async throws -> [ChurchRecord]
}

// ─────────────────────────────────────────────────────────────────
// MARK: - Phase 3: Posts Provenance
// ─────────────────────────────────────────────────────────────────

// MARK: FeedSource

/// Where a post entered the user's feed.
/// Top-level enum; does NOT conflict with the nested `UserMiniReason.ReasonKind`.
enum FeedSource: String, Codable, Hashable {
    case following
    case discover
    case churchGroup
    case prayer
    case bereanRecommended
    case direct
}

// MARK: ProvenanceReasonKind

/// The classification of a single provenance signal for a post.
/// Named `ProvenanceReasonKind` (not `ReasonKind`) to avoid shadowing the
/// nested `UserMiniReason.ReasonKind` in UserProfileMiniModel.swift.
enum ProvenanceReasonKind: String, Codable, Hashable {
    case following
    case communityTrending
    case sharedInterest
    case churchGroup
    case scripture
    case recencyBoost
    case curatedByBerean
}

// MARK: ProvenanceReason

struct ProvenanceReason: Codable, Hashable {
    let label: String
    let score: Double
    let kind: ProvenanceReasonKind
}

// MARK: PostProvenance

/// Feed-level provenance for a single post.
/// Distinct from `AmenMediaProvenanceService` / `TSMediaProvenance` which are
/// media-level (audio/image attribution), not feed-ranking signals.
struct PostProvenance: Codable, Hashable {
    let postId: String
    let reasons: [ProvenanceReason]
    let addedInterestOn: Date?
    let source: FeedSource
}

// MARK: ProvenanceFeedback

enum ProvenanceFeedback: Codable, Hashable {
    case notRelevant(postId: String)
    case wantMore(postId: String)
    case wantFewer(postId: String)
    case mute(authorId: String)
    case hide(postId: String)
}

// MARK: PostProvenanceServiceProtocol

protocol PostProvenanceServiceProtocol {
    func fetchProvenance(postId: String) async throws -> PostProvenance
    func sendFeedback(_ feedback: ProvenanceFeedback) async throws
}

// ─────────────────────────────────────────────────────────────────
// MARK: - Phase 5: Selah Stories
// ─────────────────────────────────────────────────────────────────

// MARK: ScriptureRef + Codable

/// `ScriptureRef` is defined in SemanticTopicService.swift as Equatable only.
/// Phase 5 needs Codable serialization, so we add it here as a conditional extension.
/// NOTE: If the compiler reports a duplicate Codable conformance in a future build,
/// remove this extension and add `Codable` to the original declaration in SemanticTopicService.swift.
extension ScriptureRef: Codable {
    enum CodingKeys: String, CodingKey {
        case book, chapter, verse, endVerse
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        book    = try c.decode(String.self, forKey: .book)
        chapter = try c.decode(Int.self, forKey: .chapter)
        verse   = try c.decodeIfPresent(Int.self, forKey: .verse)
        endVerse = try c.decodeIfPresent(Int.self, forKey: .endVerse)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(book, forKey: .book)
        try c.encode(chapter, forKey: .chapter)
        try c.encodeIfPresent(verse, forKey: .verse)
        try c.encodeIfPresent(endVerse, forKey: .endVerse)
    }
}

// MARK: StoryMedia (stub)

/// Represents a single media item (photo, video) within a SelahStory.
/// Stub — full definition to be provided by the Phase 5 agent.
struct StoryMedia: Codable, Hashable, Identifiable {
    let id: String
    let url: String
    let mediaType: String   // "photo" | "video"
    let durationSeconds: Double?
}

// MARK: StoryOverlay (stub)

/// A text or scripture overlay rendered on top of a StoryMedia item.
/// Stub — full definition to be provided by the Phase 5 agent.
struct StoryOverlay: Codable, Identifiable {
    let id: String
    let text: String
    let positionX: Double
    let positionY: Double
    let scriptureRef: ScriptureRef?
}

// MARK: StoryAudio (stub)

/// Background audio (worship music or ambient) associated with a SelahStory.
/// Stub — full definition to be provided by the Phase 5 agent.
struct StoryAudio: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let artistName: String?
    let url: String
    let durationSeconds: Double
}

// MARK: StoryAudience

enum StoryAudience: String, Codable, Hashable {
    case closeFriends
    case churchGroup
    case accountabilityPartner
}

// MARK: StoryKind

enum StoryKind: String, Codable, Hashable {
    case reflection
    case prayer
    case praise
}

// MARK: SelahStory

/// Multimedia ephemeral story for the Selah Stories feature (Phase 5).
/// Distinct from `SelahReflectionDocument` (text-only private journal) in SelahContracts.swift.
struct SelahStory: Identifiable, Codable {
    let id: String
    let ownerUid: String
    let kind: StoryKind
    let audience: StoryAudience
    let media: [StoryMedia]
    let overlays: [StoryOverlay]
    let audio: StoryAudio?
    let scriptureRef: ScriptureRef?
    let caption: String?
    let liturgicalSeason: LiturgicalSeasonKind?
    let createdAt: Date
    /// Stories expire after 24 hours. nil = no expiry (e.g. saved/archived stories).
    let expiresAt: Date?
}

// MARK: SelahStoryServiceProtocol

protocol SelahStoryServiceProtocol {
    /// Creates a new story and returns the generated storyId.
    func create(_ story: SelahStory) async throws -> String

    func fetchStories(for userId: String) async throws -> [SelahStory]

    func delete(storyId: String) async throws

    // MARK: Premium AI features (gated by MasterRunFeatureFlags.selahStoriesPremiumAI)

    /// Recognizes a scripture reference from a user-captured image (OCR + semantic match).
    func recognizeVerse(from imageData: Data) async throws -> ScriptureRef?

    /// Generates a short reflective prompt grounded in the given scripture reference.
    func generateReflectionPrompt(for ref: ScriptureRef) async throws -> String

    /// Recommends ambient/worship audio that complements the scripture and liturgical season.
    func matchAudio(for ref: ScriptureRef, season: LiturgicalSeasonKind?) async throws -> StoryAudio?
}

// ─────────────────────────────────────────────────────────────────
// MARK: - Cross-cutting: LiturgicalSeasonKind
// ─────────────────────────────────────────────────────────────────

/// Simplified canonical liturgical season for cross-phase use (P1, P3, P5).
///
/// DISTINCT from `LiturgicalSeasonKindType` in LiturgicalCalendarEngine.swift, which
/// splits ordinary time into `ordinaryTimeEarly` and `ordinaryTimeLate`.
/// `LiturgicalSeasonKind` uses a single `ordinary` case for simplicity.
/// Features that need finer granularity should import LiturgicalCalendarEngine directly.
enum LiturgicalSeasonKind: String, Codable, CaseIterable, Hashable {
    case ordinary
    case advent
    case christmas
    case epiphany
    case lent
    case holyWeek
    case easter
    case pentecost

    /// Returns the approximate current liturgical season based on the Gregorian calendar.
    /// This is a heuristic for UI affordances only — not a liturgical authority.
    /// For authoritative computation use `LiturgicalCalendarEngine.shared.currentSeason()`.
    static var current: LiturgicalSeasonKind {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let month = cal.component(.month, from: now)
        let day   = cal.component(.day,   from: now)

        switch (month, day) {
        // Advent: roughly Dec 1–24
        case (12, 1...24): return .advent
        // Christmas: Dec 25 – Jan 5
        case (12, 25...31), (1, 1...5): return .christmas
        // Epiphany: Jan 6 – start of Lent (approximate: late Feb)
        case (1, 6...31), (2, _):
            if month == 2 && day >= 14 { return .lent }
            return .epiphany
        // Lent: approximate Feb 14 – Palm Sunday (late Mar / early Apr)
        case (3, 1...27): return .lent
        // Holy Week: last week of March / first days of April (approximate)
        case (3, 28...31), (4, 1...7): return .holyWeek
        // Easter Season: Apr 8 – Pentecost (approximately 50 days after Easter)
        case (4, 8...30), (5, 1...19): return .easter
        // Pentecost: May 20 – Nov 30
        case (5, 20...31), (6, _), (7, _), (8, _), (9, _), (10, _), (11, _): return .pentecost
        default: return .ordinary
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// MARK: - MasterRun Feature Flags Stub
// ─────────────────────────────────────────────────────────────────

/// Stub showing which feature flags A9 must wire into the app's flags provider.
/// None of the following flags exist in any current flags file (ChurchAssistFeatureFlags,
/// CreatorFeatureFlags, TranslationFeatureFlags) as of the contract freeze date.
///
/// A9 should add these to the appropriate AMENFeatureFlags provider and replace
/// this struct with imports of the real flag values.
///
/// Usage (until A9 wires them):
///   `MasterRunFeatureFlags.findAChurch`  — Phase 1 church search new UX
///   `MasterRunFeatureFlags.postsLiquidGlass` — Phase 2 Liquid Glass post cells
///   `MasterRunFeatureFlags.whySeeingThis`    — Phase 3 provenance sheet
///   `MasterRunFeatureFlags.selahStories`     — Phase 5 multimedia stories
///   `MasterRunFeatureFlags.selahStoriesPremiumAI` — Phase 5 AI verse recognition + audio match
enum MasterRunFeatureFlags {
    // A9 WIRE POINT: replace these constants with reads from Remote Config / local flags provider.
    static let findAChurch: Bool = false
    static let postsLiquidGlass: Bool = false
    static let whySeeingThis: Bool = false
    static let selahStories: Bool = false
    static let selahStoriesPremiumAI: Bool = false
}
