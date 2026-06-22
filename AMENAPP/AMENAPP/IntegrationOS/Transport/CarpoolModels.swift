// CarpoolModels.swift — AMEN IntegrationOS

import Foundation
import CoreLocation

struct CarpoolRequest: Codable, Identifiable {
    var id: String = UUID().uuidString
    let requesterId: String
    let churchId: String
    let departureCoordinate: GeoPoint
    let departureTime: Date
    let seats: Int
    let notes: String?
    let status: CarpoolStatus
    let createdAt: Date
}

struct CarpoolMatch: Codable, Identifiable {
    var id: String = UUID().uuidString
    let request: CarpoolRequest
    let driverId: String
    let driverName: String
    let estimatedPickupTime: Date
    let confirmedAt: Date?
}

enum CarpoolStatus: String, Codable {
    case open, matched, confirmed, completed, cancelled
}

struct GeoPoint: Codable {
    let latitude: Double
    let longitude: Double

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum TransportProvider: String, CaseIterable {
    case uber = "uber"
    case lyft = "lyft"
    case appleMaps = "apple_maps"

    var deepLinkScheme: String {
        switch self {
        case .uber: return "uber://"
        case .lyft: return "lyft://"
        case .appleMaps: return "maps://"
        }
    }

    var appStoreURL: URL {
        switch self {
        case .uber: return URL(string: "https://apps.apple.com/app/uber/id368677368")!
        case .lyft: return URL(string: "https://apps.apple.com/app/lyft/id529379082")!
        case .appleMaps: return URL(string: "https://maps.apple.com")!
        }
    }

    var displayName: String { rawValue.capitalized }
}
