//
//  RealtimeSavedPostsService.swift
//  AMENAPP
//
//  Created by Steph on 1/24/26.
//
//  Firebase Realtime Database implementation for saved posts
//  Scalable and efficient bookmark system
//

import Foundation
import FirebaseDatabase
import FirebaseAuth
import Combine

// MARK: - Realtime Saved Posts Service

class RealtimeSavedPostsService: ObservableObject {
    static let shared = RealtimeSavedPostsService()
    
    private let database: DatabaseReference
    private var savedPostsListener: DatabaseHandle?
    
    @Published var savedPostIds: Set<String> = []  // For quick lookup
    @Published var isLoading = false
    
    private init() {
        self.database = Database.database(url: "https://amen-5e359-default-rtdb.firebaseio.com").reference()
        print("🔥 RealtimeSavedPostsService initialized")
    }
    
    deinit {
        removeSavedPostsListener()
    }
    
    // MARK: - Database Structure
    /*
     /user_saved_posts
       /{userId}
         /{postId}: timestamp  // When saved
     */
    
    // MARK: - Toggle Save Post
    
    func toggleSavePost(postId: String) async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimeSavedPostsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let userId = currentUser.uid
        let savedPath = "/user_saved_posts/\(userId)/\(postId)"
        
        // Check if already saved
        let snapshot = try await database.child(savedPath).getData()
        let isSaved = snapshot.exists()
        
        if isSaved {
            // Unsave
            print("🔖 Unsaving post: \(postId)")
            
            let updates: [String: Any?] = [
                savedPath: nil
            ]
            
            try await database.updateChildValues(updates as [AnyHashable: Any])
            
            savedPostIds.remove(postId)
            
            // Send notification for UI updates
            NotificationCenter.default.post(
                name: Notification.Name("postUnsaved"),
                object: nil,
                userInfo: ["postId": UUID(uuidString: postId) ?? UUID()]
            )
            
            print("✅ Post unsaved successfully")
            return false
            
        } else {
            // Save
            print("🔖 Saving post: \(postId)")
            
            let updates: [String: Any] = [
                savedPath: Date().timeIntervalSince1970
            ]
            
            try await database.updateChildValues(updates)
            
            savedPostIds.insert(postId)
            
            // Send notification for UI updates
            NotificationCenter.default.post(
                name: Notification.Name("postSaved"),
                object: nil,
                userInfo: ["postId": UUID(uuidString: postId) ?? UUID()]
            )
            
            print("✅ Post saved successfully")
            return true
        }
    }
    
    // MARK: - Check if Post is Saved
    
    func isPostSaved(postId: String) async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            return false
        }
        
        let userId = currentUser.uid
        let snapshot = try await database.child("user_saved_posts").child(userId).child(postId).getData()
        return snapshot.exists()
    }
    
    func isPostSavedSync(postId: String) -> Bool {
        return savedPostIds.contains(postId)
    }
    
    // MARK: - Fetch Saved Post IDs
    
    func fetchSavedPostIds() async throws -> [String] {
        guard let currentUser = Auth.auth().currentUser else {
            return []
        }
        
        let userId = currentUser.uid
        print("📥 Fetching saved post IDs for user: \(userId)")
        
        let snapshot = try await database.child("user_saved_posts").child(userId).getData()
        
        guard snapshot.exists(), let savedDict = snapshot.value as? [String: Any] else {
            print("⚠️ No saved posts found")
            return []
        }
        
        let postIds = Array(savedDict.keys)
        
        savedPostIds = Set(postIds)
        
        print("✅ Fetched \(postIds.count) saved post IDs")
        return postIds
    }
    
    // MARK: - Fetch Saved Posts with Details
    
    func fetchSavedPosts() async throws -> [Post] {
        let postIds = try await fetchSavedPostIds()
        
        guard !postIds.isEmpty else {
            return []
        }
        
        print("📥 Fetching \(postIds.count) saved posts with full details")
        
        var posts: [Post] = []
        
        for postId in postIds {
            do {
                let post = try await RealtimePostService.shared.fetchPost(postId: postId)
                posts.append(post)
            } catch {
                print("⚠️ Failed to fetch saved post \(postId): \(error)")
            }
        }
        
        // Sort by saved timestamp (most recent first)
        posts.sort { $0.createdAt > $1.createdAt }
        
        print("✅ Fetched \(posts.count) saved posts with details")
        return posts
    }
    
    // MARK: - Real-time Listener for Saved Posts
    
    @MainActor
    private func updateSavedPostIds(_ postIds: [String]) {
        self.savedPostIds = Set(postIds)
    }
    
    func observeSavedPosts(completion: @escaping ([String]) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion([])
            return
        }
        
        let userId = currentUser.uid
        print("👂 Setting up real-time listener for saved posts: \(userId)")
        
        removeSavedPostsListener()  // Remove existing listener
        
        savedPostsListener = database.child("user_saved_posts").child(userId).observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            Task { @MainActor in
                guard snapshot.exists(), let savedDict = snapshot.value as? [String: Any] else {
                    await self.updateSavedPostIds([])
                    completion([])
                    return
                }
                
                let postIds = Array(savedDict.keys)
                await self.updateSavedPostIds(postIds)
                
                print("🔄 Real-time update: \(postIds.count) saved posts")
                completion(postIds)
            }
        }
    }
    
    func removeSavedPostsListener() {
        if let handle = savedPostsListener {
            guard let currentUser = Auth.auth().currentUser else { return }
            let userId = currentUser.uid
            
            database.child("user_saved_posts").child(userId).removeObserver(withHandle: handle)
            savedPostsListener = nil
            print("🔇 Removed saved posts listener")
        }
    }
    
    // MARK: - Get Saved Count
    
    func getSavedPostsCount() async throws -> Int {
        guard let currentUser = Auth.auth().currentUser else {
            return 0
        }
        
        let userId = currentUser.uid
        let snapshot = try await database.child("user_saved_posts").child(userId).getData()
        
        guard snapshot.exists(), let savedDict = snapshot.value as? [String: Any] else {
            return 0
        }
        
        return savedDict.count
    }
}
