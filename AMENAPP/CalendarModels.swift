// CalendarModels.swift
// AMEN Calendar & Reminder System
// Data models for all calendar, RSVP, and reminder features

import SwiftUI
import EventKit
import FirebaseFirestore

// MARK: - AMEN Event (Calendar-ready)

struct AMENEvent: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var eventType: AMENEventType
    var startDate: Date
    var endDate: Date
    var timeZoneIdentifier: String          // e.g. "America/New_York"
    var location: String?
    var locationURL: String?                // Google Maps / Apple Maps link
    var isOnline: Bool
    var onlineMeetingURL: String?
    var notes: String?
    var organizerName: String
    var organizerId: String
    var organizerAvatarURL: String?
    var imageURL: String?
    var deepLinkURL: String?                // Opens AMEN app to this event
    var capacity: Int                       // 0 = unlimited
    var rsvpCount: Int
    var rsvpDeadline: Date?
    var requiresApproval: Bool
    var isPublic: Bool
    var isFeatured: Bool
    var tags: [String]
    var reminderOffsets: [ReminderOffset]   // Default reminder suggestions
    var moderationState: String             // "active", "under_review"
    var createdAt: Date
    var updatedAt: Date

    // Calendar sync fields
    var calendarEventId: String?            // EKEvent identifier (stored per user)

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    var durationMinutes: Int {
        Int(endDate.timeIntervalSince(startDate) / 60)
    }

    var isUpcoming: Bool {
        startDate > Date()
    }

    var isHappeningNow: Bool {
        let now = Date()
        return startDate <= now && endDate >= now
    }
}

// MARK: - Event Types

enum AMENEventType: String, Codable, CaseIterable, Identifiable {
    case churchService, churchEvent, conference, smallGroup, prayerMeeting
    case bibleStudy, worship, retreat, missionTrip, volunteer
    case youthEvent, familyEvent, community, jobInterview, mentorship
    case spiritualCheckIn, generalReminder, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .churchService:    return "Church Service"
        case .churchEvent:      return "Church Event"
        case .conference:       return "Conference"
        case .smallGroup:       return "Small Group"
        case .prayerMeeting:    return "Prayer Meeting"
        case .bibleStudy:       return "Bible Study"
        case .worship:          return "Worship"
        case .retreat:          return "Retreat"
        case .missionTrip:      return "Mission Trip"
        case .volunteer:        return "Volunteering"
        case .youthEvent:       return "Youth Event"
        case .familyEvent:      return "Family Event"
        case .community:        return "Community"
        case .jobInterview:     return "Job Interview"
        case .mentorship:       return "Mentorship Session"
        case .spiritualCheckIn: return "Spiritual Check-In"
        case .generalReminder:  return "Reminder"
        case .custom:           return "Event"
        }
    }

    var icon: String {
        switch self {
        case .churchService:    return "building.columns.fill"
        case .churchEvent:      return "star.fill"
        case .conference:       return "person.3.fill"
        case .smallGroup:       return "person.2.fill"
        case .prayerMeeting:    return "hands.sparkles.fill"
        case .bibleStudy:       return "book.fill"
        case .worship:          return "music.quarternote.3"
        case .retreat:          return "mountain.2.fill"
        case .missionTrip:      return "airplane"
        case .volunteer:        return "hand.raised.fill"
        case .youthEvent:       return "figure.2.and.child.holdinghands"
        case .familyEvent:      return "house.fill"
        case .community:        return "globe"
        case .jobInterview:     return "briefcase.fill"
        case .mentorship:       return "person.fill.badge.plus"
        case .spiritualCheckIn: return "heart.fill"
        case .generalReminder:  return "bell.fill"
        case .custom:           return "calendar"
        }
    }

    var color: Color {
        switch self {
        case .churchService, .worship:          return Color(red: 0.42, green: 0.24, blue: 0.82)
        case .prayerMeeting, .spiritualCheckIn: return Color(red: 0.62, green: 0.28, blue: 0.82)
        case .bibleStudy, .smallGroup:          return Color(red: 0.15, green: 0.45, blue: 0.82)
        case .conference, .retreat:             return Color(red: 0.15, green: 0.35, blue: 0.80)
        case .volunteer, .missionTrip:          return Color(red: 0.18, green: 0.62, blue: 0.36)
        case .jobInterview, .mentorship:        return Color(red: 0.88, green: 0.55, blue: 0.15)
        case .churchEvent, .community:          return Color(red: 0.18, green: 0.55, blue: 0.45)
        default:                                 return Color(red: 0.40, green: 0.40, blue: 0.45)
        }
    }

    var defaultReminderOffsets: [ReminderOffset] {
        switch self {
        case .churchService:    return [.oneHourBefore, .oneDayBefore]
        case .bibleStudy:       return [.thirtyMinutesBefore]
        case .jobInterview:     return [.oneHourBefore, .oneDayBefore, .threeDaysBefore]
        case .prayerMeeting:    return [.fifteenMinutesBefore]
        case .retreat:          return [.oneDayBefore, .oneWeekBefore]
        case .smallGroup:       return [.thirtyMinutesBefore]
        case .volunteer:        return [.oneHourBefore, .oneDayBefore]
        case .spiritualCheckIn: return [.atTime]
        default:                return [.thirtyMinutesBefore]
        }
    }

    var calendarNotes: String {
        switch self {
        case .jobInterview:    return "Remember to prepare your materials and arrive early. Praying for peace and clarity."
        case .bibleStudy:      return "Bring your Bible and any questions. Open your heart to learn."
        case .prayerMeeting:   return "Come as you are. There's no perfect way to pray."
        case .spiritualCheckIn: return "A moment for reflection and honest conversation with yourself and God."
        default:               return ""
        }
    }
}

