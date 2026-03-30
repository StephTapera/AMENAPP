//
//  ReEngagementNotificationService.swift
//  AMENAPP
//
//  Generates personalized, faith-based push notifications to re-engage
//  users who have been away from the app. Uses Claude API via Cloud
//  Functions to produce Spirit-led notification copy.
//

import Foundation
import FirebaseAuth
import UserNotifications

@MainActor
class ReEngagementNotificationService {
    static let shared = ReEngagementNotificationService()
    private init() {}

    /// System prompt for the AI notification writer.
    private let systemPrompt = """
    You are a push notification writer for Berean, a faith-based Bible study and spiritual growth app.

    When called, generate a short, compelling push notification to re-engage a user who has left the app. The notification should:

    - Start with a bold hook line (max 6 words) that feels personal and Spirit-led
    - Follow with 1–2 sentences of body text that create curiosity, warmth, or urgency around their faith journey
    - Feel like a gentle nudge from the Holy Spirit — never pushy or salesy
    - Reference Scripture themes, prayer, reflection, or their last activity when context is provided
    - Match the tone of a trusted spiritual companion, not a marketing bot

    Output ONLY a JSON object in this format:
    {
      "title": "Short bold hook line",
      "body": "1–2 sentence notification body text"
    }

    No preamble, no explanation, no markdown — JSON only.
    """

    // MARK: - Public API

    /// Generate and schedule a re-engagement notification based on user context.
    func scheduleReEngagementNotification(
        userName: String? = nil,
        lastActivity: String? = nil,
        timeAway: String? = nil,
        verseOfTheDay: String? = nil,
        delaySeconds: TimeInterval = 0
    ) async {
        // Build context JSON
        var context: [String: String] = [:]
        if let userName { context["user_name"] = userName }
        if let lastActivity { context["last_activity"] = lastActivity }
        if let timeAway { context["time_away"] = timeAway }
        if let verseOfTheDay { context["verse_of_the_day"] = verseOfTheDay }

        guard let contextJSON = try? JSONSerialization.data(withJSONObject: context),
              let contextString = String(data: contextJSON, encoding: .utf8) else {
            return
        }

        do {
            // Call Cloud Function (bereanNotificationText) to generate copy
            let result = try await CloudFunctionsService.shared.call(
                "bereanNotificationText",
                data: [
                    "systemPrompt": systemPrompt,
                    "userMessage": contextString,
                    "purpose": "re_engagement",
                ] as [String: Any]
            )

            // Parse response
            guard let dict = result as? [String: Any],
                  let text = dict["text"] as? String,
                  let jsonData = text.data(using: .utf8),
                  let notification = try? JSONDecoder().decode(NotificationCopy.self, from: jsonData) else {
                dlog("Failed to parse re-engagement notification response")
                return
            }

            // Schedule the local notification
            await scheduleLocalNotification(
                title: notification.title,
                body: notification.body,
                delaySeconds: delaySeconds
            )

        } catch {
            dlog("Re-engagement notification generation failed: \(error.localizedDescription)")
        }
    }

    /// Schedule when the user backgrounds the app (called from AppDelegate/scenePhase).
    func onAppBackgrounded() {
        let userName = UserService.shared.currentUser?.displayName
        let lastVerse = DailyVerseGenkitService.shared.todayVerse?.reference

        Task {
            // Schedule for 2 hours from now
            await scheduleReEngagementNotification(
                userName: userName,
                lastActivity: nil, // App usage tracking doesn't expose last screen
                timeAway: "2 hours",
                verseOfTheDay: lastVerse,
                delaySeconds: 2 * 3600
            )
        }
    }

    // MARK: - Private

    private func scheduleLocalNotification(title: String, body: String, delaySeconds: TimeInterval) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "re_engagement"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, delaySeconds),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "reengagement_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            dlog("Re-engagement notification scheduled: \"\(title)\" in \(Int(delaySeconds))s")
        } catch {
            dlog("Failed to schedule re-engagement notification: \(error)")
        }
    }

    private struct NotificationCopy: Codable {
        let title: String
        let body: String
    }
}
