// CreatorSpotlightContracts.swift
// AMENAPP — Creator Showcase & Studio / Creator Spotlight
//
// Wave 0 Swift mirrors of src/creator/creatorSpotlightContracts.ts.
// TypeScript is source of truth. Keep in sync; add no behavior here.
//
// Extends existing Creator Profiles — does NOT fork a parallel profile model.
//
// CONSTITUTION LOCK (enforced via compile-time guards on non-negotiable fields):
//   - No public trust score / tier / trust level progression
//   - No leaderboards of people; no "Most X" people-ranking
//   - No shareable big-number "Wrapped" cards
//   - No demographic inference; no AI expertise-confidence score on a person
//   - No 5-star rating on a person; no automated theological-correctness score
//   - No ads or promoted placements (labeled sponsorship disclosed transparently)
//   - No passive-viewer identity list; no engagement-time optimizer
//   - All UGC fails closed without GUARDIAN pre-moderation

import Foundation

// MARK: - Verification Badge (factual role badge — not a rank or trust tier)

enum VerificationBadgeKind: String, Codable, CaseIterable, Sendable {
    case identity        = "identity"
    case organization    = "organization"
    case educator        = "educator"
    case minister        = "minister"
    case professional    = "professional"
    case communityLeader = "community_leader"

    var displayLabel: String {
        switch self {
        case .identity:        return "Verified Identity"
        case .organization:    return "Verified Organization"
        case .educator:        return "Verified Educator"
        case .minister:        return "Verified Minister"
        case .professional:    return "Verified Professional"
        case .communityLeader: return "Verified Community Leader"
        }
    }
}

struct VerificationBadge: Codable, Sendable {
    let kind: VerificationBadgeKind
    let verifiedAt: TimeInterval
    let verifiedBy: String  // Always "amen_team"
    let displayLabel: String
}

// MARK: - Orienting Metadata (replaces vanity stat row)

enum ContentFormat: String, Codable, CaseIterable, Sendable {
    case video      = "video"
    case audio      = "audio"
    case text       = "text"
    case series     = "series"
    case studyGuide = "study_guide"
    case devotional = "devotional"
    case prayer     = "prayer"
    case live       = "live"
}

enum CreatorLiturgicalSeason: String, Codable, CaseIterable, Sendable {
    case advent       = "advent"
    case christmas    = "christmas"
    case epiphany     = "epiphany"
    case lent         = "lent"
    case holyWeek     = "holy_week"
    case easter       = "easter"
    case pentecost    = "pentecost"
    case ordinaryTime = "ordinary_time"
    case none         = "none"
}

struct OrientingMetadata: Codable, Sendable {
    let format: [ContentFormat]
    let approximateLengthMinutes: Int?
    let scriptureReferences: [String]
    let liturgicalSeason: CreatorLiturgicalSeason?
    let audienceDescription: String?
    let whereToStart: String?
    let seriesName: String?
    let totalEpisodes: Int?
}

// MARK: - Content Capability ("What's inside")

enum ContentCapabilityKind: String, Codable, CaseIterable, Sendable {
    case studyGuide            = "study_guide"
    case audio                 = "audio"
    case groupReady            = "group_ready"
    case originalLanguageNotes = "original_language_notes"
    case worksWithBerean       = "works_with_berean"
    case transcripts           = "transcripts"
    case captions              = "captions"
    case signLanguage          = "sign_language"
    case discussionGuide       = "discussion_guide"
    case prayerGuide           = "prayer_guide"
    case downloadable          = "downloadable"
}

struct ContentCapability: Codable, Sendable {
    let kind: ContentCapabilityKind
    let available: Bool
}

// MARK: - Moderation (fail-closed)

enum SpotlightModerationStatus: String, Codable, Sendable {
    case pending     = "pending"      // Not yet reviewed — NEVER show to viewers
    case approved    = "approved"     // GUARDIAN cleared — readable
    case rejected    = "rejected"
    case unavailable = "unavailable"  // Moderation path down — treat as pending
}

// MARK: - Appropriateness Signal

enum AppropriatenessSignal: String, Codable, Sendable {
    case allAges           = "all_ages"
    case teenAndUp         = "teen_and_up"
    case matureThemes      = "mature_themes"     // Auto-hidden from minor-scoped sessions
    case guidanceSuggested = "guidance_suggested"
}

// MARK: - Creator Content

struct CreatorContent: Codable, Identifiable, Sendable {
    let id: String
    let creatorId: String
    let title: String
    let description: String?
    let format: ContentFormat
    let thumbnailUrl: String?
    let previewUrl: String?
    let durationSeconds: Int?
    let scriptureReferences: [String]
    let seriesId: String?
    let seriesPosition: Int?
    let publishedAt: TimeInterval?
    let orientingMetadata: OrientingMetadata
    let capabilities: [ContentCapability]
    let appropriatenessSignal: AppropriatenessSignal
    let moderationStatus: SpotlightModerationStatus
    let privacyDisclosure: PrivacyDisclosure
}

// MARK: - Reasoned Connection (finite; no ads; no infinite feed)

enum ReasonedConnectionKind: String, Codable, Sendable {
    case themeContinuation   = "theme_continuation"
    case passageDeepening    = "passage_deepening"
    case perspectiveContrast = "perspective_contrast"  // Anti-echo-chamber
    case collaborator        = "collaborator"
    case churchAffiliation   = "church_affiliation"
}

