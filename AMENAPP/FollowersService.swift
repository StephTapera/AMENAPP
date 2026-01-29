//
//  FollowersService.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/26/26.
//
//  Service for managing followers and following relationships
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore

// MARK: - Models

struct FollowUser: Identifiable, Codable {
    let id: String // User ID
    let name: String
    let username: String
    let initials: String
    let profileImageURL: String?
    let bio: String?
    let followersCount: Int
    let isFollowing: Bool // If current user is following this user
    let followedAt: Date? // When the follow happened
}

@MainActor
class FollowersService: ObservableObject {
    static let shared = FollowersService()
    
    private let database = Database.database(url: "https://amen-5e359-default-rtdb.firebaseio.com")
    private let firestore = Firestore.firestore()
    
    @Published var followers: [FollowUser] = []
    @Published var following: [FollowUser] = []
    @Published var isLoading = false
    
    private var followersObservers: [String: DatabaseHandle] = [:]
    private var followingObservers: [String: DatabaseHandle] = [:]
    
    private init() {
        print("👥 FollowersService initialized")
    }
    
    // MARK: - Follow Actions
    
    /// Follow a user
    func followUser(userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FollowersService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        guard currentUserId != userId else {
            throw NSError(domain: "FollowersService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Cannot follow yourself"])
        }
        
        let timestamp = Date().timeIntervalSince1970
        
        // 1. Add to current user's following list (Realtime DB)
        let followingRef = database.reference()
            .child("user-following")
            .child(currentUserId)
            .child(userId)
        
        try await followingRef.setValue([
            "timestamp": timestamp,
            "userId": userId
        ])
        
        // 2. Add to target user's followers list (Realtime DB)
        let followerRef = database.reference()
            .child("user-followers")
            .child(userId)
            .child(currentUserId)
        
        try await followerRef.setValue([
            "timestamp": timestamp,
            "userId": currentUserId
        ])
        
        // 3. Update follower counts in Firestore
        let currentUserDoc = firestore.collection("users").document(currentUserId)
        try await currentUserDoc.updateData([
            "followingCount": FieldValue.increment(Int64(1))
        ])
        
        let targetUserDoc = firestore.collection("users").document(userId)
        try await targetUserDoc.updateData([
            "followersCount": FieldValue.increment(Int64(1))
        ])
        
        print("✅ Followed user: \(userId)")
        
        // Send notification
        NotificationCenter.default.post(
            name: Notification.Name("userFollowed"),
            object: nil,
            userInfo: ["userId": userId]
        )
        
