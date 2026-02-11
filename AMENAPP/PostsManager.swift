//
//  PostsManager.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Post Model

struct Post: Identifiable, Codable, Equatable {
    let id: UUID
    let databaseId: String  // Actual Firestore/RTDB document ID (stable across loads)
    let authorId: String  // Firebase user ID of the post author
    let authorName: String
    let authorUsername: String?  // Optional username (e.g., @johndoe)
    let authorInitials: String
    let authorProfileImageURL: String?  // Profile image URL
    let timeAgo: String
    var content: String  // Made mutable for editing
    let category: PostCategory
    let topicTag: String?
    let visibility: PostVisibility
    let allowComments: Bool
    let imageURLs: [String]?
    let linkURL: String?
    let createdAt: Date
    var amenCount: Int
    var lightbulbCount: Int
    var commentCount: Int
    var repostCount: Int
    var isRepost: Bool = false  // Track if this is a repost
    var originalAuthorName: String? // Track original author if repost
    var originalAuthorId: String? // Track original author ID if repost
    
    enum PostCategory: String, Codable, CaseIterable {
        case openTable = "openTable"      // ✅ Firebase-safe (no special chars)
        case testimonies = "testimonies"  // ✅ Firebase-safe (lowercase)
        case prayer = "prayer"            // ✅ Firebase-safe (lowercase)
        
        /// Display name for UI (with special formatting)
        var displayName: String {
            switch self {
            case .openTable: return "#OPENTABLE"
            case .testimonies: return "Testimonies"
            case .prayer: return "Prayer"
            }
        }
        
        var cardCategory: PostCard.PostCardCategory {
            switch self {
            case .openTable: return .openTable
            case .testimonies: return .testimonies
            case .prayer: return .prayer
            }
        }
    }
    
    enum PostVisibility: String, Codable {
        case everyone = "Everyone"
        case followers = "Followers"
        case community = "Community Only"
    }
    
    // MARK: - Custom Decoding (Handle Missing Fields)
    
    enum CodingKeys: String, CodingKey {
        case id, databaseId, authorId, authorName, authorUsername, authorInitials, authorProfileImageURL, timeAgo
        case content, category, topicTag, visibility, allowComments
        case imageURLs, linkURL, createdAt
        case amenCount, lightbulbCount, commentCount, repostCount
        case isRepost, originalAuthorName, originalAuthorId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        databaseId = try container.decodeIfPresent(String.self, forKey: .databaseId) ?? id.uuidString
        authorId = try container.decode(String.self, forKey: .authorId)
        authorName = try container.decode(String.self, forKey: .authorName)
        
        // ✅ Gracefully handle missing authorUsername (for backward compatibility)
        authorUsername = try container.decodeIfPresent(String.self, forKey: .authorUsername)
        
        authorInitials = try container.decode(String.self, forKey: .authorInitials)
        
        // ✅ Gracefully handle missing authorProfileImageURL (for backward compatibility)
        authorProfileImageURL = try container.decodeIfPresent(String.self, forKey: .authorProfileImageURL)
        
