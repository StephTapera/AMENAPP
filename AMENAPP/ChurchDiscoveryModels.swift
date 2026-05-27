import Foundation
import CoreLocation

struct ChurchSearchIntent: Codable, Equatable {
    var denominationPreferences: [String]
    var traditionPreferences: [String]
    var worshipStyle: [String]
    var teachingStyle: [String]
    var communityNeeds: [String]
    var lifeStage: [String]
    var servicePreferences: [String]
    var groupNeeds: [String]
    var accessibilityNeeds: [String]
    var languagePreferences: [String]
    var distancePreference: String
    var mustHave: [String]
    var niceToHave: [String]
    var avoid: [String]
    var confidence: Double
    var needsClarification: Bool
    var clarifyingQuestion: String?
}

struct ChurchDiscoveryRequest: Codable, Equatable {
    var rawQuery: String
    var approximateLocation: ChurchDiscoveryLocation?
    var filters: [String: String] = [:]
}

struct ChurchDiscoveryLocation: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var label: String?

    init(latitude: Double, longitude: Double, label: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
    }

    init(coordinate: CLLocationCoordinate2D, label: String? = nil) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.label = label
    }
}

struct ChurchDiscoveryResponse: Codable {
    var searchId: String?
    var intent: ChurchSearchIntent
    var results: [ChurchDiscoveryResult]
}

struct ChurchDiscoveryResult: Codable, Identifiable, Equatable {
    var id: String
    var churchId: String?
    var googlePlaceId: String?
    var name: String
    var denomination: String?
    var address: String
    var latitude: Double?
    var longitude: Double?
    var distanceMiles: Double?
    var website: String?
    var phone: String?
    var googleMapsUri: String?
    var verifiedByAmen: Bool
    var matchScore: ChurchMatchScore
    var explanation: ChurchMatchExplanation
    var summary: ChurchDiscoverySummary
    var nextBestAction: String

    var asChurch: Church? {
        guard let latitude, let longitude else { return nil }
        return Church(
            canonicalChurchId: churchId ?? googlePlaceId ?? id,
            name: name,
            denomination: denomination ?? "Christian Church",
            address: address,
            distance: distanceMiles.map { String(format: "%.1f mi", $0) } ?? "Distance unavailable",
            distanceValue: distanceMiles ?? 0,
            serviceTime: "Service times not verified yet",
            phone: phone ?? "No phone available",
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            website: website
        )
    }
}

struct ChurchMatchScore: Codable, Equatable {
    var overall: Double
    var confidence: Double
    var categories: ChurchMatchScoreCategories
}

struct ChurchMatchScoreCategories: Codable, Equatable {
    var intentMatch: Double
    var communityFit: Double
    var distanceTravelFit: Double
    var ministryGroupFit: Double
    var verifiedAmenData: Double
    var freshnessCompleteness: Double
    var accessibilityLanguageFit: Double
}

struct ChurchMatchExplanation: Codable, Equatable {
    var whyThisMayFit: [String]
    var possibleMismatch: [String]
    var verifiedFacts: [String]
    var missingInfo: [String]
    var sources: [String]
}

struct ChurchDiscoverySummary: Codable, Equatable {
    var thisMayFitBecause: String
    var checkThisFirst: String
    var bestNextStep: String
}

struct ChurchDiscoveryFilter: Codable, Equatable {
    var distanceMiles: Double?
    var denomination: String?
    var worshipStyle: String?
    var teachingStyle: String?
    var groupNeed: String?
    var accessibilityNeed: String?
    var language: String?
    var serviceTime: String?
}

struct ChurchSavedPreference: Codable, Equatable {
    var preferredDenominations: [String]
    var communityNeeds: [String]
    var worshipStyles: [String]
    var maxDistanceMiles: Double
}

enum ChurchCommunityNeed: String, Codable, CaseIterable, Identifiable {
    case youngAdults = "Young adults"
    case families = "Families"
    case bibleTeaching = "Bible teaching"
    case smallGroups = "Small groups"
    case worshipNight = "Worship night"
    case recovery = "Recovery"
    case newBelievers = "New believers"
    case traditional = "Traditional"
    case contemporary = "Contemporary"
    case onlineOptions = "Online options"

    var id: String { rawValue }
}
