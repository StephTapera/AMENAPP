import Foundation
import FirebaseFirestore

// MARK: - SpiritualStreakType

enum SpiritualStreakType: String, Codable, CaseIterable {
    case scriptureReading
    case bibleStudy
    case prayer
    case reflection
    case communityPresence

    var displayName: String {
        switch self {
        case .scriptureReading:    return "Scripture Reading"
        case .bibleStudy:          return "Bible Study"
        case .prayer:              return "Prayer"
        case .reflection:          return "Reflection"
        case .communityPresence:   return "Community Presence"
        }
    }

    var icon: String {
        switch self {
        case .scriptureReading:    return "book.pages"
        case .bibleStudy:          return "text.book.closed"
        case .prayer:              return "hands.sparkles.fill"
        case .reflection:          return "moon.stars.fill"
        case .communityPresence:   return "person.3.fill"
        }
    }

    /// Number of days after last activity before the streak resets.
    var gracePeriodDays: Int {
        switch self {
        case .scriptureReading:    return 1
        case .bibleStudy:          return 1
        case .prayer:              return 2
        case .reflection:          return 2
        case .communityPresence:   return 3
        }
    }
}

// MARK: - SpiritualMomentumState

/// Describes where the user currently is on their spiritual journey.
/// Language is intentionally grace-based — no gamification or shame.
enum SpiritualMomentumState: String, Codable {
    case grounded
    case growing
    case reflecting
    case resting

    var displayName: String {
        switch self {
        case .grounded:    return "Grounded"
        case .growing:     return "Growing"
        case .reflecting:  return "Reflecting"
        case .resting:     return "Resting"
        }
    }

    var description: String {
        switch self {
        case .grounded:
            return "You are consistently showing up. Your roots are going deep."
        case .growing:
            return "You are taking meaningful steps in your walk. Keep going."
        case .reflecting:
            return "A season of reflection can be just as fruitful as a season of action."
        case .resting:
            return "Even the earth rests. Come back when you are ready — there is no condemnation here."
        }
    }
}

// MARK: - SpiritualStreak

struct SpiritualStreak: Identifiable, Codable {
    // Stored as the streakType raw value so it doubles as a stable Firestore document ID.
    var id: String
    var type: SpiritualStreakType
    var currentStreak: Int
    var longestStreak: Int
    var totalDays: Int
    var lastActivityAt: Timestamp?
    var gracePeriodUsedToday: Bool
    var isInGracePeriod: Bool
    var recoveryEligibleUntil: Timestamp?
    /// Sorted list of streak-length milestones the user has reached (e.g. [7, 30, 90]).
    var milestones: [Int]

    init(
        type: SpiritualStreakType,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        totalDays: Int = 0,
        lastActivityAt: Timestamp? = nil,
        gracePeriodUsedToday: Bool = false,
        isInGracePeriod: Bool = false,
        recoveryEligibleUntil: Timestamp? = nil,
        milestones: [Int] = []
    ) {
        self.id = type.rawValue
        self.type = type
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.totalDays = totalDays
        self.lastActivityAt = lastActivityAt
        self.gracePeriodUsedToday = gracePeriodUsedToday
        self.isInGracePeriod = isInGracePeriod
        self.recoveryEligibleUntil = recoveryEligibleUntil
        self.milestones = milestones
    }

    /// The streak is considered active if there is a current streak or the grace window is open.
    var isActive: Bool {
        currentStreak > 0 || isInGracePeriod
    }

    /// How many whole days remain before the streak resets (0 means it resets today or has already reset).
    var daysUntilReset: Int {
        guard let lastActivity = lastActivityAt else { return 0 }
        let daysSince = Calendar.current.daysBetween(lastActivity.dateValue(), and: Date())
        let remaining = type.gracePeriodDays - daysSince
        return max(0, remaining)
    }
}

// MARK: - SpiritualNotificationIntensityMode

enum SpiritualNotificationIntensityMode: String, Codable, CaseIterable {
    case minimal
    case balanced
    case encouraging
    case activeCommunity

    var displayName: String {
        switch self {
        case .minimal:           return "Minimal"
        case .balanced:          return "Balanced"
        case .encouraging:       return "Encouraging"
        case .activeCommunity:   return "Active Community"
        }
    }

