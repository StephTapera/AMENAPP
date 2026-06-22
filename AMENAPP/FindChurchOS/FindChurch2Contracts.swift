// FindChurch2Contracts.swift
// AMENAPP — Find Church 2.0
//
// FROZEN WAVE 1 CONTRACTS — do not modify after Wave 1 commit.
// All downstream waves (2–6) import from this file.
//
// Collections:
//   churches/{id}          — ChurchObject (extends existing schema, additive)
//   gatherings/{id}        — GatheringObject (new)
//   seekerProfiles/{uid}   — SeekerProfile (Tier-P, owner-only)
//   visitPlans/{id}        — VisitPlan (commitment object)

import Foundation
import CoreLocation

// MARK: - Feature Flags

/// Raw Remote Config key names for Find Church 2.0 flags.
/// Use `AMENFeatureFlags.shared.findChurch2*Enabled` for actual gate checks;
/// this enum is for documentation and flag-name references only.
enum FindChurch2Flag: String {
    case onboarding       = "findChurch2_onboarding"
    case matchExplain     = "findChurch2_matchExplain"
    case gatherings       = "findChurch2_gatherings"
    case visitPlanner     = "findChurch2_visitPlanner"
    case claimPortal      = "findChurch2_claimPortal"
    case concierge        = "findChurch2_concierge"
    case mapHybrid        = "findChurch2_mapHybrid"
    case availability     = "findChurch2_availability"
    case trustSignals     = "findChurch2_trustSignals"
    case designRefresh    = "findChurch2_designRefresh"
}

// MARK: - ChurchObject

/// Canonical church identity stored at `churches/{id}`.
/// Additive over ChurchEntity — all new fields are optional so existing documents remain readable.
struct ChurchObject: Identifiable, Codable, Hashable {

    // ── Core identity ─────────────────────────────────────────────────────────
    let id: String
    let placeId: String?          // Google Places ID (dedupe key)
    let ein: String?              // IRS EIN (dedupe key for US nonprofits)
    let name: String
    let normalizedName: String    // lowercase, stripped punctuation — dedupe key
    let address: String
    let normalizedAddress: String // normalized for dedupe
    let city: String
    let state: String?
    let zipCode: String?
    let country: String
    let coordinate: GeoCoordinate
    let phoneNumber: String?
    let email: String?
    let website: String?
    let photoURL: String?
    let logoURL: String?

    // ── Denomination lineage ──────────────────────────────────────────────────
    let denomination: String?            // e.g. "Southern Baptist Convention"
    let denominationFamily: String?      // e.g. "Baptist"
    let denominationIsFlexible: Bool     // true for non-denom
    let denominationLineage: [String]    // ["Protestant", "Evangelical", "Baptist", "SBC"]

    // ── Beliefs schema (editable only by verified claimants) ─────────────────
    var beliefs: BeliefSchema?

    // ── Service times (structured, recurring, timezone-aware) ────────────────
    var serviceTimes: [StructuredServiceTime]

    // ── Media links ───────────────────────────────────────────────────────────
    var mediaLinks: MediaLinks

    // ── Accessibility ─────────────────────────────────────────────────────────
    var accessibility: AccessibilityInfo

    // ── Claim / verification state ────────────────────────────────────────────
    var claimState: ClaimState
    var verificationTier: VerificationTier
    var claimedBy: String?        // uid of claimant
    var claimedAt: Date?

    // ── Child safety ──────────────────────────────────────────────────────────
    var childSafetyPolicy: ChildSafetyPolicy

    // ── Staff & ministries ────────────────────────────────────────────────────
    var staffCount: Int?
    var ministryTags: [String]    // ["youth", "women", "recovery", "worship"]

    // ── Gathering refs ────────────────────────────────────────────────────────
    var gatheringIds: [String]    // IDs in the `gatherings/` collection

    // ── Computed availability (cached by CF) ──────────────────────────────────
    var availabilityCache: AvailabilityStatus?
    var availabilityCachedAt: Date?

