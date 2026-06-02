//
//  CalmNotificationPolicyEngine.swift
//  AMENAPP
//
//  Calm Control + Spiritual Rhythm OS — Notification Policy Engine
//
//  Client-side pre-flight gate for local notification scheduling.
//  The backend (Cloud Functions) is authoritative; this engine is a
//  fast-path check that avoids scheduling suppressible notifications
//  before they reach UNUserNotificationCenter.
//
//  Copy philosophy:
//    - Never shame, guilt, or pressure.
//    - Never reference streaks in a loss-aversion frame ("You're losing your streak!").
//    - All messages are invitational ("Ready to continue?") or informational ("A moment for scripture.").

// MARK: - Notification Service Ownership
// This service owns: Client-side eligibility gating for CalmNotificationCategory types
//                    (dailyVerse, readingReminder, prayerReminder, communityDigest, streakReminder,
//                    quietReturn, milestoneReflection); evaluates inactivity-pause suppression,
//                    Sabbath Mode suppression, presence-state suppression, and intensity-mode filtering;
//                    non-manipulative pre-written notification copy for all 7 categories.
// It does NOT own: Social-activity notifications (amens, follows, comments, messages), action-thread
//                  events, prayer-answered fan-out, push delivery, Firestore writes, priority scoring,
//                  or batching. NOTE: Near-duplicate of NotificationPolicyEngine.swift (CalmControl/Services)
//                  and SpiritualNotificationPolicyEngine.swift — consolidation candidate.
// Canonical routing reference: See NotificationServiceMap.md

import Foundation

// MARK: - Notification Categories

/// All notification categories this engine can reason about.
enum CalmNotificationCategory: String, CaseIterable {

    case dailyVerse          // Morning scripture delivery
    case readingReminder     // Bible reading plan prompt
    case prayerReminder      // Prayer session prompt
    case communityDigest     // Rolled-up community activity digest
    case streakReminder      // Spiritual rhythm streak nudge
    case quietReturn         // Grace re-engagement after 7+ days of inactivity
    case milestoneReflection // Celebrate a spiritual growth milestone

    // MARK: User-facing title for settings UI

    var title: String {
        switch self {
        case .dailyVerse:          return "Daily Verse"
        case .readingReminder:     return "Reading Reminder"
        case .prayerReminder:      return "Prayer Reminder"
        case .communityDigest:     return "Community Digest"
        case .streakReminder:      return "Rhythm Reminder"
        case .quietReturn:         return "Welcome Back"
        case .milestoneReflection: return "Milestone Reflection"
        }
    }

    // MARK: Essential categories

    /// Essential categories are never suppressed during inactivity pauses or by intensity filters.
    /// dailyVerse: scripture delivery is always available regardless of session state.
    /// quietReturn: the sole re-engagement touchpoint after a long absence; suppressing it defeats its purpose.
    var isEssential: Bool {
        switch self {
        case .dailyVerse, .quietReturn: return true
        default:                        return false
        }
    }

    // MARK: Suppression rules

    /// Non-essential categories are suppressed when the inactivity pause policy is active
    /// (user has been absent 7+ days). We send only quietReturn during this window.
    var suppresedDuringInactivity: Bool { !isEssential }

    /// Every category except quietReturn is silenced during Sabbath Mode.
    /// The quietReturn notification intentionally survives because a returning user
    /// may not know they had Sabbath Mode active.
    var suppressedDuringSabbath: Bool { self != .quietReturn }
}

// MARK: - Notification Intensity Modes

/// Controls how many notification categories a user receives overall.
/// Users set this in Settings > Notifications. Default is .balanced.
enum NotificationIntensityMode: String, Codable, CaseIterable {

    /// Absolute minimum: only scripture and re-engagement.
    case minimal
    /// Default: quiet but present. No repetitive streak or milestone nudges.
    case balanced
    /// All categories active. Grace-toned, never manipulative.
    case encouraging
    /// Full community awareness. Same content as encouraging; label distinguishes the intent.
    case activeCommunity

    // MARK: User-facing strings

    var label: String {
        switch self {
        case .minimal:         return "Minimal"
        case .balanced:        return "Balanced"
        case .encouraging:     return "Encouraging"
        case .activeCommunity: return "Active Community"
        }
    }

    var description: String {
        switch self {
        case .minimal:
            return "Daily verse and re-engagement only. Everything else is silenced."
        case .balanced:
            return "Scripture, prayer, and community digests. Streak nudges are off."
        case .encouraging:
            return "All categories active. Gentle, grace-based tone throughout."
        case .activeCommunity:
            return "Full notifications including community activity and milestones."
        }
    }

    var dailyLimit: Int {
        switch self {
        case .minimal: return 1
        case .balanced: return 3
        case .encouraging: return 5
        case .activeCommunity: return 8
        }
    }

    // MARK: Category filter

    /// Returns true if a notification of the given category may be delivered
    /// at this intensity level.
    func allows(category: CalmNotificationCategory) -> Bool {
        switch self {
        case .minimal:
            // Only essential categories pass through.
            return category == .dailyVerse || category == .quietReturn
        case .balanced:
            // Streak nudges and milestone reflections are too frequent for a balanced mode.
            return category != .streakReminder && category != .milestoneReflection
        case .encouraging:
            // All categories are allowed; copy is always grace-toned.
            return true
        case .activeCommunity:
            // All categories are allowed.
            return true
        }
    }
}

// MARK: - Eligibility Result

/// The result of a pre-flight eligibility check.
enum NotificationEligibilityResult: Equatable {
    case eligible
    case suppressed(reason: SuppressReason)
}

