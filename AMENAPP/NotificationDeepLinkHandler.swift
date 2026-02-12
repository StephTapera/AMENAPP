//
//  NotificationDeepLinkHandler.swift
//  AMENAPP
//
//  Handles deep linking from push notifications
//

import Foundation
import SwiftUI
import UserNotifications
import Combine

/// Handles deep linking from system push notifications
@MainActor
class NotificationDeepLinkHandler: ObservableObject {
    static let shared = NotificationDeepLinkHandler()
    
    @Published var pendingDeepLink: DeepLink?
    @Published var shouldNavigate = false
    
    private init() {
        setupNotificationHandlers()
    }
    
    // MARK: - Setup
    
    private func setupNotificationHandlers() {
        // Listen for push notification taps
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("didReceiveNotificationResponse"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo as? [String: Any] else { return }
            
            Task { @MainActor in
                await self.handleNotificationTap(userInfo: userInfo)
            }
        }
    }
    
    // MARK: - Handle Notification Tap
    
    /// Handle when user taps on a push notification
    func handleNotificationTap(userInfo: [String: Any]) async {
        print("🔗 Handling notification tap with userInfo: \(userInfo)")
        
        // Extract notification type and relevant IDs
        guard let type = userInfo["type"] as? String else {
            print("⚠️ No notification type found")
            return
        }
        
        let deepLink = createDeepLink(type: type, userInfo: userInfo)
        
        if let deepLink = deepLink {
            print("✅ Created deep link: \(deepLink)")
            self.pendingDeepLink = deepLink
            self.shouldNavigate = true
            
            // Haptic feedback
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
        }
    }
    
    /// Handle notification when app is in foreground
    func handleForegroundNotification(userInfo: [String: Any]) async {
        print("📲 Received foreground notification: \(userInfo)")
        
        // Refresh notifications service
        await NotificationService.shared.refresh()
        
        // Show in-app banner (optional)
        showInAppBanner(userInfo: userInfo)
    }
    
    // MARK: - Create Deep Link
    
    private func createDeepLink(type: String, userInfo: [String: Any]) -> DeepLink? {
        switch type {
        case "follow":
            guard let userId = userInfo["actorId"] as? String else { return nil }
            return .profile(userId: userId)
            
        case "amen", "comment", "mention", "reply":
            guard let postId = userInfo["postId"] as? String else { return nil }
            return .post(postId: postId, scrollToComments: type == "comment" || type == "reply")
            
        case "prayer_reminder":
            guard let prayerId = userInfo["prayerId"] as? String else { return nil }
            return .prayer(prayerId: prayerId)
            
        case "prayer_answered":
            guard let prayerId = userInfo["prayerId"] as? String else { return nil }
            return .prayer(prayerId: prayerId)
            
        case "message":
            guard let conversationId = userInfo["conversationId"] as? String else { return nil }
            return .conversation(conversationId: conversationId)
            
        default:
            print("⚠️ Unknown notification type: \(type)")
            return .notificationsTab
        }
    }
    
    // MARK: - In-App Banner
    
    private func showInAppBanner(userInfo: [String: Any]) {
        // Optional: Show a subtle banner when notification arrives in foreground
        // You can implement this with a custom view or use a library
        let message = userInfo["aps"] as? [String: Any]
        let alert = message?["alert"] as? [String: Any]
        let body = alert?["body"] as? String ?? "New notification"
        
        print("💬 In-app banner: \(body)")
        
        // Post notification for UI to display banner
        NotificationCenter.default.post(
            name: NSNotification.Name("showInAppBanner"),
            object: nil,
            userInfo: ["message": body, "data": userInfo]
        )
    }
    
    // MARK: - Clear Deep Link
    
    func clearDeepLink() {
        pendingDeepLink = nil
        shouldNavigate = false
    }
    
    // MARK: - Navigation Helper
    
    /// Convert deep link to NavigationPath value
    func navigationDestination(for deepLink: DeepLink) -> String {
        switch deepLink {
        case .profile(let userId):
            return "profile_\(userId)"
        case .post(let postId, _):
            return "post_\(postId)"
        case .prayer(let prayerId):
            return "prayer_\(prayerId)"
        case .conversation(let conversationId):
            return "conversation_\(conversationId)"
        case .notificationsTab:
            return "notifications"
        }
    }
}

// MARK: - Deep Link Model