    // ── Crowdsourced suggestions (pending claimant approval) ─────────────────
    var pendingServiceTimeSuggestions: Int  // count only; CF manages queue

    // ── Community signals ─────────────────────────────────────────────────────
    var amenMemberCount: Int      // Users who marked "My Church"
    var visitCount: Int
    var friendSavedCount: Int     // Count of friends who saved (user-specific, computed client-side)

    // ── Source & timestamps ───────────────────────────────────────────────────
    let source: ChurchSource
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    enum ChurchSource: String, Codable {
        case googlePlaces   = "google_places"
        case userSubmitted  = "user_submitted"
        case denominational = "denominational"
        case manual         = "manual"
    }

    enum ClaimState: String, Codable {
        case unclaimed = "unclaimed"
        case pending   = "pending"
        case verified  = "verified"
    }

    enum VerificationTier: String, Codable {
        case none   = "none"
        case domain = "domain"    // email domain match — instant
        case ein    = "ein"       // IRS EIN verified
        case manual = "manual"    // human review by Aegis
    }

    struct GeoCoordinate: Codable, Hashable {
        let latitude: Double
        let longitude: Double

        var clLocation: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

        func distance(from location: CLLocation) -> Double {
            clLocation.distance(from: location) / 1609.34
        }
    }
}

// MARK: - BeliefSchema

struct BeliefSchema: Codable, Hashable {
    var baptismView: String?          // "believer's baptism", "infant baptism", "no preference"
    var communionView: String?        // "memorial", "real presence", "transubstantiation"
    var governance: String?           // "congregational", "episcopal", "presbyterian"
    var worshipStyle: String?         // "traditional", "contemporary", "blended", "liturgical"
    var spiritualGifts: String?       // "cessationist", "continuationist", "open"
    var womenInMinistry: String?      // "egalitarian", "complementarian", "varies"
    var scriptureView: String?        // "inerrancy", "infallibility", "inspired"
    var customTags: [String]          // free-form belief tags from claimant

    /// Structured tags suitable for search facets and chip rendering.
    var allTags: [BeliefTag] {
        var tags: [BeliefTag] = []
        if let b = baptismView    { tags.append(.init(category: "Baptism", value: b)) }
        if let c = communionView  { tags.append(.init(category: "Communion", value: c)) }
        if let g = governance     { tags.append(.init(category: "Governance", value: g)) }
        if let w = worshipStyle   { tags.append(.init(category: "Worship", value: w)) }
        if let s = spiritualGifts { tags.append(.init(category: "Spiritual Gifts", value: s)) }
        if let m = womenInMinistry { tags.append(.init(category: "Women in Ministry", value: m)) }
        if let sc = scriptureView { tags.append(.init(category: "Scripture", value: sc)) }
        customTags.forEach { tags.append(.init(category: "Other", value: $0)) }
        return tags
    }
}

struct BeliefTag: Codable, Hashable {
    let category: String
    let value: String
}

// MARK: - StructuredServiceTime

struct StructuredServiceTime: Codable, Hashable, Identifiable {
    var id: String
    let dayOfWeek: Int             // 1=Sunday … 7=Saturday
    let startHour: Int             // 0-23 in local time
    let startMinute: Int           // 0-59
    let durationMinutes: Int?
    let timezone: String           // IANA timezone identifier e.g. "America/Phoenix"
    let serviceType: String?       // "Main Service", "Youth", "Spanish", etc.
    let isRecurring: Bool
    let languages: [String]        // ["en", "es"]
    let isAccessibleASL: Bool
    let isAccessibleWheelchair: Bool

    var displayTime: String {
        let hour12 = startHour % 12 == 0 ? 12 : startHour % 12
        let ampm = startHour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour12, startMinute, ampm)
    }

    init(id: String = UUID().uuidString,
         dayOfWeek: Int,
         startHour: Int,
         startMinute: Int,
         durationMinutes: Int? = nil,
         timezone: String = "America/Phoenix",
         serviceType: String? = nil,
         isRecurring: Bool = true,
         languages: [String] = ["en"],
         isAccessibleASL: Bool = false,
         isAccessibleWheelchair: Bool = false) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.startHour = startHour
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.timezone = timezone
        self.serviceType = serviceType
        self.isRecurring = isRecurring
        self.languages = languages
        self.isAccessibleASL = isAccessibleASL
        self.isAccessibleWheelchair = isAccessibleWheelchair
    }
}

