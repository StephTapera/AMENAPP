// SpaceOSModels.swift
// AMEN SpacesOS — All supporting models for the Smart Dashboard and role-aware composer.
//
// Design constraints:
//   - Pure model layer — no SwiftUI imports, no Firebase imports.
//   - Privacy rule: SpacePrayerRequest.creatorName must NEVER be exposed
//     unless isAnonymous == false.
//   - All models supply a static .preview factory for canvas/test use.
//   - SpaceMemberRole drives action visibility; never infer role client-side for security.

import Foundation

// MARK: - SpaceMemberRole

enum SpaceMemberRole: String, Codable, CaseIterable, Identifiable {
    case pastor
    case admin
    case leader
    case member
    case guest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pastor:  return "Pastor"
        case .admin:   return "Admin"
        case .leader:  return "Leader"
        case .member:  return "Member"
        case .guest:   return "Guest"
        }
    }

    /// Whether this role can post announcements directly (no approval queue).
    var canPostAnnouncement: Bool {
        switch self {
        case .pastor, .admin: return true
        default: return false
        }
    }

    /// Whether this role can post announcements that go into an approval queue.
    var canDraftAnnouncement: Bool {
        self == .leader
    }

    var canManageMembers: Bool {
        switch self {
        case .pastor, .admin: return true
        default: return false
        }
    }

    var canViewAnalytics: Bool {
        switch self {
        case .pastor, .admin: return true
        default: return false
        }
    }

    var canCreateEvent: Bool {
        switch self {
        case .pastor, .admin, .leader: return true
        default: return false
        }
    }

    var canCreatePost: Bool {
        switch self {
        case .pastor, .admin, .leader, .member: return true
        case .guest: return false
        }
    }

    var canRequestPrayer: Bool {
        switch self {
        case .pastor, .admin, .leader, .member: return true
        case .guest: return false
        }
    }

    var canRSVP: Bool {
        switch self {
        case .pastor, .admin, .leader, .member: return true
        case .guest: return false
        }
    }
}

// MARK: - SpacePostType

enum SpacePostType: String, CaseIterable, Identifiable {
    case discussion
    case announcement
    case event
    case prayerRoom
    case study
    case poll
    case resource

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .discussion:   return "Discussion"
        case .announcement: return "Announcement"
        case .event:        return "Event"
        case .prayerRoom:   return "Prayer Room"
        case .study:        return "Study"
        case .poll:         return "Poll"
        case .resource:     return "Resource"
        }
    }

    var icon: String {
        switch self {
        case .discussion:   return "bubble.left.and.bubble.right.fill"
        case .announcement: return "megaphone.fill"
        case .event:        return "calendar.badge.plus"
        case .prayerRoom:   return "hands.sparkles.fill"
        case .study:        return "text.book.closed.fill"
        case .poll:         return "chart.bar.fill"
        case .resource:     return "books.vertical.fill"
        }
    }
}

// MARK: - SpaceAudienceType

enum SpaceAudienceType: String, CaseIterable, Identifiable {
    case spaceMembers
    case leadersOnly
    case publicWithPermission

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spaceMembers:         return "Space Members"
        case .leadersOnly:          return "Leaders Only"
        case .publicWithPermission: return "Public with Permission"
        }
    }

    var icon: String {
        switch self {
        case .spaceMembers:         return "person.3.fill"
        case .leadersOnly:          return "person.badge.key.fill"
        case .publicWithPermission: return "globe"
        }
    }
}

// MARK: - SpaceQuickAction

struct SpaceQuickAction: Identifiable {
    let id: String
    var label: String
    var icon: String
    var isEnabled: Bool
    var disabledReason: String?
    var action: () -> Void

    init(
        id: String = UUID().uuidString,
        label: String,
        icon: String,
        isEnabled: Bool = true,
        disabledReason: String? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.action = action
    }
}

// MARK: - SpaceAnnouncement

struct SpaceAnnouncement: Identifiable {
    let id: String
    var title: String
    var body: String
    var authorName: String
    var authorRole: SpaceMemberRole
    var isPinned: Bool
    var createdAt: Date
    var expiresAt: Date?

