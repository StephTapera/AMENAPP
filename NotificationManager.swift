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
    // P2 FIX: Track the app version at which the notification prompt was last shown
    // so that an upgrade can surface the Settings redirect if the user previously denied.
    private let notifPromptVersionKey = "lastNotifPromptVersion"

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
            // P2 FIX: Record the version at which the prompt was shown
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                UserDefaults.standard.set(version, forKey: notifPromptVersionKey)
            }
            if granted {
                dlog("✅ Notifications authorized")
            } else {
                dlog("❌ Notifications denied")
            }
        } catch {
            dlog("❌ Notification authorization error: \(error)")
        }
    }

    /// P2 FIX: Check whether a version-based re-prompt is warranted.
    /// - If status is .notDetermined: always prompt (first install or after reset).
    /// - If status is .denied AND the current app version is newer than when we last prompted:
    ///   present a UIAlert directing the user to Settings (iOS does not allow a second
    ///   programmatic prompt after the user has denied once).
    /// Call this from onAppear in the main app view or after sign-in.
    func checkVersionBasedReprompt() async {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let lastPromptVersion = UserDefaults.standard.string(forKey: notifPromptVersionKey) ?? ""

        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            // First launch or reset — request directly
            await requestAuthorization()
        case .denied:
            // Only show the Settings redirect if this is a new version since we last prompted
            if currentVersion > lastPromptVersion {
                UserDefaults.standard.set(currentVersion, forKey: notifPromptVersionKey)
                await showSettingsRedirectAlert()
            }
        default:
            isAuthorized = settings.authorizationStatus == .authorized
        }
    }

    /// Show a UIAlert telling the user to enable notifications in Settings.
    /// Called only when the system status is .denied and a new app version warrants re-prompting.
    @MainActor
    private func showSettingsRedirectAlert() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        let alert = UIAlertController(
            title: "Enable Notifications",
            message: "Turn on notifications in Settings to receive prayer reminders, messages, and community updates.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        rootVC.present(alert, animated: true)
        dlog("🔔 Showed Settings redirect alert for notification re-prompt")
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
        
        dlog("🔔 Notification preference updated: \(key) = \(enabled)")
    }
    
    /// Load saved notification preferences from Firestore
    func loadSettings() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("⚠️ No authenticated user to load notification settings")
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
                dlog("✅ Loaded notification settings from Firestore: \(notificationSettings)")
            } else {
                // No settings in Firestore, try migrating from UserDefaults
                await migrateLegacySettings()
            }
        } catch {
            dlog("❌ Error loading notification settings from Firestore: \(error.localizedDescription)")
            // Fall back to UserDefaults if Firestore fails
            await migrateLegacySettings()
        }
    }
    
    /// Save notification preferences to Firestore
    func saveSettings() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("⚠️ No authenticated user to save notification settings")
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
            dlog("✅ Notification settings saved to Firestore")
        } catch {
            dlog("❌ Error saving notification settings to Firestore: \(error.localizedDescription)")
        }
    }
    
    /// Migrate legacy UserDefaults settings to Firestore (one-time migration)
    private func migrateLegacySettings() async {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            await MainActor.run {
                notificationSettings = decoded
            }
            dlog("✅ Migrated notification settings from UserDefaults: \(notificationSettings)")
            
            // Save to Firestore and remove from UserDefaults
            await saveSettings()
            UserDefaults.standard.removeObject(forKey: settingsKey)
            dlog("🧹 Removed legacy UserDefaults settings")
        }
    }
    
    // MARK: - Prayer Reminders
    
    /// Schedule prayer reminder notifications
    func schedulePrayerReminders(time: String) async {
        guard notificationSettings["prayerReminders"] == true else {
            dlog("⏭️ Prayer reminders disabled, skipping scheduling")
            return
        }
        
        guard isAuthorized else {
            dlog("⚠️ Notifications not authorized, requesting...")
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
                dlog("✅ Scheduled prayer reminder for \(timeSlot.hour):\(String(format: "%02d", timeSlot.minute))")
            } catch {
                dlog("❌ Failed to schedule prayer reminder: \(error)")
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
            dlog("✅ Sent message notification")
        } catch {
            dlog("❌ Failed to send message notification: \(error)")
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
            dlog("✅ Sent trending post notification")
        } catch {
            dlog("❌ Failed to send trending notification: \(error)")
        }
    }
    
    // MARK: - Schedule All
    
    /// Re-schedule all notifications based on current settings.
    /// Called automatically whenever a preference changes via updatePreference(_:enabled:).
    func scheduleAllNotifications() async {
        dlog("🔄 Re-scheduling all notifications based on settings")

        // Cancel all pending local notifications so we start fresh.
        center.removeAllPendingNotificationRequests()

        guard isAuthorized else {
            dlog("⚠️ Notifications not authorized — skipping scheduling")
            return
        }

        // Re-schedule prayer reminders if enabled, using the stored time preference.
        if notificationSettings["prayerReminders"] == true {
            let storedTime = UserDefaults.standard.string(forKey: "preferredPrayerTime") ?? "Morning"
            await schedulePrayerReminders(time: storedTime)
        }

        // Message and trending-post notifications are push-delivered by the server;
        // no local scheduling needed here beyond the category/action setup.
        dlog("✅ Notification scheduling complete")
    }
    
    // MARK: - Clear All
    
    /// Remove all pending notifications
    func clearAllNotifications() {
        center.removeAllPendingNotificationRequests()
        dlog("🗑️ Cleared all pending notifications")
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
        
        // MARK: - New Custom Categories
        
        // Prayer Request actions: Pray Now, Add to List, Dismiss
        let prayNowAction = UNNotificationAction(
            identifier: "PRAY_NOW",
            title: "Pray Now",
            options: .foreground
        )
        
        let addToListAction = UNNotificationAction(
            identifier: "ADD_TO_PRAYER_LIST",
            title: "Add to List",
            options: []
        )
        
        let dismissPrayerAction = UNNotificationAction(
            identifier: "DISMISS_PRAYER",
            title: "Dismiss",
            options: .destructive
        )
        
        let prayerRequestCategory = UNNotificationCategory(
            identifier: "PRAYER_REQUEST",
            actions: [prayNowAction, addToListAction, dismissPrayerAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        // Testimony Posted actions: React 🙌, Comment, Share
        let reactAction = UNNotificationAction(
            identifier: "REACT_AMEN",
            title: "🙌 Amen",
            options: []
        )
        
        let commentAction = UNNotificationAction(
            identifier: "COMMENT_TESTIMONY",
            title: "Comment",
            options: .foreground
        )
        
        let shareTestimonyAction = UNNotificationAction(
            identifier: "SHARE_TESTIMONY",
            title: "Share",
            options: .foreground
        )
        
        let testimonyPostedCategory = UNNotificationCategory(
            identifier: "TESTIMONY_POSTED",
            actions: [reactAction, commentAction, shareTestimonyAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        // Event Reminder actions: I'll Be There, Remind Me Later
        let attendEventAction = UNNotificationAction(
            identifier: "ATTEND_EVENT",
            title: "I'll Be There",
            options: []
        )
        
        let remindEventLaterAction = UNNotificationAction(
            identifier: "REMIND_EVENT_LATER",
            title: "Remind Me Later",
            options: []
        )
        
        let eventReminderCategory = UNNotificationCategory(
            identifier: "EVENT_REMINDER",
            actions: [attendEventAction, remindEventLaterAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        center.setNotificationCategories([
            prayerCategory,
            messageCategory,
            prayerRequestCategory,
            testimonyPostedCategory,
            eventReminderCategory
        ])
        dlog("✅ Notification categories setup complete")
    }
}