// MARK: - MediaLinks

struct MediaLinks: Codable, Hashable {
    var sermonArchiveURL: String?
    var youtubeChannelURL: String?
    var podcastRSSURL: String?
    var livestreamURL: String?
    var detectedMediaType: DetectedMediaType

    enum DetectedMediaType: String, Codable {
        case none       = "none"
        case podcast    = "podcast"
        case youtube    = "youtube"
        case livestream = "livestream"
        case multiple   = "multiple"
    }

    var hasMedia: Bool { detectedMediaType != .none }

    init(sermonArchiveURL: String? = nil,
         youtubeChannelURL: String? = nil,
         podcastRSSURL: String? = nil,
         livestreamURL: String? = nil,
         detectedMediaType: DetectedMediaType = .none) {
        self.sermonArchiveURL = sermonArchiveURL
        self.youtubeChannelURL = youtubeChannelURL
        self.podcastRSSURL = podcastRSSURL
        self.livestreamURL = livestreamURL
        self.detectedMediaType = detectedMediaType
    }
}

// MARK: - AccessibilityInfo

struct AccessibilityInfo: Codable, Hashable {
    var hasASL: Bool
    var isWheelchairAccessible: Bool
    var languages: [String]          // BCP-47 codes ["en", "es", "ko"]
    var hasChildcare: Bool
    var parkingNotes: String?
    var entranceNotes: String?

    init(hasASL: Bool = false,
         isWheelchairAccessible: Bool = false,
         languages: [String] = ["en"],
         hasChildcare: Bool = false,
         parkingNotes: String? = nil,
         entranceNotes: String? = nil) {
        self.hasASL = hasASL
        self.isWheelchairAccessible = isWheelchairAccessible
        self.languages = languages
        self.hasChildcare = hasChildcare
        self.parkingNotes = parkingNotes
        self.entranceNotes = entranceNotes
    }
}

// MARK: - ChildSafetyPolicy

struct ChildSafetyPolicy: Codable, Hashable {
    var hasFormalPolicy: Bool?       // nil = not provided
    var backgroundChecksRequired: Bool?
    var policyURL: String?

    init(hasFormalPolicy: Bool? = nil, backgroundChecksRequired: Bool? = nil, policyURL: String? = nil) {
        self.hasFormalPolicy = hasFormalPolicy
        self.backgroundChecksRequired = backgroundChecksRequired
        self.policyURL = policyURL
    }

    var displayState: DisplayState {
        switch hasFormalPolicy {
        case .none: return .notProvided
        case .some(true): return .stated(hasBackgroundChecks: backgroundChecksRequired ?? false)
        case .some(false): return .noFormalPolicy
        }
    }

    enum DisplayState {
        case notProvided
        case stated(hasBackgroundChecks: Bool)
        case noFormalPolicy
    }
}

// MARK: - AvailabilityStatus

/// Computed from structured service times. Cached by CF; falls back to client computation.
struct AvailabilityStatus: Codable, Hashable {
    var openNow: Bool
    var serviceToday: Bool
    var serviceTime: String?         // e.g. "10:30 AM" — next upcoming service today
    var studyTonight: Bool
    var livestreamActive: Bool
    var prayerAvailable: Bool
    var contactNeeded: Bool          // true when structured times unavailable
    var computedAt: Date

    static var unknown: AvailabilityStatus {
        .init(openNow: false, serviceToday: false, serviceTime: nil,
              studyTonight: false, livestreamActive: false,
              prayerAvailable: false, contactNeeded: true,
              computedAt: Date())
    }

    /// Compute from structured service times without a CF round-trip.
    static func compute(from times: [StructuredServiceTime]) -> AvailabilityStatus {
        guard !times.isEmpty else { return .unknown }

        let now = Date()
        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: now) // 1=Sun … 7=Sat
        let currentHour  = calendar.component(.hour,   from: now)
        let currentMin   = calendar.component(.minute, from: now)

