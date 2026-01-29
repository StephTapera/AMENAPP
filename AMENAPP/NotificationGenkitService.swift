//
//  NotificationGenkitService.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/23/26.
//
//  AI-powered notification enhancement using Genkit
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

// MARK: - Notification Genkit Service

@MainActor
class NotificationGenkitService: ObservableObject {
    static let shared = NotificationGenkitService()
    
    @Published var isProcessing = false
    @Published var lastError: Error?
    
    private let genkitEndpoint: String
    private let db = Firestore.firestore()
    
    init() {
        // Configure your Genkit endpoint
        if let endpoint = Bundle.main.object(forInfoDictionaryKey: "GENKIT_ENDPOINT") as? String {
            self.genkitEndpoint = endpoint
        } else {
            self.genkitEndpoint = "http://localhost:3400"
            print("⚠️ Using default Genkit endpoint for notifications: \(self.genkitEndpoint)")
        }
        
        print("✅ NotificationGenkitService initialized")
    }
    
    // MARK: - Smart Notification Generation
    
    /// Generate personalized notification text using AI
    func generateSmartNotification(
        eventType: NotificationEventType,
        senderName: String,
        senderProfile: NotificationUserProfile?,
        recipientId: String,
        context: String,
        metadata: [String: Any] = [:]
    ) async throws -> SmartNotification {
        
        isProcessing = true
        defer { isProcessing = false }
        
        print("🤖 Generating smart notification for: \(eventType.rawValue)")
        
        // Get recipient interests for personalization
        let recipientInterests = try await fetchUserInterests(userId: recipientId)
        
        // Get shared interests if available
        var sharedInterests: [String] = []
        if let senderProfile = senderProfile {
            sharedInterests = recipientInterests.filter { interest in
                senderProfile.interests.contains(interest)
            }
        }
        
        // Call Genkit to generate personalized notification
        let response = try await callGenkitFlow(
            flowName: "generateNotificationText",
            input: [
                "eventType": eventType.rawValue,
                "senderName": senderName,
                "context": context,
                "recipientInterests": recipientInterests,
                "sharedInterests": sharedInterests,
                "metadata": metadata
            ]
        )
        
        guard let title = response["title"] as? String,
              let body = response["body"] as? String,
              let priorityStr = response["priority"] as? String,
              let category = response["category"] as? String else {
            throw NotificationError.invalidResponse
        }
        
        let priority = NotificationPriority(rawValue: priorityStr) ?? .medium
        
        print("✅ Smart notification generated:")
        print("   Title: \(title)")
        print("   Body: \(body)")
        print("   Priority: \(priority.rawValue)")
        
        return SmartNotification(
            title: title,
            body: body,
            priority: priority,
            category: category,
            eventType: eventType
        )
    }
    
    // MARK: - Notification Summarization
    