    static var preview: [SpaceAnnouncement] {
        [
            SpaceAnnouncement(
                id: "ann-1",
                title: "This Sunday: Guest Speaker Dr. Marcus Webb",
                body: "We're excited to welcome Dr. Webb for our Sunday morning service. Doors open at 9:45 AM.",
                authorName: "Pastor James",
                authorRole: .pastor,
                isPinned: true,
                createdAt: Date().addingTimeInterval(-86400),
                expiresAt: Date().addingTimeInterval(5 * 86400)
            ),
            SpaceAnnouncement(
                id: "ann-2",
                title: "Serve Team Sign-Up Closes Friday",
                body: "If you'd like to serve this month, make sure to sign up before Friday at noon.",
                authorName: "Sarah M.",
                authorRole: .admin,
                isPinned: false,
                createdAt: Date().addingTimeInterval(-3 * 86400),
                expiresAt: Date().addingTimeInterval(2 * 86400)
            )
        ]
    }
}

// MARK: - SpacePrayerRequest

/// Privacy rule: NEVER access or display creatorName when isAnonymous == true.
struct SpacePrayerRequest: Identifiable {
    let id: String
    var title: String
    var body: String
    /// Only safe to display when isAnonymous == false.
    private(set) var creatorName: String?
    var isAnonymous: Bool
    var prayerCount: Int
    var isActive: Bool
    var createdAt: Date

    /// Safe display name — returns "A member" when anonymous.
    var safeDisplayName: String {
        isAnonymous ? "A member" : (creatorName ?? "A member")
    }

    init(
        id: String,
        title: String,
        body: String,
        creatorName: String?,
        isAnonymous: Bool,
        prayerCount: Int,
        isActive: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.creatorName = isAnonymous ? nil : creatorName   // strip on init
        self.isAnonymous = isAnonymous
        self.prayerCount = prayerCount
        self.isActive = isActive
        self.createdAt = createdAt
    }

    static var preview: [SpacePrayerRequest] {
        [
            SpacePrayerRequest(
                id: "pr-1",
                title: "Healing for my mother",
                body: "My mother was diagnosed this week. Please pray for her recovery and peace for our family.",
                creatorName: nil,
                isAnonymous: true,
                prayerCount: 14,
                isActive: true,
                createdAt: Date().addingTimeInterval(-7200)
            ),
            SpacePrayerRequest(
                id: "pr-2",
                title: "Starting a new job next week",
                body: "Grateful and nervous. Asking for wisdom and God's favor in this new season.",
                creatorName: "David K.",
                isAnonymous: false,
                prayerCount: 8,
                isActive: true,
                createdAt: Date().addingTimeInterval(-14400)
            ),
            SpacePrayerRequest(
                id: "pr-3",
                title: "Marriage restoration",
                body: "We're going through a difficult time. Trusting God to work in our hearts.",
                creatorName: nil,
                isAnonymous: true,
                prayerCount: 22,
                isActive: true,
                createdAt: Date().addingTimeInterval(-86400)
            )
        ]
    }
}

// MARK: - SpaceEvent (Dashboard stub — lightweight)

struct SpaceEvent: Identifiable {
    let id: String
    var title: String
    var eventDescription: String
    var scheduledAt: Date
    var durationMinutes: Int
    var location: String?
    var rsvpCount: Int
    var hasRSVPd: Bool
    var isLive: Bool

    static var preview: [SpaceEvent] {
        [
            SpaceEvent(
                id: "evt-1",
                title: "Sunday Live Worship",
                eventDescription: "Join us for live worship and a message from Pastor James.",
                scheduledAt: Date().addingTimeInterval(86400),
                durationMinutes: 90,
                location: "Main Sanctuary",
                rsvpCount: 148,
                hasRSVPd: false,
                isLive: false
            ),
            SpaceEvent(
                id: "evt-2",
                title: "Wednesday Prayer Meeting",
                eventDescription: "Midweek corporate prayer. All are welcome.",
                scheduledAt: Date().addingTimeInterval(3 * 86400),
                durationMinutes: 45,
                location: "Prayer Room B",
                rsvpCount: 32,
                hasRSVPd: true,
                isLive: false
            ),
            SpaceEvent(
                id: "evt-3",
                title: "Young Adults Bible Study",
                eventDescription: "Continuing our series through the book of Acts.",
                scheduledAt: Date().addingTimeInterval(5 * 86400),
                durationMinutes: 60,
                location: "Room 204",
                rsvpCount: 19,
                hasRSVPd: false,
                isLive: false
            )
        ]
    }
}

// MARK: - SpaceBirthday

