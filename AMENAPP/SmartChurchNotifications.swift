//
//  SmartChurchNotifications.swift
//  AMENAPP
//
//  Created by Steph on 2/2/26.
//
//  Smart notification system for church features
//

import SwiftUI
import UserNotifications
import CoreLocation

// MARK: - Smart Notification Types

enum ChurchNotificationType: String {
    // Time-based notifications
    case serviceReminder = "service_reminder"
    case weeklyPreview = "weekly_preview"
    case preServiceAlert = "pre_service_alert"
    case morningOfService = "morning_of_service"
    
    // Location-based notifications
    case nearbyChurch = "nearby_church"
    case arrivingAtChurch = "arriving_at_church"
    case leftChurch = "left_church"
    
    // Engagement notifications
    case returnVisitor = "return_visitor"
    case newChurchSuggestion = "new_church_suggestion"
    case denominationEvent = "denomination_event"
    
    // Community notifications
    case friendAttends = "friend_attends"
    case specialEvent = "special_event"
    case holidayService = "holiday_service"
    
    var title: String {
        switch self {
        case .serviceReminder:
            return "Service Starting Soon"
        case .weeklyPreview:
            return "This Week's Services"
        case .preServiceAlert:
            return "Get Ready for Service"
        case .morningOfService:
            return "Good Morning!"
        case .nearbyChurch:
            return "Church Nearby"
        case .arrivingAtChurch:
            return "Welcome!"
        case .leftChurch:
            return "Thanks for Attending"
        case .returnVisitor:
            return "We Miss You"
        case .newChurchSuggestion:
            return "New Church Suggestion"
        case .denominationEvent:
            return "Special Event"
        case .friendAttends:
            return "Your Friends Are Going"
        case .specialEvent:
            return "Special Service"
        case .holidayService:
            return "Holiday Service"
        }
    }
}

// MARK: - Smart Notification UI Components

