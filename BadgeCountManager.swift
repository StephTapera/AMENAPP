//
//  BadgeCountManager.swift
//  AMENAPP
//
//  Thread-safe badge count manager with caching and debouncing
//  Fixes: Race conditions, N+1 queries, performance issues
//

import Foundation
import UIKit
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class BadgeCountManager: ObservableObject {
    static let shared = BadgeCountManager()
    
    @Published private(set) var totalBadgeCount: Int = 0
    @Published private(set) var unreadMessages: Int = 0
    @Published private(set) var unreadNotifications: Int = 0
    
    private let db = Firestore.firestore()
    
    // Cache with TTL
    private var cachedBadgeCount: Int?
    private var cacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 30 // 30 seconds cache
    
    // Debouncing
    private var updateTask: Task<Void, Never>?
    private let debounceDelay: TimeInterval = 0.5 // 500ms debounce
    
    // Locking for thread safety
    private var isUpdating = false
    private var pendingUpdate = false
    
    // P0 FIX: Store listeners for proper cleanup
    private var conversationsListener: ListenerRegistration?
    private var notificationsListener: ListenerRegistration?
    private var isListening = false
    
    private init() {
        print("🔰 BadgeCountManager initialized")
    }
    
    deinit {
        // Cleanup listeners synchronously
        conversationsListener?.remove()
        notificationsListener?.remove()
    }
    
    // MARK: - Public API
    
    /// Request badge count update (debounced and cached)
    func requestBadgeUpdate() {
        // If cache is valid, use it immediately
        if let cached = getCachedBadgeCount() {
            applyBadgeCount(cached)
            print("📛 Using cached badge count: \(cached)")
            return
        }
        
        // Cancel any pending update
        updateTask?.cancel()
        
        // Schedule new update with debounce
        updateTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(debounceDelay * 1000)))
            
            guard !Task.isCancelled else { return }
            
            await performBadgeUpdate()
        }
    }
    
    /// Force immediate badge update (bypasses cache)
    func forceUpdateBadgeCount() async {
        updateTask?.cancel()
        cachedBadgeCount = nil
        cacheTimestamp = nil
        await performBadgeUpdate()
    }
    
    /// Clear badge (sets to 0)
    func clearBadge() {
        totalBadgeCount = 0
        unreadMessages = 0
        unreadNotifications = 0
        cachedBadgeCount = 0
        cacheTimestamp = Date()
        UIApplication.shared.applicationIconBadgeNumber = 0
        print("🧹 Badge cleared")
    }
    
    // MARK: - Private Methods
    
    private func performBadgeUpdate() async {
        // Prevent concurrent updates (locking)
        guard !isUpdating else {
            pendingUpdate = true
            print("⏳ Badge update already in progress, marking pending")
            return
        }
        
        isUpdating = true
        pendingUpdate = false
        
        defer {
            isUpdating = false
            
            // If another update was requested during this one, run it
            if pendingUpdate {
                Task {
                    await performBadgeUpdate()
                }
            }
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ No authenticated user for badge update")
            clearBadge()
            return
        }
        
        do {
            // Parallel queries for performance
            async let messagesCount = calculateUnreadMessages(userId: userId)
            async let notificationsCount = calculateUnreadNotifications(userId: userId)
            
            let (messages, notifications) = try await (messagesCount, notificationsCount)
            
            let total = messages + notifications
            
            // Update published properties
            unreadMessages = messages
            unreadNotifications = notifications
            totalBadgeCount = total
            
            // Cache the result
            cachedBadgeCount = total
            cacheTimestamp = Date()
            
            // Update app icon badge
            applyBadgeCount(total)
            
            print("✅ Badge updated: \(total) (messages: \(messages), notifications: \(notifications))")
            
        } catch {
            print("❌ Badge update failed: \(error.localizedDescription)")
        }
    }
    
    private func calculateUnreadMessages(userId: String) async throws -> Int {
        let snapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .whereField("conversationStatus", isEqualTo: "accepted")
            .getDocuments()
        
        var total = 0
        for document in snapshot.documents {
            if let unreadCounts = document.data()["unreadCounts"] as? [String: Int],
               let count = unreadCounts[userId] {
                total += count
            }
        }
        
        return total
    }
    
    private func calculateUnreadNotifications(userId: String) async throws -> Int {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("notifications")
            .whereField("read", isEqualTo: false)
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    private func getCachedBadgeCount() -> Int? {
        guard let cached = cachedBadgeCount,
              let timestamp = cacheTimestamp,
              Date().timeIntervalSince(timestamp) < cacheTTL else {
            return nil
        }
        return cached
    }
    
    private func applyBadgeCount(_ count: Int) {
        #if !targetEnvironment(simulator)
        UIApplication.shared.applicationIconBadgeNumber = count
        #endif
    }
}

// MARK: - Notification Listener Extensions

extension BadgeCountManager {
    /// Setup real-time listener for badge updates (optional, more responsive)
    func startRealtimeUpdates() {
        // P0 FIX: Prevent duplicate listeners
        guard !isListening else {
            print("⚠️ Badge listeners already active")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // P0 FIX: Store listener for cleanup
        conversationsListener = db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Conversations listener error: \(error)")
                    return
                }
                
                Task { @MainActor in
                    self.requestBadgeUpdate()
                }
            }
        
        // P0 FIX: Store listener for cleanup
        notificationsListener = db.collection("users")
            .document(userId)
            .collection("notifications")
            .whereField("read", isEqualTo: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Notifications listener error: \(error)")
                    return
                }
                
                Task { @MainActor in
                    self.requestBadgeUpdate()
                }
            }
        
        isListening = true
        print("✅ Real-time badge listeners started")
    }
    
    /// Stop real-time updates and cleanup listeners
    func stopRealtimeUpdates() {
        conversationsListener?.remove()
        notificationsListener?.remove()
        conversationsListener = nil
        notificationsListener = nil
        isListening = false
        print("🛑 Real-time badge listeners stopped")
    }
}
