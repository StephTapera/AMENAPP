//
//  NotificationService.swift
//  AMENAPP
//
//  Created by Steph on 1/23/26.
//
//  Production-ready real-time notifications from Firestore (created by Cloud Functions)
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import SwiftUI

/// Production-ready notification service with comprehensive error handling,
/// real-time updates, and AI integration capabilities.
@MainActor
final class NotificationService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = NotificationService()
    
    // MARK: - Published Properties
    
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var isLoading = false
    // P1-C FIX: error is now private(set) so external callers cannot overwrite a
    // real error with a false one. Use clearError() to dismiss from UI.
    @Published private(set) var error: NotificationServiceError?
    @Published var useAINotifications = true
    
    // MARK: - Private Properties
    
    let db = Firestore.firestore()  // Changed from private to internal for extension access
    private var listener: ListenerRegistration?
    private var topLevelListener: ListenerRegistration?  // Listens to /notifications collection for client-written notifications
    private var notificationObserver: NSObjectProtocol?
    private let maxNotifications = 100
    // Per-source document caches — merged on every update so neither listener clobbers the other
    private var subcollectionDocs: [QueryDocumentSnapshot] = []
    private var topLevelDocs: [QueryDocumentSnapshot] = []
    
    // FIX: Debounce task so both listeners firing within 50ms only trigger one processNotifications pass.
    // Without this, foreground events (both listeners fire simultaneously) cause two full parse runs
    // and two @Published assignments in quick succession, producing a brief stale-UI flash.
    private var mergeDebounceTask: Task<Void, Never>?
    
    // Retry configuration
    private let maxRetries = 3
    private var retryCount = 0
    private var retryTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationObservers()
        loadAIPreference()
    }
    
    deinit {
        // deinit is nonisolated, so we need to clean up synchronously
        // The listener and tasks will be cleaned up when they're deallocated
        listener?.remove()
        topLevelListener?.remove()
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        retryTask?.cancel()
        mergeDebounceTask?.cancel()
    }
    
    // MARK: - Cleanup
    
    /// Clean up resources when done with the service
    private func cleanup() {
        stopListening()
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        retryTask?.cancel()
    }
    
    /// Dismiss the current error from the UI. Use this instead of setting error directly.
    func clearError() {
        error = nil
    }

    /// Set a structured error from view code. Prefer this over direct assignment
    /// now that error is private(set).
    func setError(_ newError: NotificationServiceError) {
        error = newError
    }

    // MARK: - AI Preferences
    
    private func loadAIPreference() {
        useAINotifications = UserDefaults.standard.bool(forKey: "useAINotifications_v1")
    }
    
    /// Toggle AI-powered notification features
    func toggleAINotifications() {
        useAINotifications.toggle()
        UserDefaults.standard.set(useAINotifications, forKey: "useAINotifications_v1")
        dlog(useAINotifications ? "✅ AI notifications enabled" : "⚠️ AI notifications disabled")
    }
    
    // MARK: - Setup Observers
    
    private func setupNotificationObservers() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("pushNotificationReceived"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                await self?.handlePushNotificationReceived()
            }
        }
    }
    
    private func handlePushNotificationReceived() async {
        // Notifications update automatically via listener
        await updateBadgeCount()
    }
    
    private func updateBadgeCount() async {
        // P0 FIX: Use immediateUpdate for user-triggered actions (no debounce)
        // This ensures badge updates instantly when user marks notifications as read
        await BadgeCountManager.shared.immediateUpdate()
    }
    
    // MARK: - Start Listening to Notifications
    
    /// Start listening to real-time notifications for the current user
    func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = .notAuthenticated
            return
        }
        
        // Don't start multiple listeners
        if listener != nil {
            return
        }
        // Only show loading skeleton when we have no cached data yet.
        // If notifications is non-empty we already have a valid data set from a
        // previous listener session; setting isLoading=true here would produce a
        // skeleton flash every time the user re-visits the Notifications tab.
        isLoading = notifications.isEmpty
        error = nil
        retryCount = 0
        
        // Listener 1: user's notifications subcollection (created by Cloud Functions)
        #if DEBUG
        Task { @MainActor in ListenerCounter.shared.attach("notifications-subcollection") }
        #endif
        listener = db.collection("users")
            .document(userId)
            .collection("notifications")
            .order(by: "createdAt", descending: true)
            .limit(to: maxNotifications)
            .addSnapshotListener { [weak self] snapshot, firestoreError in
                guard let self = self else { return }
                
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    if let firestoreError = firestoreError {
                        await self.handleListenerError(firestoreError)
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self.isLoading = false
                        return
                    }
                    
                    // Store this source's latest docs and schedule a debounced merge.
                    // When both listeners fire within 50 ms (common on foreground), only
                    // one processNotifications call is made instead of two.
                    self.subcollectionDocs = documents
                    self.scheduleMerge()
                }
            }
        
        // Listener 2: top-level /notifications collection (written by client-side interactions
        // such as lightbulb/amen reactions — filtered by userId field)
        #if DEBUG
        Task { @MainActor in ListenerCounter.shared.attach("notifications-toplevel") }
        #endif
        topLevelListener = db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: maxNotifications)
            .addSnapshotListener { [weak self] snapshot, firestoreError in
                guard let self = self else { return }
                
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    guard firestoreError == nil, let documents = snapshot?.documents else { return }
                    // Store this source's latest docs and schedule a debounced merge.
                    self.topLevelDocs = documents
                    self.scheduleMerge()
                }
            }
    }
    
    /// Schedule a coalesced merge of both listener caches with a 100 ms debounce.
    /// Cancels any pending merge task so rapid back-to-back listener fires result
    /// in exactly one processNotifications call.
    /// P1-A FIX: Increased from 50 ms to 100 ms. On slow networks (3G/LTE with high
    /// latency) the two listeners can fire 60-90 ms apart, causing a visible stale-UI
    /// flash at 50 ms. 100 ms is still imperceptible to users but wide enough to
    /// absorb typical network jitter without a double render pass.
    private func scheduleMerge() {
        mergeDebounceTask?.cancel()
        mergeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled, let self = self else { return }
            // P0 FIX: Snapshot docs after the debounce window closes, not inline
            // in the closure capture. Any new listener fire during the sleep cancels
            // this task and reschedules, so by the time we reach here both source
            // arrays are stable and we read the latest values atomically on MainActor.
            let docs = self.subcollectionDocs + self.topLevelDocs
            await self.processNotifications(docs)
        }
    }
    
    /// Process notification documents from Firestore
    private func processNotifications(_ documents: [QueryDocumentSnapshot]) async {
        var parsedNotifications: [AppNotification] = []
        var parseErrors: [Error] = []
        var filteredMessageNotifications = 0
        var filteredSelfActions = 0
        var filteredBlockedUsers = 0
        
        // ✅ P0-6 FIX: Get blocked users synchronously from local cache
        let blockedUserIds = BlockService.shared.blockedUsers
        
        for doc in documents {
            do {
                var notification = try doc.data(as: AppNotification.self)
                
                // ✅ P0-13 FIX: Robust message notification filtering with fallback checks.
                // Messages should ONLY drive the Messages badge, not appear in the Notifications feed.
                // P0-B FIX: Also filter .unknown types that originated from a message/conversation
                // document - they get decoded as .unknown when the Cloud Function writes an
                // unrecognised type string, but the raw document still carries a conversationId
                // or a type field that matches one of the message variants.
                let rawType = doc.data()["type"] as? String ?? ""
                let rawNotificationType = doc.data()["notificationType"] as? String ?? ""
                let hasConversationId = doc.data()["conversationId"] != nil
                let isMessageNotification = notification.type == .message ||
                                          notification.type == .messageRequest ||
                                          rawType == "message" ||
                                          rawType == "messageRequest" ||
                                          rawNotificationType == "message" ||
                                          // Catch .unknown documents that are actually message notifications
                                          (notification.type == .unknown && (hasConversationId || rawType.lowercased().contains("message")))
                
                if isMessageNotification {
                    filteredMessageNotifications += 1
                    continue
                }
                
                notification.id = doc.documentID
                
                // ✅ NEW: Apply smart filters
                
                // 1. Self-action suppression
                if NotificationAggregationService.shared.isSelfAction(notification) {
                    filteredSelfActions += 1
                    continue
                }
                
                // ✅ P0-6 FIX: Synchronous block check using local cache
                // Filter out notifications from blocked users BEFORE rendering
                if let actorId = notification.actorId, blockedUserIds.contains(actorId) {
                    filteredBlockedUsers += 1
                    continue
                }
                
                parsedNotifications.append(notification)
            } catch {
                parseErrors.append(error)
                Logger.error("Failed to parse notification \(doc.documentID)", error: error)
                // Auto-delete corrupted/empty notification documents so they don't
                // cause a parse failure on every launch.
                Task.detached(priority: .background) {
                    try? await doc.reference.delete()
                }
            }
        }
        
        // Remove duplicates before updating state
        let deduplicated = self.deduplicateNotifications(parsedNotifications)
        
        // Update state
        self.notifications = deduplicated
        self.unreadCount = deduplicated.filter { !$0.read }.count
        self.isLoading = false
        self.retryCount = 0 // Reset on success
        
        // Update badge
        await updateBadgeCount()
        
        // Clean up duplicates in background (doesn't block UI)
        let duplicateCount = parsedNotifications.count - deduplicated.count
        if duplicateCount > 0 {
            Task.detached(priority: .background) {
                await self.removeDuplicateFollowNotifications()
            }
        }
        
        if !parseErrors.isEmpty {
            Logger.warning("Failed to parse \(parseErrors.count) notifications")
        }
    }
    
    /// Handle errors from the Firestore listener
    private func handleListenerError(_ firestoreError: Error) async {
        let nsError = firestoreError as NSError
        
        dlog("❌ Firestore listener error: \(firestoreError.localizedDescription)")
        dlog("   Error code: \(nsError.code), domain: \(nsError.domain)")
        
        self.isLoading = false
        
        // Determine if we should retry
        let shouldRetry = nsError.domain == "FIRFirestoreErrorDomain" && 
                         (nsError.code == 14 || nsError.code == 7) && // Unavailable or Permission Denied
                         retryCount < maxRetries
        
        if shouldRetry {
            self.error = .networkError(firestoreError)
            await retryConnection()
        } else {
            // Map to appropriate error type
            if nsError.code == 7 {
                self.error = .permissionDenied
            } else {
                self.error = .firestoreError(firestoreError)
            }
        }
    }
    
    /// Retry connection with exponential backoff
    private func retryConnection() async {
        retryCount += 1
        let delay = pow(2.0, Double(retryCount)) // Exponential backoff: 2s, 4s, 8s
        
        dlog("🔄 Retrying connection in \(delay)s (attempt \(retryCount)/\(maxRetries))")
        
        retryTask?.cancel()
        retryTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                stopListening()
                startListening()
            }
        }
    }
    
    /// Stop listening to notifications
    func stopListening() {
        listener?.remove()
        listener = nil
        topLevelListener?.remove()
        topLevelListener = nil
        #if DEBUG
        ListenerCounter.shared.detach("notifications-subcollection")
        ListenerCounter.shared.detach("notifications-toplevel")
        #endif
        retryTask?.cancel()
        retryTask = nil
        mergeDebounceTask?.cancel()
        mergeDebounceTask = nil
        // Clear per-source caches so a fresh startListening() begins from a clean slate
        subcollectionDocs = []
        topLevelDocs = []
        dlog("🛑 Stopped listening to notifications")
    }
    
    // MARK: - Duplicate Cleanup
    
    /// Deduplicate notifications in-memory (keeps most recent for each actor+type+post combination)
    /// This provides immediate UI deduplication without waiting for Firestore cleanup
    private func deduplicateNotifications(_ notifications: [AppNotification]) -> [AppNotification] {
        var seen: [String: AppNotification] = [:]
        
        for notification in notifications {
            // ✅ P0-2: Use idempotency key if available, otherwise generate
            let key: String
            if let idempotencyKey = notification.idempotencyKey {
                // Use server-provided idempotency key (most reliable)
                key = idempotencyKey
            } else {
                // Fallback: generate key from notification properties
                if let postId = notification.postId {
                    // For post-related notifications, group by actor+type+post
                    key = "\(notification.type.rawValue)_\(notification.actorId ?? "unknown")_\(postId)"
                } else {
                    // For non-post notifications (like follows), group by actor+type
                    key = "\(notification.type.rawValue)_\(notification.actorId ?? "unknown")"
                }
            }
            
            // Keep the most recent notification for each unique key
            if let existing = seen[key] {
                // Compare timestamps - keep the newer one
                if notification.createdAt.dateValue() > existing.createdAt.dateValue() {
                    seen[key] = notification
                }
            } else {
                seen[key] = notification
            }
        }
        
        // Return deduplicated list, sorted by creation date (most recent first)
        return seen.values.sorted { $0.createdAt.dateValue() > $1.createdAt.dateValue() }
    }
    
    /// Clean up duplicate follow notifications for the same user
    /// This handles cases where Cloud Functions might have created duplicates
    func removeDuplicateFollowNotifications() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("⚠️ Cannot cleanup: No authenticated user")
            return
        }
        
        dlog("🧹 Starting duplicate follow notification cleanup...")
        
        do {
            // Get all follow notifications from user's subcollection
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("notifications")
                .whereField("type", isEqualTo: "follow")
                .getDocuments()
            
            // Group by actorId
            var notificationsByActor: [String: [QueryDocumentSnapshot]] = [:]
            
            for doc in snapshot.documents {
                guard let actorId = doc.data()["actorId"] as? String else { continue }
                notificationsByActor[actorId, default: []].append(doc)
            }
            
            // For each actor with multiple notifications, keep only the most recent
            var deletedCount = 0
            let batch = db.batch()
            
            for (actorId, docs) in notificationsByActor where docs.count > 1 {
                // Sort by createdAt (most recent first)
                let sortedDocs = docs.sorted { doc1, doc2 in
                    let timestamp1 = (doc1.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                    let timestamp2 = (doc2.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                    return timestamp1 > timestamp2
                }
                
                // Delete all except the most recent
                for doc in sortedDocs.dropFirst() {
                    batch.deleteDocument(doc.reference)
                    deletedCount += 1
                    dlog("🗑️ Marking duplicate notification for deletion from \(actorId)")
                }
            }
            
            // Commit batch delete
            if deletedCount > 0 {
                try await batch.commit()
                dlog("✅ Cleaned up \(deletedCount) duplicate follow notifications")
            } else {
                dlog("✅ No duplicate follow notifications found")
            }
            
        } catch {
            dlog("❌ Failed to cleanup duplicate notifications: \(error.localizedDescription)")
            // Don't throw - this is a best-effort cleanup
        }
    }
    
    // MARK: - Mark as Read
    
    /// Mark a single notification as read
    /// - Parameter notificationId: The ID of the notification to mark as read
    func markAsRead(_ notificationId: String) async throws {
        guard !notificationId.isEmpty else {
            throw NotificationServiceError.invalidInput("Invalid notification ID")
        }
        
        do {
            guard let userId = Auth.auth().currentUser?.uid else {
                throw NotificationServiceError.notAuthenticated
            }
            
            // Use setData(merge: true) instead of updateData so this succeeds even
            // when the document doesn't exist yet (e.g. repost notifications created
            // by a Cloud Function that hasn't fully committed on the client yet).
            try await db.collection("users")
                .document(userId)
                .collection("notifications")
                .document(notificationId)
                .setData(["read": true], merge: true)
            
            // Update local state immediately for better UX
            if let index = notifications.firstIndex(where: { $0.id == notificationId }) {
                notifications[index].read = true
                unreadCount = notifications.filter { !$0.read }.count
                await updateBadgeCount()
            }
            
            dlog("✅ Marked notification as read: \(notificationId)")
        } catch let error as NSError {
            dlog("❌ Error marking notification as read: \(error.localizedDescription)")
            throw NotificationServiceError.firestoreError(error)
        }
    }
    
    /// Mark all notifications as read
    func markAllAsRead() async throws {
        guard !notifications.isEmpty else {
            dlog("ℹ️ No notifications to mark as read")
            return
        }
        
        let unreadNotifications = notifications.filter { !$0.read }
        guard !unreadNotifications.isEmpty else {
            dlog("ℹ️ All notifications already read")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NotificationServiceError.notAuthenticated
        }
        
        // FIX: Process ALL unread notifications in 500-document Firestore batches.
        // Previously the code would silently stop after the first 500 items, leaving
        // the remainder unread for high-engagement users.
        let chunkSize = 499  // stay under the 500-operation Firestore limit
        let chunks = stride(from: 0, to: unreadNotifications.count, by: chunkSize).map {
            Array(unreadNotifications[$0..<min($0 + chunkSize, unreadNotifications.count)])
        }
        var totalCommitted = 0
        
        for chunk in chunks {
            let batch = db.batch()
            for notification in chunk {
                guard let id = notification.id else { continue }
                let ref = db.collection("users")
                    .document(userId)
                    .collection("notifications")
                    .document(id)
                batch.setData(["read": true], forDocument: ref, merge: true)
            }
            try await batch.commit()
            totalCommitted += chunk.count
        }
        
        // Update local state after all batches committed
        for index in notifications.indices where !notifications[index].read {
            notifications[index].read = true
        }
        unreadCount = 0
        await updateBadgeCount()
        
        dlog("✅ Marked \(totalCommitted) notifications as read")
    }
    
    // MARK: - Delete Notification
    
    /// Delete a single notification
    /// - Parameter notificationId: The ID of the notification to delete
    func deleteNotification(_ notificationId: String) async throws {
        guard !notificationId.isEmpty else {
            throw NotificationServiceError.invalidInput("Invalid notification ID")
        }
        
        do {
            guard let userId = Auth.auth().currentUser?.uid else {
                throw NotificationServiceError.notAuthenticated
            }
            
            try await db.collection("users")
                .document(userId)
                .collection("notifications")
                .document(notificationId)
                .delete()
            
            // Update local state
            notifications.removeAll { $0.id == notificationId }
            unreadCount = notifications.filter { !$0.read }.count
            await updateBadgeCount()
            
            dlog("✅ Deleted notification: \(notificationId)")
        } catch {
            dlog("❌ Error deleting notification: \(error.localizedDescription)")
            throw NotificationServiceError.firestoreError(error)
        }
    }
    
    /// Delete all read notifications — processes in 499-operation Firestore batches
    /// to handle high-engagement users without silently dropping items.
    func deleteAllRead() async throws {
        let readNotifications = notifications.filter { $0.read }
        
        guard !readNotifications.isEmpty else {
            dlog("ℹ️ No read notifications to delete")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NotificationServiceError.notAuthenticated
        }

        let chunkSize = 499  // stay under the 500-operation Firestore limit
        let chunks = stride(from: 0, to: readNotifications.count, by: chunkSize).map {
            Array(readNotifications[$0..<min($0 + chunkSize, readNotifications.count)])
        }
        var totalDeleted = 0

        for chunk in chunks {
            let batch = db.batch()
            for notification in chunk {
                guard let id = notification.id else { continue }
                let ref = db.collection("users")
                    .document(userId)
                    .collection("notifications")
                    .document(id)
                batch.deleteDocument(ref)
                totalDeleted += 1
            }
            do {
                try await batch.commit()
            } catch {
                dlog("❌ Error deleting read notifications batch: \(error.localizedDescription)")
                throw NotificationServiceError.firestoreError(error)
            }
        }

        // Update local state after all batches committed
        notifications.removeAll { $0.read }
        unreadCount = notifications.filter { !$0.read }.count
        await updateBadgeCount()

        dlog("✅ Deleted \(totalDeleted) read notifications")
    }
    
    // MARK: - Mention Notifications
    
    /// Send notifications to users who were mentioned in a post or comment
    /// - Parameters:
    ///   - mentions: Array of mentioned users
    ///   - actorId: ID of user who created the post/comment
    ///   - actorName: Name of user who created the post/comment
    ///   - postId: ID of the post (required)
    ///   - contentType: Either "post" or "comment"
    func sendMentionNotifications(
        mentions: [MentionedUser],
        actorId: String,
        actorName: String,
        actorUsername: String?,
        postId: String,
        contentType: String
    ) async {
        guard !mentions.isEmpty else {
            dlog("ℹ️ No mentions to notify")
            return
        }
        
        dlog("📧 Sending \(mentions.count) mention notifications...")
        
        let batch = db.batch()
        var batchCount = 0
        
        for mention in mentions {
            // Don't notify yourself
            guard mention.userId != actorId else { continue }
            
            let notificationData: [String: Any] = [
                "userId": mention.userId,
                "type": "mention",
                "actorId": actorId,
                "actorName": actorName,
                "actorUsername": actorUsername ?? "",
                "postId": postId,
                "commentText": nil as String? as Any,
                "read": false,
                "createdAt": Timestamp(date: Date())
            ]
            
            let notificationRef = db.collection("users")
                .document(mention.userId)
                .collection("notifications")
                .document()
            
            batch.setData(notificationData, forDocument: notificationRef)
            batchCount += 1
            
            // Firestore batch limit is 500 operations
            if batchCount >= 500 {
                dlog("⚠️ Reached Firestore batch limit")
                break
            }
        }
        
        guard batchCount > 0 else {
            dlog("ℹ️ No mention notifications to send")
            return
        }
        
        do {
            try await batch.commit()
            dlog("✅ Sent \(batchCount) mention notifications")
        } catch {
            dlog("❌ Failed to send mention notifications: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Church Note Sharing Notifications
    
    /// Send notifications to users when a church note is shared with them
    /// - Parameters:
    ///   - noteId: ID of the shared church note
    ///   - noteTitle: Title of the church note
    ///   - recipientIds: Array of user IDs to notify
    ///   - sharerId: ID of user who shared the note
    ///   - sharerName: Name of user who shared the note
    ///   - sharerUsername: Username of user who shared the note
    func sendChurchNoteSharedNotifications(
        noteId: String,
        noteTitle: String,
        recipientIds: [String],
        sharerId: String,
        sharerName: String,
        sharerUsername: String?
    ) async {
        guard !recipientIds.isEmpty else {
            dlog("ℹ️ No recipients to notify for church note sharing")
            return
        }
        
        dlog("📧 Sending \(recipientIds.count) church note sharing notifications...")
        
        let batch = db.batch()
        var batchCount = 0
        
        for recipientId in recipientIds {
            // Don't notify yourself
            guard recipientId != sharerId else { continue }
            
            let notificationData: [String: Any] = [
                "userId": recipientId,
                "type": "church_note_shared",
                "actorId": sharerId,
                "actorName": sharerName,
                "actorUsername": sharerUsername ?? "",
                "postId": noteId,  // Using postId field for noteId
                "commentText": noteTitle,  // Using commentText field for note title
                "read": false,
                "createdAt": Timestamp(date: Date())
            ]
            
            let notificationRef = db.collection("users")
                .document(recipientId)
                .collection("notifications")
                .document()
            
            batch.setData(notificationData, forDocument: notificationRef)
            batchCount += 1
            
            // Firestore batch limit is 500 operations
            if batchCount >= 500 {
                dlog("⚠️ Reached Firestore batch limit for church note sharing")
                break
            }
        }
        
        guard batchCount > 0 else {
            dlog("ℹ️ No church note sharing notifications to send")
            return
        }
        
        do {
            try await batch.commit()
            dlog("✅ Sent \(batchCount) church note sharing notifications")
        } catch {
            dlog("❌ Failed to send church note sharing notifications: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods for Extensions
    
    /// Remove notifications from local array (used by extensions)
    /// - Parameter predicate: A closure that returns true for notifications to remove
    func removeNotifications(where predicate: (AppNotification) -> Bool) {
        notifications.removeAll(where: predicate)
        unreadCount = notifications.filter { !$0.read }.count
    }
    
    // MARK: - Refresh
    
    /// Manually refresh notifications (useful for pull-to-refresh)
    func refresh() async {
        dlog("🔄 Manually refreshing notifications...")
        
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("⚠️ Cannot refresh: No authenticated user")
            error = .notAuthenticated
            return
        }
        
        // Only show loading skeleton when we have no cached data yet.
        // If we already have notifications, the user sees live content while
        // we fetch fresh data in the background — no skeleton flash on pop/pull.
        isLoading = notifications.isEmpty

        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("notifications")
                .order(by: "createdAt", descending: true)
                .limit(to: maxNotifications)
                .getDocuments()

            // Clear per-source caches before processing fresh data so stale
            // topLevelDocs don't resurface on the next listener merge.
            subcollectionDocs = snapshot.documents
            topLevelDocs = []
            await processNotifications(subcollectionDocs)
            retryCount = 0 // Reset retry count on successful manual refresh
            dlog("✅ Manual refresh complete")
        } catch {
            dlog("❌ Error refreshing notifications: \(error.localizedDescription)")
            self.error = .firestoreError(error)
            isLoading = false
        }
    }
    
    // MARK: - Cleanup Corrupted Notifications
    
    /// Delete corrupted notifications that can't be parsed
    /// This is useful when you have old notifications with missing required fields
    func cleanupCorruptedNotifications() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NotificationServiceError.notAuthenticated
        }
        
        dlog("🧹 Starting cleanup of corrupted notifications...")
        
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("notifications")
            .getDocuments()
        
        var corruptedIds: [String] = []
        
        for doc in snapshot.documents {
            do {
                // Try to decode the notification
                _ = try doc.data(as: AppNotification.self)
            } catch {
                // If it fails, add to corrupted list
                corruptedIds.append(doc.documentID)
                dlog("⚠️ Found corrupted notification: \(doc.documentID)")
                dlog("   Error: \(error.localizedDescription)")
                dlog("   Data: \(doc.data())")
            }
        }
        
        guard !corruptedIds.isEmpty else {
            dlog("✅ No corrupted notifications found")
            return
        }
        
        // Delete corrupted notifications in 499-operation Firestore batches
        let chunkSize = 499
        let chunks = stride(from: 0, to: corruptedIds.count, by: chunkSize).map {
            Array(corruptedIds[$0..<min($0 + chunkSize, corruptedIds.count)])
        }
        var totalDeleted = 0

        for chunk in chunks {
            let batch = db.batch()
            for corruptedId in chunk {
                let ref = db.collection("users").document(userId).collection("notifications").document(corruptedId)
                batch.deleteDocument(ref)
                totalDeleted += 1
            }
            try await batch.commit()
        }

        dlog("✅ Deleted \(totalDeleted) corrupted notification(s)")
        
        // Refresh notifications after cleanup
        await refresh()
    }
}

// MARK: - Notification Service Error

enum NotificationServiceError: LocalizedError {
    case notAuthenticated
    case permissionDenied
    case networkError(Error)
    case firestoreError(Error)
    case invalidInput(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to access notifications"
        case .permissionDenied:
            return "You don't have permission to access these notifications"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .firestoreError(let error):
            return "Database error: \(error.localizedDescription)"
        case .invalidInput(let message):
            return message
        }
    }
}

// MARK: - App Notification Model

// MARK: - Notification Actor (for Threads-style grouping)

struct NotificationActor: Codable, Hashable {
    let id: String
    let name: String
    let username: String
    let profileImageURL: String?
}

// MARK: - App Notification

struct AppNotification: Identifiable, Codable, Hashable {
    var id: String?
    let userId: String
    let type: NotificationType
    let actorId: String?
    let actorName: String?
    let actorUsername: String?
    let actorProfileImageURL: String?  // ✅ NEW: Profile photo for fast display
    let postId: String?
    let commentId: String?      // For scrolling to a specific comment
    let conversationId: String? // For navigating to a specific conversation
    let prayerId: String?       // For navigating to a specific prayer
    let noteId: String?         // For navigating to a specific church note
    let commentText: String?
    var read: Bool
    let createdAt: Timestamp
    
    // ✅ NEW: Smart notification metadata for Instagram-level performance
    var priority: Int?  // 0-100 score for smart sorting
    var groupId: String?  // For grouping similar notifications
    
    // ✅ P0-2: Idempotency key to prevent duplicate notifications
    let idempotencyKey: String?  // Deterministic key: "type_actorId_targetId"
    
    // ✅ THREADS-STYLE GROUPING: Multiple actors for aggregated notifications
    var actors: [NotificationActor]?  // List of all users who performed this action
    var actorCount: Int?  // Total number of actors (for "Alex and 5 others")
    let updatedAt: Timestamp?  // Last update time (different from createdAt)
    
    enum CodingKeys: String, CodingKey {
        case userId, type, actorId, actorName, actorUsername, actorProfileImageURL
        case postId, commentId, conversationId, prayerId, noteId, commentText, read, createdAt, priority, groupId, idempotencyKey
        case actors, actorCount, updatedAt
    }
    
    // MARK: - Custom Decoding
    
    /// Custom decoder that gracefully handles missing optional fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields - will throw if missing
        userId = try container.decode(String.self, forKey: .userId)
        type = try container.decode(NotificationType.self, forKey: .type)
        read = try container.decodeIfPresent(Bool.self, forKey: .read) ?? false
        createdAt = try container.decode(Timestamp.self, forKey: .createdAt)
        
        // Optional fields - return nil if missing or invalid
        actorId = try? container.decodeIfPresent(String.self, forKey: .actorId)
        actorName = try? container.decodeIfPresent(String.self, forKey: .actorName)
        actorUsername = try? container.decodeIfPresent(String.self, forKey: .actorUsername)
        actorProfileImageURL = try? container.decodeIfPresent(String.self, forKey: .actorProfileImageURL)  // ✅ NEW
        postId = try? container.decodeIfPresent(String.self, forKey: .postId)
        commentId = try? container.decodeIfPresent(String.self, forKey: .commentId)
        conversationId = try? container.decodeIfPresent(String.self, forKey: .conversationId)
        prayerId = try? container.decodeIfPresent(String.self, forKey: .prayerId)
        noteId = try? container.decodeIfPresent(String.self, forKey: .noteId)
        commentText = try? container.decodeIfPresent(String.self, forKey: .commentText)
        priority = try? container.decodeIfPresent(Int.self, forKey: .priority)  // ✅ NEW
        groupId = try? container.decodeIfPresent(String.self, forKey: .groupId)  // ✅ NEW
        idempotencyKey = try? container.decodeIfPresent(String.self, forKey: .idempotencyKey)  // ✅ P0-2
        
        // Threads-style grouping fields
        actors = try? container.decodeIfPresent([NotificationActor].self, forKey: .actors)
        actorCount = try? container.decodeIfPresent(Int.self, forKey: .actorCount)
        updatedAt = try? container.decodeIfPresent(Timestamp.self, forKey: .updatedAt)
    }
    
    // MARK: - Notification Type
    
    enum NotificationType: String, Codable {
        case follow = "follow"
        case amen = "amen"
        case comment = "comment"
        case prayerReminder = "prayer_reminder"
        case mention = "mention"
        case reply = "reply"
        case repost = "repost"  // ✅ NEW: When someone reposts your content
        case prayerAnswered = "prayer_answered"
        case followRequestAccepted = "follow_request_accepted"  // ✅ NEW: When follow request is accepted
        case message = "message"  // ✅ P0-1: Message notifications (should be filtered from feed)
        case messageRequest = "message_request"  // ✅ P0-1: Message request notifications (should be filtered from feed)
        case messageRequestAccepted = "message_request_accepted"  // ✅ NEW: When message request is accepted
        case churchNoteShared = "church_note_shared"  // When someone shares a church note with you
        case unknown = "unknown"
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = NotificationType(rawValue: rawValue) ?? .unknown
        }

        /// SF Symbol for the action badge overlay on avatars (Threads-style).
        var iconName: String {
            switch self {
            case .follow, .followRequestAccepted: return "person.badge.plus"
            case .amen:                           return "hands.sparkles.fill"
            case .comment, .reply:                return "bubble.fill"
            case .mention:                        return "at"
            case .repost:                         return "repeat"
            case .prayerReminder, .prayerAnswered: return "hands.sparkles"
            case .churchNoteShared:               return "book.fill"
            case .message, .messageRequest, .messageRequestAccepted: return "envelope.fill"
            case .unknown:                        return "bell.fill"
            }
        }

        /// Accent color for the icon badge (Threads-style).
        var iconColor: Color {
            switch self {
            case .follow, .followRequestAccepted: return .purple
            case .amen:                           return Color(red: 1.0, green: 0.4, blue: 0.5) // pink
            case .comment, .reply:                return .blue
            case .mention:                        return .orange
            case .repost:                         return .green
            case .prayerReminder, .prayerAnswered: return .purple
            case .churchNoteShared:               return .orange
            case .message, .messageRequest, .messageRequestAccepted: return .blue
            case .unknown:                        return .secondary
            }
        }

        /// Filter category for tab filtering.
        var filterCategory: String {
            switch self {
            case .follow, .followRequestAccepted: return "follows"
            case .comment, .reply, .repost:       return "conversations"
            case .mention:                        return "mentions"
            default:                              return "all"
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var timeAgo: String {
        // For grouped notifications, use updatedAt (most recent activity)
        let date: Date
        if let updatedAt = updatedAt {
            date = updatedAt.dateValue()
        } else {
            date = createdAt.dateValue()
        }
        return timeAgoString(from: date)
    }
    
    private func timeAgoString(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .weekOfYear, .day, .hour, .minute, .second], from: date, to: now)
        
        if let years = components.year, years > 0 {
            return years == 1 ? "1y" : "\(years)y"
        }
        
        if let months = components.month, months > 0 {
            return months == 1 ? "1mo" : "\(months)mo"
        }
        
        if let weeks = components.weekOfYear, weeks > 0 {
            return weeks == 1 ? "1w" : "\(weeks)w"
        }
        
        if let days = components.day, days > 0 {
            return days == 1 ? "1d" : "\(days)d"
        }
        
        if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1h" : "\(hours)h"
        }
        
        if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1m" : "\(minutes)m"
        }
        
        if let seconds = components.second, seconds > 0 {
            return seconds <= 5 ? "now" : "\(seconds)s"
        }
        
        return "now"
    }
    
    var actionText: String {
        switch type {
        case .follow:
            return "started following you"
        case .amen:
            return "said Amen to your post"
        case .comment:
            return "commented on your post"
        case .prayerReminder:
            return "Prayer reminder"
        case .mention:
            return "mentioned you in a post"
        case .reply:
            return "replied to your comment"
        case .repost:
            return "reposted your content"  // ✅ NEW
        case .prayerAnswered:
            return "marked your prayer as answered"
        case .followRequestAccepted:
            return "accepted your follow request"  // ✅ NEW
        case .messageRequestAccepted:
            return "accepted your message request"  // ✅ NEW
        case .churchNoteShared:
            return "shared a church note with you"
        case .message:
            return "sent you a message"  // ✅ P0-1: Filtered from feed
        case .messageRequest:
            return "sent you a message request"  // ✅ P0-1: Filtered from feed
        case .unknown:
            return "interacted with you"
        }
    }
    
    var icon: String {
        switch type {
        case .follow:
            return "person.fill.badge.plus"
        case .amen:
            return "hands.sparkles.fill"
        case .comment:
            return "bubble.left.fill"
        case .prayerReminder:
            return "bell.badge.fill"
        case .mention:
            return "at.badge.plus"
        case .reply:
            return "arrowshape.turn.up.left.fill"
        case .repost:
            return "arrow.2.squarepath"  // ✅ NEW
        case .prayerAnswered:
            return "checkmark.seal.fill"
        case .followRequestAccepted:
            return "person.fill.checkmark"  // ✅ NEW
        case .messageRequestAccepted:
            return "message.fill.badge.checkmark"  // ✅ NEW
        case .churchNoteShared:
            return "note.text.badge.plus"
        case .message:
            return "message.fill"  // ✅ P0-1: Filtered from feed
        case .messageRequest:
            return "message.badge"  // ✅ P0-1: Filtered from feed
        case .unknown:
            return "bell.fill"
        }
    }
    
    var color: Color {
        switch type {
        case .follow:
            return .purple
        case .amen:
            return Color(red: 1.0, green: 0.4, blue: 0.5) // pink
        case .comment:
            return .blue
        case .prayerReminder:
            return .purple
        case .mention:
            return .orange
        case .reply:
            return .blue
        case .repost:
            return .green
        case .prayerAnswered:
            return .green
        case .followRequestAccepted:
            return .green  // ✅ NEW
        case .messageRequestAccepted:
            return .blue  // ✅ NEW
        case .churchNoteShared:
            return .purple
        case .message:
            return .blue  // ✅ P0-1: Filtered from feed
        case .messageRequest:
            return .teal  // ✅ P0-1: Filtered from feed
        case .unknown:
            return .gray
        }
    }
    
    var timeCategory: String {
        let calendar = Calendar.current
        let now = Date()
        let date = createdAt.dateValue()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return "This Week"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return "This Month"
        } else {
            return "Earlier"
        }
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AppNotification, rhs: AppNotification) -> Bool {
        lhs.id == rhs.id
    }
}

