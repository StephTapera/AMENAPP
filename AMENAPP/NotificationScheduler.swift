//
//  NotificationScheduler.swift
//  AMENAPP
//
//  Intelligent notification scheduler with user preference awareness
//

import Foundation
import UserNotifications
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

/// Schedules personalized, context-aware notifications
@MainActor
class NotificationScheduler: ObservableObject {
    static let shared = NotificationScheduler()
    
    private let center = UNUserNotificationCenter.current()
    private let db = Firestore.firestore()
    
    // Daily notification counter (resets at midnight)
    @Published private(set) var dailyNotificationCount = 0
    private var lastResetDate: Date?
    
    private init() {
        checkAndResetDailyCounter()
    }
    
    // MARK: - Daily Counter Management
    
    private func checkAndResetDailyCounter() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if let lastReset = lastResetDate {
            let lastResetDay = calendar.startOfDay(for: lastReset)
            if today > lastResetDay {
                dailyNotificationCount = 0
                lastResetDate = today
            }
        } else {
            lastResetDate = today
        }
    }
    
    private func incrementCounter() {
        checkAndResetDailyCounter()
        dailyNotificationCount += 1
    }
    
    private func canSendNotification(preferences: AMENUserPreferences) -> Bool {
        checkAndResetDailyCounter()
        return dailyNotificationCount < preferences.maxDailyNotifications
    }
    
    // MARK: - Morning Devotional
    
    /// Schedule morning devotional nudge at user-preferred time
    func scheduleMorningDevotional(for userID: String, preferences: AMENUserPreferences) async {
        guard preferences.notificationsEnabled,
              preferences.morningDevotionalEnabled,
              canSendNotification(preferences: preferences) else {
            return
        }
        
        // Cancel existing devotional notifications
        center.removePendingNotificationRequests(withIdentifiers: ["morning_devotional"])
        
        let content = UNMutableNotificationContent()
        content.title = "Good morning 🌅"
        content.body = "Start your day with today's verse and a moment of reflection"
        content.sound = .default
        content.categoryIdentifier = "MORNING_DEVOTIONAL"
        
        // Schedule for the time specified in preferences
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: preferences.morningDevotionalTime)
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: "morning_devotional",
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
            incrementCounter()
            dlog("✅ Morning devotional scheduled for \(components.hour ?? 0):\(components.minute ?? 0)")
        } catch {
            dlog("❌ Failed to schedule morning devotional: \(error)")
        }
    }
    
    // MARK: - Follow Activity Alerts
    
    /// Notify when a followed user posts after a long absence
    func notifyFollowedUserReturned(
        followerID: String,
        authorName: String,
        postContent: String,
        preferences: AMENUserPreferences
    ) async {
        guard preferences.notificationsEnabled,
              preferences.followActivityAlerts,
              canSendNotification(preferences: preferences) else {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "\(authorName) is back!"
        content.body = postContent.prefix(100) + (postContent.count > 100 ? "..." : "")
        content.sound = .default
        content.categoryIdentifier = "FOLLOW_ACTIVITY"
        content.userInfo = ["authorName": authorName, "type": "follow_return"]
        
        let request = UNNotificationRequest(
            identifier: "follow_return_\(UUID().uuidString)",
            content: content,
            trigger: nil // Immediate delivery
        )
        
        do {
            try await center.add(request)
            incrementCounter()
            dlog("✅ Follow return notification sent for \(authorName)")
        } catch {
            dlog("❌ Failed to send follow return notification: \(error)")
        }
    }
    
    // MARK: - First Amen Alert
    
    /// Notify when a prayer request receives its first Amen
    func notifyFirstAmen(
        for postID: String,
        authorID: String,
        userName: String,
        preferences: AMENUserPreferences
    ) async {
        guard preferences.notificationsEnabled,
              preferences.firstAmenAlert,
              canSendNotification(preferences: preferences) else {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Your prayer received its first Amen 🙏"
        content.body = "\(userName) is praying with you"
        content.sound = .default
        content.categoryIdentifier = "FIRST_AMEN"
        content.userInfo = ["postID": postID, "userName": userName, "type": "first_amen"]
        
        let request = UNNotificationRequest(
            identifier: "first_amen_\(postID)",
            content: content,
            trigger: nil // Immediate delivery
        )
        
        do {
            try await center.add(request)
            incrementCounter()
            dlog("✅ First Amen notification sent")
        } catch {
            dlog("❌ Failed to send first Amen notification: \(error)")
        }
    }
    
    // MARK: - Geofence Event Reminders
    
    /// Schedule geofence-aware church event reminder
    func scheduleGeofenceEventReminder(
        eventID: String,
        eventName: String,
        eventTime: Date,
        location: CLLocationCoordinate2D,
        radius: Double = 500, // meters
        preferences: AMENUserPreferences
    ) async {
        guard preferences.notificationsEnabled,
              preferences.geofenceReminders,
              canSendNotification(preferences: preferences) else {
            return
        }
        
        // Create circular region around event location
        let region = CLCircularRegion(
            center: location,
            radius: radius,
            identifier: "event_\(eventID)"
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        
        let content = UNMutableNotificationContent()
        content.title = "\(eventName) is nearby"
        content.body = "You're close to the event location. Event starts soon!"
        content.sound = .default
        content.categoryIdentifier = "EVENT_REMINDER"
        content.userInfo = ["eventID": eventID, "type": "geofence_event"]
        
        let trigger = UNLocationNotificationTrigger(region: region, repeats: false)
        let request = UNNotificationRequest(
            identifier: "geofence_\(eventID)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
            incrementCounter()
            dlog("✅ Geofence event reminder scheduled for \(eventName)")
        } catch {
            dlog("❌ Failed to schedule geofence reminder: \(error)")
        }
    }
    
    // MARK: - Prayer Request Notification
    
    /// Send notification for new prayer request
    func notifyPrayerRequest(
        postID: String,
        authorName: String,
        prayerContent: String,
        preferences: AMENUserPreferences
    ) async {
        guard preferences.notificationsEnabled,
              preferences.prayerRequestAlerts,
              canSendNotification(preferences: preferences) else {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "\(authorName) needs prayer"
        content.body = prayerContent.prefix(150) + (prayerContent.count > 150 ? "..." : "")
        content.sound = .default
        content.categoryIdentifier = "PRAYER_REQUEST"
        content.userInfo = ["postID": postID, "authorName": authorName, "type": "prayer_request"]
        
        let request = UNNotificationRequest(
            identifier: "prayer_request_\(postID)",
            content: content,
            trigger: nil
        )
        
        do {
            try await center.add(request)
            incrementCounter()
            dlog("✅ Prayer request notification sent")
        } catch {
            dlog("❌ Failed to send prayer request notification: \(error)")
        }
    }
    
    // MARK: - Testimony Notification
    
    /// Send notification for new testimony
    func notifyTestimony(
        postID: String,
        authorName: String,
        testimonyContent: String,
        preferences: AMENUserPreferences
    ) async {
        guard preferences.notificationsEnabled,
              preferences.testimonyAlerts,
              canSendNotification(preferences: preferences) else {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "\(authorName) shared a testimony"
        content.body = testimonyContent.prefix(150) + (testimonyContent.count > 150 ? "..." : "")
        content.sound = .default
        content.categoryIdentifier = "TESTIMONY_POSTED"
        content.userInfo = ["postID": postID, "authorName": authorName, "type": "testimony"]
        
        let request = UNNotificationRequest(
            identifier: "testimony_\(postID)",
            content: content,
            trigger: nil
        )
        
        do {
            try await center.add(request)
            incrementCounter()
            dlog("✅ Testimony notification sent")
        } catch {
            dlog("❌ Failed to send testimony notification: \(error)")
        }
    }
    
    // MARK: - Event Reminder
    
    /// Schedule event reminder notification
    func scheduleEventReminder(
        eventID: String,
        eventName: String,
        eventTime: Date,
        minutesBefore: Int = 60,
        preferences: AMENUserPreferences
    ) async {
        guard preferences.notificationsEnabled,
              preferences.eventReminders,
              canSendNotification(preferences: preferences) else {
            return
        }
        
        let reminderTime = eventTime.addingTimeInterval(-Double(minutesBefore * 60))
        
        guard reminderTime > Date() else {
            dlog("⚠️ Event reminder time is in the past, skipping")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Event reminder: \(eventName)"
        content.body = "Starting in \(minutesBefore) minutes"
        content.sound = .default
        content.categoryIdentifier = "EVENT_REMINDER"
        content.userInfo = ["eventID": eventID, "eventName": eventName, "type": "event_reminder"]
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: reminderTime.timeIntervalSinceNow,
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "event_reminder_\(eventID)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
            incrementCounter()
            dlog("✅ Event reminder scheduled for \(eventName)")
        } catch {
            dlog("❌ Failed to schedule event reminder: \(error)")
        }
    }
    
    // MARK: - Cooldown Management
    
    /// Check if enough time has passed since last notification of this type
    func canSendWithCooldown(type: String, cooldownMinutes: Int = 30) -> Bool {
        let key = "last_notification_\(type)"
        
        if let lastTime = UserDefaults.standard.object(forKey: key) as? Date {
            let elapsed = Date().timeIntervalSince(lastTime) / 60 // Convert to minutes
            if elapsed < Double(cooldownMinutes) {
                dlog("⚠️ Cooldown active for \(type): \(Int(elapsed))min elapsed, need \(cooldownMinutes)min")
                return false
            }
        }
        
        UserDefaults.standard.set(Date(), forKey: key)
        return true
    }
    
    // MARK: - Utility
    
    /// Cancel all pending notifications
    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        dlog("✅ All pending notifications cancelled")
    }
    
    /// Cancel specific notification
    func cancelNotification(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        dlog("✅ Cancelled notification: \(identifier)")
    }
}
