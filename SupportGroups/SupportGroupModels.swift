import Foundation
import FirebaseFirestore

enum SupportGroupCategory: String, Codable, CaseIterable {
    case grief, addiction, anxiety, depression, identity, relationship, faith, other
    var displayName: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .grief: return "heart.slash.fill"; case .addiction: return "link.badge.plus"
        case .anxiety: return "brain.head.profile"; case .depression: return "cloud.drizzle.fill"
        case .identity: return "person.fill.questionmark"; case .relationship: return "person.2.fill"
        case .faith: return "cross.fill"; case .other: return "ellipsis.circle.fill"
        }
    }
}

enum SupportGroupVisibility: String, Codable {
    case `public`, `private`, churchOnly
    var displayName: String {
        switch self { case .public: return "Public"; case .private: return "Private"; case .churchOnly: return "Church Only" }
    }
}

enum MemberRole: String, Codable {
    case member, coLeader, leader
    var displayName: String { rawValue.capitalized }
}

enum MemberStatus: String, Codable {
    case active, onLeave, inactive
}

struct SupportGroup: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var description: String
    var category: SupportGroupCategory
    var focusTags: [String]
    var leaderUserId: String
    var leaderName: String
    var leaderVerified: Bool
    var createdAt: Timestamp?
    var visibility: SupportGroupVisibility
    var churchId: String?
    var memberCount: Int
    var guidelines: [String]
    var guardianModerated: Bool
    var postsLastWeek: Int
    var activeMembers: Int
}

struct SupportGroupMember: Codable {
    var joinedAt: Timestamp?
    var role: MemberRole
    var status: MemberStatus
    var lastActiveAt: Timestamp?
}

struct SupportGroupPost: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var content: String
    var createdAt: Timestamp?
    var hearts: Int
    var comments: Int
    var modStatus: String
    var isAnonymous: Bool
    var authorName: String?
}

struct SupportGroupResource: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var type: String
    var url: String?
    var pinned: Bool
    var addedAt: Timestamp?
}
