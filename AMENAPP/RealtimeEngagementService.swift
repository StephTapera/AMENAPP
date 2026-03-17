//
//  RealtimeEngagementService.swift
//  AMENAPP
//
//  Created by Steph on 1/24/26.
//
//  Firebase Realtime Database implementation for engagement stats
//  Handles likes, amens, lightbulbs, comments, reposts with atomic increments
//

import Foundation
import FirebaseDatabase
import FirebaseAuth
import Combine

// MARK: - Realtime Engagement Service

@MainActor
class RealtimeEngagementService: ObservableObject {
    static let shared = RealtimeEngagementService()
    
    private let database: DatabaseReference
    private var statsListeners: [String: DatabaseHandle] = [:]  // postId -> listener handle
    
    @Published var postStats: [String: PostStats] = [:]  // postId -> stats
    
    struct PostStats {
        var amenCount: Int = 0
        var lightbulbCount: Int = 0
        var commentCount: Int = 0
        var repostCount: Int = 0
    }
    
    private init() {
        self.database = Database.database().reference()
    }
    
    deinit {
        removeAllListeners()
    }
    
    // MARK: - Toggle Amen
    
    func toggleAmen(postId: String) async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimeEngagementService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let userId = currentUser.uid
        let interactionPath = "/post_interactions/\(postId)/amen/\(userId)"
        
        // Check if user already said amen
        let snapshot = try await database.child(interactionPath).getData()
        let hasAmen = snapshot.exists()
        
