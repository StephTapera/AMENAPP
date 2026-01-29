//
//  FollowService.swift
//  AMENAPP
//
//  Created by Steph on 1/21/26.
//
//  Service for managing follow/unfollow relationships between users
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Follow Model

struct Follow: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var followerId: String      // User who is following
    var followingId: String     // User being followed
    var createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case followerId
        case followingId
        case createdAt
    }
    
    init(
        id: String? = nil,
        followerId: String,
        followingId: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.followerId = followerId
        self.followingId = followingId
        self.createdAt = createdAt
    }
}

// MARK: - Follow Service

@MainActor
class FollowService: ObservableObject {
    static let shared = FollowService()
    
    @Published var following: Set<String> = []       // User IDs you're following
    @Published var followers: Set<String> = []        // User IDs following you
    @Published var followingList: [FollowUserProfile] = [] // Full user objects
    @Published var followersList: [FollowUserProfile] = [] // Full user objects
    @Published var isLoading = false
    @Published var error: String?
    
    // Real-time follow counts for current user
    @Published var currentUserFollowersCount: Int = 0
    @Published var currentUserFollowingCount: Int = 0
    
    private let firebaseManager = FirebaseManager.shared
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    
    private init() {}
    
    // MARK: - Follow User
    
    /// Follow a user
    func followUser(userId: String) async throws {
        print("👥 Following user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            print("❌ Not authenticated - cannot follow user")
            throw FirebaseError.unauthorized
        }
        
        print("   Current user ID: \(currentUserId)")
        print("   Target user ID: \(userId)")
        
        // Don't follow yourself
        guard userId != currentUserId else {
            print("⚠️ Cannot follow yourself")
            return
        }
        
        // Check if already following
        if await isFollowing(userId: userId) {
            print("⚠️ Already following this user")
            return
        }
        
        // Create follow relationship
        let follow = Follow(
            followerId: currentUserId,
            followingId: userId
        )
        
        print("   Creating follow relationship...")
        
        // Use batch write for atomicity
        let batch = db.batch()
        
        // 1. Add to follows collection
        let followRef = db.collection(FirebaseManager.CollectionPath.follows).document()
        do {
            try batch.setData(from: follow, forDocument: followRef)
        } catch {
            print("❌ Failed to encode follow data: \(error)")
            throw error
        }
        
        // 2. Increment follower count on target user
        let targetUserRef = db.collection(FirebaseManager.CollectionPath.users).document(userId)
        batch.updateData([
            "followersCount": FieldValue.increment(Int64(1)),
            "updatedAt": Date()
        ], forDocument: targetUserRef)
        
        // 3. Increment following count on current user
        let currentUserRef = db.collection(FirebaseManager.CollectionPath.users).document(currentUserId)
        batch.updateData([
            "followingCount": FieldValue.increment(Int64(1)),
            "updatedAt": Date()
        ], forDocument: currentUserRef)
        
        // Commit batch
        do {
            print("   Committing batch write...")
            try await batch.commit()
            print("✅ Followed user successfully")
        } catch {
            print("❌ Batch commit failed: \(error)")
            print("   Error details: \((error as NSError).localizedDescription)")
            throw error
        }
        
        // Update local state
        following.insert(userId)
        
        // Create notification for followed user
        try? await createFollowNotification(userId: userId)
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    // MARK: - Unfollow User
    
    /// Unfollow a user
    func unfollowUser(userId: String) async throws {
        print("👥 Unfollowing user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Find the follow relationship
        let followQuery = db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followerId", isEqualTo: currentUserId)
            .whereField("followingId", isEqualTo: userId)
            .limit(to: 1)
        
        let snapshot = try await followQuery.getDocuments()
        
        guard let followDoc = snapshot.documents.first else {
            print("⚠️ Not following this user")
            return
        }
        
        // Use batch write for atomicity
        let batch = db.batch()
        
        // 1. Delete follow relationship
        batch.deleteDocument(followDoc.reference)
        
        // 2. Decrement follower count on target user
        let targetUserRef = db.collection(FirebaseManager.CollectionPath.users).document(userId)
        batch.updateData([
            "followersCount": FieldValue.increment(Int64(-1)),
            "updatedAt": Date()
        ], forDocument: targetUserRef)
        
        // 3. Decrement following count on current user
        let currentUserRef = db.collection(FirebaseManager.CollectionPath.users).document(currentUserId)
        batch.updateData([
            "followingCount": FieldValue.increment(Int64(-1)),
            "updatedAt": Date()
        ], forDocument: currentUserRef)
        
        // Commit batch
        try await batch.commit()
        
        print("✅ Unfollowed user successfully")
        
        // Update local state
        following.remove(userId)
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    // MARK: - Toggle Follow
    
    /// Toggle follow status (follow if not following, unfollow if following)
    func toggleFollow(userId: String) async throws {
        if await isFollowing(userId: userId) {
            try await unfollowUser(userId: userId)
        } else {
            try await followUser(userId: userId)
        }
    }
    
    // MARK: - Check Follow Status
    
    /// Check if current user is following another user
    func isFollowing(userId: String) async -> Bool {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            return false
        }
        
        // Check local cache first
        if following.contains(userId) {
            return true
        }
        
        // Check Firestore
        do {
            let snapshot = try await db.collection(FirebaseManager.CollectionPath.follows)
                .whereField("followerId", isEqualTo: currentUserId)
                .whereField("followingId", isEqualTo: userId)
                .limit(to: 1)
                .getDocuments()
            
            let isFollowing = !snapshot.documents.isEmpty
            
            if isFollowing {
                following.insert(userId)
            }
            
            return isFollowing
        } catch {
            print("❌ Error checking follow status: \(error)")
            return false
        }
    }
    
    // MARK: - Fetch Followers
    
    /// Fetch all followers for a user (returns user IDs)
    func fetchFollowerIds(userId: String) async throws -> [String] {
        print("📥 Fetching followers for user: \(userId)")
        
        // Query without ordering to avoid index requirement
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followingId", isEqualTo: userId)
            .getDocuments()
        
        let followerIds = snapshot.documents.compactMap { $0.data()["followerId"] as? String }
        
        print("✅ Fetched \(followerIds.count) followers")
        
        return followerIds
    }
    
    /// Fetch followers with full user data
    func fetchFollowers(userId: String) async throws -> [FollowUserProfile] {
        let followerIds = try await fetchFollowerIds(userId: userId)
        
        var followers: [FollowUserProfile] = []
        
        for followerId in followerIds {
            if let userDoc = try? await db.collection(FirebaseManager.CollectionPath.users)
                .document(followerId)
                .getDocument(),
               let userData = userDoc.data() {
                
                let userProfile = FollowUserProfile(
                    id: followerId,
                    displayName: userData["displayName"] as? String ?? "Unknown",
                    username: userData["username"] as? String ?? "unknown",
                    bio: userData["bio"] as? String,
                    profileImageURL: userData["profileImageURL"] as? String,
                    followersCount: userData["followersCount"] as? Int ?? 0,
                    followingCount: userData["followingCount"] as? Int ?? 0
                )
                
                followers.append(userProfile)
            }
        }
        
        return followers
    }
    
    /// Fetch basic user info for a single user (lightweight)
    func fetchUserBasicInfo(userId: String) async throws -> UserBasicInfo {
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(userId)
            .getDocument()
        
        guard let userData = userDoc.data() else {
            throw NSError(domain: "FollowService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        return UserBasicInfo(
            id: userId,
            displayName: userData["displayName"] as? String ?? "Unknown User",
            username: userData["username"] as? String ?? "unknown",
            profileImageURL: userData["profileImageURL"] as? String
        )
    }
    
    /// Remove a follower (current user removes someone from their followers list)
    func removeFollower(followerId: String) async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("👥 Removing follower: \(followerId)")
        
        // Find the follow relationship where they follow you
        let followQuery = db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followerId", isEqualTo: followerId)
            .whereField("followingId", isEqualTo: currentUserId)
            .limit(to: 1)
        
        let snapshot = try await followQuery.getDocuments()
        
        guard let followDoc = snapshot.documents.first else {
            print("⚠️ No follow relationship found")
            return
        }
        
        // Use batch write
        let batch = db.batch()
        
        // 1. Delete follow relationship
        batch.deleteDocument(followDoc.reference)
        
        // 2. Decrement follower count on current user
        let currentUserRef = db.collection(FirebaseManager.CollectionPath.users).document(currentUserId)
        batch.updateData([
            "followersCount": FieldValue.increment(Int64(-1)),
            "updatedAt": Date()
        ], forDocument: currentUserRef)
        
        // 3. Decrement following count on the follower
        let followerRef = db.collection(FirebaseManager.CollectionPath.users).document(followerId)
        batch.updateData([
            "followingCount": FieldValue.increment(Int64(-1)),
            "updatedAt": Date()
        ], forDocument: followerRef)
        
        // Commit batch
        try await batch.commit()
        
        print("✅ Follower removed successfully")
    }
    
    // MARK: - Fetch Following
    
    /// Fetch all users that a user is following (returns user IDs)
    func fetchFollowingIds(userId: String) async throws -> [String] {
        print("📥 Fetching following for user: \(userId)")
        
        // Query without ordering to avoid index requirement
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followerId", isEqualTo: userId)
            .getDocuments()
        
        let followingIds = snapshot.documents.compactMap { $0.data()["followingId"] as? String }
        
        print("✅ Fetched \(followingIds.count) following")
        
        return followingIds
    }
    
    /// Fetch following with full user data
    func fetchFollowing(userId: String) async throws -> [FollowUserProfile] {
        let followingIds = try await fetchFollowingIds(userId: userId)
        
        var followingList: [FollowUserProfile] = []
        
        for followingId in followingIds {
            if let userDoc = try? await db.collection(FirebaseManager.CollectionPath.users)
                .document(followingId)
                .getDocument(),
               let userData = userDoc.data() {
                
                let userProfile = FollowUserProfile(
                    id: followingId,
                    displayName: userData["displayName"] as? String ?? "Unknown",
                    username: userData["username"] as? String ?? "unknown",
                    bio: userData["bio"] as? String,
                    profileImageURL: userData["profileImageURL"] as? String,
                    followersCount: userData["followersCount"] as? Int ?? 0,
                    followingCount: userData["followingCount"] as? Int ?? 0
                )
                
                followingList.append(userProfile)
            }
        }
        
        return followingList
    }
    
    // MARK: - Load Current User's Data
    
    /// Load current user's following list into cache
    func loadCurrentUserFollowing() async {
        guard let currentUserId = firebaseManager.currentUser?.uid else { return }
        
        do {
            let followingIds = try await fetchFollowingIds(userId: currentUserId)
            following = Set(followingIds)
            print("✅ Loaded \(followingIds.count) following into cache")
        } catch {
            print("❌ Failed to load following: \(error)")
        }
    }
    
    /// Load current user's followers list into cache
    func loadCurrentUserFollowers() async {
        guard let currentUserId = firebaseManager.currentUser?.uid else { return }
        
        do {
            let followerIds = try await fetchFollowerIds(userId: currentUserId)
            followers = Set(followerIds)
            print("✅ Loaded \(followerIds.count) followers into cache")
        } catch {
            print("❌ Failed to load followers: \(error)")
        }
    }
    
    // MARK: - Mutual Follows
    
    /// Check if two users follow each other
    func areMutualFollowers(userId: String) async -> Bool {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            return false
        }
        
        let youFollowThem = await isFollowing(userId: userId)
        
        // Check if they follow you
        do {
            let snapshot = try await db.collection(FirebaseManager.CollectionPath.follows)
                .whereField("followerId", isEqualTo: userId)
                .whereField("followingId", isEqualTo: currentUserId)
                .limit(to: 1)
                .getDocuments()
            
            let theyFollowYou = !snapshot.documents.isEmpty
            
            return youFollowThem && theyFollowYou
        } catch {
            return false
        }
    }
    
    // MARK: - Real-time Listeners
    
    /// Start listening to current user's following list
    func startListening() {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            print("⚠️ No user ID for listener")
            return
        }
        
        print("🔊 Starting real-time listener for follows...")
        
        // Listen to following
        let followingListener = db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followerId", isEqualTo: currentUserId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Following listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let followingIds = snapshot.documents.compactMap { doc -> String? in
                    doc.data()["followingId"] as? String
                }
                
