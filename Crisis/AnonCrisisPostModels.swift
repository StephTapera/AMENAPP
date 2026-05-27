import Foundation
import FirebaseFirestore

enum GuardianStatus: String, Codable {
    case approved, flagged, hiddenForSafety
}

struct AnonCrisisPost: Identifiable, Codable {
    @DocumentID var id: String?
    var userIdHash: String
    var createdAt: Timestamp?
    var content: String
    var linkedOrganizations: [String]
    var linkedWellness: [String]
    var guardianStatus: GuardianStatus
    var crisisLevel: CrisisLevel
    var commentsAllowed: Bool
    var resourcesAutoAdded: [CrisisResource]
    var heartsCount: Int

    struct CrisisResource: Codable, Identifiable {
        var id: String { type + linkedId }
        var type: String
        var linkedId: String
        var reason: String
    }
}

struct CrisisComment: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var content: String
    var type: CommentType
    var createdAt: Timestamp?
    var guardianModerated: Bool

    enum CommentType: String, Codable {
        case support, resource, prayer
        var displayName: String { rawValue.capitalized }
        var icon: String {
            switch self { case .support: return "heart.fill"; case .resource: return "link.circle.fill"; case .prayer: return "hands.sparkles.fill" }
        }
    }
}