        if hasAmen {
            // Remove amen
            dlog("🙏 Removing amen from post: \(postId)")
            
            let updates: [String: Any?] = [
                interactionPath: nil
            ]
            
            try await database.updateChildValues(updates as [AnyHashable: Any])
            
            // Decrement count
            try await database.child("post_stats").child(postId).child("amenCount").runTransactionBlock { currentData in
                if var count = currentData.value as? Int, count > 0 {
                    count -= 1
                    currentData.value = count
                }
                return TransactionResult.success(withValue: currentData)
            }
            
            dlog("✅ Amen removed successfully")
            return false
            
        } else {
            // Add amen
            dlog("🙏 Adding amen to post: \(postId)")
            
            let updates: [String: Any] = [
                interactionPath: Date().timeIntervalSince1970
            ]
            
            try await database.updateChildValues(updates)
            
            // Increment count atomically
            try await database.child("post_stats").child(postId).child("amenCount").runTransactionBlock { currentData in
                var count = currentData.value as? Int ?? 0
                count += 1
                currentData.value = count
                return TransactionResult.success(withValue: currentData)
            }
            
            dlog("✅ Amen added successfully")
            return true
        }
    }
    
    // MARK: - Toggle Lightbulb
    
    func toggleLightbulb(postId: String) async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimeEngagementService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let userId = currentUser.uid
        let interactionPath = "/post_interactions/\(postId)/lightbulb/\(userId)"
        
        // Check if user already lit lightbulb
        let snapshot = try await database.child(interactionPath).getData()
        let hasLightbulb = snapshot.exists()
        
        if hasLightbulb {
            // Remove lightbulb
            dlog("💡 Removing lightbulb from post: \(postId)")
            
            let updates: [String: Any?] = [
                interactionPath: nil
            ]
            
            try await database.updateChildValues(updates as [AnyHashable: Any])
            
            // Decrement count
            try await database.child("post_stats").child(postId).child("lightbulbCount").runTransactionBlock { currentData in
                if var count = currentData.value as? Int, count > 0 {
                    count -= 1
                    currentData.value = count
                }
                return TransactionResult.success(withValue: currentData)
            }
            
            dlog("✅ Lightbulb removed successfully")
            return false
            
        } else {
            // Add lightbulb
            dlog("💡 Adding lightbulb to post: \(postId)")
            
            let updates: [String: Any] = [
                interactionPath: Date().timeIntervalSince1970
            ]
            
            try await database.updateChildValues(updates)
            
            // Increment count atomically
            try await database.child("post_stats").child(postId).child("lightbulbCount").runTransactionBlock { currentData in
                var count = currentData.value as? Int ?? 0
                count += 1
                currentData.value = count
                return TransactionResult.success(withValue: currentData)
            }
            
            dlog("✅ Lightbulb added successfully")
            return true
        }
    }
    
    // MARK: - Check User Interactions
    
    func checkUserAmen(postId: String) async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            return false
        }
        
        let userId = currentUser.uid
        let snapshot = try await database.child("post_interactions").child(postId).child("amen").child(userId).getData()
        return snapshot.exists()
    }
    
    func checkUserLightbulb(postId: String) async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            return false
        }
        
        let userId = currentUser.uid
        let snapshot = try await database.child("post_interactions").child(postId).child("lightbulb").child(userId).getData()
        return snapshot.exists()
    }
    
    // MARK: - Increment Comment Count
    
    func incrementCommentCount(postId: String) async throws {
        dlog("💬 Incrementing comment count for post: \(postId)")
        
        try await database.child("post_stats").child(postId).child("commentCount").runTransactionBlock { currentData in
            var count = currentData.value as? Int ?? 0
            count += 1
            currentData.value = count
            return TransactionResult.success(withValue: currentData)
        }
        
        dlog("✅ Comment count incremented")
    }
    
    func decrementCommentCount(postId: String) async throws {
        dlog("💬 Decrementing comment count for post: \(postId)")
        
        try await database.child("post_stats").child(postId).child("commentCount").runTransactionBlock { currentData in
            if var count = currentData.value as? Int, count > 0 {
                count -= 1
                currentData.value = count
            }
            return TransactionResult.success(withValue: currentData)
        }
        
        dlog("✅ Comment count decremented")
    }
    
    // MARK: - Increment Repost Count
    
    func incrementRepostCount(postId: String) async throws {
        dlog("🔄 Incrementing repost count for post: \(postId)")
        
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimeEngagementService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let userId = currentUser.uid
        
        // Mark that user reposted this
        let updates: [String: Any] = [
            "/post_interactions/\(postId)/reposts/\(userId)": Date().timeIntervalSince1970
        ]
        
        try await database.updateChildValues(updates)
        
        // Increment count
        try await database.child("post_stats").child(postId).child("repostCount").runTransactionBlock { currentData in
            var count = currentData.value as? Int ?? 0
            count += 1
            currentData.value = count
            return TransactionResult.success(withValue: currentData)
        }
        
        dlog("✅ Repost count incremented")
    }
    
    // MARK: - Fetch Post Stats
    
    func fetchPostStats(postId: String) async throws -> PostStats {
        let snapshot = try await database.child("post_stats").child(postId).getData()
        
        guard snapshot.exists(), let data = snapshot.value as? [String: Any] else {
            // Return default stats if not found
            return PostStats()
        }
        
        return PostStats(
            amenCount: data["amenCount"] as? Int ?? 0,
            lightbulbCount: data["lightbulbCount"] as? Int ?? 0,
            commentCount: data["commentCount"] as? Int ?? 0,
            repostCount: data["repostCount"] as? Int ?? 0
        )
    }
    
    // MARK: - Real-time Stats Listener
    
    func observePostStats(postId: String, completion: @escaping (PostStats) -> Void) {
        dlog("👂 Setting up real-time stats listener for post: \(postId)")
        
        let handle = database.child("post_stats").child(postId).observe(.value) { snapshot in
            guard snapshot.exists(), let data = snapshot.value as? [String: Any] else {
                completion(PostStats())
                return
            }
            
            let stats = PostStats(
                amenCount: data["amenCount"] as? Int ?? 0,
                lightbulbCount: data["lightbulbCount"] as? Int ?? 0,
                commentCount: data["commentCount"] as? Int ?? 0,
                repostCount: data["repostCount"] as? Int ?? 0
            )
            
            Task { @MainActor in
                self.postStats[postId] = stats
                completion(stats)
            }
        }
        
        statsListeners[postId] = handle
    }
    
    func removeStatsListener(postId: String) {
        if let handle = statsListeners[postId] {
            database.child("post_stats").child(postId).removeObserver(withHandle: handle)
            statsListeners.removeValue(forKey: postId)
            dlog("🔇 Removed stats listener for post: \(postId)")
        }
    }
    
    nonisolated func removeAllListeners() {
        Task { @MainActor in
            for (postId, handle) in statsListeners {
                database.child("post_stats").child(postId).removeObserver(withHandle: handle)
            }
            statsListeners.removeAll()
            dlog("🔇 All stats listeners removed")
        }
    }
}
