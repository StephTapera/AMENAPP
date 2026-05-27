// SpiritualNotificationPolicyEngine.swift
// AMENAPP — SpiritualRhythmOS
//
// Pure logic layer. No Firebase. Foundation only.
// Evaluates whether a notification should fire and provides warm, non-guilt copy.
// Backend Cloud Functions enforce server-side policy; this engine is the client gate.
//
// Design principles:
//   - No guilt-based copy. All messages are warm, supportive, and optional in tone.
//   - After 7 days inactive: suppress all non-essential categories.
//   - Only one respectful pause notice is sent at the 7-day mark (.quietReturn).
//   - Sabbath mode silences everything, no exceptions.
//   - All categories are user-configurable via SpiritualRhythmSettings.

import Foundation

// MARK: - Supporting Domain Types
// These types live here so the engine is fully self-contained within SpiritualRhythmOS.
// They are consumed by the broader module wherever notification scheduling is needed.

/// The seven notification categories the policy engine understands.
enum SpiritualNotificationCategory: String, CaseIterable, Hashable, Sendable {
    case dailyVerse
    case readingReminder
    case prayerReminder
    case communityDigest
    case streakReminder
    case quietReturn
    case milestoneReflection
}

/// How many notifications per day the user wants.
enum NotificationIntensityMode: String, CaseIterable, Sendable {
    case minimal           // 1/day
    case balanced          // 3/day
    case encouraging       // 5/day
    case activeCommunity   // 8/day

    /// Hard daily cap for this intensity level.
    var dailyLimit: Int {
        switch self {
        case .minimal:          return 1
        case .balanced:         return 3
        case .encouraging:      return 5
        case .activeCommunity:  return 8
        }
    }
}

/// User notification preferences: which categories are on and at what intensity.
struct NotificationPreferences: Equatable, Sendable {
    var intensity: NotificationIntensityMode
    var enabledCategories: Set<SpiritualNotificationCategory>

    init(
        intensity: NotificationIntensityMode = .balanced,
        enabledCategories: Set<SpiritualNotificationCategory> = Set(SpiritualNotificationCategory.allCases)
    ) {
        self.intensity = intensity
        self.enabledCategories = enabledCategories
    }

    static let `default` = NotificationPreferences()
}

/// Sabbath mode configuration. isCurrentlyActive is evaluated at call time.
struct SabbathModeSettings: Equatable, Sendable {
    /// Whether the user has enabled sabbath mode at all.
    var isEnabled: Bool
    /// Day of week on which sabbath begins (1 = Sunday … 7 = Saturday; matches Calendar.weekday).
    var dayOfWeek: Int
    /// Hour (0-23) sabbath begins on that day.
    var startHour: Int
    /// Duration in hours (e.g. 24 = full day).
    var durationHours: Int

    init(
        isEnabled: Bool = false,
        dayOfWeek: Int = 1,
        startHour: Int = 18,
        durationHours: Int = 24
    ) {
        self.isEnabled = isEnabled
        self.dayOfWeek = dayOfWeek
        self.startHour = startHour
        self.durationHours = durationHours
    }

    /// True if right now falls inside the configured sabbath window.
    var isCurrentlyActive: Bool {
        guard isEnabled else { return false }
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.weekday, .hour], from: now)
        guard let currentWeekday = components.weekday,
              let currentHour = components.hour else { return false }

        // Build the sabbath start as a concrete hour-of-week (0 … 167).
        let sabbathStartHourOfWeek = (dayOfWeek - 1) * 24 + startHour
        let sabbathEndHourOfWeek   = sabbathStartHourOfWeek + durationHours

        let currentHourOfWeek = (currentWeekday - 1) * 24 + currentHour

        // Handle wrap-around at end of week (168 hours/week).
        if sabbathEndHourOfWeek <= 168 {
            return currentHourOfWeek >= sabbathStartHourOfWeek &&
                   currentHourOfWeek < sabbathEndHourOfWeek
        } else {
            // Wraps into next week.
            let wrappedEnd = sabbathEndHourOfWeek - 168
            return currentHourOfWeek >= sabbathStartHourOfWeek ||
                   currentHourOfWeek < wrappedEnd
        }
    }
}

