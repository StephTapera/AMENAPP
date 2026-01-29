//
//  NotificationService.swift
//  AMENAPP
//
//  Created by Steph on 1/23/26.
//
//  Real-time notifications from Firestore (created by Cloud Functions)
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()
    
    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0
    @Published var isLoading = false
    @Published var useAINotifications = true  // ✅ Enable/disable AI notifications
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private let aiService = NotificationGenkitService.shared  // ✅ AI integration
    
    private init() {
        setupNotificationObservers()
        loadAIPreference()
    }
    
    // MARK: - AI Preferences
    
    private func loadAIPreference() {
        useAINotifications = UserDefaults.standard.bool(forKey: "useAINotifications_v1") ?? true
    }
    
    func toggleAINotifications() {
        useAINotifications.toggle()
        UserDefaults.standard.set(useAINotifications, forKey: "useAINotifications_v1")
        print(useAINotifications ? "✅ AI notifications enabled" : "⚠️ AI notifications disabled")
    }
    
    // MARK: - Setup Observers
    
    private func setupNotificationObservers() {
        // Listen for push notifications received
        NotificationCenter.default.addObserver(
            forName: Notification.Name("pushNotificationReceived"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            Task { @MainActor in
                // Refresh notifications when push is received
                self.refreshNotifications()
            }
        }
    }
    
    private func refreshNotifications() {
        // Notifications are already updating via real-time listener
        // This just ensures badge count is updated
        PushNotificationManager.shared.updateBadgeCount()
        print("🔄 Notifications refreshed from push")
    }
    
    // MARK: - Start Listening to Notifications
    
    func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ No authenticated user")
            return
        }
        
        print("📡 Starting notifications listener for user: \(userId)")
        isLoading = true
        
        // Listen to notifications collection (created by Cloud Functions!)
        listener = db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to notifications: \(error.localizedDescription)")
                    self.isLoading = false
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.isLoading = false
                    return
                }
                
                self.notifications = documents.compactMap { doc in
                    var notification = try? doc.data(as: AppNotification.self)
                    notification?.id = doc.documentID
                    return notification
                }
                
                self.unreadCount = self.notifications.filter { !$0.read }.count
                self.isLoading = false
                
                print("✅ Loaded \(self.notifications.count) notifications (\(self.unreadCount) unread)")
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
        print("🛑 Stopped listening to notifications")
    }
    
    // MARK: - Mark as Read
    
    func markAsRead(_ notificationId: String) async {
        do {
            try await db.collection("notifications")
                .document(notificationId)
                .updateData(["read": true])
            
            // Update local state
            if let index = notifications.firstIndex(where: { $0.id == notificationId }) {
                notifications[index].read = true
                unreadCount = notifications.filter { !$0.read }.count
            }
            
            print("✅ Marked notification as read: \(notificationId)")
        } catch {
            print("❌ Error marking notification as read: \(error.localizedDescription)")
        }
    }
    
    func markAllAsRead() async {
        let batch = db.batch()
        
        for notification in notifications where !notification.read {
            guard let id = notification.id else { continue }
            let ref = db.collection("notifications").document(id)
            batch.updateData(["read": true], forDocument: ref)
        }
        
        do {
            try await batch.commit()
            
            // Update local state
            for index in notifications.indices {
                notifications[index].read = true
            }
            unreadCount = 0
            
            print("✅ Marked all \(notifications.count) notifications as read")
        } catch {
            print("❌ Error marking all as read: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Delete Notification
    
    func deleteNotification(_ notificationId: String) async {
        do {
            try await db.collection("notifications")
                .document(notificationId)
                .delete()
            
            // Update local state
            notifications.removeAll { $0.id == notificationId }
            unreadCount = notifications.filter { !$0.read }.count
            
            print("✅ Deleted notification: \(notificationId)")
        } catch {
            print("❌ Error deleting notification: \(error.localizedDescription)")
        }
    }
    
    func deleteAllRead() async {
        let batch = db.batch()
        
        for notification in notifications where notification.read {
            guard let id = notification.id else { continue }
            let ref = db.collection("notifications").document(id)
            batch.deleteDocument(ref)
        }
        
        do {
            try await batch.commit()
            
            // Update local state
            notifications.removeAll { $0.read }
            
            print("✅ Deleted all read notifications")
        } catch {
            print("❌ Error deleting read notifications: \(error.localizedDescription)")
        }
    }
}

// MARK: - App Notification Model

struct AppNotification: Identifiable, Codable {
    var id: String?
    let userId: String
    let type: String // "follow", "amen", "comment", "prayer_reminder"
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
    
    var timeAgo: String {
        createdAt.dateValue().timeAgoDisplay()
    }
    
    var actionText: String {
        switch type {
        case "follow":
            return "started following you"
        case "amen":
            return "said Amen to your post"
        case "comment":
            return "commented on your post"
        case "prayer_reminder":
            return "Prayer reminder"
        default:
            return "interacted with you"
        }
    }
    
    var icon: String {
        switch type {
        case "follow":
            return "person.fill.badge.plus"
        case "amen":
            return "hands.sparkles.fill"
        case "comment":
            return "bubble.left.fill"
        case "prayer_reminder":
            return "hands.and.sparkles.fill"
        default:
            return "bell.fill"
        }
    }
    
    var color: Color {
        switch type {
        case "follow":
            return .green
        case "amen":
            return .blue
        case "comment":
            return .purple
        case "prayer_reminder":
            return .orange
        default:
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
}

import SwiftUI
