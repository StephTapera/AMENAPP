//
//  RealtimeRepostsService.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/26/26.
//
//  Service for managing reposts in Firebase Realtime Database
//

import Foundation
import FirebaseDatabase
import FirebaseAuth
import Combine

@MainActor
class RealtimeRepostsService: ObservableObject {
    static let shared = RealtimeRepostsService()
    
    @Published var repostedPostIds: Set<UUID> = []
    
    private let database = Database.database()
    private var repostObservers: [String: DatabaseHandle] = [:]
    
    private init() {}
    
    // MARK: - Repost Actions
    
    /// Repost a post
    /// - Parameters:
    ///   - postId: The UUID of the post (for backwards compatibility)
    ///   - originalPost: The post being reposted
    /// ✅ FIXED: Now uses Firestore ID instead of full UUID for consistency
    func repostPost(postId: UUID, originalPost: Post) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "RealtimeRepostsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let timestamp = Date().timeIntervalSince1970
        
        // ✅ Use the short Firestore ID instead of full UUID
        let firestoreId = originalPost.firestoreId
        
        // 1. Add to user's reposts list
        let userRepostRef = database.reference()
            .child("user-reposts")
            .child(userId)
            .child(firestoreId)
        
        let repostData: [String: Any] = [
            "postId": firestoreId,  // ✅ Use Firestore ID
            "originalAuthorId": originalPost.authorId,
            "timestamp": timestamp,
            "repostedAt": timestamp
        ]
        
        try await userRepostRef.setValue(repostData)
        // Note: repostCount is maintained in Firestore by RepostService via FieldValue.increment().

        // 2. Add to global reposts tracking
        let globalRepostRef = database.reference()
            .child("post-reposts")
            .child(firestoreId)
            .child(userId)

        try await globalRepostRef.setValue([
            "timestamp": timestamp,
            "userId": userId
        ])

        // Update local cache
        repostedPostIds.insert(postId)

