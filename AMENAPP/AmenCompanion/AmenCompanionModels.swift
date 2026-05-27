import Foundation
import CoreLocation

// MARK: - Location Context

struct LocationContext: Equatable {
    var city: String
    var state: String
    var country: String
    var coordinate: CLLocationCoordinate2D
    var environment: EnvironmentType
    var isNewArea: Bool
    var broadAreaLabel: String

    static let unknown = LocationContext(
        city: "", state: "", country: "", coordinate: .init(), environment: .unknown, isNewArea: false, broadAreaLabel: ""
    )
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - Environment Type

enum EnvironmentType: String, Codable, CaseIterable {
    case airport        = "airport"
    case campus         = "campus"
    case conference     = "conference"
    case stadium        = "stadium"
    case hospital       = "hospital"
    case coworking      = "coworking"
    case international  = "international"
    case church         = "church"
    case home           = "home"
    case unknown        = "unknown"

    var displayName: String {
        switch self {
        case .airport:       return "Airport"
        case .campus:        return "Campus"
        case .conference:    return "Conference"
        case .stadium:       return "Stadium"
        case .hospital:      return "Hospital"
        case .coworking:     return "Workspace"
        case .international: return "Traveling Abroad"
        case .church:        return "Church"
        case .home:          return "Home Area"
        case .unknown:       return "Nearby"
        }
    }

    var systemImage: String {
        switch self {
        case .airport:       return "airplane.departure"
        case .campus:        return "graduationcap.fill"
        case .conference:    return "person.3.sequence.fill"
        case .stadium:       return "sportscourt.fill"
        case .hospital:      return "cross.circle.fill"
        case .coworking:     return "laptopcomputer"
        case .international: return "globe"
        case .church:        return "building.columns.fill"
        case .home:          return "house.fill"
        case .unknown:       return "location.fill"
        }
    }

    var surfaceAdaptation: EnvironmentSurfaceAdaptation {
        switch self {
        case .airport:       return EnvironmentSurfaceAdaptation(showLocalRecs: true, enableQuietMode: false, showNearbyEvents: false, showChurchDiscovery: true)
        case .campus:        return EnvironmentSurfaceAdaptation(showLocalRecs: true, enableQuietMode: false, showNearbyEvents: true, showChurchDiscovery: true)
        case .conference:    return EnvironmentSurfaceAdaptation(showLocalRecs: false, enableQuietMode: false, showNearbyEvents: true, showChurchDiscovery: false)
        case .stadium:       return EnvironmentSurfaceAdaptation(showLocalRecs: false, enableQuietMode: false, showNearbyEvents: true, showChurchDiscovery: false)
        case .hospital:      return EnvironmentSurfaceAdaptation(showLocalRecs: false, enableQuietMode: true, showNearbyEvents: false, showChurchDiscovery: false)
        case .coworking:     return EnvironmentSurfaceAdaptation(showLocalRecs: true, enableQuietMode: false, showNearbyEvents: false, showChurchDiscovery: false)
        case .international: return EnvironmentSurfaceAdaptation(showLocalRecs: true, enableQuietMode: false, showNearbyEvents: false, showChurchDiscovery: true)
        case .church:        return EnvironmentSurfaceAdaptation(showLocalRecs: false, enableQuietMode: false, showNearbyEvents: false, showChurchDiscovery: false)
        case .home:          return EnvironmentSurfaceAdaptation(showLocalRecs: false, enableQuietMode: false, showNearbyEvents: true, showChurchDiscovery: true)
        case .unknown:       return EnvironmentSurfaceAdaptation(showLocalRecs: false, enableQuietMode: false, showNearbyEvents: false, showChurchDiscovery: false)
        }
    }
}

struct EnvironmentSurfaceAdaptation {
    var showLocalRecs: Bool
    var enableQuietMode: Bool
    var showNearbyEvents: Bool
    var showChurchDiscovery: Bool
}

// MARK: - Companion Prompt

struct CompanionPrompt: Identifiable, Equatable {
    let id: String
    var type: CompanionPromptType
    var headline: String
    var detail: String
    var primaryAction: CompanionAction
    var secondaryAction: CompanionAction?
    var dismissible: Bool

