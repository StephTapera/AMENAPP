//
//  FollowRelationship.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//

import Foundation
import FirebaseFirestore

/// Represents a follower/following relationship between two users
struct FollowRelationship: Codable, Identifiable {
    @DocumentID var id: String?
    var followerId: String      // User who is following
    var followingId: String     // User being followed
    var createdAt: Date
    var notificationsEnabled: Bool  // Can the follower get notifications from this user?
    
    enum CodingKeys: String, CodingKey {
        case id
        case followerId
        case followingId
        case createdAt
        case notificationsEnabled
    }
    
    init(
        id: String? = nil,
        followerId: String,
        followingId: String,
        createdAt: Date = Date(),
        notificationsEnabled: Bool = true
    ) {
        self.id = id
        self.followerId = followerId
        self.followingId = followingId
        self.createdAt = createdAt
        self.notificationsEnabled = notificationsEnabled
    }
}

/// A user profile with follow status information
struct UserProfileWithFollowStatus: Identifiable {
    let id: String
    let user: UserModel
    var isFollowing: Bool
    var isFollower: Bool
    var isMutual: Bool {
        isFollowing && isFollower
    }
}
