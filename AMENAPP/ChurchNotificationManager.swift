//
//  ChurchNotificationManager.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import Foundation
import Combine
import UserNotifications
import CoreLocation

class ChurchNotificationManager: NSObject, ObservableObject {
    static let shared = ChurchNotificationManager()
    
    @Published var isAuthorized = false
    
    private override init() {
        super.init()
        checkNotificationAuthorization()
    }
    
    func checkNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func checkAuthorizationStatus() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized = settings.authorizationStatus == .authorized
        await MainActor.run {
            self.isAuthorized = authorized
        }
        return authorized
    }
    
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await MainActor.run {
                self.isAuthorized = granted
            }
            return granted
        } catch {
            print("Error requesting notification permission: \(error)")
            return false
        }
    }
    
    // Schedule reminder for upcoming service
    func scheduleServiceReminder(for church: Church, beforeMinutes: Int = 60) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Service Starting Soon"
        content.body = "\(church.name) service starts in \(beforeMinutes) minutes"
        content.sound = .default
        content.categoryIdentifier = "SERVICE_REMINDER"
        
        // Add action buttons
        let getDirectionsAction = UNNotificationAction(
            identifier: "GET_DIRECTIONS",
            title: "Get Directions",
            options: .foreground
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: .destructive
        )
        
        let category = UNNotificationCategory(
            identifier: "SERVICE_REMINDER",
            actions: [getDirectionsAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        // Calculate trigger time (for demo, we'll use 1 hour before next Sunday)
        let trigger = createServiceTrigger(serviceTime: church.serviceTime, beforeMinutes: beforeMinutes)
        
        let request = UNNotificationRequest(
            identifier: "service-\(church.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }
    
    // Schedule location-based reminder when near church
    func scheduleLocationReminder(for church: Church, radius: CLLocationDistance = 500) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "You're Near \(church.name)"
        content.body = "Stop by for a visit or check service times"
        content.sound = .default
        
        // Create location-based trigger
        let region = CLCircularRegion(
            center: church.coordinate,
            radius: radius,
            identifier: "church-\(church.id.uuidString)"
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        
        let trigger = UNLocationNotificationTrigger(region: region, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "location-\(church.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling location notification: \(error)")
            }
        }
    }
    
    // Schedule weekly reminder for saved church
    func scheduleWeeklyReminder(for church: Church) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Service This Sunday"
        content.body = "\(church.name) - \(church.serviceTime)"
        content.sound = .default
        content.badge = 1
        
        // Create weekly trigger for Saturday evening reminder
        var dateComponents = DateComponents()
        dateComponents.weekday = 7 // Saturday
        dateComponents.hour = 19 // 7 PM
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "weekly-\(church.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling weekly notification: \(error)")
            }
        }
    }
    
    // Remove all notifications for a church
    func removeNotifications(for church: Church) {
        let identifiers = [
            "service-\(church.id.uuidString)",
            "location-\(church.id.uuidString)",
            "weekly-\(church.id.uuidString)"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    // Helper to create service trigger
    private func createServiceTrigger(serviceTime: String, beforeMinutes: Int) -> UNCalendarNotificationTrigger {
        // Parse service time and create trigger
        // For demo purposes, setting for next Sunday at parsed time minus beforeMinutes
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        
        // Simple parser for "Sunday 9:00 AM" format
        if let timeRange = serviceTime.range(of: #"\d{1,2}:\d{2}\s*[AP]M"#, options: .regularExpression) {
            let timeString = String(serviceTime[timeRange])
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            if let time = formatter.date(from: timeString) {
                let calendar = Calendar.current
                let components = calendar.dateComponents([.hour, .minute], from: time)
                dateComponents.hour = components.hour
                dateComponents.minute = (components.minute ?? 0) - beforeMinutes
            }
        }
        
        return UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
    }
}

