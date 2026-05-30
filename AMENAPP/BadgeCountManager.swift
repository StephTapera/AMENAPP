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
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import UserNotifications
import WidgetKit

@MainActor
class BadgeCountManager: ObservableObject {
    static let shared = BadgeCountManager()
    
    @Published private(set) var totalBadgeCount: Int = 0
    @Published private(set) var unreadMessages: Int = 0
    @Published private(set) var unreadNotifications: Int = 0
    
    private lazy var db = Firestore.firestore()
    
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
    private var badgeConversationsRetryCount = 0

    // PERF FIX: Track whether the real-time conversations listener has fired at least
    // once and populated unreadMessages. When true, performBadgeUpdate() skips the
    // separate calculateUnreadMessages() Firestore query because the listener result
    // is already authoritative — this eliminates the 200-read scan every time any
    // badge update is triggered while the listener is active.
    private var listenerHasPopulatedMessages = false

    // Suppression window: after clearNotifications() the listener fires with
    // stale unread docs before markAllAsRead() writes commit, which flips the
    // badge back from 0 to the old count (0→8 race).  We suppress
    // requestBadgeUpdate() for 3 seconds after a clear to let the writes land.
    private var notificationsClearTime: Date?
    private let notificationsClearSuppressionInterval: TimeInterval = 5.0

    // Auth state listener — clears badge on sign-out, starts updates on sign-in
    private var authStateListener: AuthStateDidChangeListenerHandle?

    // V2: Server-side unseenCount listener for drift recovery
    private var serverCountListener: ListenerRegistration?
    private var serverUnseenCount: Int?
    private var driftDetectedAt: Date?
    private var driftRecoveryTask: Task<Void, Never>?
    private var reconciliationTask: Task<Void, Never>?
    private var badgeServerCountRetryCount = 0

    private init() {
        dlog("🔰 BadgeCountManager initialized")
        // Guard: skip Firebase setup when running in a test host that has not
        // configured Firebase (FirebaseApp.configure() was never called).
        // This prevents Auth.auth() and Firestore.firestore() from crashing
        // the test process during singleton initialization.
        guard FirebaseApp.app() != nil else { return }
        setupAuthStateListener()
    }
    