enum DeepLink: Equatable {
    case profile(userId: String)
    case post(postId: String, scrollToComments: Bool)
    case prayer(prayerId: String)
    case conversation(conversationId: String)
    case notificationsTab
    
    static func == (lhs: DeepLink, rhs: DeepLink) -> Bool {
        switch (lhs, rhs) {
        case (.profile(let lId), .profile(let rId)):
            return lId == rId
        case (.post(let lId, let lScroll), .post(let rId, let rScroll)):
            return lId == rId && lScroll == rScroll
        case (.prayer(let lId), .prayer(let rId)):
            return lId == rId
        case (.conversation(let lId), .conversation(let rId)):
            return lId == rId
        case (.notificationsTab, .notificationsTab):
            return true
        default:
            return false
        }
    }
}

// MARK: - AppDelegate Integration

/// Add this to your AppDelegate to handle push notifications
extension NotificationDeepLinkHandler {
    
    /// Call this from AppDelegate when notification is tapped (app was closed/background)
    static func handleLaunch(withUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            await shared.handleNotificationTap(userInfo: userInfo)
        }
    }
    
    /// Call this from UNUserNotificationCenterDelegate when notification received in foreground
    static func handleForeground(withUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            await shared.handleForegroundNotification(userInfo: userInfo)
        }
    }
}

// MARK: - Usage Example in AppDelegate

/*
 
 // In your AppDelegate.swift or App struct:
 
 import UserNotifications
 
 class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
     
     func application(
         _ application: UIApplication,
         didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
     ) -> Bool {
         // Set notification delegate
         UNUserNotificationCenter.current().delegate = self
         
         // Handle notification if app was launched from notification
         if let notification = launchOptions?[.remoteNotification] as? [String: Any] {
             NotificationDeepLinkHandler.handleLaunch(withUserInfo: notification)
         }
         
         return true
     }
     
     // MARK: - UNUserNotificationCenterDelegate
     
     // Called when notification is tapped (app in background/foreground)
     func userNotificationCenter(
         _ center: UNUserNotificationCenter,
         didReceive response: UNNotificationResponse,
         withCompletionHandler completionHandler: @escaping () -> Void
     ) {
         let userInfo = response.notification.request.content.userInfo
         
         // Post notification for deep link handler
         NotificationCenter.default.post(
             name: NSNotification.Name("didReceiveNotificationResponse"),
             object: nil,
             userInfo: userInfo
         )
         
         completionHandler()
     }
     
     // Called when notification arrives while app is in foreground
     func userNotificationCenter(
         _ center: UNUserNotificationCenter,
         willPresent notification: UNNotification,
         withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
     ) {
         let userInfo = notification.request.content.userInfo
         
         NotificationDeepLinkHandler.handleForeground(withUserInfo: userInfo)
         
         // Show banner, badge, and sound
         completionHandler([.banner, .badge, .sound])
     }
     
     // Register for remote notifications
     func application(
         _ application: UIApplication,
         didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
     ) {
         let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
         let token = tokenParts.joined()
         print("📱 APNs Token: \(token)")
         
         // Send token to your backend
         Task {
             await saveAPNsToken(token)
         }
     }
     
     func application(
         _ application: UIApplication,
         didFailToRegisterForRemoteNotificationsWithError error: Error
     ) {
         print("❌ Failed to register for remote notifications: \(error)")
     }
     
     private func saveAPNsToken(_ token: String) async {
         // Save to Firestore user document
         guard let userId = Auth.auth().currentUser?.uid else { return }
         
         do {
             try await Firestore.firestore()
                 .collection("users")
                 .document(userId)
                 .updateData([
                     "apnsToken": token,
                     "apnsTokenUpdatedAt": FieldValue.serverTimestamp()
                 ])
             print("✅ APNs token saved")
         } catch {
             print("❌ Failed to save APNs token: \(error)")
         }
     }
 }
 
 // In your main App struct:
 
 @main
 struct AMENAPPApp: App {
     @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
     @StateObject private var deepLinkHandler = NotificationDeepLinkHandler.shared
     
     var body: some Scene {
         WindowGroup {
             ContentView()
                 .environmentObject(deepLinkHandler)
                 .onOpenURL { url in
                     // Handle deep links from URLs
                     handleDeepLink(url)
                 }
         }
     }
     
     private func handleDeepLink(_ url: URL) {
         // Parse URL and create appropriate deep link
         print("🔗 Deep link: \(url)")
     }
 }
 
 */
