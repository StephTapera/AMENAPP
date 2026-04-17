// SmartActivityCopyGenerator.swift
// AMENAPP
//
// Generates localizable display copy for SmartUserRow from a combined
// UserActivitySummary + RelationshipActivityState. Pure function — no I/O.

import Foundation

struct SmartActivityCopyGenerator {

    // MARK: - Generate

    static func generate(
        summary: UserActivitySummary?,
        relationship: RelationshipActivityState?
    ) -> SmartActivityCopyModel {
        guard let summary, summary.hasRecentActivity else {
            return .empty
        }

        let unseenCount = relationship?.totalUnseenCount ?? 0
        let hasUnseen = unseenCount > 0
        let hasMutual = relationship?.hasMutualInteraction ?? false

        let headline = makeHeadline(summary: summary, unseenCount: unseenCount)
        let subtext = makeSubtext(summary: summary, relationship: relationship, hasMutual: hasMutual)
        let badgeLabel = unseenCount > 0 ? badgeString(unseenCount) : nil
        let accent: ActivityAccentColor = hasUnseen ? .vibrant : (summary.isActive ? .moderate : .muted)

        return SmartActivityCopyModel(
            headline: headline,
            subtext: subtext,
            badgeCount: unseenCount,
            badgeLabel: badgeLabel,
            accentColor: accent
        )
    }

    // MARK: - Headline

    private static func makeHeadline(summary: UserActivitySummary, unseenCount: Int) -> String {
        let type = summary.primaryActivityType
        let relativeTime = summary.lastActiveAt.map { relativeTimeString($0) } ?? ""

        switch type {
        case .post:
            if unseenCount > 1 {
                return "\(unseenCount) new posts"
            } else if unseenCount == 1 {
                return "New post"
            } else if !relativeTime.isEmpty {
                return "Posted \(relativeTime)"
            }
            return "Active recently"

        case .prayer:
            if unseenCount > 0 {
                return "\(unseenCount) new prayer\(unseenCount > 1 ? "s" : "")"
            } else if !relativeTime.isEmpty {
                return "Prayed \(relativeTime)"
            }
            return "Recently prayed"

        case .note:
            if unseenCount > 0 {
                return "New church note"
            } else if !relativeTime.isEmpty {
                return "Took notes \(relativeTime)"
            }
            return "Recently active"

        case .verse, .none:
            return relativeTime.isEmpty ? "Active recently" : "Active \(relativeTime)"
        }
    }

    // MARK: - Subtext

    private static func makeSubtext(
        summary: UserActivitySummary,
        relationship: RelationshipActivityState?,
        hasMutual: Bool
    ) -> String? {
        var parts: [String] = []

        // Topic overlap
        if let topics = relationship?.mutualTopics, !topics.isEmpty {
            let tagStr = topics.prefix(2).map { "#\($0)" }.joined(separator: " ")
            parts.append(tagStr)
        }

        // Mutual interaction signal
        if hasMutual {
            parts.append("You've interacted")
        }

        // Active streak
        if summary.activeStreak >= 3 {
            parts.append("\(summary.activeStreak)-day streak")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Badge

    private static func badgeString(_ count: Int) -> String {
        count > 9 ? "9+" : "\(count)"
    }

    // MARK: - Relative Time

    static func relativeTimeString(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        switch seconds {
        case ..<60:
            return "just now"
        case ..<3_600:
            let mins = Int(seconds / 60)
            return "\(mins)m ago"
        case ..<86_400:
            let hrs = Int(seconds / 3_600)
            return "\(hrs)h ago"
        case ..<604_800:
            let days = Int(seconds / 86_400)
            return "\(days)d ago"
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

// MARK: - Convenience on UserActivitySummary

private extension UserActivitySummary {
    var isActive: Bool {
        guard let last = lastActiveAt else { return false }
        return Date().timeIntervalSince(last) < 3 * 86_400
    }
}
