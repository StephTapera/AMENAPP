//
//  FirstVisitCompanionViewModel.swift
//  AMENAPP
//
//  Created by Claude on 2026-02-24.
//  First Visit Companion - View Model
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation
import Combine

@MainActor
class FirstVisitCompanionViewModel: ObservableObject {
    // Services
    private let visitPlanService = VisitPlanService()
    private let calendarService = CalendarIntegrationService()
    private let notificationScheduler = ChurchVisitNotificationScheduler()
    
    // State
    @Published var selectedChurch: VisitCompanionChurch?
    @Published var selectedService: VisitCompanionChurchService?
    @Published var selectedDate: Date = Date()
    @Published var visitPlan: VisitPlan?
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSuccess = false
    
    // Calendar and notifications
    @Published var addToCalendar = true
    @Published var enable24HourReminder = true
    @Published var enableDayOfReminder = true
    @Published var enablePostVisitReminder = true
    
    // MARK: - Create Visit Plan
    
    func createVisitPlan() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Please sign in to create a visit plan"
            return
        }
        
        guard let church = selectedChurch,
              let service = selectedService else {
            errorMessage = "Please select a church and service"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Calculate service date/time
            let serviceDateTime = calculateServiceDateTime(
                date: selectedDate,
                serviceTime: service.startTime
            )
            
            // Create visit plan (idempotent)
            var plan = try await visitPlanService.createVisitPlan(
                userId: userId,
                church: church,
                service: service,
                serviceDate: serviceDateTime
            )
            
            // Add to calendar if requested
            if addToCalendar {
                do {
                    let eventId = try await calendarService.addChurchVisitToCalendar(
                        church: church,
                        service: service,
                        serviceDate: serviceDateTime
                    )
                    
                    // Update visit plan with calendar info
                    if let planId = plan.id {
                        try await visitPlanService.updateCalendarSync(
                            visitPlanId: planId,
                            calendarEventId: eventId
                        )
                    }
                } catch {
                    Logger.error("Failed to add to calendar: \(error.localizedDescription)")
                    // Continue even if calendar fails
                }
            }
            
            // Schedule notifications
            if let planId = plan.id {
                // 24-hour reminder
                if enable24HourReminder {
                    do {
                        let notificationId = try await notificationScheduler.schedule24HourReminder(
                            church: church,
                            service: service,
                            serviceDate: serviceDateTime,
                            visitPlanId: planId
                        )
                        
                        try await visitPlanService.updateReminderScheduled(
                            visitPlanId: planId,
                            notificationId: notificationId
                        )
                    } catch NotificationSchedulerError.reminderDateInPast {
                        Logger.debug("24h reminder skipped (date in past)")
                    } catch {
                        Logger.error("Failed to schedule 24h reminder: \(error.localizedDescription)")
                    }
                }
                
                // Day-of reminder
                if enableDayOfReminder {
                    do {
                        let notificationId = try await notificationScheduler.scheduleDayOfReminder(
                            church: church,
                            service: service,
                            serviceDate: serviceDateTime,
                            visitPlanId: planId
                        )
                        
                        try await visitPlanService.updateDayOfReminderScheduled(
                            visitPlanId: planId,
                            notificationId: notificationId
                        )
                    } catch NotificationSchedulerError.reminderDateInPast {
                        Logger.debug("Day-of reminder skipped (date in past)")
                    } catch {
                        Logger.error("Failed to schedule day-of reminder: \(error.localizedDescription)")
                    }
                }
                
                // Post-visit note reminder
                if enablePostVisitReminder {
                    do {
                        _ = try await notificationScheduler.schedulePostVisitNoteReminder(
                            church: church,
                            service: service,
                            serviceDate: serviceDateTime,
                            visitPlanId: planId
                        )
                    } catch NotificationSchedulerError.reminderDateInPast {
                        Logger.debug("Post-visit reminder skipped (date in past)")
                    } catch {
                        Logger.error("Failed to schedule post-visit reminder: \(error.localizedDescription)")
                    }
                }
                
                // Fetch updated plan
                plan = try await visitPlanService.getVisitPlan(
                    userId: userId,
                    churchId: church.id ?? "",
                    serviceDate: serviceDateTime
                ) ?? plan
            }
            
            visitPlan = plan
            showSuccess = true
            isLoading = false
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    // MARK: - Cancel Visit Plan
    
    func cancelVisitPlan() async {
        guard let planId = visitPlan?.id else { return }
        
        isLoading = true
        
        do {
            // Cancel notifications
            await notificationScheduler.cancelAllReminders(visitPlanId: planId)
            
            // Remove from calendar if synced
            if let eventId = visitPlan?.calendarEventId {
                try await calendarService.removeCalendarEvent(eventId: eventId)
            }
            
            // Cancel in Firestore
            try await visitPlanService.cancelVisitPlan(visitPlanId: planId)
            
            visitPlan = nil
            isLoading = false
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    // MARK: - Load Existing Visit Plan
    
    func loadExistingVisitPlan(church: VisitCompanionChurch, serviceDate: Date) async {
        guard let userId = Auth.auth().currentUser?.uid,
              let churchId = church.id else { return }
        
        do {
            visitPlan = try await visitPlanService.getVisitPlan(
                userId: userId,
                churchId: churchId,
                serviceDate: serviceDate
            )
        } catch {
            Logger.error("Failed to load visit plan: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateServiceDateTime(date: Date, serviceTime: String) -> Date {
        // serviceTime format: "10:00 AM", "2:30 PM", etc.
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        guard let time = formatter.date(from: serviceTime) else {
            // Fallback: use 10:00 AM if parsing fails
            return Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: date) ?? date
        }
        
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        
        return calendar.date(
            bySettingHour: timeComponents.hour ?? 10,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: date
        ) ?? date
    }
    
    /// Validates that selected date is in the future
    func isValidVisitDate() -> Bool {
        let serviceDateTime = calculateServiceDateTime(
            date: selectedDate,
            serviceTime: selectedService?.startTime ?? "10:00 AM"
        )
        return serviceDateTime > Date()
    }
    
    /// Formats service date for display
    func formattedServiceDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: selectedDate)
    }
}
