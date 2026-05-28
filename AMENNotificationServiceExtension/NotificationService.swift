//
//  NotificationService.swift
//  AMENNotificationServiceExtension
//
//  Mutates incoming push payloads for safe preview display.
//

// MARK: - Notification Service Ownership
// This service owns: UNNotificationServiceExtension payload mutation before display;
//                    safety-state check (guarded/moderated/restricted) — replaces body with
//                    "Open AMEN to review this update safely."; title hydration from actorName
//                    + type for generic "AMEN" push payloads (message, reply, comment, follow types).
// It does NOT own: Notification creation, Firestore writes, priority scoring, batching, delivery,
//                  re-engagement copy, action-thread events, or spiritual-rhythm gating.
//                  This runs in the AMENNotificationServiceExtension process target, not the main app.
// Canonical routing reference: See NotificationServiceMap.md

import UserNotifications

final class AMENNotificationServiceExtensionHandler: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        let userInfo = bestAttemptContent.userInfo
        let safetyState = (userInfo["safetyState"] as? String) ?? "clear"

        if safetyState == "guarded" || safetyState == "moderated" || safetyState == "restricted" {
            bestAttemptContent.body = "Open AMEN to review this update safely."
        }

        if let actorName = userInfo["actorName"] as? String,
           let type = userInfo["type"] as? String,
           bestAttemptContent.title == "AMEN" {
            bestAttemptContent.title = title(for: type, actorName: actorName)
        }

        contentHandler(bestAttemptContent)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private func title(for type: String, actorName: String) -> String {
        switch type {
        case "new_message", "message", "message_request":
            return "\(actorName) sent you a message"
        case "reply_to_comment", "reply":
            return "\(actorName) replied to you"
        case "comment_on_post", "comment":
            return "\(actorName) commented on your post"
        case "follow", "follow_request_approved":
            return "\(actorName) interacted with you"
        default:
            return "AMEN"
        }
    }
}
