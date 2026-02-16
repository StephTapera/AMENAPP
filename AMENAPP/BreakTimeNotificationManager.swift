//
//  BreakTimeNotificationManager.swift
//  AMENAPP
//
//  Created by Steph on 1/31/26.
//
//  Manages accurate break time notifications based on user's onboarding preferences
//

import UserNotifications
import SwiftUI
import Combine

/// Manages daily inspiration notifications (verses & app reminders) - NOT break reminders
/// Break reminders are now handled by SmartBreakReminderService based on actual usage
@MainActor
class BreakTimeNotificationManager: ObservableObject {
    static let shared = BreakTimeNotificationManager()
    
    @Published var isAuthorized: Bool = false
    @Published var scheduledBreakTimes: [BreakTime] = []
    
    private let center = UNUserNotificationCenter.current()
    private let breakTimeKey = "break_time_schedule"
    
    // Rotating verses for variety
    private let morningVerses = [
        ("This is the day that the Lord has made; let us rejoice and be glad in it", "Psalm 118:24"),
        ("The steadfast love of the Lord never ceases; his mercies never come to an end; they are new every morning", "Lamentations 3:22-23"),
        ("Satisfy us in the morning with your steadfast love, that we may rejoice and be glad all our days", "Psalm 90:14"),
        ("My soul is satisfied as with a rich feast, and my mouth praises you with joyful lips", "Psalm 63:5"),
        ("In the morning, O Lord, you hear my voice; in the morning I lay my requests before you", "Psalm 5:3")
    ]
    
    private let nightVerses = [
        ("Be still, and know that I am God", "Psalm 46:10"),
        ("In peace I will both lie down and sleep; for you alone, O Lord, make me dwell in safety", "Psalm 4:8"),
        ("The Lord is my light and my salvation; whom shall I fear?", "Psalm 27:1"),
        ("Cast all your anxieties on him, because he cares for you", "1 Peter 5:7"),
        ("Come to me, all who labor and are heavy laden, and I will give you rest", "Matthew 11:28")
    ]
    
    struct BreakTime: Codable, Identifiable {
        let id: UUID
        let hour: Int
        let minute: Int
        let title: String
        let icon: String
        
        init(hour: Int, minute: Int, title: String, icon: String) {
            self.id = UUID()
            self.hour = hour
            self.minute = minute
            self.title = title
            self.icon = icon
        }
        
        var timeString: String {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            
            if let date = Calendar.current.date(from: components) {
                return formatter.string(from: date)
            }
            return "\(hour):\(String(format: "%02d", minute))"
        }
    }
    
