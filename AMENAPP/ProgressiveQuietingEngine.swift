//
//  ProgressiveQuietingEngine.swift
//  AMENAPP
//
//  Progressive notification filtering: low → medium → critical
//

import Foundation
import FirebaseFirestore

/// Gradually reduces notification volume as quiet hours approach
@MainActor
class ProgressiveQuietingEngine: ObservableObject {
    static let shared = ProgressiveQuietingEngine()

    private let calendar = Calendar.current

    @Published var currentQuietLevel: QuietLevel = .none

    enum QuietLevel: Int, Comparable {
        case none = 0           // All notifications
        case minimal = 1        // Filter out low-priority (likes, basic follows)
        case moderate = 2       // Only medium+ priority (comments, replies, DMs)
        case substantial = 3    // Only high+ priority (questions, mentions, prayers)
        case critical = 4       // Only critical (crisis, urgent DMs)

        static func < (lhs: QuietLevel, rhs: QuietLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var displayName: String {
            switch self {
            case .none: return "All Notifications"
            case .minimal: return "Mostly Quiet"
            case .moderate: return "Moderately Quiet"
            case .substantial: return "Very Quiet"
            case .critical: return "Critical Only"
            }
        }

        var description: String {
            switch self {
            case .none:
                return "Receiving all notifications"
            case .minimal:
                return "Filtering likes and basic follows"
            case .moderate:
                return "Only comments, replies, and messages"
            case .substantial:
                return "Only important interactions"
            case .critical:
                return "Only urgent and crisis notifications"
            }
        }

        var minimumPriority: Double {
            switch self {
            case .none: return 0.0
            case .minimal: return 0.3
            case .moderate: return 0.5
            case .substantial: return 0.7
            case .critical: return 0.9
            }
        }
    }

    // MARK: - Progressive Quieting Logic

    /// Calculate current quiet level based on time until quiet hours
    func calculateQuietLevel(quietHoursStart: String, quietHoursEnd: String) -> QuietLevel {
        let now = Date()

        guard let startTime = parseTime(quietHoursStart),
              let endTime = parseTime(quietHoursEnd) else {
            return .none
        }

        // Check if currently in quiet hours
        if isInQuietHours(now: now, start: startTime, end: endTime) {
            return .critical
        }

        // Calculate time until quiet hours start
        let minutesUntilQuiet = minutesUntil(time: startTime, from: now)

        // Progressive levels:
        // 2+ hours before: none
        // 1-2 hours before: minimal
        // 30min-1hr before: moderate
        // 15-30min before: substantial
        // <15min before: critical

        if minutesUntilQuiet < 0 || minutesUntilQuiet > 120 {
            return .none
        } else if minutesUntilQuiet > 60 {
            return .minimal
        } else if minutesUntilQuiet > 30 {
            return .moderate
        } else if minutesUntilQuiet > 15 {
            return .substantial
        } else {
            return .critical
        }
    }

    /// Determine if a notification should be delivered based on current quiet level
    func shouldDeliver(
        notification: NotificationRouting,
        currentLevel: QuietLevel
    ) -> NotificationDecision {
        // Crisis alerts always get through
        if notification.category == .crisisAlerts {
            return .deliver(channel: .push, reason: "Crisis alert override")
        }

        // Check priority against quiet level threshold
        let priority = notification.priority.score

        if priority >= currentLevel.minimumPriority {
            return .deliver(channel: .push, reason: "Priority \(String(format: "%.2f", priority)) exceeds threshold")
        }

        // Determine what to do with the notification
        switch currentLevel {
        case .none:
            return .deliver(channel: .push, reason: "No quiet restrictions")

        case .minimal:
            // Batch low-priority notifications
            if priority < 0.3 {
                return .batch(reason: "Low priority during minimal quiet")
            } else {
                return .deliver(channel: .push, reason: "Above minimal threshold")
            }

        case .moderate:
            // Batch medium-low, delay delivery
            if priority < 0.5 {
                return .batch(reason: "Below moderate threshold")
            } else {
                return .deliver(channel: .push, reason: "Above moderate threshold")
            }

        case .substantial:
            // Only high-priority gets through
            if priority < 0.7 {
                return .suppress(reason: "Below substantial threshold")
            } else {
                return .deliver(channel: .push, reason: "High priority")
            }

        case .critical:
            // Only critical gets through
            if priority < 0.9 {
                return .suppress(reason: "Below critical threshold")
            } else {
                return .deliver(channel: .push, reason: "Critical priority")
            }
        }
    }

