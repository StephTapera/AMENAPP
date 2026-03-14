//
//  PushNotificationHandler.swift
//  AMENAPP
//
//  Handles incoming push notifications and deep linking.
//
//  TOKEN STRATEGY
//  - Each device token is stored at users/{uid}/deviceTokens/{sanitisedToken}
//    with platform, updatedAt, enabled, locale, timezone fields.
//  - On refresh the old entry is removed and the new one upserted.
//  - On sign-out the current token is marked disabled (not deleted, so
//    Cloud Functions can clean invalid tokens gracefully).
//  - On APNs/FCM error the backend should call markTokenInvalid().
//

import Foundation
import UIKit
import UserNotifications
import FirebaseMessaging
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class PushNotificationHandler: NSObject, ObservableObject {
    static let shared = PushNotificationHandler()

    @Published var pendingDeepLink: NotificationDeepLink?

    /// Clear the pending deep link. Call this after navigation has completed to
    /// prevent repeated navigation on view re-renders.
    func clearPendingDeepLink() {
        pendingDeepLink = nil
    }

    // Track the last saved token so we skip no-op updates
    private var lastSavedToken: String?

    private override init() {
        super.init()
    }

    // MARK: - Foreground Handling

    func handleForegroundNotification(_ notification: UNNotification) {
        let userInfo = notification.request.content.userInfo
        print("📬 Received foreground notification")
        print("   Title:", notification.request.content.title)
        print("   Body:", notification.request.content.body)
        print("   UserInfo:", userInfo)

        // Update badge from notification payload
        if let badge = notification.request.content.badge?.intValue {
            UNUserNotificationCenter.current().setBadgeCount(badge) { _ in }
        }

        // Refresh notification listener (guarded internally)
        NotificationService.shared.startListening()
    }

    // MARK: - Notification Tap

    func handleNotificationTap(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        print("👆 User tapped notification")

        guard let type = userInfo["type"] as? String else {
            print("⚠️ No notification type found")
            return
        }

        // Resolve the intended deep link
        var intendedLink: NotificationDeepLink?
        switch type {
        case "follow", "follow_request_accepted":
            if let actorId = userInfo["actorId"] as? String {
                intendedLink = .profile(userId: actorId)
            }
        case "amen", "comment", "reply", "mention", "tag", "repost":
            if let postId = userInfo["postId"] as? String {
                intendedLink = .post(postId: postId)
            }
        case "message_request_accepted", "dm", "message":
            if let actorId = userInfo["actorId"] as? String {
                intendedLink = .conversation(userId: actorId)
            }
        default:
            print("⚠️ Unknown notification type:", type)
        }

        // ── Shabbat gate ──────────────────────────────────────────────────
        // On Sunday with Shabbat active, redirect blocked notifications to
        // the Resources tab instead of opening the blocked content.
        if let link = intendedLink {
            let feature = link.requiredFeature
            if case .blocked = AppAccessController.shared.canAccess(feature) {
                ShabbatModeService.shared.logBlocked(feature: feature, route: "push_notification/\(type)")
                print("🚫 PushNotificationHandler: notification tap blocked by Shabbat Mode (type=\(type))")
                // Navigate to Resources tab — gate view will be shown
                NotificationCenter.default.post(name: .shabbatDeepLinkBlocked, object: nil,
                                                userInfo: ["blockedRoute": "notification/\(type)"])
                // Still mark as read
                if let notificationId = userInfo["notificationId"] as? String {
                    Task { try? await NotificationService.shared.markAsRead(notificationId) }
                }
                return
            }
        }
        // ─────────────────────────────────────────────────────────────────

        pendingDeepLink = intendedLink

        // P0 FIX: Route to the correct tab via NotificationDeepLinkRouter.
        // pendingDeepLink was set above but ContentView never observed it.
        // Calling routeFromPushPayload publishes activeDestination which
        // NotificationNavigationHandler (applied in ContentView) observes.
        NotificationDeepLinkRouter.shared.routeFromPushPayload(userInfo)

        // Mark notification as read if we have the ID
        if let notificationId = userInfo["notificationId"] as? String {
            Task {
                try? await NotificationService.shared.markAsRead(notificationId)
            }
        }
    }

    // MARK: - Token Management

    /// Upsert the FCM token into `users/{uid}/deviceTokens/{sanitisedToken}`.
    /// Using a subcollection means one user can have tokens on multiple devices
    /// and the Cloud Function fan-outs to all enabled tokens automatically.
    func saveFCMToken(_ token: String, for userId: String) async throws {
        guard token != lastSavedToken else { return } // Skip no-ops
        lastSavedToken = token

        let db = FirebaseManager.shared.firestore
        let sanitised = sanitiseTokenKey(token)

        // Keep the legacy top-level field for any existing server code that reads it
        try await db.collection("users").document(userId).updateData([
            "fcmToken": token,
            "fcmTokenUpdatedAt": FieldValue.serverTimestamp()
        ])

        // Write to per-device subcollection (supports multi-device)
        try await db.collection("users").document(userId)
            .collection("deviceTokens").document(sanitised)
            .setData([
                "token": token,
                "platform": "ios",
                "enabled": true,
                "updatedAt": FieldValue.serverTimestamp(),
                "locale": Locale.current.identifier,
                "timezone": TimeZone.current.identifier
            ])

        print("✅ FCM token saved (deviceTokens subcollection)")
    }

    /// Mark the current token disabled on sign-out (does not delete so CF can clean up).
    func disableFCMToken(for userId: String) async {
        guard let token = lastSavedToken ?? Messaging.messaging().fcmToken else { return }
        let db = FirebaseManager.shared.firestore
        let sanitised = sanitiseTokenKey(token)
        do {
            // Remove legacy field
            try await db.collection("users").document(userId).updateData([
                "fcmToken": FieldValue.delete()
            ])
            // Mark subcollection entry disabled (retains history for CF cleanup)
            try await db.collection("users").document(userId)
                .collection("deviceTokens").document(sanitised)
                .setData(["enabled": false, "disabledAt": FieldValue.serverTimestamp()], merge: true)
            lastSavedToken = nil
            print("✅ FCM token disabled on sign-out")
        } catch {
            print("❌ Failed to disable FCM token:", error)
        }
    }

    /// Legacy helper kept for call-sites that use the old name.
    func removeFCMToken(for userId: String) async {
        await disableFCMToken(for: userId)
    }

    // MARK: - Private Helpers

    /// FCM tokens contain characters invalid as Firestore doc IDs. Replace them.
    private func sanitiseTokenKey(_ token: String) -> String {
        token.replacingOccurrences(of: "/", with: "_")
             .replacingOccurrences(of: ".", with: "_")
    }
}