        timeAgo = try container.decode(String.self, forKey: .timeAgo)
        content = try container.decode(String.self, forKey: .content)
        category = try container.decode(PostCategory.self, forKey: .category)
        topicTag = try container.decodeIfPresent(String.self, forKey: .topicTag)
        visibility = try container.decode(PostVisibility.self, forKey: .visibility)
        allowComments = try container.decode(Bool.self, forKey: .allowComments)
        imageURLs = try container.decodeIfPresent([String].self, forKey: .imageURLs)
        linkURL = try container.decodeIfPresent(String.self, forKey: .linkURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        amenCount = try container.decode(Int.self, forKey: .amenCount)
        lightbulbCount = try container.decode(Int.self, forKey: .lightbulbCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        repostCount = try container.decode(Int.self, forKey: .repostCount)
        isRepost = try container.decodeIfPresent(Bool.self, forKey: .isRepost) ?? false
        originalAuthorName = try container.decodeIfPresent(String.self, forKey: .originalAuthorName)
        originalAuthorId = try container.decodeIfPresent(String.self, forKey: .originalAuthorId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(databaseId, forKey: .databaseId)
        try container.encode(authorId, forKey: .authorId)
        try container.encode(authorName, forKey: .authorName)
        try container.encodeIfPresent(authorUsername, forKey: .authorUsername)
        try container.encode(authorInitials, forKey: .authorInitials)
        try container.encodeIfPresent(authorProfileImageURL, forKey: .authorProfileImageURL)
        try container.encode(timeAgo, forKey: .timeAgo)
        try container.encode(content, forKey: .content)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(topicTag, forKey: .topicTag)
        try container.encode(visibility, forKey: .visibility)
        try container.encode(allowComments, forKey: .allowComments)
        try container.encodeIfPresent(imageURLs, forKey: .imageURLs)
        try container.encodeIfPresent(linkURL, forKey: .linkURL)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(amenCount, forKey: .amenCount)
        try container.encode(lightbulbCount, forKey: .lightbulbCount)
        try container.encode(commentCount, forKey: .commentCount)
        try container.encode(repostCount, forKey: .repostCount)
        try container.encode(isRepost, forKey: .isRepost)
        try container.encodeIfPresent(originalAuthorName, forKey: .originalAuthorName)
        try container.encodeIfPresent(originalAuthorId, forKey: .originalAuthorId)
    }
    
    init(
        id: UUID = UUID(),
        databaseId: String? = nil,
        authorId: String = "",
        authorName: String,
        authorUsername: String? = nil,
        authorInitials: String,
        authorProfileImageURL: String? = nil,
        timeAgo: String = "Just now",
        content: String,
        category: PostCategory,
        topicTag: String? = nil,
        visibility: PostVisibility = .everyone,
        allowComments: Bool = true,
        imageURLs: [String]? = nil,
        linkURL: String? = nil,
        createdAt: Date = Date(),
        amenCount: Int = 0,
        lightbulbCount: Int = 0,
        commentCount: Int = 0,
        repostCount: Int = 0,
        isRepost: Bool = false,
        originalAuthorName: String? = nil,
        originalAuthorId: String? = nil
    ) {
        self.id = id
        self.databaseId = databaseId ?? id.uuidString
        self.authorId = authorId
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorInitials = authorInitials
        self.authorProfileImageURL = authorProfileImageURL
        self.timeAgo = timeAgo
        self.content = content
        self.category = category
        self.topicTag = topicTag
        self.visibility = visibility
        self.allowComments = allowComments
        self.imageURLs = imageURLs
        self.linkURL = linkURL
        self.createdAt = createdAt
        self.amenCount = amenCount
        self.lightbulbCount = lightbulbCount
        self.commentCount = commentCount
        self.repostCount = repostCount
        self.isRepost = isRepost
        self.originalAuthorName = originalAuthorName
        self.originalAuthorId = originalAuthorId
    }
}

// MARK: - Posts Manager

class PostsManager: ObservableObject {
    @MainActor static let shared = PostsManager()
    
    @Published var openTablePosts: [Post] = []
    @Published var testimoniesPosts: [Post] = []
    @Published var prayerPosts: [Post] = []
    @Published var allPosts: [Post] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebasePostService = FirebasePostService.shared
    private let personalizationService = PersonalizationService.shared
    
    private init() {
        // Load posts from Firebase
        Task {
            await loadPostsFromFirebase()
        }
    }
    
    // MARK: - Load from Firebase
    
    func loadPostsFromFirebase() async {
        do {
            print("📥 Loading posts from Firebase...")
            try await firebasePostService.fetchAllPosts()
            
            // Subscribe to real-time updates
            firebasePostService.startListening()
            
            // Update local arrays
            self.allPosts = firebasePostService.posts
            self.openTablePosts = firebasePostService.openTablePosts
            self.testimoniesPosts = firebasePostService.testimoniesPosts
            self.prayerPosts = firebasePostService.prayerPosts
            
            print("✅ Posts loaded from Firebase: \(allPosts.count) total")
        } catch {
            print("❌ Failed to load posts from Firebase: \(error)")
            self.error = error.localizedDescription
            // Posts will show empty state in UI
        }
    }
    
    func refreshPosts() async {
        await loadPostsFromFirebase()
    }
    
    // MARK: - Create Post
    
    func createPost(
        content: String,
        category: Post.PostCategory,
        topicTag: String? = nil,
        visibility: Post.PostVisibility = .everyone,
        allowComments: Bool = true,
        imageURLs: [String]? = nil,
        linkURL: String? = nil
    ) {
        Task {
            do {
                // Use Firebase service to create post
                try await firebasePostService.createPost(
                    content: content,
                    category: category,
                    topicTag: topicTag,
                    visibility: visibility,
                    allowComments: allowComments,
                    imageURLs: imageURLs,
                    linkURL: linkURL
                )
                
                print("✅ Post created successfully")
                
                // Real-time listener will automatically update the UI
                // But we can manually refresh if needed
                await refreshPosts()
                
                // Post notification for UI update
                NotificationCenter.default.post(
                    name: .newPostCreated,
                    object: nil,
                    userInfo: ["category": category.rawValue]
                )
                
            } catch {
                print("❌ Failed to create post: \(error)")
                self.error = error.localizedDescription
            }
        }
    }
    
    // MARK: - Get Posts by Category
    
    func getPosts(for category: Post.PostCategory) -> [Post] {
        switch category {
        case .openTable:
            return openTablePosts
        case .testimonies:
            return testimoniesPosts
        case .prayer:
            return prayerPosts
        }
    }
    
    // MARK: - Fetch Filtered Posts
    
    /// Fetch posts with filter and category applied (backend-connected)
    func fetchFilteredPosts(
        for category: Post.PostCategory,
        filter: String,
        topicTag: String? = nil
    ) async {
        do {
            print("📥 Fetching filtered posts: category=\(category.rawValue), filter=\(filter), topicTag=\(topicTag ?? "none")")
            
            let posts = try await firebasePostService.fetchPosts(
                for: category,
                filter: filter,
                topicTag: topicTag
            )
            
            // Apply personalization if "For You" filter
            let finalPosts: [Post]
            if filter == "For You" {
                // Use the new PersonalizationService for better algorithm
                finalPosts = personalizationService.personalizePostsFeed(posts, category: category)
            } else {
                finalPosts = posts
            }
            
            // Update the appropriate category array
            switch category {
            case .openTable:
                self.openTablePosts = finalPosts
            case .testimonies:
                self.testimoniesPosts = finalPosts
            case .prayer:
                self.prayerPosts = finalPosts
            }
            
            print("✅ Updated \(category.rawValue) posts with \(finalPosts.count) items (personalized: \(filter == "For You"))")
            
        } catch {
            print("❌ Failed to fetch filtered posts: \(error)")
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Edit Post
    
    func editPost(postId: UUID, newContent: String) {
        Task {
            do {
                try await firebasePostService.editPost(postId: postId.uuidString, newContent: newContent)
                
                print("✅ Post edited successfully")
                
                // Update local cache
                updatePostInAllArrays(postId: postId) { post in
                    var updatedPost = post
                    updatedPost.content = newContent
                    return updatedPost
                }
                
                // Post notification for UI update
                NotificationCenter.default.post(
                    name: .postEdited,
                    object: nil,
                    userInfo: ["postId": postId]
                )
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
            } catch {
                print("❌ Failed to edit post: \(error)")
                self.error = error.localizedDescription
            }
        }
    }
    
    // MARK: - Delete Post
    
    func deletePost(postId: UUID) {
        Task {
            do {
                try await firebasePostService.deletePost(postId: postId.uuidString)
                
                print("✅ Post deleted successfully")
                
                // Remove from local arrays
                allPosts.removeAll { $0.id == postId }
                openTablePosts.removeAll { $0.id == postId }
                testimoniesPosts.removeAll { $0.id == postId }
                prayerPosts.removeAll { $0.id == postId }
                
                // Post notification for UI update
                NotificationCenter.default.post(
                    name: .postDeleted,
                    object: nil,
                    userInfo: ["postId": postId]
                )
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.warning)
                
            } catch {
                print("❌ Failed to delete post: \(error)")
                self.error = error.localizedDescription
            }
        }
    }
    
    // MARK: - Repost to Profile
    
    func repostToProfile(originalPost: Post, userInitials: String = "JD", userName: String = "John Disciple") {
        Task {
            do {
                try await firebasePostService.repostToProfile(originalPostId: originalPost.firestoreId)
                
                print("✅ Post reposted successfully")
                
                // Refresh posts to get the new repost
                await refreshPosts()
                
                // Post notification
                NotificationCenter.default.post(
                    name: .postReposted,
                    object: nil,
                    userInfo: ["originalPostId": originalPost.id]
                )
                
            } catch {
                print("❌ Failed to repost: \(error)")
                self.error = error.localizedDescription
            }
        }
    }
    
    // MARK: - Update Post Interactions
    
    func updateAmenCount(postId: UUID, increment: Bool) {
        Task {
            do {
                try await firebasePostService.toggleAmen(postId: postId.uuidString)
                
                // Update local cache
                updatePostInAllArrays(postId: postId) { post in
                    var updatedPost = post
                    updatedPost.amenCount += increment ? 1 : -1
                    return updatedPost
                }
            } catch {
                print("❌ Failed to update amen count: \(error)")
            }
        }
    }
    
    func updateLightbulbCount(postId: UUID, increment: Bool) {
        Task {
            do {
                try await firebasePostService.toggleLightbulb(postId: postId.uuidString)
                
                // Update local cache
                updatePostInAllArrays(postId: postId) { post in
                    var updatedPost = post
                    updatedPost.lightbulbCount += increment ? 1 : -1
                    return updatedPost
                }
            } catch {
                print("❌ Failed to update lightbulb count: \(error)")
            }
        }
    }
    
    func updateCommentCount(postId: UUID, increment: Bool) {
        Task {
            do {
                if increment {
                    try await firebasePostService.incrementCommentCount(postId: postId.uuidString)
                }
                
                // Update local cache
                updatePostInAllArrays(postId: postId) { post in
                    var updatedPost = post
                    updatedPost.commentCount += increment ? 1 : -1
                    return updatedPost
                }
            } catch {
                print("❌ Failed to update comment count: \(error)")
            }
        }
    }
    
    func updateRepostCount(postId: UUID, increment: Bool) {
        // This is handled automatically by repostToProfile
        updatePostInAllArrays(postId: postId) { post in
            var updatedPost = post
            updatedPost.repostCount += increment ? 1 : -1
            return updatedPost
        }
    }
    
    // MARK: - Helper Methods
    
    private func updatePostInAllArrays(postId: UUID, update: (Post) -> Post) {
        // Update in all posts
        if let index = allPosts.firstIndex(where: { $0.id == postId }) {
            allPosts[index] = update(allPosts[index])
        }
        
        // Update in category-specific arrays
        if let index = openTablePosts.firstIndex(where: { $0.id == postId }) {
            openTablePosts[index] = update(openTablePosts[index])
        }
        
        if let index = testimoniesPosts.firstIndex(where: { $0.id == postId }) {
            testimoniesPosts[index] = update(testimoniesPosts[index])
        }
        
        if let index = prayerPosts.firstIndex(where: { $0.id == postId }) {
            prayerPosts[index] = update(prayerPosts[index])
        }
    }
}


