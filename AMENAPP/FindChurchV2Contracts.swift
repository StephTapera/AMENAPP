//
//  FindChurchV2Contracts.swift
//  AMENAPP
//
//  Find a Church v2 — Swift MIRROR of functions/src/contracts/church.ts (SOURCE OF TRUTH).
//  Wave 0 contract freeze per FIND_CHURCH_V2_SPEC.md §2–§4.
//
//  Field names are IDENTICAL to the TypeScript (camelCase) so Codable decodes the
//  callable JSON directly. Types are namespaced under the `FCV2` enum to avoid
//  collision with the existing v1 `Church` / `ServiceTime` models (FindChurchView.swift).
//  Namespacing changes type NAMES only — wire field names are unchanged, so the
//  mirror stays exact. Nothing here is wired into a view or service yet.
//
//  NOT YET ADDED TO THE XCODE TARGET — see Wave 0 report (pbxproj add is a human step).
//

import Foundation

/// Namespace for all Find a Church v2 wire contracts.
enum FCV2 {

    // MARK: - shared

    enum Denomination: String, Codable, CaseIterable {
        case non_denominational, baptist, methodist, presbyterian
        case lutheran, pentecostal, catholic, orthodox, anglican
        case reformed, anabaptist, bible_church, other
    }

    struct GeoPointH: Codable, Hashable {
        let lat: Double
        let lng: Double
        let geohash: String        // geofire-common encodeGeohash(), precision 9
    }

    enum WorshipStyle: String, Codable {
        case traditional, contemporary, blended, liturgical
    }

    // MARK: - service times

    struct ServiceTime: Codable, Identifiable, Hashable {
        let id: String
        let dayOfWeek: Int         // 0 = Sunday ... 6
        let startLocal: String     // "10:30" 24h
        let durationMinutes: Int
        let timezone: String       // IANA
        let language: String       // ISO-639-1
        let style: WorshipStyle?
        let isOnline: Bool
        let livestreamUrl: String?
        let childCheckIn: Bool
    }

    // MARK: - safety

    struct ChurchSafety: Codable, Hashable {
        enum BackgroundCheckPolicy: String, Codable {
            case all_volunteers, child_facing, none, unspecified
        }
        let hasChildSafetyPolicy: Bool
        let childSafetyPolicyUrl: String?
        let backgroundCheckPolicy: BackgroundCheckPolicy
    }

    struct ChurchAccessibility: Codable, Hashable {
        enum Parking: String, Codable {
            case lot, street, garage, none, unspecified
        }
        let wheelchair: Bool
        let hearingLoop: Bool
        let aslInterpreted: Bool
        let parking: Parking
    }

    enum VerificationStatus: String, Codable {
        case unverified, pending, verified, rejected
    }

    enum ReportState: String, Codable {
        case clear, under_review, restricted
    }

    enum MediaState: String, Codable {
        case none, pending_gate, approved, blocked
    }

    // MARK: - core doc

    struct Address: Codable, Hashable {
        let line1: String
        let city: String
        let region: String
        let postal: String
        let country: String
    }

    struct Verification: Codable, Hashable {
        enum Method: String, Codable { case domain, doc, manual }
        let status: VerificationStatus
        let method: Method?
        let verifiedAt: Double?     // epoch ms; SERVER-ONLY writable
    }

    struct Church: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        let denomination: Denomination
        let bio: String?
        let statementOfFaithUrl: String?

        let location: GeoPointH
        let address: Address
        let approxLocationOnly: Bool

        let heroMediaRef: String?
        let heroMediaState: MediaState

        let ministries: [String]
        let languages: [String]
        let accessibility: ChurchAccessibility
        let safety: ChurchSafety

        let verification: Verification
        let reportState: ReportState

        let profileCompleteness: Double   // 0..1
        let followerCount: Int

        let websiteUrl: String?
        let socialLinks: [String: String]?
        let givingUrl: String?
        let contactEmail: String?

