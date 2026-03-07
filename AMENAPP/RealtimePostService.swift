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

// MARK: - Listener Token

/// Pairs a DatabaseQuery with its handle so observers can be removed from the
/// correct reference — not just the root database ref.
/// `nonisolated(unsafe)` on `query` allows safe access from the lock-protected
/// `removeAllListenerTokens()` which is `nonisolated` for deinit compatibility.
private struct ListenerToken {
    nonisolated(unsafe) let query: DatabaseQuery
    let handle: DatabaseHandle
}

// MARK: - Realtime Database Post Service

@MainActor
class RealtimePostService: ObservableObject {
    static let shared = RealtimePostService()
    
    private nonisolated(unsafe) let database: DatabaseReference
    // listenerTokens is only accessed on MainActor except in deinit.
    // Using nonisolated(unsafe) + NSLock ensures safe cross-thread access during deinit.
    private nonisolated(unsafe) var listenerTokens: [ListenerToken] = []
    private let listenersLock = NSLock()

    // Per-observer cancellable tasks — keyed by an observer tag string.
    // Cancelled before a new refresh task starts to prevent stampede.
    private var observerTasks: [String: Task<Void, Never>] = [:]
    
    @Published var isLoading = false
    @Published var error: String?
    
    private init() {
        // Initialize Realtime Database with correct URL
        self.database = Database.database().reference()
    }
    
