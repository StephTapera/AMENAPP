//
//  RealtimePostService.swift
//  AMENAPP
//
//  Created by Steph on 1/24/26.
//
//  Firebase Realtime Database implementation for posts, comments, and engagement stats
//  Optimized for real-time updates and cost efficiency
//

import Foundation
import FirebaseDatabase
import FirebaseAuth
import Combine

// MARK: - Realtime Database Post Service

@MainActor
class RealtimePostService: ObservableObject {
    static let shared = RealtimePostService()
    
    private let database: DatabaseReference
    private nonisolated(unsafe) var listeners: [DatabaseHandle] = []
    
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private init() {
        // Initialize Realtime Database with correct URL
        self.database = Database.database(url: "https://amen-5e359-default-rtdb.firebaseio.com").reference()
        print("🔥 RealtimePostService initialized")
    }
    
    deinit {
        removeAllListeners()
    }
    
    // MARK: - Database Structure
    /*
     Realtime Database Structure:
     
     /posts
       /{postId}
         - authorId: "userId"
         - authorName: "John Doe"
         - authorUsername: "johndoe"
         - authorInitials: "JD"
         - authorProfileImageURL: "https://..."
         - content: "Post content here"
         - category: "openTable" | "testimonies" | "prayer"
         - topicTag: "Relationships"
         - visibility: "everyone"
         - allowComments: true
         - imageURLs: ["url1", "url2"]
         - linkURL: "https://..."
         - createdAt: timestamp
         - updatedAt: timestamp
         - isRepost: false
         - originalPostId: null
         - originalAuthorName: null
     
     /user_posts
       /{userId}
         /{postId}: timestamp  // When posted
     
     /category_posts
       /openTable
         /{postId}: timestamp
       /testimonies
         /{postId}: timestamp
       /prayer
         /{postId}: timestamp
     
     /post_stats
       /{postId}
         - amenCount: 0
         - lightbulbCount: 0
         - commentCount: 0
         - repostCount: 0
     
     /post_interactions
       /{postId}
         /amen
           /{userId}: timestamp
         /lightbulb
           /{userId}: timestamp
         /reposts
           /{userId}: timestamp
     
     /user_saved_posts
       /{userId}
         /{postId}: timestamp  // When saved
     
     /comments
       /{postId}
         /{commentId}
           - authorId: "userId"
           - authorName: "John Doe"
           - authorInitials: "JD"
           - authorProfileImageURL: "https://..."
           - content: "Comment text"
           - createdAt: timestamp
           - amenCount: 0
           - replyCount: 0
     
     /comment_stats
       /{commentId}
         - amenCount: 0
         - replyCount: 0
     */
    
    // MARK: - Create Post
    
    func createPost(
        content: String,
        category: Post.PostCategory,
        topicTag: String? = nil,
        visibility: Post.PostVisibility = .everyone,
        allowComments: Bool = true,
        imageURLs: [String]? = nil,
        linkURL: String? = nil
    ) async throws -> Post {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimePostService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let userId = currentUser.uid
        
        // Get cached user data for fast post creation
        let displayName = UserDefaults.standard.string(forKey: "currentUserDisplayName") ?? "User"
        let username = UserDefaults.standard.string(forKey: "currentUserUsername") ?? "user"
        let initials = UserDefaults.standard.string(forKey: "currentUserInitials") ?? "U"
        let profileImageURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
        
        // Generate post ID
        let postId = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        
        // Create post data
        let postData: [String: Any] = [
            "authorId": userId,
            "authorName": displayName,
            "authorUsername": username,
            "authorInitials": initials,
            "authorProfileImageURL": profileImageURL ?? "",
            "content": content,
            "category": category.rawValue,
            "topicTag": topicTag ?? "",
            "visibility": visibility.rawValue,
            "allowComments": allowComments,
            "imageURLs": imageURLs ?? [],
            "linkURL": linkURL ?? "",
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "isRepost": false,
            "originalPostId": "",
            "originalAuthorName": ""
        ]
        
        print("📝 Creating post in Realtime Database...")
        print("   Post ID: \(postId)")
        print("   Category: \(category.rawValue)")
        
        // Use multi-path update for atomic write
        let updates: [String: Any] = [
            "/posts/\(postId)": postData,
            "/user_posts/\(userId)/\(postId)": timestamp,
            "/category_posts/\(category.rawValue)/\(postId)": timestamp,
            "/post_stats/\(postId)": [
                "amenCount": 0,
                "lightbulbCount": 0,
                "commentCount": 0,
                "repostCount": 0
            ]
        ]
        
        try await database.updateChildValues(updates)
        
        print("✅ Post created successfully in Realtime Database")
        
        // Create Post object for return
        let post = Post(
            id: UUID(uuidString: postId) ?? UUID(),
            authorId: userId,
            authorName: displayName,
            authorInitials: initials,
            timeAgo: "Just now",
            content: content,
            category: category,
            topicTag: topicTag,
            visibility: visibility,
            allowComments: allowComments,
            imageURLs: imageURLs,
            linkURL: linkURL,
            createdAt: Date(),
            amenCount: 0,
            lightbulbCount: 0,
            commentCount: 0,
            repostCount: 0
        )
        
        return post
    }
    
