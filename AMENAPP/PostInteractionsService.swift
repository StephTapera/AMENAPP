//
//  PostInteractionsService.swift
//  AMENAPP
//
//  Real-time service for post likes (lightbulbs & amens), comments, and reposts
//

import Foundation
import FirebaseDatabase
import FirebaseAuth
import FirebaseFirestore
import Combine
import SwiftUI

// MARK: - Post Interactions Service

@MainActor
class PostInteractionsService: ObservableObject {
    static let shared = PostInteractionsService()
    
    private var _database: Database?
    private var database: Database {
        if let db = _database {
            return db
        }
        let db = Database.database()
        
        // ✅ NOTE: Offline persistence is already enabled globally in AppDelegate.swift
        // No need to call isPersistenceEnabled here (would crash if called after first access)
        dlog("✅ PostInteractions Database initialized successfully (using global persistence)")
        
        _database = db
        return db
    }
    
    private var ref: DatabaseReference {
        database.reference()
    }
    
    private let firestore = Firestore.firestore()
    
    // Published properties for real-time updates
    @Published var postLightbulbs: [String: Int] = [:]  // postId -> count
    @Published var postAmens: [String: Int] = [:]       // postId -> count
    @Published var postComments: [String: Int] = [:]    // postId -> count
    @Published var postReposts: [String: Int] = [:]     // postId -> count
    
    @Published var userLightbulbedPosts: Set<String> = []  // Posts current user lit
    @Published var userAmenedPosts: Set<String> = []       // Posts current user amened
    @Published var userRepostedPosts: Set<String> = []     // Posts current user reposted
    
    @Published var postCommentsData: [String: [RealtimeComment]] = [:]  // postId -> comments

    // P1-B FIX: Track per-post content expansion state here (not as PostCard @State)
    // so the expanded state survives SwiftUI view recycling during scroll.
    // PostCard reads and writes this set; the published change propagates via @ObservedObject.
    @Published var expandedPostIds: Set<String> = []

    /// Toggle or read per-post content expansion. Used by PostCard instead of local @State.
    func isExpanded(_ postId: String) -> Bool { expandedPostIds.contains(postId) }
    func toggleExpanded(_ postId: String) {
        if expandedPostIds.contains(postId) {
            expandedPostIds.remove(postId)
        } else {
            expandedPostIds.insert(postId)
        }
    }
    
    private var observers: [String: DatabaseHandle] = [:]
    // SCALE FIX: Maximum number of simultaneously observed posts.
    // At 2 handles per post (counts + commentsData) this caps RTDB concurrent
    // connections at 60, well below Firebase's 100-per-client soft limit.
    // When the cap is reached the oldest postId's listeners are evicted first.
    private static let maxActivePostObservers = 30
    // Insertion-order tracking so we can evict the oldest post when the cap is hit.
    private var observerInsertionOrder: [String] = []   // postIds in observation order

    // P0 FIX: In-flight guards prevent concurrent toggle calls (rapid double-tap).
    // Keyed by postId so different posts can toggle independently.
    private var lightbulbTogglesInFlight: Set<String> = []
    private var amenTogglesInFlight: Set<String> = []
    // P0-A FIX: Repost also needs an in-flight guard to prevent double-writes on rapid taps.
    private var repostTogglesInFlight: Set<String> = []

    // Cache user's display name from Firestore
    @Published var cachedUserDisplayName: String?
    
    // Track if initial cache load is complete
    @Published var hasLoadedInitialCache = false
    
    private init() {
        loadUserInteractions()
        Task {
            await loadUserDisplayName()
        }
        
        // ✅ Monitor database connection state
        monitorDatabaseConnection()
    }
    
    /// Load user's display name from Firestore and cache it
    private func loadUserDisplayName() async {
        guard currentUserId != "anonymous" else { return }
        
        do {
            let userDoc = try await Firestore.firestore()
                .collection("users")
                .document(currentUserId)
                .getDocument()
            
            if let displayName = userDoc.data()?["displayName"] as? String {
                await MainActor.run {
                    cachedUserDisplayName = displayName
                }
                dlog("✅ Loaded user display name: \(displayName)")
                
                // Also update Firebase Auth profile if needed
                if Auth.auth().currentUser?.displayName != displayName {
                    let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest()
                    changeRequest?.displayName = displayName
                    try? await changeRequest?.commitChanges()
                    dlog("✅ Updated Auth displayName")
                }
            }
        } catch {
            dlog("⚠️ Could not load user display name: \(error)")
        }
    }
    
    var currentUserId: String {
        Auth.auth().currentUser?.uid ?? "anonymous"
    }
    
    var currentUserName: String {
        // First try cached name from Firestore
        if let cachedName = cachedUserDisplayName, !cachedName.isEmpty {
            return cachedName
        }
        
        // Try Firebase Auth displayName
        if let displayName = Auth.auth().currentUser?.displayName, !displayName.isEmpty {
            return displayName
        }
        
        // Fallback to email username if displayName not set
        if let email = Auth.auth().currentUser?.email {
            let emailUsername = email.components(separatedBy: "@").first ?? "User"
            return emailUsername.capitalized
        }
        
        return "Anonymous"
    }
    
    // MARK: - Lightbulb (💡) Actions
    
