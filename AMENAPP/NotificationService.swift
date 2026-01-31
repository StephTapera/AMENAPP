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
    @Published private(set) var error: NotificationServiceError?
    @Published var useAINotifications = true
    
    // MARK: - Private Properties
    
    private let db = Firestore.firestore()
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
        // Update app badge with unread count
        #if !targetEnvironment(simulator)
        await UIApplication.shared.applicationIconBadgeNumber = unreadCount
        #endif
        print("📛 Badge count updated: \(unreadCount)")
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
        
        // Listen to notifications collection (created by Cloud Functions)
        listener = db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
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
        
        // Update state
        self.notifications = parsedNotifications
        self.unreadCount = parsedNotifications.filter { !$0.read }.count
        self.isLoading = false
        self.retryCount = 0 // Reset on success
        
        // Update badge
        await updateBadgeCount()
        
        print("✅ Loaded \(parsedNotifications.count) notifications (\(unreadCount) unread)")
        
        if !parseErrors.isEmpty {
            print("⚠️ Failed to parse \(parseErrors.count) notification(s)")
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
    
    // MARK: - Mark as Read
    
    /// Mark a single notification as read
    /// - Parameter notificationId: The ID of the notification to mark as read
    func markAsRead(_ notificationId: String) async throws {
        guard !notificationId.isEmpty else {
            throw NotificationServiceError.invalidInput("Invalid notification ID")
        }
        
        do {
            try await db.collection("notifications")
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
        
        let batch = db.batch()
        var batchCount = 0
        
        for notification in unreadNotifications {
            guard let id = notification.id else { continue }
            let ref = db.collection("notifications").document(id)
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
            try await db.collection("notifications")
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
        
        let batch = db.batch()
        var batchCount = 0
        
        for notification in readNotifications {
            guard let id = notification.id else { continue }
            let ref = db.collection("notifications").document(id)
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
            let snapshot = try await db.collection("notifications")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: maxNotifications)
                .getDocuments()
            
            await processNotifications(snapshot.documents)
            print("✅ Manual refresh complete")
        } catch {
            print("❌ Error refreshing notifications: \(error.localizedDescription)")
            self.error = .firestoreError(error)
            isLoading = false
        }
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

struct AppNotification: Identifiable, Codable, Hashable {
    var id: String?
    let userId: String
    let type: NotificationType
    let actorId: String?
    let actorName: String?
    let actorUsername: String?
    let postId: String?
    let commentText: String?
    var read: Bool
    let createdAt: Timestamp
    
    enum CodingKeys: String, CodingKey {
        case userId, type, actorId, actorName, actorUsername, postId, commentText, read, createdAt
    }
    
    // MARK: - Notification Type
    
    enum NotificationType: String, Codable {
        case follow = "follow"
        case amen = "amen"
        case comment = "comment"
        case prayerReminder = "prayer_reminder"
        case mention = "mention"
        case reply = "reply"
        case prayerAnswered = "prayer_answered"
        case unknown = "unknown"
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = NotificationType(rawValue: rawValue) ?? .unknown
        }
    }
    
    // MARK: - Computed Properties
    
    var timeAgo: String {
        let date: Date = createdAt.dateValue()
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
        case .prayerAnswered:
            return "marked your prayer as answered"
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
        case .prayerAnswered:
            return "checkmark.seal.fill"
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
        case .prayerAnswered:
            return .green
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