/// A single spiritual streak (scripture, prayer, reflection, etc.).
struct SpiritualStreak: Equatable, Sendable {
    var category: SpiritualNotificationCategory
    var currentCount: Int

    init(category: SpiritualNotificationCategory, currentCount: Int = 0) {
        self.category = category
        self.currentCount = currentCount
    }
}

/// The top-level settings object consumed by the policy engine.
struct SpiritualRhythmSettings: Equatable, Sendable {
    var sabbathMode: SabbathModeSettings
    var notificationPreferences: NotificationPreferences
    /// When non-nil, the inactivity pause is considered active.
    var inactivityPauseActivatedAt: Date?
    /// Preferred verse delivery time in "HH:mm" format (e.g. "07:00").
    var preferredVerseTime: String
    /// Preferred general reminder time in "HH:mm" format (e.g. "08:00").
    var preferredReminderTime: String

    init(
        sabbathMode: SabbathModeSettings = SabbathModeSettings(),
        notificationPreferences: NotificationPreferences = .default,
        inactivityPauseActivatedAt: Date? = nil,
        preferredVerseTime: String = "07:00",
        preferredReminderTime: String = "08:00"
    ) {
        self.sabbathMode = sabbathMode
        self.notificationPreferences = notificationPreferences
        self.inactivityPauseActivatedAt = inactivityPauseActivatedAt
        self.preferredVerseTime = preferredVerseTime
        self.preferredReminderTime = preferredReminderTime
    }

    /// True when the user has been flagged as inactive (pause window is open).
    var isInactivityPauseActive: Bool {
        inactivityPauseActivatedAt != nil
    }

    static let `default` = SpiritualRhythmSettings()
}

// MARK: - Policy Result Types

/// Why a notification was suppressed. Never surfaced to the user directly.
enum NotificationSuppressReason: String, Sendable {
    case sabbathMode
    case inactivityPause
    case intensityLimitReached
    case categoryDisabled
    case duplicateToday
}

/// The policy engine's verdict for a single notification evaluation.
struct NotificationEligibilityResult: Sendable {
    let shouldSend: Bool
    let reason: NotificationSuppressReason?
    let suggestedCopy: String?

    static func allowed(copy: String) -> NotificationEligibilityResult {
        NotificationEligibilityResult(shouldSend: true, reason: nil, suggestedCopy: copy)
    }

    static func suppressed(reason: NotificationSuppressReason) -> NotificationEligibilityResult {
        NotificationEligibilityResult(shouldSend: false, reason: reason, suggestedCopy: nil)
    }
}

/// A resolved schedule entry ready to hand to UNUserNotificationCenter.
struct ScheduledNotificationConfig: Sendable {
    let category: SpiritualNotificationCategory
    let hour: Int
    let minute: Int
    let title: String
    let body: String
}

// MARK: - Policy Engine

@MainActor
final class SpiritualNotificationPolicyEngine: ObservableObject {

    static let shared = SpiritualNotificationPolicyEngine()

    // Seeds used for per-session copy variation. Refreshed per evaluate call.
    private var copyVariantSeed: UInt64 = 0

    private init() {
        copyVariantSeed = UInt64(Date.timeIntervalSinceReferenceDate * 1000)
    }

    // MARK: - Core Evaluation

    /// Decides whether a notification for `category` should be sent right now.
    ///
    /// Evaluation order:
    ///   1. Sabbath mode — hard stop.
    ///   2. Inactivity pause — only .quietReturn passes through.
    ///   3. Intensity cap — daily send count vs. the mode's limit.
    ///   4. Category disabled — user turned this category off.
    ///   5. Duplicate guard — category already sent today.
    ///   6. Allowed — return copy.
    func evaluate(
        category: SpiritualNotificationCategory,
        settings: SpiritualRhythmSettings,
        sentTodayCount: Int,
        alreadySentCategories: Set<SpiritualNotificationCategory>
    ) -> NotificationEligibilityResult {

        // 1. Sabbath mode silences everything.
        if settings.sabbathMode.isCurrentlyActive {
            return .suppressed(reason: .sabbathMode)
        }

        // 2. Inactivity pause: only .quietReturn is allowed through.
        if settings.isInactivityPauseActive && category != .quietReturn {
            return .suppressed(reason: .inactivityPause)
        }

        // 3. Daily intensity cap.
        let limit = settings.notificationPreferences.intensity.dailyLimit
        if sentTodayCount >= limit {
            return .suppressed(reason: .intensityLimitReached)
        }

        // 4. Category disabled by user.
        if !settings.notificationPreferences.enabledCategories.contains(category) {
            return .suppressed(reason: .categoryDisabled)
        }

        // 5. Duplicate — this category was already sent today.
        if alreadySentCategories.contains(category) {
            return .suppressed(reason: .duplicateToday)
        }

        // 6. Allowed — generate copy.
        let copy = suggestedCopy(for: category, streaks: [])
        return .allowed(copy: copy)
    }

