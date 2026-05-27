import Foundation

// MARK: - Calm Control Settings

enum AmenPresenceState: String, Codable, CaseIterable, Identifiable {
    case visible
    case quiet
    case reflecting
    case focused
    case sabbathing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .visible: return "Visible"
        case .quiet: return "Quiet"
        case .reflecting: return "Reflecting"
        case .focused: return "Focused"
        case .sabbathing: return "Sabbathing"
        }
    }
}

enum AmenNotificationIntensity: String, Codable, CaseIterable, Identifiable {
    case minimal
    case balanced
    case encouraging
    case activeCommunity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .balanced: return "Balanced"
        case .encouraging: return "Encouraging"
        case .activeCommunity: return "Active Community"
        }
    }
}

enum AmenRhythmNotificationCategory: String, Codable, CaseIterable, Identifiable {
    case dailyVerse
    case readingReminder
    case prayerReminder
    case communityDigest
    case streakReminder
    case quietReturn
    case milestoneReflection

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dailyVerse: return "Daily Verse"
        case .readingReminder: return "Reading Reminder"
        case .prayerReminder: return "Prayer Reminder"
        case .communityDigest: return "Community Digest"
        case .streakReminder: return "Streak Reminder"
        case .quietReturn: return "Quiet Return"
        case .milestoneReflection: return "Milestone Reflection"
        }
    }

    var isEssential: Bool {
        switch self {
        case .dailyVerse, .readingReminder, .prayerReminder:
            return true
        case .communityDigest, .streakReminder, .quietReturn, .milestoneReflection:
            return false
        }
    }
}

enum AmenSpiritualActivityType: String, Codable, CaseIterable, Identifiable {
    case scripture
    case bibleReading
    case prayerReflection
    case communityPresence

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scripture: return "Scripture"
        case .bibleReading: return "Bible Reading"
        case .prayerReflection: return "Prayer & Reflection"
        case .communityPresence: return "Community Presence"
        }
    }
}

enum AmenSpiritualMomentumState: String, Codable, CaseIterable, Identifiable {
    case resting
    case reflecting
    case growing
    case grounded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .resting: return "Resting"
        case .reflecting: return "Reflecting"
        case .growing: return "Growing"
        case .grounded: return "Grounded"
        }
    }
}

struct AmenPrivacySettings: Codable, Equatable {
    var hideFollowerCount: Bool = true
    var hideFollowingCount: Bool = true
    var privateFollowingGraph: Bool = true
    var quietProfileMode: Bool = false
    var disableReadReceipts: Bool = true
    var allowAnonymousReflectionPosting: Bool = false
    var defaultAudienceLayerId: String? = nil

    var publicMetricsEnabled: Bool {
        !hideFollowerCount || !hideFollowingCount
    }
}

struct AmenFeedControls: Codable, Equatable {
    var textOnlyFeedMode: Bool = false
    var disablePhotos: Bool = false
    var disableVideos: Bool = false
    var hideViralContent: Bool = true
    var noDebateFilter: Bool = false
    var topicSaturationLimit: Int = 3
    var motionIntensity: Int = 2
    var audioIntensity: Int = 1
    var emotionalEnergyLimit: Int = 3
    var aiNoiseCompressionEnabled: Bool = false
}

struct AmenNotificationSettings: Codable, Equatable {
    var masterPushEnabled: Bool = true
    var intensity: AmenNotificationIntensity = .balanced
    var enabledCategories: [AmenRhythmNotificationCategory: Bool] = AmenRhythmNotificationCategory.allCases.reduce(into: [:]) { result, category in
        result[category] = true
    }
    var adaptiveRemindersEnabled: Bool = true
    var dailyVersePushEnabled: Bool = true
    var quietHoursEnabled: Bool = false
    var sabbathSuppressesNonessential: Bool = true
    var inactivityPauseEnabled: Bool = true
    var pauseNoticeSentAt: Date? = nil
    var pausedAfterInactivity: Bool = false

    func isCategoryEnabled(_ category: AmenRhythmNotificationCategory) -> Bool {
        enabledCategories[category] ?? true
    }
}

struct AmenSpiritualRhythm: Codable, Equatable {
    var scriptureStreakEnabled: Bool = true
    var bibleReadingStreakEnabled: Bool = true
    var prayerReflectionStreakEnabled: Bool = true
    var communityPresenceStreakEnabled: Bool = false
    var graceRecoveryEnabled: Bool = true
    var sabbathModeEnabled: Bool = false
    var privateMomentumState: AmenSpiritualMomentumState = .resting
    var lastActivityAt: Date? = nil
    var preferredReminderHour: Int = 8
    var preferredEveningDigestHour: Int = 18
}

struct AmenPresenceSettings: Codable, Equatable {
    var state: AmenPresenceState = .visible
    var expiresAt: Date? = nil
}

struct AmenAudienceLayer: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var memberIds: [String]
    var isDefault: Bool
}

struct AmenStreakState: Codable, Identifiable, Equatable {
    var id: String { streakType.rawValue }
    var streakType: AmenSpiritualActivityType
    var currentCount: Int
    var longestCount: Int
    var lastRecordedAt: Date?
    var graceRecoveriesRemaining: Int
    var isRecovered: Bool

    static func empty(_ type: AmenSpiritualActivityType) -> AmenStreakState {
        AmenStreakState(
            streakType: type,
            currentCount: 0,
            longestCount: 0,
            lastRecordedAt: nil,
            graceRecoveriesRemaining: 2,
            isRecovered: false
        )
    }
}

struct AmenCalmControlSnapshot: Codable, Equatable {
    var privacy: AmenPrivacySettings = AmenPrivacySettings()
    var notificationSettings: AmenNotificationSettings = AmenNotificationSettings()
    var spiritualRhythm: AmenSpiritualRhythm = AmenSpiritualRhythm()
    var presence: AmenPresenceSettings = AmenPresenceSettings()
    var feedControls: AmenFeedControls = AmenFeedControls()
    var streaks: [AmenStreakState] = AmenSpiritualActivityType.allCases.map { AmenStreakState.empty($0) }
}
