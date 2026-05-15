import Foundation
import FirebaseFirestore

// MARK: - RestModePolicy

struct RestModePolicy: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    var enabled: Bool
    var modeName: RestModeName
    var modeLevel: RestModeLevel
    var timezone: String
    var activeDay: RestActiveDay
    var customSchedule: RestCustomSchedule?
    var startTime: String           // "HH:mm" e.g. "00:00"
    var endTime: String             // "HH:mm" e.g. "23:59"
    var allowedRoutes: [String]
    var restrictedRoutes: [String]
    var reflectionFeedEnabled: Bool
    var postingPolicy: RestPostingPolicy
    var commentPolicy: RestCommentPolicy
    var notificationPolicy: RestNotificationPolicy
    var allowTemporaryOverride: Bool
    var overrideDurationMinutes: Int
    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}

enum RestModeName: String, Codable {
    case lordsDay = "lord_day"
    case sundayRest = "sunday_rest"
    case sabbathRhythm = "sabbath_rhythm"

    var displayName: String {
        switch self {
        case .lordsDay:       return "Lord's Day Mode"
        case .sundayRest:     return "Sunday Rest Mode"
        case .sabbathRhythm:  return "Sabbath Rhythm"
        }
    }
}

enum RestModeLevel: String, Codable, CaseIterable, Identifiable {
    case gentle
    case worship
    case full

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gentle:  return "Gentle"
        case .worship: return "Worship"
        case .full:    return "Full Rest"
        }
    }

    var description: String {
        switch self {
        case .gentle:
            return "Feed becomes Reflection Feed. Social notifications quiet. You can still post with a gentle nudge."
        case .worship:
            return "Feed paused. Limited posting (prayer, testimony, church notes). Social notifications muted."
        case .full:
            return "App mostly closed. Only Find a Church, Church Notes, Bible, and Prayer remain. Drafts only."
        }
    }
}

enum RestActiveDay: String, Codable {
    case sunday
    case saturday
    case custom
}

struct RestCustomSchedule: Codable {
    var days: [Int]         // 1 = Sunday … 7 = Saturday (Calendar.weekday)
    var startTime: String
    var endTime: String
}

enum RestPostingPolicy: String, Codable {
    case allowed            // All posts allowed
    case limitedTypes       // Prayer, testimony, church notes, scripture reflection only
    case draftOnly          // All posts saved as drafts
    case disabled
}

enum RestCommentPolicy: String, Codable {
    case open               // Normal commenting
    case toneGated          // Sunday tone check before posting
    case readOnly
    case disabled
}

struct RestNotificationPolicy: Codable {
    var allowedTypes: [String]
    var mutedTypes: [String]
}

// MARK: - Default policy factory

extension RestModePolicy {
    static func defaultPolicy(for userId: String, timezone: String) -> RestModePolicy {
        RestModePolicy(
            id: nil,
            userId: userId,
            enabled: false,
            modeName: .lordsDay,
            modeLevel: .worship,
            timezone: timezone,
            activeDay: .sunday,
            customSchedule: nil,
            startTime: "00:00",
            endTime: "23:59",
            allowedRoutes: RestModeRoutes.allowed,
            restrictedRoutes: RestModeRoutes.restricted,
            reflectionFeedEnabled: true,
            postingPolicy: .limitedTypes,
            commentPolicy: .toneGated,
            notificationPolicy: RestNotificationPolicy(
                allowedTypes: RestModeNotifications.allowed,
                mutedTypes: RestModeNotifications.muted
            ),
            allowTemporaryOverride: true,
            overrideDurationMinutes: 15
        )
    }
}

// MARK: - Route constants

enum RestModeRoutes {
    static let allowed: [String] = [
        "find_church",
        "church_notes",
        "bible",
        "daily_verse",
        "prayer_request",
        "saved_notes",
        "emergency_support"
    ]

    static let restricted: [String] = [
        "main_feed",
        "create_post",
        "comments",
        "likes",
        "reposts",
        "trending",
        "social_notifications",
        "messages",
        "infinite_scroll"
    ]

    /// Post categories allowed to publish (not draft) during worship/full rest
    static let allowedPostCategories: Set<String> = [
        "prayer",
        "testimonies",
        "devotional",
        "churchNote",
        "scriptureReflection"
    ]
}

// MARK: - Notification constants

enum RestModeNotifications {
    static let allowed: [String] = [
        "church_reminder",
        "sermon_notes_reminder",
        "prayer_support",
        "daily_verse",
        "emergency_support"
    ]

    static let muted: [String] = [
        "like",
        "repost",
        "new_follower",
        "trending",
        "comment_debate",
        "algorithmic_recommendation",
        "dm_non_urgent"
    ]
}

// MARK: - Override reason (structured, never raw text stored)

enum RestModeOverrideReason: String, CaseIterable, Identifiable {
    case encouragement = "encouragement"
    case support = "support"
    case responding = "responding"
    case habit = "habit"
    case other = "other"

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .encouragement: return "I need encouragement"
        case .support:       return "I need support"
        case .responding:    return "I need to respond to someone"
        case .habit:         return "I opened by habit"
        case .other:         return "Other reason"
        }
    }

    var icon: String {
        switch self {
        case .encouragement: return "heart"
        case .support:       return "hands.sparkles"
        case .responding:    return "message"
        case .habit:         return "exclamationmark.circle"
        case .other:         return "ellipsis.circle"
        }
    }

    /// Destination to surface for this override reason
    var suggestedRoute: AmenRoute? {
        switch self {
        case .encouragement: return .dailyVerse
        case .support:       return .prayerRequest
        case .responding:    return .messages
        case .habit, .other: return nil
        }
    }
}
