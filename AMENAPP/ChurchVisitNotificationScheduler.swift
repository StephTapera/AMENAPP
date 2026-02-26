//
//  ChurchVisitNotificationScheduler.swift
//  AMENAPP
//
//  Created by Claude on 2026-02-24.
//  First Visit Companion - Notification Scheduling
//

import Foundation
import UserNotifications
import FirebaseFirestore
import Combine

@MainActor
class ChurchVisitNotificationScheduler: ObservableObject {
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Authorization
    
    /// Requests notification permission
    func requestNotificationPermission() async throws -> Bool {
        let settings = await notificationCenter.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
            
        case .notDetermined:
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted
            
        case .denied, .ephemeral:
            return false
            
        @unknown default:
            return false
        }
    }
    
    // MARK: - Schedule Church Visit Reminders
    
    /// Schedules 24-hour reminder for church visit (idempotent)
    func schedule24HourReminder(
        church: VisitCompanionChurch,
        service: VisitCompanionChurchService,
        serviceDate: Date,
        visitPlanId: String
    ) async throws -> String {
        // Unique notification ID (idempotent)
        let notificationId = "visit_24h_\(visitPlanId)"
        
        // Cancel any existing notification with this ID
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationId])
        
        // Calculate reminder time (24 hours before service)
        let reminderDate = serviceDate.addingTimeInterval(-86400) // -24 hours
        
        // Don't schedule if in the past
        guard reminderDate > Date() else {
            Logger.debug("Reminder date is in the past, skipping: \(reminderDate)")
            throw NotificationSchedulerError.reminderDateInPast
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Church Visit Tomorrow"
        content.body = "Your visit to \(church.name) is tomorrow at \(service.startTime). Tap for details."
        content.sound = .default
        content.badge = 0
        content.categoryIdentifier = "CHURCH_VISIT_REMINDER"
        
        // Add user info for deep linking
        content.userInfo = [
            "type": "church_visit_reminder",
            "visit_plan_id": visitPlanId,
            "church_id": church.id ?? "",
            "church_name": church.name,
            "service_time": service.startTime,
            "church_address": church.address.fullAddress
        ]
        
        // Add what to expect info
        var subtitleParts: [String] = []
        if let dressCode = church.dressCode {
            subtitleParts.append("Dress: \(dressCode)")
        }
        if let parking = church.parkingInfo {
            subtitleParts.append("Parking: \(parking)")
        }
        if !subtitleParts.isEmpty {
            content.subtitle = subtitleParts.joined(separator: " • ")
        }
        
        // Create trigger
        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        try await notificationCenter.add(request)
        
        Logger.debug("Scheduled 24h reminder: \(notificationId) for \(reminderDate)")
        return notificationId
    }
    
    /// Schedules day-of reminder (1 hour before service) - idempotent
    func scheduleDayOfReminder(
        church: VisitCompanionChurch,
        service: VisitCompanionChurchService,
        serviceDate: Date,
        visitPlanId: String
    ) async throws -> String {
        // Unique notification ID (idempotent)
        let notificationId = "visit_dayof_\(visitPlanId)"
        
        // Cancel any existing notification with this ID
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationId])
        
        // Calculate reminder time (1 hour before service)
        let reminderDate = serviceDate.addingTimeInterval(-3600) // -1 hour
        
        // Don't schedule if in the past
        guard reminderDate > Date() else {
            Logger.debug("Day-of reminder date is in the past, skipping: \(reminderDate)")
            throw NotificationSchedulerError.reminderDateInPast
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Church Visit in 1 Hour"
        content.body = "\(church.name) service starts at \(service.startTime). Time to get ready!"
        content.sound = .default
        content.badge = 0
        content.categoryIdentifier = "CHURCH_VISIT_DAY_OF"
        
        // Add directions action
        content.userInfo = [
            "type": "church_visit_day_of",
            "visit_plan_id": visitPlanId,
            "church_id": church.id ?? "",
            "church_name": church.name,
            "church_address": church.address.fullAddress,
            "latitude": church.address.coordinates?.latitude ?? 0,
            "longitude": church.address.coordinates?.longitude ?? 0
        ]
        
        // Add subtitle with address
        content.subtitle = church.address.fullAddress
        
        // Create trigger
        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        try await notificationCenter.add(request)
        
        Logger.debug("Scheduled day-of reminder: \(notificationId) for \(reminderDate)")
        return notificationId
    }
    
    /// Schedules post-visit note creation reminder (2 hours after service) - idempotent
    func schedulePostVisitNoteReminder(
        church: VisitCompanionChurch,
        service: VisitCompanionChurchService,
        serviceDate: Date,
        visitPlanId: String
    ) async throws -> String {
        // Unique notification ID (idempotent)
        let notificationId = "visit_postnote_\(visitPlanId)"
        
        // Cancel any existing notification with this ID
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationId])
        
        // Calculate reminder time (2 hours after service start + duration)
        let serviceEndDate = serviceDate.addingTimeInterval(TimeInterval(service.duration * 60))
        let reminderDate = serviceEndDate.addingTimeInterval(7200) // +2 hours after service ends
        
        // Don't schedule if in the past
        guard reminderDate > Date() else {
            Logger.debug("Post-visit reminder date is in the past, skipping: \(reminderDate)")
            throw NotificationSchedulerError.reminderDateInPast
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "How was your visit to \(church.name)?"
        content.body = "Take a moment to capture your thoughts and reflections from today's service."
        content.sound = .default
        content.badge = 0
        content.categoryIdentifier = "CHURCH_VISIT_POST_NOTE"
        
        // Add user info for deep linking to note creation
        content.userInfo = [
            "type": "church_visit_post_note",
            "visit_plan_id": visitPlanId,
            "church_id": church.id ?? "",
            "church_name": church.name,
            "service_date": serviceDate.timeIntervalSince1970,
            "auto_create_note": true
        ]
        
        // Create trigger
        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        try await notificationCenter.add(request)
        
        Logger.debug("Scheduled post-visit note reminder: \(notificationId) for \(reminderDate)")
        return notificationId
    }
    
    // MARK: - Cancel Reminders
    
    /// Cancels all reminders for a visit plan (idempotent)
    func cancelAllReminders(visitPlanId: String) async {
        let identifiers = [
            "visit_24h_\(visitPlanId)",
            "visit_dayof_\(visitPlanId)",
            "visit_postnote_\(visitPlanId)"
        ]
        
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        Logger.debug("Cancelled all reminders for visit plan: \(visitPlanId)")
    }
    
    /// Cancels specific reminder (idempotent)
    func cancelReminder(notificationId: String) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationId])
        Logger.debug("Cancelled reminder: \(notificationId)")
    }
    
    // MARK: - Notification Actions Setup
    
    /// Registers notification categories and actions
    func registerNotificationCategories() {
        // Church visit reminder actions (24h before)
        let viewDetailsAction = UNNotificationAction(
            identifier: "VIEW_VISIT_DETAILS",
            title: "View Details",
            options: [.foreground]
        )
        let addToCalendarAction = UNNotificationAction(
            identifier: "ADD_TO_CALENDAR",
            title: "Add to Calendar",
            options: []
        )
        let reminderCategory = UNNotificationCategory(
            identifier: "CHURCH_VISIT_REMINDER",
            actions: [viewDetailsAction, addToCalendarAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Day-of reminder actions (1h before)
        let getDirectionsAction = UNNotificationAction(
            identifier: "GET_DIRECTIONS",
            title: "Get Directions",
            options: [.foreground]
        )
        let dayOfCategory = UNNotificationCategory(
            identifier: "CHURCH_VISIT_DAY_OF",
            actions: [getDirectionsAction, viewDetailsAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Post-visit note reminder actions
        let createNoteAction = UNNotificationAction(
            identifier: "CREATE_NOTE",
            title: "Create Note",
            options: [.foreground]
        )
        let remindLaterAction = UNNotificationAction(
            identifier: "REMIND_LATER",
            title: "Remind Me Later",
            options: []
        )
        let postNoteCategory = UNNotificationCategory(
            identifier: "CHURCH_VISIT_POST_NOTE",
            actions: [createNoteAction, remindLaterAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register all categories
        notificationCenter.setNotificationCategories([
            reminderCategory,
            dayOfCategory,
            postNoteCategory
        ])
        
        Logger.debug("Registered church visit notification categories")
    }
    
    // MARK: - Static Setup (for AppDelegate)
    
    /// Static method to setup notification categories during app initialization
    /// Called from AppDelegate.setupPushNotifications()
    static func setupVisitPlanNotificationCategories() {
        let notificationCenter = UNUserNotificationCenter.current()
        
        // Church visit reminder actions (24h before)
        let viewDetailsAction = UNNotificationAction(
            identifier: "VIEW_VISIT_DETAILS",
            title: "View Details",
            options: [.foreground]
        )
        let addToCalendarAction = UNNotificationAction(
            identifier: "ADD_TO_CALENDAR",
            title: "Add to Calendar",
            options: []
        )
        let reminderCategory = UNNotificationCategory(
            identifier: "CHURCH_VISIT_REMINDER",
            actions: [viewDetailsAction, addToCalendarAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Day-of reminder actions (1h before)
        let getDirectionsAction = UNNotificationAction(
            identifier: "GET_DIRECTIONS",
            title: "Get Directions",
            options: [.foreground]
        )
        let dayOfCategory = UNNotificationCategory(
            identifier: "CHURCH_VISIT_DAY_OF",
            actions: [getDirectionsAction, viewDetailsAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Post-visit note reminder actions
        let createNoteAction = UNNotificationAction(
            identifier: "CREATE_NOTE",
            title: "Create Note",
            options: [.foreground]
        )
        let remindLaterAction = UNNotificationAction(
            identifier: "REMIND_LATER",
            title: "Remind Me Later",
            options: []
        )
        let postNoteCategory = UNNotificationCategory(
            identifier: "CHURCH_VISIT_POST_NOTE",
            actions: [createNoteAction, remindLaterAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register all categories
        notificationCenter.setNotificationCategories([
            reminderCategory,
            dayOfCategory,
            postNoteCategory
        ])
        
        Logger.debug("Registered church visit notification categories (static)")
    }
}

// MARK: - Errors

enum NotificationSchedulerError: LocalizedError {
    case reminderDateInPast
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .reminderDateInPast:
            return "Reminder date is in the past"
        case .permissionDenied:
            return "Notification permission denied"
        }
    }
}
