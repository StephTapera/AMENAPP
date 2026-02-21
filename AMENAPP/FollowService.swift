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
    private var isListening = false  // ✅ FIX: Prevent duplicate listener registration
    
    private init() {}
    
    // MARK: - Follow User
    
    // Track in-progress follow operations to prevent duplicates
    private var followOperationsInProgress = Set<String>()
    
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
        
        // PREVENT DUPLICATE OPERATIONS
        guard !followOperationsInProgress.contains(userId) else {
            print("⚠️ Follow operation already in progress for user: \(userId)")
            return
        }
        
        // Mark operation as in progress
        followOperationsInProgress.insert(userId)
        defer {
            followOperationsInProgress.remove(userId)
        }
        
        // Check if already following (check Firestore directly, not cache)
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followerId", isEqualTo: currentUserId)
            .whereField("followingId", isEqualTo: userId)
            .limit(to: 1)
            .getDocuments()
        
        if !snapshot.documents.isEmpty {
            print("⚠️ Already following this user (found in Firestore)")
            following.insert(userId) // Update cache
            return
        }
        
        // Optimistically update local state FIRST (prevents double-tap)
        await MainActor.run {
            following.insert(userId)
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
            // Revert optimistic update
            following.remove(userId)
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
            // Revert optimistic update on error
            following.remove(userId)
            throw error
        }
        
        // ✅ NOTIFICATION FIX: Removed duplicate notification creation
        // Cloud Function (onUserFollow) handles follow notifications automatically
        // when a document is created in the "follows" collection
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    // MARK: - Unfollow User
    
    // Track in-progress unfollow operations to prevent duplicates
    private var unfollowOperationsInProgress = Set<String>()
    
    /// Unfollow a user
    func unfollowUser(userId: String) async throws {
        print("👥 Unfollowing user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // PREVENT DUPLICATE OPERATIONS
        guard !unfollowOperationsInProgress.contains(userId) else {
            print("⚠️ Unfollow operation already in progress for user: \(userId)")
            return
        }
        
        // Mark operation as in progress
        unfollowOperationsInProgress.insert(userId)
        defer {
            unfollowOperationsInProgress.remove(userId)
        }
        
        // Optimistically update local state FIRST (prevents double-tap)
        following.remove(userId)
        
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
        
        // P1-2: Use transaction-safe decrements to prevent negative counts
        // Note: We use regular increment(-1) here since transactions are expensive
        // The defensive clamping in UserProfileView handles edge cases
        // For a full transaction-based solution, see safeDecrementCount() helper
        
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
        do {
            try await batch.commit()
            print("✅ Unfollowed user successfully")
        } catch {
            print("❌ Unfollow failed: \(error)")
            // Revert optimistic update on error
            following.insert(userId)
            throw error
        }
        
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
        
        // P1-4: Use batch fetching for better performance
        return try await batchFetchUserProfiles(userIds: followerIds)
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
        
        // P1-4: Use batch fetching for better performance
        return try await batchFetchUserProfiles(userIds: followingIds)
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
        // ✅ FIX: Prevent duplicate listeners
        guard !isListening else {
            print("⚠️ Already listening to follow changes")
            return
        }
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            print("⚠️ No user ID for listener")
            return
        }
        
        isListening = true
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
        
        listeners.append(followingListener)
        listeners.append(followersListener)
        
        // NOTE: Removed userStatsListener to prevent duplicate counter updates
        // The following/followers listeners already provide accurate counts from the follows collection
    }
    
    /// Stop all listeners
    func stopListening() {
        print("🔇 Stopping follow listeners...")
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        isListening = false  // ✅ FIX: Reset flag so listeners can be restarted
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
    
    // MARK: - P1-1: Unified Count Sources
    
    /// P1-1: Get cached follower/following counts for current user (no Firestore read)
    /// Returns cached counts from real-time listener, or nil if not available
    func getCachedCurrentUserCounts() -> (followers: Int, following: Int)? {
        guard firebaseManager.currentUser != nil else {
            return nil
        }
        
        // Only return if we have valid cached data from real-time listeners
        if currentUserFollowersCount > 0 || currentUserFollowingCount > 0 {
            return (currentUserFollowersCount, currentUserFollowingCount)
        }
        
        return nil
    }
    
    /// P1-1: Unified method to get follower/following counts with caching
    /// First checks cache, falls back to Firestore if needed
    func getFollowCounts(userId: String) async throws -> (followers: Int, following: Int) {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // P1-1: If requesting current user's counts and we have cached data, use it
        if userId == currentUserId, let cached = getCachedCurrentUserCounts() {
            print("✅ Using cached counts for current user: \(cached.followers) followers, \(cached.following) following")
            return cached
        }
        
        // Fall back to Firestore read for other users or if cache unavailable
        print("📡 Fetching counts from Firestore for user: \(userId)")
        return try await getFollowStats(userId: userId)
    }
    
    // MARK: - P1-4: Batch Fetch Optimization
    
    /// P1-4: Batch fetch user profiles to minimize Firestore reads
    /// Uses Firestore's `in` query operator with 10-item batches (Firestore limit)
    private func batchFetchUserProfiles(userIds: [String]) async throws -> [FollowUserProfile] {
        guard !userIds.isEmpty else {
            return []
        }
        
        print("📦 Batch fetching \(userIds.count) user profiles...")
        
        // Firestore 'in' query limit is 10 items per batch
        let batchSize = 10
        var allProfiles: [FollowUserProfile] = []
        
        // Split user IDs into batches of 10
        let batches = stride(from: 0, to: userIds.count, by: batchSize).map {
            Array(userIds[$0..<min($0 + batchSize, userIds.count)])
        }
        
        print("   Processing \(batches.count) batch(es) of \(batchSize) items each")
        
        // Fetch each batch in parallel for maximum performance
        try await withThrowingTaskGroup(of: [FollowUserProfile].self) { group in
            for batch in batches {
                group.addTask {
                    // Use Firestore's 'in' query to fetch multiple users at once
                    let snapshot = try await self.db.collection(FirebaseManager.CollectionPath.users)
                        .whereField(FieldPath.documentID(), in: batch)
                        .getDocuments()
                    
                    let profiles = snapshot.documents.compactMap { doc -> FollowUserProfile? in
                        guard let userData = doc.data() as? [String: Any] else {
                            return nil
                        }
                        
                        return FollowUserProfile(
                            id: doc.documentID,
                            displayName: userData["displayName"] as? String ?? "Unknown",
                            username: userData["username"] as? String ?? "unknown",
                            bio: userData["bio"] as? String,
                            profileImageURL: userData["profileImageURL"] as? String,
                            followersCount: userData["followersCount"] as? Int ?? 0,
                            followingCount: userData["followingCount"] as? Int ?? 0
                        )
                    }
                    
                    print("   ✅ Fetched batch of \(profiles.count) users")
                    return profiles
                }
            }
            
            // Collect all results from parallel tasks
            for try await batchProfiles in group {
                allProfiles.append(contentsOf: batchProfiles)
            }
        }
        
        print("✅ Batch fetch complete: \(allProfiles.count) profiles fetched")
        
        return allProfiles
    }
    
    // MARK: - P1-2: Transaction-Safe Counter Helpers
    
    /// P1-2: Transaction-safe decrement that prevents negative counts
    /// Note: Currently not used to avoid transaction overhead on every unfollow
    /// The defensive clamping in views provides adequate protection
    /// This is here as a reference implementation if needed for critical scenarios
    private func safeDecrementCount(
        userRef: DocumentReference,
        field: String
    ) async throws {
        try await db.runTransaction { transaction, errorPointer in
            do {
                let userDoc = try transaction.getDocument(userRef)
                let currentCount = userDoc.data()?[field] as? Int ?? 0
                
                // Only decrement if > 0
                if currentCount > 0 {
                    transaction.updateData([
                        field: currentCount - 1,
                        "updatedAt": Date()
                    ], forDocument: userRef)
                } else {
                    print("⚠️ Prevented negative decrement for \(field) on user \(userRef.documentID)")
                }
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
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