        var serviceToday = false
        var serviceTimeStr: String? = nil
        var openNow = false

        for t in times where t.dayOfWeek == todayWeekday {
            serviceToday = true
            if serviceTimeStr == nil { serviceTimeStr = t.displayTime }
            // "open now" = within service window (start to start + duration)
            let startMins = t.startHour * 60 + t.startMinute
            let endMins   = startMins + (t.durationMinutes ?? 90)
            let nowMins   = currentHour * 60 + currentMin
            if nowMins >= startMins && nowMins <= endMins { openNow = true }
        }

        return .init(
            openNow: openNow,
            serviceToday: serviceToday,
            serviceTime: serviceTimeStr,
            studyTonight: false,        // Gatherings layer fills this in W2
            livestreamActive: false,     // MediaLinks detection fills this in W2
            prayerAvailable: false,
            contactNeeded: false,
            computedAt: now
        )
    }
}

// MARK: - GatheringObject

/// Bible study, home group, campus ministry, or standalone gathering.
/// Stored at `gatherings/{id}`. May have an optional parent `churchId`.
struct GatheringObject: Identifiable, Codable, Hashable {
    let id: String
    let churchId: String?            // optional parent church
    let title: String
    let description: String?
    let gatheringType: GatheringType
    let hostVerified: Bool

    // Capacity & scheduling
    let seatsOpen: Int?
    var startsAt: Date?
    var meetingCadence: MeetingCadence
    var timezone: String             // IANA

    // Life-stage tags
    var lifeStage: [LifeStageTag]

    // Location
    var isOnline: Bool
    var address: String?
    var coordinate: ChurchObject.GeoCoordinate?

    // Contact
    var contactName: String?
    var contactEmail: String?        // CF-controlled; not readable by clients

    // Flags
    var isPublic: Bool
    var isDeleted: Bool
    let createdAt: Date
    var updatedAt: Date

    enum GatheringType: String, Codable {
        case bibleStudy      = "bible_study"
        case homeGroup       = "home_group"
        case campusMinistry  = "campus_ministry"
        case youthGroup      = "youth_group"
        case womenGroup      = "women_group"
        case mensGroup       = "mens_group"
        case recoveryGroup   = "recovery_group"
        case prayerGroup     = "prayer_group"
        case worship         = "worship"
        case service         = "service"
        case other           = "other"

        var displayName: String {
            switch self {
            case .bibleStudy:     return "Bible Study"
            case .homeGroup:      return "Home Group"
            case .campusMinistry: return "Campus Ministry"
            case .youthGroup:     return "Youth Group"
            case .womenGroup:     return "Women's Group"
            case .mensGroup:      return "Men's Group"
            case .recoveryGroup:  return "Recovery"
            case .prayerGroup:    return "Prayer Group"
            case .worship:        return "Worship Team"
            case .service:        return "Service Opportunity"
            case .other:          return "Gathering"
            }
        }
    }

    enum MeetingCadence: String, Codable {
        case weekly, biweekly, monthly, oneTime = "one_time", ongoing
    }

    enum LifeStageTag: String, Codable, CaseIterable {
        case youngAdults = "young_adults"
        case families    = "families"
        case singles
        case college
        case recovery
        case newBelievers = "new_believers"
        case creatives
        case seniors
        case teens

        var displayName: String {
            switch self {
            case .youngAdults:  return "Young Adults"
            case .families:     return "Families"
            case .singles:      return "Singles"
            case .college:      return "College"
            case .recovery:     return "Recovery"
            case .newBelievers: return "New Believers"
            case .creatives:    return "Creatives"
            case .seniors:      return "Seniors"
            case .teens:        return "Teens"
            }
        }
    }
}

// MARK: - MatchExplanation

