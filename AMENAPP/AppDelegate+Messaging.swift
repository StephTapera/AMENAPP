//
//  AppDelegate+Messaging.swift
//  AMENAPP
//
//  AppDelegate extension for messaging and push notifications
//  Add these methods to your existing AppDelegate
//

import UIKit
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

/*
 ⚠️ INTEGRATION INSTRUCTIONS:
 
 1. Add this code to your existing AppDelegate.swift file
 2. Make sure AppDelegate conforms to UNUserNotificationCenterDelegate
 3. Call setupMessaging() and setupFirestore() in application(_:didFinishLaunchingWithOptions:)
 
 Example:
 
 class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
     
     func application(_ application: UIApplication, 
                      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
         
         // Configure Firebase
         FirebaseApp.configure()
         
         // Setup Firestore offline persistence (MUST be called immediately after configure)
         setupFirestore()
         
         // Setup messaging
         setupMessaging()
         
         // Register for remote notifications
         application.registerForRemoteNotifications()
         
         return true
     }
     
     // Add all the methods below to your AppDelegate
 }
 */

// MARK: - Firestore Configuration

extension AppDelegate {
    
    /// Configure Firestore with offline persistence
    /// ⚠️ MUST be called immediately after FirebaseApp.configure()
    func setupFirestore() {
        let db = Firestore.firestore()
        let settings = FirestoreSettings()
        
        // Enable offline persistence
        settings.isPersistenceEnabled = true
        
        // Set cache size (unlimited for better offline support)
        settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        
        db.settings = settings
        
        print("✅ Firestore configured with offline persistence")
    }
}

// MARK: - Push Notification Setup

extension AppDelegate {
    
    /// Setup push notifications and FCM
    func setupMessaging() {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Configure push notification manager
        PushNotificationManager.shared.configure()
        
        print("✅ Push notifications configured")
    }
    
    /// Handle successful APNS token registration
    func application(_ application: UIApplication, 
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Pass device token to FCM
        Messaging.messaging().apnsToken = deviceToken
        
        print("✅ APNS token registered")
    }
    
    /// Handle failed APNS token registration
    func application(_ application: UIApplication, 
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate {
    
    /// Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        
        print("📬 Received notification while in foreground: \(userInfo)")
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        print("👆 User tapped notification: \(userInfo)")
        
        // Extract conversation ID
        if let conversationId = userInfo["conversationId"] as? String {
            handleNotificationTap(conversationId: conversationId)
        }
        
        completionHandler()
    }
    
    /// Handle notification tap - navigate to conversation
    private func handleNotificationTap(conversationId: String) {
        // Post notification to navigate to conversation
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenConversation"),
            object: nil,
            userInfo: ["conversationId": conversationId]
        )
        
        print("🚀 Navigating to conversation: \(conversationId)")
    }
}

// MARK: - Sample AppDelegate Template

/*
 Use this template if you don't have an AppDelegate yet:

import UIKit
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, 
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Configure Firebase
        FirebaseApp.configure()
        
        // Setup Firestore (MUST be called immediately after configure)
        setupFirestore()
        
        // Setup messaging
        setupMessaging()
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        
        return true
    }
    
    // MARK: - Firestore Configuration
    
    func setupFirestore() {
        let db = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        db.settings = settings
        print("✅ Firestore configured with offline persistence")
    }
    
    // MARK: - Push Notification Setup
    
    func setupMessaging() {
        UNUserNotificationCenter.current().delegate = self
        PushNotificationManager.shared.configure()
        print("✅ Push notifications configured")
    }
    
    func application(_ application: UIApplication, 
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        print("✅ APNS token registered")
    }
    
    func application(_ application: UIApplication, 
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let conversationId = userInfo["conversationId"] as? String {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenConversation"),
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
        }
        completionHandler()
    }
}

// Add to your @main App file:
@main
struct AMENAPPApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
*/
