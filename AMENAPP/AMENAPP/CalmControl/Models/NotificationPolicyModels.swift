import Foundation
import FirebaseFirestore

// MARK: - Notification Category

enum AmenNotificationCategory: String, Codable, CaseIterable {
    case dailyVerse = "dailyVerse"
    case readingReminder = "readingReminder"
    case prayerReminder = "prayerReminder"
    case communityDigest = "communityDigest"
    case streakReminder = "streakReminder"
    case quietReturn = "quietReturn"
    case milestoneReflection = "milestoneReflection"

    var displayName: String {
        switch self {
        case .dailyVerse: return "Daily Verse"
        case .readingReminder: return "Reading Reminder"
        case .prayerReminder: return "Prayer Reminder"
        case .communityDigest: return "Community Digest"
        case .streakReminder: return "Streak Reminder"
        case .quietReturn: return "Gentle Return"
        case .milestoneReflection: return "Milestone Memory"
        }
    }

    var description: String {
        switch self {
        case .dailyVerse: return "A verse delivered at your preferred time."
        case .readingReminder: return "Gentle nudge for your reading rhythm."
        case .prayerReminder: return "Your scheduled prayer time."
        case .communityDigest: return "Morning or evening summary of meaningful activity."
        case .streakReminder: return "Encouragement to continue your rhythm."
        case .quietReturn: return "A warm welcome if you've been away."
        case .milestoneReflection: return "Celebrate your spiritual milestones."
        }
    }

    var isEssential: Bool {
        // Essential notifications survive inactivity suppression
        switch self {
        case .quietReturn: return true
        default: return false
        }
    }
}

// MARK: - Notification Intensity Mode

enum AmenNotificationIntensity: String, Codable, CaseIterable {
    case minimal = "minimal"
    case balanced = "balanced"
    case encouraging = "encouraging"
    case activeCommunity = "active_community"

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .balanced: return "Balanced"
        case .encouraging: return "Encouraging"
        case .activeCommunity: return "Active Community"
        }
    }

    var description: String {
        switch self {
        case .minimal: return "Only the most important notifications."
        case .balanced: return "A calm, steady flow."
        case .encouraging: return "Regular encouragement and reminders."
        case .activeCommunity: return "Stay connected to everything happening."
        }
    }
}

// MARK: - Notification Settings

struct AmenNotificationSettings: Codable {
    var intensityMode: AmenNotificationIntensity = .balanced
    var enabledCategories: [String: Bool] = [:]
    var quietHoursEnabled: Bool = false
    var quietHoursStartHour: Int = 22  // 10 PM
    var quietHoursEndHour: Int = 7     // 7 AM
    var sabbathSuppressAll: Bool = true
    @ServerTimestamp var updatedAt: Date?

    func isCategoryEnabled(_ category: AmenNotificationCategory) -> Bool {
        enabledCategories[category.rawValue] ?? true
    }

    mutating func setCategory(_ category: AmenNotificationCategory, enabled: Bool) {
        enabledCategories[category.rawValue] = enabled
    }
}

// MARK: - Notification Eligibility Result

struct AmenNotificationEligibility {
    let isEligible: Bool
    let suppressedReason: String?

    static let eligible = AmenNotificationEligibility(isEligible: true, suppressedReason: nil)
    static func suppressed(_ reason: String) -> AmenNotificationEligibility {
        AmenNotificationEligibility(isEligible: false, suppressedReason: reason)
    }
}
