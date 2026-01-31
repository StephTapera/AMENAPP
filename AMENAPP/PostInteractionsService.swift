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
        print("✅ PostInteractions Database initialized successfully")
        _database = db
        return db
    }
    
    private var ref: DatabaseReference {
        database.reference()
    }
    
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
    
    private init() {
        loadUserInteractions()
        Task {
            await loadUserDisplayName()
        }
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
            
            print("💡 Lightbulb removed from post: \(postId)")
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
            
            print("💡 Lightbulb added to post: \(postId)")
        }
    }
    
    /// Check if user has lit lightbulb on post
    func hasLitLightbulb(postId: String) async -> Bool {
        guard currentUserId != "anonymous" else { return false }
        
        do {
            let snapshot = try await ref.child("postInteractions").child(postId).child("lightbulbs").child(currentUserId).getData()
            return snapshot.exists()
        } catch {
            print("❌ Failed to check lightbulb status: \(error)")
            return false
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
            
            print("🙏 Amen removed from post: \(postId)")
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
            
            print("🙏 Amen added to post: \(postId)")
        }
    }
    
    /// Check if user has amened post
    func hasAmened(postId: String) async -> Bool {
        guard currentUserId != "anonymous" else { return false }
        
        do {
            let snapshot = try await ref.child("postInteractions").child(postId).child("amens").child(currentUserId).getData()
            return snapshot.exists()
        } catch {
            print("❌ Failed to check amen status: \(error)")
            return false
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
    func addComment(postId: String, content: String, authorInitials: String = "??", authorUsername: String) async throws -> String {
        guard currentUserId != "anonymous" else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let commentRef = ref.child("postInteractions").child(postId).child("comments").childByAutoId()
        
        guard let commentId = commentRef.key else {
            throw NSError(domain: "PostInteractions", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate comment ID"])
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        let commentData: [String: Any] = [
            "id": commentId,
            "postId": postId,
            "authorId": currentUserId,
            "authorName": currentUserName,
            "authorInitials": authorInitials,
            "authorUsername": authorUsername,  // ✅ NEW: Store username
            "content": content,
            "timestamp": timestamp,
            "likes": 0
        ]
        
        try await commentRef.setValue(commentData)
        
        // Increment comment count
        try await ref.child("postInteractions").child(postId).child("commentCount").setValue(ServerValue.increment(1))
        
        // Update local state
        postComments[postId] = (postComments[postId] ?? 0) + 1
        
        print("💬 Comment added to post: \(postId) by @\(authorUsername)")
        
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
        do {
            let snapshot = try await ref.child("postInteractions").child(postId).child("comments").getData()
            
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
                // ✅ NEW: Read username from RTDB if available
                let authorUsername = commentData["authorUsername"] as? String
                
                let comment = RealtimeComment(
                    id: id,
                    postId: postId,
                    authorId: authorId,
                    authorName: authorName,
                    authorInitials: authorInitials,
                    authorUsername: authorUsername,  // ✅ Pass username
                    content: content,
                    timestamp: Date(timeIntervalSince1970: Double(timestamp) / 1000.0),
                    likes: likes
                )
                
                comments.append(comment)
            }
            
            // Sort by timestamp
            comments.sort { $0.timestamp < $1.timestamp }
            
            return comments
        } catch {
            print("❌ Failed to get comments: \(error)")
            return []
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
            
            print("🔄 Repost removed from post: \(postId)")
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
            
            print("🔄 Repost added to post: \(postId)")
            return true
        }
    }
    
    /// Check if user has reposted post
    func hasReposted(postId: String) async -> Bool {
        guard currentUserId != "anonymous" else { return false }
        
        do {
            let snapshot = try await ref.child("postInteractions").child(postId).child("reposts").child(currentUserId).getData()
            return snapshot.exists()
        } catch {
            print("❌ Failed to check repost status: \(error)")
            return false
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
                
                let comment = RealtimeComment(
                    id: id,
                    postId: postId,
                    authorId: authorId,
                    authorName: authorName,
                    authorInitials: authorInitials,
                    authorUsername: authorUsername,  // ✅ Pass username
                    content: content,
                    timestamp: Date(timeIntervalSince1970: Double(timestamp) / 1000.0),
                    likes: likes
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
        guard currentUserId != "anonymous" else { return }
        
        Task {
            // Load lightbulbs
            let lightbulbsSnapshot = try? await ref.child("userInteractions").child(currentUserId).child("lightbulbs").getData()
            if let lightbulbsData = lightbulbsSnapshot?.value as? [String: Bool] {
                userLightbulbedPosts = Set(lightbulbsData.keys)
            }
            
            // Load amens
            let amensSnapshot = try? await ref.child("userInteractions").child(currentUserId).child("amens").getData()
            if let amensData = amensSnapshot?.value as? [String: Bool] {
                userAmenedPosts = Set(amensData.keys)
            }
            
            // Load reposts
            let repostsSnapshot = try? await ref.child("userInteractions").child(currentUserId).child("reposts").getData()
            if let repostsData = repostsSnapshot?.value as? [String: Bool] {
                userRepostedPosts = Set(repostsData.keys)
            }
            
            print("✅ Loaded user interactions")
        }
        
        // Observe user interactions in real-time
        observeUserInteractions()
    }
    
    /// Observe user's interactions in real-time
    private func observeUserInteractions() {
        guard currentUserId != "anonymous" else { return }
        
        // Observe user's lightbulbs
        ref.child("userInteractions").child(currentUserId).child("lightbulbs").observe(.value) { [weak self] snapshot in
            guard let self = self,
                  let data = snapshot.value as? [String: Bool] else { return }
            self.userLightbulbedPosts = Set(data.keys)
        }
        
        // Observe user's amens
        ref.child("userInteractions").child(currentUserId).child("amens").observe(.value) { [weak self] snapshot in
            guard let self = self,
                  let data = snapshot.value as? [String: Bool] else { return }
            self.userAmenedPosts = Set(data.keys)
        }
        
        // Observe user's reposts
        ref.child("userInteractions").child(currentUserId).child("reposts").observe(.value) { [weak self] snapshot in
            guard let self = self,
                  let data = snapshot.value as? [String: Bool] else { return }
            self.userRepostedPosts = Set(data.keys)
        }
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
    let authorUsername: String?  // ✅ NEW: Optional username field
    let content: String
    let timestamp: Date
    var likes: Int
    
    var isFromCurrentUser: Bool {
        authorId == (Auth.auth().currentUser?.uid ?? "")
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
