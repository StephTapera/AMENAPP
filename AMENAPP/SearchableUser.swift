//
//  SearchableUser.swift
//  AMENAPP
//
//  Unified user model for search and discovery
//

import SwiftUI
import Foundation

// Note: FirebaseSearchUser is the canonical type defined in UserSearchService.swift
// If you see "ambiguous type" errors, search your project for duplicate FirebaseSearchUser definitions and remove them

struct SearchableUser: Identifiable {
    let id: String
    let name: String
    let username: String?
    let email: String?
    let bio: String?
    let avatarUrl: String?
    let interests: [String]
    let postCount: Int
    let followerCount: Int
    let followingCount: Int
    
    var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1)) + String(words[1].prefix(1))
        } else {
            return String(name.prefix(2))
        }
    }
    
    var displayName: String {
        return name
    }
    
    var avatarColor: Color {
        // Generate a consistent color based on user ID
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .indigo, .cyan]
        let hash = abs(id.hashValue)
        return colors[hash % colors.count]
    }
    
    // Full initializer
    init(
        id: String,
        name: String,
        username: String? = nil,
        email: String? = nil,
        bio: String? = nil,
        avatarUrl: String? = nil,
        interests: [String] = [],
        postCount: Int = 0,
        followerCount: Int = 0,
        followingCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.email = email
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.interests = interests
        self.postCount = postCount
        self.followerCount = followerCount
        self.followingCount = followingCount
    }
    
    // Convert from Firebase ContactUser
    init(from contactUser: ContactUser) {
        self.id = contactUser.id ?? UUID().uuidString
        self.name = contactUser.name
        self.username = contactUser.username
        self.email = contactUser.email
        self.bio = nil
        self.avatarUrl = contactUser.avatarUrl
        self.interests = []
        self.postCount = 0
        self.followerCount = 0
        self.followingCount = 0
    }
    
    // Convert from FirebaseSearchUser
    init(from firebaseUser: FirebaseSearchUser) {
        self.id = firebaseUser.id
        self.name = firebaseUser.displayName
        self.username = firebaseUser.username
        self.email = nil
        self.bio = firebaseUser.bio
        self.avatarUrl = firebaseUser.profileImageURL
        self.interests = []
        self.postCount = 0
        self.followerCount = 0
        self.followingCount = 0
    }
    
    // Sample data for testing
    static let sampleUsers: [SearchableUser] = [
        SearchableUser(
            id: "1",
            name: "Sarah Chen",
            username: "sarahc",
            email: "sarah@example.com",
            bio: "Tech entrepreneur & worship leader 🎸 Building kingdom businesses",
            avatarUrl: nil,
            interests: ["AI & Faith", "Tech Ethics", "Worship", "Startups"],
            postCount: 142,
            followerCount: 1234,
            followingCount: 567
        ),
        SearchableUser(
            id: "2",
            name: "Michael Thompson",
            username: "mikethompson",
            email: "michael@example.com",
            bio: "Pastor | Author | Coffee enthusiast ☕️",
            avatarUrl: nil,
            interests: ["Ministry", "Teaching", "Scripture", "Prayer"],
            postCount: 89,
            followerCount: 3456,
            followingCount: 234
        ),
        SearchableUser(
            id: "3",
            name: "Emily Rodriguez",
            username: "emilyrod",
            email: "emily@example.com",
            bio: "Campus minister reaching Gen Z for Christ 🙏",
            avatarUrl: nil,
            interests: ["Youth Ministry", "Social Media", "Evangelism"],
            postCount: 234,
            followerCount: 2100,
            followingCount: 890
        ),
        SearchableUser(
            id: "4",
            name: "David Martinez",
            username: "davidm",
            email: "david@example.com",
            bio: "Software engineer building tools for churches",
            avatarUrl: nil,
            interests: ["Tech", "Church Innovation", "AI", "Bible Study"],
            postCount: 67,
            followerCount: 890,
            followingCount: 432
        ),
        SearchableUser(
            id: "5",
            name: "Rachel Kim",
            username: "rachelk",
            email: "rachel@example.com",
            bio: "Worship leader & songwriter 🎵",
            avatarUrl: nil,
            interests: ["Worship", "Music", "Creative Arts", "Prayer"],
            postCount: 156,
            followerCount: 4500,
            followingCount: 678
        )
    ]
}
