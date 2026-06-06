// AmenEventModels.swift — AMEN IntegrationOS

import Foundation

struct AmenIntegrationEvent: Codable, Identifiable {
    var id: String = UUID().uuidString
    let title: String
    let description: String?
    let hostId: String
    let hostName: String
    let spaceId: String?
    let location: EventLocation?
    let startDate: Date
    let endDate: Date
    let coverImageURL: String?
    let tags: [String]
    let maxAttendees: Int?
    let isPublic: Bool
    let sourceProvider: String
    let createdAt: Date
}

struct EventLocation: Codable {
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?
    let isVirtual: Bool
    let virtualURL: String?
}

struct EventRSVP: Codable, Identifiable {
    var id: String = UUID().uuidString
    let eventId: String
    let userId: String
    let status: EventRSVPStatus
    let respondedAt: Date
    let notes: String?
}

enum EventRSVPStatus: String, Codable, CaseIterable {
    case going, interested, notGoing, waitlist
}

struct EventAttendee: Codable, Identifiable {
    var id: String = UUID().uuidString
    let userId: String
    let displayName: String
    let avatarURL: String?
    let rsvpStatus: EventRSVPStatus
}
