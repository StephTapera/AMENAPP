import Foundation
import FirebaseFirestore
import FirebaseAuth
import UserNotifications
import Combine

/// Centralised notification sender.
///
/// KEY GUARANTEES
/// 1. Deterministic Firestore document IDs → repeated events overwrite, never duplicate.
/// 2. Like events use a rollup doc (like_rollup_{postId}) so 10 likes = 1 notification item.
/// 3. Push is sent ONLY from the `pendingNotifications` collection (picked up by Cloud Function).
///    The client never calls FCM directly.
/// 4. In-app write and pendingNotifications write are done in a single Firestore batch so
///    they are atomic – no orphaned push without in-app record or vice-versa.
/// 5. Quiet-hours and per-type toggles are checked before any write.
@MainActor
class ActionableNotificationService: ObservableObject {
    static let shared = ActionableNotificationService()

    private let db = Firestore.firestore()
    private let router = SmartNotificationRouter.shared

    // MARK: - Public Send API

    /// Primary entry-point for sending a notification.
    /// Pass a deterministic `notificationId` for idempotency; if nil a UUID is used (use for
    /// truly unique events like each individual DM message).
    func sendNotification(
        notificationId: String? = nil,
        category: NotificationCategory,
        fromUserId: String,
        fromUsername: String,
        toUserId: String,
        title: String,
        body: String,
        entityId: String?,
        deepLink: String,
        metadata: [String: String] = [:]
    ) async throws {
        // Never notify self
        guard fromUserId != toUserId else { return }

        // Route through priority system
        let routing = try await router.route(
            category: category,
            fromUserId: fromUserId,
            toUserId: toUserId,
            content: body,
            entityId: entityId
        )

        guard routing.channel != .suppress else { return }

        // Quiet-hours enforcement
        let prefs = await loadPreferences(userId: toUserId)
        if isInQuietHours(prefs: prefs) && category != .crisisAlerts { return }

        // Per-category toggle
        let catSetting = prefs.categorySettings[category] ?? category.defaultSetting
        guard catSetting.mode != .off else { return }

        let privacyLevel = await getUserPrivacyLevel(prefs: prefs)
        let actions = generateActions(for: category, entityId: entityId)

        // Stable notification doc ID (deterministic → idempotent)
        let docId = notificationId ?? UUID().uuidString

        let payload = ActionableNotificationPayload(
            id: docId,
            category: category,
            title: title,
            body: body,
            privacyLevel: privacyLevel,
            deepLink: deepLink,
            actions: actions,
            collapseKey: routing.collapseKey,
            metadata: metadata,
            expiresAt: Date().addingTimeInterval(routing.ttl)
        )

        let (safeTitle, safeBody) = payload.displayText(for: privacyLevel, senderName: fromUsername)

        switch routing.channel {
        case .push:
            try await sendPushAndSaveInApp(
                payload: payload,
                safeTitle: safeTitle,
                safeBody: safeBody,
                toUserId: toUserId,
                routing: routing,
                catSetting: catSetting
            )
        case .inApp:
            try await saveInAppNotification(payload: payload, toUserId: toUserId)
        case .digest:
            try await addToDigest(payload: payload, toUserId: toUserId, routing: routing)
        case .silent:
            // Badge-only: let BadgeCountManager pick it up from listener
            break
        case .suppress:
            break
        }
    }

    // MARK: - Like Rollup