/// Only shown when the member has consented to birthday visibility.
struct SpaceBirthday: Identifiable {
    let id: String
    var displayName: String
    var birthdayDate: Date      // year component ignored for display
    var hasConsented: Bool      // always true if this record exists; checked before display

    static var preview: [SpaceBirthday] {
        [
            SpaceBirthday(id: "bday-1", displayName: "Angela R.", birthdayDate: Date(), hasConsented: true),
            SpaceBirthday(id: "bday-2", displayName: "Marcus W.", birthdayDate: Date().addingTimeInterval(86400), hasConsented: true)
        ]
    }
}

// MARK: - SpaceVolunteerNeed

struct SpaceVolunteerNeed: Identifiable {
    let id: String
    var roleName: String
    var description: String
    var spotsNeeded: Int
    var spotsFilledCount: Int
    var contactName: String
    var deadline: Date?

    var spotsRemaining: Int { max(0, spotsNeeded - spotsFilledCount) }
    var isFull: Bool { spotsRemaining == 0 }

    static var preview: [SpaceVolunteerNeed] {
        [
            SpaceVolunteerNeed(
                id: "vol-1",
                roleName: "Greeter Team",
                description: "Welcome guests at the main entrance Sunday mornings.",
                spotsNeeded: 4,
                spotsFilledCount: 1,
                contactName: "Pastor James",
                deadline: Date().addingTimeInterval(4 * 86400)
            ),
            SpaceVolunteerNeed(
                id: "vol-2",
                roleName: "Kids Ministry Helper",
                description: "Assist in the 3–5 age classroom during 10 AM service.",
                spotsNeeded: 2,
                spotsFilledCount: 0,
                contactName: "Sarah M.",
                deadline: Date().addingTimeInterval(2 * 86400)
            ),
            SpaceVolunteerNeed(
                id: "vol-3",
                roleName: "Sound Board Operator",
                description: "Run sound for Wednesday evening service. Training provided.",
                spotsNeeded: 1,
                spotsFilledCount: 0,
                contactName: "Tech Team",
                deadline: nil
            )
        ]
    }
}

// MARK: - SpaceNote

struct SpaceNote: Identifiable {
    let id: String
    var title: String
    var scriptureRef: String?
    var authorName: String
    var previewText: String
    var sharedAt: Date

    static var preview: [SpaceNote] {
        [
            SpaceNote(
                id: "note-1",
                title: "Romans 8 — Sunday Sermon Notes",
                scriptureRef: "Romans 8:28",
                authorName: "Pastor James",
                previewText: "All things work together for good for those who love God...",
                sharedAt: Date().addingTimeInterval(-86400)
            ),
            SpaceNote(
                id: "note-2",
                title: "Acts 2 Study — Week 3",
                scriptureRef: "Acts 2:42–47",
                authorName: "Sarah M.",
                previewText: "The early church devoted themselves to the apostles' teaching...",
                sharedAt: Date().addingTimeInterval(-3 * 86400)
            ),
            SpaceNote(
                id: "note-3",
                title: "Midweek Prayer — Key Points",
                scriptureRef: nil,
                authorName: "David K.",
                previewText: "Focus areas this week: healing, provision, and spiritual renewal...",
                sharedAt: Date().addingTimeInterval(-5 * 86400)
            )
        ]
    }
}

// MARK: - SpaceDashboardData

struct SpaceDashboardData {
    var announcements: [SpaceAnnouncement]
    var prayerRequests: [SpacePrayerRequest]
    var upcomingEvents: [SpaceEvent]
    var birthdaysThisWeek: [SpaceBirthday]
    var volunteerNeeds: [SpaceVolunteerNeed]
    var recentNotes: [SpaceNote]

    static var preview: SpaceDashboardData {
        SpaceDashboardData(
            announcements: SpaceAnnouncement.preview,
            prayerRequests: SpacePrayerRequest.preview,
            upcomingEvents: SpaceEvent.preview,
            birthdaysThisWeek: SpaceBirthday.preview,
            volunteerNeeds: SpaceVolunteerNeed.preview,
            recentNotes: SpaceNote.preview
        )
    }

    static var empty: SpaceDashboardData {
        SpaceDashboardData(
            announcements: [],
            prayerRequests: [],
            upcomingEvents: [],
            birthdaysThisWeek: [],
            volunteerNeeds: [],
            recentNotes: []
        )
    }
}
