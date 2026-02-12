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
 2. This file uses CompositeNotificationDelegate for notification handling (not AppDelegate itself)
 3. Call setupMessaging() and setupFirestore() in application(_:didFinishLaunchingWithOptions:)
 
 Example:
 
 class AppDelegate: NSObject, UIApplicationDelegate {
     
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
        let center = UNUserNotificationCenter.current()
        
        // Use composite delegate that handles both Firebase and Church notifications
        center.delegate = CompositeNotificationDelegate.shared
        
        // Set FCM delegate - PushNotificationManager conforms to MessagingDelegate
        Messaging.messaging().delegate = PushNotificationManager.shared as MessagingDelegate
        
        // Setup FCM token
        PushNotificationManager.shared.setupFCMToken()
        
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

// MARK: - Notification Handling
// Note: Notification delegate methods are handled by CompositeNotificationDelegate
// which is set in setupMessaging(). The CompositeNotificationDelegate coordinates
// between PushNotificationManager and ChurchNotificationManager.
//
// If you need custom notification handling in AppDelegate, you can extend
// CompositeNotificationDelegate or PushNotificationManager instead.

// MARK: - Sample AppDelegate Template

/*
 Use this template if you don't have an AppDelegate yet:

import UIKit
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    
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
        let center = UNUserNotificationCenter.current()
        
        // Use composite delegate that handles notifications
        center.delegate = CompositeNotificationDelegate.shared
        
        // Set FCM delegate
        Messaging.messaging().delegate = PushNotificationManager.shared as MessagingDelegate
        
        // Setup FCM token
        PushNotificationManager.shared.setupFCMToken()
        
        print("✅ Push notifications configured")
    }
    
    func application(_ application: UIApplication, 
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        PushNotificationManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        print("✅ APNS token registered")
    }
    
    func application(_ application: UIApplication, 
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotificationManager.shared.didFailToRegisterForRemoteNotifications(error: error)
        print("❌ Failed to register for remote notifications: \(error)")
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

// Note: Notification delegate methods (willPresent, didReceive) are handled by
// CompositeNotificationDelegate and PushNotificationManager, not AppDelegate directly.
*/