// MARK: - Deep Link Types

enum NotificationDeepLink: Equatable {
    case profile(userId: String)
    case post(postId: String)
    case conversation(userId: String)
    case notifications

    var navigationPath: String {
        switch self {
        case .profile(let userId): return "profile_\(userId)"
        case .post(let postId):    return "post_\(postId)"
        case .conversation(let userId): return "conversation_\(userId)"
        case .notifications: return "notifications"
        }
    }

    /// Maps to the AppFeature required to open this link — used by the Shabbat gate.
    var requiredFeature: AppFeature {
        switch self {
        case .profile:       return .profileBrowse
        case .post:          return .feed
        case .conversation:  return .messages
        case .notifications: return .notifications
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationHandler: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            handleForegroundNotification(notification)
        }
        completionHandler([.banner, .badge, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            handleNotificationTap(response)
        }
        completionHandler()
    }
}

// MARK: - MessagingDelegate

extension PushNotificationHandler: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("🔄 FCM Token refreshed")
        guard let token = fcmToken else {
            print("⚠️ No FCM token received")
            return
        }
        print("   New token:", token)

        Task { @MainActor in
            guard let userId = FirebaseManager.shared.currentUser?.uid else {
                print("⚠️ No authenticated user to save FCM token")
                return
            }
            try? await saveFCMToken(token, for: userId)
        }
    }
}