    /// Special handler for likes – maintains a single rollup doc per post so N likes
    /// produce exactly 1 notification item that is updated in-place.
    func sendLikeRollup(
        postId: String,
        postOwnerId: String,
        actorUid: String,
        actorUsername: String,
        postSnippet: String
    ) async throws {
        guard actorUid != postOwnerId else { return }

        let prefs = await loadPreferences(userId: postOwnerId)
        if isInQuietHours(prefs: prefs) { return }
        let catSetting = prefs.categorySettings[.reactions] ?? NotificationCategory.reactions.defaultSetting
        guard catSetting.mode != .off else { return }

        let rollupId = NotificationId.likeRollup(postId: postId)
        let rollupRef = db.collection("users").document(postOwnerId)
            .collection("notifications").document(rollupId)

        // Use a transaction so concurrent likes don't race
        _ = try await db.runTransaction { transaction, errorPointer in
            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(rollupRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            let now = Timestamp(date: Date())
            if snap.exists {
                var actorUids = snap.data()?["actorUids"] as? [String] ?? []
                // Keep list bounded (most-recent actors, max 10)
                if !actorUids.contains(actorUid) {
                    actorUids.insert(actorUid, at: 0)
                    if actorUids.count > 10 { actorUids = Array(actorUids.prefix(10)) }
                }
                let count = (snap.data()?["count"] as? Int ?? 0) + (actorUids.first == actorUid ? 0 : 1)
                transaction.updateData([
                    "actorUids": actorUids,
                    "actorUid": actorUid,
                    "count": max(count, actorUids.count),
                    "updatedAt": now,
                    "read": false,
                    "title": self.likeTitle(count: max(count, actorUids.count), username: actorUsername),
                    "body": postSnippet
                ], forDocument: rollupRef)
            } else {
                transaction.setData([
                    "id": rollupId,
                    "type": "like",
                    "category": NotificationCategory.reactions.rawValue,
                    "postId": postId,
                    "actorUid": actorUid,
                    "actorUids": [actorUid],
                    "count": 1,
                    "title": "\(actorUsername) liked your post",
                    "body": postSnippet,
                    "deepLink": "post/\(postId)",
                    "read": false,
                    "rollupKey": NotificationId.likeRollupKey(postId: postId),
                    "createdAt": now,
                    "updatedAt": now
                ], forDocument: rollupRef)
            }
            return nil
        }
    }

    // MARK: - Generate Actions

    private func generateActions(for category: NotificationCategory, entityId: String?) -> [NotificationAction] {
        switch category {
        case .directMessages:
            return [
                NotificationAction(id: "reply", title: "Reply", type: .reply, destructive: false, requiresAuth: true, icon: "arrowshape.turn.up.left"),
                NotificationAction(id: "mute", title: "Mute", type: .mute, destructive: false, requiresAuth: true, icon: "bell.slash"),
                NotificationAction(id: "request", title: "Move to Requests", type: .markAsRequest, destructive: false, requiresAuth: true, icon: "tray.and.arrow.down")
            ]
        case .groupMessages:
            return [
                NotificationAction(id: "reply", title: "Reply", type: .reply, destructive: false, requiresAuth: true, icon: "arrowshape.turn.up.left"),
                NotificationAction(id: "mute", title: "Mute Thread", type: .muteThread, destructive: false, requiresAuth: true, icon: "bell.slash")
            ]
        case .follows:
            return [
                NotificationAction(id: "accept", title: "Accept", type: .acceptFollow, destructive: false, requiresAuth: true, icon: "checkmark"),
                NotificationAction(id: "decline", title: "Decline", type: .declineFollow, destructive: true, requiresAuth: true, icon: "xmark")
            ]
        case .prayerUpdates:
            return [
                NotificationAction(id: "prayed", title: "Prayed", type: .markPrayed, destructive: false, requiresAuth: true, icon: "hands.sparkles"),
                NotificationAction(id: "encourage", title: "Send Encouragement", type: .sendEncouragement, destructive: false, requiresAuth: true, icon: "heart")
            ]
        case .replies:
            return [
                NotificationAction(id: "reply", title: "Reply", type: .replyToComment, destructive: false, requiresAuth: true, icon: "arrowshape.turn.up.left"),
                NotificationAction(id: "restrict", title: "Restrict User", type: .restrictUser, destructive: true, requiresAuth: true, icon: "hand.raised")
            ]
        case .mentions, .reactions, .reposts, .churchNotes, .crisisAlerts:
            return []
        }
    }

    // MARK: - Push + In-App (atomic batch)

    private func sendPushAndSaveInApp(
        payload: ActionableNotificationPayload,
        safeTitle: String,
        safeBody: String,
        toUserId: String,
        routing: SmartNotificationRouting,
        catSetting: SmartNotificationPreferences.CategorySetting
    ) async throws {
        let batch = db.batch()

        // 1. In-app notification doc (deterministic ID → setData overwrites on retry)
        let inAppRef = db.collection("users").document(toUserId)
            .collection("notifications").document(payload.id)
        batch.setData(buildInAppData(payload: payload), forDocument: inAppRef)

        // 2. Pending push entry for Cloud Function to pick up (fan-out to all device tokens)
        //    Using payload.id as the pendingNotifications doc ID ensures idempotency here too.
        if catSetting.pushEnabled {
            let pendingRef = db.collection("pendingNotifications").document(payload.id)
            batch.setData([
                "recipientUid": toUserId,
                "title": safeTitle,
                "body": safeBody,
                "category": payload.category.rawValue,
                "deepLink": payload.deepLink,
                "collapseKey": payload.collapseKey ?? "",
                "priority": routing.priority.level == .critical ? "high" : "normal",
                "sound": catSetting.soundEnabled ? "default" : "",
                "notificationId": payload.id,
                "metadata": payload.metadata,
                "createdAt": FieldValue.serverTimestamp(),
                "status": "pending"
            ], forDocument: pendingRef)
        }

        try await batch.commit()
    }

    // MARK: - In-App Only

    private func saveInAppNotification(payload: ActionableNotificationPayload, toUserId: String) async throws {
        try await db.collection("users").document(toUserId)
            .collection("notifications").document(payload.id)
            .setData(buildInAppData(payload: payload))
    }

    private func buildInAppData(payload: ActionableNotificationPayload) -> [String: Any] {
        [
            "id": payload.id,
            "category": payload.category.rawValue,
            "title": payload.title,
            "body": payload.body,
            "deepLink": payload.deepLink,
            "actions": payload.actions.map { action -> [String: Any] in
                [
                    "id": action.id,
                    "title": action.title,
                    "type": action.type.rawValue,
                    "destructive": action.destructive,
                    "requiresAuth": action.requiresAuth,
                    "icon": action.icon ?? ""
                ]
            },
            "metadata": payload.metadata,
            "createdAt": FieldValue.serverTimestamp(),
            "read": false,
            "expiresAt": payload.expiresAt.map { Timestamp(date: $0) } ?? NSNull()
        ]
    }

    // MARK: - Digest Management

    private func addToDigest(
        payload: ActionableNotificationPayload,
        toUserId: String,
        routing: SmartNotificationRouting
    ) async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let digestId = "\(toUserId)_\(Int(today.timeIntervalSince1970))"
        let digestRef = db.collection("notificationDigests").document(digestId)

        let itemData: [String: Any] = [
            "notificationId": payload.id,
            "category": payload.category.rawValue,
            "title": payload.title,
            "body": payload.body,
            "deepLink": payload.deepLink,
            "timestamp": FieldValue.serverTimestamp()
        ]

        let batch = db.batch()

        // Upsert digest doc (merge so it's safe to call repeatedly)
        batch.setData([
            "id": digestId,
            "userId": toUserId,
            "createdAt": FieldValue.serverTimestamp(),
            "deliverAt": Timestamp(date: routing.deliverAt),
            "delivered": false,
            "opened": false
        ], forDocument: digestRef, merge: true)

        // ArrayUnion is idempotent for identical items
        batch.updateData([
            "items": FieldValue.arrayUnion([itemData]),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: digestRef)

        // Also save individual in-app record (idempotent setData)
        let inAppRef = db.collection("users").document(toUserId)
            .collection("notifications").document(payload.id)
        batch.setData(buildInAppData(payload: payload), forDocument: inAppRef)

        try await batch.commit()
    }

    // MARK: - Preferences Helpers

    private func loadPreferences(userId: String) async -> SmartNotificationPreferences {
        let doc = try? await db.collection("users").document(userId)
            .collection("settings").document("notifications").getDocument()
        guard let data = doc?.data(),
              let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let prefs = try? JSONDecoder().decode(SmartNotificationPreferences.self, from: jsonData) else {
            return SmartNotificationPreferences()
        }
        return prefs
    }

    private func getUserPrivacyLevel(prefs: SmartNotificationPreferences) async -> SmartNotificationPreferences.LockScreenPrivacy {
        prefs.lockScreenPrivacy
    }

    /// Returns true if current time falls inside the user's configured quiet window.
    private func isInQuietHours(prefs: SmartNotificationPreferences) -> Bool {
        guard let qh = prefs.quietHours, qh.enabled else { return false }

        // Sunday mode
        if prefs.sundayMode {
            let weekday = Calendar.current.component(.weekday, from: Date())
            if weekday == 1 { return true } // Sunday
        }

        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        let startParts = qh.startTime.split(separator: ":").compactMap { Int($0) }
        let endParts   = qh.endTime.split(separator: ":").compactMap { Int($0) }
        guard startParts.count == 2, endParts.count == 2 else { return false }

        let startMinutes = startParts[0] * 60 + startParts[1]
        let endMinutes   = endParts[0]   * 60 + endParts[1]

        if startMinutes <= endMinutes {
            // Same-day window e.g. 09:00–17:00
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            // Overnight window e.g. 22:00–08:00
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }

    private func likeTitle(count: Int, username: String) -> String {
        count == 1 ? "\(username) liked your post" : "\(username) and \(count - 1) other\(count - 1 == 1 ? "" : "s") liked your post"
    }

    // MARK: - Handle Action (called from notification tap)

    func handleAction(actionType: NotificationAction.ActionType, notificationId: String, entityId: String?) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        switch actionType {
        case .reply, .sendEncouragement, .replyToComment:
            // Open composer (handled by UI)
            break
        case .mute:
            if let conversationId = entityId {
                try await muteConversation(conversationId: conversationId, userId: currentUserId)
            }
        case .markAsRequest:
            if let conversationId = entityId {
                try await db.collection("conversations").document(conversationId).updateData(["isRequest_\(currentUserId)": true])
            }
        case .block:
            if let blockUserId = entityId {
                try await db.collection("users").document(currentUserId)
                    .collection("blocked").document(blockUserId)
                    .setData(["blockedAt": FieldValue.serverTimestamp()])
            }
        case .acceptFollow:
            if let followerId = entityId {
                try await acceptFollowRequest(followerId: followerId, userId: currentUserId)
            }
        case .declineFollow:
            if let followerId = entityId {
                try await db.collection("users").document(currentUserId)
                    .collection("followRequests").document(followerId).delete()
            }
        case .markPrayed:
            if let prayerId = entityId {
                try await db.collection("prayers").document(prayerId).updateData([
                    "prayedBy": FieldValue.arrayUnion([currentUserId]),
                    "prayerCount": FieldValue.increment(Int64(1))
                ])
            }
        case .restrictUser:
            if let userId = entityId {
                try await db.collection("users").document(currentUserId)
                    .collection("restricted").document(userId)
                    .setData(["restrictedAt": FieldValue.serverTimestamp()])
            }
        case .hideComment:
            if let commentId = entityId {
                try await db.collection("users").document(currentUserId)
                    .collection("hiddenComments").document(commentId)
                    .setData(["hiddenAt": FieldValue.serverTimestamp()])
            }
        case .muteThread:
            if let threadId = entityId {
                let muteUntil = Date().addingTimeInterval(28800)
                try await db.collection("users").document(currentUserId)
                    .collection("mutedThreads").document(threadId)
                    .setData(["mutedAt": FieldValue.serverTimestamp(), "mutedUntil": Timestamp(date: muteUntil)])
            }
        case .unmuteThread:
            if let threadId = entityId {
                try await db.collection("users").document(currentUserId)
                    .collection("mutedThreads").document(threadId).delete()
            }
        }

        // Mark notification as read
        try await db.collection("users").document(currentUserId)
            .collection("notifications").document(notificationId)
            .updateData(["read": true, "readAt": FieldValue.serverTimestamp()])
    }

    // MARK: - Private helpers

    private func muteConversation(conversationId: String, userId: String) async throws {
        try await db.collection("users").document(userId)
            .collection("mutedConversations").document(conversationId)
            .setData(["mutedAt": FieldValue.serverTimestamp(), "mutedUntil": NSNull()])
    }

    private func acceptFollowRequest(followerId: String, userId: String) async throws {
        let batch = db.batch()
        let followerRef = db.collection("users").document(userId).collection("followers").document(followerId)
        let followingRef = db.collection("users").document(followerId).collection("following").document(userId)
        batch.setData(["followedAt": FieldValue.serverTimestamp()], forDocument: followerRef)
        batch.setData(["followedAt": FieldValue.serverTimestamp()], forDocument: followingRef)
        try await batch.commit()
    }
}