    deinit {
        conversationsListener?.remove()
        notificationsListener?.remove()
        if let authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
        // MEDIUM FIX: Cancel background reconciliation tasks so they cannot write
        // stale badge counts to a newly-signed-in user's Firestore document if
        // they fire after sign-out. stopRealtimeUpdates() cancels these at sign-out
        // time, but deinit is the safety net if the singleton is ever deallocated
        // mid-flight (e.g. during a test tear-down or simulator reset).
        driftRecoveryTask?.cancel()
        reconciliationTask?.cancel()
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
                    self.resetRetryCounters()
                    self.clearBadge()
                    dlog("🧹 Badge cleared on sign-out")
                }
            }
        }
    }
    
    // MARK: - Public API
    
    /// Request badge count update (debounced and cached)
    func requestBadgeUpdate() {
        // Suppression window: if notifications were just cleared, the Firestore
        // listener fires with stale unread docs before markAllAsRead() writes commit.
        // Skip the update to prevent the badge flipping 0→8.
        if let clearTime = notificationsClearTime,
           Date().timeIntervalSince(clearTime) < notificationsClearSuppressionInterval {
            dlog("🚫 Badge update suppressed — notifications clear in progress")
            return
        }

        // If cache is valid, use it immediately
        if let cached = getCachedBadgeCount() {
            applyBadgeCount(cached)
            dlog("📛 Using cached badge count: \(cached)")
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

    /// Immediate badge update for user-triggered actions (no debounce, no cache).
    /// Use this when user marks a single notification as read or performs actions that
    /// should update badge instantly. Does NOT clear the notifications suppression window
    /// so it stays safe to call during the mark-all-read flow.
    func immediateUpdate() async {
        updateTask?.cancel()
        cachedBadgeCount = nil
        cacheTimestamp = nil
        // NOTE: intentionally NOT clearing notificationsClearTime here.
        // If we are inside the suppression window (e.g. called after markAllAsRead),
        // performBadgeUpdate will re-query Firestore before the write has propagated
        // and will return the stale count, flipping the badge back from 0.
        // The suppression window is only cleared by clearNotifications() itself
        // (which resets it after the post-suppression re-query fires) or by sign-out.
        if let clearTime = notificationsClearTime,
           Date().timeIntervalSince(clearTime) < notificationsClearSuppressionInterval {
            dlog("🚫 immediateUpdate suppressed — notifications clear in progress")
            return
        }
        await performBadgeUpdate()
    }
    
    /// Full reset — stops listeners, zeroes all counts, and clears every cache.
    /// Call on sign-out so no badge data from the previous user leaks to the next session.
    func reset() {
        stopRealtimeUpdates()
        resetRetryCounters()
        // Zero all published counts
        totalBadgeCount = 0
        unreadMessages = 0
        unreadNotifications = 0
        // Clear in-memory caches
        cachedBadgeCount = nil
        cacheTimestamp = nil
        notificationsClearTime = nil
        // Clear persisted fallback count so the next user's badge starts at 0
        UserDefaults.standard.removeObject(forKey: "badgeLastKnownTotal")
        // Zero the app icon badge and widget
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        syncToWidget()
        dlog("🧹 BadgeCountManager: full reset on sign-out")
    }

    /// Clear badge (sets to 0)
    func clearBadge() {
        totalBadgeCount = 0
        unreadMessages = 0
        unreadNotifications = 0
        cachedBadgeCount = 0
        cacheTimestamp = Date()
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        dlog("🧹 Badge cleared")
    }

    /// Optimistically zero the messages dot and write unreadCounts=0 to Firestore
    /// for all conversations. The snapshot listener will confirm the zero once the
    /// writes land, keeping local and remote state consistent.
    func clearMessages() {
        unreadMessages = 0
        totalBadgeCount = unreadNotifications
        cachedBadgeCount = unreadNotifications
        cacheTimestamp = Date()
        notificationsClearTime = Date()
        applyBadgeCount(unreadNotifications)
        dlog("🧹 Messages badge cleared")

        // Zero unreadCounts in Firestore so the real-time listener stays at 0
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let db = self.db  // capture before leaving @MainActor
        Task.detached(priority: .utility) {
            // Retry once if we hit a transient permission error during auth propagation
            for attempt in 1...2 {
                do {
                    let snapshot = try await db.collection("conversations")
                        .whereField("participantIds", arrayContains: userId)
                        .getDocuments()
                    let batch = db.batch()
                    for doc in snapshot.documents {
                        let status = doc.data()["conversationStatus"] as? String
                        guard status == nil || status == "accepted" else { continue }
                        if let counts = doc.data()["unreadCounts"] as? [String: Int],
                           let count = counts[userId], count > 0 {
                            batch.updateData(["unreadCounts.\(userId)": 0], forDocument: doc.reference)
                        }
                    }
                    try await batch.commit()
                    return  // success
                } catch {
                    let nsError = error as NSError
                    if nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7 && attempt == 1 {
                        // Transient auth-propagation race — wait and retry once
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        continue
                    }
                    dlog("⚠️ Failed to clear Firestore unreadCounts: \(error.localizedDescription)")
                    return
                }
            }
        }
    }

    /// Optimistically zero the notifications dot immediately (real count will follow from listener)
    func clearNotifications() {
        unreadNotifications = 0
        totalBadgeCount = unreadMessages
        // Cache the zero so any requestBadgeUpdate() during the suppression
        // window returns 0 from cache instead of querying stale Firestore data.
        cachedBadgeCount = unreadMessages
        cacheTimestamp = Date()
        notificationsClearTime = Date()
        // Persist the cleared count so the offline fallback doesn't restore the
        // stale pre-clear value after an app kill/relaunch.
        UserDefaults.standard.set(unreadMessages, forKey: "badgeLastKnownTotal")
        applyBadgeCount(unreadMessages)
        dlog("🧹 Notifications badge cleared")

        // Schedule a post-suppression re-query to pick up the true count once
        // the markAllAsRead() writes have had time to commit.  This covers the
        // edge case where the Firestore listener doesn't re-fire after the
        // suppression window expires (e.g. writes committed during suppression
        // and the listener already delivered the final snapshot).
        Task {
            try? await Task.sleep(nanoseconds: UInt64(notificationsClearSuppressionInterval * 1_000_000_000) + 500_000_000)
            await immediateUpdate()
        }
    }
    
    // MARK: - Private Methods
    
    private func performBadgeUpdate() async {
        // Prevent concurrent updates (locking)
        guard !isUpdating else {
            pendingUpdate = true
            dlog("⏳ Badge update already in progress, marking pending")
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
            dlog("⚠️ No authenticated user for badge update")
            clearBadge()
            return
        }
        
        do {
            // PERF FIX: When the real-time conversations listener is active and has already
            // populated unreadMessages from a snapshot, skip calculateUnreadMessages() entirely.
            // The listener result is authoritative and eliminates the 200-read Firestore scan
            // that previously ran on every badge trigger while the listener was running.
            var messages = listenerHasPopulatedMessages ? unreadMessages : 0
            var notifications = 0
            if listenerHasPopulatedMessages {
                // Only query notifications; message count is already known from listener
                notifications = try await calculateUnreadNotifications(userId: userId)
            } else {
                // Listener not yet active — query both (initial startup path)
                try await withThrowingTaskGroup(of: (Bool, Int).self) { group in
                    group.addTask { (true, try await self.calculateUnreadMessages(userId: userId)) }
                    group.addTask { (false, try await self.calculateUnreadNotifications(userId: userId)) }
                    for try await (isMessages, count) in group {
                        if isMessages { messages = count } else { notifications = count }
                    }
                }
            }
            
            let total = messages + notifications
            
            // Update published properties
            unreadMessages = messages
            unreadNotifications = notifications
            totalBadgeCount = total
            
            // Cache the result
            cachedBadgeCount = total
            cacheTimestamp = Date()
            // OFFLINE FIX: Persist so the offline fallback can recover this count after an app kill.
            UserDefaults.standard.set(total, forKey: "badgeLastKnownTotal")
            
            // Update app icon badge
            applyBadgeCount(total)
            
            dlog("✅ Badge updated: \(total) (messages: \(messages), notifications: \(notifications))")
            
        } catch {
            dlog("❌ Badge update failed: \(error.localizedDescription)")
            // OFFLINE FIX: When the badge query fails (typically because the device
            // is offline), fall back to the last persisted count so the badge doesn't
            // silently reset to 0. The persisted count is written on every successful
            // update so it always reflects the last authoritative server value.
            let persistedTotal = UserDefaults.standard.integer(forKey: "badgeLastKnownTotal")
            if persistedTotal > 0 && totalBadgeCount == 0 {
                totalBadgeCount = persistedTotal
                applyBadgeCount(persistedTotal)
                dlog("📛 Badge offline fallback: using last-known count \(persistedTotal)")
            }
        }
    }
    
    private func calculateUnreadMessages(userId: String) async throws -> Int {
        // Query only by participantIds to avoid requiring a composite index.
        // Filter conversationStatus client-side.
        // Limit to 500 to cap read cost — badge count saturates at 500 unread.
        let snapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .limit(to: 500)
            .getDocuments()
        
        var total = 0
        for document in snapshot.documents {
            let status = document.data()["conversationStatus"] as? String
            guard status == nil || status == "accepted" else { continue }
            if let unreadCounts = document.data()["unreadCounts"] as? [String: Int],
               let count = unreadCounts[userId] {
                total += count
            }
        }
        
        return total
    }
    
    private func calculateUnreadNotifications(userId: String) async throws -> Int {
        // Limit to 200 — badge count saturates well before this point.
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("notifications")
            .whereField("read", isEqualTo: false)
            .limit(to: 200)
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
                dlog("📱 App icon badge set to: \(count)")
            } catch {
                dlog("⚠️ Failed to set badge count: \(error)")
            }
        }
        syncToWidget()
    }

    /// Push current badge counts to the shared App Group so widgets can display them.
    /// Reloads all widget timelines so the home screen reflects the updated counts
    /// within the system's 30-second window.
    private func syncToWidget() {
        let defaults = UserDefaults(suiteName: "group.com.amenapp.shared")
        defaults?.set(totalBadgeCount, forKey: "widget_unread")
        defaults?.set(unreadNotifications, forKey: "widget_notif_unread")
        defaults?.set(unreadMessages, forKey: "widget_message_unread")
        WidgetCenter.shared.reloadAllTimelines()
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
            dlog("⚠️ Badge listeners already active")
            return
        }
        guard let userId = Auth.auth().currentUser?.uid else { return }

        // Reset the retry counter on a fresh explicit start so the new session
        // gets a full 3-retry budget. This is safe here because startRealtimeUpdates()
        // is only called from the auth-state listener (sign-in) or external callers —
        // NOT from the internal retry path (which calls reattachConversationsListener directly).
        badgeConversationsRetryCount = 0

        reattachConversationsListener(userId: userId)

        notificationsListener = db.collection("users")
            .document(userId)
            .collection("notifications")
            .whereField("read", isEqualTo: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    dlog("❌ Badge – notifications listener error: \(error.localizedDescription)")
                    return
                }
                let count = snapshot?.documents.count ?? 0
                Task { @MainActor in
                    // Suppression window: after clearNotifications(), the listener
                    // fires with stale unread docs before markAllAsRead() writes
                    // fully propagate.  Suppress BOTH the @Published property
                    // update AND the requestBadgeUpdate() call so the tab-bar
                    // badge stays at 0 instead of flipping back to the old count.
                    if let clearTime = self.notificationsClearTime,
                       Date().timeIntervalSince(clearTime) < self.notificationsClearSuppressionInterval {
                        dlog("🚫 Badge listener suppressed — notifications clear in progress (stale count=\(count))")
                        return
                    }

                    self.unreadNotifications = count
                    // Invalidate cache so the combined total is recomputed fresh,
                    // matching the conversations listener pattern.
                    self.cachedBadgeCount = nil
                    self.cacheTimestamp = nil
                    self.requestBadgeUpdate()
                }
            }

        // V2: Listen to server-side unseenCount for drift recovery
        startServerCountListener(userId: userId)

        // V2: Start periodic reconciliation (every 5 minutes while active)
        startPeriodicReconciliation()

        isListening = true
        dlog("✅ Real-time badge listeners started")
    }

    /// Attach (or reattach) only the conversations sub-listener.
    /// Called from startRealtimeUpdates and from the permission-error retry path.
    /// Does NOT touch notificationsListener or isListening — those stay as-is.
    private func reattachConversationsListener(userId: String) {
        // Safety: remove any stale listener before reattaching.
        conversationsListener?.remove()
        conversationsListener = nil

        // Note: We query only by participantIds (single-field index, always available).
        // Filtering by conversationStatus in the query would require a composite index
        // that may not exist. Instead we filter client-side to avoid permission/index errors.
        conversationsListener = db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    dlog("❌ Badge – conversations listener error: \(error.localizedDescription)")
                    // Transient permission errors on startup resolve once the auth token propagates.
                    let nsError = error as NSError
                    if nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7 {
                        if self.badgeConversationsRetryCount < 3 {
                            self.badgeConversationsRetryCount += 1
                            let retryNum = self.badgeConversationsRetryCount
                            let delay = UInt64(retryNum) * 3_000_000_000
                            dlog("⚠️ Badge listener: permission denied — retry \(retryNum)/3 in \(retryNum * 3)s")
                            // Detach immediately so the error callback stops firing while we wait.
                            self.conversationsListener?.remove()
                            self.conversationsListener = nil
                            Task { @MainActor [weak self] in
                                guard let self = self else { return }
                                try? await Task.sleep(nanoseconds: delay)
                                // Bail if stopRealtimeUpdates() was called while we waited
                                // (it resets badgeConversationsRetryCount to 0).
                                guard self.badgeConversationsRetryCount == retryNum else { return }
                                guard let uid = Auth.auth().currentUser?.uid else { return }
                                self.reattachConversationsListener(userId: uid)
                            }
                        } else {
                            // Final failure — leave listener nil to stop the error flood.
                            dlog("🛑 Badge listener: permission denied after 3 retries — check Firestore rules deployment.")
                            self.conversationsListener?.remove()
                            self.conversationsListener = nil
                        }
                    }
                    return
                }
                // Successful read — reset retry counter
                self.badgeConversationsRetryCount = 0
                // Compute unread message count directly from snapshot — avoids
                // stale cached values after a markAsRead write.
                // Filter client-side: only count accepted (or nil/missing) conversations.
                guard let docs = snapshot?.documents else { return }
                let uid = Auth.auth().currentUser?.uid ?? ""
                var msgCount = 0
                for doc in docs {
                    let status = doc.data()["conversationStatus"] as? String
                    guard status == nil || status == "accepted" else { continue }
                    if let counts = doc.data()["unreadCounts"] as? [String: Int],
                       let c = counts[uid] { msgCount += c }
                }
                Task { @MainActor in
                    self.unreadMessages = msgCount
                    // PERF FIX: Mark that the listener has given us an authoritative
                    // message count — subsequent performBadgeUpdate() calls can skip
                    // the expensive calculateUnreadMessages() Firestore scan.
                    self.listenerHasPopulatedMessages = true
                    // Invalidate cache so the combined total is recomputed fresh
                    self.cachedBadgeCount = nil
                    self.cacheTimestamp = nil
                    self.requestBadgeUpdate()
                }
            }
    }

    /// Stop real-time updates and cleanup listeners.
    /// NOTE: badgeConversationsRetryCount is intentionally NOT reset here.
    /// Resetting it on every stop would allow the retry loop to run forever
    /// if stop/start cycles happen faster than the backoff delay (e.g. auth
    /// token refresh during startup). The counter is only reset on a
    /// successful Firestore read or when the user explicitly signs out
    /// (call resetRetryCounters() from the sign-out path if needed).
    func stopRealtimeUpdates() {
        conversationsListener?.remove()
        notificationsListener?.remove()
        serverCountListener?.remove()
        conversationsListener = nil
        notificationsListener = nil
        serverCountListener = nil
        driftRecoveryTask?.cancel()
        driftRecoveryTask = nil
        reconciliationTask?.cancel()
        reconciliationTask = nil
        serverUnseenCount = nil
        driftDetectedAt = nil
        isListening = false
        // PERF FIX: Reset so the next startRealtimeUpdates() session re-queries once on startup
        listenerHasPopulatedMessages = false
        dlog("🛑 Real-time badge listeners stopped")
    }

    /// Reset the permission retry counters. Call this only on explicit sign-out
    /// so a fresh sign-in gets a full 3-retry budget.
    func resetRetryCounters() {
        badgeConversationsRetryCount = 0
        badgeServerCountRetryCount = 0
    }

    // MARK: - V2 Server Count Drift Recovery

    /// Listens to `users/{uid}/notificationState/inbox` for the server-maintained `unseenCount`.
    /// If the local notification count diverges from the server count by >2 for >10 seconds,
    /// the local count is corrected to match the server.
    private func startServerCountListener(userId: String) {
        serverCountListener?.remove()
        serverCountListener = nil

        serverCountListener = db.collection("users")
            .document(userId)
            .collection("notificationState")
            .document("inbox")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    let nsError = error as NSError
                    let isPermissionError = nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7
                    if isPermissionError && self.badgeServerCountRetryCount < 3 {
                        self.badgeServerCountRetryCount += 1
                        let retryNum = self.badgeServerCountRetryCount
                        let delay = UInt64(retryNum) * 3_000_000_000
                        dlog("⚠️ Badge – server count listener: permission denied — retry \(retryNum)/3 in \(retryNum * 3)s")
                        self.serverCountListener?.remove()
                        self.serverCountListener = nil
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            try? await Task.sleep(nanoseconds: delay)
                            guard self.badgeServerCountRetryCount == retryNum else { return }
                            guard let uid = Auth.auth().currentUser?.uid else { return }
                            self.startServerCountListener(userId: uid)
                        }
                    } else if isPermissionError {
                        dlog("🛑 Badge – server count listener: permission denied after 3 retries — drift recovery disabled")
                        self.serverCountListener?.remove()
                        self.serverCountListener = nil
                    } else {
                        dlog("⚠️ Badge – server count listener error: \(error.localizedDescription)")
                    }
                    return
                }
                // Successful read — reset retry counter
                self.badgeServerCountRetryCount = 0
                guard let data = snapshot?.data(),
                      let count = data["unseenCount"] as? Int else { return }

                Task { @MainActor in
                    self.serverUnseenCount = count
                    self.checkForDrift()
                }
            }
    }

    /// Compares local unreadNotifications against serverUnseenCount.
    /// If they diverge by >2, starts a 10-second timer. If still diverged after
    /// the timer, adopts the server count.
    private func checkForDrift() {
        guard let serverCount = serverUnseenCount else { return }

        let drift = abs(unreadNotifications - serverCount)
        if drift > 2 {
            if driftDetectedAt == nil {
                driftDetectedAt = Date()
                dlog("⚠️ Badge drift detected: local=\(unreadNotifications) server=\(serverCount)")

                // Start 10-second timer
                driftRecoveryTask?.cancel()
                driftRecoveryTask = Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self.applyDriftRecovery() }
                }
            }
        } else {
            // Drift resolved naturally
            driftDetectedAt = nil
            driftRecoveryTask?.cancel()
            driftRecoveryTask = nil
        }
    }

    /// Adopts the server count if drift is still present after the grace period.
    private func applyDriftRecovery() {
        guard let serverCount = serverUnseenCount else { return }
        guard let driftStart = driftDetectedAt else { return }

        let elapsed = Date().timeIntervalSince(driftStart)
        let currentDrift = abs(unreadNotifications - serverCount)

        if elapsed >= 10 && currentDrift > 2 {
            dlog("🔄 Badge drift recovery: adopting server count \(serverCount) (was \(unreadNotifications))")
            unreadNotifications = serverCount
            cachedBadgeCount = nil
            cacheTimestamp = nil
            requestBadgeUpdate()
        }

        driftDetectedAt = nil
        driftRecoveryTask = nil
    }

    /// Calls the server-side reconcileNotificationCount callable every 5 minutes
    /// while the app is active, to ensure the server's unseenCount stays accurate.
    private func startPeriodicReconciliation() {
        reconciliationTask?.cancel()
        reconciliationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000) // 5 minutes
                guard !Task.isCancelled else { return }
                await performReconciliation()
            }
        }
    }

    /// Public trigger for an immediate server-count reconciliation.
    /// Call this after bulk operations (e.g. markAllAsRead) that are likely to
    /// leave the server unseenCount stale.
    func triggerReconciliation() {
        Task { await performReconciliation() }
    }

    /// Calls the reconcileNotificationCount Cloud Function.
    private func performReconciliation() async {
        do {
            let callable = Functions.functions().httpsCallable("reconcileNotificationCount")
            let result = try await callable.call([:])
            if let data = result.data as? [String: Any],
               let corrected = data["corrected"] as? Bool,
               corrected {
                let prev = data["previousCount"] as? Int ?? -1
                let actual = data["actualCount"] as? Int ?? -1
                dlog("🔄 Badge reconciliation: corrected server count from \(prev) to \(actual)")
            }
        } catch {
            // Cloud Function may not be deployed yet; NOT_FOUND is expected in that case
            // and is not actionable — log at debug level only so it doesn't pollute production logs.
            let nsError = error as NSError
            let isNotFound = nsError.domain == "com.firebase.functions" && nsError.code == 9
            if !isNotFound {
                dlog("⚠️ Badge reconciliation failed: \(error.localizedDescription)")
            }
        }
    }
}