// MARK: - Reminder Offset

enum ReminderOffset: String, Codable, CaseIterable, Identifiable {
    case atTime = "at_time"
    case fiveMinutesBefore = "5_min"
    case tenMinutesBefore = "10_min"
    case fifteenMinutesBefore = "15_min"
    case thirtyMinutesBefore = "30_min"
    case oneHourBefore = "1_hour"
    case twoHoursBefore = "2_hours"
    case oneDayBefore = "1_day"
    case twoDaysBefore = "2_days"
    case threeDaysBefore = "3_days"
    case oneWeekBefore = "1_week"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .atTime:               return "At time of event"
        case .fiveMinutesBefore:    return "5 minutes before"
        case .tenMinutesBefore:     return "10 minutes before"
        case .fifteenMinutesBefore: return "15 minutes before"
        case .thirtyMinutesBefore:  return "30 minutes before"
        case .oneHourBefore:        return "1 hour before"
        case .twoHoursBefore:       return "2 hours before"
        case .oneDayBefore:         return "1 day before"
        case .twoDaysBefore:        return "2 days before"
        case .threeDaysBefore:      return "3 days before"
        case .oneWeekBefore:        return "1 week before"
        }
    }

    /// Minutes before event for EKAlarm
    var minutesBefore: Int {
        switch self {
        case .atTime:               return 0
        case .fiveMinutesBefore:    return 5
        case .tenMinutesBefore:     return 10
        case .fifteenMinutesBefore: return 15
        case .thirtyMinutesBefore:  return 30
        case .oneHourBefore:        return 60
        case .twoHoursBefore:       return 120
        case .oneDayBefore:         return 60 * 24
        case .twoDaysBefore:        return 60 * 24 * 2
        case .threeDaysBefore:      return 60 * 24 * 3
        case .oneWeekBefore:        return 60 * 24 * 7
        }
    }
}

// MARK: - RSVP Record

struct AMENEventRSVP: Identifiable, Codable {
    @DocumentID var id: String?
    var eventId: String
    var userId: String
    var displayName: String
    var status: RSVPStatus
    var addedToCalendar: Bool
    var calendarEventId: String?            // System EKEvent identifier
    var reminderEnabled: Bool
    var selectedReminderOffsets: [ReminderOffset]
    var note: String?                       // Optional note from attendee
    var createdAt: Date
    var updatedAt: Date
}

enum RSVPStatus: String, Codable {
    case going, maybe, notGoing, waitlist, pendingApproval

    var label: String {
        switch self {
        case .going:           return "Going"
        case .maybe:           return "Maybe"
        case .notGoing:        return "Not Going"
        case .waitlist:        return "On Waitlist"
        case .pendingApproval: return "Pending Approval"
        }
    }