    /// Toggle lightbulb on a post
    func toggleLightbulb(postId: String) async throws {
        guard currentUserId != "anonymous" else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // P0 FIX: Prevent concurrent toggle calls from rapid double-taps.
        // Without this guard two simultaneous read→write cycles can produce count drift.
        guard !lightbulbTogglesInFlight.contains(postId) else {
            dlog("⏭️ [Lightbulb] Toggle already in-flight for \(postId), ignoring duplicate")
            return
        }
        lightbulbTogglesInFlight.insert(postId)
        defer { lightbulbTogglesInFlight.remove(postId) }

        let userLightbulbRef = ref.child("postInteractions").child(postId).child("lightbulbs").child(currentUserId)

        // Use cached state — avoids a blocking getData() round-trip before the write.
        // The cache is kept in sync by startListening() and the real-time observer.
        let isCurrentlyLit = userLightbulbedPosts.contains(postId)

        if isCurrentlyLit {
            // Remove lightbulb
            try await userLightbulbRef.removeValue()
            
            // Decrement count atomically with a transaction to prevent race conditions
            try await ref.child("postInteractions").child(postId).child("lightbulbCount").runTransactionBlock { currentData in
                if let count = currentData.value as? Int, count > 0 {
                    currentData.value = count - 1
                } else if currentData.value == nil {
                    currentData.value = 0
                }
                return TransactionResult.success(withValue: currentData)
            }
            
            // Mirror to user interaction index in background (non-critical path)
            Task.detached { [weak self] in
                guard let self else { return }
                try? await self.syncUserInteraction(type: "lightbulbs", postId: postId, value: false)
            }

            // Update local boolean state only — count is owned by the real-time observer.
            // Mutating postLightbulbs here causes double-counting when the observer fires.
            userLightbulbedPosts.remove(postId)

            dlog("💡 [DEBUG] Lightbulb removed from post: \(postId)")
            dlog("   - User: \(currentUserId)")
            dlog("   - New count: \(postLightbulbs[postId] ?? 0)")
            dlog("   - User's total lightbulbs: \(userLightbulbedPosts.count)")
        } else {
            // Add lightbulb
            try await userLightbulbRef.setValue([
                "userId": currentUserId,
                "userName": currentUserName,
                "timestamp": ServerValue.timestamp()
            ])

            // Increment count atomically with a transaction to prevent race conditions
            try await ref.child("postInteractions").child(postId).child("lightbulbCount").runTransactionBlock { currentData in
                let count = currentData.value as? Int ?? 0
                currentData.value = count + 1
                return TransactionResult.success(withValue: currentData)
            }

            // Mirror to user interaction index in background (non-critical path)
            Task.detached { [weak self] in
                guard let self else { return }
                try? await self.syncUserInteraction(type: "lightbulbs", postId: postId, value: true)
            }
            
            // Update local boolean state only — count is owned by the real-time observer.
            userLightbulbedPosts.insert(postId)

            // ✅ OPTIMIZED: Create notification asynchronously (fire-and-forget, doesn't block UI)
            Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    let postAuthorId = try await self.getPostAuthorId(postId: postId)
                    try await self.createNotification(type: "lightbulb", postId: postId, postAuthorId: postAuthorId)
                } catch {
                    dlog("⚠️ Lightbulb notification failed for post \(postId): \(error.localizedDescription)")
                }
            }
            