        let createdAt: Double
        let updatedAt: Double
    }

    enum MinistryKey: String, Codable {
        case kids, youth, young_adults, mens, womens
        case recovery, prayer, worship, counseling, spanish
    }

    // MARK: - subcollections

    struct Ministry: Codable, Identifiable, Hashable {
        let id: String
        let key: MinistryKey
        let title: String
        let description: String?
        let ageRange: String?
        let meetsLabel: String?
        let contactEmail: String?
    }

    struct SmallGroup: Codable, Identifiable, Hashable {
        let id: String
        let churchId: String
        let title: String
        let type: String
        let description: String?
        let meetsLabel: String
        let location: GeoPointH?
        let isOnline: Bool
        let language: String
        let childFriendly: Bool
        let createdAt: Double
        let updatedAt: Double
    }

    struct ChurchEvent: Codable, Identifiable, Hashable {
        let id: String
        let churchId: String
        let title: String
        let description: String?
        let kind: String
        let startsAtIso: String
        let endsAtIso: String?
        let location: GeoPointH?
        let isOnline: Bool
        let registrationUrl: String?
        let createdAt: Double
        let updatedAt: Double
    }

    struct Sermon: Codable, Identifiable, Hashable {
        let id: String
        let churchId: String
        let title: String
        let speaker: String?
        let series: String?
        let scriptureRefs: [String]
        let datePreachedIso: String?
        let thumbnailMediaRef: String?
        let thumbnailMediaState: MediaState
        let audioUrl: String?
        let videoUrl: String?
        let createdAt: Double
        let updatedAt: Double
    }

    enum ChurchAdminRole: String, Codable {
        case owner, pastor, executive_admin, editor
    }

    struct ChurchAdmin: Codable, Hashable {
        let uid: String
        let churchId: String
        let role: ChurchAdminRole
        let addedAt: Double
    }

    // MARK: - user-owned subdocs

    struct SavedChurch: Codable, Hashable {
        let churchId: String
        let savedAt: Double
    }

    struct ChurchSearchHistoryEntry: Codable, Identifiable, Hashable {
        let id: String
        let term: String
        let resultChurchId: String?
        let searchedAt: Double
    }

    struct ChurchPreferences: Codable, Hashable {
        struct AccessibilityNeeds: Codable, Hashable {
            let wheelchair: Bool
            let hearingLoop: Bool
            let aslInterpreted: Bool
        }
        let denominations: [Denomination]
        let ministries: [MinistryKey]
        let languages: [String]
        let worshipStyles: [WorshipStyle]
        let accessibilityNeeds: AccessibilityNeeds
        let privateSearch: Bool
        let updatedAt: Double
    }

    struct VisitPlan: Codable, Identifiable, Hashable {
        let id: String
        let churchId: String
        let serviceTimeId: String?
        let plannedForIso: String
        let partySize: Int?
        let notes: String?
        let sharedWithChurch: Bool   // ALWAYS false for minors (§5.2)
        let createdAt: Double
        let updatedAt: Double
    }

    struct VisitorIntent: Codable, Identifiable, Hashable {
        let id: String
        let visitPlanId: String
        let plannedForIso: String
        let partySize: Int?
        let createdAt: Double
    }

    // MARK: - reports & verification

    enum ReportReason: String, Codable {
        case misleading_profile, impersonation, child_safety_concern
        case inappropriate_media, spam, other
    }

    struct ChurchReport: Codable, Identifiable, Hashable {
        enum State: String, Codable { case open, escalated, actioned, dismissed }
        let id: String
        let churchId: String
        let reporterUid: String
        let reason: ReportReason
        let details: String?
        let state: State
        let createdAt: Double
    }

    struct ChurchVerificationRequestDoc: Codable, Identifiable, Hashable {
        let id: String
        let churchId: String
        let requesterUid: String
        let method: Verification.Method
        let evidenceUrl: String?
        let status: VerificationStatus
        let createdAt: Double
    }

    // MARK: - discovery request/response (the brain)

    struct ChurchFilter: Codable, Hashable {
        enum Key: String, Codable {
            case near_me, open_sunday, service_today, kids, youth
            case young_adults, small_groups, bible_study, worship_night
            case online_service, denomination, non_denominational, verified
            case accessible, spanish_service, live_stream, counseling
            case parking, events
        }
        let key: Key
        let value: String?
    }

    struct LatLng: Codable, Hashable {
        let lat: Double
        let lng: Double
    }

    struct ChurchDiscoveryRequest: Codable {
        let center: LatLng
        let radiusMeters: Double
        let filters: [ChurchFilter]
        let nowIso: String
        let sessionId: String
    }

    struct NextService: Codable, Hashable {
        let serviceTimeId: String
        let startsInMinutes: Int
        let isOnline: Bool
    }

    enum Badge: String, Codable {
        case verified, kids_safe_policy, accessible, spanish, livestream, new
    }

    struct ChurchMatch: Codable, Identifiable, Hashable {
        var id: String { churchId }
        let churchId: String
        let distanceMeters: Double
        let score: Double
        let whyMatched: [String]      // max 3
        let nextService: NextService?
        let openNow: Bool
        let verified: Bool
        let badges: [Badge]
    }

    struct GuideCard: Codable, Identifiable, Hashable {
        enum Source: String, Codable { case editorial, algorithmic }
        let id: String
        let title: String
        let subtitle: String?
        let coverMediaRef: String?
        let churchIds: [String]
        let source: Source
    }

    struct SmallGroupMatch: Codable, Identifiable, Hashable {
        var id: String { groupId }
        let groupId: String
        let churchId: String
        let title: String
        let type: String
        let distanceMeters: Double
        let meetsLabel: String
    }

    struct EventMatch: Codable, Identifiable, Hashable {
        var id: String { eventId }
        let eventId: String
        let churchId: String
        let title: String
        let startsAtIso: String
        let distanceMeters: Double
        let kind: String
    }

    /// Discriminated union on `kind` — mirrors the TS `DiscoverySection`.
    enum DiscoverySection: Codable {
        case nearby([ChurchMatch])
        case servicesToday([ChurchMatch])
        case suggested([ChurchMatch])
        case smallGroups([SmallGroupMatch])
        case events([EventMatch])
        case guides([GuideCard])

        private enum CodingKeys: String, CodingKey { case kind, items }
        private enum Kind: String, Codable {
            case nearby
            case services_today
            case suggested
            case small_groups
            case events
            case guides
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(Kind.self, forKey: .kind)
            switch kind {
            case .nearby:        self = .nearby(try c.decode([ChurchMatch].self, forKey: .items))
            case .services_today: self = .servicesToday(try c.decode([ChurchMatch].self, forKey: .items))
            case .suggested:     self = .suggested(try c.decode([ChurchMatch].self, forKey: .items))
            case .small_groups:  self = .smallGroups(try c.decode([SmallGroupMatch].self, forKey: .items))
            case .events:        self = .events(try c.decode([EventMatch].self, forKey: .items))
            case .guides:        self = .guides(try c.decode([GuideCard].self, forKey: .items))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .nearby(let v):        try c.encode(Kind.nearby, forKey: .kind);        try c.encode(v, forKey: .items)
            case .servicesToday(let v): try c.encode(Kind.services_today, forKey: .kind); try c.encode(v, forKey: .items)
            case .suggested(let v):     try c.encode(Kind.suggested, forKey: .kind);     try c.encode(v, forKey: .items)
            case .smallGroups(let v):   try c.encode(Kind.small_groups, forKey: .kind);  try c.encode(v, forKey: .items)
            case .events(let v):        try c.encode(Kind.events, forKey: .kind);        try c.encode(v, forKey: .items)
            case .guides(let v):        try c.encode(Kind.guides, forKey: .kind);        try c.encode(v, forKey: .items)
            }
        }
    }

    struct ContextChip: Codable, Hashable {
        let dayLabel: String
        let soonCount: Int
        let radiusLabel: String
    }

    struct CalmCap: Codable, Hashable {
        let maxItemsPerSection: Int
        let infiniteScroll: Bool   // always false
    }

    struct ChurchDiscoveryResponse: Codable {
        let contextChip: ContextChip?
        let sections: [DiscoverySection]
        let calmCap: CalmCap
    }

    // MARK: - callable request/response — §3

    struct SearchChurchesRequest: Codable {
        let q: String
        let center: LatLng
        let radiusMeters: Double
        let filters: [ChurchFilter]
        let page: Int
    }

    struct SearchChurchesResponse: Codable {
        let items: [ChurchMatch]
        let nextPage: Int?
    }

    struct ChurchProfile: Codable {
        let church: Church
        let serviceTimes: [ServiceTime]
        let ministries: [Ministry]
        let upcomingEvents: [ChurchEvent]
        let sermons: [Sermon]
    }

    struct PlanVisitRequest: Codable {
        let churchId: String
        let serviceTimeId: String?
        let plannedForIso: String
        let partySize: Int?
        let notes: String?
        let shareWithChurch: Bool
    }

    struct PlanVisitResponse: Codable {
        let visitPlanId: String
        let sharedWithChurch: Bool
    }

    struct ChurchVerificationRequest: Codable {
        let churchId: String
        let method: Verification.Method
        let evidenceUrl: String?
    }

    struct ChurchClaimRequest: Codable {
        let churchId: String?
        let proposedName: String?
        let role: ChurchAdminRole
        let contactEmail: String
        let evidenceUrl: String?
    }
}
