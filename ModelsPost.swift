//
//  Post.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import Foundation

// Legacy Post model - being replaced by the one in PostsManager.swift
// TODO: Migrate all usages to the new Post model and remove this
struct LegacyPost: Identifiable, Codable, Hashable {
    let id: String
    let authorId: String
    let authorName: String
    let authorUsername: String
    let authorAvatarURL: String?
    let content: String
    let category: String
    let createdAt: Date
    let likes: Int
    let comments: Int
    let shares: Int
    let isLiked: Bool
    
    init(
        id: String = UUID().uuidString,
        authorId: String,
        authorName: String,
        authorUsername: String,
        authorAvatarURL: String? = nil,
        content: String,
        category: String,
        createdAt: Date = Date(),
        likes: Int = 0,
        comments: Int = 0,
        shares: Int = 0,
        isLiked: Bool = false
    ) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorAvatarURL = authorAvatarURL
        self.content = content
        self.category = category
        self.createdAt = createdAt
        self.likes = likes
        self.comments = comments
        self.shares = shares
        self.isLiked = isLiked
    }
    
    // MARK: - Computed Properties
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

// MARK: - Mock Data
extension LegacyPost {
    static let mockPosts: [LegacyPost] = [
        LegacyPost(
            authorId: "1",
            authorName: "David Chen",
            authorUsername: "@davidchen",
            content: "Been thinking about how AI could revolutionize Bible study. Imagine personalized scripture recommendations based on what you're going through. But can we trust algorithms to guide spiritual growth?",
            category: "#OPENTABLE",
            createdAt: Date().addingTimeInterval(-1800), // 30 minutes ago
            likes: 24,
            comments: 8,
            shares: 3
        ),
        LegacyPost(
            authorId: "2",
            authorName: "Sarah Johnson",
            authorUsername: "@sarahj",
            content: "Just launched my faith-based startup! Building an app to connect prayer groups worldwide. Looking for feedback from the community. 🙏",
            category: "#OPENTABLE",
            createdAt: Date().addingTimeInterval(-3600), // 1 hour ago
            likes: 56,
            comments: 15,
            shares: 12
        ),
        LegacyPost(
            authorId: "3",
            authorName: "Michael Brown",
            authorUsername: "@mbrown",
            content: "Testimony time: God opened doors I never imagined. My tech startup just got funded, and we're using it to create ethical AI solutions. All glory to Him! 🙌",
            category: "Testimonies",
            createdAt: Date().addingTimeInterval(-7200), // 2 hours ago
            likes: 142,
            comments: 34,
            shares: 28
        ),
        LegacyPost(
            authorId: "4",
            authorName: "Emily Davis",
            authorUsername: "@emilyd",
            content: "Please pray for my team as we prepare for our product launch next week. We've worked hard, but we know it's all in God's hands. 🙏",
            category: "Prayer",
            createdAt: Date().addingTimeInterval(-10800), // 3 hours ago
            likes: 89,
            comments: 45,
            shares: 8
        ),
        LegacyPost(
            authorId: "5",
            authorName: "James Wilson",
            authorUsername: "@jwilson",
            content: "Hot take: The intersection of faith and technology isn't just possible—it's necessary. We need more believers in tech spaces making ethical decisions.",
            category: "#OPENTABLE",
            createdAt: Date().addingTimeInterval(-14400), // 4 hours ago
            likes: 201,
            comments: 67,
            shares: 45
        )
    ]
}