    // MARK: - Copy Generation

    /// Returns warm, non-guilt copy for a notification category.
    /// Picks randomly from 2-3 variants per category.
    func suggestedCopy(for category: SpiritualNotificationCategory, streaks: [SpiritualStreak]) -> String {
        let variants: [String]

        switch category {
        case .dailyVerse:
            variants = [
                "Your verse for today is ready.",
                "A word for your morning.",
                "Something to carry with you today."
            ]

        case .readingReminder:
            variants = [
                "Continue where you left off.",
                "A few minutes with scripture today?",
                "Your reading is waiting whenever you're ready."
            ]

        case .prayerReminder:
            variants = [
                "A moment to pray.",
                "Your prayer time is here.",
                "Pause and bring what's on your heart."
            ]

        case .communityDigest:
            variants = [
                "See what your community is reflecting on.",
                "Your community has been active today.",
                "A few moments of shared reflection from your community."
            ]

        case .streakReminder:
            // Look up the best active streak for the most encouraging (but honest) message.
            let best = streaks.max(by: { $0.currentCount < $1.currentCount })
            let streakCount = best?.currentCount ?? 0
            if streakCount > 0 {
                variants = [
                    "You've been consistent. Keep going.",
                    "Your rhythm is building. Well done.",
                    "Another day in your spiritual practice. You're doing well."
                ]
            } else {
                // No active streak — still warm, zero pressure.
                variants = [
                    "Ready to begin a new rhythm today?",
                    "Small, steady steps add up. Today is a good day to start.",
                    "Whenever you're ready, we're here."
                ]
            }

        case .quietReturn:
            variants = [
                "We've missed you. No pressure — just here when you're ready.",
                "Welcome back whenever you are. There's no rush.",
                "This space is still here for you, whenever you'd like to return."
            ]

        case .milestoneReflection:
            variants = [
                "You've reached a meaningful milestone. Take a moment to reflect.",
                "Something worth pausing over — a milestone in your journey.",
                "A meaningful marker. Take it in."
            ]
        }

        return pickVariant(from: variants)
    }

    // MARK: - Inactivity Pause

    /// The one respectful message sent when a user crosses the 7-day inactivity threshold.
    /// Only dispatched once per inactivity window; Cloud Functions track the sent state.
    func inactivityPauseCopy() -> String {
        "We've noticed you've been away. We'll pause most notifications so you can rest. Come back whenever you're ready."
    }

    // MARK: - Schedule Builder