    var description: String {
        switch self {
        case .minimal:
            return "One gentle nudge per day. Quiet presence, no noise."
        case .balanced:
            return "A handful of thoughtful notifications spread through the day."
        case .encouraging:
            return "Regular reminders to help you stay connected to your rhythm."
        case .activeCommunity:
            return "Stay fully connected — community activity, verses, and reminders throughout the day."
        }
    }

    var dailyLimit: Int {
        switch self {
        case .minimal:           return 1
        case .balanced:          return 3
        case .encouraging:       return 5
        case .activeCommunity:   return 8
        }
    }
}

// MARK: - SpiritualNotificationCategory

enum SpiritualNotificationCategory: String, Codable, CaseIterable {
    case dailyVerse
    case readingReminder
    case prayerReminder
    case communityDigest
    case streakReminder
    case quietReturn
    case milestoneReflection
}

// MARK: - NotificationPreferences

struct NotificationPreferences: Codable {
    var intensity: SpiritualNotificationIntensityMode
    var enabledCategories: Set<SpiritualNotificationCategory>
    /// Preferred time for the daily verse notification (HH:mm, 24-hour).
    var preferredVerseTime: String
    /// Preferred time for reading/prayer reminders (HH:mm, 24-hour).
    var preferredReminderTime: String
    var eveningDigestEnabled: Bool
    var morningDigestEnabled: Bool

    init(
        intensity: SpiritualNotificationIntensityMode,
        enabledCategories: Set<SpiritualNotificationCategory>,
        preferredVerseTime: String = "08:00",
        preferredReminderTime: String = "19:00",
        eveningDigestEnabled: Bool = true,
        morningDigestEnabled: Bool = true
    ) {
        self.intensity = intensity
        self.enabledCategories = enabledCategories
        self.preferredVerseTime = preferredVerseTime
        self.preferredReminderTime = preferredReminderTime
        self.eveningDigestEnabled = eveningDigestEnabled
        self.morningDigestEnabled = morningDigestEnabled
    }

    init(
        intensity: NotificationIntensityMode,
        enabledCategories: Set<SpiritualNotificationCategory>,
        preferredVerseTime: String = "08:00",
        preferredReminderTime: String = "19:00",
        eveningDigestEnabled: Bool = true,
        morningDigestEnabled: Bool = true
    ) {
        self.init(
            intensity: SpiritualNotificationIntensityMode(rawValue: intensity.rawValue) ?? .balanced,
            enabledCategories: enabledCategories,
            preferredVerseTime: preferredVerseTime,
            preferredReminderTime: preferredReminderTime,
            eveningDigestEnabled: eveningDigestEnabled,
            morningDigestEnabled: morningDigestEnabled
        )
    }

    static var defaults: NotificationPreferences {
        NotificationPreferences(
            intensity: SpiritualNotificationIntensityMode.balanced,
            enabledCategories: [
                .dailyVerse,
                .readingReminder,
                .prayerReminder,
                .communityDigest,
                .milestoneReflection
            ],
            preferredVerseTime: "08:00",
            preferredReminderTime: "19:00",
            eveningDigestEnabled: true,
            morningDigestEnabled: true
        )
    }
}

// MARK: - SabbathModeSettings

struct SabbathModeSettings: Codable {
    var enabled: Bool
    /// 0 = Sunday … 6 = Saturday (matches `Calendar.Component.weekday - 1`)
    var startDay: Int
    var startHour: Int
    var endDay: Int
    var endHour: Int

    init(
        enabled: Bool = false,
        startDay: Int = 0,
        startHour: Int = 18,
        endDay: Int = 1,
        endHour: Int = 6
    ) {
        self.enabled = enabled
        self.startDay = startDay
        self.startHour = startHour
        self.endDay = endDay
        self.endHour = endHour
    }

    init(
        isEnabled: Bool,
        startDay: Int = 0,
        startHour: Int = 18,
        endDay: Int = 1,
        endHour: Int = 6
    ) {
        self.init(enabled: isEnabled, startDay: startDay, startHour: startHour, endDay: endDay, endHour: endHour)
    }

