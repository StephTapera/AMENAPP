//
//  FollowStateManager.swift
//  AMENAPP
//
//  ✅ P0-7: Single source of truth for follow state across the app
//  Prevents state inconsistency where buttons show wrong state
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
final class FollowStateManager: ObservableObject {
    static let shared = FollowStateManager()
    
    // ✅ Single source of truth for follow states
    @Published private(set) var followStates: [String: FollowState] = [:]
    
    // Cache management
    private var fetchTasks: [String: Task<FollowState, Never>] = [:]
    private let cacheExpiry: TimeInterval = 60 // 1 minute cache
    private var cacheTimestamps: [String: Date] = [:]
    
    private let db = Firestore.firestore()
    
    private init() {
        print("🔰 FollowStateManager initialized")
        
        // Listen for follow state changes from other parts of the app
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFollowStateChange),
            name: .followStateDidChange,
            object: nil
        )
    }
    
    // MARK: - Follow State Enum
    
    enum FollowState: Equatable {
        case notFollowing
        case requested          // You sent a follow request
        case following          // You follow them
        case followsYou         // They follow you (but you don't follow them)
        case mutualFollow       // Both following each other
        
        var buttonTitle: String {
            switch self {
            case .notFollowing, .followsYou:
                return "Follow"
            case .requested:
                return "Requested"
            case .following, .mutualFollow:
                return "Following"
            }
        }
        
        var buttonColor: Color {
            switch self {
            case .notFollowing, .followsYou:
                return .blue
            case .requested:
                return .gray
            case .following, .mutualFollow:
                return .green
            }
        }
        
        var isFollowing: Bool {
            self == .following || self == .mutualFollow
        }
    }
    
    // MARK: - Public API
    
    /// Get follow state for a user (cached or fetch from Firestore)
    func getState(for userId: String) async -> FollowState {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return .notFollowing
        }
        
        // Don't check state for yourself
        if userId == currentUserId {
            return .notFollowing
        }
        
        // Check if cache is valid
        if let cached = followStates[userId],
           let timestamp = cacheTimestamps[userId],
           Date().timeIntervalSince(timestamp) < cacheExpiry {
            return cached
        }
        
        // If there's already a fetch in progress, wait for it
        if let existingTask = fetchTasks[userId] {
            return await existingTask.value
        }
        
        // Create new fetch task
        let task = Task<FollowState, Never> {
            let state = await fetchFollowState(userId: userId)
            
            // Update cache
            followStates[userId] = state
            cacheTimestamps[userId] = Date()
            fetchTasks.removeValue(forKey: userId)
            
            return state
        }
        
        fetchTasks[userId] = task
        return await task.value
    }
    
    /// Update state for a user (after follow/unfollow action)
    func updateState(for userId: String, state: FollowState) {
        followStates[userId] = state
        cacheTimestamps[userId] = Date()
        
        print("✅ Updated follow state for \(userId): \(state)")
        
        // Broadcast update via NotificationCenter for cross-view updates
        NotificationCenter.default.post(
            name: .followStateDidChange,
            object: nil,
            userInfo: ["userId": userId, "state": state]
        )
    }
    
    /// Invalidate cache for a specific user
    func invalidateCache(for userId: String) {
        followStates.removeValue(forKey: userId)
        cacheTimestamps.removeValue(forKey: userId)
        fetchTasks[userId]?.cancel()
        fetchTasks.removeValue(forKey: userId)
        
        print("🗑️ Invalidated cache for \(userId)")
    }
    
    /// Clear all caches
    func clearAllCaches() {
        followStates.removeAll()
        cacheTimestamps.removeAll()
        fetchTasks.values.forEach { $0.cancel() }
        fetchTasks.removeAll()
        
        print("🧹 Cleared all follow state caches")
    }
    
    // MARK: - Private Methods
    
    private func fetchFollowState(userId: String) async -> FollowState {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return .notFollowing
        }
        
        do {
            // Check if you follow them
            let youFollowThem = try await checkFollow(from: currentUserId, to: userId)
            
            // Check if they follow you
            let theyFollowYou = try await checkFollow(from: userId, to: currentUserId)
            
            // Check for pending request
            let hasPendingRequest = try await checkPendingRequest(from: currentUserId, to: userId)
            
            // Determine state
            if youFollowThem && theyFollowYou {
                return .mutualFollow
            } else if youFollowThem {
                return .following
            } else if theyFollowYou {
                return .followsYou
            } else if hasPendingRequest {
                return .requested
            } else {
                return .notFollowing
            }
            
        } catch {
            print("❌ Failed to fetch follow state for \(userId): \(error)")
            return .notFollowing
        }
    }
    
    private func checkFollow(from: String, to: String) async throws -> Bool {
        let doc = try await db.collection("users")
            .document(from)
            .collection("following")
            .document(to)
            .getDocument()
        
        return doc.exists
    }
    
    private func checkPendingRequest(from: String, to: String) async throws -> Bool {
        let snapshot = try await db.collection("followRequests")
            .whereField("fromUserId", isEqualTo: from)
            .whereField("toUserId", isEqualTo: to)
            .whereField("status", isEqualTo: "pending")
            .limit(to: 1)
            .getDocuments()
        
        return !snapshot.documents.isEmpty
    }
    
    @objc private func handleFollowStateChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let userId = userInfo["userId"] as? String,
              let state = userInfo["state"] as? FollowState else {
            return
        }
        
        // Update local cache
        followStates[userId] = state
        cacheTimestamps[userId] = Date()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let followStateDidChange = Notification.Name("followStateDidChange")
}
