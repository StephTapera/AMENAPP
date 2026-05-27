import Foundation

struct FollowUser: Identifiable, Codable {
    let id: String
    let name: String
    let username: String
    let initials: String
    let profileImageURL: String?
    let bio: String?
    let followersCount: Int
    let isFollowing: Bool
    let followedAt: Date?
}
