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
    @Published var error: NotificationServiceError?  // ✅ Now publicly settable for error dismissal
    @Published var useAINotifications = true
    
    // MARK: - Private Properties
    
    let db = Firestore.firestore()  // Changed from private to internal for extension access
    private var listener: ListenerRegistration?
    private var notificationObserver: NSObjectProtocol?
    private let maxNotifications = 100
    
    // Retry configuration
    private let maxRetries = 3
    private var retryCount = 0
    private var retryTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationObservers()
        loadAIPreference()
        print("✅ NotificationService initialized")
    }
    
    deinit {
        // deinit is nonisolated, so we need to clean up synchronously
        // The listener and tasks will be cleaned up when they're deallocated
        listener?.remove()
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        retryTask?.cancel()
        print("🧹 NotificationService cleaned up")
    }
    
    // MARK: - Cleanup
    
    /// Clean up resources when done with the service
    private func cleanup() {
        stopListening()
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        retryTask?.cancel()
        print("🧹 NotificationService cleaned up")
    }
    
    // MARK: - AI Preferences
    
    private func loadAIPreference() {
        useAINotifications = UserDefaults.standard.bool(forKey: "useAINotifications_v1")
        if useAINotifications {
            print("✅ AI notifications enabled")
        }
    }
    
    /// Toggle AI-powered notification features
    func toggleAINotifications() {
        useAINotifications.toggle()
        UserDefaults.standard.set(useAINotifications, forKey: "useAINotifications_v1")
        print(useAINotifications ? "✅ AI notifications enabled" : "⚠️ AI notifications disabled")
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
        print("🔄 Push notification received, refreshing...")
        // Notifications update automatically via listener
        // Just update badge count
        await updateBadgeCount()
    }
    
    private func updateBadgeCount() async {
        // Delegate to BadgeCountManager for thread-safe, cached updates
        await BadgeCountManager.shared.requestBadgeUpdate()
    }
    
    // MARK: - Start Listening to Notifications
    
    /// Start listening to real-time notifications for the current user
    func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot start listening: No authenticated user")
            error = .notAuthenticated
            return
        }
        
        // Don't start multiple listeners
        if listener != nil {
            print("⚠️ Listener already active")
            return
        }
        
        print("📡 Starting notifications listener for user: \(userId)")
        isLoading = true
        error = nil
        retryCount = 0
        
        // Listen to user's notifications subcollection (created by Cloud Functions)
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
                        print("⚠️ No documents in snapshot")
                        return
                    }
                    
                    await self.processNotifications(documents)
                }
            }
    }
    
    /// Process notification documents from Firestore
    private func processNotifications(_ documents: [QueryDocumentSnapshot]) async {
        var parsedNotifications: [AppNotification] = []
        var parseErrors: [Error] = []
        
        for doc in documents {
            do {
                var notification = try doc.data(as: AppNotification.self)
                notification.id = doc.documentID
                parsedNotifications.append(notification)
            } catch {
                parseErrors.append(error)
                print("⚠️ Error parsing notification \(doc.documentID): \(error.localizedDescription)")
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
        
        let duplicateCount = parsedNotifications.count - deduplicated.count
        if duplicateCount > 0 {
            print("🧹 Removed \(duplicateCount) duplicate notification(s)")
        }
        
        print("✅ Loaded \(deduplicated.count) notifications (\(unreadCount) unread)")
        
        if !parseErrors.isEmpty {
            print("⚠️ Failed to parse \(parseErrors.count) notification(s)")
        }
        
        // Clean up duplicates in background (doesn't block UI)
        if duplicateCount > 0 {
            Task.detached(priority: .background) {
                await self.removeDuplicateFollowNotifications()
            }
        }
    }
    
    /// Handle errors from the Firestore listener
    private func handleListenerError(_ firestoreError: Error) async {
        let nsError = firestoreError as NSError
        
        print("❌ Firestore listener error: \(firestoreError.localizedDescription)")
        print("   Error code: \(nsError.code), domain: \(nsError.domain)")
        
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
        
        print("🔄 Retrying connection in \(delay)s (attempt \(retryCount)/\(maxRetries))")
        
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
        retryTask?.cancel()
        retryTask = nil
        print("🛑 Stopped listening to notifications")
    }
    
    // MARK: - Duplicate Cleanup
    
    /// Deduplicate notifications in-memory (keeps most recent for each actor+type+post combination)
    /// This provides immediate UI deduplication without waiting for Firestore cleanup
    private func deduplicateNotifications(_ notifications: [AppNotification]) -> [AppNotification] {
        var seen: [String: AppNotification] = [:]
        
        for notification in notifications {
            // Create unique key based on type, actor, and post (if applicable)
            let key: String
            if let postId = notification.postId {
                // For post-related notifications, group by actor+type+post
                key = "\(notification.type.rawValue)_\(notification.actorId ?? "unknown")_\(postId)"
            } else {
                // For non-post notifications (like follows), group by actor+type
                key = "\(notification.type.rawValue)_\(notification.actorId ?? "unknown")"
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
            print("⚠️ Cannot cleanup: No authenticated user")
            return
        }
        
        print("🧹 Starting duplicate follow notification cleanup...")
        
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
                    print("🗑️ Marking duplicate notification for deletion from \(actorId)")
                }
            }
            
            // Commit batch delete
            if deletedCount > 0 {
                try await batch.commit()
                print("✅ Cleaned up \(deletedCount) duplicate follow notifications")
            } else {
                print("✅ No duplicate follow notifications found")
            }
            
        } catch {
            print("❌ Failed to cleanup duplicate notifications: \(error.localizedDescription)")
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
            
            try await db.collection("users")
                .document(userId)
                .collection("notifications")
                .document(notificationId)
                .updateData(["read": true])
            
            // Update local state immediately for better UX
            if let index = notifications.firstIndex(where: { $0.id == notificationId }) {
                notifications[index].read = true
                unreadCount = notifications.filter { !$0.read }.count
                await updateBadgeCount()
            }
            
            print("✅ Marked notification as read: \(notificationId)")
        } catch {
            print("❌ Error marking notification as read: \(error.localizedDescription)")
            throw NotificationServiceError.firestoreError(error)
        }
    }
    
    /// Mark all notifications as read
    func markAllAsRead() async throws {
        guard !notifications.isEmpty else {
            print("ℹ️ No notifications to mark as read")
            return
        }
        
        let unreadNotifications = notifications.filter { !$0.read }
        guard !unreadNotifications.isEmpty else {
            print("ℹ️ All notifications already read")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NotificationServiceError.notAuthenticated
        }
        
        let batch = db.batch()
        var batchCount = 0
        
        for notification in unreadNotifications {
            guard let id = notification.id else { continue }
            let ref = db.collection("users")
                .document(userId)
                .collection("notifications")
                .document(id)
            batch.updateData(["read": true], forDocument: ref)
            batchCount += 1
            
            // Firestore batch limit is 500 operations
            if batchCount >= 500 {
                print("⚠️ Reached Firestore batch limit, processing partial batch")
                break
            }
        }
        
        do {
            try await batch.commit()
            
            // Update local state
            for index in notifications.indices where !notifications[index].read {
                notifications[index].read = true
            }
            unreadCount = 0
            await updateBadgeCount()
            
            print("✅ Marked \(batchCount) notifications as read")
        } catch {
            print("❌ Error marking all as read: \(error.localizedDescription)")
            throw NotificationServiceError.firestoreError(error)
        }
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
            
            print("✅ Deleted notification: \(notificationId)")
        } catch {
            print("❌ Error deleting notification: \(error.localizedDescription)")
            throw NotificationServiceError.firestoreError(error)
        }
    }
    
    /// Delete all read notifications
    func deleteAllRead() async throws {
        let readNotifications = notifications.filter { $0.read }
        
        guard !readNotifications.isEmpty else {
            print("ℹ️ No read notifications to delete")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NotificationServiceError.notAuthenticated
        }
        
        let batch = db.batch()
        var batchCount = 0
        
        for notification in readNotifications {
            guard let id = notification.id else { continue }
            let ref = db.collection("users")
                .document(userId)
                .collection("notifications")
                .document(id)
            batch.deleteDocument(ref)
            batchCount += 1
            
            // Firestore batch limit is 500 operations
            if batchCount >= 500 {
                print("⚠️ Reached Firestore batch limit, processing partial batch")
                break
            }
        }
        
        do {
            try await batch.commit()
            
            // Update local state
            notifications.removeAll { $0.read }
            unreadCount = notifications.filter { !$0.read }.count
            await updateBadgeCount()
            
            print("✅ Deleted \(batchCount) read notifications")
        } catch {
            print("❌ Error deleting read notifications: \(error.localizedDescription)")
            throw NotificationServiceError.firestoreError(error)
        }
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
            print("ℹ️ No mentions to notify")
            return
        }
        
        print("📧 Sending \(mentions.count) mention notifications...")
        
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
                "commentText": nil as String?,
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
                print("⚠️ Reached Firestore batch limit")
                break
            }
        }
        
        guard batchCount > 0 else {
            print("ℹ️ No mention notifications to send")
            return
        }
        
        do {
            try await batch.commit()
            print("✅ Sent \(batchCount) mention notifications")
        } catch {
            print("❌ Failed to send mention notifications: \(error.localizedDescription)")
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
            print("ℹ️ No recipients to notify for church note sharing")
            return
        }
        
        print("📧 Sending \(recipientIds.count) church note sharing notifications...")
        
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
                print("⚠️ Reached Firestore batch limit for church note sharing")
                break
            }
        }
        
        guard batchCount > 0 else {
            print("ℹ️ No church note sharing notifications to send")
            return
        }
        
        do {
            try await batch.commit()
            print("✅ Sent \(batchCount) church note sharing notifications")
        } catch {
            print("❌ Failed to send church note sharing notifications: \(error.localizedDescription)")
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
        print("🔄 Manually refreshing notifications...")
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot refresh: No authenticated user")
            error = .notAuthenticated
            return
        }
        
        isLoading = true
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("notifications")
                .order(by: "createdAt", descending: true)
                .limit(to: maxNotifications)
                .getDocuments()
            
            await processNotifications(snapshot.documents)
            retryCount = 0 // Reset retry count on successful manual refresh
            print("✅ Manual refresh complete")
        } catch {
            print("❌ Error refreshing notifications: \(error.localizedDescription)")
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
        
        print("🧹 Starting cleanup of corrupted notifications...")
        
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
                print("⚠️ Found corrupted notification: \(doc.documentID)")
                print("   Error: \(error.localizedDescription)")
                print("   Data: \(doc.data())")
            }
        }
        
        guard !corruptedIds.isEmpty else {
            print("✅ No corrupted notifications found")
            return
        }
        
        // Delete corrupted notifications in batches
        let batch = db.batch()
        var batchCount = 0
        
        for corruptedId in corruptedIds {
            let ref = db.collection("users").document(userId).collection("notifications").document(corruptedId)
            batch.deleteDocument(ref)
            batchCount += 1
            
            if batchCount >= 500 {
                print("⚠️ Reached Firestore batch limit at 500, processing partial batch")
                break
            }
        }
        
        try await batch.commit()
        
        print("✅ Deleted \(batchCount) corrupted notification(s)")
        
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
    let commentText: String?
    var read: Bool
    let createdAt: Timestamp
    
    // ✅ NEW: Smart notification metadata for Instagram-level performance
    var priority: Int?  // 0-100 score for smart sorting
    var groupId: String?  // For grouping similar notifications
    
    // ✅ THREADS-STYLE GROUPING: Multiple actors for aggregated notifications
    var actors: [NotificationActor]?  // List of all users who performed this action
    var actorCount: Int?  // Total number of actors (for "Alex and 5 others")
    let updatedAt: Timestamp?  // Last update time (different from createdAt)
    
    enum CodingKeys: String, CodingKey {
        case userId, type, actorId, actorName, actorUsername, actorProfileImageURL
        case postId, commentText, read, createdAt, priority, groupId
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
        commentText = try? container.decodeIfPresent(String.self, forKey: .commentText)
        priority = try? container.decodeIfPresent(Int.self, forKey: .priority)  // ✅ NEW
        groupId = try? container.decodeIfPresent(String.self, forKey: .groupId)  // ✅ NEW
        
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
        case messageRequestAccepted = "message_request_accepted"  // ✅ NEW: When message request is accepted
        case churchNoteShared = "church_note_shared"  // When someone shares a church note with you
        case unknown = "unknown"
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = NotificationType(rawValue: rawValue) ?? .unknown
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
        case .unknown:
            return "bell.fill"
        }
    }
    
    var color: Color {
        switch type {
        case .follow:
            return .green
        case .amen:
            return .blue
        case .comment:
            return .purple
        case .prayerReminder:
            return .orange
        case .mention:
            return .pink
        case .reply:
            return .indigo
        case .repost:
            return .cyan  // ✅ NEW
        case .prayerAnswered:
            return .green
        case .followRequestAccepted:
            return .green  // ✅ NEW
        case .messageRequestAccepted:
            return .blue  // ✅ NEW
        case .churchNoteShared:
            return .purple
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