/// Replaces bare percentage badge. `score` + structured chips everywhere a match is shown.
/// Rule: never render a score without at least two `topReasons`.
struct MatchExplanation: Codable, Hashable {
    let score: Int                   // 0-100
    let topReasons: [ReasonChip]
    let mismatches: [ReasonChip]
    let generatedBy: String          // "local" | "berean" | "server"
    let generatedAt: Date

    struct ReasonChip: Codable, Hashable, Identifiable {
        var id: String { category.rawValue + "_" + label }
        let category: ReasonCategory
        let label: String            // human-readable, e.g. "2.1 mi away"
        let weight: Double           // 0.0-1.0 contributing weight to score
        let isPositive: Bool         // true = match, false = mismatch

        enum ReasonCategory: String, Codable {
            case distance
            case serviceTime
            case denomination
            case worshipStyle
            case lifeStage
            case language
            case accessibility
            case familyFit
            case community          // AMEN members, friends attending
            case beliefs
            case custom
        }
    }

    var badgeText: String {
        switch score {
        case 80...: return "Great fit"
        case 60..<80: return "Good fit"
        case 40..<60: return "Worth exploring"
        default: return "Learning more"
        }
    }

    var primaryReasonSummary: String {
        topReasons.prefix(2).map(\.label).joined(separator: " · ")
    }
}

// MARK: - SeekerProfile (Tier-P)

/// Private seeker preferences. On-device first; Firestore sync controlled by privacySyncEnabled.
/// Firestore path: `seekerProfiles/{uid}` — owner-only.
struct SeekerProfile: Codable {

    var userId: String
    var intent: [SeekerIntent]
    var fitChips: [FitChip]
    var comfortPreferences: [ComfortChip]
    var inferredLifeStage: GatheringObject.LifeStageTag?
    var inferredSeason: String?          // "new_believer", "recommitment", "exploring"
    var inferredSignals: [InferredSignal] // From in-app behavior (requires explicit opt-in)

    // Privacy flags (functional — not decorative)
    var privateRecommendationsOnly: Bool  // computation on-device only
    var dontShareLocation: Bool           // switches to manual city entry
    var discoveryAgentEnabled: Bool       // default OFF — explicit user opt-in required

    var privacySyncEnabled: Bool          // sync to Firestore (default OFF)
    var updatedAt: Date

    static var empty: SeekerProfile {
        SeekerProfile(userId: "", intent: [], fitChips: [], comfortPreferences: [],
                      inferredLifeStage: nil, inferredSeason: nil, inferredSignals: [],
                      privateRecommendationsOnly: false, dontShareLocation: false,
                      discoveryAgentEnabled: false, privacySyncEnabled: false,
                      updatedAt: Date())
    }

    enum SeekerIntent: String, Codable, CaseIterable {
        case findChurch     = "find_a_church"
        case bibleStudy     = "join_a_bible_study"
        case visitSunday    = "visit_this_sunday"
        case watchOnline    = "watch_online"
        case findCommunity  = "find_community"
        case talkToPastor   = "talk_to_a_pastor"
        case serve          = "serve_somewhere"
        case newToFaith     = "new_to_faith"

        var displayName: String {
            switch self {
            case .findChurch:    return "Find a church"
            case .bibleStudy:    return "Join a Bible study"
            case .visitSunday:   return "Visit this Sunday"
            case .watchOnline:   return "Watch online"
            case .findCommunity: return "Find community"
            case .talkToPastor:  return "Talk to a pastor"
            case .serve:         return "Serve somewhere"
            case .newToFaith:    return "New to faith"
            }
        }
    }

    enum FitChip: String, Codable, CaseIterable {
        case nearMe             = "near_me"
        case serviceToday       = "service_today"
        case youngAdults        = "young_adults"
        case families
        case traditional
        case modernWorship      = "modern_worship"
        case smallChurch        = "small_church"
        case largeChurch        = "large_church"
        case nonDenominational  = "non_denominational"
        case baptist            = "baptist"
        case methodist          = "methodist"
        case pentecostal        = "pentecostal"
        case catholic           = "catholic"
        case orthodox           = "orthodox"
        case spanishService     = "spanish_service"
        case aslAvailable       = "asl_available"