    var icon: String {
        switch self {
        case .going:           return "checkmark.circle.fill"
        case .maybe:           return "questionmark.circle.fill"
        case .notGoing:        return "xmark.circle.fill"
        case .waitlist:        return "clock.fill"
        case .pendingApproval: return "person.badge.clock.fill"
        }
    }

    var color: Color {
        switch self {
        case .going:           return Color(red: 0.18, green: 0.62, blue: 0.36)
        case .maybe:           return .orange
        case .notGoing:        return .red
        case .waitlist:        return .blue
        case .pendingApproval: return .orange
        }
    }
}

// MARK: - Calendar Saved Event (per-user tracking)

struct AMENSavedCalendarEvent: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var amenEventId: String?                // Reference to AMENEvent
    var title: String
    var eventType: AMENEventType
    var startDate: Date
    var endDate: Date
    var timeZoneIdentifier: String
    var location: String?
    var isOnline: Bool
    var notes: String
    var calendarEventId: String?            // System EKEvent identifier
    var localNotificationIds: [String]      // UNNotification identifiers
    var reminders: [ReminderOffset]
    var isSavedToCalendar: Bool
    var followUpReminderDate: Date?         // Post-event follow-up
    var followUpSent: Bool
    var createdAt: Date
}

// MARK: - Reminder Template

struct AMENReminderTemplate: Identifiable {
    var id: String { rawValue }
    var rawValue: String
    var title: String
    var body: String
    var eventType: AMENEventType
    var defaultOffset: ReminderOffset
    var isRecurring: Bool

    static let jobInterviewPrepReminder = AMENReminderTemplate(
        rawValue: "job_interview_prep",
        title: "Interview Tomorrow",
        body: "Prepare your materials, notes, and questions. Trust the preparation you've done.",
        eventType: .jobInterview,
        defaultOffset: .oneDayBefore,
        isRecurring: false
    )

    static let prayerReminder = AMENReminderTemplate(
        rawValue: "prayer_reminder",
        title: "Prayer Time",
        body: "Your scheduled prayer time is coming up.",
        eventType: .prayerMeeting,
        defaultOffset: .fifteenMinutesBefore,
        isRecurring: true
    )

    static let bibleStudyReminder = AMENReminderTemplate(
        rawValue: "bible_study_reminder",
        title: "Bible Study Today",
        body: "Don't forget your Bible study session.",
        eventType: .bibleStudy,
        defaultOffset: .thirtyMinutesBefore,
        isRecurring: false
    )

    static let smallGroupReminder = AMENReminderTemplate(
        rawValue: "small_group_reminder",
        title: "Small Group Tonight",
        body: "Your small group meets today.",
        eventType: .smallGroup,
        defaultOffset: .oneHourBefore,
        isRecurring: true
    )

    static let volunteerReminder = AMENReminderTemplate(
        rawValue: "volunteer_reminder",
        title: "You're Volunteering",
        body: "Remember your volunteer commitment today. Thank you for serving.",
        eventType: .volunteer,
        defaultOffset: .twoHoursBefore,
        isRecurring: false
    )
}

// MARK: - Calendar Permission State

enum CalendarPermissionState {
    case notDetermined, authorized, denied, restricted

    var shouldShowPermissionPrompt: Bool {
        self == .notDetermined
    }

    var canAddEvents: Bool {
        self == .authorized
    }
}

// MARK: - Calendar Add Options

struct CalendarAddOptions {
    var addToCalendar: Bool = true
    var enableReminder: Bool = true
    var reminderOffsets: [ReminderOffset] = [.thirtyMinutesBefore]
    var addFollowUpReminder: Bool = false
    var followUpDaysAfter: Int = 1
    var useNativeEventEditor: Bool = false  // If true, opens EKEventEditViewController
}

// MARK: - Event Duplicate Check

struct EventDuplicateKey: Hashable {
    let title: String
    let startDate: Date
    let organizerId: String

    init(event: AMENEvent) {
        self.title = event.title
        self.startDate = event.startDate
        self.organizerId = event.organizerId
    }
}

// MARK: - Firestore Collection Names

enum CalendarCollections {
    static let events = "faithEvents"
    static let rsvps = "eventRSVPs"
    static let savedCalendarEvents = "savedCalendarEvents"
    static let reminderSchedules = "reminderSchedules"
}
