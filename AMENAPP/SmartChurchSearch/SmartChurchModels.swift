import Foundation
import FirebaseFirestore

struct SmartChurch: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var address: String
    var city: String
    var state: String
    var zip: String
    var location: SmartChurchLocation
    var geoPoint: GeoPoint?
    var denomination: String
    var denominationFamily: String
    var worshipStyles: [SmartChurchWorshipStyle]
    var ministries: [SmartChurchMinistry]
    var size: SmartChurchSize
    var serviceTimes: [SmartChurchServiceTime]
    var languages: [String]
    var statementOfFaith: String
    var doctrinalTags: [SmartChurchDoctrinalTag]
    var description: String
    var website: String?
    var phone: String?
    var email: String?
    var photos: [String]
    var googlePlaceId: String?
    var source: SmartChurchSource
    var claimed: Bool
    var claimedByUid: String?
    var embeddingVersion: Int
    var createdAt: Timestamp
    var updatedAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case city
        case state
        case zip
        case location
        case geoPoint
        case denomination
        case denominationFamily
        case worshipStyles
        case ministries
        case size
        case serviceTimes
        case languages
        case statementOfFaith
        case doctrinalTags
        case description
        case website
        case phone
        case email
        case photos
        case googlePlaceId
        case source
        case claimed
        case claimedByUid
        case embeddingVersion
        case createdAt
        case updatedAt
    }
}

struct SmartChurchLocation: Codable, Hashable {
    var lat: Double
    var lng: Double

    enum CodingKeys: String, CodingKey {
        case lat
        case lng
    }
}

struct SmartChurchServiceTime: Codable, Hashable, Identifiable {
    var day: String
    var time: String
    var language: String
    var type: String

    var id: String {
        [day, time, language, type].joined(separator: "|")
    }

    enum CodingKeys: String, CodingKey {
        case day
        case time
        case language
        case type
    }
}

enum SmartChurchWorshipStyle: String, Codable, CaseIterable, Hashable, Identifiable {
    case contemporary
    case traditional
    case blended
    case liturgical
    case charismatic

    var id: String { rawValue }
}

enum SmartChurchMinistry: String, Codable, CaseIterable, Hashable, Identifiable {
    case youth
    case youngAdults = "young_adults"
    case kids
    case men
    case women
    case recovery
    case missions
    case college
    case seniors
    case marriage

    var id: String { rawValue }
}

enum SmartChurchSize: String, Codable, CaseIterable, Hashable, Identifiable {
    case small
    case medium
    case large
    case mega

    var id: String { rawValue }
}

enum SmartChurchSource: String, Codable, CaseIterable, Hashable, Identifiable {
    case googlePlaces = "google_places"
    case claimed
    case manual

    var id: String { rawValue }
}

enum SmartChurchDoctrinalTag: String, Codable, CaseIterable, Hashable, Identifiable {
    case trinitarian
    case niceneOrthodox = "nicene_orthodox"
    case biblicalInerrancy = "biblical_inerrancy"
    case evangelical
    case continuationist
    case cessationist
    case sacramental
    case credobaptism
    case paedobaptism
    case complementarian
    case egalitarian
    case missional
    case charismatic
    case reformed
    case wesleyan
    case baptist
    case catholic
    case orthodox
    case pentecostal
    case nonDenominational = "non_denominational"

    var id: String { rawValue }
}

struct SmartChurchSearchResult: Identifiable, Codable, Hashable {
    var church: SmartChurch
    var distanceMiles: Double
    var matchReason: String
    var score: Double

    var id: String { church.id }
}

struct SmartChurchSearchResponse: Codable, Hashable {
    var results: [SmartChurchSearchResult]
}
