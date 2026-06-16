//
//  BlockService.swift
//  AMENAPP
//
//  Created by Steph on 1/21/26.
//
//  Service for managing blocked users functionality
//

import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth
import Combine

// MARK: - Block Model

struct Block: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var blockerId: String      // User who blocked
    var blockedId: String      // User being blocked (matches Firestore rules)
    var blockedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case blockerId
        case blockedId
        case blockedAt
    }
    
    init(
        id: String? = nil,
        blockerId: String,
        blockedId: String,
        blockedAt: Date = Date()
    ) {
        self.id = id
        self.blockerId = blockerId
        self.blockedId = blockedId
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
    
    private lazy var firebaseManager = FirebaseManager.shared
    private lazy var db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    private init() {
        guard FirebaseApp.app() != nil else { return }
        setupAuthListener()
    }
    
    deinit {
        if let h = authStateListener {
            Auth.auth().removeStateDidChangeListener(h)
        }
        listeners.forEach { $0.remove() }
    }
    
    /// Automatically start/stop the real-time block listener when auth state changes.
    /// This ensures `blockedUsers` is always fresh for `NotificationService.processNotifications`.
    private func setupAuthListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if user != nil {
                    if self.listeners.isEmpty {
                        self.startListening()
                        await self.loadBlockedUsers()
                    }
                } else {
                    self.stopListening()
                    self.clearCache()
                }
            }
        }
    }
    
    // MARK: - Block User
    
    /// Block a user.
    ///
    /// Calls the `createBlock` Cloud Function, which atomically writes to:
    ///   1. `blockedUsers/{blockerId}_{blockedId}` — read by antiHarassmentEnforcement CF
    ///      to prevent server-side message delivery to blocked users.
    ///   2. `users/{blockerId}/blockedUsers/{blockedId}` — checked by Firestore security
    ///      rules (callerIsBlockedByAuthor) and triggers blockRelationshipCleanup CF.
    /// The blockRelationshipCleanup trigger handles follow-edge removal server-side.
    func blockUser(userId: String) async throws {
        dlog("🚫 Blocking user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        guard userId != currentUserId else {
            dlog("⚠️ Cannot block yourself")
            return
        }
        
        if await isBlocked(userId: userId) {
            dlog("⚠️ User is already blocked")
            return
        }
        
        // Call createBlock CF — atomically writes to both stores.
        // blockRelationshipCleanup fires automatically on subcollection create.
        _ = try await Functions.functions().httpsCallable("createBlock").call(["blockedId": userId])
        
        dlog("✅ Blocked user successfully (both stores written via CF)")

        blockedUsers.insert(userId)

        // Archive conversations immediately on the client (non-fatal — CF cleanup
        // is the authoritative cleanup; this is a UX optimisation).
        try? await FirebaseMessagingService.shared.archiveConversationsWithUser(userId)

        await loadBlockedUsers()

        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
    }
    
    // MARK: - Unblock User
    
    /// Unblock a user.
    ///
    /// Calls the `createUnblock` Cloud Function, which atomically removes both
    /// `blockedUsers/{blockerId}_{blockedId}` and `users/{blockerId}/blockedUsers/{blockedId}`.
    func unblockUser(userId: String) async throws {
        dlog("✅ Unblocking user: \(userId)")
        
        guard firebaseManager.currentUser?.uid != nil else {
            throw FirebaseError.unauthorized
        }
        
        _ = try await Functions.functions().httpsCallable("createUnblock").call(["blockedId": userId])
        
        dlog("✅ Unblocked user successfully (both stores cleared via CF)")
        
        blockedUsers.remove(userId)
        await loadBlockedUsers()
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    // MARK: - Check Block Status
    
    /// Check if current user has blocked another user.
    /// Uses O(1) doc-ID lookup on `blockedUsers/{currentUserId}_{userId}`.
    func isBlocked(userId: String) async -> Bool {
        guard let currentUserId = firebaseManager.currentUser?.uid else { return false }
        
        if blockedUsers.contains(userId) { return true }
        
        do {
            let doc = try await db.collection("blockedUsers")
                .document("\(currentUserId)_\(userId)")
                .getDocument()
            if doc.exists { blockedUsers.insert(userId) }
            return doc.exists
        } catch {
            dlog("❌ Error checking block status: \(error)")
            return false
        }
    }
    
    /// Check if current user has been blocked by `uid` (mid-session re-check).
    /// Alias for isBlockedBy(userId:) with a name that reads clearly at the call site:
    ///   `BlockService.shared.isBlocked(byUser: recipientId)`
    func isBlocked(byUser uid: String) async -> Bool {
        return await isBlockedBy(userId: uid)
    }

    /// Check if another user has blocked current user.
    /// Uses O(1) doc-ID lookup on `blockedUsers/{userId}_{currentUserId}`.
    func isBlockedBy(userId: String) async -> Bool {
        guard let currentUserId = firebaseManager.currentUser?.uid else { return false }
        
        do {
            let doc = try await db.collection("blockedUsers")
                .document("\(userId)_\(currentUserId)")
                .getDocument()
            return doc.exists
        } catch {
            dlog("❌ Error checking if blocked by user: \(error)")
            return false
        }
    }
    
    // MARK: - Fetch Blocked Users
    
    /// Fetch all blocked users for current user.
    /// Reads from `users/{uid}/blockedUsers` subcollection, which is populated
    /// atomically by the `createBlock` Cloud Function.
    func loadBlockedUsers() async {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            dlog("⚠️ No authenticated user")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            dlog("📥 Fetching blocked users...")
            
            let snapshot = try await db
                .collection("users").document(currentUserId)
                .collection("blockedUsers")
                .getDocuments()
            
            let blockedIds = snapshot.documents.compactMap { $0.data()["blockedId"] as? String }
            blockedUsers = Set(blockedIds)
            
            var profiles: [BlockedUserProfile] = []
            for doc in snapshot.documents {
                guard let blockedId = doc.data()["blockedId"] as? String else { continue }
                let createdAt = (doc.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                
                if let userDoc = try? await db.collection(FirebaseManager.CollectionPath.users)
                    .document(blockedId)
                    .getDocument(),
                   let userData = userDoc.data() {
                    profiles.append(BlockedUserProfile(
                        id: blockedId,
                        displayName: userData["displayName"] as? String ?? "Unknown",
                        username: userData["username"] as? String ?? "unknown",
                        initials: userData["initials"] as? String ?? "??",
                        profileImageURL: userData["profileImageURL"] as? String,
                        blockedAt: createdAt
                    ))
                }
            }
            
            blockedUsersList = profiles
            dlog("✅ Loaded \(profiles.count) blocked users")
        } catch {
            dlog("❌ Failed to load blocked users: \(error)")
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Real-time Listener
    
    /// Start listening to blocked users changes.
    /// Listens to `users/{uid}/blockedUsers` subcollection, which is written
    /// atomically by the `createBlock` Cloud Function.
    func startListening() {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            dlog("⚠️ No user ID for listener")
            return
        }
        
        dlog("🔊 Starting real-time listener for blocks...")
        
        let listener = db
            .collection("users").document(currentUserId)
            .collection("blockedUsers")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    dlog("❌ Blocks listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                Task { @MainActor in
                    let blockedIds = snapshot.documents.compactMap { doc -> String? in
                        doc.data()["blockedId"] as? String
                    }
                    self.blockedUsers = Set(blockedIds)
                    dlog("✅ Real-time update: \(blockedIds.count) blocked users")
                    await self.loadBlockedUsers()
                }
            }
        
        listeners.append(listener)
    }
    
    /// Stop all listeners
    func stopListening() {
        dlog("🔇 Stopping block listeners...")
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    /// Stop listeners AND clear all in-memory user state so previous user's
    /// block list is never visible to the next signed-in account.
    /// Called by AppLifecycleManager.performFullSignOutCleanup().
    func resetUserState() {
        stopListening()
        blockedUsers.removeAll()
        blockedUsersList.removeAll()
        dlog("🧹 BlockService: user state cleared on sign-out")
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


