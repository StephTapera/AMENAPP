//
//  User.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import Foundation

// MARK: - Legacy User Model (Pre-Firebase)
// NOTE: This is the old user model. New code should use UserModel from UserModel.swift
struct AppUser: Identifiable, Codable {
    let id: String
    let username: String
    let displayName: String
    let email: String
    let avatarURL: String?
    let bio: String?
    let joinedDate: Date
    let followerCount: Int?
    let followingCount: Int?
    let postCount: Int?
    let isVerified: Bool
    
    init(
        id: String = UUID().uuidString,
        username: String,
        displayName: String,
        email: String,
        avatarURL: String? = nil,
        bio: String? = nil,
        joinedDate: Date = Date(),
        followerCount: Int? = nil,
        followingCount: Int? = nil,
        postCount: Int? = nil,
        isVerified: Bool = false
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.avatarURL = avatarURL
        self.bio = bio
        self.joinedDate = joinedDate
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.postCount = postCount
        self.isVerified = isVerified
    }
}

// MARK: - User Stats
extension AppUser {
    var formattedJoinDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: joinedDate)
    }
    
    var formattedFollowerCount: String {
        guard let count = followerCount else { return "0" }
        return formatCount(count)
    }
    
    var formattedFollowingCount: String {
        guard let count = followingCount else { return "0" }
        return formatCount(count)
    }
    
    var formattedPostCount: String {
        guard let count = postCount else { return "0" }
        return formatCount(count)
    }
    
    private func formatCount(_ count: Int) -> String {
        switch count {
        case 0..<1000:
            return "\(count)"
        case 1000..<1_000_000:
            return String(format: "%.1fK", Double(count) / 1000)
        default:
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }
}
