// AmenGatheringModels.swift
// AMENAPP — Amen Gatherings Data Models
//
// Matches the backend TypeScript AmenGathering schema exactly.
// All mutations go through AmenGatheringService callables, never direct Firestore.

import Foundation

// MARK: - Gathering Type

enum AmenGatheringType: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }

    case prayerNight          = "prayerNight"
    case bibleStudy           = "bibleStudy"
    case worshipNight         = "worshipNight"
    case churchService        = "churchService"
    case smallGroup           = "smallGroup"
    case volunteerOpportunity = "volunteerOpportunity"
    case retreat              = "retreat"
    case `class`              = "class"
    case missionTrip          = "missionTrip"
    case custom               = "custom"

    var displayName: String {
        switch self {
        case .prayerNight:          return "Prayer Night"
        case .bibleStudy:           return "Bible Study"
        case .worshipNight:         return "Worship Night"
        case .churchService:        return "Church Service"
        case .smallGroup:           return "Small Group"
        case .volunteerOpportunity: return "Volunteer Opportunity"
        case .retreat:              return "Retreat"
        case .class:                return "Class"
        case .missionTrip:          return "Mission Trip"
        case .custom:               return "Gathering"
        }
    }

    var systemImage: String {
        switch self {
        case .prayerNight:          return "hands.sparkles"
        case .bibleStudy:           return "book.circle"
        case .worshipNight:         return "music.note.list"
        case .churchService:        return "building.columns"
        case .smallGroup:           return "person.3"
        case .volunteerOpportunity: return "heart.circle"
        case .retreat:              return "mountain.2"
        case .class:                return "graduationcap"
        case .missionTrip:          return "airplane.circle"
        case .custom:               return "star.circle"
        }
    }

    var defaultAccessMode: AmenAccessMode {
        switch self {
        case .smallGroup, .retreat, .missionTrip, .volunteerOpportunity: return .request
        default: return .join
        }
    }

    var isSensitiveByDefault: Bool {
        switch self {
        case .smallGroup, .prayerNight, .retreat: return true
        default: return false
        }
    }
}

// MARK: - Host Type

enum AmenGatheringHostType: String, Codable, CaseIterable {
    case user         = "user"
    case church       = "church"
    case organization = "organization"
    case smallGroup   = "smallGroup"

    var displayName: String {
        switch self {
        case .user:         return "Personal"
        case .church:       return "Church"
        case .organization: return "Organization"
        case .smallGroup:   return "Small Group"
        }
    }
}

// MARK: - Status

enum AmenGatheringStatus: String, Codable {
    case draft     = "draft"
    case published = "published"
    case cancelled = "cancelled"
    case completed = "completed"
    case archived  = "archived"

    var displayName: String {
        switch self {
        case .draft:     return "Draft"
        case .published: return "Published"
        case .cancelled: return "Cancelled"
        case .completed: return "Completed"
        case .archived:  return "Archived"
        }
    }

    var isActive: Bool { self == .published }
}

// MARK: - Visibility

enum AmenGatheringVisibility: String, Codable, CaseIterable {
    case `public`  = "public"
    case unlisted  = "unlisted"
    case `private` = "private"
    case roleGated = "roleGated"

    var displayName: String {
        switch self {
        case .public:   return "Public"
        case .unlisted: return "Unlisted"
        case .private:  return "Private"
        case .roleGated: return "Role-Gated"
        }
    }

    var systemImage: String {
        switch self {
        case .public:   return "globe"
        case .unlisted: return "link"
        case .private:  return "lock.fill"
        case .roleGated: return "person.badge.key.fill"
        }
    }
}

// MARK: - Location Type

enum AmenGatheringLocationType: String, Codable, CaseIterable {
    case physical = "physical"
    case online   = "online"
    case hybrid   = "hybrid"
    case tbd      = "tbd"

    var displayName: String {
        switch self {
        case .physical: return "In Person"
        case .online:   return "Online"
        case .hybrid:   return "Hybrid"
        case .tbd:      return "Location TBD"
        }
    }

    var systemImage: String {
        switch self {
        case .physical: return "mappin.circle.fill"
        case .online:   return "video.circle.fill"
        case .hybrid:   return "arrow.triangle.merge"
        case .tbd:      return "questionmark.circle"
        }
    }
}

// MARK: - RSVP Status

enum AmenGatheringRsvpStatus: String, Codable {
    case going      = "going"
    case maybe      = "maybe"
    case declined   = "declined"
    case waitlisted = "waitlisted"
    case pending    = "pending"

