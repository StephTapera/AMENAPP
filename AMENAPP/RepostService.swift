//
//  RepostService.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Service for handling reposts with optional comments
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class RepostService: ObservableObject {
    static let shared = RepostService()
    
    @Published var reposts: [Repost] = []
    @Published var repostedPostIds: Set<String> = []  // For quick lookups
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebaseManager = FirebaseManager.shared
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    
    private init() {}
    
    // MARK: - Create Repost
    
    /// Repost a post to user's profile (with optional comment)
    func repost(postId: String, withComment comment: String? = nil) async throws {
        print("🔄 Reposting post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Check if already reposted
        if await hasReposted(postId: postId) {
            print("⚠️ Already reposted this post")
            throw NSError(domain: "RepostService", code: 409, userInfo: [
                NSLocalizedDescriptionKey: "You have already reposted this post"
            ])
        }
        
        // Fetch original post
        let originalPostDoc = try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .getDocument()
        
        guard let originalPost = try? originalPostDoc.data(as: FirestorePost.self) else {
            throw FirebaseError.documentNotFound
        }
        
        // Fetch current user data
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(userId)
            .getDocument()
        
        guard let userData = userDoc.data() else {
            throw FirebaseError.documentNotFound
        }
        
        let displayName = userData["displayName"] as? String ?? "Unknown User"
        let username = userData["username"] as? String ?? "unknown"
        let initials = userData["initials"] as? String ?? "??"
        let profileImageURL = userData["profileImageURL"] as? String
        
        // Create repost tracking document
        let repost = Repost(
            userId: userId,
            originalPostId: postId,
            withComment: comment
        )
        
        // Create new post as a repost
        let repostPost = FirestorePost(
            authorId: userId,
            authorName: displayName,
            authorUsername: username,
            authorInitials: initials,
            authorProfileImageURL: profileImageURL,
            content: originalPost.content,
            category: originalPost.category,
            topicTag: originalPost.topicTag,
            visibility: "everyone",  // Reposts are always public
            allowComments: true,
            imageURLs: originalPost.imageURLs,
            linkURL: originalPost.linkURL,
            isRepost: true,
            originalPostId: postId,
            originalAuthorId: originalPost.authorId,
            originalAuthorName: originalPost.authorName
        )
        
        // Use batch write for atomicity
        let batch = db.batch()
        
        // 1. Add repost tracking document
        let repostRef = db.collection(FirebaseManager.CollectionPath.reposts).document()
        try batch.setData(from: repost, forDocument: repostRef)
        
        // 2. Create the repost post
        let repostPostRef = db.collection(FirebaseManager.CollectionPath.posts).document()
        try batch.setData(from: repostPost, forDocument: repostPostRef)
        
        // 3. Increment repost count on original post
        let originalPostRef = db.collection(FirebaseManager.CollectionPath.posts).document(postId)
        batch.updateData([
            "repostCount": FieldValue.increment(Int64(1)),
            "updatedAt": Date()
        ], forDocument: originalPostRef)
        
        // 4. Increment user's post count
        let userRef = db.collection(FirebaseManager.CollectionPath.users).document(userId)
        batch.updateData([
            "postsCount": FieldValue.increment(Int64(1)),
            "updatedAt": Date()
        ], forDocument: userRef)
        
        // Commit batch
        try await batch.commit()
        
        print("✅ Post reposted successfully")
        
        // Update local cache
        var repostWithId = repost
        repostWithId.id = repostRef.documentID
        reposts.append(repostWithId)
        repostedPostIds.insert(postId)
        
        // Create notification for original post author
        if originalPost.authorId != userId {
            try? await createRepostNotification(
                originalPostId: postId,
                originalAuthorId: originalPost.authorId,
                reposterName: displayName
            )
        }
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    /// Unrepost (remove repost)
    func unrepost(postId: String) async throws {
        print("🗑️ Unreposting post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Find the repost tracking document
        let repostQuery = db.collection(FirebaseManager.CollectionPath.reposts)
            .whereField("userId", isEqualTo: userId)
            .whereField("originalPostId", isEqualTo: postId)
            .limit(to: 1)
        
        let repostSnapshot = try await repostQuery.getDocuments()
        
        guard let repostDoc = repostSnapshot.documents.first else {
            throw FirebaseError.documentNotFound
        }
        
        // Find the repost post document
        let repostPostQuery = db.collection(FirebaseManager.CollectionPath.posts)
            .whereField("authorId", isEqualTo: userId)
            .whereField("isRepost", isEqualTo: true)
            .whereField("originalPostId", isEqualTo: postId)
            .limit(to: 1)
        
        let repostPostSnapshot = try await repostPostQuery.getDocuments()
        
        // Use batch write
        let batch = db.batch()
        
        // 1. Delete repost tracking document
        batch.deleteDocument(repostDoc.reference)
        
        // 2. Delete repost post (if exists)
        if let repostPostDoc = repostPostSnapshot.documents.first {
            batch.deleteDocument(repostPostDoc.reference)
        }
        
        // 3. Decrement repost count on original post
        let originalPostRef = db.collection(FirebaseManager.CollectionPath.posts).document(postId)
        batch.updateData([
            "repostCount": FieldValue.increment(Int64(-1)),
            "updatedAt": Date()
        ], forDocument: originalPostRef)
        
        // 4. Decrement user's post count
        let userRef = db.collection(FirebaseManager.CollectionPath.users).document(userId)
        batch.updateData([
            "postsCount": FieldValue.increment(Int64(-1)),
            "updatedAt": Date()
        ], forDocument: userRef)
        
        // Commit batch
        try await batch.commit()
        
        print("✅ Repost removed")
        
        // Update local cache
        reposts.removeAll { $0.originalPostId == postId }
        repostedPostIds.remove(postId)
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    /// Toggle repost status
    func toggleRepost(postId: String, withComment comment: String? = nil) async throws {
        if await hasReposted(postId: postId) {
            try await unrepost(postId: postId)
        } else {
            try await repost(postId: postId, withComment: comment)
        }
    }
    
    // MARK: - Fetch Reposts
    
    /// Fetch all reposts by current user
    func fetchUserReposts() async throws -> [Repost] {
        print("📥 Fetching user's reposts...")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.reposts)
            .whereField("userId", isEqualTo: userId)
            .order(by: "repostedAt", descending: true)
            .getDocuments()
        
        let fetchedReposts = try snapshot.documents.compactMap { doc in
            try doc.data(as: Repost.self)
        }
        
        print("✅ Fetched \(fetchedReposts.count) reposts")
        
        // Update local cache
        reposts = fetchedReposts
        repostedPostIds = Set(fetchedReposts.map { $0.originalPostId })
        
        return fetchedReposts
    }
    
    /// Fetch all users who reposted a specific post
    func fetchRepostsForPost(postId: String) async throws -> [Repost] {
        print("📥 Fetching reposts for post: \(postId)")
        
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.reposts)
            .whereField("originalPostId", isEqualTo: postId)
            .order(by: "repostedAt", descending: true)
            .getDocuments()
        
        let fetchedReposts = try snapshot.documents.compactMap { doc in
            try doc.data(as: Repost.self)
        }
        
        print("✅ Fetched \(fetchedReposts.count) reposts for post")
        
        return fetchedReposts
    }
    
    /// Check if user has reposted a post
    func hasReposted(postId: String) async -> Bool {
        guard let userId = firebaseManager.currentUser?.uid else {
            return false
        }
        
        // First check local cache
        if repostedPostIds.contains(postId) {
            return true
        }
        
        // If not in cache, check Firestore
        do {
            let query = db.collection(FirebaseManager.CollectionPath.reposts)
                .whereField("userId", isEqualTo: userId)
                .whereField("originalPostId", isEqualTo: postId)
                .limit(to: 1)
            
            let snapshot = try await query.getDocuments()
            let hasReposted = !snapshot.documents.isEmpty
            
            if hasReposted {
                repostedPostIds.insert(postId)
            }
            
            return hasReposted
        } catch {
            print("❌ Error checking repost status: \(error)")
            return false
        }
    }
    
    // MARK: - Quote Repost (Repost with Comment)
    
    /// Create a quote repost (repost with a comment)
    func quoteRepost(postId: String, comment: String) async throws {
        guard !comment.isEmpty else {
            throw NSError(domain: "RepostService", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Quote repost comment cannot be empty"
            ])
        }
        
        try await repost(postId: postId, withComment: comment)
    }
    
    // MARK: - Real-time Listeners
    
    /// Start listening to user's reposts
    func startListening() {
        guard let userId = firebaseManager.currentUser?.uid else {
            print("⚠️ No user ID for listener")
            return
        }
        
        print("🔊 Starting real-time listener for reposts...")
        
        let listener = db.collection(FirebaseManager.CollectionPath.reposts)
            .whereField("userId", isEqualTo: userId)
            .order(by: "repostedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Reposts listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let fetchedReposts = snapshot.documents.compactMap { doc -> Repost? in
                    try? doc.data(as: Repost.self)
                }
                
                self.reposts = fetchedReposts
                self.repostedPostIds = Set(fetchedReposts.map { $0.originalPostId })
                
                print("✅ Real-time update: \(fetchedReposts.count) reposts")
            }
        
        listeners.append(listener)
    }
    
    /// Stop all listeners
    func stopListening() {
        print("🔇 Stopping repost listeners...")
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    // MARK: - Helper Methods
    
    /// Get repost count for a post
    func getRepostCount(for postId: String) async throws -> Int {
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.reposts)
            .whereField("originalPostId", isEqualTo: postId)
            .count
            .getAggregation(source: .server)
        
        return Int(snapshot.count.intValue)
    }
    
    // MARK: - Notifications
    
    private func createRepostNotification(
        originalPostId: String,
        originalAuthorId: String,
        reposterName: String
    ) async throws {
        guard let userId = firebaseManager.currentUser?.uid else { return }
        
        let notification: [String: Any] = [
            "userId": originalAuthorId,
            "type": "repost",
            "fromUserId": userId,
            "fromUserName": reposterName,
            "postId": originalPostId,
            "message": "\(reposterName) reposted your post",
            "createdAt": Date(),
            "isRead": false
        ]
        
        try await db.collection("notifications").addDocument(data: notification)
    }
}