        // Notify ProfileView of the new repost
        NotificationCenter.default.post(
            name: Notification.Name("postReposted"),
            object: nil,
            userInfo: [
                "post": originalPost,
                "userId": userId
            ]
        )
    }
    
    /// Undo repost
    /// ✅ FIXED: Now accepts Firestore ID string instead of UUID
    func undoRepost(firestoreId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "RealtimeRepostsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // 1. Remove from user's reposts list
        let userRepostRef = database.reference()
            .child("user-reposts")
            .child(userId)
            .child(firestoreId)  // ✅ Use Firestore ID
        
        try await userRepostRef.removeValue()
        // Note: repostCount decrement is handled in Firestore by RepostService.
        // No RTDB write to /posts/{id}/repostCount — RTDB rules don't allow it.

        // 2. Remove from global reposts tracking
        let globalRepostRef = database.reference()
            .child("post-reposts")
            .child(firestoreId)  // ✅ Use Firestore ID
            .child(userId)
        
        try await globalRepostRef.removeValue()
        
        // Send notification
        NotificationCenter.default.post(
            name: Notification.Name("postUnreposted"),
            object: nil,
            userInfo: ["firestoreId": firestoreId]
        )
    }
    
    /// Check if user has reposted a post
    /// ⚠️ DEPRECATED: Use PostInteractionsService.hasReposted(postId: String) instead
    /// This function is kept for backward compatibility but should not be used
    func hasReposted(postId: UUID) async throws -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else {
            return false
        }
        
        // Check local cache first for better performance
        if repostedPostIds.contains(postId) {
            return true
        }
        
        // ⚠️ This will not work with new Firestore ID format
        // Use PostInteractionsService.hasReposted(postId: String) instead
        let repostRef = database.reference()
            .child("user-reposts")
            .child(userId)
            .child(postId.uuidString)
        
        let snapshot = try await repostRef.getData()
        let exists = snapshot.exists()
        
        // Update cache
        if exists {
            repostedPostIds.insert(postId)
        }
        
        return exists
    }
    
    // MARK: - Fetch Reposts
    
    /// Fetch all posts that the user has reposted
    func fetchUserReposts(userId: String? = nil) async throws -> [Post] {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        
        guard let targetUserId = targetUserId else {
            throw NSError(domain: "RealtimeRepostsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let repostsRef = database.reference()
            .child("user-reposts")
            .child(targetUserId)

        let snapshot = try await repostsRef.getData()

        guard snapshot.exists(), let repostsData = snapshot.value as? [String: Any] else {
            return []
        }

        let postIds = Array(repostsData.keys)
        guard !postIds.isEmpty else { return [] }

        // Fetch all reposted posts in parallel (fixes N+1 serial fetch pattern)
        let firestoreService = FirebasePostService.shared
        let posts: [Post] = await withTaskGroup(of: Post?.self) { group in
            for postId in postIds {
                group.addTask {
                    try? await firestoreService.fetchPostById(postId: postId)
                }
            }
            var result: [Post] = []
            for await post in group {
                if let post = post { result.append(post) }
            }
            return result
        }

        // Sort by repost timestamp (most recent first)
        return posts.sorted { post1, post2 in
            if let repost1Data = repostsData[post1.firestoreId] as? [String: Any],
               let timestamp1 = repost1Data["timestamp"] as? Double,
               let repost2Data = repostsData[post2.firestoreId] as? [String: Any],
               let timestamp2 = repost2Data["timestamp"] as? Double {
                return timestamp1 > timestamp2
            }
            return post1.createdAt > post2.createdAt
        }
    }
    
    // MARK: - Real-time Observers
    
    /// Observe user's reposts in real-time
    func observeUserReposts(userId: String? = nil, completion: @escaping ([Post]) -> Void) {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        
        guard let targetUserId = targetUserId else {
            print("❌ Cannot observe reposts: User not authenticated")
            return
        }
        
        let repostsRef = database.reference()
            .child("user-reposts")
            .child(targetUserId)
        
        let handle = repostsRef.observe(.value) { snapshot in
            Task {
                do {
                    let posts = try await self.fetchUserReposts(userId: targetUserId)
                    await MainActor.run {
                        completion(posts)
                    }
                } catch {
                    print("❌ Error observing reposts: \(error)")
                    await MainActor.run {
                        completion([])
                    }
                }
            }
        }
        
        repostObservers[targetUserId] = handle
        print("👀 Observing reposts for user: \(targetUserId)")
    }
    
    /// Remove observer
    func removeObserver(userId: String) {
        guard let handle = repostObservers[userId] else { return }
        
        let repostsRef = database.reference()
            .child("user-reposts")
            .child(userId)
        
        repostsRef.removeObserver(withHandle: handle)
        repostObservers.removeValue(forKey: userId)
        
        print("🔇 Removed reposts observer for user: \(userId)")
    }
    
    /// Stop ALL active repost observers — call on sign-out.
    func stopAllObservers() {
        let root = database.reference()
        for (userId, handle) in repostObservers {
            root.child("user-reposts").child(userId).removeObserver(withHandle: handle)
        }
        repostObservers.removeAll()
        repostedPostIds.removeAll()
    }
    
    // MARK: - Helper Methods
    
    private func parsePost(from data: [String: Any], postId: String) -> Post? {
        guard let content = data["content"] as? String,
              let authorId = data["authorId"] as? String,
              let authorName = data["authorName"] as? String,
              let authorInitials = data["authorInitials"] as? String,
              let categoryRaw = data["category"] as? String,
              let category = Post.PostCategory(rawValue: categoryRaw),
              let timestamp = data["createdAt"] as? Double else {
            print("⚠️ Invalid post data for postId: \(postId)")
            return nil
        }
        
        let createdAt = Date(timeIntervalSince1970: timestamp)
        let topicTag = data["topicTag"] as? String
        let amenCount = data["amenCount"] as? Int ?? 0
        let lightbulbCount = data["lightbulbCount"] as? Int ?? 0
        let commentCount = data["commentCount"] as? Int ?? 0
        let repostCount = data["repostCount"] as? Int ?? 0
        let timeAgo = data["timeAgo"] as? String ?? "Just now"
        let visibilityRaw = data["visibility"] as? String ?? "Everyone"
        let visibility = Post.PostVisibility(rawValue: visibilityRaw) ?? .everyone
        let allowComments = data["allowComments"] as? Bool ?? true
        let imageURLs = data["imageURLs"] as? [String]
        let linkURL = data["linkURL"] as? String
        let isRepost = data["isRepost"] as? Bool ?? false
        let originalAuthorName = data["originalAuthorName"] as? String
        let originalAuthorId = data["originalAuthorId"] as? String
        
        return Post(
            id: UUID(uuidString: postId) ?? UUID(),
            authorId: authorId,
            authorName: authorName,
            authorInitials: authorInitials,
            timeAgo: timeAgo,
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
            originalAuthorName: originalAuthorName,
            originalAuthorId: originalAuthorId
        )
    }
}