        // TODO: Create follow notification for the target user
        // await NotificationService.shared.createFollowNotification(from: currentUserId, to: userId)
    }
    
    /// Unfollow a user
    func unfollowUser(userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FollowersService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // 1. Remove from current user's following list
        let followingRef = database.reference()
            .child("user-following")
            .child(currentUserId)
            .child(userId)
        
        try await followingRef.removeValue()
        
        // 2. Remove from target user's followers list
        let followerRef = database.reference()
            .child("user-followers")
            .child(userId)
            .child(currentUserId)
        
        try await followerRef.removeValue()
        
        // 3. Update follower counts in Firestore
        let currentUserDoc = firestore.collection("users").document(currentUserId)
        try await currentUserDoc.updateData([
            "followingCount": FieldValue.increment(Int64(-1))
        ])
        
        let targetUserDoc = firestore.collection("users").document(userId)
        try await targetUserDoc.updateData([
            "followersCount": FieldValue.increment(Int64(-1))
        ])
        
        print("✅ Unfollowed user: \(userId)")
        
        // Send notification
        NotificationCenter.default.post(
            name: Notification.Name("userUnfollowed"),
            object: nil,
            userInfo: ["userId": userId]
        )
    }
    
    /// Check if current user is following another user
    func isFollowing(userId: String) async throws -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }
        
        let followingRef = database.reference()
            .child("user-following")
            .child(currentUserId)
            .child(userId)
        
        let snapshot = try await followingRef.getData()
        return snapshot.exists()
    }
    
    // MARK: - Fetch Followers/Following
    
    /// Fetch followers for a user
    func fetchFollowers(userId: String? = nil) async throws -> [FollowUser] {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        
        guard let targetUserId = targetUserId else {
            throw NSError(domain: "FollowersService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let followersRef = database.reference()
            .child("user-followers")
            .child(targetUserId)
        
        let snapshot = try await followersRef.getData()
        
        guard snapshot.exists(), let followersData = snapshot.value as? [String: Any] else {
            print("📭 No followers found")
            await MainActor.run {
                self.followers = []
            }
            return []
        }
        
        // Extract follower user IDs
        let followerIds = Array(followersData.keys)
        print("📬 Found \(followerIds.count) followers")
        
        // Fetch user details from Firestore
        var users: [FollowUser] = []
        
        for followerId in followerIds {
            do {
                let userDoc = try await firestore.collection("users").document(followerId).getDocument()
                
                if let userData = userDoc.data() {
                    let followerTimestamp = (followersData[followerId] as? [String: Any])?["timestamp"] as? Double
                    let followedAt = followerTimestamp != nil ? Date(timeIntervalSince1970: followerTimestamp!) : nil
                    
                    // Check if current user is following this follower
                    let isFollowingBack = try await isFollowing(userId: followerId)
                    
                    if let user = parseFollowUser(id: followerId, data: userData, isFollowing: isFollowingBack, followedAt: followedAt) {
                        users.append(user)
                    }
                }
            } catch {
                print("⚠️ Error fetching follower \(followerId): \(error)")
            }
        }
        
        // Sort by follow date (most recent first)
        users.sort { ($0.followedAt ?? Date.distantPast) > ($1.followedAt ?? Date.distantPast) }
        
        await MainActor.run {
            self.followers = users
        }
        
        print("✅ Fetched \(users.count) followers")
        return users
    }
    
    /// Fetch following list for a user
    func fetchFollowing(userId: String? = nil) async throws -> [FollowUser] {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        
        guard let targetUserId = targetUserId else {
            throw NSError(domain: "FollowersService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let followingRef = database.reference()
            .child("user-following")
            .child(targetUserId)
        
        let snapshot = try await followingRef.getData()
        
        guard snapshot.exists(), let followingData = snapshot.value as? [String: Any] else {
            print("📭 Not following anyone")
            await MainActor.run {
                self.following = []
            }
            return []
        }
        
        // Extract following user IDs
        let followingIds = Array(followingData.keys)
        print("📬 Following \(followingIds.count) users")
        
        // Fetch user details from Firestore
        var users: [FollowUser] = []
        
        for followingId in followingIds {
            do {
                let userDoc = try await firestore.collection("users").document(followingId).getDocument()
                
                if let userData = userDoc.data() {
                    let followTimestamp = (followingData[followingId] as? [String: Any])?["timestamp"] as? Double
                    let followedAt = followTimestamp != nil ? Date(timeIntervalSince1970: followTimestamp!) : nil
                    
                    if let user = parseFollowUser(id: followingId, data: userData, isFollowing: true, followedAt: followedAt) {
                        users.append(user)
                    }
                }
            } catch {
                print("⚠️ Error fetching following user \(followingId): \(error)")
            }
        }
        
        // Sort by follow date (most recent first)
        users.sort { ($0.followedAt ?? Date.distantPast) > ($1.followedAt ?? Date.distantPast) }
        
        await MainActor.run {
            self.following = users
        }
        
        print("✅ Fetched \(users.count) following users")
        return users
    }
    
    // MARK: - Real-time Observers
    
    /// Observe followers in real-time
    func observeFollowers(userId: String? = nil, completion: @escaping ([FollowUser]) -> Void) {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        
        guard let targetUserId = targetUserId else {
            print("❌ Cannot observe followers: User not authenticated")
            return
        }
        
        let followersRef = database.reference()
            .child("user-followers")
            .child(targetUserId)
        
        let handle = followersRef.observe(.value) { snapshot in
            Task {
                do {
                    let users = try await self.fetchFollowers(userId: targetUserId)
                    await MainActor.run {
                        completion(users)
                    }
                } catch {
                    print("❌ Error observing followers: \(error)")
                    await MainActor.run {
                        completion([])
                    }
                }
            }
        }
        
        followersObservers[targetUserId] = handle
        print("👀 Observing followers for user: \(targetUserId)")
    }
    
    /// Observe following list in real-time
    func observeFollowing(userId: String? = nil, completion: @escaping ([FollowUser]) -> Void) {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        
        guard let targetUserId = targetUserId else {
            print("❌ Cannot observe following: User not authenticated")
            return
        }
        
        let followingRef = database.reference()
            .child("user-following")
            .child(targetUserId)
        
        let handle = followingRef.observe(.value) { snapshot in
            Task {
                do {
                    let users = try await self.fetchFollowing(userId: targetUserId)
                    await MainActor.run {
                        completion(users)
                    }
                } catch {
                    print("❌ Error observing following: \(error)")
                    await MainActor.run {
                        completion([])
                    }
                }
            }
        }
        
        followingObservers[targetUserId] = handle
        print("👀 Observing following for user: \(targetUserId)")
    }
    
    /// Remove observers
    func removeObservers(userId: String) {
        // Remove followers observer
        if let handle = followersObservers[userId] {
            let followersRef = database.reference()
                .child("user-followers")
                .child(userId)
            followersRef.removeObserver(withHandle: handle)
            followersObservers.removeValue(forKey: userId)
        }
        
        // Remove following observer
        if let handle = followingObservers[userId] {
            let followingRef = database.reference()
                .child("user-following")
                .child(userId)
            followingRef.removeObserver(withHandle: handle)
            followingObservers.removeValue(forKey: userId)
        }
        
        print("🔇 Removed follow observers for user: \(userId)")
    }
    
    // MARK: - Helper Methods
    
    private func parseFollowUser(id: String, data: [String: Any], isFollowing: Bool, followedAt: Date?) -> FollowUser? {
        guard let name = data["displayName"] as? String,
              let username = data["username"] as? String else {
            return nil
        }
        
        let profileImageURL = data["profileImageURL"] as? String
        let bio = data["bio"] as? String
        let followersCount = data["followersCount"] as? Int ?? 0
        
        // Generate initials
        let names = name.components(separatedBy: " ")
        let initials = names.compactMap { $0.first }.map { String($0) }.joined().prefix(2).uppercased()
        
        return FollowUser(
            id: id,
            name: name,
            username: username,
            initials: String(initials),
            profileImageURL: profileImageURL,
            bio: bio,
            followersCount: followersCount,
            isFollowing: isFollowing,
            followedAt: followedAt
        )
    }
}
