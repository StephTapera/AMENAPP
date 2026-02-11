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

/// Manages prayer break notifications with accurate timing based on user preferences
@MainActor
class BreakTimeNotificationManager: ObservableObject {
    static let shared = BreakTimeNotificationManager()
    
    @Published var isAuthorized: Bool = false
    @Published var scheduledBreakTimes: [BreakTime] = []
    
    private let center = UNUserNotificationCenter.current()
    private let breakTimeKey = "break_time_schedule"
    
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
    
    /// Schedule break notifications based on prayer time preference from onboarding
    func scheduleBreakNotifications(for prayerTime: String) async {
        guard isAuthorized else {
            print("⚠️ Not authorized for break notifications")
            _ = await requestAuthorization()
            return
        }
        
        // Remove existing break notifications
        center.removePendingNotificationRequests(withIdentifiers: getAllBreakIdentifiers())
        
        // Get break times based on user preference
        let breakTimes = getBreakTimes(for: prayerTime)
        scheduledBreakTimes = breakTimes
        saveScheduledBreakTimes()
        
        // Schedule each break notification
        for breakTime in breakTimes {
            await scheduleBreakNotification(for: breakTime)
        }
        
        print("✅ Scheduled \(breakTimes.count) break notifications for: \(prayerTime)")
    }
    
    private func scheduleBreakNotification(for breakTime: BreakTime) async {
        let content = UNMutableNotificationContent()
        content.title = "Time for a Break 🙏"
        content.body = "Step away from the screen and spend time in prayer with God"
        content.sound = .default
        content.categoryIdentifier = "PRAYER_BREAK"
        content.userInfo = [
            "break_time_id": breakTime.id.uuidString,
            "break_hour": breakTime.hour,
            "break_minute": breakTime.minute
        ]
        
        // Create date components for daily repeat
        var dateComponents = DateComponents()
        dateComponents.hour = breakTime.hour
        dateComponents.minute = breakTime.minute
        
        // Create trigger (repeats daily at specified time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: "break_\(breakTime.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
            print("✅ Scheduled break notification for \(breakTime.timeString)")
        } catch {
            print("❌ Failed to schedule break notification: \(error)")
        }
    }
    
    // MARK: - Break Time Calculation
    
    private func getBreakTimes(for prayerTime: String) -> [BreakTime] {
        switch prayerTime {
        case "Morning":
            return [
                BreakTime(hour: 8, minute: 0, title: "Morning Prayer Break", icon: "sunrise.fill")
            ]
            
        case "Afternoon":
            return [
                BreakTime(hour: 14, minute: 0, title: "Afternoon Prayer Break", icon: "sun.max.fill")
            ]
            
        case "Evening":
            return [
                BreakTime(hour: 18, minute: 0, title: "Evening Prayer Break", icon: "sunset.fill")
            ]
            
        case "Night":
            return [
                BreakTime(hour: 21, minute: 0, title: "Night Prayer Break", icon: "moon.stars.fill")
            ]
            
        case "Day & Night":
            return [
                BreakTime(hour: 8, minute: 0, title: "Morning Prayer Break", icon: "sunrise.fill"),
                BreakTime(hour: 21, minute: 0, title: "Night Prayer Break", icon: "moon.stars.fill")
            ]
            
        default:
            // Default to morning
            return [
                BreakTime(hour: 8, minute: 0, title: "Morning Prayer Break", icon: "sunrise.fill")
            ]
        }
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
        let prayNowAction = UNNotificationAction(
            identifier: "PRAY_NOW",
            title: "Pray Now",
            options: .foreground
        )
        
        let remindLaterAction = UNNotificationAction(
            identifier: "REMIND_LATER_15",
            title: "Remind in 15 min",
            options: []
        )
        
        let skipAction = UNNotificationAction(
            identifier: "SKIP_BREAK",
            title: "Skip",
            options: .destructive
        )
        
        let category = UNNotificationCategory(
            identifier: "PRAYER_BREAK",
            actions: [prayNowAction, remindLaterAction, skipAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Prayer Break Reminder",
            options: .customDismissAction
        )
        
        center.setNotificationCategories([category])
        print("✅ Break notification categories configured")
    }
    
    // MARK: - Reminder Actions
    
    /// Schedule a reminder for 15 minutes later
    func scheduleRemindLater() async {
        let content = UNMutableNotificationContent()
        content.title = "Prayer Break Reminder 🙏"
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
        let breakNotifications = pending.filter { $0.identifier.hasPrefix("break_") }
        return breakNotifications.count
    }
}
