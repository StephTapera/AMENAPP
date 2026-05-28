import Foundation
import FirebaseFirestore

enum ModerationContentType: String, Codable, CaseIterable {
    case crisisPost, givingPost, crisisComment, communityPost, anonCrisisPost, supportGroupPost
    var displayName: String {
        switch self {
        case .crisisPost: return "Crisis Post"; case .givingPost: return "Giving Post"
        case .crisisComment: return "Crisis Comment"; case .communityPost: return "Community Post"
        case .anonCrisisPost: return "Anon Crisis Post"; case .supportGroupPost: return "Support Group Post"
        }
    }
}

enum ModerationCaseStatus: String, Codable, CaseIterable {
    case new, reviewing, resolved, escalated, falsePositive
    var displayName: String {
        switch self { case .new: return "New"; case .reviewing: return "Reviewing"; case .resolved: return "Resolved"; case .escalated: return "Escalated"; case .falsePositive: return "False Positive" }
    }
}

enum ModerationAction: String, Codable {
    case approve, hide, delete, escalateToTeam, contactUser
    var displayName: String {
        switch self { case .approve: return "Approve"; case .hide: return "Hide"; case .delete: return "Delete"; case .escalateToTeam: return "Escalate"; case .contactUser: return "Contact User" }
    }
    var isDestructive: Bool { self == .delete || self == .hide }
    var icon: String {
        switch self { case .approve: return "checkmark.circle.fill"; case .hide: return "eye.slash.fill"; case .delete: return "trash.fill"; case .escalateToTeam: return "exclamationmark.triangle.fill"; case .contactUser: return "envelope.fill" }
    }
}

struct ModerationFlag: Codable {
    var reason: String
    var severity: Int
    var flaggedBy: String
    var flaggedAt: Timestamp?
    var context: String?
}

struct ModeratorNote: Identifiable, Codable {
    @DocumentID var id: String?
    var moderatorId: String
    var note: String
    var timestamp: Timestamp?
}

struct ModerationCase: Identifiable, Codable {
    @DocumentID var id: String?
    var type: ModerationContentType
    var contentId: String
    var flag: ModerationFlag
    var status: ModerationCaseStatus
    var assignedTo: String?
    var assignedAt: Timestamp?
    var notes: [ModeratorNote]
    var action: ModerationAction?
    var actionTakenBy: String?
    var actionTakenAt: Timestamp?
}

struct CrisisEscalation: Identifiable, Codable {
    @DocumentID var id: String?
    var userIdHash: String
    var type: String
    var detectedAt: Timestamp?
    var severity: Int
    var indicators: [String]
    var crisisTeamNotified: Bool
    var contacted: Bool
    var contactMethod: String?
    var contactedAt: Timestamp?
    var followUpAt: Timestamp?
    var outcome: String?
}