    /// Summarize multiple notifications into a single digest
    func summarizeNotifications(
        notifications: [PendingNotification],
        maxLength: Int = 100
    ) async throws -> NotificationSummary {
        
        guard !notifications.isEmpty else {
            throw NotificationError.noNotifications
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        print("📊 Summarizing \(notifications.count) notifications...")
        
        let notificationData = notifications.map { notif in
            [
                "type": notif.type,
                "sender": notif.senderName,
                "message": notif.message,
                "timestamp": notif.timestamp.timeIntervalSince1970
            ] as [String: Any]
        }
        
        let response = try await callGenkitFlow(
            flowName: "summarizeNotifications",
            input: [
                "notifications": notificationData,
                "maxLength": maxLength
            ]
        )
        
        guard let summary = response["summary"] as? String,
              let count = response["count"] as? Int,
              let topPriority = response["topPriority"] as? String else {
            throw NotificationError.invalidResponse
        }
        
        print("✅ Summary generated: \(summary)")
        
        return NotificationSummary(
            summary: summary,
            count: count,
            topPriority: topPriority,
            notificationIds: notifications.map { $0.id }
        )
    }
    
    // MARK: - Smart Timing Optimization
    
    /// Determine optimal time to send notification
    func optimizeTiming(
        for userId: String,
        notificationType: NotificationEventType,
        priority: NotificationPriority
    ) async throws -> TimingRecommendation {
        
        print("⏰ Optimizing notification timing for user: \(userId)")
        
        // Fetch user's activity patterns
        let activityPatterns = try await fetchUserActivityPatterns(userId: userId)
        let userTimezone = try await fetchUserTimezone(userId: userId)
        
        // For high priority, always send immediately
        if priority == .high {
            return TimingRecommendation(
                sendImmediately: true,
                delayMinutes: 0,
                reasoning: "High priority notification - send immediately"
            )
        }
        
        let response = try await callGenkitFlow(
            flowName: "optimizeNotificationTiming",
            input: [
                "userId": userId,
                "notificationType": notificationType.rawValue,
                "priority": priority.rawValue,
                "userTimezone": userTimezone,
                "activityPatterns": activityPatterns.map { pattern in
                    ["hour": pattern.hour, "activeCount": pattern.activeCount]
                },
                "currentHour": Calendar.current.component(.hour, from: Date())
            ]
        )
        
        guard let sendImmediately = response["sendImmediately"] as? Bool,
              let delayMinutes = response["delayMinutes"] as? Int,
              let reasoning = response["reasoning"] as? String else {
            throw NotificationError.invalidResponse
        }
        
        print("✅ Timing optimized: \(sendImmediately ? "Send now" : "Delay \(delayMinutes) min")")
        print("   Reasoning: \(reasoning)")
        
        return TimingRecommendation(
            sendImmediately: sendImmediately,
            delayMinutes: delayMinutes,
            reasoning: reasoning
        )
    }
    
    // MARK: - Send Smart Notification
    
    /// Complete flow: Generate AI notification and send it
    func sendSmartNotification(
        eventType: NotificationEventType,
        senderName: String,
        senderProfile: NotificationUserProfile?,
        recipientId: String,
        context: String,
        metadata: [String: Any] = [:],
        customData: [String: Any] = [:]
    ) async throws {
        
        // Step 1: Generate smart notification text
        let smartNotif = try await generateSmartNotification(
            eventType: eventType,
            senderName: senderName,
            senderProfile: senderProfile,
            recipientId: recipientId,
            context: context,
            metadata: metadata
        )
        
        // Step 2: Check timing optimization
        let timing = try await optimizeTiming(
            for: recipientId,
            notificationType: eventType,
            priority: smartNotif.priority
        )
        
        // Step 3: Get recipient's FCM token
        let fcmToken = try await fetchFCMToken(userId: recipientId)
        
        // Step 4: Create notification content
        let content = UNMutableNotificationContent()
        content.title = smartNotif.title
        content.body = smartNotif.body
        content.sound = .default
        content.categoryIdentifier = smartNotif.category
        
        // Set interruption level based on priority
        switch smartNotif.priority {
        case .high:
            content.interruptionLevel = .timeSensitive
        case .medium:
            content.interruptionLevel = .active
        case .low:
            content.interruptionLevel = .passive
        }
        
        // Add custom data
        var userInfo = customData
        userInfo["type"] = eventType.rawValue
        userInfo["priority"] = smartNotif.priority.rawValue
        content.userInfo = userInfo
        
        // Step 5: Send notification
        if timing.sendImmediately {
            // Send immediately via FCM
            try await sendPushNotification(
                token: fcmToken,
                content: content
            )
            print("✅ Smart notification sent immediately")
        } else {
            // Schedule for later
            try await scheduleNotification(
                token: fcmToken,
                content: content,
                delayMinutes: timing.delayMinutes
            )
            print("✅ Smart notification scheduled for \(timing.delayMinutes) minutes")
        }
        
        // Step 6: Save to Firestore for in-app notifications
        try await saveNotificationToFirestore(
            recipientId: recipientId,
            notification: smartNotif,
            customData: userInfo
        )
    }
    
    // MARK: - Batch Notifications
    
    /// Send notification summary for multiple pending notifications
    func sendBatchNotificationSummary(
        userId: String,
        pendingNotifications: [PendingNotification]
    ) async throws {
        
        guard pendingNotifications.count >= 3 else {
            print("⚠️ Not enough notifications to batch (need 3+, have \(pendingNotifications.count))")
            return
        }
        
        print("📦 Creating batch notification summary for \(pendingNotifications.count) notifications")
        
        // Generate summary
        let summary = try await summarizeNotifications(
            notifications: pendingNotifications,
            maxLength: 120
        )
        
        // Get FCM token
        let fcmToken = try await fetchFCMToken(userId: userId)
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Your AMEN Community"
        content.body = summary.summary
        content.sound = .default
        content.badge = NSNumber(value: summary.count)
        content.categoryIdentifier = "batch_summary"
        content.userInfo = [
            "type": "batch",
            "notificationIds": summary.notificationIds,
            "count": summary.count
        ]
        
        // Send
        try await sendPushNotification(token: fcmToken, content: content)
        
        // Mark individual notifications as sent in batch
        try await markNotificationsAsBatched(notificationIds: summary.notificationIds)
        
        print("✅ Batch notification summary sent")
    }
    
    // MARK: - Helper Methods
    
    private func callGenkitFlow(
        flowName: String,
        input: [String: Any]
    ) async throws -> [String: Any] {
        
        guard let url = URL(string: "\(genkitEndpoint)/\(flowName)") else {
            throw NotificationError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": input])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotificationError.requestFailed
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ Genkit request failed with status: \(httpResponse.statusCode)")
            if let errorString = String(data: data, encoding: .utf8) {
                print("   Error: \(errorString)")
            }
            throw NotificationError.requestFailed
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NotificationError.invalidResponse
        }
        
        // Genkit wraps response in "result" key
        if let result = json["result"] as? [String: Any] {
            return result
        }
        
        return json
    }
    
    private func fetchUserInterests(userId: String) async throws -> [String] {
        let doc = try await db.collection("users").document(userId).getDocument()
        
        if let interests = doc.data()?["interests"] as? [String] {
            return interests
        }
        
        return []
    }
    
    private func fetchUserActivityPatterns(userId: String) async throws -> [UserActivityPattern] {
        // Fetch from analytics or use defaults
        // For now, return default patterns
        return [
            UserActivityPattern(hour: 7, activeCount: 45),   // Morning
            UserActivityPattern(hour: 12, activeCount: 30),  // Noon
            UserActivityPattern(hour: 18, activeCount: 60),  // Evening
            UserActivityPattern(hour: 21, activeCount: 50),  // Night
            UserActivityPattern(hour: 2, activeCount: 5)     // Late night
        ]
    }
    
    private func fetchUserTimezone(userId: String) async throws -> String {
        let doc = try await db.collection("users").document(userId).getDocument()
        
        if let timezone = doc.data()?["timezone"] as? String {
            return timezone
        }
        
        return TimeZone.current.identifier
    }
    
    private func fetchFCMToken(userId: String) async throws -> String {
        let doc = try await db.collection("users").document(userId).getDocument()
        
        guard let token = doc.data()?["fcmToken"] as? String else {
            throw NotificationError.noFCMToken
        }
        
        return token
    }
    
    private func sendPushNotification(
        token: String,
        content: UNNotificationContent
    ) async throws {
        // In production, this would call Firebase Cloud Functions
        // For now, we'll save to Firestore to trigger Cloud Function
        
        let notificationData: [String: Any] = [
            "token": token,
            "title": content.title,
            "body": content.body,
            "data": content.userInfo,
            "priority": "high",
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        try await db.collection("notificationQueue").addDocument(data: notificationData)
        print("✅ Notification queued for delivery")
    }
    
    private func scheduleNotification(
        token: String,
        content: UNNotificationContent,
        delayMinutes: Int
    ) async throws {
        
        let scheduledTime = Date().addingTimeInterval(TimeInterval(delayMinutes * 60))
        
        let notificationData: [String: Any] = [
            "token": token,
            "title": content.title,
            "body": content.body,
            "data": content.userInfo,
            "scheduledFor": Timestamp(date: scheduledTime),
            "status": "scheduled",
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        try await db.collection("scheduledNotifications").addDocument(data: notificationData)
        print("✅ Notification scheduled for: \(scheduledTime)")
    }
    
    private func saveNotificationToFirestore(
        recipientId: String,
        notification: SmartNotification,
        customData: [String: Any]
    ) async throws {
        
        var notificationData: [String: Any] = [
            "userId": recipientId,
            "title": notification.title,
            "body": notification.body,
            "type": notification.eventType.rawValue,
            "priority": notification.priority.rawValue,
            "category": notification.category,
            "read": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        // Merge custom data
        notificationData.merge(customData) { _, new in new }
        
        try await db.collection("notifications").addDocument(data: notificationData)
        print("✅ Notification saved to Firestore")
    }
    
    private func markNotificationsAsBatched(notificationIds: [String]) async throws {
        let batch = db.batch()
        
        for id in notificationIds {
            let ref = db.collection("notifications").document(id)
            batch.updateData(["batched": true, "batchedAt": FieldValue.serverTimestamp()], forDocument: ref)
        }
        
        try await batch.commit()
        print("✅ \(notificationIds.count) notifications marked as batched")
    }
}

// MARK: - Data Models

enum NotificationEventType: String, Codable {
    case message = "message"
    case match = "match"
    case like = "like"
    case comment = "comment"
    case prayerRequest = "prayer_request"
    case prayerAnswer = "prayer_answer"
    case groupInvite = "group_invite"
    case eventInvite = "event_invite"
    case eventReminder = "event_reminder"
    case newFollower = "new_follower"
    case profileView = "profile_view"
    case verseOfDay = "verse_of_day"
    case devotional = "devotional"
}

enum NotificationPriority: String, Codable {
    case high = "high"       // Immediate, time-sensitive
    case medium = "medium"   // Normal delivery
    case low = "low"         // Can be batched/delayed
}

struct SmartNotification {
    let title: String
    let body: String
    let priority: NotificationPriority
    let category: String
    let eventType: NotificationEventType
}

struct NotificationSummary {
    let summary: String
    let count: Int
    let topPriority: String
    let notificationIds: [String]
}

struct PendingNotification: Identifiable {
    let id: String
    let type: String
    let senderName: String
    let message: String
    let timestamp: Date
}

struct UserActivityPattern {
    let hour: Int           // Hour of day (0-23)
    let activeCount: Int    // Number of actions in that hour
}

struct TimingRecommendation {
    let sendImmediately: Bool
    let delayMinutes: Int
    let reasoning: String
}

struct NotificationUserProfile {
    let id: String
    let name: String
    let interests: [String]
    let denomination: String?
    let location: String?
}

enum NotificationError: LocalizedError {
    case invalidEndpoint
    case requestFailed
    case invalidResponse
    case noNotifications
    case noFCMToken
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid Genkit endpoint URL"
        case .requestFailed:
            return "Genkit request failed"
        case .invalidResponse:
            return "Invalid response from Genkit"
        case .noNotifications:
            return "No notifications to process"
        case .noFCMToken:
            return "User has no FCM token"
        }
    }
}
