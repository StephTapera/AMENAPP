import Foundation
import CoreLocation

enum SpiritualGraphNodeType: String, Codable, CaseIterable, Hashable {
    case user
    case church
    case ministry
    case event
    case studyInterest
    case worshipStyle
    case servicePattern
    case volunteerActivity
    case savedContent
    case prayerInterest
}

enum SpiritualGraphEdgeType: String, Codable, CaseIterable, Hashable {
    case attends
    case saved
    case visited
    case interested
    case studies
    case volunteers
    case watches
    case participates
    case serves
    case connectedTo
}

enum SpiritualMemoryType: String, Codable, CaseIterable, Hashable {
    case churchVisit
    case savedSermon
    case studyTopic
    case prayerHabit
    case volunteerInterest
    case serviceAttendance
    case recurringMinistry
    case spiritualGoal
    case savedScriptureTheme
}

enum SpiritualMemoryVisibility: String, Codable, CaseIterable, Hashable {
    case privateOnly
    case userApprovedForBerean
    case exportOnly
}

enum PresenceSensitivityLevel: String, Codable, CaseIterable, Hashable {
    case minimal
    case balanced
    case quiet
}

enum PresenceSignalType: String, Codable, CaseIterable, Hashable {
    case prayerGathering
    case serviceStartingSoon
    case quietPrayerSpace
    case bibleStudyTonight
    case volunteerOpportunity
    case savedChurchReminder
}

struct SpiritualGraphNode: Codable, Hashable, Identifiable {
    let id: String
    let type: SpiritualGraphNodeType
    let title: String
    let tags: [String]
    let metadata: [String: String]
    let confidence: Double
    let updatedAt: Date?
}

struct SpiritualGraphEdge: Codable, Hashable, Identifiable {
    let id: String
    let fromId: String
    let toId: String
    let type: SpiritualGraphEdgeType
    let strength: Double
    let confidence: Double
    let createdAt: Date?
    let updatedAt: Date?
}

struct SpiritualAffinitySnapshot: Codable, Hashable {
    let churchAffinity: [String: Double]
    let worshipSimilarity: [String: Double]
    let communityOverlap: [String: Double]
    let ministryRelevance: [String: Double]
    let updatedAt: Date?
}

struct SpiritualMemoryRecord: Codable, Hashable, Identifiable {
    let id: String
    let type: SpiritualMemoryType
    let source: String
    let tags: [String]
    let createdAt: Date?
    let confidence: Double
    let visibility: SpiritualMemoryVisibility
    let derivedInsights: [String]
}

struct PresencePreferences: Codable, Hashable {
    let quietModeEnabled: Bool
    let worshipAwareSuppression: Bool
    let travelAwareSuppression: Bool
    let sensitivityLevel: PresenceSensitivityLevel
    let enabledSignals: [PresenceSignalType]
    let updatedAt: Date?

    static let `default` = PresencePreferences(
        quietModeEnabled: false,
        worshipAwareSuppression: true,
        travelAwareSuppression: true,
        sensitivityLevel: .balanced,
        enabledSignals: PresenceSignalType.allCases,
        updatedAt: nil
    )
}

struct PresenceSignal: Codable, Hashable, Identifiable {
    let id: String
    let type: PresenceSignalType
    let title: String
    let detail: String?
    let churchId: String?
    let eventId: String?
    let location: ChurchEntity.GeoPoint?
    let startsAt: Date?
    let confidence: Double
    let confidenceLevel: ChurchConfidenceLevel
    let sources: [ChurchGroundingSource]
    let updatedAt: Date?
}

struct BereanOperatingContext: Codable, Hashable {
    let userId: String
    let churchId: String?
    let eventId: String?
    let mediaId: String?
    let studyTopicIds: [String]
    let memoryIds: [String]
    let preferredResponseMode: String?
    let sources: [ChurchGroundingSource]
    let confidence: ChurchConfidenceMetadata
}

struct BereanOperatingResponse: Codable, Hashable {
    let answer: String
    let attributionLine: String
    let confidence: ChurchConfidenceMetadata
    let sources: [ChurchGroundingSource]
    let notConfirmedYet: Bool
}

struct SpatialPresenceSnapshot: Codable, Hashable {
    let floatingCardEnabled: Bool
    let immersivePreviewAvailable: Bool
    let prayerMapSignals: [PresenceSignal]
    let ambientOverlayHints: [String]
    let updatedAt: Date?
}

struct AmbientGlassState: Codable, Hashable {
    let glassIntensity: Double
    let blurRadius: Double
    let highlightOpacity: Double
    let calmMotionFactor: Double
    let quietMode: Bool
    let prayerMode: Bool
}

// MARK: - Church Grounding Types

enum ChurchConfidenceLevel: String, Codable, CaseIterable, Hashable {
    case low      = "low"
    case medium   = "medium"
    case high     = "high"
    case verified = "verified"
}

enum ChurchGroundingSourceType: String, Codable, CaseIterable, Hashable {
    case verifiedMetadata = "verifiedMetadata"
    case adminProvided    = "adminProvided"
    case approvedMedia    = "approvedMedia"
    case publicRecord     = "publicRecord"
    case userContributed  = "userContributed"
}

struct ChurchGroundingSource: Codable, Hashable, Identifiable {
    let id: String
    let type: ChurchGroundingSourceType
    let title: String
    let detail: String?
    let url: String?
    let verified: Bool
    let updatedAt: Date?
}

struct ChurchConfidenceMetadata: Codable, Hashable {
    let confidence: Double
    let level: ChurchConfidenceLevel
    let sources: [ChurchGroundingSource]
    let note: String
    let updatedAt: Date?
}

struct GroundedChurchAnswer: Codable, Hashable {
    let response: String
    let confidence: ChurchConfidenceMetadata
    let sources: [ChurchGroundingSource]
    let fallbackMessage: String?
}