            dlog("💡 [DEBUG] Lightbulb added to post: \(postId)")
            dlog("   - User: \(currentUserId)")
            dlog("   - New count: \(postLightbulbs[postId] ?? 1)")
            dlog("   - User's total lightbulbs: \(userLightbulbedPosts.count)")
        }
    }
    
    /// Check if user has lit lightbulb on post
    func hasLitLightbulb(postId: String) async -> Bool {
        guard currentUserId != "anonymous" else { return false }
        
        // ✅ Check the user interactions index (canonical source of truth for user's lightbulb state)
        do {
            let snapshot = try await ref.child("userInteractions").child(currentUserId).child("lightbulbs").child(postId).getData()
            let exists = snapshot.exists()
            
            // ✅ Sync cache in background — don't block the caller waiting for a frame boundary.
            // The 10ms sleep was preventing concurrent frame warnings but delayed every PostCard load.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if exists && !self.userLightbulbedPosts.contains(postId) {
                    self.userLightbulbedPosts.insert(postId)
                } else if !exists && self.userLightbulbedPosts.contains(postId) {
                    self.userLightbulbedPosts.remove(postId)
                }
            }
            
            return exists
        } catch {
            dlog("❌ Failed to check lightbulb status: \(error)")
            // Return cache state on error
            return userLightbulbedPosts.contains(postId)
        }
    }
    
    /// Get lightbulb count for post
    func getLightbulbCount(postId: String) async -> Int {
        // Use in-memory cache if the real-time observer has already populated it
        if let cached = postLightbulbs[postId] { return cached }
        do {
            let snapshot = try await ref.child("postInteractions").child(postId).child("lightbulbCount").getData()
            return snapshot.value as? Int ?? 0
        } catch {
            // Suppress noisy offline errors — observer will populate the value when connected
            return 0
        }
    }
    
    // MARK: - Amen (🙏) Actions
    
    /// Toggle amen on a post
    func toggleAmen(postId: String) async throws {
        guard currentUserId != "anonymous" else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // P0 FIX: Prevent concurrent toggle calls from rapid double-taps.
        guard !amenTogglesInFlight.contains(postId) else {
            dlog("⏭️ [Amen] Toggle already in-flight for \(postId), ignoring duplicate")
            return
        }
        amenTogglesInFlight.insert(postId)
        defer { amenTogglesInFlight.remove(postId) }

        let userAmenRef = ref.child("postInteractions").child(postId).child("amens").child(currentUserId)

        // Use cached state — avoids a blocking getData() round-trip before the write.
        let isCurrentlyAmened = userAmenedPosts.contains(postId)

        if isCurrentlyAmened {
            // Remove amen
            try await userAmenRef.removeValue()

            // Decrement count atomically with a transaction to prevent race conditions
            try await ref.child("postInteractions").child(postId).child("amenCount").runTransactionBlock { currentData in
                if let count = currentData.value as? Int, count > 0 {
                    currentData.value = count - 1
                } else if currentData.value == nil {
                    currentData.value = 0
                }
                return TransactionResult.success(withValue: currentData)
            }

            // Mirror to user interaction index in background (non-critical path)
            Task.detached { [weak self] in
                guard let self else { return }
                try? await self.syncUserInteraction(type: "amens", postId: postId, value: false)
            }

            // Update local boolean state only — count is owned by the real-time observer.
            userAmenedPosts.remove(postId)

            dlog("🙏 [DEBUG] Amen removed from post: \(postId)")
            dlog("   - User: \(currentUserId)")
            dlog("   - New count: \(postAmens[postId] ?? 0)")
            dlog("   - User's total amens: \(userAmenedPosts.count)")
        } else {
            // Add amen
            try await userAmenRef.setValue([
                "userId": currentUserId,
                "userName": currentUserName,
                "timestamp": ServerValue.timestamp()
            ])

            // Increment count atomically with a transaction to prevent race conditions
            try await ref.child("postInteractions").child(postId).child("amenCount").runTransactionBlock { currentData in
                let count = currentData.value as? Int ?? 0
                currentData.value = count + 1
                return TransactionResult.success(withValue: currentData)
            }

            // Mirror to user interaction index in background (non-critical path)
            Task.detached { [weak self] in
                guard let self else { return }
                try? await self.syncUserInteraction(type: "amens", postId: postId, value: true)
            }
            
            // Update local boolean state only — count is owned by the real-time observer.
            userAmenedPosts.insert(postId)

            // ✅ OPTIMIZED: Create notification asynchronously (fire-and-forget, doesn't block UI)
            Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    let postAuthorId = try await self.getPostAuthorId(postId: postId)
                    try await self.createNotification(type: "amen", postId: postId, postAuthorId: postAuthorId)
                } catch {
                    dlog("⚠️ Amen notification failed for post \(postId): \(error.localizedDescription)")
                }
            }
            
            dlog("🙏 [DEBUG] Amen added to post: \(postId)")
            dlog("   - User: \(currentUserId)")
            dlog("   - New count: \(postAmens[postId] ?? 1)")
            dlog("   - User's total amens: \(userAmenedPosts.count)")
        }
    }
    
    /// Check if user has amened post
    func hasAmened(postId: String) async -> Bool {
        guard currentUserId != "anonymous" else { return false }
        
        // ✅ Check the user interactions index (canonical source of truth)
        do {
            let snapshot = try await ref.child("userInteractions").child(currentUserId).child("amens").child(postId).getData()
            let exists = snapshot.exists()
            
            // ✅ Sync cache in background — don't block the caller waiting for a frame boundary.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if exists && !self.userAmenedPosts.contains(postId) {
                    self.userAmenedPosts.insert(postId)
                } else if !exists && self.userAmenedPosts.contains(postId) {
                    self.userAmenedPosts.remove(postId)
                }
            }
            
            return exists
        } catch {
            dlog("❌ Failed to check amen status: \(error)")
            // Return cache state on error
            return userAmenedPosts.contains(postId)
        }
    }
    
    /// Get amen count for post
    func getAmenCount(postId: String) async -> Int {
        if let cached = postAmens[postId] { return cached }
        do {
            let snapshot = try await ref.child("postInteractions").child(postId).child("amenCount").getData()
            return snapshot.value as? Int ?? 0
        } catch {
            return 0
        }
    }
    
    // MARK: - Comments
    
    // P0: Prevent double-tap duplicate comments.
    // Key = userId + postId + content-prefix + truncated-second.
    @MainActor private var inflightComments: [String: Task<String, Error>] = [:]

    /// Add a comment to a post
    func addComment(
        postId: String,
        content: String,
        authorInitials: String = "??",
        authorUsername: String,
        authorProfileImageURL: String? = nil,
        clientRequestId: String? = nil  // Optimistic UI dedup key written to RTDB
    ) async throws -> String {
        guard currentUserId != "anonymous" else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // P0 IDEMPOTENCY: coalesce rapid double-taps on "Send"
        let truncatedSecond = Int(Date().timeIntervalSince1970)
        let commentIdempotencyKey = "\(currentUserId)_\(postId)_\(content.prefix(32))_\(truncatedSecond)"
        if let existingTask = inflightComments[commentIdempotencyKey] {
            dlog("⏭️ [Idempotency] Comment already in flight, waiting for existing task")
            return try await existingTask.value
        }

        let commentTask = Task<String, Error> { [weak self] in
            guard let self else { throw NSError(domain: "PostInteractions", code: -2) }
            defer {
                Task { @MainActor in
                    self.inflightComments.removeValue(forKey: commentIdempotencyKey)
                }
            }
            return try await self._performAddComment(
                postId: postId,
                content: content,
                authorInitials: authorInitials,
                authorUsername: authorUsername,
                authorProfileImageURL: authorProfileImageURL,
                clientRequestId: clientRequestId
            )
        }
        inflightComments[commentIdempotencyKey] = commentTask
        return try await commentTask.value
    }

    /// Internal implementation called after idempotency gate.
    private func _performAddComment(
        postId: String,
        content: String,
        authorInitials: String = "??",
        authorUsername: String,
        authorProfileImageURL: String? = nil,
        clientRequestId: String? = nil
    ) async throws -> String {
        let commentRef = ref.child("postInteractions").child(postId).child("comments").childByAutoId()
        
        guard let commentId = commentRef.key else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate comment ID"])
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        // ✅ Build comment data with optional profile image URL
        var commentData: [String: Any] = [
            "id": commentId,
            "postId": postId,
            "authorId": currentUserId,
            "authorName": currentUserName,
            "authorInitials": authorInitials,
            "authorUsername": authorUsername,
            "content": content,
            "timestamp": timestamp,
            "likes": 0
        ]
        
        // ✅ Add profile image URL if available
        if let profileImageURL = authorProfileImageURL, !profileImageURL.isEmpty {
            commentData["authorProfileImageURL"] = profileImageURL
            dlog("✅ Storing profile image URL in comment: \(profileImageURL)")
        }

        // Write clientRequestId so the real-time listener can match optimistic entries
        if let clientRequestId = clientRequestId {
            commentData["clientRequestId"] = clientRequestId
        }
        
        do {
            try await commentRef.setValue(commentData)
            dlog("✅ Comment data written to RTDB successfully")
            dlog("   Path: postInteractions/\(postId)/comments/\(commentId)")
            dlog("   Data keys: \(commentData.keys.joined(separator: ", "))")
        } catch {
            dlog("❌ CRITICAL: Failed to write comment to RTDB: \(error)")
            throw error
        }
        
        // Increment comment count
        do {
            try await ref.child("postInteractions").child(postId).child("commentCount").setValue(ServerValue.increment(1))
            dlog("✅ Comment count incremented successfully")
        } catch {
            dlog("⚠️ Warning: Failed to increment comment count: \(error)")
            // Don't throw - comment was still created
        }
        
        // Update local state
        postComments[postId] = (postComments[postId] ?? 0) + 1
        
        // ✅ Create notification for post author
        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let postAuthorId = try await self.getPostAuthorId(postId: postId)
                try await self.createNotification(type: "comment", postId: postId, postAuthorId: postAuthorId)
            } catch {
                dlog("⚠️ Comment notification failed for post \(postId): \(error.localizedDescription)")
            }
        }
        
        dlog("💬 Comment added to post: \(postId) by @\(authorUsername)")
        dlog("🔍 You can verify at: postInteractions/\(postId)/comments")
        
        return commentId
    }
    
    /// Delete a comment
    func deleteComment(postId: String, commentId: String) async throws {
        guard currentUserId != "anonymous" else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Verify user owns the comment
        let commentRef = ref.child("postInteractions").child(postId).child("comments").child(commentId)
        let snapshot = try await commentRef.getData()
        
        guard let commentData = snapshot.value as? [String: Any],
              let authorId = commentData["authorId"] as? String,
              authorId == currentUserId else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authorized to delete this comment"])
        }
        
        try await commentRef.removeValue()

        // P1 FIX: Use a transaction to decrement with a floor of 0.
        // ServerValue.increment(-1) alone can produce negative counts if multiple
        // deletes race. The transaction aborts if the value would go below 0.
        try await ref.child("postInteractions").child(postId).child("commentCount").runTransactionBlock { currentData in
            if let count = currentData.value as? Int, count > 0 {
                currentData.value = count - 1
            } else {
                currentData.value = 0
            }
            return TransactionResult.success(withValue: currentData)
        }

        // Update local state
        if let currentCount = postComments[postId] {
            postComments[postId] = max(0, currentCount - 1)
        }
        
        dlog("💬 Comment deleted: \(commentId)")
    }
    
    /// Get comments for a post
    func getComments(postId: String) async -> [RealtimeComment] {
        dlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        dlog("🔍 [RTDB] GET COMMENTS CALLED")
        dlog("🔍 [RTDB] Post ID: \(postId)")
        dlog("🔍 [RTDB] Querying path: postInteractions/\(postId)/comments")
        dlog("🔍 [RTDB] Database URL: \(database.app?.options.databaseURL ?? "unknown")")
        dlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // ✅ FIX: Use observeSingleEvent instead of getData() to properly use offline cache
        // getData() bypasses cache on cold start, observeSingleEvent uses cache-first approach
        return await withCheckedContinuation { continuation in
            dlog("🔍 [RTDB] Using observeSingleEvent for cache-friendly loading...")
            
            ref.child("postInteractions").child(postId).child("comments")
                .observeSingleEvent(of: .value) { snapshot in
                    dlog("🔍 [RTDB] observeSingleEvent returned successfully")
                    dlog("🔍 [RTDB] Snapshot exists: \(snapshot.exists()), hasChildren: \(snapshot.hasChildren())")
                    dlog("🔍 [RTDB] Children count: \(snapshot.childrenCount)")

                    // Debug: Print raw snapshot value
                    if let rawValue = snapshot.value {
                        dlog("🔍 [RTDB] Raw snapshot value type: \(type(of: rawValue))")
                        if let dict = rawValue as? [String: Any] {
                            dlog("🔍 [RTDB] Comment IDs in snapshot: \(dict.keys.joined(separator: ", "))")
                        }
                    } else {
                        dlog("⚠️ [RTDB] Snapshot value is nil!")
                    }
                    
                    var comments: [RealtimeComment] = []
                    
                    for child in snapshot.children {
                        guard let childSnapshot = child as? DataSnapshot,
                              let commentData = childSnapshot.value as? [String: Any],
                              let id = commentData["id"] as? String,
                              let authorId = commentData["authorId"] as? String,
                              let authorName = commentData["authorName"] as? String,
                              let authorInitials = commentData["authorInitials"] as? String,
                              let content = commentData["content"] as? String,
                              let timestamp = commentData["timestamp"] as? Int64 else {
                            continue
                        }
                        
                        let likes = commentData["likes"] as? Int ?? 0
                        // ✅ Read username from RTDB if available
                        let authorUsername = commentData["authorUsername"] as? String
                        // ✅ Read profile image URL from RTDB if available
                        let authorProfileImageURL = commentData["authorProfileImageURL"] as? String
                        // ✅ Read parentCommentId for replies
                        let parentCommentId = commentData["parentCommentId"] as? String
                        
                        let comment = RealtimeComment(
                            id: id,
                            postId: postId,
                            authorId: authorId,
                            authorName: authorName,
                            authorInitials: authorInitials,
                            authorUsername: authorUsername,
                            authorProfileImageURL: authorProfileImageURL,  // ✅ NEW: Pass profile image URL
                            content: content,
                            timestamp: Date(timeIntervalSince1970: Double(timestamp) / 1000.0),
                            likes: likes,
                            parentCommentId: parentCommentId
                        )
                        
                        comments.append(comment)
                    }
                    
                    // Sort by timestamp
                    comments.sort { $0.timestamp < $1.timestamp }
                    
                    dlog("✅ [RTDB] Successfully parsed \(comments.count) comments")
                    for comment in comments {
                        dlog("   📝 ID: \(comment.id) - Content: \"\(comment.content)\"")
                    }
                    
                    continuation.resume(returning: comments)
                } withCancel: { error in
                    dlog("❌ [RTDB] Failed to get comments: \(error)")
                    dlog("   Error details: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                }
        }
    }
    
    /// Get comment count for post
    func getCommentCount(postId: String) async -> Int {
        if let cached = postComments[postId] { return cached }
        do {
            let snapshot = try await ref.child("postInteractions").child(postId).child("commentCount").getData()
            return snapshot.value as? Int ?? 0
        } catch {
            return 0
        }
    }
    
    // MARK: - Reposts
    
    /// Toggle repost on a post
    func toggleRepost(postId: String) async throws -> Bool {
        guard currentUserId != "anonymous" else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // P0-A FIX: Prevent concurrent repost toggle calls from rapid double-taps.
        guard !repostTogglesInFlight.contains(postId) else {
            dlog("⏭️ [Repost] Toggle already in-flight for \(postId), ignoring duplicate")
            return userRepostedPosts.contains(postId)
        }
        repostTogglesInFlight.insert(postId)
        defer { repostTogglesInFlight.remove(postId) }

        let userRepostRef = ref.child("postInteractions").child(postId).child("reposts").child(currentUserId)

        // Use cached state — avoids a blocking getData() round-trip before the write.
        let isCurrentlyReposted = userRepostedPosts.contains(postId)

        if isCurrentlyReposted {
            // Remove repost
            try await userRepostRef.removeValue()

            // P0-E FIX: Use a transaction to decrement with a floor of 0.
            try await ref.child("postInteractions").child(postId).child("repostCount").runTransactionBlock { currentData in
                if let count = currentData.value as? Int, count > 0 {
                    currentData.value = count - 1
                } else {
                    currentData.value = 0
                }
                return TransactionResult.success(withValue: currentData)
            }

            // Mirror to user interaction index in background (non-critical path)
            Task.detached { [weak self] in
                guard let self else { return }
                try? await self.syncUserInteraction(type: "reposts", postId: postId, value: false)
            }
            
            // Update local state
            userRepostedPosts.remove(postId)
            if let currentCount = postReposts[postId] {
                postReposts[postId] = max(0, currentCount - 1)
            }
            
            dlog("🔄 [DEBUG] Repost removed from post: \(postId)")
            dlog("   - User: \(currentUserId)")
            dlog("   - New count: \(postReposts[postId] ?? 0)")
            dlog("   - User's total reposts: \(userRepostedPosts.count)")
            return false
        } else {
            // Add repost
            try await userRepostRef.setValue([
                "userId": currentUserId,
                "userName": currentUserName,
                "timestamp": ServerValue.timestamp()
            ])
            
            // Increment count
            try await ref.child("postInteractions").child(postId).child("repostCount").setValue(ServerValue.increment(1))

            // Mirror to user interaction index in background (non-critical path)
            Task.detached { [weak self] in
                guard let self else { return }
                try? await self.syncUserInteraction(type: "reposts", postId: postId, value: true)
            }

            // Update local state
            userRepostedPosts.insert(postId)
            postReposts[postId] = (postReposts[postId] ?? 0) + 1
            
            // ✅ Create notification for post author
            Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    let postAuthorId = try await self.getPostAuthorId(postId: postId)
                    try await self.createNotification(type: "repost", postId: postId, postAuthorId: postAuthorId)
                } catch {
                    dlog("⚠️ Repost notification failed for post \(postId): \(error.localizedDescription)")
                }
            }
            
            dlog("🔄 [DEBUG] Repost added to post: \(postId)")
            dlog("   - User: \(currentUserId)")
            dlog("   - New count: \(postReposts[postId] ?? 1)")
            dlog("   - User's total reposts: \(userRepostedPosts.count)")
            return true
        }
    }
    
    /// Check if user has reposted post
    func hasReposted(postId: String) async -> Bool {
        guard currentUserId != "anonymous" else { return false }
        
        // ✅ Check the user interactions index (canonical source of truth)
        do {
            let snapshot = try await ref.child("userInteractions").child(currentUserId).child("reposts").child(postId).getData()
            let exists = snapshot.exists()
            
            // ✅ Sync cache in background — don't block the caller waiting for a frame boundary.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if exists && !self.userRepostedPosts.contains(postId) {
                    self.userRepostedPosts.insert(postId)
                } else if !exists && self.userRepostedPosts.contains(postId) {
                    self.userRepostedPosts.remove(postId)
                }
            }
            
            return exists
        } catch {
            dlog("❌ Failed to check repost status: \(error)")
            // Return cache state on error
            return userRepostedPosts.contains(postId)
        }
    }
    
    /// Get repost count for post
    func getRepostCount(postId: String) async -> Int {
        if let cached = postReposts[postId] { return cached }
        do {
            let snapshot = try await ref.child("postInteractions").child(postId).child("repostCount").getData()
            return snapshot.value as? Int ?? 0
        } catch {
            return 0
        }
    }
    
    // MARK: - Real-time Observers
    
    /// Observe interactions for a specific post
    func observePostInteractions(postId: String) {
        // Already observing this post — skip re-registration.
        // Without this guard every tab switch re-registers 40 RTDB listeners simultaneously
        // (2 per card × 20 cards), which stalls the main thread and causes visible lag.
        guard observers["\(postId)_counts"] == nil else { return }
        // Remove any partial existing observers
        stopObservingPost(postId: postId)

        // SCALE FIX: Enforce a hard cap on concurrent RTDB post observers.
        // When the cap is reached, evict the oldest observer to make room.
        let currentPostCount = observerInsertionOrder.count
        if currentPostCount >= Self.maxActivePostObservers {
            let evictCount = currentPostCount - Self.maxActivePostObservers + 1
            let toEvict = Array(observerInsertionOrder.prefix(evictCount))
            toEvict.forEach { stopObservingPost(postId: $0) }
        }
        observerInsertionOrder.append(postId)
        
        let postRef = ref.child("postInteractions").child(postId)
        
        // PERF: Observe all 4 counts in a single listener on the parent node.
        // This batches lightbulb/amen/comment/repost updates into one objectWillChange publish
        // instead of 4 separate ones, cutting PostCard .onChange callbacks by 75%.
        let countsHandle = postRef.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            // Firebase callbacks run on a background thread; extract plain values now
            // so we never mutate @Published properties off MainActor (causes SIGABRT).
            guard let data = snapshot.value as? [String: Any] else { return }
            let lightbulbs = data["lightbulbCount"] as? Int ?? 0
            let amens      = data["amenCount"]      as? Int ?? 0
            let comments   = data["commentCount"]   as? Int ?? 0
            let reposts    = data["repostCount"]    as? Int ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Send objectWillChange once, then mutate all 4 backing stores directly
                // so SwiftUI sees a single state-change notification.
                self.objectWillChange.send()
                self.postLightbulbs.updateValue(lightbulbs, forKey: postId)
                self.postAmens.updateValue(amens,      forKey: postId)
                self.postComments.updateValue(comments, forKey: postId)
                self.postReposts.updateValue(reposts,  forKey: postId)
            }
        }
        observers["\(postId)_counts"] = countsHandle
        
        // Observe comments data
        let commentsDataHandle = postRef.child("comments").observe(.value) { [weak self] snapshot in
            guard let self = self else { return }

            // ⚠️ CRITICAL: DataSnapshot memory is only valid synchronously within this callback.
            // Extract everything into plain Swift value types NOW, before crossing an async boundary.
            struct RawRealtimeComment {
                let id: String
                let postId: String
                let authorId: String
                let authorName: String
                let authorInitials: String
                let authorUsername: String?
                let authorProfileImageURL: String?
                let content: String
                let timestamp: Int64
                let likes: Int
                let parentCommentId: String?
            }

            var rawComments: [RawRealtimeComment] = []
            for child in snapshot.children.allObjects as? [DataSnapshot] ?? [] {
                guard let commentData = child.value as? [String: Any],
                      let id = commentData["id"] as? String,
                      let authorId = commentData["authorId"] as? String,
                      let authorName = commentData["authorName"] as? String,
                      let authorInitials = commentData["authorInitials"] as? String,
                      let content = commentData["content"] as? String,
                      let timestamp = commentData["timestamp"] as? Int64 else {
                    continue
                }
                rawComments.append(RawRealtimeComment(
                    id: id,
                    postId: postId,
                    authorId: authorId,
                    authorName: authorName,
                    authorInitials: authorInitials,
                    authorUsername: commentData["authorUsername"] as? String,
                    authorProfileImageURL: commentData["authorProfileImageURL"] as? String,
                    content: content,
                    timestamp: timestamp,
                    likes: commentData["likes"] as? Int ?? 0,
                    parentCommentId: commentData["parentCommentId"] as? String
                ))
            }
            // DataSnapshot is no longer referenced after this point.

            Task { @MainActor [weak self] in
                guard let self else { return }
                var comments: [RealtimeComment] = rawComments.map { raw in
                    RealtimeComment(
                        id: raw.id,
                        postId: raw.postId,
                        authorId: raw.authorId,
                        authorName: raw.authorName,
                        authorInitials: raw.authorInitials,
                        authorUsername: raw.authorUsername,
                        authorProfileImageURL: raw.authorProfileImageURL,
                        content: raw.content,
                        timestamp: Date(timeIntervalSince1970: Double(raw.timestamp) / 1000.0),
                        likes: raw.likes,
                        parentCommentId: raw.parentCommentId
                    )
                }
                comments.sort { $0.timestamp < $1.timestamp }
                self.postCommentsData[postId] = comments
            }
        }
        observers["\(postId)_commentsData"] = commentsDataHandle

    }
    
    /// Stop observing a specific post
    func stopObservingPost(postId: String) {
        // _counts: single parent-node listener (replaces the old 4 per-field listeners)
        // _commentsData: comments sub-tree listener
        let keys = ["\(postId)_counts", "\(postId)_commentsData"]
        let postRef = ref.child("postInteractions").child(postId)
        for key in keys {
            if let handle = observers[key] {
                postRef.removeObserver(withHandle: handle)
                observers.removeValue(forKey: key)
            }
        }
        observerInsertionOrder.removeAll { $0 == postId }
    }
    
    /// Stop ALL active observers — call on sign-out or when no posts are visible.
    func stopAllObservers() {
        // Each key is formatted as "\(postId)_counts" or "\(postId)_commentsData".
        // Observers were registered on child refs (postInteractions/postId), so we
        // must remove them on the same child ref, not the root ref.
        let knownSuffixes = ["_counts", "_commentsData"]
        for (key, handle) in observers {
            var postId = key
            for suffix in knownSuffixes {
                if key.hasSuffix(suffix) {
                    postId = String(key.dropLast(suffix.count))
                    break
                }
            }
            ref.child("postInteractions").child(postId).removeObserver(withHandle: handle)
        }
        observers.removeAll()
        observerInsertionOrder.removeAll()
    }
    
    // MARK: - Load User Interactions
    
    /// Load all user's interactions on app start
    private func loadUserInteractions() {
        guard currentUserId != "anonymous" else { 
            dlog("⚠️ Cannot load user interactions: anonymous user")
            return 
        }
        
        dlog("🔄 Loading user interactions for user: \(currentUserId)")
        
        // ✅ CRITICAL FIX: Don't load with getData() - it races with the observer and clears data!
        // The real-time observer (observeUserInteractions) loads from cache instantly via .observe()
        // and keeps the data synced. Using getData() here was causing the data to be cleared
        // after the observer loaded it.
        
        // ✅ FIX: Load initial data synchronously from cache before starting observer
        // This ensures UI has data immediately on app restart
        Task { @MainActor in
            await loadInitialUserInteractionsFromCache()
            observeUserInteractions()
        }
    }
    
    /// Load initial user interaction state from offline cache (blocking)
    private func loadInitialUserInteractionsFromCache() async {
        guard currentUserId != "anonymous" else { return }
        
        dlog("📦 Loading initial user interactions from cache...")
        let userInteractionsRef = ref.child("userInteractions").child(currentUserId)
        
        // ✅ FIX: Use observeSingleEvent instead of getData() for instant cache-first reads
        // getData() waits for network which causes 1-3 second delay on cold start
        // observeSingleEvent uses cached data immediately (offline persistence)
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var hasLoadedLightbulbs = false
            var hasLoadedAmens = false
            var hasLoadedReposts = false
            
            func checkCompletion() {
                if hasLoadedLightbulbs && hasLoadedAmens && hasLoadedReposts {
                    Task { @MainActor in
                        dlog("✅ Initial user interactions loaded successfully from cache")
                        self.hasLoadedInitialCache = true
                        continuation.resume()
                    }
                }
            }
            
            // Load lightbulbs (cache-first)
            userInteractionsRef.child("lightbulbs").observeSingleEvent(of: .value) { [weak self] snapshot in
                guard let self = self else { 
                    hasLoadedLightbulbs = true
                    checkCompletion()
                    return 
                }
                
                Task { @MainActor in
                    if let data = snapshot.value as? [String: Bool] {
                        self.userLightbulbedPosts = Set(data.keys)
                        dlog("✅ Loaded \(self.userLightbulbedPosts.count) lightbulbed posts from cache")
                        dlog("   💡 Post IDs: \(self.userLightbulbedPosts.map { $0.prefix(8) }.joined(separator: ", "))")
                    } else {
                        dlog("📭 No lightbulbed posts in cache")
                    }
                    hasLoadedLightbulbs = true
                    checkCompletion()
                }
            }
            
            // Load amens (cache-first)
            userInteractionsRef.child("amens").observeSingleEvent(of: .value) { [weak self] snapshot in
                guard let self = self else { 
                    hasLoadedAmens = true
                    checkCompletion()
                    return 
                }
                
                Task { @MainActor in
                    if let data = snapshot.value as? [String: Bool] {
                        self.userAmenedPosts = Set(data.keys)
                        dlog("✅ Loaded \(self.userAmenedPosts.count) amened posts from cache")
                    } else {
                        dlog("📭 No amened posts in cache")
                    }
                    hasLoadedAmens = true
                    checkCompletion()
                }
            }
            
            // Load reposts (cache-first)
            userInteractionsRef.child("reposts").observeSingleEvent(of: .value) { [weak self] snapshot in
                guard let self = self else { 
                    hasLoadedReposts = true
                    checkCompletion()
                    return 
                }
                
                Task { @MainActor in
                    if let data = snapshot.value as? [String: Bool] {
                        self.userRepostedPosts = Set(data.keys)
                        dlog("✅ Loaded \(self.userRepostedPosts.count) reposted posts from cache")
                    } else {
                        dlog("📭 No reposted posts in cache")
                    }
                    hasLoadedReposts = true
                    checkCompletion()
                }
            }
        }
    }
    
    /// Observe user's interactions in real-time
    private func observeUserInteractions() {
        guard currentUserId != "anonymous" else { 
            dlog("⚠️ Cannot observe user interactions: anonymous user")
            return 
        }
        
        dlog("👀 Starting real-time observers for user interactions")
        
        // ✅ CRITICAL FIX: Keep user interactions synced locally for offline persistence
        let userInteractionsRef = ref.child("userInteractions").child(currentUserId)
        userInteractionsRef.keepSynced(true)
        dlog("✅ Enabled offline sync for user interactions")
        
        // Observe user's lightbulbs
        userInteractionsRef.child("lightbulbs").observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let data = snapshot.value as? [String: Bool] {
                    self.userLightbulbedPosts = Set(data.keys)
                    dlog("🔄 Updated lightbulbed posts: \(self.userLightbulbedPosts.count) posts")
                    dlog("   💡 Post IDs: \(self.userLightbulbedPosts.map { $0.prefix(8) }.joined(separator: ", "))")
                } else {
                    // ✅ CRITICAL: Don't clear on empty - could be initial cache miss
                    // Only clear if we explicitly have an empty object (not nil/missing)
                    if snapshot.exists() {
                        self.userLightbulbedPosts = []
                        dlog("🔄 Cleared lightbulbed posts (explicitly empty)")
                    } else {
                        dlog("⏭️ Skipping empty snapshot (cache not ready or no data yet)")
                    }
                }
            }
        }
        
        // Observe user's amens
        userInteractionsRef.child("amens").observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let data = snapshot.value as? [String: Bool] {
                    self.userAmenedPosts = Set(data.keys)
                    dlog("🔄 Updated amened posts: \(self.userAmenedPosts.count) posts")
                } else {
                    if snapshot.exists() {
                        self.userAmenedPosts = []
                        dlog("🔄 Cleared amened posts (explicitly empty)")
                    } else {
                        dlog("⏭️ Skipping empty amen snapshot (cache not ready or no data yet)")
                    }
                }
            }
        }
        
        // Observe user's reposts
        userInteractionsRef.child("reposts").observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let data = snapshot.value as? [String: Bool] {
                    self.userRepostedPosts = Set(data.keys)
                    dlog("🔄 Updated reposted posts: \(self.userRepostedPosts.count) posts")
                } else {
                    if snapshot.exists() {
                        self.userRepostedPosts = []
                        dlog("🔄 Cleared reposted posts (explicitly empty)")
                    } else {
                        dlog("⏭️ Skipping empty repost snapshot (cache not ready or no data yet)")
                    }
                }
            }
        }
        
        dlog("✅ Real-time observers active for user interactions")
    }
    
    /// Sync user interaction to user index
    private func syncUserInteraction(type: String, postId: String, value: Bool) async throws {
        guard currentUserId != "anonymous" else { return }
        
        let userInteractionRef = ref.child("userInteractions").child(currentUserId).child(type).child(postId)
        
        if value {
            try await userInteractionRef.setValue(true)
        } else {
            try await userInteractionRef.removeValue()
        }
    }
    
    // MARK: - Batch Load
    
    /// Load interaction counts for multiple posts at once
    func loadInteractionsForPosts(_ postIds: [String]) async {
        for postId in postIds {
            async let lightbulbs = getLightbulbCount(postId: postId)
            async let amens = getAmenCount(postId: postId)
            async let comments = getCommentCount(postId: postId)
            async let reposts = getRepostCount(postId: postId)
            
            let (lightbulbCount, amenCount, commentCount, repostCount) = await (lightbulbs, amens, comments, reposts)
            
            postLightbulbs[postId] = lightbulbCount
            postAmens[postId] = amenCount
            postComments[postId] = commentCount
            postReposts[postId] = repostCount
        }
    }
    
    /// Get all interaction counts for a specific post
    func getInteractionCounts(postId: String) async -> (amenCount: Int, commentCount: Int, repostCount: Int, lightbulbCount: Int) {
        async let amens = getAmenCount(postId: postId)
        async let comments = getCommentCount(postId: postId)
        async let reposts = getRepostCount(postId: postId)
        async let lightbulbs = getLightbulbCount(postId: postId)
        
        let (amenCount, commentCount, repostCount, lightbulbCount) = await (amens, comments, reposts, lightbulbs)
        return (amenCount, commentCount, repostCount, lightbulbCount)
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        stopAllObservers()
    }
    
    deinit {
        // Schedule cleanup on MainActor since ref is MainActor-isolated.
        // stopAllObservers() removes handles directly without fragile key parsing.
        Task { @MainActor [weak self] in
            self?.stopAllObservers()
        }
    }
}

