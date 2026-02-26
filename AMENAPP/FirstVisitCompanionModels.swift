//
//  FirstVisitCompanionModels.swift
//  AMENAPP
//
//  Created by Claude on 2026-02-24.
//  First Visit Companion - All Models Consolidated
//

import Foundation
import FirebaseFirestore
import CoreLocation

// MARK: - Church Models

struct VisitCompanionChurch: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    let name: String
    let denomination: String?
    let address: VisitCompanionChurchAddress
    let phoneNumber: String?
    let website: String?
    let description: String?
    
    // What to expect info
    let dressCode: String?
    let parkingInfo: String?
    let accessibilityInfo: String?
    let childcareAvailable: Bool
    let welcomeTeamContact: String?
    
    // Services
    let services: [VisitCompanionChurchService]
    
    // Metadata
    let createdAt: Timestamp
    let updatedAt: Timestamp
    let verified: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case denomination
        case address
        case phoneNumber = "phone_number"
        case website
        case description
        case dressCode = "dress_code"
        case parkingInfo = "parking_info"
        case accessibilityInfo = "accessibility_info"
        case childcareAvailable = "childcare_available"
        case welcomeTeamContact = "welcome_team_contact"
        case services
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case verified
    }
}

struct VisitCompanionChurchAddress: Codable, Hashable {
    let street: String
    let city: String
    let state: String
    let zipCode: String
    let country: String
    let coordinates: GeoPoint?
    
    var fullAddress: String {
        "\(street), \(city), \(state) \(zipCode)"
    }
    
    enum CodingKeys: String, CodingKey {
        case street
        case city
        case state
        case zipCode = "zip_code"
        case country
        case coordinates
    }
}

struct VisitCompanionChurchService: Codable, Hashable, Identifiable {
    var id: String {
        "\(dayOfWeek)_\(startTime)"
    }
    
    let dayOfWeek: String
    let startTime: String
    let duration: Int
    let serviceType: String
    let language: String?
    let streamingAvailable: Bool
    
    enum CodingKeys: String, CodingKey {
        case dayOfWeek = "day_of_week"
        case startTime = "start_time"
        case duration
        case serviceType = "service_type"
        case language
        case streamingAvailable = "streaming_available"
    }
}

// MARK: - Visit Plan Model

struct VisitPlan: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let churchId: String
    let churchName: String
    
    // Service details
    let serviceDate: Timestamp
    let serviceTime: String
    let serviceType: String
    
    // Calendar integration
    let calendarEventId: String?
    let calendarSynced: Bool
    
    // Notifications
    let reminderScheduled: Bool
    let reminderNotificationId: String?
    let dayOfReminderScheduled: Bool
    let dayOfReminderNotificationId: String?
    
    // Directions
    let churchAddress: String
    let churchCoordinates: GeoPoint?
    
    // Status tracking
    let status: VisitPlanStatus
    let visited: Bool
    let visitedAt: Timestamp?
    
    // Auto-note creation
    let autoNoteCreated: Bool
    let noteId: String?
    
    // Metadata
    let createdAt: Timestamp
    let updatedAt: Timestamp
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case churchId = "church_id"
        case churchName = "church_name"
        case serviceDate = "service_date"
        case serviceTime = "service_time"
        case serviceType = "service_type"
        case calendarEventId = "calendar_event_id"
        case calendarSynced = "calendar_synced"
        case reminderScheduled = "reminder_scheduled"
        case reminderNotificationId = "reminder_notification_id"
        case dayOfReminderScheduled = "day_of_reminder_scheduled"
        case dayOfReminderNotificationId = "day_of_reminder_notification_id"
        case churchAddress = "church_address"
        case churchCoordinates = "church_coordinates"
        case status
        case visited
        case visitedAt = "visited_at"
        case autoNoteCreated = "auto_note_created"
        case noteId = "note_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum VisitPlanStatus: String, Codable {
    case planned = "planned"
    case reminded = "reminded"
    case dayOf = "day_of"
    case visited = "visited"
    case expired = "expired"
    case cancelled = "cancelled"
}

// MARK: - Adapter Extension

extension VisitCompanionChurch {
    /// Creates a VisitCompanionChurch from the FindChurchView Church model
    init(from findChurchModel: Church) {
        let now = Timestamp()
        
        // Parse address components
        let addressComponents = findChurchModel.address.components(separatedBy: ", ")
        let street = addressComponents.first ?? findChurchModel.address
        let city = addressComponents.count > 1 ? addressComponents[1] : ""
        let stateZip = addressComponents.count > 2 ? addressComponents[2] : ""
        
        self.init(
            id: findChurchModel.id.uuidString,
            name: findChurchModel.name,
            denomination: findChurchModel.denomination.isEmpty ? nil : findChurchModel.denomination,
            address: VisitCompanionChurchAddress(
                street: street,
                city: city,
                state: stateZip.components(separatedBy: " ").first ?? "",
                zipCode: stateZip.components(separatedBy: " ").last ?? "",
                country: "USA",
                coordinates: GeoPoint(
                    latitude: findChurchModel.latitude,
                    longitude: findChurchModel.longitude
                )
            ),
            phoneNumber: findChurchModel.phone.isEmpty ? nil : findChurchModel.phone,
            website: findChurchModel.website,
            description: nil,
            dressCode: "Come as you are",
            parkingInfo: "Parking available on-site",
            accessibilityInfo: "Wheelchair accessible",
            childcareAvailable: true,
            welcomeTeamContact: nil,
            services: [
                VisitCompanionChurchService(
                    dayOfWeek: "Sunday",
                    startTime: findChurchModel.serviceTime,
                    duration: 90,
                    serviceType: "Main Service",
                    language: "English",
                    streamingAvailable: false
                )
            ],
            createdAt: now,
            updatedAt: now,
            verified: false
        )
    }
}