                Task { @MainActor in
                    self.following = Set(followingIds)
                    self.currentUserFollowingCount = followingIds.count
                    print("✅ Real-time update: \(followingIds.count) following")
                }
            }
        
        // Listen to followers
        let followersListener = db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followingId", isEqualTo: currentUserId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Followers listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let followerIds = snapshot.documents.compactMap { doc -> String? in
                    doc.data()["followerId"] as? String
                }
                
                Task { @MainActor in
                    self.followers = Set(followerIds)
                    self.currentUserFollowersCount = followerIds.count
                    print("✅ Real-time update: \(followerIds.count) followers")
                }
            }
        
        // Listen to current user's document for count updates
        let userStatsListener = db.collection(FirebaseManager.CollectionPath.users)
            .document(currentUserId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ User stats listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot, let data = snapshot.data() else { return }
                
                let followersCount = data["followersCount"] as? Int ?? 0
                let followingCount = data["followingCount"] as? Int ?? 0
                
                Task { @MainActor in
                    self.currentUserFollowersCount = followersCount
                    self.currentUserFollowingCount = followingCount
                    print("✅ Real-time stats: \(followersCount) followers, \(followingCount) following")
                }
            }
        
        listeners.append(followingListener)
        listeners.append(followersListener)
        listeners.append(userStatsListener)
    }
    
    /// Stop all listeners
    func stopListening() {
        print("🔇 Stopping follow listeners...")
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    // MARK: - Notifications
    
    private func createFollowNotification(userId: String) async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else { return }
        
        // Fetch current user's name
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(currentUserId)
            .getDocument()
        
        let displayName = userDoc.data()?["displayName"] as? String ?? "Someone"
        
        let notification: [String: Any] = [
            "userId": userId,
            "type": "follow",
            "fromUserId": currentUserId,
            "fromUserName": displayName,
            "message": "\(displayName) started following you",
            "createdAt": Date(),
            "isRead": false
        ]
        
        try await db.collection("notifications").addDocument(data: notification)
        
        print("✅ Follow notification created for user: \(userId)")
    }
    
    // MARK: - Bulk Operations
    
    /// Get follow statistics
    func getFollowStats(userId: String) async throws -> (followers: Int, following: Int) {
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(userId)
            .getDocument()
        
        let followersCount = userDoc.data()?["followersCount"] as? Int ?? 0
        let followingCount = userDoc.data()?["followingCount"] as? Int ?? 0
        
        return (followersCount, followingCount)
    }
}

// MARK: - Follow User Profile Model (for follow lists)

struct FollowUserProfile: Identifiable, Codable {
    let id: String
    let displayName: String
    let username: String
    let bio: String?
    let profileImageURL: String?
    let followersCount: Int
    let followingCount: Int
    
    var initials: String {
        displayName
            .components(separatedBy: " ")
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
            .prefix(2)
            .uppercased()
    }
}

// MARK: - User Basic Info Model (for followers/following lists)

struct UserBasicInfo: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let username: String
    let profileImageURL: String?
    
    var initials: String {
        displayName
            .components(separatedBy: " ")
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
            .prefix(2)
            .uppercased()
    }
    
    init(id: String, displayName: String, username: String, profileImageURL: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.profileImageURL = profileImageURL
    }
}

// MARK: - Firestore Collection Path Extension

extension FirebaseManager.CollectionPath {
    static let follows = "follows"
}
