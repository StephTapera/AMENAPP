//
//  BlockService.swift
//  AMENAPP
//
//  Created by Steph on 1/21/26.
//
//  Service for managing blocked users functionality
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Block Model

struct Block: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var blockerId: String      // User who blocked
    var blockedUserId: String  // User being blocked
    var blockedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case blockerId
        case blockedUserId
        case blockedAt
    }
    
    init(
        id: String? = nil,
        blockerId: String,
        blockedUserId: String,
        blockedAt: Date = Date()
    ) {
        self.id = id
        self.blockerId = blockerId
        self.blockedUserId = blockedUserId
        self.blockedAt = blockedAt
    }
}

// MARK: - Blocked User Profile

struct BlockedUserProfile: Identifiable, Codable {
    let id: String
    let displayName: String
    let username: String
    let initials: String
    let profileImageURL: String?
    let blockedAt: Date
}

// MARK: - Block Service

@MainActor
class BlockService: ObservableObject {
    static let shared = BlockService()
    
    @Published var blockedUsers: Set<String> = []           // Set of blocked user IDs
    @Published var blockedUsersList: [BlockedUserProfile] = [] // Full user profiles
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebaseManager = FirebaseManager.shared
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    
    private init() {}
    
    // MARK: - Block User
    
    /// Block a user
    func blockUser(userId: String) async throws {
        print("🚫 Blocking user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Don't block yourself
        guard userId != currentUserId else {
            print("⚠️ Cannot block yourself")
            return
        }
        
        // Check if already blocked
        if await isBlocked(userId: userId) {
            print("⚠️ User is already blocked")
            return
        }
        
        // Create block relationship
        let block = Block(
            blockerId: currentUserId,
            blockedUserId: userId
        )
        
        // Use batch write for atomicity
        let batch = db.batch()
        
        // 1. Add to blocks collection
        let blockRef = db.collection(FirebaseManager.CollectionPath.blocks).document()
        try batch.setData(from: block, forDocument: blockRef)
        
        // 2. Remove existing follow relationships in both directions
        // Remove if current user follows blocked user
        let followingQuery = try await db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followerId", isEqualTo: currentUserId)
            .whereField("followingId", isEqualTo: userId)
            .limit(to: 1)
            .getDocuments()
        
        if let followDoc = followingQuery.documents.first {
            batch.deleteDocument(followDoc.reference)
            
            // Decrement counts
            let targetUserRef = db.collection(FirebaseManager.CollectionPath.users).document(userId)
            batch.updateData([
                "followersCount": FieldValue.increment(Int64(-1))
            ], forDocument: targetUserRef)
            
            let currentUserRef = db.collection(FirebaseManager.CollectionPath.users).document(currentUserId)
            batch.updateData([
                "followingCount": FieldValue.increment(Int64(-1))
            ], forDocument: currentUserRef)
        }
        
        // Remove if blocked user follows current user
        let followersQuery = try await db.collection(FirebaseManager.CollectionPath.follows)
            .whereField("followerId", isEqualTo: userId)
            .whereField("followingId", isEqualTo: currentUserId)
            .limit(to: 1)
            .getDocuments()
        
        if let followerDoc = followersQuery.documents.first {
            batch.deleteDocument(followerDoc.reference)
            
            // Decrement counts
            let currentUserRef = db.collection(FirebaseManager.CollectionPath.users).document(currentUserId)
            batch.updateData([
                "followersCount": FieldValue.increment(Int64(-1))
            ], forDocument: currentUserRef)
            
            let blockedUserRef = db.collection(FirebaseManager.CollectionPath.users).document(userId)
            batch.updateData([
                "followingCount": FieldValue.increment(Int64(-1))
            ], forDocument: blockedUserRef)
        }
        
        // Commit batch
        try await batch.commit()
        
        print("✅ Blocked user successfully")
        
        // Update local state
        blockedUsers.insert(userId)
        
        // Reload blocked users list
        await loadBlockedUsers()
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
    }
    
    // MARK: - Unblock User
    
    /// Unblock a user
    func unblockUser(userId: String) async throws {
        print("✅ Unblocking user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Find the block relationship
        let blockQuery = db.collection(FirebaseManager.CollectionPath.blocks)
            .whereField("blockerId", isEqualTo: currentUserId)
            .whereField("blockedUserId", isEqualTo: userId)
            .limit(to: 1)
        
        let snapshot = try await blockQuery.getDocuments()
        
        guard let blockDoc = snapshot.documents.first else {
            print("⚠️ User is not blocked")
            return
        }
        
        // Delete block relationship
        try await blockDoc.reference.delete()
        
        print("✅ Unblocked user successfully")
        
        // Update local state
        blockedUsers.remove(userId)
        
        // Reload blocked users list
        await loadBlockedUsers()
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    // MARK: - Check Block Status
    
    /// Check if current user has blocked another user
    func isBlocked(userId: String) async -> Bool {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            return false
        }
        
        // Check local cache first
        if blockedUsers.contains(userId) {
            return true
        }
        
        // Check Firestore
        do {
            let snapshot = try await db.collection(FirebaseManager.CollectionPath.blocks)
                .whereField("blockerId", isEqualTo: currentUserId)
                .whereField("blockedUserId", isEqualTo: userId)
                .limit(to: 1)
                .getDocuments()
            
            let isBlocked = !snapshot.documents.isEmpty
            
            if isBlocked {
                blockedUsers.insert(userId)
            }
            
            return isBlocked
        } catch {
            print("❌ Error checking block status: \(error)")
            return false
        }
    }
    
    /// Check if another user has blocked current user
    func isBlockedBy(userId: String) async -> Bool {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            return false
        }
        
        do {
            let snapshot = try await db.collection(FirebaseManager.CollectionPath.blocks)
                .whereField("blockerId", isEqualTo: userId)
                .whereField("blockedUserId", isEqualTo: currentUserId)
                .limit(to: 1)
                .getDocuments()
            
            return !snapshot.documents.isEmpty
        } catch {
            print("❌ Error checking if blocked by user: \(error)")
            return false
        }
    }
    
    // MARK: - Fetch Blocked Users
    
    /// Fetch all blocked users for current user
    func loadBlockedUsers() async {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            print("⚠️ No authenticated user")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            print("📥 Fetching blocked users...")
            
            let snapshot = try await db.collection(FirebaseManager.CollectionPath.blocks)
                .whereField("blockerId", isEqualTo: currentUserId)
                .order(by: "blockedAt", descending: true)
                .getDocuments()
            
            let blocks = try snapshot.documents.compactMap { doc in
                try doc.data(as: Block.self)
            }
            
            // Update blocked user IDs set
            blockedUsers = Set(blocks.map { $0.blockedUserId })
            
            // Fetch full user profiles for each blocked user
            var profiles: [BlockedUserProfile] = []
            
            for block in blocks {
                if let userDoc = try? await db.collection(FirebaseManager.CollectionPath.users)
                    .document(block.blockedUserId)
                    .getDocument(),
                   let userData = userDoc.data() {
                    
                    let profile = BlockedUserProfile(
                        id: block.blockedUserId,
                        displayName: userData["displayName"] as? String ?? "Unknown",
                        username: userData["username"] as? String ?? "unknown",
                        initials: userData["initials"] as? String ?? "??",
                        profileImageURL: userData["profileImageURL"] as? String,
                        blockedAt: block.blockedAt
                    )
                    
                    profiles.append(profile)
                }
            }
            
            blockedUsersList = profiles
            
            print("✅ Loaded \(profiles.count) blocked users")
        } catch {
            print("❌ Failed to load blocked users: \(error)")
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Real-time Listener
    
    /// Start listening to blocked users changes
    func startListening() {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            print("⚠️ No user ID for listener")
            return
        }
        
        print("🔊 Starting real-time listener for blocks...")
        
        let listener = db.collection(FirebaseManager.CollectionPath.blocks)
            .whereField("blockerId", isEqualTo: currentUserId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Blocks listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                Task {
                    let blockedIds = snapshot.documents.compactMap { doc -> String? in
                        doc.data()["blockedUserId"] as? String
                    }
                    
                    await MainActor.run {
                        self.blockedUsers = Set(blockedIds)
                        print("✅ Real-time update: \(blockedIds.count) blocked users")
                    }
                    
                    // Reload full profiles
                    await self.loadBlockedUsers()
                }
            }
        
        listeners.append(listener)
    }
    
    /// Stop all listeners
    func stopListening() {
        print("🔇 Stopping block listeners...")
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    // MARK: - Helper Methods
    
    /// Check if two users have any block relationship (either direction)
    func hasBlockRelationship(userId: String) async -> Bool {
        let youBlockedThem = await isBlocked(userId: userId)
        let theyBlockedYou = await isBlockedBy(userId: userId)
        
        return youBlockedThem || theyBlockedYou
    }
    
    /// Clear all cached data
    func clearCache() {
        blockedUsers.removeAll()
        blockedUsersList.removeAll()
    }
}

// MARK: - Firestore Collection Path Extension

extension FirebaseManager.CollectionPath {
    static let blocks = "blocks"
}