    // MARK: - Fetch User Posts
    
    func fetchUserPosts(userId: String) async throws -> [Post] {
        print("📥 Fetching user posts from Realtime Database for user: \(userId)")
        
        // Get list of post IDs for this user
        let snapshot = try await database.child("user_posts").child(userId).getData()
        
        guard snapshot.exists(), let postDict = snapshot.value as? [String: Any] else {
            print("⚠️ No posts found for user")
            return []
        }
        
        // Fetch each post
        var posts: [Post] = []
        
        for (postId, _) in postDict {
            if let post = try? await fetchPost(postId: postId) {
                posts.append(post)
            }
        }
        
        // Sort by creation date (newest first)
        posts.sort { $0.createdAt > $1.createdAt }
        
        print("✅ Fetched \(posts.count) posts for user")
        return posts
    }
    
    // MARK: - Fetch Single Post
    
    func fetchPost(postId: String) async throws -> Post {
        let postSnapshot = try await database.child("posts").child(postId).getData()
        let statsSnapshot = try await database.child("post_stats").child(postId).getData()
        
        guard postSnapshot.exists(), let postData = postSnapshot.value as? [String: Any] else {
            throw NSError(domain: "RealtimePostService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Post not found"])
        }
        
        // Parse post data
        let authorId = postData["authorId"] as? String ?? ""
        let authorName = postData["authorName"] as? String ?? "Unknown"
        let authorUsername = postData["authorUsername"] as? String ?? ""
        let authorInitials = postData["authorInitials"] as? String ?? "?"
        let content = postData["content"] as? String ?? ""
        let categoryStr = postData["category"] as? String ?? "openTable"
        let topicTag = postData["topicTag"] as? String
        let visibilityStr = postData["visibility"] as? String ?? "everyone"
        let allowComments = postData["allowComments"] as? Bool ?? true
        let imageURLs = postData["imageURLs"] as? [String]
        let linkURL = postData["linkURL"] as? String
        let createdAtTimestamp = postData["createdAt"] as? TimeInterval ?? 0
        let isRepost = postData["isRepost"] as? Bool ?? false
        let originalAuthorName = postData["originalAuthorName"] as? String
        
        // Parse stats
        var amenCount = 0
        var lightbulbCount = 0
        var commentCount = 0
        var repostCount = 0
        
        if statsSnapshot.exists(), let statsData = statsSnapshot.value as? [String: Any] {
            amenCount = statsData["amenCount"] as? Int ?? 0
            lightbulbCount = statsData["lightbulbCount"] as? Int ?? 0
            commentCount = statsData["commentCount"] as? Int ?? 0
            repostCount = statsData["repostCount"] as? Int ?? 0
        }
        
        // Convert to Post model
        let category = Post.PostCategory(rawValue: categoryStr) ?? .openTable
        let visibility = Post.PostVisibility(rawValue: visibilityStr) ?? .everyone
        let createdAt = Date(timeIntervalSince1970: createdAtTimestamp)
        
