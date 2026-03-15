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
    // Cache the userId at registration time so removeSavedPostsListener() works
    // even after sign-out clears Auth.auth().currentUser
    private var savedPostsUserId: String?
    
    @Published var savedPostIds: Set<String> = []  // For quick lookup
    @Published var isLoading = false
    
    private init() {
        self.database = Database.database().reference()
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
    
    /// ✅ Toggle save status with offline handling
    func toggleSavePost(postId: String) async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimeSavedPostsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // ✅ Check network first
        guard AMENNetworkMonitor.shared.isConnected else {
            dlog("📱 Offline - cannot toggle save status")
            throw NSError(
                domain: "RealtimeSavedPostsService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No internet connection. Please try again when online."]
            )
        }
        
        let userId = currentUser.uid
        let savedPath = "/user_saved_posts/\(userId)/\(postId)"
        
        // Use the in-memory cache for the toggle decision — avoids a round-trip to RTDB
        // that can return stale offline-cached data and cause double-unsave on rapid taps.
        let isSaved = savedPostIds.contains(postId)
        
        if isSaved {
            // Unsave
            dlog("🔖 Unsaving post: \(postId)")
            
            let updates: [String: Any?] = [
                savedPath: nil
            ]
            
            try await database.updateChildValues(updates as [AnyHashable: Any])
            
            savedPostIds.remove(postId)
            
            // Send notification for UI updates
            NotificationCenter.default.post(
                name: Notification.Name("postUnsaved"),
                object: nil,
                userInfo: ["postId": postId]
            )
            
            dlog("✅ Post unsaved successfully")
            return false
            
        } else {
            // Save
            dlog("🔖 Saving post: \(postId)")
            
            let updates: [String: Any] = [
                savedPath: Date().timeIntervalSince1970
            ]
            
            try await database.updateChildValues(updates)
            
            savedPostIds.insert(postId)
            
            // Send notification for UI updates
            NotificationCenter.default.post(
                name: Notification.Name("postSaved"),
                object: nil,
                userInfo: ["postId": postId]
            )
            
            dlog("✅ Post saved successfully")
            return true
        }
    }
    
    // MARK: - Check if Post is Saved
    
    /// ✅ Check if post is saved (with offline support)
    func isPostSaved(postId: String) async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            return false
        }
        
        // ✅ Check network first
        guard AMENNetworkMonitor.shared.isConnected else {
            dlog("📱 Offline - using cached saved status for: \(postId)")
            return isPostSavedSync(postId: postId)
        }
        
        let userId = currentUser.uid
        
        do {
            let snapshot = try await database.child("user_saved_posts").child(userId).child(postId).getData()
            let isSaved = snapshot.exists()
            
            // Update cache
            if isSaved {
                savedPostIds.insert(postId)
            } else {
                savedPostIds.remove(postId)
            }
            
            return isSaved
        } catch {
            // Suppress startup transient "client offline / no active listeners" errors —
            // these fire when RTDB hasn't finished handshaking yet even though the network
            // monitor reports connected. The cache fallback below is correct behavior.
            let isOfflineError = error.localizedDescription.contains("client offline") ||
                                 error.localizedDescription.contains("no active listeners")
            if !isOfflineError {
                dlog("⚠️ Failed to check saved status (using cache): \(error.localizedDescription)")
            }
            // Fall back to cached value
            return isPostSavedSync(postId: postId)
        }
    }
    
    /// ✅ Synchronous check using local cache (for offline use)
    func isPostSavedSync(postId: String) -> Bool {
        return savedPostIds.contains(postId)
    }
    
    // MARK: - Fetch Saved Post IDs
    
    func fetchSavedPostIds() async throws -> [String] {
        guard let currentUser = Auth.auth().currentUser else {
            return []
        }
        
        let userId = currentUser.uid
        dlog("📥 Fetching saved post IDs for user: \(userId)")
        
        let snapshot = try await database.child("user_saved_posts").child(userId).getData()
        
        guard snapshot.exists(), let savedDict = snapshot.value as? [String: Any] else {
            dlog("⚠️ No saved posts found")
            return []
        }
        
        let postIds = Array(savedDict.keys)
        
        savedPostIds = Set(postIds)
        
        dlog("✅ Fetched \(postIds.count) saved post IDs")
        return postIds
    }
    
    // MARK: - Fetch Saved Posts with Details
    
    func fetchSavedPosts() async throws -> [Post] {
        // ✅ Check if offline - use cached post IDs
        let postIds: [String]
        if AMENNetworkMonitor.shared.isConnected {
            postIds = try await fetchSavedPostIds()
        } else {
            dlog("📱 Offline - using cached saved post IDs")
            postIds = Array(savedPostIds)
        }
        
        guard !postIds.isEmpty else {
            return []
        }
        
        dlog("📥 Fetching \(postIds.count) saved posts with full details")
        
        var posts: [Post] = []
        
        for postId in postIds {
            do {
                // ✅ FIX: Use FirebasePostService to fetch from Firestore (not RTDB)
                if let post = try await FirebasePostService.shared.fetchPostById(postId: postId) {
                    posts.append(post)
                } else {
                    dlog("⚠️ Post \(postId) not found in Firestore")
                }
            } catch let error as NSError {
                // ✅ Handle offline errors gracefully
                if error.domain == "com.firebase.core" && error.code == 1 {
                    dlog("📱 Post \(postId) not in cache - skipping (offline)")
                } else {
                    dlog("⚠️ Failed to fetch saved post \(postId): \(error)")
                }
            }
        }
        
        // Sort by saved timestamp (most recent first)
        posts.sort { $0.createdAt > $1.createdAt }
        
        dlog("✅ Fetched \(posts.count) saved posts with details")
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
        dlog("👂 Setting up real-time listener for saved posts: \(userId)")
        
        removeSavedPostsListener()  // Remove existing listener
        
        savedPostsUserId = userId  // Cache for cleanup on sign-out
        let savedPostsRef = database.child("user_saved_posts").child(userId)
        
        // ✅ CRITICAL FIX: Keep saved posts synced locally for offline persistence
        savedPostsRef.keepSynced(true)
        
        savedPostsListener = savedPostsRef.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            Task { @MainActor in
                guard snapshot.exists(), let savedDict = snapshot.value as? [String: Any] else {
                    self.updateSavedPostIds([])
                    completion([])
                    return
                }
                
                let postIds = Array(savedDict.keys)
                self.updateSavedPostIds(postIds)
                
                dlog("🔄 Real-time update: \(postIds.count) saved posts")
                completion(postIds)
            }
        }
    }
    
    func removeSavedPostsListener() {
        guard let handle = savedPostsListener,
              let userId = savedPostsUserId else { return }
        database.child("user_saved_posts").child(userId).removeObserver(withHandle: handle)
        savedPostsListener = nil
        savedPostsUserId = nil
        dlog("🔇 Removed saved posts listener")
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