    static func newAreaPrompt(city: String, state: String) -> CompanionPrompt {
        CompanionPrompt(
            id: "new_area_\(city)_\(state)",
            type: .newArea,
            headline: "You're near \(city)",
            detail: "Want help finding a church, Bible study, or faith community nearby?",
            primaryAction: CompanionAction(label: "Find a Church", destination: .churchDiscovery),
            secondaryAction: CompanionAction(label: "Maybe Later", destination: .dismiss),
            dismissible: true
        )
    }

    static func sundayReminderPrompt(churchName: String) -> CompanionPrompt {
        CompanionPrompt(
            id: "sunday_reminder",
            type: .sundayReminder,
            headline: "Sunday is coming up",
            detail: "\(churchName) has a service this Sunday. Want to plan your visit?",
            primaryAction: CompanionAction(label: "Plan Visit", destination: .visitPlanning),
            secondaryAction: CompanionAction(label: "Dismiss", destination: .dismiss),
            dismissible: true
        )
    }
}

enum CompanionPromptType: String, Codable {
    case newArea
    case sundayReminder
    case savedChurchUpdate
    case connectionNearby
    case visitReminder
    case postVisitReflection
}

struct CompanionAction: Equatable {
    var label: String
    var destination: CompanionDestination
}

enum CompanionDestination: Equatable {
    case churchDiscovery
    case visitPlanning
    case safeConnection
    case dismiss
    case externalURL(String)
}

// MARK: - Church Visit Plan

struct ChurchVisitPlan: Identifiable, Codable {
    let id: String
    var churchId: String
    var churchName: String
    var serviceTime: String
    var serviceDay: String
    var visitDate: Date?
    var directionsURL: String?
    var invitedFriendUIDs: [String]
    var prayerNote: String?
    var reminderEnabled: Bool
    var reflectionPrompted: Bool
    var createdAt: Date
    var updatedAt: Date

    var visitDateLabel: String {
        guard let date = visitDate else { return serviceDay }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}

// MARK: - Safe Connection

struct SafeConnection: Identifiable, Codable {
    let id: String
    var initiatorUID: String
    var receiverUID: String?
    var broadArea: String
    var intent: SafeConnectionIntent
    var state: SafeConnectionState
    var initiatorOptedIn: Bool
    var receiverOptedIn: Bool
    var createdAt: Date
    var expiresAt: Date

    var isMutuallyConsented: Bool {
        initiatorOptedIn && receiverOptedIn
    }
}

enum SafeConnectionIntent: String, Codable, CaseIterable {
    case prayer          = "prayer"
    case visitChurch     = "visit_church"
    case conversation    = "conversation"
    case bibleStudy      = "bible_study"

    var displayName: String {
        switch self {
        case .prayer:      return "Connect for Prayer"
        case .visitChurch: return "Visit Church Together"
        case .conversation: return "Start Conversation"
        case .bibleStudy:  return "Bible Study"
        }
    }

    var systemImage: String {
        switch self {
        case .prayer:      return "hands.sparkles"
        case .visitChurch: return "building.columns"
        case .conversation: return "bubble.left.and.bubble.right"
        case .bibleStudy:  return "book.circle"
        }
    }
}

enum SafeConnectionState: String, Codable {
    case pending    = "pending"
    case matched    = "matched"
    case active     = "active"
    case declined   = "declined"
    case expired    = "expired"
}

// MARK: - Companion Privacy Preferences

struct CompanionPrivacyPreferences: Codable {
    var locationSharingEnabled: Bool
    var newAreaDetectionEnabled: Bool
    var safeConnectionEnabled: Bool
    var churchDiscoveryEnabled: Bool
    var broadAreaOnly: Bool
    var notificationsEnabled: Bool

    static let `default` = CompanionPrivacyPreferences(
        locationSharingEnabled: true,
        newAreaDetectionEnabled: true,
        safeConnectionEnabled: false,
        churchDiscoveryEnabled: true,
        broadAreaOnly: true,
        notificationsEnabled: true
    )
}