        var displayName: String {
            switch self {
            case .nearMe:            return "Near me"
            case .serviceToday:      return "Service today"
            case .youngAdults:       return "Young adults"
            case .families:          return "Families"
            case .traditional:       return "Traditional"
            case .modernWorship:     return "Modern worship"
            case .smallChurch:       return "Small church"
            case .largeChurch:       return "Large church"
            case .nonDenominational: return "Non-denominational"
            case .baptist:           return "Baptist"
            case .methodist:         return "Methodist"
            case .pentecostal:       return "Pentecostal"
            case .catholic:          return "Catholic"
            case .orthodox:          return "Orthodox"
            case .spanishService:    return "Spanish service"
            case .aslAvailable:      return "ASL available"
            }
        }

        /// Which intents make this chip relevant to show
        var relevantIntents: [SeekerIntent] {
            switch self {
            case .nearMe, .serviceToday, .traditional, .modernWorship,
                 .smallChurch, .largeChurch, .nonDenominational, .baptist,
                 .methodist, .pentecostal, .catholic, .orthodox:
                return SeekerIntent.allCases
            case .youngAdults:          return [.findChurch, .findCommunity, .bibleStudy]
            case .families:             return [.findChurch, .visitSunday, .findCommunity]
            case .spanishService:       return [.findChurch, .visitSunday]
            case .aslAvailable:         return SeekerIntent.allCases
            }
        }
    }

    enum ComfortChip: String, Codable, CaseIterable {
        case showParking         = "show_parking"
        case showWhatToExpect    = "show_what_to_expect"
        case needChildcare       = "need_childcare"
        case preferSmallerGroups = "prefer_smaller_groups"
        case wantBibleStudyFirst = "want_bible_study_first"
        case needLivestreamFirst = "need_livestream_first"
        case privateRecs         = "private_recommendations_only"
        case noLocation          = "dont_share_location"

        var displayName: String {
            switch self {
            case .showParking:         return "Show parking info"
            case .showWhatToExpect:    return "Show what to expect"
            case .needChildcare:       return "Need childcare"
            case .preferSmallerGroups: return "Prefer smaller groups"
            case .wantBibleStudyFirst: return "Want Bible study first"
            case .needLivestreamFirst: return "Need livestream first"
            case .privateRecs:         return "Private recommendations only"
            case .noLocation:          return "Don't share my location"
            }
        }

        var isFunctional: Bool {
            self == .privateRecs || self == .noLocation
        }
    }

    struct InferredSignal: Codable {
        let signal: String
        let source: String           // "church_note", "sermon_watch", "church_save"
        let inferredAt: Date
    }
}

// MARK: - VisitPlan (Commitment Object)

// NOTE: `VisitPlan` is defined in FirstVisitCompanionModels.swift (ALREADY-GOOD).
// Wave 1 extends it below. Decision logged in DECISIONS.md (D-01-ext).

extension VisitPlan {
    /// Whether this plan is for an upcoming service (planned or reminded, service day ≥ today).
    var isUpcoming: Bool {
        guard status == .planned || status == .reminded else { return false }
        return true
    }
}

extension VisitPlanStatus {
    /// Map legacy status names to Wave 1 contract names.
    var isActive: Bool { self == .planned || self == .reminded || self == .dayOf }
    var isComplete: Bool { self == .visited }
}

// MARK: - ClaimRequest

/// Submitted by a user claiming ownership of an unclaimed church profile.
struct ClaimRequest: Codable {
    let id: String
    let churchId: String
    let claimantUid: String
    let verificationMethod: ChurchObject.VerificationTier
    let emailDomain: String?         // for domain-match verification
    let einProvided: String?         // hashed EIN — CF compares against IRS
    let documentURLs: [String]       // Storage URLs of submitted docs
    let status: ClaimStatus
    let submittedAt: Date
    var reviewedAt: Date?
    var reviewerNote: String?

    enum ClaimStatus: String, Codable {
        case submitted = "submitted"
        case inReview  = "in_review"
        case approved  = "approved"
        case denied    = "denied"
    }
}
