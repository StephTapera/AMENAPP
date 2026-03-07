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
import UserNotifications

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
    private let cacheTTL: TimeInterval = 2 // 2 second cache — just enough to coalesce
                                            // simultaneous listener fires; short enough
                                            // that a markAsRead write is reflected immediately
    
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
    
    // Auth state listener — clears badge on sign-out, starts updates on sign-in
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    private init() {
        print("🔰 BadgeCountManager initialized")
        setupAuthStateListener()
    }
    
    deinit {
        conversationsListener?.remove()
        notificationsListener?.remove()
        if let authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
    }
    
    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            Task { @MainActor in
                if user != nil {
                    // User signed in — start real-time updates (idempotent)
                    self.startRealtimeUpdates()
                } else {
                    // User signed out — immediately zero the badge and stop listeners
                    self.stopRealtimeUpdates()
                    self.clearBadge()
                    print("🧹 Badge cleared on sign-out")
                }
            }
        }
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

    /// Immediate badge update for user-triggered actions (no debounce, no cache)
    /// Use this when user marks notifications as read or performs actions that should update badge instantly
    func immediateUpdate() async {
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
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        print("🧹 Badge cleared")
    }

    /// Optimistically zero the messages dot and write unreadCounts=0 to Firestore
    /// for all conversations. The snapshot listener will confirm the zero once the
    /// writes land, keeping local and remote state consistent.
    func clearMessages() {
        unreadMessages = 0
        totalBadgeCount = unreadNotifications
        cachedBadgeCount = nil
        cacheTimestamp = nil
        applyBadgeCount(unreadNotifications)
        print("🧹 Messages badge cleared")

        // Zero unreadCounts in Firestore so the real-time listener stays at 0
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let db = self.db  // capture before leaving @MainActor
        Task.detached(priority: .utility) {
            do {
                let snapshot = try await db.collection("conversations")
                    .whereField("participantIds", arrayContains: userId)
                    .whereField("conversationStatus", isEqualTo: "accepted")
                    .getDocuments()
                let batch = db.batch()
                for doc in snapshot.documents {
                    if let counts = doc.data()["unreadCounts"] as? [String: Int],
                       let count = counts[userId], count > 0 {
                        batch.updateData(["unreadCounts.\(userId)": 0], forDocument: doc.reference)
                    }
                }
                try await batch.commit()
            } catch {
                print("⚠️ Failed to clear Firestore unreadCounts: \(error.localizedDescription)")
            }
        }
    }

    /// Optimistically zero the notifications dot immediately (real count will follow from listener)
    func clearNotifications() {
        unreadNotifications = 0
        totalBadgeCount = unreadMessages
        cachedBadgeCount = nil
        cacheTimestamp = nil
        applyBadgeCount(unreadMessages)
        print("🧹 Notifications badge cleared")
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
        // P0 FIX: Use UNUserNotificationCenter (modern API) instead of UIApplication
        // This is the correct iOS 16+ API and prevents conflicts
        // Note: Also works in simulator for testing (previously was disabled)
        Task {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(count)
                print("📱 App icon badge set to: \(count)")
            } catch {
                print("⚠️ Failed to set badge count: \(error)")
            }
        }
    }
}

// MARK: - Notification Listener Extensions

extension BadgeCountManager {
    /// Setup real-time listener for badge updates (optional, more responsive).
    ///
    /// DEDUPE FIX: Both the conversations listener and the notifications listener call
    /// `requestBadgeUpdate()`, which is debounced (500 ms).  Even if both fire within
    /// the same millisecond only ONE `performBadgeUpdate` runs, eliminating the
    /// double-badge-increment race window that existed previously.
    func startRealtimeUpdates() {
        guard !isListening else {
            print("⚠️ Badge listeners already active")
            return
        }
        guard let userId = Auth.auth().currentUser?.uid else { return }

        conversationsListener = db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .whereField("conversationStatus", isEqualTo: "accepted")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("❌ Badge – conversations listener error: \(error.localizedDescription)")
                    return
                }
                // Compute unread message count directly from snapshot — avoids
                // stale cached values after a markAsRead write.
                guard let docs = snapshot?.documents else { return }
                let uid = Auth.auth().currentUser?.uid ?? ""
                var msgCount = 0
                for doc in docs {
                    if let counts = doc.data()["unreadCounts"] as? [String: Int],
                       let c = counts[uid] { msgCount += c }
                }
                Task { @MainActor in
                    self.unreadMessages = msgCount
                    // Invalidate cache so the combined total is recomputed fresh
                    self.cachedBadgeCount = nil
                    self.cacheTimestamp = nil
                    self.requestBadgeUpdate()
                }
            }

        notificationsListener = db.collection("users")
            .document(userId)
            .collection("notifications")
            .whereField("read", isEqualTo: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("❌ Badge – notifications listener error: \(error.localizedDescription)")
                    return
                }
                // Use snapshot count directly — Firestore delivers this listener
                // only after the read=true write commits, so it's always fresh.
                let count = snapshot?.documents.count ?? 0
                Task { @MainActor in
                    self.unreadNotifications = count
                    // Invalidate cache so the combined total is recomputed fresh,
                    // matching the conversations listener pattern. This avoids applying
                    // a stale unreadMessages value when both listeners fire simultaneously.
                    self.cachedBadgeCount = nil
                    self.cacheTimestamp = nil
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
