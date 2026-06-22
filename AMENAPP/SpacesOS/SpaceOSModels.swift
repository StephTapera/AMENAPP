// SpaceOSModels.swift
// AMENAPP — SpacesOS
// Supporting models for the Smart Space Dashboard and Composer.

import Foundation
import SwiftUI

// MARK: - Member Role

enum SpaceMemberRole: String, CaseIterable, Identifiable {
    case pastor, admin, leader, member, guest

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

    var canPost: Bool { self != .guest }
    var canManageMembers: Bool { self == .pastor || self == .admin }
    var canPostAnnouncement: Bool { self != .guest && self != .member }
    var canViewAnalytics: Bool { self == .pastor || self == .admin }
}

// MARK: - Quick Action

struct SpaceQuickAction: Identifiable {
    let id: String
    var label: String
    var icon: String
    var isEnabled: Bool
    var disabledReason: String?
    var action: () -> Void

    static func actions(
        for role: SpaceMemberRole,
        onPost: @escaping () -> Void,
        onAnnouncement: @escaping () -> Void,
        onEvent: @escaping () -> Void,
        onPrayer: @escaping () -> Void,
        onMembers: @escaping () -> Void,
        onAnalytics: @escaping () -> Void
    ) -> [SpaceQuickAction] {
        switch role {
        case .pastor, .admin:
            return [
                SpaceQuickAction(id: "announce", label: "Announce", icon: "megaphone.fill", isEnabled: true, action: onAnnouncement),
                SpaceQuickAction(id: "event", label: "Event", icon: "calendar.badge.plus", isEnabled: true, action: onEvent),
                SpaceQuickAction(id: "members", label: "Members", icon: "person.2.fill", isEnabled: true, action: onMembers),
                SpaceQuickAction(id: "analytics", label: "Analytics", icon: "chart.bar.fill", isEnabled: true, action: onAnalytics)
            ]
        case .leader:
            return [
                SpaceQuickAction(id: "announce", label: "Announce", icon: "megaphone.fill", isEnabled: true, action: onAnnouncement),
                SpaceQuickAction(id: "event", label: "Event", icon: "calendar.badge.plus", isEnabled: true, action: onEvent),
                SpaceQuickAction(id: "prayer", label: "Prayer Room", icon: "hands.sparkles.fill", isEnabled: true, action: onPrayer)
            ]
        case .member:
            return [
                SpaceQuickAction(id: "post", label: "Post", icon: "plus.bubble.fill", isEnabled: true, action: onPost),
                SpaceQuickAction(id: "prayer", label: "Request Prayer", icon: "hands.sparkles.fill", isEnabled: true, action: onPrayer),
                SpaceQuickAction(id: "event", label: "Add to Calendar", icon: "calendar", isEnabled: true, action: onEvent)
            ]
        case .guest:
            return [
                SpaceQuickAction(id: "post", label: "Post", icon: "plus.bubble.fill", isEnabled: false,
                                 disabledReason: "Join to participate", action: {}),
                SpaceQuickAction(id: "prayer", label: "Prayer", icon: "hands.sparkles.fill", isEnabled: false,
                                 disabledReason: "Join to participate", action: {}),
                SpaceQuickAction(id: "join", label: "Join Space", icon: "person.badge.plus.fill", isEnabled: true, action: onPost)
            ]
        }
    }
}

// MARK: - Dashboard Sections

struct SpaceAnnouncement: Identifiable {
    let id: String
    var title: String
    var body: String
    var authorName: String
    var postedAt: Date
    var isPinned: Bool

    static let previews: [SpaceAnnouncement] = [
        SpaceAnnouncement(id: "a1", title: "Sunday Service Change",
                          body: "This Sunday's service will start at 10am instead of 9am. Please plan accordingly.",
                          authorName: "Pastor James", postedAt: Date().addingTimeInterval(-3600), isPinned: true),
        SpaceAnnouncement(id: "a2", title: "New Bible Study Starting",
                          body: "We're starting the book of James next Thursday at 7pm. All are welcome!",
                          authorName: "Elder Sarah", postedAt: Date().addingTimeInterval(-86400), isPinned: false)
    ]
}