// MARK: - Realtime Comment Model

struct RealtimeComment: Identifiable, Codable {
    let id: String
    let postId: String
    let authorId: String
    let authorName: String
    let authorInitials: String
    let authorUsername: String?  // ✅ Optional username field
    let authorProfileImageURL: String?  // ✅ NEW: Profile image URL
    let content: String
    let timestamp: Date
    var likes: Int
    let parentCommentId: String?  // ✅ For tracking replies
    
    var isFromCurrentUser: Bool {
        authorId == (Auth.auth().currentUser?.uid ?? "")
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Database Connection Monitoring
extension PostInteractionsService {
    /// Monitor Firebase Realtime Database connection state
    func monitorDatabaseConnection() {
        let connectedRef = Database.database().reference(withPath: ".info/connected")
        
        var hasLoggedInitialConnection = false
        
        connectedRef.observe(.value) { snapshot in
            if let connected = snapshot.value as? Bool {
                #if DEBUG
                // Only log initial connection and disconnections (not reconnections)
                if connected && !hasLoggedInitialConnection {
                    dlog("✅ Firebase Realtime Database: CONNECTED")
                    hasLoggedInitialConnection = true
                } else if !connected {
                    dlog("⚠️ Firebase Realtime Database: DISCONNECTED (will auto-reconnect)")
                }
                #endif
            }
        }
    }
}

// MARK: - Notification Helper Extension
extension PostInteractionsService {
    /// Get post author ID from Firestore
    private func getPostAuthorId(postId: String) async throws -> String {
        let postDoc = try await firestore.collection("posts").document(postId).getDocument()
        guard let authorId = postDoc.data()?["authorId"] as? String else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "Post author not found"])
        }
        return authorId
    }
    
    /// Create a notification in Firestore for post reactions
    private func createNotification(
        type: String,
        postId: String,
        postAuthorId: String
    ) async throws {
        // Don't notify if user reacts to their own post
        guard postAuthorId != currentUserId else { return }
        
        // Get current user's profile data
        let userDoc = try await firestore.collection("users").document(currentUserId).getDocument()
        let userData = userDoc.data()
        
        let notification: [String: Any] = [
            "type": type,
            "actorId": currentUserId,
            "actorName": currentUserName,
            "actorUsername": userData?["username"] as? String ?? "",
            "actorProfileImageURL": userData?["profileImageURL"] as? String ?? "",
            "postId": postId,
            "userId": postAuthorId,
            "read": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        // Write to the top-level /notifications collection.
        // The NotificationService listener reads from this collection filtered by userId.
        // This avoids writing to another user's subcollection (which requires App Check
        // to pass, causing 403 errors on simulator where App Check uses a debug token).
        // Deterministic ID prevents duplicate notifications for the same action.
        let deterministicId = "\(type)_\(postId)_\(currentUserId)"
        try await firestore.collection("notifications")
            .document(deterministicId)
            .setData(notification, merge: true)
    }
}