    enum NotificationDecision {
        case deliver(channel: NotificationChannel, reason: String)
        case batch(reason: String)
        case suppress(reason: String)
    }

    // MARK: - Time Calculations

    private func parseTime(_ timeString: String) -> DateComponents? {
        // Parse "HH:mm" format
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return nil
        }

        return DateComponents(hour: hour, minute: minute)
    }

    private func minutesUntil(time: DateComponents, from now: Date) -> Int {
        guard let targetTime = calendar.nextDate(
            after: now,
            matching: time,
            matchingPolicy: .nextTime
        ) else {
            return -1
        }

        let interval = targetTime.timeIntervalSince(now)
        return Int(interval / 60)
    }

    private func isInQuietHours(now: Date, start: DateComponents, end: DateComponents) -> Bool {
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)

        guard let startHour = start.hour,
              let startMinute = start.minute,
              let endHour = end.hour,
              let endMinute = end.minute else {
            return false
        }

        let currentTotalMinutes = currentHour * 60 + currentMinute
        let startTotalMinutes = startHour * 60 + startMinute
        let endTotalMinutes = endHour * 60 + endMinute

        // Handle overnight quiet hours (e.g., 22:00 - 07:00)
        if startTotalMinutes > endTotalMinutes {
            return currentTotalMinutes >= startTotalMinutes || currentTotalMinutes < endTotalMinutes
        } else {
            return currentTotalMinutes >= startTotalMinutes && currentTotalMinutes < endTotalMinutes
        }
    }

    // MARK: - UI Feedback

    /// Generate user-facing feedback about current quiet level
    func generateQuietFeedback() -> QuietFeedback {
        let level = currentQuietLevel

        let emoji: String
        switch level {
        case .none: emoji = "🔔"
        case .minimal: emoji = "🔕"
        case .moderate: emoji = "🌙"
        case .substantial: emoji = "💤"
        case .critical: emoji = "🛑"
        }

        let color: String
        switch level {
        case .none: color = "blue"
        case .minimal: color = "green"
        case .moderate: color = "orange"
        case .substantial: color = "purple"
        case .critical: color = "red"
        }

        return QuietFeedback(
            level: level,
            emoji: emoji,
            color: color,
            message: level.description
        )
    }

    struct QuietFeedback {
        let level: QuietLevel
        let emoji: String
        let color: String
        let message: String
    }

    // MARK: - Category-Specific Progressive Rules

    /// Apply progressive filtering rules per notification category
    func applyProgressiveRules(
        category: NotificationCategory,
        priority: Double,
        quietLevel: QuietLevel
    ) -> Bool {
        // Define category-specific thresholds

        switch category {
        case .directMessages:
            // DMs are more important
            return priority >= max(0.3, quietLevel.minimumPriority - 0.2)

        case .replies:
            // Replies are important
            return priority >= max(0.4, quietLevel.minimumPriority - 0.1)

        case .mentions:
            // Mentions are fairly important
            return priority >= quietLevel.minimumPriority

        case .reactions:
            // Reactions are low priority
            return priority >= quietLevel.minimumPriority + 0.1

        case .follows:
            // Follows are low priority
            return priority >= quietLevel.minimumPriority + 0.2

        case .prayerUpdates:
            // Prayer is important
            return priority >= max(0.4, quietLevel.minimumPriority - 0.1)

        case .churchNotes:
            // Church notes moderately important
            return priority >= quietLevel.minimumPriority

        case .reposts:
            // Reposts are low priority
            return priority >= quietLevel.minimumPriority + 0.1

        case .groupMessages:
            // Group messages moderately important
            return priority >= quietLevel.minimumPriority

        case .crisisAlerts:
            // Always deliver
            return true
        }
    }
}

// MARK: - Supporting Types

struct NotificationRouting {
    let category: NotificationCategory
    let priority: NotificationPriority
    let timestamp: Date
}

struct NotificationPriority {
    let score: Double
}

enum NotificationChannel {
    case push
    case inApp
    case badge
}