    /// Builds a list of notification schedule configs from the user's settings.
    /// Skips any category not in enabledCategories, and skips everything during sabbath.
    ///
    /// Time mapping:
    ///   - dailyVerse       → preferredVerseTime
    ///   - readingReminder  → preferredReminderTime
    ///   - prayerReminder   → preferredReminderTime + 1 hour (default 20:00 floor)
    ///   - communityDigest  → 07:00 (morning) and/or 21:00 (evening) variants
    ///   - streakReminder   → preferredReminderTime
    ///   - quietReturn      → not scheduled (sent on-demand by inactivity logic)
    ///   - milestoneReflection → preferredReminderTime
    func scheduleNotificationCategories(settings: SpiritualRhythmSettings) -> [ScheduledNotificationConfig] {
        // Nothing fires during an active sabbath.
        guard !settings.sabbathMode.isCurrentlyActive else { return [] }

        let enabled = settings.notificationPreferences.enabledCategories
        var configs: [ScheduledNotificationConfig] = []

        let (verseHour, verseMinute) = parseTime(settings.preferredVerseTime, fallbackHour: 7)
        let (reminderHour, reminderMinute) = parseTime(settings.preferredReminderTime, fallbackHour: 8)

        // Prayer reminder: +1 hour after reminder time, floored at 20:00.
        let rawPrayerHour = reminderHour + 1
        let prayerHour = rawPrayerHour < 20 ? 20 : min(rawPrayerHour, 22)
        let prayerMinute = reminderMinute

        // 1. Daily Verse
        if enabled.contains(.dailyVerse) {
            configs.append(ScheduledNotificationConfig(
                category: .dailyVerse,
                hour: verseHour,
                minute: verseMinute,
                title: "Daily Verse",
                body: suggestedCopy(for: .dailyVerse, streaks: [])
            ))
        }

        // 2. Reading Reminder
        if enabled.contains(.readingReminder) {
            configs.append(ScheduledNotificationConfig(
                category: .readingReminder,
                hour: reminderHour,
                minute: reminderMinute,
                title: "Reading Reminder",
                body: suggestedCopy(for: .readingReminder, streaks: [])
            ))
        }

        // 3. Prayer Reminder
        if enabled.contains(.prayerReminder) {
            configs.append(ScheduledNotificationConfig(
                category: .prayerReminder,
                hour: prayerHour,
                minute: prayerMinute,
                title: "Prayer Reminder",
                body: suggestedCopy(for: .prayerReminder, streaks: [])
            ))
        }

        // 4. Community Digest — morning edition at 07:00
        if enabled.contains(.communityDigest) {
            configs.append(ScheduledNotificationConfig(
                category: .communityDigest,
                hour: 7,
                minute: 0,
                title: "Morning Community Digest",
                body: suggestedCopy(for: .communityDigest, streaks: [])
            ))
            // Evening edition at 21:00 (only if intensity allows more than 1 per day)
            if settings.notificationPreferences.intensity.dailyLimit > 1 {
                configs.append(ScheduledNotificationConfig(
                    category: .communityDigest,
                    hour: 21,
                    minute: 0,
                    title: "Evening Community Digest",
                    body: "A quiet look at what your community shared today."
                ))
            }
        }

        // 5. Streak Reminder
        if enabled.contains(.streakReminder) {
            configs.append(ScheduledNotificationConfig(
                category: .streakReminder,
                hour: reminderHour,
                minute: max(reminderMinute, 30), // offset slightly from readingReminder
                title: "Spiritual Rhythm",
                body: suggestedCopy(for: .streakReminder, streaks: [])
            ))
        }

        // 6. Quiet Return — intentionally excluded from scheduled configs.
        // It is dispatched once on-demand by the inactivity logic, not on a schedule.

        // 7. Milestone Reflection
        if enabled.contains(.milestoneReflection) {
            configs.append(ScheduledNotificationConfig(
                category: .milestoneReflection,
                hour: reminderHour,
                minute: reminderMinute,
                title: "A Moment to Reflect",
                body: suggestedCopy(for: .milestoneReflection, streaks: [])
            ))
        }

        return configs
    }

    // MARK: - Inactivity Suppression Helpers

    /// Returns true if all non-essential notifications should be suppressed.
    /// Checks whether an inactivity pause has been activated (pause date is set).
    func shouldSuppressAllNonEssential(settings: SpiritualRhythmSettings) -> Bool {
        settings.inactivityPauseActivatedAt != nil
    }

    /// The only category that bypasses an inactivity pause.
    func essentialCategories() -> Set<SpiritualNotificationCategory> {
        [.quietReturn]
    }

    // MARK: - Private Helpers

    /// Parses an "HH:mm" string into (hour, minute). Returns `fallbackHour`:00 on failure.
    private func parseTime(_ timeString: String, fallbackHour: Int) -> (Int, Int) {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2,
              (0...23).contains(parts[0]),
              (0...59).contains(parts[1]) else {
            return (fallbackHour, 0)
        }
        return (parts[0], parts[1])
    }

    /// Picks a copy variant using a lightweight deterministic rotation
    /// so successive calls within the same session feel varied without true randomness deps.
    private func pickVariant(from variants: [String]) -> String {
        guard !variants.isEmpty else { return "" }
        copyVariantSeed = copyVariantSeed &* 6364136223846793005 &+ 1442695040888963407
        let index = Int((copyVariantSeed >> 33) % UInt64(variants.count))
        return variants[index]
    }
}