    var displayName: String {
        switch self {
        case .going:      return "Going"
        case .maybe:      return "Maybe"
        case .declined:   return "Can't Attend"
        case .waitlisted: return "Waitlisted"
        case .pending:    return "Pending Approval"
        }
    }

    var actionLabel: String {
        switch self {
        case .going:      return "I'm Going"
        case .maybe:      return "Maybe"
        case .declined:   return "Can't Make It"
        case .waitlisted: return "Join Waitlist"
        case .pending:    return "Request Access"
        }
    }

    var systemImage: String {
        switch self {
        case .going:      return "checkmark.circle.fill"
        case .maybe:      return "questionmark.circle"
        case .declined:   return "xmark.circle"
        case .waitlisted: return "clock.circle"
        case .pending:    return "hourglass"
        }
    }
}

// MARK: - Guest List Visibility

enum AmenGatheringGuestListVisibility: String, Codable, CaseIterable {
    case `public`      = "public"
    case attendeesOnly = "attendeesOnly"
    case hostsOnly     = "hostsOnly"

    var displayName: String {
        switch self {
        case .public:       return "Visible to Everyone"
        case .attendeesOnly: return "Attendees Only"
        case .hostsOnly:    return "Hosts Only"
        }
    }
}

// MARK: - Answers Visibility

enum AmenGatheringAnswersVisibility: String, Codable, CaseIterable {
    case hostsOnly      = "hostsOnly"
    case attendeeSummary = "attendeeSummary"
    case `private`      = "private"

    var displayName: String {
        switch self {
        case .hostsOnly:       return "Hosts Only"
        case .attendeeSummary: return "Summary to Attendees"
        case .private:         return "Private"
        }
    }
}

// MARK: - Question Type

enum AmenGatheringQuestionType: String, Codable, CaseIterable {
    case shortText    = "shortText"
    case longText     = "longText"
    case singleChoice = "singleChoice"
    case multiChoice  = "multiChoice"
    case boolean      = "boolean"

    var displayName: String {
        switch self {
        case .shortText:    return "Short Answer"
        case .longText:     return "Long Answer"
        case .singleChoice: return "Single Choice"
        case .multiChoice:  return "Multiple Choice"
        case .boolean:      return "Yes / No"
        }
    }
}

// MARK: - Sub-Structs

struct AmenGatheringLocation: Codable, Hashable {
    var type: AmenGatheringLocationType
    var name: String?
    var address: String?
    var city: String?
    var region: String?
    var country: String?
    var onlineUrl: String?
    var directionsUrl: String?

    var displaySummary: String {
        switch type {
        case .online:   return "Online"
        case .hybrid:   return name.map { "Hybrid · \($0)" } ?? "Hybrid"
        case .tbd:      return "Location TBD"
        case .physical: return name ?? city ?? "In Person"
        }
    }
}

struct AmenGatheringTheme: Codable {
    var coverImageUrl: String?
    var gradientName: String?
    var templateId: String?
    var iconName: String?
    var scriptureReference: String?
    var scriptureTextPreview: String?
}

struct AmenGatheringDetails: Codable {
    var speaker: String?
    var leader: String?
    var whatToBring: String?
    var childcare: String?
    var parking: String?
    var accessibilityNotes: String?
    var contactEmail: String?
    var contactPhone: String?
}

struct AmenGatheringSpiritual: Codable {
    var prayerFocus: String?
    var scriptureReference: String?
    var allowPrayerRequests: Bool
    var allowPastoralFollowUp: Bool
    var allowTestimonies: Bool
}

struct AmenGatheringRsvpSettings: Codable {
    var allowGoing: Bool
    var allowMaybe: Bool
    var allowDecline: Bool
    var questionsEnabled: Bool
    var guestListVisibility: AmenGatheringGuestListVisibility
    var answersVisibility: AmenGatheringAnswersVisibility
}

struct AmenGatheringAccess: Codable {
    var accessPassEnabled: Bool
    var defaultAccessPassId: String?
    var mode: AmenAccessMode
    var requiresApproval: Bool
    var allowGuestPreview: Bool
    var allowUnauthenticatedRsvp: Bool
}

struct AmenGatheringConnectedTargets: Codable {
    var spaceId: String?
    var discussionId: String?
    var churchId: String?
    var organizationId: String?
    var smallGroupId: String?
    var prayerRoomId: String?
    var sermonNotesId: String?