        return Post(
            id: UUID(uuidString: postId) ?? UUID(),
            authorId: authorId,
            authorName: authorName,
            authorInitials: authorInitials,
            timeAgo: createdAt.timeAgo(),
            content: content,
            category: category,
            topicTag: topicTag,
            visibility: visibility,
            allowComments: allowComments,
            imageURLs: imageURLs,
            linkURL: linkURL,
            createdAt: createdAt,
            amenCount: amenCount,
            lightbulbCount: lightbulbCount,
            commentCount: commentCount,
            repostCount: repostCount,
            isRepost: isRepost,
            originalAuthorName: originalAuthorName
        )
    }
    
    // MARK: - Fetch Posts by Category
    
    func fetchCategoryPosts(category: Post.PostCategory, limit: Int = 50) async throws -> [Post] {
        print("📥 Fetching \(category.rawValue) posts from Realtime Database (limit: \(limit))")
        
        // Get post IDs for category, ordered by timestamp
        let snapshot = try await database
            .child("category_posts")
            .child(category.rawValue)
            .queryOrderedByValue()
            .queryLimited(toLast: UInt(limit))
            .getData()
        
        guard snapshot.exists(), let postDict = snapshot.value as? [String: Any] else {
            print("⚠️ No posts found for category")
            return []
        }
        
        // Fetch each post
        var posts: [Post] = []
        
        for (postId, _) in postDict {
            if let post = try? await fetchPost(postId: postId) {
                posts.append(post)
            }
        }
        
        // Sort by creation date (newest first)
        posts.sort { $0.createdAt > $1.createdAt }
        
        print("✅ Fetched \(posts.count) posts for category: \(category.rawValue)")
        return posts
    }
    
    // MARK: - Update Post
    
    func updatePost(postId: String, content: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimePostService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        print("✏️ Updating post: \(postId)")
        
        let updates: [String: Any] = [
            "/posts/\(postId)/content": content,
            "/posts/\(postId)/updatedAt": Date().timeIntervalSince1970
        ]
        
        try await database.updateChildValues(updates)
        print("✅ Post updated successfully")
    }
    
    // MARK: - Delete Post
    
    func deletePost(postId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimePostService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let userId = currentUser.uid
        
        print("🗑️ Deleting post: \(postId)")
        
        // Fetch post to get category
        let post = try await fetchPost(postId: postId)
        
        // Multi-path delete
        let updates: [String: Any?] = [
            "/posts/\(postId)": nil,
            "/user_posts/\(userId)/\(postId)": nil,
            "/category_posts/\(post.category.rawValue)/\(postId)": nil,
            "/post_stats/\(postId)": nil,
            "/post_interactions/\(postId)": nil,
            "/comments/\(postId)": nil
        ]
        
        try await database.updateChildValues(updates as [AnyHashable: Any])
        print("✅ Post deleted successfully")
    }
    
    // MARK: - Real-time Listener for User Posts
    
    func observeUserPosts(userId: String, completion: @escaping ([Post]) -> Void) {
        print("👂 Setting up real-time listener for user posts: \(userId)")
        
        let handle = database.child("user_posts").child(userId).observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            Task {
                do {
                    guard snapshot.exists(), let postDict = snapshot.value as? [String: Any] else {
                        await MainActor.run {
                            completion([])
                        }
                        return
                    }
                    
                    // Fetch all posts
                    var posts: [Post] = []
                    
                    for (postId, _) in postDict {
                        if let post = try? await self.fetchPost(postId: postId) {
                            posts.append(post)
                        }
                    }
                    
                    // Sort by creation date
                    posts.sort { $0.createdAt > $1.createdAt }
                    
                    await MainActor.run {
                        print("🔄 Real-time update: \(posts.count) user posts")
                        completion(posts)
                    }
                } catch {
                    print("❌ Error in real-time listener: \(error)")
                }
            }
        }
        
        listeners.append(handle)
    }
    
    // MARK: - Real-time Listener for Category Posts
    
    func observeCategoryPosts(category: Post.PostCategory, limit: Int = 50, completion: @escaping ([Post]) -> Void) {
        print("👂 Setting up real-time listener for \(category.rawValue) posts")
        
        let handle = database
            .child("category_posts")
            .child(category.rawValue)
            .queryOrderedByValue()
            .queryLimited(toLast: UInt(limit))
            .observe(.value) { [weak self] snapshot in
                guard let self = self else { return }
                
                Task {
                    do {
                        guard snapshot.exists(), let postDict = snapshot.value as? [String: Any] else {
                            await MainActor.run {
                                completion([])
                            }
                            return
                        }
                        
                        // Fetch all posts
                        var posts: [Post] = []
                        
                        for (postId, _) in postDict {
                            if let post = try? await self.fetchPost(postId: postId) {
                                posts.append(post)
                            }
                        }
                        
                        // Sort by creation date
                        posts.sort { $0.createdAt > $1.createdAt }
                        
                        await MainActor.run {
                            print("🔄 Real-time update: \(posts.count) \(category.rawValue) posts")
                            completion(posts)
                        }
                    } catch {
                        print("❌ Error in real-time listener: \(error)")
                    }
                }
            }
        
        listeners.append(handle)
    }
    
    // MARK: - Remove Listeners
    
    nonisolated func removeAllListeners() {
        for handle in listeners {
            database.removeObserver(withHandle: handle)
        }
        listeners.removeAll()
        print("🔇 All real-time listeners removed")
    }
}

// MARK: - Date Extension for Time Ago

extension Date {
    func timeAgo() -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.minute, .hour, .day, .weekOfYear, .month, .year], from: self, to: now)
        
        if let year = components.year, year > 0 {
            return "\(year)y"
        }
        if let month = components.month, month > 0 {
            return "\(month)mo"
        }
        if let week = components.weekOfYear, week > 0 {
            return "\(week)w"
        }
        if let day = components.day, day > 0 {
            return "\(day)d"
        }
        if let hour = components.hour, hour > 0 {
            return "\(hour)h"
        }
        if let minute = components.minute, minute > 0 {
            return "\(minute)m"
        }
        return "now"
    }
}
