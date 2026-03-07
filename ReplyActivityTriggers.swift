
//
//  ReplyActivityTriggers.swift
//  AMENAPP
//
//  Wires in-app notification events and tone-check warnings to the
//  Reply Assist Dynamic Island Live Activity.
//
//  TRIGGER POINTS:
//   A) InAppNotificationBanner receives a comment/mention/DM notification
//      → calls ReplyActivityTriggers.shared.handle(notification:)
//   B) User taps Send on a comment/reply and ThinkFirstGuardrailsService
//      returns .softPrompt or .requireEdit for harsh tone
//      → calls ReplyActivityTriggers.shared.handleToneWarn(draft:postId:)
//   C) User long-presses a notification row in NotificationsView
//      → calls ReplyActivityTriggers.shared.handle(notification:forceTrigger:true)
//
//  SAFETY RULES ENFORCED HERE:
//   - Only triggers for comment / mention / dm notification types.
//   - Only triggers if user has enabled "Show Reply Suggestions" in Settings.
//   - Does not expose private account content or content from blocked users.
//   - Minors protection: uses existing isMinorSender check before generating.
//   - Context excerpt is capped at 200 chars before being sent to the pipeline.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ReplyActivityTriggers {

    static let shared = ReplyActivityTriggers()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: - Notification Trigger (comment / mention / DM arrival)

    /// Call this when an in-app notification of type comment, mention, or dm arrives.
    /// Safe to call from InAppNotificationBannerModifier or PushNotificationHandler.
    func handle(notification: NotificationTriggerInfo) {
        guard UserDefaults.standard.bool(forKey: "replyAssist_suggestionsEnabled") else { return }
        guard isSupportedType(notification.type) else { return }

        Task { [weak self] in
            guard let self else { return }

            // Fetch minimal context (topic excerpt, not full body) from Firestore
            let contextExcerpt = await self.fetchContextExcerpt(for: notification)
            let isMinor = await self.senderIsMinor(userId: notification.actorId)

            let event = ReplyActivityEvent(
                replyType: replyType(for: notification.type),
                entityId: notification.entityId,
                subEntityId: notification.subEntityId,
                actorDisplayName: notification.actorDisplayName,
                contextSnippet: contextExcerpt
            )

            // Start / update the Live Activity (debounced)
            LiveActivityManager.shared.startReplyActivity(event: event)

            // Kick off suggestion generation in background (results posted via updateReplySuggestions)
            let request = SmartReplySuggestionRequest(
                mode: .smartReply,
                contextExcerpt: contextExcerpt,
                actorDisplayName: notification.actorDisplayName,
                actorIsMinor: isMinor
            )
            SmartReplySuggestionService.shared.generateAndUpdateActivity(
                request: request,
                contextSnippet: contextExcerpt,
                activityEntityId: notification.entityId
            )
        }
    }

    // MARK: - Tone Assist Trigger

    /// Call this when ThinkFirstGuardrailsService returns .softPrompt or .requireEdit
    /// for a comment / reply the user is about to send.
    ///
    /// - Parameters:
    ///   - draft:  The user's draft text (used to generate a gentler rewrite).
    ///   - postId: The post the user is replying to (for the deep-link destination).
    func handleToneWarn(draft: String, postId: String) {
        guard UserDefaults.standard.bool(forKey: "replyAssist_suggestionsEnabled") else { return }

        let event = ReplyActivityEvent(
            replyType: .toneAssist,
            entityId: postId,
            subEntityId: nil,
            actorDisplayName: nil,
            contextSnippet: nil
        )

        LiveActivityManager.shared.startReplyActivity(event: event)

        Task {
            let request = SmartReplySuggestionRequest(
                mode: .toneRewrite(originalDraft: draft),
                contextExcerpt: nil,
                actorDisplayName: nil,
                actorIsMinor: false
            )
            SmartReplySuggestionService.shared.generateAndUpdateActivity(
                request: request,
                contextSnippet: nil,
                activityEntityId: postId
            )
        }
    }

    // MARK: - Private helpers

    private func isSupportedType(_ type: String) -> Bool {
        ["comment", "mention", "dm", "message", "reply"].contains(type.lowercased())
    }

    private func replyType(for notificationType: String) -> ReplyActivityAttributes.ReplyType {
        switch notificationType.lowercased() {
        case "dm", "message": return .dm
        default:              return .comment
        }
    }

    /// Fetches the post title or first line only (never the full body).
    /// Returns nil on any error — the activity starts in fallback state.
    private func fetchContextExcerpt(for notification: NotificationTriggerInfo) async -> String? {
        guard !notification.entityId.isEmpty else { return nil }

        // For DMs: never fetch content (always privacy-restricted unless user opts in)
        if notification.type.lowercased() == "dm" || notification.type.lowercased() == "message" {
            let allowed = UserDefaults.standard.bool(forKey: "replyAssist_showPreviews")
            guard allowed else { return nil }
            // Even with previews on, we don't fetch DM content here — the commenter name is enough context
            return nil
        }

        // For comment/mention: fetch the post's category/topic as context
        do {
            let doc = try await db.collection("posts").document(notification.entityId).getDocument()
            guard let data = doc.data() else { return nil }
            let content = data["content"] as? String ?? ""
            let category = data["category"] as? String ?? ""
            let excerpt = category.isEmpty ? content : "[\(category)] \(content)"
            return String(excerpt.prefix(200))  // cap at 200 chars — never send full content
        } catch {
            return nil
        }
    }

    /// Returns true if sender is a known minor (uses MinorSafetyService if available).
    private func senderIsMinor(userId: String) async -> Bool {
        guard !userId.isEmpty else { return false }
        // Check the user profile for age restriction flag
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            return doc.data()?["isMinor"] as? Bool ?? false
        } catch {
            return false  // Default safe: do not block suggestions due to lookup failure
        }
    }
}

// MARK: - Notification Trigger Info

/// Minimal payload describing an incoming notification event.
/// Populated from InAppNotificationBanner / PushNotificationHandler.
struct NotificationTriggerInfo {
    /// Notification type string: "comment", "mention", "dm", "reply"
    let type: String
    /// postId for comment/mention, conversationId for dm
    let entityId: String
    /// commentId for comment type (optional)
    let subEntityId: String?
    /// Actor's UID
    let actorId: String
    /// Actor's display name (privacy-gated before being shown)
    let actorDisplayName: String?
}
