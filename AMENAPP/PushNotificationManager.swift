//
//  PushNotificationManager.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//
//  Handles push notifications via Firebase Cloud Messaging (FCM)
//

import Foundation
import SwiftUI
import Combine
import UserNotifications
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore

class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    
    @Published var deviceToken: String?
    @Published var fcmToken: String?
    @Published var notificationPermissionGranted = false
    
    private let db = Firestore.firestore()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Request Permissions
    
    @MainActor
    func requestNotificationPermissions() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            await MainActor.run {
                notificationPermissionGranted = granted
            }
            
            if granted {
                print("✅ Notification permission granted")
                await registerForRemoteNotifications()
            } else {
                print("❌ Notification permission denied")
            }
            
            return granted
        } catch {
            print("❌ Error requesting notification permission: \(error)")
            return false
        }
    }
    
    @MainActor
    func checkNotificationPermissions() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        let granted = settings.authorizationStatus == .authorized
        
        await MainActor.run {
            notificationPermissionGranted = granted
        }
        
        return granted
    }
    
    // MARK: - Register for Remote Notifications
    
    func registerForRemoteNotifications() async {
        await UIApplication.shared.registerForRemoteNotifications()
        print("📱 Registering for remote notifications...")
    }
    
    // MARK: - Handle Device Token
    
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        
        self.deviceToken = token
        print("📱 Device Token: \(token)")
        
        // Set APNs token for FCM
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }
    
    // MARK: - FCM Token Management
    
    func setupFCMToken() {
        #if targetEnvironment(simulator)
        print("⚠️ Skipping FCM setup on simulator (APNS not available)")
        return
        #else
        // Get FCM token
        Messaging.messaging().token { [weak self] token, error in
            guard let self = self else { return }
            
            if let error = error {
                // Only log as warning, not error, since it's expected on simulator
                print("⚠️ FCM token unavailable: \(error.localizedDescription)")
                return
            }
            
            if let token = token {
                Task { @MainActor in
                    self.fcmToken = token
                    print("🔑 FCM Token: \(token)")
                    await self.saveFCMTokenToFirestore(token)
                }
            }
        }
        #endif
        
        // Listen for token refresh
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fcmTokenRefreshed),
            name: Notification.Name.MessagingRegistrationTokenRefreshed,
            object: nil
        )
    }
    
    @objc private func fcmTokenRefreshed() {
        Messaging.messaging().token { [weak self] token, error in
            guard let self = self, let token = token else { return }
            
            Task { @MainActor in
                self.fcmToken = token
                print("🔄 FCM Token refreshed: \(token)")
                await self.saveFCMTokenToFirestore(token)
            }
        }
    }
    
    // MARK: - Save Token to Firestore
    
    private func saveFCMTokenToFirestore(_ token: String) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ No authenticated user to save FCM token")
            return
        }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "fcmToken": token,
                "fcmTokenUpdatedAt": FieldValue.serverTimestamp(),
                "platform": "ios"
            ])
            
            print("✅ FCM token saved to Firestore for user: \(userId)")
        } catch {
            print("❌ Error saving FCM token to Firestore: \(error)")
        }
    }
    
    // MARK: - Remove Token on Logout
    
    func removeFCMTokenFromFirestore() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "fcmToken": FieldValue.delete()
            ])
            
            print("✅ FCM token removed from Firestore")
        } catch {
            print("❌ Error removing FCM token: \(error)")
        }
    }
    
    // MARK: - Handle Foreground Notifications
    
    func handleForegroundNotification(_ notification: UNNotification) {
        let userInfo = notification.request.content.userInfo
        
        print("📬 Received foreground notification:")
        print("   Title: \(notification.request.content.title)")
        print("   Body: \(notification.request.content.body)")
        print("   User Info: \(userInfo)")
        
        // Update badge count
        updateBadgeCount()
        
        // Post local notification for app to handle
        NotificationCenter.default.post(
            name: Notification.Name("pushNotificationReceived"),
            object: nil,
            userInfo: userInfo
        )
    }
    
    func handleNotificationTap(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        
        print("👆 User tapped notification:")
        print("   User Info: \(userInfo)")
        
        // Extract notification type and data
        if let notificationType = userInfo["type"] as? String {
            handleNotificationAction(type: notificationType, data: userInfo)
        }
    }
    
    private func handleNotificationAction(type: String, data: [AnyHashable: Any]) {
        // Handle different notification types
        switch type {
        case "message":
            // Open specific conversation
            if let conversationId = data["conversationId"] as? String {
                print("📬 Opening conversation: \(conversationId)")
                MessagingCoordinator.shared.openConversation(conversationId)
            }
        case "messageRequest":
            // Open message requests tab
            if let conversationId = data["conversationId"] as? String {
                print("📨 Opening message request: \(conversationId)")
                MessagingCoordinator.shared.openMessageRequests()
            }
        default:
            // Post notification for app to handle navigation
            NotificationCenter.default.post(
                name: Notification.Name("pushNotificationTapped"),
                object: nil,
                userInfo: data as? [String: Any] ?? [:]
            )
        }
    }
    
    // MARK: - Badge Management
    
    func updateBadgeCount() {
        Task {
            guard let userId = Auth.auth().currentUser?.uid else { return }
            
            do {
                // Calculate total unread from conversations (messages)
                let conversationsSnapshot = try await db.collection("conversations")
                    .whereField("participantIds", arrayContains: userId)
                    .whereField("conversationStatus", isEqualTo: "accepted")
                    .getDocuments()
                
                var totalUnreadMessages = 0
                for document in conversationsSnapshot.documents {
                    if let unreadCounts = document.data()["unreadCounts"] as? [String: Int],
                       let count = unreadCounts[userId] {
                        totalUnreadMessages += count
                    }
                }
                
                // Add general notifications count
                let notificationsSnapshot = try await db.collection("notifications")
                    .whereField("userId", isEqualTo: userId)
                    .whereField("read", isEqualTo: false)
                    .getDocuments()
                
                let totalNotifications = notificationsSnapshot.documents.count
                
                // Total badge = messages + notifications
                let totalBadge = totalUnreadMessages + totalNotifications
                
                await MainActor.run {
                    UIApplication.shared.applicationIconBadgeNumber = totalBadge
                }
                
                print("📛 Badge count updated: \(totalBadge) (Messages: \(totalUnreadMessages), Notifications: \(totalNotifications))")
            } catch {
                print("❌ Error updating badge count: \(error)")
            }
        }
    }
    
    func clearBadge() {
        UIApplication.shared.applicationIconBadgeNumber = 0
        print("📛 Badge cleared")
    }
    
    // MARK: - Test Notification
    
    func scheduleTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "This is a test notification from AMENAPP"
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ Test notification scheduled")
        } catch {
            print("❌ Error scheduling test notification: \(error)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    
    // Called when notification arrives while app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            handleForegroundNotification(notification)
        }
        
        // Show notification even in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Called when user taps notification
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

extension PushNotificationManager: MessagingDelegate {
    
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else { return }
        
        Task { @MainActor in
            self.fcmToken = fcmToken
            print("🔑 FCM Token received: \(fcmToken)")
            await self.saveFCMTokenToFirestore(fcmToken)
        }
    }
}