struct SpacePrayerRequest: Identifiable {
    let id: String
    var body: String
    var isAnonymous: Bool
    var authorName: String?
    var postedAt: Date
    var prayerCount: Int

    var displayName: String { isAnonymous ? "A member" : (authorName ?? "Member") }

    static let previews: [SpacePrayerRequest] = [
        SpacePrayerRequest(id: "p1", body: "Please pray for my mother's surgery next week. Believing for full recovery.",
                           isAnonymous: false, authorName: "David K.", postedAt: Date().addingTimeInterval(-7200), prayerCount: 14),
        SpacePrayerRequest(id: "p2", body: "Prayers needed for a difficult situation at work.",
                           isAnonymous: true, authorName: nil, postedAt: Date().addingTimeInterval(-18000), prayerCount: 6)
    ]
}

struct SpaceEvent: Identifiable {
    let id: String
    var title: String
    var date: Date
    var location: String?
    var rsvpCount: Int
    var hasRsvped: Bool

    static let previews: [SpaceEvent] = [
        SpaceEvent(id: "e1", title: "Community Service Day", date: Date().addingTimeInterval(86400 * 3),
                   location: "Downtown Mission", rsvpCount: 23, hasRsvped: false),
        SpaceEvent(id: "e2", title: "Thursday Bible Study", date: Date().addingTimeInterval(86400 * 5),
                   location: "Room 204", rsvpCount: 12, hasRsvped: true)
    ]
}

struct SpaceBirthday: Identifiable {
    let id: String
    var memberName: String
    var date: Date

    static let previews: [SpaceBirthday] = [
        SpaceBirthday(id: "b1", memberName: "Maria G.", date: Date()),
        SpaceBirthday(id: "b2", memberName: "Thomas R.", date: Date().addingTimeInterval(86400 * 2))
    ]
}

struct SpaceVolunteerNeed: Identifiable {
    let id: String
    var role: String
    var description: String
    var spotsRemaining: Int
    var event: String

    static let previews: [SpaceVolunteerNeed] = [
        SpaceVolunteerNeed(id: "v1", role: "Usher", description: "Help welcome guests at Sunday service",
                           spotsRemaining: 3, event: "Sunday Service"),
        SpaceVolunteerNeed(id: "v2", role: "Setup Crew", description: "Community Service Day setup at 7am",
                           spotsRemaining: 5, event: "Community Service Day")
    ]
}

struct SpaceNote: Identifiable {
    let id: String
    var title: String
    var snippet: String
    var authorName: String
    var postedAt: Date

    static let previews: [SpaceNote] = [
        SpaceNote(id: "n1", title: "Psalm 23 Deep Dive",
                  snippet: "The Lord is my shepherd — exploring the imagery of divine provision…",
                  authorName: "Sister Ruth", postedAt: Date().addingTimeInterval(-43200)),
        SpaceNote(id: "n2", title: "James 1 — Trials and Wisdom",
                  snippet: "Key themes: perseverance, wisdom, and the source of temptation…",
                  authorName: "Elder Mark", postedAt: Date().addingTimeInterval(-86400))
    ]
}

struct SpaceDashboardData {
    var announcements: [SpaceAnnouncement]
    var prayerRequests: [SpacePrayerRequest]
    var upcomingEvents: [SpaceEvent]
    var birthdaysThisWeek: [SpaceBirthday]
    var volunteerNeeds: [SpaceVolunteerNeed]
    var recentNotes: [SpaceNote]

    static let preview = SpaceDashboardData(
        announcements: SpaceAnnouncement.previews,
        prayerRequests: SpacePrayerRequest.previews,
        upcomingEvents: SpaceEvent.previews,
        birthdaysThisWeek: SpaceBirthday.previews,
        volunteerNeeds: SpaceVolunteerNeed.previews,
        recentNotes: SpaceNote.previews
    )
}

// MARK: - Post Type

enum SpacePostType: String, CaseIterable, Identifiable {
    case discussion, announcement, event, prayerRoom, study, poll, resource

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
        case .study:        return "book.closed.fill"
        case .poll:         return "chart.bar.fill"
        case .resource:     return "books.vertical.fill"
        }
    }
}