    var isEmpty: Bool {
        spaceId == nil && discussionId == nil && churchId == nil &&
        organizationId == nil && smallGroupId == nil &&
        prayerRoomId == nil && sermonNotesId == nil
    }
}

struct AmenGatheringCounts: Codable {
    var going: Int
    var maybe: Int
    var declined: Int
    var invited: Int
    var pendingRequests: Int
    var waitlisted: Int
    var checkedIn: Int
    var comments: Int
    var photos: Int

    static let empty = AmenGatheringCounts(
        going: 0, maybe: 0, declined: 0, invited: 0,
        pendingRequests: 0, waitlisted: 0, checkedIn: 0,
        comments: 0, photos: 0
    )
}

struct AmenGatheringSafety: Codable {
    var isSensitive: Bool
    var isYouthRelated: Bool
    var requiresModeration: Bool
    var allowPublicComments: Bool
    var prayerRequestsPrivateByDefault: Bool
}

// MARK: - Core Gathering Model

struct AmenGathering: Codable, Identifiable {
    var id: String { gatheringId }

    let gatheringId: String
    var title: String
    var description: String?
    var type: AmenGatheringType
    var hostType: AmenGatheringHostType
    var hostId: String
    var hostName: String
    var hostVerified: Bool
    var hostPhotoURL: String?
    var createdByUid: String
    var startAt: Date
    var endAt: Date?
    var timezone: String?
    var location: AmenGatheringLocation
    var visibility: AmenGatheringVisibility
    var status: AmenGatheringStatus
    var capacity: Int?
    var waitlistEnabled: Bool
    var access: AmenGatheringAccess
    var connectedTargets: AmenGatheringConnectedTargets
    var theme: AmenGatheringTheme
    var details: AmenGatheringDetails
    var spiritual: AmenGatheringSpiritual
    var rsvpSettings: AmenGatheringRsvpSettings
    var counts: AmenGatheringCounts
    var safety: AmenGatheringSafety

    var isUpcoming: Bool { startAt > Date() }

    var countdownLabel: String? {
        let interval = startAt.timeIntervalSinceNow
        guard interval > 0 && interval < 7 * 24 * 3600 else { return nil }
        let hours = Int(interval / 3600)
        if hours < 1 { return "Starting soon" }
        if hours < 24 { return "In \(hours)h" }
        return "In \(hours / 24)d"
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startAt)
    }
}

// MARK: - RSVP Record

struct AmenGatheringRsvp: Codable, Identifiable {
    var id: String { uid }

    let uid: String
    let gatheringId: String
    var status: AmenGatheringRsvpStatus
    var displayName: String?
    var photoURL: String?
    var requestedPrayer: Bool?
    var requestedPastoralFollowUp: Bool?
    var checkedInAt: Date?
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - Question

struct AmenGatheringQuestion: Codable, Identifiable {
    var id: String { questionId }

    let questionId: String
    var prompt: String
    var type: AmenGatheringQuestionType
    var options: [String]?
    var required: Bool
    var sensitive: Bool
    var sortOrder: Int
}

// MARK: - Feed Card (privacy-shaped preview for lists)

struct AmenGatheringFeedCard: Codable, Identifiable {
    var id: String { gatheringId }

    let gatheringId: String
    var title: String
    var type: AmenGatheringType
    var hostName: String
    var hostVerified: Bool
    var hostPhotoURL: String?
    var coverImageUrl: String?
    var gradientName: String?
    var startAt: Date
    var location: AmenGatheringLocation
    var visibility: AmenGatheringVisibility
    var accessMode: AmenAccessMode
    var rsvpCount: Int
    var userRsvpStatus: AmenGatheringRsvpStatus?
    var isSaved: Bool
    var scriptureReference: String?

