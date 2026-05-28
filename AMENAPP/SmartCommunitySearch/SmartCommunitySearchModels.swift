import Foundation
import CoreLocation

// MARK: - Enums

enum SmartCommunityResultType: String, Codable, CaseIterable {
    case church, space, group, event, discussion, creator, mentor
}

enum SmartSearchSurface: String, Codable {
    case findChurch = "find_church"
    case spaces, discovery
    case globalSearch = "global_search"
}

enum SmartSearchActionType: String, Codable {
    case view, save, directions, rsvp, message, join, askBerean, refineSearch
}

// MARK: - Request / Response Models

struct SmartCommunitySearchRequest: Encodable {
    let queryText: String
    let location: SmartSearchLocation?
    let manualLocationText: String?
    let filters: [String: String]?
    let context: SmartSearchContext?
}

struct SmartSearchLocation: Codable {
    let lat: Double
    let lng: Double
    let accuracyMeters: Double?
}

struct SmartSearchContext: Codable {
    let surface: SmartSearchSurface
    let previousSearchId: String?
}

// MARK: - Intent

struct SmartCommunitySearchIntent: Codable {
    let rawQuery: String
    let communityType: String
    let denominations: [String]
    let worshipStyle: [String]
    let ageGroups: [String]
    let languages: [String]
    let accessibilityNeeds: [String]
    let childcareNeeded: Bool
    let distancePreferenceMiles: Double?
    let schedulePreference: String?
    let vibe: [String]
    let spiritualNeed: [String]
    let safetySensitivity: String
    let searchExpansionTerms: [String]
    let confidence: Double
    let needsClarification: Bool
    let clarifyingQuestion: String?
}

// MARK: - Actions

struct SmartCommunityAction: Codable, Identifiable, Equatable {
    let type: SmartSearchActionType
    let label: String
    let payload: [String: String]?

    var id: String { type.rawValue }
}

// MARK: - Results

struct SmartCommunityRankedResult: Codable, Identifiable, Equatable {
    let id: String
    let source: String  // "amen" | "google_maps"
    let type: SmartCommunityResultType
    let title: String
    let subtitle: String?
    let distanceLabel: String?
    let tags: [String]
    let matchScore: Double
    let reasons: [String]
    let cautions: [String]?
    let actions: [SmartCommunityAction]
    let locationCoord: SmartSearchCoord?
    let imageUrl: String?
    let primaryUrl: String?

    var matchLabel: String {
        if matchScore > 0.75 { return "Strong match" }
        if matchScore > 0.5 { return "Possible match" }
        return "Worth exploring"
    }

    var primaryAction: SmartCommunityAction? {
        actions.first
    }

    func action(ofType type: SmartSearchActionType) -> SmartCommunityAction? {
        actions.first { $0.type == type }
    }
}

struct SmartSearchCoord: Codable, Equatable {
    let lat: Double
    let lng: Double

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Full Response

struct SmartCommunitySearchResponse: Decodable {
    let searchId: String
    let interpretedIntent: SmartCommunitySearchIntent
    let results: [SmartCommunityRankedResult]
    let refinementSuggestions: [String]
    let safetyNotice: String?
    let usedExternalPlaces: Bool
    let usedAI: Bool
}

// MARK: - Location State

enum SmartSearchLocationState: Equatable {
    case notDetermined
    case denied
    case available(CLLocationCoordinate2D)
    case manual(String)  // ZIP or city name

    static func == (lhs: SmartSearchLocationState, rhs: SmartSearchLocationState) -> Bool {
        switch (lhs, rhs) {
        case (.notDetermined, .notDetermined): return true
        case (.denied, .denied): return true
        case (.available(let a), .available(let b)): return a.latitude == b.latitude && a.longitude == b.longitude
        case (.manual(let a), .manual(let b)): return a == b
        default: return false
        }
    }

    var searchLocation: SmartSearchLocation? {
        switch self {
        case .available(let coord):
            return SmartSearchLocation(lat: coord.latitude, lng: coord.longitude, accuracyMeters: 1000)
        default:
            return nil
        }
    }

    var manualLocationText: String? {
        switch self {
        case .manual(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default:
            return nil
        }
    }
}

// MARK: - UI State Machine

enum SmartSearchUIState: Equatable {
    case idle
    case loading
    case results([SmartCommunityRankedResult])
    case empty(query: String)
    case error(String)
    case crisis  // Safety state for crisis detection

    static func == (lhs: SmartSearchUIState, rhs: SmartSearchUIState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.crisis, .crisis):
            return true
        case (.results(let lhsResults), .results(let rhsResults)):
            return lhsResults.map(\.id) == rhsResults.map(\.id)
        case (.empty(let lhsQuery), .empty(let rhsQuery)):
            return lhsQuery == rhsQuery
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }

    var hasResults: Bool {
        if case .results = self { return true }
        return false
    }
}