    /// Returns `true` when Sabbath mode is both enabled and currently in effect.
    var isCurrentlyActive: Bool {
        guard enabled else { return false }
        let now = Date()
        let calendar = Calendar.current
        // weekday: 1 = Sunday … 7 = Saturday → convert to 0-based
        let weekday = (calendar.component(.weekday, from: now) - 1) // 0=Sun…6=Sat
        let hour = calendar.component(.hour, from: now)

        // Build a linear "minutes since Sunday 00:00" for comparison.
        let minutesPerDay = 24 * 60
        let currentMinutes = weekday * minutesPerDay + hour * 60
        let startMinutes  = startDay  * minutesPerDay + startHour  * 60
        var endMinutes    = endDay    * minutesPerDay + endHour    * 60

        // If the window wraps across the week boundary (e.g. Sat evening → Sun morning)
        // shift end forward by one week so the comparison stays linear.
        if endMinutes <= startMinutes {
            endMinutes += 7 * minutesPerDay
        }

        // Handle the wrap-around case: if currentMinutes < startMinutes, check
        // whether adding a week makes it fall inside the window.
        let adjustedCurrent = currentMinutes < startMinutes
            ? currentMinutes + 7 * minutesPerDay
            : currentMinutes

        return adjustedCurrent >= startMinutes && adjustedCurrent < endMinutes
    }
}

// MARK: - SpiritualRhythmSettings

/// Stored at `users/{uid}/spiritualRhythm/main`.
struct SpiritualRhythmSettings: Codable {
    var notificationPreferences: NotificationPreferences
    var sabbathMode: SabbathModeSettings
    var momentumState: SpiritualMomentumState
    var lastActiveAt: Timestamp?
    /// Non-nil once the inactivity pause has been activated (>= 7 days without activity).
    var inactivityPauseActivatedAt: Timestamp?
    /// Non-nil once the single pause notification has been sent; prevents re-sending.
    var pauseNotificationSentAt: Timestamp?
    var enabledStreakTypes: Set<SpiritualStreakType>
    var updatedAt: Timestamp?

    init(
        notificationPreferences: NotificationPreferences,
        sabbathMode: SabbathModeSettings,
        momentumState: SpiritualMomentumState = .growing,
        lastActiveAt: Timestamp? = nil,
        inactivityPauseActivatedAt: Timestamp? = nil,
        pauseNotificationSentAt: Timestamp? = nil,
        enabledStreakTypes: Set<SpiritualStreakType> = Set(SpiritualStreakType.allCases),
        updatedAt: Timestamp? = nil
    ) {
        self.notificationPreferences = notificationPreferences
        self.sabbathMode = sabbathMode
        self.momentumState = momentumState
        self.lastActiveAt = lastActiveAt
        self.inactivityPauseActivatedAt = inactivityPauseActivatedAt
        self.pauseNotificationSentAt = pauseNotificationSentAt
        self.enabledStreakTypes = enabledStreakTypes
        self.updatedAt = updatedAt
    }

    init(
        sabbathMode: SabbathModeSettings,
        notificationPreferences: NotificationPreferences,
        inactivityPauseActivatedAt: Date?
    ) {
        self.init(
            notificationPreferences: notificationPreferences,
            sabbathMode: sabbathMode,
            inactivityPauseActivatedAt: inactivityPauseActivatedAt.map(Timestamp.init(date:))
        )
    }

    // MARK: Computed

    var daysSinceLastActive: Int {
        guard let lastActive = lastActiveAt else { return 0 }
        return Calendar.current.daysBetween(lastActive.dateValue(), and: Date())
    }

    var isInactivityPauseActive: Bool {
        inactivityPauseActivatedAt != nil
    }

    // MARK: Defaults

    static var defaults: SpiritualRhythmSettings {
        SpiritualRhythmSettings(
            notificationPreferences: .defaults,
            sabbathMode: SabbathModeSettings(),
            momentumState: .growing,
            lastActiveAt: nil,
            inactivityPauseActivatedAt: nil,
            pauseNotificationSentAt: nil,
            enabledStreakTypes: Set(SpiritualStreakType.allCases),
            updatedAt: nil
        )
    }
}

// MARK: - Calendar Helpers (file-private)

private extension Calendar {
    /// Returns the number of whole days between `start` and `end`.
    func daysBetween(_ start: Date, and end: Date) -> Int {
        let components = dateComponents([.day], from: startOfDay(for: start), to: startOfDay(for: end))
        return abs(components.day ?? 0)
    }
}
