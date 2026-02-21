//
//  NotificationManager.swift
//  AMENAPP
//
//  Created by Steph on 1/31/26.
//
//  Manages all app notifications including prayer reminders
//

import UserNotifications
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

/// Manages notification permissions and scheduling
@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var notificationSettings: [String: Bool] = [
        "prayerReminders": true,
        "newMessages": true,
        "trendingPosts": false
    ]
    
    @Published var isAuthorized: Bool = false
    
    private let center = UNUserNotificationCenter.current()
    private let db = Firestore.firestore()
    // DEPRECATED: UserDefaults storage deprecated. Settings now stored in Firestore.
    private let settingsKey = "notification_preferences"
    
    private init() {
        Task {
            await loadSettings()
        }
        checkAuthorization()
    }
    
    // MARK: - Authorization
    
    /// Request notification permissions from user
    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            
            if granted {
                print("✅ Notifications authorized")
            } else {
                print("❌ Notifications denied")
            }
        } catch {
            print("❌ Notification authorization error: \(error)")
        }
    }
    
    /// Check current authorization status
    func checkAuthorization() {
        Task {
            let settings = await center.notificationSettings()
            isAuthorized = settings.authorizationStatus == .authorized
        }
    }
    
    // MARK: - Settings Management
    
    /// Update notification preference (saves to Firestore)
    func updatePreference(_ key: String, enabled: Bool) {
        notificationSettings[key] = enabled
        
        Task {
            await saveSettings()
            await scheduleAllNotifications()
        }
        
        print("🔔 Notification preference updated: \(key) = \(enabled)")
    }
    
    /// Load saved notification preferences from Firestore
    func loadSettings() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ No authenticated user to load notification settings")
            // Migrate legacy UserDefaults settings if they exist
            await migrateLegacySettings()
            return
        }
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            if let data = document.data(),
               let firestoreSettings = data["notificationSettings"] as? [String: Bool] {
                await MainActor.run {
                    // Map Firestore keys to local keys
                    notificationSettings["prayerReminders"] = firestoreSettings["prayerRequests"] ?? true
                    notificationSettings["newMessages"] = firestoreSettings["messages"] ?? true
                    notificationSettings["trendingPosts"] = firestoreSettings["communityUpdates"] ?? false
                }
                print("✅ Loaded notification settings from Firestore: \(notificationSettings)")
            } else {
                // No settings in Firestore, try migrating from UserDefaults
                await migrateLegacySettings()
            }
        } catch {
            print("❌ Error loading notification settings from Firestore: \(error.localizedDescription)")
            // Fall back to UserDefaults if Firestore fails
            await migrateLegacySettings()
        }
    }
    
    /// Save notification preferences to Firestore
    func saveSettings() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ No authenticated user to save notification settings")
            return
        }
        
        // Map local keys to Firestore keys
        let firestoreSettings: [String: Bool] = [
            "prayerRequests": notificationSettings["prayerReminders"] ?? true,
            "messages": notificationSettings["newMessages"] ?? true,
            "communityUpdates": notificationSettings["trendingPosts"] ?? false
        ]
        
        do {
            try await db.collection("users").document(userId).updateData([
                "notificationSettings": firestoreSettings,
                "notificationSettingsUpdatedAt": FieldValue.serverTimestamp()
            ])
            print("✅ Notification settings saved to Firestore")
        } catch {
            print("❌ Error saving notification settings to Firestore: \(error.localizedDescription)")
        }
    }
    
    /// Migrate legacy UserDefaults settings to Firestore (one-time migration)
    private func migrateLegacySettings() async {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            await MainActor.run {
                notificationSettings = decoded
            }
            print("✅ Migrated notification settings from UserDefaults: \(notificationSettings)")
            
            // Save to Firestore and remove from UserDefaults
            await saveSettings()
            UserDefaults.standard.removeObject(forKey: settingsKey)
            print("🧹 Removed legacy UserDefaults settings")
        }
    }
    
    // MARK: - Prayer Reminders
    
    /// Schedule prayer reminder notifications
    func schedulePrayerReminders(time: String) async {
        guard notificationSettings["prayerReminders"] == true else {
            print("⏭️ Prayer reminders disabled, skipping scheduling")
            return
        }
        
        guard isAuthorized else {
            print("⚠️ Notifications not authorized, requesting...")
            await requestAuthorization()
            return
        }
        
        // Remove existing prayer reminders
        center.removePendingNotificationRequests(withIdentifiers: ["prayer_reminder"])
        
        // Schedule new reminders based on time preference
        let timeSlots = getPrayerTimeSlots(for: time)
        
        for (index, timeSlot) in timeSlots.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Time for Prayer"
            content.body = "Take a moment to connect with God through prayer."
            content.sound = .default
            content.categoryIdentifier = "PRAYER_REMINDER"
            
            var dateComponents = DateComponents()
            dateComponents.hour = timeSlot.hour
            dateComponents.minute = timeSlot.minute
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: "prayer_reminder_\(index)",
                content: content,
                trigger: trigger
            )
            
            do {
                try await center.add(request)
                print("✅ Scheduled prayer reminder for \(timeSlot.hour):\(String(format: "%02d", timeSlot.minute))")
            } catch {
                print("❌ Failed to schedule prayer reminder: \(error)")
            }
        }
    }
    
    private func getPrayerTimeSlots(for time: String) -> [(hour: Int, minute: Int)] {
        switch time {
        case "Morning":
            return [(hour: 8, minute: 0)]
        case "Afternoon":
            return [(hour: 14, minute: 0)]
        case "Evening":
            return [(hour: 18, minute: 0)]
        case "Night":
            return [(hour: 21, minute: 0)]
        case "Day & Night":
            return [(hour: 8, minute: 0), (hour: 21, minute: 0)]
        default:
            return [(hour: 8, minute: 0)]
        }
    }
    
    // MARK: - Message Notifications
    
    /// Send notification for new message
    func sendMessageNotification(from senderName: String, preview: String) async {
        guard notificationSettings["newMessages"] == true else { return }
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "New Message from \(senderName)"
        content.body = preview
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "NEW_MESSAGE"
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate delivery
        )
        
        do {
            try await center.add(request)
            print("✅ Sent message notification")
        } catch {
            print("❌ Failed to send message notification: \(error)")
        }
    }
    
    // MARK: - Trending Posts Notifications
    
    /// Send notification for trending post
    func sendTrendingPostNotification(title: String) async {
        guard notificationSettings["trendingPosts"] == true else { return }
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Trending in Community"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = "TRENDING_POST"
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        do {
            try await center.add(request)
            print("✅ Sent trending post notification")
        } catch {
            print("❌ Failed to send trending notification: \(error)")
        }
    }
    
    // MARK: - Schedule All
    
    /// Re-schedule all notifications based on current settings
    func scheduleAllNotifications() async {
        // This would be called when settings change
        // You'll need to store the prayer time preference and re-schedule
        print("🔄 Re-scheduling all notifications based on settings")
    }
    
    // MARK: - Clear All
    
    /// Remove all pending notifications
    func clearAllNotifications() {
        center.removeAllPendingNotificationRequests()
        print("🗑️ Cleared all pending notifications")
    }
}

// MARK: - Notification Categories

extension NotificationManager {
    /// Setup notification categories with actions
    func setupNotificationCategories() {
        // Prayer reminder actions
        let prayAction = UNNotificationAction(
            identifier: "PRAY_NOW",
            title: "Pray Now",
            options: .foreground
        )
        let laterAction = UNNotificationAction(
            identifier: "REMIND_LATER",
            title: "Remind Me Later",
            options: []
        )
        
        let prayerCategory = UNNotificationCategory(
            identifier: "PRAYER_REMINDER",
            actions: [prayAction, laterAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Message actions
        let replyAction = UNNotificationAction(
            identifier: "REPLY_MESSAGE",
            title: "Reply",
            options: .foreground
        )
        
        let messageCategory = UNNotificationCategory(
            identifier: "NEW_MESSAGE",
            actions: [replyAction],
            intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([prayerCategory, messageCategory])
        print("✅ Notification categories setup complete")
    }
}
