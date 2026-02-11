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
    
    private let database = Database.database(url: "https://amen-5e359-default-rtdb.firebaseio.com")
    private var repostObservers: [String: DatabaseHandle] = [:]
    
    private init() {
        print("🔄 RealtimeRepostsService initialized")
    }
    
    // MARK: - Repost Actions
    
    /// Repost a post
    func repostPost(postId: UUID, originalPost: Post) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "RealtimeRepostsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let timestamp = Date().timeIntervalSince1970
        
        // 1. Add to user's reposts list
        let userRepostRef = database.reference()
            .child("user-reposts")
            .child(userId)
            .child(postId.uuidString)
        
        let repostData: [String: Any] = [
            "postId": postId.uuidString,
            "originalAuthorId": originalPost.authorId,
            "timestamp": timestamp,
            "repostedAt": timestamp
        ]
        
        try await userRepostRef.setValue(repostData)
        
        // 2. Increment repost count on the original post
        let postRepostCountRef = database.reference()
            .child("posts")
            .child(postId.uuidString)
            .child("repostCount")
        
        try await postRepostCountRef.runTransactionBlock { currentData in
            if let count = currentData.value as? Int {
                currentData.value = count + 1
            } else {
                currentData.value = 1
            }
            return TransactionResult.success(withValue: currentData)
        }
        
        // 3. Add to global reposts tracking
        let globalRepostRef = database.reference()
            .child("post-reposts")
            .child(postId.uuidString)
            .child(userId)
        
        try await globalRepostRef.setValue([
            "timestamp": timestamp,
            "userId": userId
        ])
        
        // Update local cache
        repostedPostIds.insert(postId)
        
        print("✅ Post reposted successfully: \(postId)")
        
        // Send notification
        NotificationCenter.default.post(
            name: Notification.Name("postReposted"),
            object: nil,
            userInfo: ["post": originalPost, "postId": postId]
        )
    }
    
    /// Undo repost
    func undoRepost(postId: UUID) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "RealtimeRepostsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // 1. Remove from user's reposts list
        let userRepostRef = database.reference()
            .child("user-reposts")
            .child(userId)
            .child(postId.uuidString)
        
        try await userRepostRef.removeValue()
        
        // 2. Decrement repost count on the original post
        let postRepostCountRef = database.reference()
            .child("posts")
            .child(postId.uuidString)
            .child("repostCount")
        
        try await postRepostCountRef.runTransactionBlock { currentData in
            if let count = currentData.value as? Int, count > 0 {
                currentData.value = count - 1
            } else {
                currentData.value = 0
            }
            return TransactionResult.success(withValue: currentData)
        }
        
        // 3. Remove from global reposts tracking
        let globalRepostRef = database.reference()
            .child("post-reposts")
            .child(postId.uuidString)
            .child(userId)
        
        try await globalRepostRef.removeValue()
        
        // Update local cache
        repostedPostIds.remove(postId)
        
        print("✅ Repost undone: \(postId)")
        
        // Send notification
        NotificationCenter.default.post(
            name: Notification.Name("postUnreposted"),
            object: nil,
            userInfo: ["postId": postId]
        )
    }
    
    /// Check if user has reposted a post
    func hasReposted(postId: UUID) async throws -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else {
            return false
        }
        
        // Check local cache first for better performance
        if repostedPostIds.contains(postId) {
            return true
        }
        
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
            print("📭 No reposts found for user: \(targetUserId)")
            return []
        }
        
        // Extract post IDs
        let postIds = Array(repostsData.keys)
        print("📬 Found \(postIds.count) reposts for user: \(targetUserId)")
        
        // Fetch full post details for each reposted post
        var posts: [Post] = []
        
        for postId in postIds {
            do {
                let postRef = database.reference().child("posts").child(postId)
                let postSnapshot = try await postRef.getData()
                
                if postSnapshot.exists(), let postData = postSnapshot.value as? [String: Any] {
                    if let post = self.parsePost(from: postData, postId: postId) {
                        posts.append(post)
                    }
                }
            } catch {
                print("⚠️ Error fetching reposted post \(postId): \(error)")
            }
        }
        
        // Sort by repost timestamp (most recent first)
        posts.sort { post1, post2 in
            if let repost1Data = repostsData[post1.id.uuidString] as? [String: Any],
               let timestamp1 = repost1Data["timestamp"] as? Double,
               let repost2Data = repostsData[post2.id.uuidString] as? [String: Any],
               let timestamp2 = repost2Data["timestamp"] as? Double {
                return timestamp1 > timestamp2
            }
            return post1.createdAt > post2.createdAt
        }
        
        print("✅ Fetched \(posts.count) reposted posts")
        return posts
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
        let authorProfileImageURL = data["authorProfileImageURL"] as? String
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
            authorProfileImageURL: authorProfileImageURL,
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
