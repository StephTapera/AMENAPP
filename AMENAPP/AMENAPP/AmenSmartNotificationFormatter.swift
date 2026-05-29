//
//  AmenSmartNotificationFormatter.swift
//  AMENAPP
//
//  Smart notification title/content formatter for the AMEN faith app.
//  Converts raw APNs payloads into human-friendly, faith-native summaries.
//
//  All methods are static — this struct has no stored state.
//

import Foundation
import UserNotifications

// MARK: - AmenSmartNotificationFormatter

struct AmenSmartNotificationFormatter {

    // MARK: - Title Generation

    /// Produce a human-readable summary title from one or more notification payloads.
    ///
    /// - Parameter notifications: Array of raw notification `userInfo` dictionaries
    ///   (the same payloads passed to `UNUserNotificationCenterDelegate`).
    /// - Returns: A non-empty, faith-aligned title string.
    static func formatTitle(for notifications: [[AnyHashable: Any]]) -> String {
        guard !notifications.isEmpty else { return "You have a new update" }

        let first = notifications[0]
        let type  = first["type"] as? String ?? ""
        let count = notifications.count

        switch type {

        case "prayer":
            if count > 1 {
                return "\(count) friends are praying with you right now"
            } else {
                // Use the notification body as the prayer title when available
                let title = first["prayerTitle"] as? String
                    ?? (first["body"] as? String)
                    ?? (first["aps"] as? [AnyHashable: Any]).flatMap { $0["body"] as? String }
                    ?? "Someone is praying with you"
                return title
            }

        case "comment":
            return count > 1
                ? "\(count) new comments on your reflection"
                : "New discussion on your reflection"

        case "follow":
            return count > 1
                ? "\(count) people from your community want to connect"
                : "Someone from your community wants to connect"

        case "berean":
            return "Berean found a verse for your question"

        case "church_event":
            let churchName = (first["churchName"] as? String) ?? "Your church"
            if let startTimestamp = first["startTime"] as? TimeInterval {
                let startDate = Date(timeIntervalSince1970: startTimestamp)
                let minutes   = Int(startDate.timeIntervalSinceNow / 60)
                if minutes > 0 {
                    return "\(churchName) service starts in \(minutes) min"
                }
            }
            let eventTitle = (first["eventTitle"] as? String) ?? "service"
            return "\(churchName) \(eventTitle) is starting soon"

        case "testimony":
            return count > 1
                ? "\(count) testimonies shared in your community"
                : "Your community celebrated a testimony"

        case "amen_reaction":
            let reactionCount = (first["reactionCount"] as? Int) ?? count
            return "\(reactionCount) Amens on your post"

        case "group_message":
            let topic = (first["topic"] as? String) ?? "something meaningful"
            return "Your group discussed \(topic) tonight"

        default:
            return count == 1
                ? "You have a new update"
                : "\(count) new updates"
        }
    }

    // MARK: - Summarization Decision

    /// Returns `true` when it is appropriate to summarize multiple notifications
    /// into a single grouped alert rather than showing them individually.
    ///
    /// Summarizes when: more than 3 notifications exist AND they are all the same type.
    ///
    /// - Parameter notifications: Array of raw notification `userInfo` dictionaries.
    static func shouldSummarize(_ notifications: [[AnyHashable: Any]]) -> Bool {
        guard notifications.count > 3 else { return false }
        let types = notifications.compactMap { $0["type"] as? String }
        // Only summarize if we can read the type from every payload and they all match
        guard types.count == notifications.count, let firstType = types.first else { return false }
        return types.allSatisfy { $0 == firstType }
    }

    // MARK: - Content Enrichment

    /// Enrich a `UNMutableNotificationContent` with a smart title and appropriate category.
    ///
    /// This method is typically called from
    /// `UNNotificationServiceExtension.didReceive(_:withContentHandler:)` or from
    /// a custom UNUserNotificationCenterDelegate before the content is displayed.
    ///
    /// - Parameters:
    ///   - content:  The mutable content object to enrich (a copy is returned).
    ///   - userInfo: The raw notification payload dictionary.
    /// - Returns: A new `UNMutableNotificationContent` with title/category applied.
    static func enrichContent(
        _ content: UNMutableNotificationContent,
        with userInfo: [AnyHashable: Any]
    ) -> UNMutableNotificationContent {
        // Work on a mutable copy so the caller's original is untouched
        let enriched = content.mutableCopy() as! UNMutableNotificationContent // swiftlint:disable:this force_cast

        // Apply smart title
        enriched.title = formatTitle(for: [userInfo])

        // Apply category identifier so the system can show actionable buttons
        let type = userInfo["type"] as? String ?? ""
        enriched.categoryIdentifier = categoryIdentifier(for: type)

        return enriched
    }

    // MARK: - Private Helpers

    /// Maps a notification `type` string to a registered `UNNotificationCategory` identifier.
    ///
    /// Categories and their actions should be registered in `AppDelegate` during launch.
    /// Unrecognised types fall back to the generic "AMEN_DEFAULT" category.
    private static func categoryIdentifier(for type: String) -> String {
        switch type {
        case "prayer":        return "AMEN_PRAYER"
        case "comment":       return "AMEN_COMMENT"
        case "follow":        return "AMEN_FOLLOW"
        case "berean":        return "AMEN_BEREAN"
        case "church_event":  return "AMEN_CHURCH_EVENT"
        case "testimony":     return "AMEN_TESTIMONY"
        case "amen_reaction": return "AMEN_REACTION"
        case "group_message": return "AMEN_GROUP_MESSAGE"
        default:              return "AMEN_DEFAULT"
        }
    }
}
