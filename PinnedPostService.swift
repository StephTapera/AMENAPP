//
//  PinnedPostService.swift
//  AMENAPP
//
//  Smart pin post feature - like Threads
//  Allows users to pin ONE post to the top of their profile
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class PinnedPostService: ObservableObject {
    static let shared = PinnedPostService()
    
    @Published private(set) var pinnedPostIds: Set<String> = []
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Pin/Unpin Post
    
    /// Pin a post to user's profile (limit: 1 pinned post per user)
    func pinPost(postId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PinnedPost", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("📌 Pinning post \(postId) for user \(userId)")
        
        // Check if user already has a pinned post
        let userRef = db.collection("users").document(userId)
        let userData = try await userRef.getDocument().data()
        
        if let existingPinnedPostId = userData?["pinnedPostId"] as? String, !existingPinnedPostId.isEmpty {
            // User already has a pinned post - unpin it first
            print("⚠️ User already has pinned post: \(existingPinnedPostId). Unpinning first...")
            try await unpinPost(postId: existingPinnedPostId)
        }
        
        // Verify post exists and belongs to user
        let postRef = db.collection("posts").document(postId)
        let postDoc = try await postRef.getDocument()
        
        guard postDoc.exists else {
            throw NSError(domain: "PinnedPost", code: 404, userInfo: [NSLocalizedDescriptionKey: "Post not found"])
        }
        
        guard let postUserId = postDoc.data()?["userId"] as? String, postUserId == userId else {
            throw NSError(domain: "PinnedPost", code: 403, userInfo: [NSLocalizedDescriptionKey: "Can only pin your own posts"])
        }
        
        // Pin the post
        let batch = db.batch()
        
        // Update user profile with pinned post ID
        batch.updateData([
            "pinnedPostId": postId,
            "pinnedAt": FieldValue.serverTimestamp()
        ], forDocument: userRef)
        
        // Add pinned flag to post document
        batch.updateData([
            "isPinned": true,
            "pinnedAt": FieldValue.serverTimestamp()
        ], forDocument: postRef)
        
        try await batch.commit()
        
        // Update local cache
        pinnedPostIds.insert(postId)
        
        print("✅ Post pinned successfully")
    }
    
    /// Unpin a post from user's profile
    func unpinPost(postId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PinnedPost", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("📌 Unpinning post \(postId) for user \(userId)")
        
        let batch = db.batch()
        
        // Remove pinned post ID from user profile
        let userRef = db.collection("users").document(userId)
        batch.updateData([
            "pinnedPostId": FieldValue.delete(),
            "pinnedAt": FieldValue.delete()
        ], forDocument: userRef)
        
        // Remove pinned flag from post
        let postRef = db.collection("posts").document(postId)
        batch.updateData([
            "isPinned": FieldValue.delete(),
            "pinnedAt": FieldValue.delete()
        ], forDocument: postRef)
        
        try await batch.commit()
        
        // Update local cache
        pinnedPostIds.remove(postId)
        
        print("✅ Post unpinned successfully")
    }
    
    /// Toggle pin status for a post
    func togglePin(postId: String) async throws {
        if pinnedPostIds.contains(postId) {
            try await unpinPost(postId: postId)
        } else {
            try await pinPost(postId: postId)
        }
    }
    
    // MARK: - Fetch Pinned Posts
    
    /// Get pinned post ID for a specific user
    func getPinnedPostId(for userId: String) async throws -> String? {
        let userDoc = try await db.collection("users").document(userId).getDocument()
        return userDoc.data()?["pinnedPostId"] as? String
    }
    
    /// Load pinned post status for current user
    func loadCurrentUserPinnedPosts() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            if let pinnedPostId = try await getPinnedPostId(for: userId) {
                pinnedPostIds.insert(pinnedPostId)
                print("✅ Loaded pinned post: \(pinnedPostId)")
            }
        } catch {
            print("❌ Failed to load pinned posts: \(error)")
        }
    }
    
    /// Check if a post is pinned
    func isPostPinned(_ postId: String) -> Bool {
        return pinnedPostIds.contains(postId)
    }
    
    // MARK: - Real-time Listener
    
    private var pinnedPostListener: ListenerRegistration?
    
    /// Start listening for pinned post changes
    func startListening() {
        guard pinnedPostListener == nil else {
            print("⚠️ Pinned post listener already active")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        pinnedPostListener = db.collection("users")
            .document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let data = snapshot?.data() else { return }
                
                Task { @MainActor in
                    // Clear previous pinned posts
                    self.pinnedPostIds.removeAll()
                    
                    // Add current pinned post
                    if let pinnedPostId = data["pinnedPostId"] as? String {
                        self.pinnedPostIds.insert(pinnedPostId)
                        print("🔄 Pinned post updated: \(pinnedPostId)")
                    }
                }
            }
        
        print("✅ Pinned post listener started")
    }
    
    /// Stop listening for pinned post changes
    func stopListening() {
        pinnedPostListener?.remove()
        pinnedPostListener = nil
        print("🛑 Pinned post listener stopped")
    }
}