    var countdownLabel: String? {
        let interval = startAt.timeIntervalSinceNow
        guard interval > 0 && interval < 7 * 24 * 3600 else { return nil }
        let hours = Int(interval / 3600)
        if hours < 1 { return "Soon" }
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

// MARK: - Create Input

struct AmenCreateGatheringInput: Codable {
    var title: String
    var type: AmenGatheringType
    var hostType: AmenGatheringHostType
    var hostId: String
    var description: String?
    var startAt: Date
    var endAt: Date?
    var timezone: String?
    var location: AmenGatheringLocation
    var visibility: AmenGatheringVisibility
    var theme: AmenGatheringTheme
    var details: AmenGatheringDetails
    var spiritual: AmenGatheringSpiritual
    var rsvpSettings: AmenGatheringRsvpSettings
    var safety: AmenGatheringSafety
    var connectedTargets: AmenGatheringConnectedTargets
    var access: AmenGatheringAccess
    var capacity: Int?
    var waitlistEnabled: Bool
    var questions: [AmenCreateQuestionInput]
    var publishImmediately: Bool

    static func empty() -> AmenCreateGatheringInput {
        let soon = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return AmenCreateGatheringInput(
            title: "",
            type: .prayerNight,
            hostType: .user,
            hostId: "",
            startAt: soon,
            location: AmenGatheringLocation(type: .physical),
            visibility: .public,
            theme: AmenGatheringTheme(),
            details: AmenGatheringDetails(),
            spiritual: AmenGatheringSpiritual(
                allowPrayerRequests: true,
                allowPastoralFollowUp: true,
                allowTestimonies: true
            ),
            rsvpSettings: AmenGatheringRsvpSettings(
                allowGoing: true,
                allowMaybe: true,
                allowDecline: true,
                questionsEnabled: false,
                guestListVisibility: .attendeesOnly,
                answersVisibility: .hostsOnly
            ),
            safety: AmenGatheringSafety(
                isSensitive: false,
                isYouthRelated: false,
                requiresModeration: false,
                allowPublicComments: true,
                prayerRequestsPrivateByDefault: true
            ),
            connectedTargets: AmenGatheringConnectedTargets(),
            access: AmenGatheringAccess(
                accessPassEnabled: true,
                mode: .join,
                requiresApproval: false,
                allowGuestPreview: true,
                allowUnauthenticatedRsvp: false
            ),
            waitlistEnabled: false,
            questions: [],
            publishImmediately: false
        )
    }
}

struct AmenCreateQuestionInput: Codable {
    var prompt: String
    var type: AmenGatheringQuestionType
    var options: [String]
    var required: Bool
    var sensitive: Bool
    var sortOrder: Int
}

// MARK: - Create Response

struct AmenCreateGatheringResponse: Codable {
    let gatheringId: String
    let accessPassId: String?
    let shareLink: String?
    let qrPayload: String?
    let universalLink: String?
}

// MARK: - Input Wrappers

struct AmenGatheringUpdateInput {
    let gatheringId: String
    var title: String?
    var description: String?
    var startAt: Date?
    var endAt: Date?
    var location: AmenGatheringLocation?
    var visibility: AmenGatheringVisibility?
    var details: AmenGatheringDetails?
    var spiritual: AmenGatheringSpiritual?
    var theme: AmenGatheringTheme?
    var rsvpSettings: AmenGatheringRsvpSettings?
    var access: AmenGatheringAccess?
}

struct AmenGatheringRsvpInput {
    let gatheringId: String
    let status: AmenGatheringRsvpStatus
    var answers: [String: String]?
    var requestedPrayer: Bool?
    var requestedPastoralFollowUp: Bool?
}

struct AmenGatheringSendUpdateInput {
    let gatheringId: String
    let title: String
    let body: String
    var deepLinkPath: String?
}

// MARK: - Error

enum AmenGatheringError: LocalizedError {
    case notAuthenticated
    case permissionDenied
    case notFound
    case capacityFull
    case cancelled
    case invalidInput(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:   return "Sign in to continue."
        case .permissionDenied:   return "You don't have permission to do that."
        case .notFound:           return "This gathering could not be found."
        case .capacityFull:       return "This gathering is full. You've been added to the waitlist."
        case .cancelled:          return "This gathering has been cancelled."
        case .invalidInput(let m): return m
        case .unknown(let m):     return m
        }
    }

    var userFacingTitle: String {
        switch self {
        case .notAuthenticated: return "Sign In Required"
        case .permissionDenied: return "Not Permitted"
        case .notFound:         return "Not Found"
        case .capacityFull:     return "Full — Waitlisted"
        case .cancelled:        return "Cancelled"
        case .invalidInput:     return "Check Your Input"
        case .unknown:          return "Something Went Wrong"
        }
    }

    static func from(code: String) -> AmenGatheringError {
        switch code {
        case "auth-required":     return .notAuthenticated
        case "permission-denied": return .permissionDenied
        case "not-found":         return .notFound
        case "capacity-full":     return .capacityFull
        case "cancelled":         return .cancelled
        default:                  return .unknown(code)
        }
    }
}
