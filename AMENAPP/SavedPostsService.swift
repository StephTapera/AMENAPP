//
//  SavedPostsService.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Service for saving posts and managing saved collections
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class SavedPostsService: ObservableObject {
    static let shared = SavedPostsService()
    
    @Published var savedPosts: [SavedPost] = []
    @Published var savedPostIds: Set<String> = []  // For quick lookups
    @Published var collections: [String] = ["All", "Prayer", "Testimonies", "OpenTable"]  // Custom collections
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebaseManager = FirebaseManager.shared
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    
    private init() {}
    
    // MARK: - Save Post
    
    /// Save a post to user's saved collection
    func savePost(postId: String, post: Post? = nil, collection: String? = nil) async throws {
        print("💾 Saving post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Check if already saved
        if savedPostIds.contains(postId) {
            print("⚠️ Post already saved")
            return
        }
        
        let savedPost = SavedPost(
            userId: userId,
            postId: postId,
            collectionName: collection
        )
        
        // Save to Firestore
        let docRef = try db.collection(FirebaseManager.CollectionPath.savedPosts)
            .addDocument(from: savedPost)
        
        print("✅ Post saved with ID: \(docRef.documentID)")
        
        // Update local cache
        var savedPostWithId = savedPost
        savedPostWithId.id = docRef.documentID
        savedPosts.append(savedPostWithId)
        savedPostIds.insert(postId)
        
        // Send notification for real-time ProfileView update
        if let post = post {
            NotificationCenter.default.post(
                name: Notification.Name("postSaved"),
                object: nil,
                userInfo: ["post": post]
            )
            print("📬 Post saved notification sent")
        }
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    /// Unsave a post
    func unsavePost(postId: String) async throws {
        print("🗑️ Unsaving post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Find the saved post document
        let query = db.collection(FirebaseManager.CollectionPath.savedPosts)
            .whereField("userId", isEqualTo: userId)
            .whereField("postId", isEqualTo: postId)
            .limit(to: 1)
        
        let snapshot = try await query.getDocuments()
        
        guard let document = snapshot.documents.first else {
            print("⚠️ Saved post not found")
            return
        }
        
        try await document.reference.delete()
        
        print("✅ Post unsaved")
        
        // Update local cache
        savedPosts.removeAll { $0.postId == postId }
        savedPostIds.remove(postId)
        
        // Send notification for real-time ProfileView update
        if let postUUID = UUID(uuidString: postId) {
            NotificationCenter.default.post(
                name: Notification.Name("postUnsaved"),
                object: nil,
                userInfo: ["postId": postUUID]
            )
            print("📬 Post unsaved notification sent")
        }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    /// Toggle save status of a post
    func toggleSave(postId: String, collection: String? = nil) async throws {
        if savedPostIds.contains(postId) {
            try await unsavePost(postId: postId)
        } else {
            try await savePost(postId: postId, collection: collection)
        }
    }
    
    // MARK: - Fetch Saved Posts
    
    /// Fetch all saved posts for current user
    func fetchSavedPosts(collection: String? = nil) async throws -> [SavedPost] {
        print("📥 Fetching saved posts...")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        var query = db.collection(FirebaseManager.CollectionPath.savedPosts)
            .whereField("userId", isEqualTo: userId)
        
        // Filter by collection if specified
        if let collection = collection, collection != "All" {
            query = query.whereField("collectionName", isEqualTo: collection)
        }
        
        let snapshot = try await query
            .order(by: "savedAt", descending: true)
            .getDocuments()
        
        let fetchedSavedPosts = try snapshot.documents.compactMap { doc in
            try doc.data(as: SavedPost.self)
        }
        
        print("✅ Fetched \(fetchedSavedPosts.count) saved posts")
        
        // Update local cache
        savedPosts = fetchedSavedPosts
        savedPostIds = Set(fetchedSavedPosts.map { $0.postId })
        
        return fetchedSavedPosts
    }
    
    /// Fetch actual post objects for saved posts
    func fetchSavedPostObjects(collection: String? = nil) async throws -> [Post] {
        let savedPosts = try await fetchSavedPosts(collection: collection)
        
        var posts: [Post] = []
        
        for savedPost in savedPosts {
            do {
                // Fetch the actual post document
                let postDoc = try await db.collection(FirebaseManager.CollectionPath.posts)
                    .document(savedPost.postId)
                    .getDocument()
                
                if let firestorePost = try? postDoc.data(as: FirestorePost.self) {
                    posts.append(firestorePost.toPost())
                }
            } catch {
                print("⚠️ Failed to fetch saved post: \(savedPost.postId)")
            }
        }
        
        print("✅ Fetched \(posts.count) saved post objects")
        
        return posts
    }
    
    /// Check if a post is saved
    func isPostSaved(postId: String) async -> Bool {
        guard let userId = firebaseManager.currentUser?.uid else {
            return false
        }
        
        // First check local cache
        if savedPostIds.contains(postId) {
            return true
        }
        
        // If not in cache, check Firestore
        do {
            let query = db.collection(FirebaseManager.CollectionPath.savedPosts)
                .whereField("userId", isEqualTo: userId)
                .whereField("postId", isEqualTo: postId)
                .limit(to: 1)
            
            let snapshot = try await query.getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            print("❌ Error checking saved status: \(error)")
            return false
        }
    }
    
    // MARK: - Collections Management
    
    /// Create a new custom collection
    func createCollection(name: String) async throws {
        guard !name.isEmpty else {
            throw NSError(domain: "SavedPostsService", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Collection name cannot be empty"
            ])
        }
        
        // Check if collection already exists
        if collections.contains(name) {
            throw NSError(domain: "SavedPostsService", code: 409, userInfo: [
                NSLocalizedDescriptionKey: "Collection already exists"
            ])
        }
        
        collections.append(name)
        
        // Optionally save to user preferences in Firestore
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        try await db.collection(FirebaseManager.CollectionPath.users)
            .document(userId)
            .updateData([
                "savedPostCollections": FieldValue.arrayUnion([name])
            ])
        
        print("✅ Collection created: \(name)")
    }
    
    /// Delete a custom collection (moves all posts to "All")
    func deleteCollection(name: String) async throws {
        guard name != "All" else {
            throw NSError(domain: "SavedPostsService", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Cannot delete default collection"
            ])
        }
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Update all saved posts in this collection to "All"
        let query = db.collection(FirebaseManager.CollectionPath.savedPosts)
            .whereField("userId", isEqualTo: userId)
            .whereField("collectionName", isEqualTo: name)
        
        let snapshot = try await query.getDocuments()
        
        let batch = db.batch()
        for document in snapshot.documents {
            batch.updateData(["collectionName": "All"], forDocument: document.reference)
        }
        try await batch.commit()
        
        // Remove from user preferences
        try await db.collection(FirebaseManager.CollectionPath.users)
            .document(userId)
            .updateData([
                "savedPostCollections": FieldValue.arrayRemove([name])
            ])
        
        collections.removeAll { $0 == name }
        
        print("✅ Collection deleted: \(name)")
    }
    
    /// Move a saved post to a different collection
    func moveToCollection(postId: String, newCollection: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let query = db.collection(FirebaseManager.CollectionPath.savedPosts)
            .whereField("userId", isEqualTo: userId)
            .whereField("postId", isEqualTo: postId)
            .limit(to: 1)
        
        let snapshot = try await query.getDocuments()
        
        guard let document = snapshot.documents.first else {
            throw FirebaseError.documentNotFound
        }
        
        try await document.reference.updateData([
            "collectionName": newCollection
        ])
        
        print("✅ Post moved to collection: \(newCollection)")
        
        // Update local cache
        if let index = savedPosts.firstIndex(where: { $0.postId == postId }) {
            savedPosts[index].collectionName = newCollection
        }
    }
    
    // MARK: - Real-time Listeners
    
    /// Start listening to saved posts
    func startListening() {
        guard let userId = firebaseManager.currentUser?.uid else {
            print("⚠️ No user ID for listener")
            return
        }
        
        print("🔊 Starting real-time listener for saved posts...")
        
        let listener = db.collection(FirebaseManager.CollectionPath.savedPosts)
            .whereField("userId", isEqualTo: userId)
            .order(by: "savedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Saved posts listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let fetchedSavedPosts = snapshot.documents.compactMap { doc -> SavedPost? in
                    try? doc.data(as: SavedPost.self)
                }
                
                self.savedPosts = fetchedSavedPosts
                self.savedPostIds = Set(fetchedSavedPosts.map { $0.postId })
                
                print("✅ Real-time update: \(fetchedSavedPosts.count) saved posts")
            }
        
        listeners.append(listener)
    }
    
    /// Stop all listeners
    func stopListening() {
        print("🔇 Stopping saved posts listeners...")
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    // MARK: - Bulk Operations
    
    /// Delete all saved posts
    func clearAllSavedPosts() async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("🗑️ Clearing all saved posts...")
        
        let query = db.collection(FirebaseManager.CollectionPath.savedPosts)
            .whereField("userId", isEqualTo: userId)
        
        let snapshot = try await query.getDocuments()
        
        let batch = db.batch()
        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }
        try await batch.commit()
        
        print("✅ All saved posts cleared")
        
        // Update local cache
        savedPosts.removeAll()
        savedPostIds.removeAll()
    }
    
    /// Get count of saved posts
    func getSavedPostCount() async throws -> Int {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.savedPosts)
            .whereField("userId", isEqualTo: userId)
            .count
            .getAggregation(source: .server)
        
        return Int(snapshot.count.intValue)
    }
}