    deinit {
        // Only token removal is safe in deinit (nonisolated + lock-protected).
        // observerTasks cancellation requires the actor and is handled by stopAllObserving()
        // which is called explicitly on logout via AuthenticationViewModel.signOut().
        removeAllListenerTokens()
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
        
        // Create post data - only include non-empty optional fields
        var postData: [String: Any] = [
            "authorId": userId,
            "authorName": displayName,
            "authorUsername": username,
            "authorInitials": initials,
            "content": content,
            "category": category.rawValue,
            "visibility": visibility.rawValue,
            "allowComments": allowComments,
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "isRepost": false
        ]
        
        // Add optional fields only if they have values
        if let profileImageURL = profileImageURL, !profileImageURL.isEmpty {
            postData["authorProfileImageURL"] = profileImageURL
        }
        
        if let topicTag = topicTag, !topicTag.isEmpty {
            postData["topicTag"] = topicTag
        }
        
        if let imageURLs = imageURLs, !imageURLs.isEmpty {
            postData["imageURLs"] = imageURLs
        }
        
        if let linkURL = linkURL, !linkURL.isEmpty {
            postData["linkURL"] = linkURL
        }
        
        dlog("📝 Creating post in Realtime Database...")
        dlog("   Post ID: \(postId)")
        dlog("   Category: \(category.rawValue)")
        dlog("   Post data keys: \(postData.keys.sorted())")
        
        // Atomic multi-path update — all four locations succeed or fail together.
        // Flat key paths avoid nested-dictionary serialisation issues with the RTDB bridge.
        var atomicUpdates: [String: Any] = [
            "user_posts/\(userId)/\(postId)": timestamp,
            "category_posts/\(category.rawValue)/\(postId)": timestamp,
            "post_stats/\(postId)/amenCount": 0,
            "post_stats/\(postId)/lightbulbCount": 0,
            "post_stats/\(postId)/commentCount": 0,
            "post_stats/\(postId)/repostCount": 0
        ]
        
        // Flatten postData fields under "posts/{postId}/" so all keys remain at the
        // top level of the multi-path dictionary, avoiding nested map issues.
        for (key, value) in postData {
            atomicUpdates["posts/\(postId)/\(key)"] = value
        }
        
        do {
            try await database.updateChildValues(atomicUpdates)
        } catch {
            dlog("❌ Firebase atomic write error: \(error)")
            dlog("   Error details: \(error.localizedDescription)")
            throw error
        }
        
        dlog("✅ Post created successfully in Realtime Database")
        
        // Create Post object for return
        let post = Post(
            id: UUID(uuidString: postId) ?? UUID(),
            firebaseId: postId,
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
        dlog("📥 Fetching user posts from Realtime Database for user: \(userId)")
        
        // Get list of post IDs for this user
        let snapshot = try await database.child("user_posts").child(userId).getData()
        
        guard snapshot.exists(), let postDict = snapshot.value as? [String: Any] else {
            dlog("⚠️ No posts found for user")
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
        
        dlog("✅ Fetched \(posts.count) posts for user")
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
        _ = postData["authorUsername"] as? String ?? ""
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
            firebaseId: postId,
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
        dlog("📥 Fetching \(category.rawValue) posts from Realtime Database (limit: \(limit))")
        
        // Get post IDs for category, ordered by timestamp
        let snapshot = try await database
            .child("category_posts")
            .child(category.rawValue)
            .queryOrderedByValue()
            .queryLimited(toLast: UInt(limit))
            .getData()
        
        guard snapshot.exists(), let postDict = snapshot.value as? [String: Any] else {
            dlog("⚠️ No posts found for category")
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
        
        dlog("✅ Fetched \(posts.count) posts for category: \(category.rawValue)")
        return posts
    }
    
    // MARK: - Update Post
    
    func updatePost(postId: String, content: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimePostService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        dlog("✏️ Updating post: \(postId)")
        
        // Ownership check — verify caller owns this post before writing
        let post = try await fetchPost(postId: postId)
        guard post.authorId == currentUser.uid else {
            throw NSError(domain: "RealtimePostService", code: 403, userInfo: [NSLocalizedDescriptionKey: "You can only edit your own posts"])
        }
        
        let updates: [String: Any] = [
            "posts/\(postId)/content": content,
            "posts/\(postId)/updatedAt": Date().timeIntervalSince1970
        ]
        
        try await database.updateChildValues(updates)
        dlog("✅ Post updated successfully")
    }
    
    // MARK: - Delete Post
    
    func deletePost(postId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimePostService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        dlog("🗑️ Deleting post: \(postId)")
        
        // Fetch post to get authorId and category before deleting
        let post = try await fetchPost(postId: postId)
        
        // Ownership check — only the post author may delete
        guard post.authorId == currentUser.uid else {
            throw NSError(domain: "RealtimePostService", code: 403, userInfo: [NSLocalizedDescriptionKey: "You can only delete your own posts"])
        }
        
        // Use post.authorId (not currentUser.uid) to correctly target the user_posts index
        let updates: [String: Any?] = [
            "posts/\(postId)": nil,
            "user_posts/\(post.authorId)/\(postId)": nil,
            "category_posts/\(post.category.rawValue)/\(postId)": nil,
            "post_stats/\(postId)": nil,
            "post_interactions/\(postId)": nil,
            "comments/\(postId)": nil
        ]
        
        try await database.updateChildValues(updates as [AnyHashable: Any])
        dlog("✅ Post deleted successfully")
    }
    
    // MARK: - Real-time Listener for User Posts
    
    func observeUserPosts(userId: String, completion: @escaping ([Post]) -> Void) {
        dlog("👂 Setting up real-time listener for user posts: \(userId)")
        
        let taskKey = "userPosts:\(userId)"
        let query = database.child("user_posts").child(userId)
        
        let handle = query.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            // Cancel any in-flight refresh for this observer before starting a new one
            self.observerTasks[taskKey]?.cancel()
            self.observerTasks[taskKey] = Task {
                guard snapshot.exists(), let postDict = snapshot.value as? [String: Any] else {
                    completion([])
                    return
                }
                
                var posts: [Post] = []
                for (postId, _) in postDict {
                    guard !Task.isCancelled else { return }
                    do {
                        let post = try await self.fetchPost(postId: postId)
                        posts.append(post)
                    } catch {
                        dlog("⚠️ Failed to fetch post \(postId): \(error)")
                    }
                }
                
                guard !Task.isCancelled else { return }
                posts.sort { $0.createdAt > $1.createdAt }
                dlog("🔄 Real-time update: \(posts.count) user posts")
                completion(posts)
            }
        }
        
        appendListenerToken(ListenerToken(query: query, handle: handle))
    }

    // MARK: - Real-time Listener for Category Posts
    
    func observeCategoryPosts(category: Post.PostCategory, limit: Int = 50, completion: @escaping ([Post]) -> Void) {
        dlog("👂 Setting up real-time listener for \(category.rawValue) posts")
        
        let taskKey = "categoryPosts:\(category.rawValue)"
        let query = database
            .child("category_posts")
            .child(category.rawValue)
            .queryOrderedByValue()
            .queryLimited(toLast: UInt(limit))
        
        let handle = query.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            // Cancel any in-flight refresh for this observer before starting a new one
            self.observerTasks[taskKey]?.cancel()
            self.observerTasks[taskKey] = Task {
                guard snapshot.exists(), let postDict = snapshot.value as? [String: Any] else {
                    completion([])
                    return
                }
                
                var posts: [Post] = []
                for (postId, _) in postDict {
                    guard !Task.isCancelled else { return }
                    do {
                        let post = try await self.fetchPost(postId: postId)
                        posts.append(post)
                    } catch {
                        dlog("⚠️ Failed to fetch post \(postId): \(error)")
                    }
                }
                
                guard !Task.isCancelled else { return }
                posts.sort { $0.createdAt > $1.createdAt }
                dlog("🔄 Real-time update: \(posts.count) \(category.rawValue) posts")
                completion(posts)
            }
        }

        appendListenerToken(ListenerToken(query: query, handle: handle))
    }


    // MARK: - Remove Listeners

    /// Cancels all in-flight refresh tasks and removes every RTDB observer.
    /// Call this on logout or when the owning screen disappears.
    func stopAllObserving() {
        // Cancel all pending actor-isolated fetch tasks
        for (_, task) in observerTasks { task.cancel() }
        observerTasks.removeAll()
        // Delegate token removal to the nonisolated helper (safe from any context)
        removeAllListenerTokens()
    }

    /// Removes every RTDB observer from the exact query it was registered on.
    /// `nonisolated` so it can be called from `deinit` without hopping to the actor.
    nonisolated func removeAllListenerTokens() {
        listenersLock.lock()
        let snapshot = listenerTokens
        listenerTokens.removeAll()
        listenersLock.unlock()

        for token in snapshot {
            token.query.removeObserver(withHandle: token.handle)
        }
        dlog("🔇 All real-time listeners removed")
    }

    private func appendListenerToken(_ token: ListenerToken) {
        listenersLock.lock()
        listenerTokens.append(token)
        listenersLock.unlock()
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