/// Notification preferences view
struct NotificationPreferencesView: View {
    @StateObject private var notificationManager = ChurchNotificationManager.shared
    @State private var preferences = NotificationPreferences()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Notifications", isOn: $preferences.notificationsEnabled)
                        .tint(Color(red: 0.2, green: 0.2, blue: 0.2))
                } header: {
                    Text("General")
                } footer: {
                    Text("Receive reminders and updates about your saved churches")
                }
                
                if preferences.notificationsEnabled {
                    Section("Time-Based Reminders") {
                        Toggle("1 Hour Before Service", isOn: $preferences.oneHourBefore)
                        Toggle("Morning of Service", isOn: $preferences.morningOfService)
                        Toggle("Saturday Evening Preview", isOn: $preferences.weekendPreview)
                    }
                    .tint(Color(red: 0.2, green: 0.2, blue: 0.2))
                    
                    Section("Location-Based") {
                        Toggle("Nearby Church Alerts", isOn: $preferences.nearbyAlerts)
                        Toggle("Arrival Notifications", isOn: $preferences.arrivalNotifications)
                        
                        if preferences.nearbyAlerts {
                            HStack {
                                Text("Alert Distance")
                                Spacer()
                                Picker("", selection: $preferences.nearbyRadius) {
                                    Text("0.5 mi").tag(804.67)
                                    Text("1 mi").tag(1609.34)
                                    Text("2 mi").tag(3218.69)
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                    .tint(Color(red: 0.2, green: 0.2, blue: 0.2))
                    
                    Section("Engagement") {
                        Toggle("Return Visitor Reminders", isOn: $preferences.returnVisitorReminders)
                        Toggle("New Church Suggestions", isOn: $preferences.newChurchSuggestions)
                        Toggle("Special Events", isOn: $preferences.specialEvents)
                    }
                    .tint(Color(red: 0.2, green: 0.2, blue: 0.2))
                    
                    Section("Quiet Hours") {
                        Toggle("Do Not Disturb", isOn: $preferences.quietHoursEnabled)
                        
                        if preferences.quietHoursEnabled {
                            DatePicker("Start Time", selection: $preferences.quietHoursStart, displayedComponents: .hourAndMinute)
                            DatePicker("End Time", selection: $preferences.quietHoursEnd, displayedComponents: .hourAndMinute)
                        }
                    }
                    .tint(Color(red: 0.2, green: 0.2, blue: 0.2))
                }
            }
            .navigationTitle("Notification Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        savePreferences()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func savePreferences() {
        UserDefaults.standard.set(try? JSONEncoder().encode(preferences), forKey: "notification_preferences")
    }
}

/// In-app notification banner
struct SmartNotificationBanner: View {
    let notification: InAppNotification
    @Binding var isPresented: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(notification.type.color.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: notification.type.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(notification.type.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                
                Text(notification.message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                    .lineLimit(2)
            }
            
            Spacer()
            
            if let action = notification.action {
                Button(action: {
                    action()
                    withAnimation {
                        isPresented = false
                    }
                }) {
                    Text(notification.actionTitle ?? "View")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(notification.type.color)
                }
            }
            
            Button {
                withAnimation {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color(red: 0.6, green: 0.6, blue: 0.6))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
        )
        .padding(.horizontal, 20)
    }
}

struct InAppNotification: Identifiable {
    let id = UUID()
    let type: NotificationDisplayType
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    
    enum NotificationDisplayType {
        case reminder
        case location
        case engagement
        case event
        
        var icon: String {
            switch self {
            case .reminder: return "bell.fill"
            case .location: return "location.fill"
            case .engagement: return "heart.fill"
            case .event: return "star.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .reminder: return .blue
            case .location: return .green
            case .engagement: return .orange
            case .event: return .purple
            }
        }
    }
}

// MARK: - Notification Preferences Model

struct NotificationPreferences: Codable {
    var notificationsEnabled: Bool = true
    
    // Time-based
    var oneHourBefore: Bool = true
    var morningOfService: Bool = true
    var weekendPreview: Bool = true
    
    // Location-based
    var nearbyAlerts: Bool = true
    var arrivalNotifications: Bool = true
    var nearbyRadius: Double = 1609.34 // 1 mile
    
    // Engagement
    var returnVisitorReminders: Bool = true
    var newChurchSuggestions: Bool = true
    var specialEvents: Bool = true
    
    // Quiet hours
    var quietHoursEnabled: Bool = false
    var quietHoursStart: Date = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    var quietHoursEnd: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
}

// MARK: - Smart Notification Ideas

/**
 ## 🔔 Smart Notification Implementation Guide
 
 ### 1. **Time-Based Notifications**
 
 #### Service Reminders (1 Hour Before)
 - Title: "Service Starting Soon"
 - Body: "[Church Name] service begins in 1 hour at [Time]"
 - Action: "Get Directions"
 - Trigger: 60 minutes before service time
 
 #### Morning of Service
 - Title: "Good Morning! 🙏"
 - Body: "[Church Name] service today at [Time]"
 - Action: "View Details"
 - Trigger: 8 AM on service day
 
 #### Saturday Evening Preview
 - Title: "This Week's Services"
 - Body: "You have [X] services saved for tomorrow"
 - Action: "Review Schedule"
 - Trigger: Saturday 6 PM
 
 #### Countdown Notifications
 - Title: "Service in 15 Minutes"
 - Body: "Time to head to [Church Name]"
 - Action: "Start Navigation"
 - Trigger: 15 minutes before service
 
 ### 2. **Location-Based Notifications**
 
 #### Nearby Church Alert
 - Title: "Church Nearby 📍"
 - Body: "[Church Name] is just [Distance] away"
 - Action: "View Church"
 - Trigger: Within 1 mile radius
 
 #### Arrival Notification
 - Title: "Welcome! 👋"
 - Body: "You've arrived at [Church Name]"
 - Action: "Check In"
 - Trigger: Arrival at church location
 
 #### Departure Follow-up
 - Title: "Thanks for Attending"
 - Body: "How was your experience at [Church Name]?"
 - Action: "Leave Feedback"
 - Trigger: 30 minutes after leaving church
 
 #### Route Notification
 - Title: "Traffic Alert 🚗"
 - Body: "Heavy traffic on your route. Leave 10 minutes early"
 - Action: "Start Navigation"
 - Trigger: Traffic API integration
 
 ### 3. **Engagement Notifications**
 
 #### Return Visitor Reminder
 - Title: "We Miss You 💙"
 - Body: "It's been 2 weeks since you visited [Church Name]"
 - Action: "View Next Service"
 - Trigger: 14 days after last visit
 
 #### New Church Suggestion
 - Title: "New Church Suggestion"
 - Body: "[Church Name] opened near you. [Denomination]"
 - Action: "Learn More"
 - Trigger: New church in area
 
 #### Denomination Match
 - Title: "Church You Might Like"
 - Body: "Based on your preferences: [Church Name]"
 - Action: "View Details"
 - Trigger: Smart algorithm
 
 #### Streak Notification
 - Title: "3 Weeks in a Row! 🔥"
 - Body: "You're building a great habit"
 - Action: "See Progress"
 - Trigger: Consistent attendance
 
 ### 4. **Community & Social Notifications**
 
 #### Friend Activity
 - Title: "Your Friends Are Going"
 - Body: "[Friend Name] attends [Church Name]"
 - Action: "Connect"
 - Trigger: Social graph analysis
 
 #### Group Invitation
 - Title: "Join Small Group"
 - Body: "[Church Name] has small groups near you"
 - Action: "Browse Groups"
 - Trigger: Church has groups
 
 #### Event Invitation
 - Title: "Community Event"
 - Body: "[Church Name] - [Event Name] this [Day]"
 - Action: "RSVP"
 - Trigger: Church event calendar
 
 ### 5. **Special Occasions**
 
 #### Holiday Services
 - Title: "Christmas Eve Service 🎄"
 - Body: "[Church Name] special service at [Time]"
 - Action: "Add to Calendar"
 - Trigger: Major holidays
 
 #### Easter Notifications
 - Title: "Easter Sunday Services 🐣"
 - Body: "Special services at [X] churches near you"
 - Action: "Browse Services"
 - Trigger: Easter week
 
 #### First-Time Visit Anniversary
 - Title: "1 Year Anniversary 🎉"
 - Body: "You first visited [Church Name] 1 year ago!"
 - Action: "Share Memory"
 - Trigger: Anniversary date
 
 ### 6. **Weather-Based Notifications**
 
 #### Weather Alert
 - Title: "Rainy Day ☔"
 - Body: "[Church Name] service still on. Bring an umbrella!"
 - Action: "View Service"
 - Trigger: Weather API + Service time
 
 #### Temperature Alert
 - Title: "Cold Morning ❄️"
 - Body: "Bundle up for service at [Church Name]"
 - Action: "Check Weather"
 - Trigger: Temperature < 32°F
 
 ### 7. **Personalized Insights**
 
 #### Attendance Insights
 - Title: "Your Church Journey 📊"
 - Body: "You've visited [X] churches this month"
 - Action: "View Stats"
 - Trigger: Weekly/Monthly summary
 
 #### Favorite Church
 - Title: "Your Top Church"
 - Body: "[Church Name] is your most visited church"
 - Action: "View History"
 - Trigger: Monthly analysis
 
 #### Discovery Notification
 - Title: "Explore New Denominations"
 - Body: "Try a [Denomination] service this week"
 - Action: "Browse"
 - Trigger: Monthly encouragement
 
 ### 8. **Smart Scheduling**
 
 #### Multi-Church Reminder
 - Title: "Multiple Services Today"
 - Body: "You have [X] services saved. Choose one?"
 - Action: "View Options"
 - Trigger: Conflicting times
 
 #### Service Time Change
 - Title: "Time Change Alert ⏰"
 - Body: "[Church Name] updated service time to [New Time]"
 - Action: "Update Calendar"
 - Trigger: Church updates info
 
 #### Cancelled Service
 - Title: "Service Cancelled"
 - Body: "[Church Name] cancelled service. Alternative options?"
 - Action: "Find Alternative"
 - Trigger: Church cancellation
 
 ### 9. **Contextual Notifications**
 
 #### Travel Mode
 - Title: "Churches in [City]"
 - Body: "Visiting [City]? [X] churches found"
 - Action: "Explore"
 - Trigger: Significant location change
 
 #### First Service of Month
 - Title: "New Month, New Opportunity"
 - Body: "Start fresh at [Church Name]"
 - Action: "Plan Visit"
 - Trigger: First day of month
 
 #### Sunday Morning
 - Title: "Good Sunday Morning! ☀️"
 - Body: "Your saved churches are ready for you"
 - Action: "View Services"
 - Trigger: Sunday 7 AM
 
 ### 10. **Interactive Notifications**
 
 #### Quick Actions
 - Swipe Actions: "Get Directions", "Call", "Save for Later"
 - Inline Buttons: "Yes", "No", "Remind Me Later"
 - Rich Media: Church photos, service times
 
 #### Live Activities (iOS 16+)
 - Service Countdown: Live countdown to service
 - Navigation: Turn-by-turn in Live Activity
 - Attendance: Check-in directly from notification
 
 ### Implementation Priority
 
 **High Priority (Must Have)**
 1. ✅ Service Reminders (1 hour before)
 2. ✅ Morning of Service
 3. ✅ Saturday Evening Preview
 4. ✅ Nearby Church Alerts
 5. ✅ Arrival Notifications
 
 **Medium Priority (Should Have)**
 6. Return Visitor Reminders
 7. Weather Alerts
 8. Holiday Services
 9. Traffic Alerts
 10. Friend Activity
 
 **Low Priority (Nice to Have)**
 11. Attendance Insights
 12. Streak Notifications
 13. Discovery Prompts
 14. Travel Mode
 15. Anniversary Notifications
 
 ### User Experience Guidelines
 
 1. **Frequency Limits**
    - Max 2 notifications per day
    - Max 7 notifications per week
    - Respect quiet hours (10 PM - 8 AM default)
 
 2. **Personalization**
    - Only send relevant notifications
    - Learn from user dismissals
    - Adapt to user behavior
 
 3. **Actionable**
    - Every notification should have a clear action
    - Quick actions from notification
    - Deep linking to relevant screens
 
 4. **Respectful**
    - Honor Do Not Disturb
    - Respect notification preferences
    - Easy to disable/customize
 
 5. **Timely**
    - Send at appropriate times
    - Account for time zones
    - Context-aware scheduling
 */

// MARK: - Advanced Notification Scheduler

extension ChurchNotificationManager {
    
    /// Schedule smart notification for a church with all types
    func scheduleAllSmartNotifications(for church: Church) {
        let preferences = loadPreferences()
        guard preferences.notificationsEnabled else { return }
        
        // Time-based
        if preferences.oneHourBefore {
            scheduleServiceReminder(for: church, beforeMinutes: 60)
        }
        
        if preferences.morningOfService {
            scheduleMorningReminder(for: church)
        }
        
        if preferences.weekendPreview {
            scheduleWeeklyReminder(for: church)
        }
        
        // Location-based
        if preferences.nearbyAlerts {
            scheduleLocationReminder(for: church, radius: preferences.nearbyRadius)
        }
        
        if preferences.arrivalNotifications {
            scheduleArrivalNotification(for: church)
        }
    }
    
    /// Schedule morning-of-service notification
    func scheduleMorningReminder(for church: Church) {
        let content = UNMutableNotificationContent()
        content.title = "Good Morning! 🙏"
        content.body = "\(church.name) service today at \(church.shortServiceTime)"
        content.sound = .default
        content.categoryIdentifier = "MORNING_REMINDER"
        
        // Parse service time and create trigger for 8 AM that day
        var dateComponents = DateComponents()
        dateComponents.hour = 8
        dateComponents.minute = 0
        dateComponents.weekday = getServiceWeekday(from: church.serviceTime)
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "morning_\(church.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule morning reminder: \(error)")
            } else {
                print("✅ Scheduled morning reminder for \(church.name)")
            }
        }
    }
    
    /// Schedule arrival notification (geofence)
    func scheduleArrivalNotification(for church: Church) {
        let content = UNMutableNotificationContent()
        content.title = "Welcome! 👋"
        content.body = "You've arrived at \(church.name)"
        content.sound = .default
        content.categoryIdentifier = "ARRIVAL"
        
        let center = CLLocationCoordinate2D(latitude: church.latitude, longitude: church.longitude)
        let region = CLCircularRegion(center: center, radius: 100, identifier: church.id.uuidString)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        
        let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
        let request = UNNotificationRequest(
            identifier: "arrival_\(church.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule arrival notification: \(error)")
            } else {
                print("✅ Scheduled arrival notification for \(church.name)")
            }
        }
    }
    
    private func getServiceWeekday(from serviceTime: String) -> Int {
        // Sunday = 1, Monday = 2, etc.
        // Parse "Sunday 10:00 AM" -> 1
        if serviceTime.localizedCaseInsensitiveContains("sunday") {
            return 1
        } else if serviceTime.localizedCaseInsensitiveContains("saturday") {
            return 7
        }
        return 1 // Default to Sunday
    }
    
    private func loadPreferences() -> NotificationPreferences {
        guard let data = UserDefaults.standard.data(forKey: "notification_preferences"),
              let preferences = try? JSONDecoder().decode(NotificationPreferences.self, from: data) else {
            return NotificationPreferences()
        }
        return preferences
    }
}

#Preview("Notification Settings") {
    NotificationPreferencesView()
}

#Preview("Notification Banner") {
    SmartNotificationBanner(
        notification: InAppNotification(
            type: .reminder,
            title: "Service Starting Soon",
            message: "Grace Community Church service begins in 1 hour",
            actionTitle: "Get Directions"
        ),
        isPresented: .constant(true)
    )
    .padding()
}
