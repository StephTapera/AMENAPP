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
    private var isListening = false  // Prevent duplicate listener registration

    // P0 CRASH FIX: Track the user ID for which follow data was last loaded.
    // The auth state listener can re-fire spuriously (token refresh, RTDB
    // reconnect), triggering duplicate loadCurrentUserFollowing/Followers()
    // calls that run concurrently with in-flight UI navigation, racing
    // @Published writes → CA layer hierarchy crash.
    // Reset on stopListening() so sign-out → sign-in reloads correctly.
    private var loadedForUserId: String?
    // Prevent two concurrent in-flight loads for the same user.
    private var isLoadingFollowData = false

    private init() {}
    
    // MARK: - Follow User
    
    // Track in-progress follow operations to prevent duplicates
    private var followOperationsInProgress = Set<String>()
    
    /// Follow a user
    func followUser(userId: String) async throws {
        dlog("👥 Following user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            dlog("❌ Not authenticated - cannot follow user")
            throw FirebaseError.unauthorized
        }
        
        dlog("   Current user ID: \(currentUserId)")
        dlog("   Target user ID: \(userId)")
        
        // Don't follow yourself
        guard userId != currentUserId else {
            dlog("⚠️ Cannot follow yourself")
            return
        }
        
        // ✅ CHECK RATE LIMIT FOR NEW ACCOUNTS
        let rateLimitCheck = await NewAccountRestrictionService.shared.canFollow(userId: currentUserId)
        guard rateLimitCheck.allowed else {
            if let reason = rateLimitCheck.reason {
                dlog("⚠️ Rate limit exceeded: \(reason)")
                await MainActor.run {
                    self.error = reason
                }
            }
            throw FirebaseError.rateLimitExceeded
        }
        
        // PREVENT DUPLICATE OPERATIONS
        guard !followOperationsInProgress.contains(userId) else {
            dlog("⚠️ Follow operation already in progress for user: \(userId)")
            return
        }
        
        // Mark operation as in progress
        followOperationsInProgress.insert(userId)
        defer {
            followOperationsInProgress.remove(userId)
        }
        
        // P1-6 FIX: Parallelize the two independent reads (existing-follow check + privacy lookup).
        // Previously these ran sequentially; running them concurrently cuts latency roughly in half.
        // The existingRequest check (3rd read) still depends on targetUserDoc so it stays sequential.
        async let followSnapshotTask = db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followerId", isEqualTo: currentUserId)
            .whereField("followingId", isEqualTo: userId)
            .limit(to: 1)
            .getDocuments()

        async let targetUserDocTask = db.collection(FirebaseManager.CollectionPath.users)
            .document(userId)
            .getDocument()

        let (snapshot, targetUserDoc) = try await (followSnapshotTask, targetUserDocTask)

        if !snapshot.documents.isEmpty {
            dlog("⚠️ Already following this user (found in Firestore)")
            following.insert(userId) // Update cache
            return
        }
        
        let isPrivate = targetUserDoc.data()?["isPrivate"] as? Bool ?? false
        
        if isPrivate {
            // Check if request already sent (depends on knowing isPrivate, so sequential is fine)
            let existingRequest = try await db.collection("followRequests")
                .whereField("fromUserId", isEqualTo: currentUserId)
                .whereField("toUserId", isEqualTo: userId)
                .whereField("status", isEqualTo: "pending")
                .limit(to: 1)
                .getDocuments()
            
            guard existingRequest.documents.isEmpty else {
                dlog("⚠️ Follow request already pending for user: \(userId)")
                return
            }
            
            // Create a pending follow request
            let requestData: [String: Any] = [
                "fromUserId": currentUserId,
                "toUserId": userId,
                "status": "pending",
                "createdAt": FieldValue.serverTimestamp()
            ]
            try await db.collection("followRequests").addDocument(data: requestData)
            dlog("✅ Follow request sent to private account: \(userId)")
            return
        }
        
        // Public account — optimistically update local state FIRST (prevents double-tap)
        following.insert(userId)
        
        // Create follow relationship
        let follow = Follow(
            followerId: currentUserId,
            followingId: userId
        )
        
        dlog("   Creating follow relationship...")
        
        // Use batch write for atomicity
        let batch = db.batch()
        
        // 1. Add to follows collection
        let followRef = db.collection(FirebaseManager.CollectionPath.follows).document()
        do {
            try batch.setData(from: follow, forDocument: followRef)
        } catch {
            dlog("❌ Failed to encode follow data: \(error)")
            // Revert optimistic update
            following.remove(userId)
            throw error
        }

        // 1b. Write follows_index entry — used by Firestore privacy rules for O(1) lookups
        let indexId = "\(currentUserId)_\(userId)"
        let indexRef = db.collection("follows_index").document(indexId)
        batch.setData([
            "followerId": currentUserId,
            "followingId": userId,
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: indexRef)

        // 2. Increment follower count on target user
        let targetUserRef = db.collection(FirebaseManager.CollectionPath.users).document(userId)
        batch.updateData([
            "followersCount": FieldValue.increment(Int64(1)),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: targetUserRef)
        
        // 3. Increment following count on current user
        let currentUserRef = db.collection(FirebaseManager.CollectionPath.users).document(currentUserId)
        batch.updateData([
            "followingCount": FieldValue.increment(Int64(1)),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: currentUserRef)
        
        // Commit batch
        do {
            dlog("   Committing batch write...")
            try await batch.commit()
            dlog("✅ Followed user successfully")
            
            // ✅ RECORD RATE LIMIT ACTION
            await NewAccountRestrictionService.shared.recordAction(.follow, userId: currentUserId)
            
        } catch {
            dlog("❌ Batch commit failed: \(error)")
            dlog("   Error details: \((error as NSError).localizedDescription)")
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

        // Invalidate privacy cache so follow state is fresh everywhere
        PrivacyAccessControl.shared.invalidate(userId: userId)
        NotificationCenter.default.post(
            name: .followRelationshipChanged,
            object: nil,
            userInfo: ["userId": userId]
        )
        // Broadcast to all UI components observing followStateChanged
        NotificationCenter.default.post(
            name: .followStateChanged,
            object: nil,
            userInfo: ["userId": userId, "isFollowing": true]
        )
    }
    
    // MARK: - Unfollow User
    
    // Track in-progress unfollow operations to prevent duplicates
    private var unfollowOperationsInProgress = Set<String>()
    
    /// Unfollow a user
    func unfollowUser(userId: String) async throws {
        dlog("👥 Unfollowing user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // PREVENT DUPLICATE OPERATIONS
        guard !unfollowOperationsInProgress.contains(userId) else {
            dlog("⚠️ Unfollow operation already in progress for user: \(userId)")
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
            dlog("⚠️ Not following this user")
            return
        }
        
        let followDocRef = followDoc.reference
        let targetUserRef = db.collection(FirebaseManager.CollectionPath.users).document(userId)
        let currentUserRef = db.collection(FirebaseManager.CollectionPath.users).document(currentUserId)

        // Pre-read current counts so we can apply a floor of 0 in the batch write.
        // FieldValue.increment(-1) can produce negative counts on concurrent unfollows;
        // reading first and using max(0, count - 1) prevents that.
        // The Firestore isCounterUpdate() rule allows a delta of [-1, 0, 1], so a 0 delta
        // (when count is already 0) is still accepted.
        async let targetSnapTask = targetUserRef.getDocument()
        async let currentSnapTask = currentUserRef.getDocument()
        let (targetSnap, currentSnap) = try await (targetSnapTask, currentSnapTask)
        let newFollowersCount = max(0, (targetSnap.data()?["followersCount"] as? Int ?? 0) - 1)
        let newFollowingCount = max(0, (currentSnap.data()?["followingCount"] as? Int ?? 0) - 1)

        // Use a batch write instead of a transaction for unfollow.
        // Transactions require every doc to be read before write (for security rule evaluation
        // of resource.data). The follows_index delete was failing because there was no prior
        // transaction.getDocument(indexRef), leaving resource.data null when the rule checked
        // resource.data.get('followerId'). A batch write with the computed values avoids this
        // entirely — the rules' isCounterUpdate() check passes because the delta is ±1 (or 0).
        let batch = db.batch()
        batch.deleteDocument(followDocRef)
        batch.updateData([
            "followersCount": newFollowersCount,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: targetUserRef)
        batch.updateData([
            "followingCount": newFollowingCount,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: currentUserRef)

        // Only delete the index doc if it actually exists — a missing index doc causes
        // resource==null in Firestore rules, which would deny the entire batch (Code=7).
        let indexRef = db.collection("follows_index").document("\(currentUserId)_\(userId)")
        let indexSnap = try? await indexRef.getDocument()
        if indexSnap?.exists == true {
            batch.deleteDocument(indexRef)
        }

        do {
            try await batch.commit()
        } catch {
            dlog("❌ Unfollow batch failed: \(error)")
            // Revert optimistic update on error
            following.insert(userId)
            throw error
        }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()

        // Invalidate privacy cache on unfollow
        PrivacyAccessControl.shared.invalidate(userId: userId)
        NotificationCenter.default.post(
            name: .followRelationshipChanged,
            object: nil,
            userInfo: ["userId": userId]
        )
        // Broadcast to all UI components observing followStateChanged
        NotificationCenter.default.post(
            name: .followStateChanged,
            object: nil,
            userInfo: ["userId": userId, "isFollowing": false]
        )
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
            dlog("❌ Error checking follow status: \(error)")
            return false
        }
    }
    
    // MARK: - Fetch Followers
    
    /// Fetch all followers for a user (returns user IDs)
    func fetchFollowerIds(userId: String) async throws -> [String] {
        dlog("📥 Fetching followers for user: \(userId)")
        
        // Query without ordering to avoid index requirement
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followingId", isEqualTo: userId)
            .getDocuments()
        
        let followerIds = snapshot.documents.compactMap { $0.data()["followerId"] as? String }
        
        dlog("✅ Fetched \(followerIds.count) followers")
        
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
        
        dlog("👥 Removing follower: \(followerId)")
        
        // Find the follow relationship where they follow you
        let followQuery = db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followerId", isEqualTo: followerId)
            .whereField("followingId", isEqualTo: currentUserId)
            .limit(to: 1)
        
        let snapshot = try await followQuery.getDocuments()
        
        guard let followDoc = snapshot.documents.first else {
            dlog("⚠️ No follow relationship found")
            return
        }
        
        let followDocRef = followDoc.reference
        let currentUserRef = db.collection(FirebaseManager.CollectionPath.users).document(currentUserId)
        let followerRef = db.collection(FirebaseManager.CollectionPath.users).document(followerId)
        
        // P1 FIX: Transaction with clamped decrements to prevent negative counts
        _ = try await db.runTransaction { transaction, errorPointer in
            let currentSnap: DocumentSnapshot
            let followerSnap: DocumentSnapshot
            do {
                currentSnap = try transaction.getDocument(currentUserRef)
                followerSnap = try transaction.getDocument(followerRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            let newFollowers = max(0, (currentSnap.data()?["followersCount"] as? Int ?? 0) - 1)
            let newFollowing = max(0, (followerSnap.data()?["followingCount"] as? Int ?? 0) - 1)
            transaction.deleteDocument(followDocRef)
            transaction.updateData(["followersCount": newFollowers, "updatedAt": Date()], forDocument: currentUserRef)
            transaction.updateData(["followingCount": newFollowing, "updatedAt": Date()], forDocument: followerRef)
            // Remove follows_index so the removed follower loses private-content access
            let indexRef = self.db.collection("follows_index").document("\(followerId)_\(currentUserId)")
            transaction.deleteDocument(indexRef)
            return nil
        }
        dlog("✅ Follower removed successfully")

        // Invalidate privacy cache for the removed follower
        PrivacyAccessControl.shared.invalidate(userId: followerId)
        NotificationCenter.default.post(
            name: .followRelationshipChanged,
            object: nil,
            userInfo: ["userId": followerId]
        )
    }
    
    // MARK: - Fetch Following
    
    /// Fetch all users that a user is following (returns user IDs)
    func fetchFollowingIds(userId: String) async throws -> [String] {
        dlog("📥 Fetching following for user: \(userId)")
        
        // Query without ordering to avoid index requirement
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followerId", isEqualTo: userId)
            .getDocuments()
        
        let followingIds = snapshot.documents.compactMap { $0.data()["followingId"] as? String }
        
        dlog("✅ Fetched \(followingIds.count) following")
        
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
        // Skip if already loaded for this user and a load isn't already in progress.
        guard loadedForUserId != currentUserId, !isLoadingFollowData else {
            dlog("⏭️ Follow data already loaded for current user — skipping duplicate load")
            return
        }
        isLoadingFollowData = true

        do {
            let followingIds = try await fetchFollowingIds(userId: currentUserId)
            following = Set(followingIds)
            loadedForUserId = currentUserId
            dlog("✅ Loaded \(followingIds.count) following into cache")
        } catch {
            dlog("❌ Failed to load following: \(error)")
        }
        isLoadingFollowData = false
    }

    /// Load current user's followers list into cache
    func loadCurrentUserFollowers() async {
        guard let currentUserId = firebaseManager.currentUser?.uid else { return }
        // The `loadedForUserId` guard in loadCurrentUserFollowing() covers both loads
        // (they're always called together). Skip redundant followers fetch too.
        guard loadedForUserId != currentUserId, !isLoadingFollowData else {
            dlog("⏭️ Follow data already loaded for current user — skipping duplicate load")
            return
        }

        do {
            let followerIds = try await fetchFollowerIds(userId: currentUserId)
            followers = Set(followerIds)
            dlog("✅ Loaded \(followerIds.count) followers into cache")
        } catch {
            dlog("❌ Failed to load followers: \(error)")
        }
    }
    
    // MARK: - Mutual Follows
    
    /// Check if two users follow each other
    func areMutualFollowers(userId: String) async -> Bool {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            return false
        }
        
        // Run both queries concurrently instead of sequentially.
        async let youFollowThemTask = isFollowing(userId: userId)
        async let theyFollowYouTask: Bool = {
            do {
                let snapshot = try await db.collection(FirebaseManager.CollectionPath.follows)
                    .whereField("followerId", isEqualTo: userId)
                    .whereField("followingId", isEqualTo: currentUserId)
                    .limit(to: 1)
                    .getDocuments()
                return !snapshot.documents.isEmpty
            } catch {
                return false
            }
        }()
        
        let youFollowThem = await youFollowThemTask
        let theyFollowYou = await theyFollowYouTask
        return youFollowThem && theyFollowYou
    }
    
    // MARK: - Real-time Listeners
    
    /// Start listening to current user's following list
    func startListening() {
        // ✅ FIX: Prevent duplicate listeners
        guard !isListening else {
            dlog("⚠️ Already listening to follow changes")
            return
        }
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            dlog("⚠️ No user ID for listener")
            return
        }
        
        isListening = true
        dlog("🔊 Starting real-time listener for follows...")

        #if DEBUG
        ListenerCounter.shared.attach("follow-following")
        ListenerCounter.shared.attach("follow-followers")
        #endif

        // Listen to following
        let followingListener = db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followerId", isEqualTo: currentUserId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    dlog("❌ Following listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let followingIds = snapshot.documents.compactMap { doc -> String? in
                    doc.data()["followingId"] as? String
                }
                
                Task { @MainActor in
                    self.following = Set(followingIds)
                    self.currentUserFollowingCount = followingIds.count
                    dlog("✅ Real-time update: \(followingIds.count) following")
                }
            }
        
        // Listen to followers
        let followersListener = db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followingId", isEqualTo: currentUserId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    dlog("❌ Followers listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let followerIds = snapshot.documents.compactMap { doc -> String? in
                    doc.data()["followerId"] as? String
                }
                
                Task { @MainActor in
                    self.followers = Set(followerIds)
                    self.currentUserFollowersCount = followerIds.count
                    dlog("✅ Real-time update: \(followerIds.count) followers")
                }
            }
        
        listeners.append(followingListener)
        listeners.append(followersListener)
        
        // NOTE: Removed userStatsListener to prevent duplicate counter updates
        // The following/followers listeners already provide accurate counts from the follows collection
    }
    
    /// Stop all listeners
    func stopListening() {
        dlog("🔇 Stopping follow listeners...")
        #if DEBUG
        if !listeners.isEmpty {
            ListenerCounter.shared.detach("follow-following")
            ListenerCounter.shared.detach("follow-followers")
        }
        #endif
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        isListening = false  // ✅ FIX: Reset flag so listeners can be restarted
        loadedForUserId = nil       // Allow re-load after sign-out → sign-in
        isLoadingFollowData = false // Clear any stale in-progress flag
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
            dlog("✅ Using cached counts for current user: \(cached.followers) followers, \(cached.following) following")
            return cached
        }
        
        // Fall back to Firestore read for other users or if cache unavailable
        dlog("📡 Fetching counts from Firestore for user: \(userId)")
        return try await getFollowStats(userId: userId)
    }
    
    // MARK: - P1-4: Batch Fetch Optimization
    
    /// P1-4: Batch fetch user profiles to minimize Firestore reads
    /// Uses Firestore's `in` query operator with 10-item batches (Firestore limit)
    private func batchFetchUserProfiles(userIds: [String]) async throws -> [FollowUserProfile] {
        guard !userIds.isEmpty else {
            return []
        }
        
        dlog("📦 Batch fetching \(userIds.count) user profiles...")
        
        // Firestore 'in' query limit is 10 items per batch
        let batchSize = 10
        var allProfiles: [FollowUserProfile] = []
        
        // Split user IDs into batches of 10
        let batches = stride(from: 0, to: userIds.count, by: batchSize).map {
            Array(userIds[$0..<min($0 + batchSize, userIds.count)])
        }
        
        dlog("   Processing \(batches.count) batch(es) of \(batchSize) items each")
        
        // Fetch each batch in parallel for maximum performance
        try await withThrowingTaskGroup(of: [FollowUserProfile].self) { group in
            for batch in batches {
                group.addTask {
                    // Use Firestore's 'in' query to fetch multiple users at once
                    let snapshot = try await self.db.collection(FirebaseManager.CollectionPath.users)
                        .whereField(FieldPath.documentID(), in: batch)
                        .getDocuments()
                    
                    let profiles = snapshot.documents.compactMap { doc -> FollowUserProfile? in
                        let userData = doc.data()
                        guard !userData.isEmpty else {
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
                    
                    dlog("   ✅ Fetched batch of \(profiles.count) users")
                    return profiles
                }
            }
            
            // Collect all results from parallel tasks
            for try await batchProfiles in group {
                allProfiles.append(contentsOf: batchProfiles)
            }
        }
        
        dlog("✅ Batch fetch complete: \(allProfiles.count) profiles fetched")
        
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
        _ = try await db.runTransaction { transaction, errorPointer in
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
                    dlog("⚠️ Prevented negative decrement for \(field) on user \(userRef.documentID)")
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
