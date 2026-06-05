// AmenChurchModels.swift
// AMEN Community OS — Church OS (Phase 3 / Agent A8)
//
// Canonical Church OS domain models. Extends the stub AmenChurch in AmenCoreModels.swift
// with the full rich Church OS object set (campuses, service times, passport stamps, etc.).
//
// Naming contract:
//   - AmenChurch (stub) lives in AmenCoreModels.swift — do NOT redeclare here.
//   - This file adds ChurchOSProfile (the rich presentation object used by Church OS views),
//     ChurchCampus, ServiceTime, ServiceStyle, ChurchSize, ChurchPassportStamp, ChurchPassport,
//     and VisitReadiness.
//   - followersCount / memberCount / visitCount are private and NEVER shown in any UI.
//
// Design rules:
//   - All counts that represent vanity metrics are marked: PRIVATE — never surfaced
//   - Church passport is private by default (isPrivate = true)
//   - Soft-delete only (isDeleted flag)

import Foundation
import CoreLocation

// MARK: - ChurchSize

enum ChurchSize: String, Codable, Sendable, CaseIterable {
    case micro        = "micro"
    case small        = "small"
    case medium       = "medium"
    case large        = "large"
    case megachurch   = "megachurch"
    case multisite    = "multisite"

    var displayName: String {
        switch self {
        case .micro:      return "Micro (< 50)"
        case .small:      return "Small (50–200)"
        case .medium:     return "Medium (200–500)"
        case .large:      return "Large (500–2 000)"
        case .megachurch: return "Megachurch (2 000+)"
        case .multisite:  return "Multi-site"
        }
    }
}

// MARK: - ServiceStyle

enum ServiceStyle: String, Codable, Sendable, CaseIterable {
    case contemporary      = "contemporary"
    case traditional       = "traditional"
    case blended           = "blended"
    case liturgical        = "liturgical"
    case charismatic       = "charismatic"
    case reformed          = "reformed"
    case nondenominational = "nondenominational"

    var displayName: String {
        switch self {
        case .contemporary:      return "Contemporary"
        case .traditional:       return "Traditional"
        case .blended:           return "Blended"
        case .liturgical:        return "Liturgical"
        case .charismatic:       return "Charismatic"
        case .reformed:          return "Reformed"
        case .nondenominational: return "Non-Denominational"
        }
    }
}

// MARK: - ServiceTime

struct ServiceTime: Codable, Identifiable, Sendable {
    var id: String
    var dayOfWeek: Int           // 0 = Sunday … 6 = Saturday
    var startTime: String        // e.g. "10:00 AM"
    var endTime: String?
    var location: String         // campus name or "Main Campus"
    var isOnline: Bool
    var streamUrl: String?
    var serviceStyle: ServiceStyle

    /// Human-readable day name derived from dayOfWeek.
    var dayName: String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard dayOfWeek >= 0, dayOfWeek < names.count else { return "" }
        return names[dayOfWeek]
    }
}

// MARK: - ChurchCampus

/// A single physical or online campus associated with a church.
/// phoneNumber is intentionally included — it is public org contact info.
struct ChurchCampus: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var address: String
    var city: String
    var state: String
    var zipCode: String
    var latitude: Double?
    var longitude: Double?
    var isPrimary: Bool
    var serviceTimes: [ServiceTime]
    var phoneNumber: String?   // public org contact info
    var websiteUrl: String?
}

// MARK: - ChurchOSProfile

/// Full Church OS presentation object used by AmenChurchService and all Church OS views.
/// Distinct from the AmenCoreModels AmenChurch stub (Firestore schema mirror).
///
/// Anti-engagement invariants (NEVER expose in UI):
///   memberCount    — PRIVATE, never shown
///   followersCount — PRIVATE, never shown
struct ChurchOSProfile: Identifiable, Codable, Sendable {
    var id: String
    var name: String
    var denomination: String?
    var bio: String
    var coverImageUrl: String?
    var logoUrl: String?
    var campuses: [ChurchCampus]
    var size: ChurchSize
    var foundedYear: Int?
    var seniorPastorName: String?
    var website: String?
    var socialLinks: [String: String]
    var isVerified: Bool
    var verificationBadge: String?
    var missionStatement: String?
    var sermonSeriesRef: String?
    // PRIVATE — never shown publicly (anti-engagement)
    private(set) var memberCount: Int
    private(set) var followersCount: Int
    var givingEnabled: Bool
    var givingPlatformRef: String?
    var prayerRequestsEnabled: Bool
    var churchNotesEnabled: Bool
    var createdBy: String
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var isActive: Bool

    /// Convenience: today's service times across all campuses.
    var serviceTimesToday: [ServiceTime] {
        let todayWeekday = Calendar.current.component(.weekday, from: Date()) - 1 // Sunday=0
        return campuses.flatMap { $0.serviceTimes.filter { $0.dayOfWeek == todayWeekday } }
    }
}

// MARK: - ChurchPassportStamp

/// A single visit stamp on a user's Church Passport.
/// isPrivate defaults to true — stamps are never shared without explicit user action.
struct ChurchPassportStamp: Codable, Identifiable, Sendable {
    var id: String
    var churchId: String
    var churchName: String
    var churchLogoUrl: String?
    var visitDate: Date
    var notes: String?
    var isPrivate: Bool   // private by default

    init(
        id: String = UUID().uuidString,
        churchId: String,
        churchName: String,
        churchLogoUrl: String? = nil,
        visitDate: Date,
        notes: String? = nil,
        isPrivate: Bool = true
    ) {
        self.id = id
        self.churchId = churchId
        self.churchName = churchName
        self.churchLogoUrl = churchLogoUrl
        self.visitDate = visitDate
        self.notes = notes
        self.isPrivate = isPrivate
    }
}

// MARK: - ChurchPassport

/// A user's complete church visit history. Private by default.
/// visitCount is PRIVATE — never shown publicly (anti-engagement).
struct ChurchPassport: Codable, Identifiable, Sendable {
    var id: String               // = userId
    var userId: String
    var stamps: [ChurchPassportStamp]
    var currentChurchId: String?
    var homeChurchId: String?
    var isPrivate: Bool
    // PRIVATE — never shown publicly (anti-engagement)
    private(set) var visitCount: Int
    var createdAt: Date
    var updatedAt: Date

    /// Stamps sorted most-recent first; optionally including private stamps.
    func visibleStamps(showingPrivate: Bool) -> [ChurchPassportStamp] {
        let filtered = showingPrivate ? stamps : stamps.filter { !$0.isPrivate }
        return filtered.sorted { $0.visitDate > $1.visitDate }
    }
}

// MARK: - VisitReadiness

/// What to expect on a first visit to a specific church.
struct VisitReadiness: Sendable {
    let churchId: String
    let firstTimerTips: [String]
    let serviceTimeToday: ServiceTime?
    let parkingInfo: String?
    let childcareAvailable: Bool
    let accessibilityInfo: String?

    var isReadyToVisit: Bool { serviceTimeToday != nil }
}
