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
        let databaseURL = "https://amen-5e359-default-rtdb.firebaseio.com"
        print("🔥 Initializing PostInteractions Database with URL: [\(databaseURL)]")
        let db = Database.database(url: databaseURL)
        
        // ✅ NOTE: Offline persistence is already enabled globally in AppDelegate.swift
        // No need to call isPersistenceEnabled here (would crash if called after first access)
        print("✅ PostInteractions Database initialized successfully (using global persistence)")
        
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
    
    private var observers: [String: DatabaseHandle] = [:]
    
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
                print("✅ Loaded user display name: \(displayName)")
                
                // Also update Firebase Auth profile if needed
                if Auth.auth().currentUser?.displayName != displayName {
                    let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest()
                    changeRequest?.displayName = displayName
                    try? await changeRequest?.commitChanges()
                    print("✅ Updated Auth displayName")
                }
            }
        } catch {
            print("⚠️ Could not load user display name: \(error)")
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
        
        let userLightbulbRef = ref.child("postInteractions").child(postId).child("lightbulbs").child(currentUserId)
        
        // Check current state
        let snapshot = try await userLightbulbRef.getData()
        let isCurrentlyLit = snapshot.exists()
        
        if isCurrentlyLit {
            // Remove lightbulb
            try await userLightbulbRef.removeValue()
            
            // Decrement count
            try await ref.child("postInteractions").child(postId).child("lightbulbCount").setValue(ServerValue.increment(-1))
            
            // Update user interaction index
            try await syncUserInteraction(type: "lightbulbs", postId: postId, value: false)
            
            // Update local state
            userLightbulbedPosts.remove(postId)
            if let currentCount = postLightbulbs[postId] {
                postLightbulbs[postId] = max(0, currentCount - 1)
            }
            
            print("💡 [DEBUG] Lightbulb removed from post: \(postId)")
            print("   - User: \(currentUserId)")
            print("   - New count: \(postLightbulbs[postId] ?? 0)")
            print("   - User's total lightbulbs: \(userLightbulbedPosts.count)")
        } else {
            // Add lightbulb
            try await userLightbulbRef.setValue([
                "userId": currentUserId,
                "userName": currentUserName,
                "timestamp": ServerValue.timestamp()
            ])
            
            // Increment count
            try await ref.child("postInteractions").child(postId).child("lightbulbCount").setValue(ServerValue.increment(1))
            
            // Update user interaction index
            try await syncUserInteraction(type: "lightbulbs", postId: postId, value: true)
            
            // Update local state
            userLightbulbedPosts.insert(postId)
            postLightbulbs[postId] = (postLightbulbs[postId] ?? 0) + 1
            
            // ✅ OPTIMIZED: Create notification asynchronously (fire-and-forget, doesn't block UI)
            Task.detached { [weak self] in
                guard let self = self else { return }
                if let postAuthorId = try? await self.getPostAuthorId(postId: postId) {
                    try? await self.createNotification(type: "lightbulb", postId: postId, postAuthorId: postAuthorId)
                }
            }
            
            print("💡 [DEBUG] Lightbulb added to post: \(postId)")
            print("   - User: \(currentUserId)")
            print("   - New count: \(postLightbulbs[postId] ?? 1)")
            print("   - User's total lightbulbs: \(userLightbulbedPosts.count)")
        }
    }
    
    /// Check if user has lit lightbulb on post
    func hasLitLightbulb(postId: String) async -> Bool {
        guard currentUserId != "anonymous" else { return false }
        
        // ✅ Check the user interactions index (canonical source of truth for user's lightbulb state)
        do {
            let snapshot = try await ref.child("userInteractions").child(currentUserId).child("lightbulbs").child(postId).getData()
            let exists = snapshot.exists()
            
            // ✅ Sync cache with RTDB state to ensure consistency
            // Delay updates to prevent "multiple updates per frame" warning when loading many posts
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
            
            if exists && !userLightbulbedPosts.contains(postId) {
                userLightbulbedPosts.insert(postId)
                print("💡 Added \(postId.prefix(8)) to lightbulb cache from RTDB query")
            } else if !exists && userLightbulbedPosts.contains(postId) {
                userLightbulbedPosts.remove(postId)
                print("💡 Removed \(postId.prefix(8)) from lightbulb cache (not in RTDB)")
            }
            
            return exists
        } catch {
            print("❌ Failed to check lightbulb status: \(error)")
            // Return cache state on error
            return userLightbulbedPosts.contains(postId)
        }
    }
    
    /// Get lightbulb count for post
    func getLightbulbCount(postId: String) async -> Int {
        do {
            let snapshot = try await ref.child("postInteractions").child(postId).child("lightbulbCount").getData()
            return snapshot.value as? Int ?? 0
        } catch {
            print("❌ Failed to get lightbulb count: \(error)")
            return 0
        }
    }
    
    // MARK: - Amen (🙏) Actions
    
    /// Toggle amen on a post
    func toggleAmen(postId: String) async throws {
        guard currentUserId != "anonymous" else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let userAmenRef = ref.child("postInteractions").child(postId).child("amens").child(currentUserId)
        
        // Check current state
        let snapshot = try await userAmenRef.getData()
        let isCurrentlyAmened = snapshot.exists()
        
        if isCurrentlyAmened {
            // Remove amen
            try await userAmenRef.removeValue()
            
            // Decrement count
            try await ref.child("postInteractions").child(postId).child("amenCount").setValue(ServerValue.increment(-1))
            
            // Update user interaction index
            try await syncUserInteraction(type: "amens", postId: postId, value: false)
            
            // Update local state
            userAmenedPosts.remove(postId)
            if let currentCount = postAmens[postId] {
                postAmens[postId] = max(0, currentCount - 1)
            }
            
            print("🙏 [DEBUG] Amen removed from post: \(postId)")
            print("   - User: \(currentUserId)")
            print("   - New count: \(postAmens[postId] ?? 0)")
            print("   - User's total amens: \(userAmenedPosts.count)")
        } else {
            // Add amen
            try await userAmenRef.setValue([
                "userId": currentUserId,
                "userName": currentUserName,
                "timestamp": ServerValue.timestamp()
            ])
            
            // Increment count
            try await ref.child("postInteractions").child(postId).child("amenCount").setValue(ServerValue.increment(1))
            
            // Update user interaction index
            try await syncUserInteraction(type: "amens", postId: postId, value: true)
            
            // Update local state
            userAmenedPosts.insert(postId)
            postAmens[postId] = (postAmens[postId] ?? 0) + 1
            
            // ✅ OPTIMIZED: Create notification asynchronously (fire-and-forget, doesn't block UI)
            Task.detached { [weak self] in
                guard let self = self else { return }
                if let postAuthorId = try? await self.getPostAuthorId(postId: postId) {
                    try? await self.createNotification(type: "amen", postId: postId, postAuthorId: postAuthorId)
                }
            }
            
            print("🙏 [DEBUG] Amen added to post: \(postId)")
            print("   - User: \(currentUserId)")
            print("   - New count: \(postAmens[postId] ?? 1)")
            print("   - User's total amens: \(userAmenedPosts.count)")
        }
    }
    
    /// Check if user has amened post
    func hasAmened(postId: String) async -> Bool {
        guard currentUserId != "anonymous" else { return false }
        
        // ✅ Check the user interactions index (canonical source of truth)
        do {
            let snapshot = try await ref.child("userInteractions").child(currentUserId).child("amens").child(postId).getData()
            let exists = snapshot.exists()
            
            // ✅ Sync cache with RTDB state to ensure consistency
            // Delay updates to prevent "multiple updates per frame" warning when loading many posts
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms delay (stagger from lightbulb)
            
            if exists && !userAmenedPosts.contains(postId) {
                userAmenedPosts.insert(postId)
                print("🙏 Added \(postId.prefix(8)) to amen cache from RTDB query")
            } else if !exists && userAmenedPosts.contains(postId) {
                userAmenedPosts.remove(postId)
                print("🙏 Removed \(postId.prefix(8)) from amen cache (not in RTDB)")
            }
            
            return exists
        } catch {
            print("❌ Failed to check amen status: \(error)")
            // Return cache state on error
            return userAmenedPosts.contains(postId)
        }
    }
    
    /// Get amen count for post
    func getAmenCount(postId: String) async -> Int {
        do {
            let snapshot = try await ref.child("postInteractions").child(postId).child("amenCount").getData()
            return snapshot.value as? Int ?? 0
        } catch {
            print("❌ Failed to get amen count: \(error)")
            return 0
        }
    }
    
    // MARK: - Comments
    
    /// Add a comment to a post
    func addComment(
        postId: String, 
        content: String, 
        authorInitials: String = "??", 
        authorUsername: String,
        authorProfileImageURL: String? = nil  // ✅ NEW PARAMETER
    ) async throws -> String {
        guard currentUserId != "anonymous" else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
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
            print("✅ Storing profile image URL in comment: \(profileImageURL)")
        }
        
        do {
            try await commentRef.setValue(commentData)
            print("✅ Comment data written to RTDB successfully")
            print("   Path: postInteractions/\(postId)/comments/\(commentId)")
            print("   Data keys: \(commentData.keys.joined(separator: ", "))")
        } catch {
            print("❌ CRITICAL: Failed to write comment to RTDB: \(error)")
            throw error
        }
        
        // Increment comment count
        do {
            try await ref.child("postInteractions").child(postId).child("commentCount").setValue(ServerValue.increment(1))
            print("✅ Comment count incremented successfully")
        } catch {
            print("⚠️ Warning: Failed to increment comment count: \(error)")
            // Don't throw - comment was still created
        }
        
        // Update local state
        postComments[postId] = (postComments[postId] ?? 0) + 1
        
        print("💬 Comment added to post: \(postId) by @\(authorUsername)")
        print("🔍 You can verify at: postInteractions/\(postId)/comments")
        
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
        
        // Decrement comment count
        try await ref.child("postInteractions").child(postId).child("commentCount").setValue(ServerValue.increment(-1))
        
        // Update local state
        if let currentCount = postComments[postId] {
            postComments[postId] = max(0, currentCount - 1)
        }
        
        print("💬 Comment deleted: \(commentId)")
    }
    
    /// Get comments for a post
    func getComments(postId: String) async -> [RealtimeComment] {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 [RTDB] GET COMMENTS CALLED")
        print("🔍 [RTDB] Post ID: \(postId)")
        print("🔍 [RTDB] Querying path: postInteractions/\(postId)/comments")
        print("🔍 [RTDB] Database URL: \(database.app?.options.databaseURL ?? "unknown")")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // ✅ FIX: Use observeSingleEvent instead of getData() to properly use offline cache
        // getData() bypasses cache on cold start, observeSingleEvent uses cache-first approach
        return await withCheckedContinuation { continuation in
            print("🔍 [RTDB] Using observeSingleEvent for cache-friendly loading...")
            
            ref.child("postInteractions").child(postId).child("comments")
                .observeSingleEvent(of: .value) { snapshot in
                    print("🔍 [RTDB] observeSingleEvent returned successfully")
                    print("🔍 [RTDB] Snapshot exists: \(snapshot.exists()), hasChildren: \(snapshot.hasChildren())")
                    print("🔍 [RTDB] Children count: \(snapshot.childrenCount)")

                    // Debug: Print raw snapshot value
                    if let rawValue = snapshot.value {
                        print("🔍 [RTDB] Raw snapshot value type: \(type(of: rawValue))")
                        if let dict = rawValue as? [String: Any] {
                            print("🔍 [RTDB] Comment IDs in snapshot: \(dict.keys.joined(separator: ", "))")
                        }
                    } else {
                        print("⚠️ [RTDB] Snapshot value is nil!")
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
                    
                    print("✅ [RTDB] Successfully parsed \(comments.count) comments")
                    for comment in comments {
                        print("   📝 ID: \(comment.id) - Content: \"\(comment.content)\"")
                    }
                    
                    continuation.resume(returning: comments)
                } withCancel: { error in
                    print("❌ [RTDB] Failed to get comments: \(error)")
                    print("   Error details: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                }
        }
    }
    
    /// Get comment count for post
    func getCommentCount(postId: String) async -> Int {
        do {
            let snapshot = try await ref.child("postInteractions").child(postId).child("commentCount").getData()
            return snapshot.value as? Int ?? 0
        } catch {
            print("❌ Failed to get comment count: \(error)")
            return 0
        }
    }
    
    // MARK: - Reposts
    
    /// Toggle repost on a post
    func toggleRepost(postId: String) async throws -> Bool {
        guard currentUserId != "anonymous" else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let userRepostRef = ref.child("postInteractions").child(postId).child("reposts").child(currentUserId)
        
        // Check current state
        let snapshot = try await userRepostRef.getData()
        let isCurrentlyReposted = snapshot.exists()
        
        if isCurrentlyReposted {
            // Remove repost
            try await userRepostRef.removeValue()
            
            // Decrement count
            try await ref.child("postInteractions").child(postId).child("repostCount").setValue(ServerValue.increment(-1))
            
            // Update user interaction index
            try await syncUserInteraction(type: "reposts", postId: postId, value: false)
            
            // Update local state
            userRepostedPosts.remove(postId)
            if let currentCount = postReposts[postId] {
                postReposts[postId] = max(0, currentCount - 1)
            }
            
            print("🔄 [DEBUG] Repost removed from post: \(postId)")
            print("   - User: \(currentUserId)")
            print("   - New count: \(postReposts[postId] ?? 0)")
            print("   - User's total reposts: \(userRepostedPosts.count)")
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
            
            // Update user interaction index
            try await syncUserInteraction(type: "reposts", postId: postId, value: true)
            
            // Update local state
            userRepostedPosts.insert(postId)
            postReposts[postId] = (postReposts[postId] ?? 0) + 1
            
            print("🔄 [DEBUG] Repost added to post: \(postId)")
            print("   - User: \(currentUserId)")
            print("   - New count: \(postReposts[postId] ?? 1)")
            print("   - User's total reposts: \(userRepostedPosts.count)")
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
            
            // ✅ Sync cache with RTDB state to ensure consistency
            // Delay updates to prevent "multiple updates per frame" warning when loading many posts
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms delay (stagger from lightbulb/amen)
            
            if exists && !userRepostedPosts.contains(postId) {
                userRepostedPosts.insert(postId)
                print("🔄 Added \(postId.prefix(8)) to repost cache from RTDB query")
            } else if !exists && userRepostedPosts.contains(postId) {
                userRepostedPosts.remove(postId)
                print("🔄 Removed \(postId.prefix(8)) from repost cache (not in RTDB)")
            }
            
            return exists
        } catch {
            print("❌ Failed to check repost status: \(error)")
            // Return cache state on error
            return userRepostedPosts.contains(postId)
        }
    }
    
    /// Get repost count for post
    func getRepostCount(postId: String) async -> Int {
        do {
            let snapshot = try await ref.child("postInteractions").child(postId).child("repostCount").getData()
            return snapshot.value as? Int ?? 0
        } catch {
            print("❌ Failed to get repost count: \(error)")
            return 0
        }
    }
    
    // MARK: - Real-time Observers
    
    /// Observe interactions for a specific post
    func observePostInteractions(postId: String) {
        // Remove existing observers
        stopObservingPost(postId: postId)
        
        let postRef = ref.child("postInteractions").child(postId)
        
        // Observe lightbulb count
        let lightbulbHandle = postRef.child("lightbulbCount").observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            let count = snapshot.value as? Int ?? 0
            self.postLightbulbs[postId] = count
        }
        observers["\(postId)_lightbulbs"] = lightbulbHandle
        
        // Observe amen count
        let amenHandle = postRef.child("amenCount").observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            let count = snapshot.value as? Int ?? 0
            self.postAmens[postId] = count
        }
        observers["\(postId)_amens"] = amenHandle
        
        // Observe comment count
        let commentHandle = postRef.child("commentCount").observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            let count = snapshot.value as? Int ?? 0
            self.postComments[postId] = count
        }
        observers["\(postId)_comments"] = commentHandle
        
        // Observe repost count
        let repostHandle = postRef.child("repostCount").observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            let count = snapshot.value as? Int ?? 0
            self.postReposts[postId] = count
        }
        observers["\(postId)_reposts"] = repostHandle
        
        // Observe comments data
        let commentsDataHandle = postRef.child("comments").observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
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
                // ✅ NEW: Read username from RTDB
                let authorUsername = commentData["authorUsername"] as? String
                // ✅ NEW: Read profile image URL from RTDB
                let authorProfileImageURL = commentData["authorProfileImageURL"] as? String
                // ✅ NEW: Read parentCommentId for replies
                let parentCommentId = commentData["parentCommentId"] as? String
                
                let comment = RealtimeComment(
                    id: id,
                    postId: postId,
                    authorId: authorId,
                    authorName: authorName,
                    authorInitials: authorInitials,
                    authorUsername: authorUsername,  // ✅ Pass username
                    authorProfileImageURL: authorProfileImageURL,  // ✅ Pass profile image URL
                    content: content,
                    timestamp: Date(timeIntervalSince1970: Double(timestamp) / 1000.0),
                    likes: likes,
                    parentCommentId: parentCommentId  // ✅ Pass parentCommentId
                )
                
                comments.append(comment)
            }
            
            comments.sort { $0.timestamp < $1.timestamp }
            self.postCommentsData[postId] = comments
        }
        observers["\(postId)_commentsData"] = commentsDataHandle
        
        print("👀 Observing interactions for post: \(postId)")
    }
    
    /// Stop observing a specific post
    func stopObservingPost(postId: String) {
        let pathMapping: [String: String] = [
            "\(postId)_lightbulbs": "lightbulbCount",
            "\(postId)_amens": "amenCount",
            "\(postId)_comments": "commentCount",
            "\(postId)_reposts": "repostCount",
            "\(postId)_commentsData": "comments"
        ]
        
        for (key, path) in pathMapping {
            if let handle = observers[key] {
                ref.child("postInteractions").child(postId).child(path).removeObserver(withHandle: handle)
                observers.removeValue(forKey: key)
            }
        }
        
        print("🔇 Stopped observing post: \(postId)")
    }
    
    // MARK: - Load User Interactions
    
    /// Load all user's interactions on app start
    private func loadUserInteractions() {
        guard currentUserId != "anonymous" else { 
            print("⚠️ Cannot load user interactions: anonymous user")
            return 
        }
        
        print("🔄 Loading user interactions for user: \(currentUserId)")
        
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
        
        print("📦 Loading initial user interactions from cache...")
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
                        print("✅ Initial user interactions loaded successfully from cache")
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
                        print("✅ Loaded \(self.userLightbulbedPosts.count) lightbulbed posts from cache")
                        print("   💡 Post IDs: \(self.userLightbulbedPosts.map { $0.prefix(8) }.joined(separator: ", "))")
                    } else {
                        print("📭 No lightbulbed posts in cache")
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
                        print("✅ Loaded \(self.userAmenedPosts.count) amened posts from cache")
                    } else {
                        print("📭 No amened posts in cache")
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
                        print("✅ Loaded \(self.userRepostedPosts.count) reposted posts from cache")
                    } else {
                        print("📭 No reposted posts in cache")
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
            print("⚠️ Cannot observe user interactions: anonymous user")
            return 
        }
        
        print("👀 Starting real-time observers for user interactions")
        
        // ✅ CRITICAL FIX: Keep user interactions synced locally for offline persistence
        let userInteractionsRef = ref.child("userInteractions").child(currentUserId)
        userInteractionsRef.keepSynced(true)
        print("✅ Enabled offline sync for user interactions")
        
        // Observe user's lightbulbs
        userInteractionsRef.child("lightbulbs").observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let data = snapshot.value as? [String: Bool] {
                    self.userLightbulbedPosts = Set(data.keys)
                    print("🔄 Updated lightbulbed posts: \(self.userLightbulbedPosts.count) posts")
                    print("   💡 Post IDs: \(self.userLightbulbedPosts.map { $0.prefix(8) }.joined(separator: ", "))")
                } else {
                    // ✅ CRITICAL: Don't clear on empty - could be initial cache miss
                    // Only clear if we explicitly have an empty object (not nil/missing)
                    if snapshot.exists() {
                        self.userLightbulbedPosts = []
                        print("🔄 Cleared lightbulbed posts (explicitly empty)")
                    } else {
                        print("⏭️ Skipping empty snapshot (cache not ready or no data yet)")
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
                    print("🔄 Updated amened posts: \(self.userAmenedPosts.count) posts")
                } else {
                    if snapshot.exists() {
                        self.userAmenedPosts = []
                        print("🔄 Cleared amened posts (explicitly empty)")
                    } else {
                        print("⏭️ Skipping empty amen snapshot (cache not ready or no data yet)")
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
                    print("🔄 Updated reposted posts: \(self.userRepostedPosts.count) posts")
                } else {
                    if snapshot.exists() {
                        self.userRepostedPosts = []
                        print("🔄 Cleared reposted posts (explicitly empty)")
                    } else {
                        print("⏭️ Skipping empty repost snapshot (cache not ready or no data yet)")
                    }
                }
            }
        }
        
        print("✅ Real-time observers active for user interactions")
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
        // Remove all observers
        for (key, handle) in observers {
            let components = key.split(separator: "_")
            if components.count == 2 {
                let postId = String(components[0])
                let path = String(components[1])
                ref.child("postInteractions").child(postId).child(path).removeObserver(withHandle: handle)
            }
        }
        observers.removeAll()
    }
    
    deinit {
        Task { @MainActor in
            cleanup()
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
        let connectedRef = Database.database(url: "https://amen-5e359-default-rtdb.firebaseio.com").reference(withPath: ".info/connected")
        
        var hasLoggedInitialConnection = false
        
        connectedRef.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            if let connected = snapshot.value as? Bool {
                #if DEBUG
                // Only log initial connection and disconnections (not reconnections)
                if connected && !hasLoggedInitialConnection {
                    print("✅ Firebase Realtime Database: CONNECTED")
                    hasLoggedInitialConnection = true
                } else if !connected {
                    print("⚠️ Firebase Realtime Database: DISCONNECTED (will auto-reconnect)")
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
        
        try await firestore.collection("users")
            .document(postAuthorId)
            .collection("notifications")
            .addDocument(data: notification)
    }
}