    private init() {
        checkAuthorization()
        loadScheduledBreakTimes()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
            isAuthorized = granted
            
            if granted {
                print("✅ Break notification authorization granted")
                setupNotificationCategories()
            } else {
                print("❌ Break notification authorization denied")
            }
            
            return granted
        } catch {
            print("❌ Break notification authorization error: \(error)")
            return false
        }
    }
    
    func checkAuthorization() {
        Task {
            let settings = await center.notificationSettings()
            isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }
    }
    
    // MARK: - Schedule Break Notifications
    
    /// Schedule break notifications (ONLY 2 daily: morning + night to avoid duplicates)
    func scheduleBreakNotifications(for prayerTime: String) async {
        guard isAuthorized else {
            print("⚠️ Not authorized for break notifications")
            _ = await requestAuthorization()
            return
        }
        
        // CRITICAL: Remove ALL existing break notifications first
        await removeAllBreakNotifications()

        // Get break times (strictly morning + night only, ignoring prayerTime parameter)
        let breakTimes = getBreakTimes(for: prayerTime)
        scheduledBreakTimes = breakTimes
        saveScheduledBreakTimes()
        
        // Schedule each break notification with unique identifiers
        for breakTime in breakTimes {
            await scheduleBreakNotification(for: breakTime)
        }
        
        print("✅ Scheduled EXACTLY \(breakTimes.count) break notifications (morning & night only)")
        
        // Verify no duplicates
        let count = await getPendingNotificationsCount()
        if count > 2 {
            print("⚠️ WARNING: Found \(count) pending break notifications! Expected 2.")
        }
    }
    
    private func scheduleBreakNotification(for breakTime: BreakTime) async {
        let content = UNMutableNotificationContent()
        
        // Select a random verse based on time of day
        let isMorning = breakTime.hour < 12
        let verses = isMorning ? morningVerses : nightVerses
        let randomVerse = verses.randomElement()!
        
        // Format notification
        if isMorning {
            content.title = "Good Morning"
            content.body = "\"\(randomVerse.0)\" - \(randomVerse.1)"
        } else {
            content.title = "Evening Reflection"
            content.body = "\"\(randomVerse.0)\" - \(randomVerse.1)"
        }
        
        content.sound = .default
        content.categoryIdentifier = "DAILY_INSPIRATION"
        content.userInfo = [
            "type": "daily_inspiration",
            "break_time_id": breakTime.id.uuidString,
            "break_hour": breakTime.hour,
            "break_minute": breakTime.minute,
            "verse": randomVerse.0,
            "reference": randomVerse.1
        ]
        
        // Create date components for daily repeat
        var dateComponents = DateComponents()
        dateComponents.hour = breakTime.hour
        dateComponents.minute = breakTime.minute
        
        // Create trigger (repeats daily at specified time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: "inspiration_\(breakTime.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
            print("✅ Scheduled daily inspiration for \(breakTime.timeString)")
        } catch {
            print("❌ Failed to schedule inspiration notification: \(error)")
        }
    }
    
    // MARK: - Break Time Calculation
    
    private func getBreakTimes(for prayerTime: String) -> [BreakTime] {
        // STRICTLY enforce only two daily inspirations (ignore prayerTime parameter)
        // These send verses and encouragement, NOT break reminders
        [
            BreakTime(hour: 8, minute: 0, title: "Morning Inspiration", icon: "sunrise.fill"),
            BreakTime(hour: 21, minute: 0, title: "Evening Reflection", icon: "moon.stars.fill")
        ]
    }
    
    // MARK: - Persistence
    
    private func saveScheduledBreakTimes() {
        if let encoded = try? JSONEncoder().encode(scheduledBreakTimes) {
            UserDefaults.standard.set(encoded, forKey: breakTimeKey)
        }
    }
    
    private func loadScheduledBreakTimes() {
        if let data = UserDefaults.standard.data(forKey: breakTimeKey),
           let decoded = try? JSONDecoder().decode([BreakTime].self, from: data) {
            scheduledBreakTimes = decoded
            print("✅ Loaded \(decoded.count) scheduled break times")
        }
    }
    
    // MARK: - Notification Categories
    
    private func setupNotificationCategories() {
        let reflectAction = UNNotificationAction(
            identifier: "REFLECT_NOW",
            title: "Reflect",
            options: .foreground
        )
        
        let shareAction = UNNotificationAction(
            identifier: "SHARE_VERSE",
            title: "Share",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "DAILY_INSPIRATION",
            actions: [reflectAction, shareAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Daily Inspiration",
            options: .customDismissAction
        )
        
        center.setNotificationCategories([category])
        print("✅ Daily inspiration notification categories configured")
    }
    
    // MARK: - Reminder Actions
    
    /// Schedule a reminder for 15 minutes later
    func scheduleRemindLater() async {
        let content = UNMutableNotificationContent()
        content.title = "Prayer Break Reminder"
        content.body = "Here's your reminder to take a prayer break"
        content.sound = .default
        content.categoryIdentifier = "PRAYER_BREAK"
        
        // Trigger in 15 minutes
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 900, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "remind_later_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
            print("✅ Scheduled reminder for 15 minutes")
        } catch {
            print("❌ Failed to schedule reminder: \(error)")
        }
    }
    
    // MARK: - Utilities
    
    private func getAllBreakIdentifiers() -> [String] {
        scheduledBreakTimes.map { "break_\($0.id.uuidString)" }
    }

    private func removeAllBreakNotifications() async {
        let pending = await center.pendingNotificationRequests()
        // Remove old "break_" notifications AND new "inspiration_" notifications
        let notificationIdentifiers = pending
            .filter { $0.identifier.hasPrefix("break_") || $0.identifier.hasPrefix("inspiration_") }
            .map { $0.identifier }
        if !notificationIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers)
            print("🗑️ Removed \(notificationIdentifiers.count) old notification(s)")
        }
    }
    
    /// Remove all break notifications
    func clearAllBreakNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: getAllBreakIdentifiers())
        scheduledBreakTimes.removeAll()
        saveScheduledBreakTimes()
        print("🗑️ Cleared all break notifications")
    }
    
    /// Get pending notifications count
    func getPendingNotificationsCount() async -> Int {
        let pending = await center.pendingNotificationRequests()
        let inspirationNotifications = pending.filter { 
            $0.identifier.hasPrefix("inspiration_") || $0.identifier.hasPrefix("break_") 
        }
        return inspirationNotifications.count
    }
}
