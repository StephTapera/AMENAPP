import Foundation
import CoreLocation

// MARK: - Spatial Environment

struct SpatialEnvironment {
    var type: EnvironmentType
    var broadArea: String
    var isNew: Bool
    var detectedAt: Date
    var confidence: Double
    var suggestedAdaptations: EnvironmentSurfaceAdaptation

    static let unknown = SpatialEnvironment(
        type: .unknown, broadArea: "", isNew: false, detectedAt: Date(), confidence: 0,
        suggestedAdaptations: EnvironmentSurfaceAdaptation(showLocalRecs: false, enableQuietMode: false, showNearbyEvents: false, showChurchDiscovery: false)
    )
}

// MARK: - Nearby Gathering

struct NearbyGathering: Identifiable {
    let id: String
    var type: AmenGatheringType
    var broadLocation: String
    var participantCount: Int
    var isOpenToJoin: Bool
    var title: String
    var startsAt: Date?
    var isAnonymized: Bool

    var countLabel: String {
        participantCount == 1 ? "1 person" : "\(participantCount) people"
    }
}

// MARK: - Spatial Post Metadata

struct SpatialPostMetadata: Codable {
    var broadArea: String
    var environmentType: String
    var isLocationPost: Bool
    var eventContext: String?

    static let none = SpatialPostMetadata(broadArea: "", environmentType: "unknown", isLocationPost: false)
}

// MARK: - Ambient Signal

struct AmbientSignal: Identifiable {
    let id: String
    var type: AmbientSignalType
    var message: String
    var detail: String?
    var confidence: Double
    var priority: AmbientSignalPriority
    var action: AmbientSignalAction?
    var expiresAt: Date

    var isExpired: Bool { Date() > expiresAt }
}

enum AmbientSignalType: String, Codable {
    case nearbyGathering        = "nearby_gathering"
    case communityMoment        = "community_moment"
    case environmentShift       = "environment_shift"
    case connectionOpportunity  = "connection_opportunity"
    case eventStarting          = "event_starting"
    case serviceReminder        = "service_reminder"
}

enum AmbientSignalPriority: Int, Codable, Comparable {
    case low    = 0
    case medium = 1
    case high   = 2

    static func < (lhs: AmbientSignalPriority, rhs: AmbientSignalPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AmbientSignalAction {
    var label: String
    var deepLinkPath: String
}

// MARK: - Spatial Relationship Type (distinct from SpiritualOS RelationshipType which is faith-relationship focused)

enum SpatialRelationshipType: String, Codable, CaseIterable {
    case collaborator       = "collaborator"
    case mentor             = "mentor"
    case localConnection    = "local_connection"
    case creator            = "creator"
    case prayerPartner      = "prayer_partner"
    case accountability     = "accountability"
    case classmate          = "classmate"
    case coworker           = "coworker"
    case conferenceContact  = "conference_contact"
    case general            = "general"

    var displayName: String {
        switch self {
        case .collaborator:      return "Collaborator"
        case .mentor:            return "Mentor"
        case .localConnection:   return "Local Connection"
        case .creator:           return "Creator"
        case .prayerPartner:     return "Prayer Partner"
        case .accountability:    return "Accountability"
        case .classmate:         return "Classmate"
        case .coworker:          return "Coworker"
        case .conferenceContact: return "Conference Contact"
        case .general:           return "Connection"
        }
    }

    var systemImage: String {
        switch self {
        case .collaborator:      return "person.2.fill"
        case .mentor:            return "graduationcap.fill"
        case .localConnection:   return "mappin.circle.fill"
        case .creator:           return "sparkles"
        case .prayerPartner:     return "hands.sparkles.fill"
        case .accountability:    return "checkmark.shield.fill"
        case .classmate:         return "book.closed.fill"
        case .coworker:          return "briefcase.fill"
        case .conferenceContact: return "person.badge.key.fill"
        case .general:           return "person.circle.fill"
        }
    }
}

// MARK: - Social Relationship

struct SocialRelationship: Identifiable, Codable {
    let id: String
    var uid: String
    var targetUID: String
    var type: SpatialRelationshipType
    var commonContexts: [String]
    var mutualScore: Double
    var createdAt: Date
    var isConfirmed: Bool
}

// MARK: - Smart Introduction

struct SmartIntroduction: Identifiable {
    let id: String
    var targetUID: String
    var targetDisplayName: String
    var targetPhotoURL: String?
    var commonContexts: [String]
    var suggestedRelationshipType: SpatialRelationshipType
    var introductionReason: String
    var overlapScore: Double
    var isAnonymized: Bool
}

// MARK: - Ephemeral Live Space

struct EphemeralLiveSpace: Identifiable, Codable {
    let id: String
    var title: String
    var triggerEnvironment: String
    var broadLocation: String
    var memberUIDs: [String]
    var isActive: Bool
    var createdAt: Date
    var expiresAt: Date
    var postCount: Int
    var hasDiscussion: Bool
    var hasMediaPool: Bool

    var isExpired: Bool { Date() > expiresAt }
}