/// The reason a notification was suppressed.
enum SuppressReason: String, Equatable {
    /// User has been inactive for 7+ days; inactivity pause policy active.
    case inactivityPause
    /// Sabbath Mode is active for this user.
    case sabbathMode
    /// User's current presence state suppresses this category.
    case presenceState
    /// Intensity mode does not allow this category.
    case intensityMode
}

// MARK: - Notification Content

/// Resolved title and body strings ready to pass to UNMutableNotificationContent.
struct NotificationContent {
    let title: String
    let body: String
    let category: CalmNotificationCategory
}

// MARK: - Policy Engine

/// Client-side pre-flight check for local notification scheduling.
///
/// Call `isEligible(...)` before scheduling any `UNNotificationRequest`.
/// The backend Cloud Functions are the authoritative notification gate;
/// this engine prevents unnecessary scheduling work on device.
///
/// Thread safety: @MainActor — all reads happen on the main actor consistent
/// with SwiftUI's environment and `UNUserNotificationCenter` delegate callbacks.
@MainActor
final class CalmNotificationPolicyEngine: ObservableObject {

    static let shared = CalmNotificationPolicyEngine()

    private init() {}

    // MARK: - Eligibility Check

    /// Determines whether a notification may be delivered given the user's
    /// current state. Returns `.eligible` or `.suppressed(reason:)`.
    ///
    /// Evaluation order (first match wins):
    ///   1. Inactivity suppression — 7+ days absent pauses non-essential categories.
    ///   2. Sabbath Mode — user has explicitly entered a digital sabbath.
    ///   3. Presence state — derived sabbath-equivalent presence states.
    ///   4. Intensity mode — user's chosen notification volume level.
    ///
    /// - Parameters:
    ///   - category:           The category of notification to evaluate.
    ///   - intensityMode:      The user's current intensity preference.
    ///   - sabbathModeActive:  True when the user has activated Sabbath Mode via settings.
    ///   - inactivityPaused:   True when the inactivity pause policy has fired
    ///                         (user absent 7+ days and `inactivityPausePolicyEnabled` flag is on).
    ///   - presenceState:      The user's current `PresenceState` from `CalmControlModels`.
    func isEligible(
        category: CalmNotificationCategory,
        intensityMode: NotificationIntensityMode,
        sabbathModeActive: Bool,
        inactivityPaused: Bool,
        presenceState: PresenceState
    ) -> NotificationEligibilityResult {

        // 1. Inactivity suppression (7+ days)
        if inactivityPaused && category.suppresedDuringInactivity {
            return .suppressed(reason: .inactivityPause)
        }

        // 2. Sabbath Mode (explicit user preference)
        if sabbathModeActive && category.suppressedDuringSabbath {
            return .suppressed(reason: .sabbathMode)
        }

        // 3. Presence state suppression
        // .sabbathing is the presence-layer equivalent of explicit Sabbath Mode.
        if presenceState == .sabbathing && category.suppressedDuringSabbath {
            return .suppressed(reason: .presenceState)
        }

        // 4. Intensity mode filter
        if !intensityMode.allows(category: category) {
            return .suppressed(reason: .intensityMode)
        }

        return .eligible
    }

    // MARK: - Notification Copy

    /// Returns pre-written, non-manipulative notification copy for each category.
    ///
    /// All copy is invitational or informational. Streak-related messages never
    /// reference loss or breaking a streak. Milestone messages are celebratory,
    /// not comparative.
    ///
    /// - Parameters:
    ///   - category:    The notification category.
    ///   - streakCount: Optional current streak length; used only to frame milestones positively.
    func notificationCopy(
        for category: CalmNotificationCategory,
        streakCount: Int? = nil
    ) -> NotificationContent {
        switch category {

        case .dailyVerse:
            return NotificationContent(
                title: "Your verse for today",
                body: "A moment of scripture is ready when you are.",
                category: category
            )

        case .readingReminder:
            return NotificationContent(
                title: "Reading plan",
                body: "Your reading plan is waiting. Whenever you're ready.",
                category: category
            )

        case .prayerReminder:
            return NotificationContent(
                title: "A moment for prayer",
                body: "Step away for a few minutes. Your community is praying too.",
                category: category
            )

        case .communityDigest:
            return NotificationContent(
                title: "What your community shared",
                body: "A few things from your community while you were away.",
                category: category
            )

        case .streakReminder:
            // Explicitly non-loss-aversion. We celebrate continuity, not fear of loss.
            if let count = streakCount, count > 0 {
                return NotificationContent(
                    title: "Your rhythm continues",
                    body: "\(count) day\(count == 1 ? "" : "s") of intentional practice. Ready to continue?",
                    category: category
                )
            }
            return NotificationContent(
                title: "Keep the rhythm going",
                body: "Ready to continue your spiritual practice today?",
                category: category
            )

        case .quietReturn:
            // Grace-first re-engagement after 7+ days. No guilt, no pressure.
            return NotificationContent(
                title: "Welcome back",
                body: "No pressure. Your community and your scripture are here whenever you're ready.",
                category: category
            )

        case .milestoneReflection:
            // Celebrate faithfulness without comparison or score-keeping language.
            if let count = streakCount, count > 0 {
                return NotificationContent(
                    title: "A moment to reflect",
                    body: "\(count) day\(count == 1 ? "" : "s") of faithful practice. Take a moment to acknowledge that.",
                    category: category
                )
            }
            return NotificationContent(
                title: "A moment to reflect",
                body: "You've reached a milestone in your spiritual practice. Take a moment to acknowledge that.",
                category: category
            )
        }
    }
}