struct ReasonedConnection: Codable, Sendable {
    let targetId: String
    let targetKind: String   // "creator" | "series" | "content"
    /// Always shown to the user — never hidden
    let reason: String
    let reasonCategory: ReasonedConnectionKind
    // Compile-time guard: this connection is never an ad slot
    // (enforced by absence of any ad-slot field)
}

// MARK: - Community Reflection (replaces star-rating on a person)

enum ReflectionTag: String, Codable, CaseIterable, Sendable {
    case scriptureHelpful         = "scripture_helpful"
    case encouragedDeeperStudy    = "encouraged_deeper_study"
    case practical                = "practical"
    case goodForGroups            = "good_for_groups"
    case helpfulForNewBelievers   = "helpful_for_new_believers"
    case clear                    = "clear"
}

struct CommunityReflection: Codable, Identifiable, Sendable {
    let id: String
    let authorId: String
    let contentId: String?
    let targetCreatorId: String
    let tags: [ReflectionTag]
    let writtenReflection: String?
    let submittedAt: TimeInterval
    let moderationStatus: SpotlightModerationStatus
    /// Invisible to public until moderationStatus == .approved
    let visibleToPublic: Bool
}

struct BereanReflectionSummary: Codable, Sendable {
    let contentId: String?
    let creatorId: String
    let analyzedCount: Int
    let label: String          // Always "Summarized by Berean"
    let howGeneratedUrl: String
    let themeSummary: String
    let excludedCategories: [String]
    let generatedAt: TimeInterval
}

// MARK: - Privacy Disclosure ("What this touches")

struct PrivacyFieldDisclosure: Codable, Sendable {
    let fieldName: String
    let description: String
    let zone: PrivacyCoreZone
    let purposeDescription: String
}

struct PrivacyDisclosure: Codable, Sendable {
    let contentId: String?
    let creatorId: String?
    let touchedFields: [PrivacyFieldDisclosure]
    let neverTouchedList: [String]
    /// NSPrivacyTracking invariant — always false
    let nsmPrivacyTracking: Bool  // Must always be false
    let generatedAt: TimeInterval
}

// MARK: - Now / New

enum NowAndNewKind: String, Codable, Sendable {
    case newSeries      = "new_series"
    case liveSession    = "live_session"
    case upcomingEvent  = "upcoming_event"
    case newEpisode     = "new_episode"
    case announcement   = "announcement"
    case resource       = "resource"
}

struct NowAndNewItem: Codable, Identifiable, Sendable {
    let id: String
    let creatorId: String
    let kind: NowAndNewKind
    let headline: String
    let description: String?
    let scheduledAt: TimeInterval?
    let liveNow: Bool
    let primaryActionLabel: String?
    let primaryActionDeepLink: String?
}

// MARK: - Curation Slot (editorial/pastoral; NEVER a popularity rank)

enum CurationIntent: String, Codable, Sendable {
    case editorial         = "editorial"
    case pastoral          = "pastoral"
    case seasonal          = "seasonal"
    case newVoice          = "new_voice"
    case local             = "local"
    case labeledSponsorship = "labeled_sponsorship"  // Paid; always labeled
}

struct CurationSlot: Codable, Identifiable, Sendable {
    let id: String
    let intent: CurationIntent
    let targetId: String
    let targetKind: String
    let intentLabel: String
    let liturgicalSeason: CreatorLiturgicalSeason?
    let activeFrom: TimeInterval
    let activeUntil: TimeInterval
    let sponsorLabel: String?  // Required when intent == .labeledSponsorship
}

// MARK: - Creator Spotlight (public page extension)

enum ContentTab: String, Codable, CaseIterable, Sendable {
    case overview    = "overview"
    case teachings   = "teachings"
    case series      = "series"
    case posts       = "posts"
    case live        = "live"
    case events      = "events"
    case resources   = "resources"
    case communities = "communities"
    case about       = "about"
}

struct CreatorSpotlight: Codable, Sendable {
    /// Links to existing CreatorProfile — never duplicates profile fields
    let creatorId: String
    let missionStatement: String?
    let featuredContentId: String?
    let verificationBadges: [VerificationBadge]
    let activeSeriesIds: [String]
    let contentTabOrder: [ContentTab]
    /// Finite list — no infinite feed; each connection has a stated reason
    let reasonedConnections: [ReasonedConnection]
    let nowAndNew: [NowAndNewItem]
    /// Always false until flag enabled — fail-closed
    let enabled: Bool
}

// MARK: - Studio Insight (stewardship framing — not a scoreboard)

enum InsightKind: String, Codable, Sendable {
    case formationTrend      = "formation_trend"
    case searchDiscovery     = "search_discovery"
    case passageResonance    = "passage_resonance"
    case stewardshipSummary  = "stewardship_summary"
}

struct StudioInsight: Codable, Identifiable, Sendable {
    let id: String
    let creatorId: String
    let kind: InsightKind
    /// Stewardship-framed plain language — raw number never hero of the screen
    let narrativeText: String
    let supportingMetricLabel: String?
    let supportingMetricValue: String?
    let supportingMetricContext: String?
    let periodLabel: String
    let generatedAt: TimeInterval
    // No growth chart field; no streak field; no "post more to grow" field
}
