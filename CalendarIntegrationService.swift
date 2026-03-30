//
//  CalendarIntegrationService.swift
//  AMENAPP
//
//  Created by Claude on 2026-02-24.
//  First Visit Companion - Calendar Integration
//

import Foundation
import EventKit
import FirebaseFirestore
import Combine

@MainActor
class CalendarIntegrationService: ObservableObject {
    private let eventStore = EKEventStore()
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    
    init() {
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    private func checkAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }
    
    /// Requests calendar access permission
    func requestCalendarAccess() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        switch status {
        case .authorized, .fullAccess:
            authorizationStatus = status
            return true
            
        case .notDetermined, .restricted:
            let granted = try await eventStore.requestFullAccessToEvents()
            checkAuthorizationStatus()
            return granted
            
        case .denied, .writeOnly:
            authorizationStatus = status
            return false
            
        @unknown default:
            return false
        }
    }
    
    // MARK: - Add Church Visit to Calendar
    
    /// Adds church visit to user's calendar. Returns calendar event identifier.
    func addChurchVisitToCalendar(
        church: VisitCompanionChurch,
        service: VisitCompanionChurchService,
        serviceDate: Date
    ) async throws -> String {
        // Ensure we have permission
        let hasAccess = try await requestCalendarAccess()
        guard hasAccess else {
            throw CalendarError.permissionDenied
        }
        
        // Check if event already exists (idempotent)
        let existingEventId = try await findExistingChurchEvent(
            churchName: church.name,
            serviceDate: serviceDate,
            serviceTime: service.startTime
        )
        
        if let existingEventId = existingEventId {
            dlog("Calendar event already exists: \(existingEventId)")
            return existingEventId
        }
        
        // Create new event
        let event = EKEvent(eventStore: eventStore)
        event.title = "Church Visit: \(church.name)"
        event.location = church.address.fullAddress
        
        // Parse service time and duration
        let startDate = parseServiceDateTime(serviceDate: serviceDate, serviceTime: service.startTime)
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(TimeInterval(service.duration * 60))
        
        // Add notes with what to expect
        var notes = "Service Type: \(service.serviceType)\n"
        if let dressCode = church.dressCode {
            notes += "\nDress Code: \(dressCode)"
        }
        if let parking = church.parkingInfo {
            notes += "\nParking: \(parking)"
        }
        if let accessibility = church.accessibilityInfo {
            notes += "\nAccessibility: \(accessibility)"
        }
        if church.childcareAvailable {
            notes += "\nChildcare: Available"
        }
        if let website = church.website {
            notes += "\n\nWebsite: \(website)"
        }
        event.notes = notes
        
        // Set calendar (use default)
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        // Add alerts
        // 24 hours before
        let dayBeforeAlarm = EKAlarm(relativeOffset: -86400) // -24 hours
        event.addAlarm(dayBeforeAlarm)
        
        // 1 hour before
        let hourBeforeAlarm = EKAlarm(relativeOffset: -3600) // -1 hour
        event.addAlarm(hourBeforeAlarm)
        
        // Save event
        try eventStore.save(event, span: .thisEvent)
        
        guard let eventIdentifier = event.eventIdentifier else {
            throw CalendarError.eventCreationFailed
        }
        
        dlog("Created calendar event: \(eventIdentifier)")
        return eventIdentifier
    }
    
    // MARK: - Update Calendar Event
    
    /// Updates existing calendar event
    func updateCalendarEvent(
        eventId: String,
        church: VisitCompanionChurch,
        service: VisitCompanionChurchService,
        serviceDate: Date
    ) async throws {
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound
        }
        
        event.title = "Church Visit: \(church.name)"
        event.location = church.address.fullAddress
        
        let startDate = parseServiceDateTime(serviceDate: serviceDate, serviceTime: service.startTime)
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(TimeInterval(service.duration * 60))
        
        try eventStore.save(event, span: .thisEvent)
        dlog("Updated calendar event: \(eventId)")
    }
    
    // MARK: - Remove Calendar Event
    
    /// Removes calendar event (idempotent - no error if already removed)
    func removeCalendarEvent(eventId: String) async throws {
        guard let event = eventStore.event(withIdentifier: eventId) else {
            dlog("Calendar event not found (already removed): \(eventId)")
            return
        }
        
        try eventStore.remove(event, span: .thisEvent)
        dlog("Removed calendar event: \(eventId)")
    }
    
    // MARK: - Helper Methods
    
    /// Finds existing calendar event for church visit (idempotent check)
    private func findExistingChurchEvent(
        churchName: String,
        serviceDate: Date,
        serviceTime: String
    ) async throws -> String? {
        let startDate = parseServiceDateTime(serviceDate: serviceDate, serviceTime: serviceTime)
        
        // Search window: 1 hour before to 1 hour after
        let searchStart = startDate.addingTimeInterval(-3600)
        let searchEnd = startDate.addingTimeInterval(3600)
        
        let predicate = eventStore.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: nil
        )
        
        let events = eventStore.events(matching: predicate)
        
        // Look for matching church visit event
        for event in events {
            if event.title?.contains("Church Visit: \(churchName)") == true {
                return event.eventIdentifier
            }
        }
        
        return nil
    }
    
    /// Parses service date and time string into Date
    private func parseServiceDateTime(serviceDate: Date, serviceTime: String) -> Date {
        // serviceTime format: "10:00 AM", "2:30 PM", etc.
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        guard let time = formatter.date(from: serviceTime) else {
            // Fallback: use 10:00 AM if parsing fails
            return Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: serviceDate) ?? serviceDate
        }
        
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        
        return calendar.date(
            bySettingHour: timeComponents.hour ?? 10,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: serviceDate
        ) ?? serviceDate
    }
}

// MARK: - Errors

enum CalendarError: LocalizedError {
    case permissionDenied
    case eventCreationFailed
    case eventNotFound
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Calendar access permission denied. Please enable in Settings."
        case .eventCreationFailed:
            return "Failed to create calendar event."
        case .eventNotFound:
            return "Calendar event not found."
        }
    }
}
