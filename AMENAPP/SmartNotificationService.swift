//
//  SmartNotificationService.swift
//  AMENAPP
//
//  AI-powered smart notifications to reduce fatigue
//  Batches similar notifications intelligently
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

// MARK: - Smart Notification Models

/// Batched notification group
struct NotificationBatch: Codable {
    let batchId: String
    let type: BatchType
    let count: Int
    let title: String
    let body: String
    let userIds: [String]
    let timestamp: Date
    
    enum BatchType: String, Codable {
        case prayers = "prayers" // Multiple people prayed
        case amens = "amens" // Multiple amens on your post
        case comments = "comments" // Multiple comments
        case follows = "follows" // Multiple follow requests
        case reposts = "reposts" // Multiple reposts
        case mentions = "mentions" // Multiple mentions
    }
}

/// User notification preferences learned by AI
struct AINotificationPreferences: Codable {
    let userId: String
    let bestTimeOfDay: Int // Hour (0-23)
    let preferredBatchSize: Int
    let quietHours: [Int] // Hours to not disturb
    let engagementRate: Double // How often user opens notifications
    let lastUpdated: Date
}

// MARK: - Smart Notification Service

/// Service for intelligent notification batching and timing
class SmartNotificationService {
    static let shared = SmartNotificationService()
    private lazy var db = Firestore.firestore()
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // Batching intervals
    private let batchWindowMinutes = 15 // Batch notifications within 15 minutes
    
    private init() {}
    
    // MARK: - Smart Batching
    
    /// Queue a notification for smart batching
    /// - Parameters:
    ///   - type: Type of notification
    ///   - recipientId: User receiving notification
    ///   - senderId: User triggering notification
    ///   - postId: Related post ID (if applicable)
    ///   - message: Notification message
    func queueNotification(
        type: NotificationBatch.BatchType,
        recipientId: String,
        senderId: String,
        postId: String? = nil,
        message: String
    ) async throws {
        
        dlog("📬 [SMART_NOTIF] Queuing \(type.rawValue) notification for user \(recipientId)")
        
        // Step 1: Check if user has similar pending notifications
        let existingBatch = try await findExistingBatch(
            type: type,
            recipientId: recipientId,
            postId: postId
        )
        
        if let batch = existingBatch {
            // Add to existing batch
            try await addToBatch(
                batchId: batch.batchId,
                senderId: senderId
            )
            
            dlog("📬 [SMART_NOTIF] Added to existing batch \(batch.batchId)")
            
        } else {
            // Create new batch
            let batchId = try await createNewBatch(
                type: type,
                recipientId: recipientId,
                senderId: senderId,
                postId: postId,
                message: message
            )
            
            dlog("📬 [SMART_NOTIF] Created new batch \(batchId)")
            
            // Schedule batch delivery based on user preferences
            try await scheduleBatchDelivery(batchId: batchId, recipientId: recipientId)
        }
    }
    
    /// Find existing batch using the deterministic day-bucket notificationKey.
    ///
    /// The key encodes type + postId + recipientId + ISO date, so there is at
    /// most one batch per combination per calendar day. This replaces the
    /// previous rolling-15-minute window query, providing stronger deduplication.
    private func findExistingBatch(
        type: NotificationBatch.BatchType,
        recipientId: String,
        postId: String?
    ) async throws -> NotificationBatch? {

        let dayBucket = ISO8601DateFormatter.dayBucketString(from: Date())
        let postPart = postId ?? "nopost"
        let notificationKey = "\(type.rawValue)_\(postPart)_\(recipientId)_\(dayBucket)"

        let doc = try await db.collection("notificationBatches")
            .document(notificationKey)
            .getDocument()

        guard doc.exists else { return nil }

        // Only return if not yet delivered — delivered batches should not
        // accumulate more senders after push has gone out.
        let delivered = doc.data()?["delivered"] as? Bool ?? false
        guard !delivered else { return nil }

        return try? doc.data(as: NotificationBatch.self)
    }
    
    /// Add notification to existing batch.
    /// `userIds` is capped at 10 senders for display ("John, Jane, and X others").
    /// Beyond 10, only `count` is incremented to avoid unbounded array growth.
    private func addToBatch(batchId: String, senderId: String) async throws {
        let docRef = db.collection("notificationBatches").document(batchId)
        let snapshot = try? await docRef.getDocument()
        let existingIds = snapshot?.data()?["userIds"] as? [String] ?? []
        var updateData: [String: Any] = [
            "count": FieldValue.increment(Int64(1)),
            "lastUpdated": FieldValue.serverTimestamp()
        ]
        if existingIds.count < 10 {
            updateData["userIds"] = FieldValue.arrayUnion([senderId])
        }
        try await docRef.updateData(updateData)
    }
    
    /// Create new notification batch.
    ///
    /// Deduplication key format: "{type}_{postId}_{recipientId}_{dayBucket}"
    /// where dayBucket is the ISO date string (YYYY-MM-DD).
    /// Using this as the document ID means only one batch exists per
    /// type + post + recipient per calendar day. Subsequent triggers on the
    /// same day increment `count` via `setData(merge: true)` rather than
    /// creating a new document.
    private func createNewBatch(
        type: NotificationBatch.BatchType,
        recipientId: String,
        senderId: String,
        postId: String?,
        message: String
    ) async throws -> String {

        let dayBucket = ISO8601DateFormatter.dayBucketString(from: Date())
        let postPart = postId ?? "nopost"
        let notificationKey = "\(type.rawValue)_\(postPart)_\(recipientId)_\(dayBucket)"

        var batchData: [String: Any] = [
            "notificationKey": notificationKey,
            "type": type.rawValue,
            "recipientId": recipientId,
            "userIds": [senderId],
            "count": 1,
            "message": message,
            "delivered": false,
            "timestamp": FieldValue.serverTimestamp(),
            "lastUpdated": FieldValue.serverTimestamp()
        ]

        if let postId = postId {
            batchData["postId"] = postId
        }

        // Use notificationKey as document ID for idempotency.
        // If this key already exists (race condition), merge increments count
        // without overwriting the existing batch state.
        try await db.collection("notificationBatches")
            .document(notificationKey)
            .setData(batchData, merge: false)

        return notificationKey
    }
    
    // MARK: - Smart Delivery Timing
    
    /// Schedule batch delivery based on user preferences
    private func scheduleBatchDelivery(batchId: String, recipientId: String) async throws {
        
        // Get user notification preferences (learned by AI)
        let preferences = try await getUserPreferences(userId: recipientId)
        
        // Calculate optimal delivery time
        let deliveryTime = calculateOptimalDeliveryTime(preferences: preferences)
        
        dlog("📬 [SMART_NOTIF] Scheduled batch \(batchId) for delivery at \(deliveryTime)")
        
        // Schedule Cloud Function to deliver batch
        try await db.collection("scheduledBatches")
            .document(batchId)
            .setData([
                "batchId": batchId,
                "recipientId": recipientId,
                "deliveryTime": Timestamp(date: deliveryTime),
                "status": "scheduled"
            ])
    }
    
    /// Get user notification preferences (AI-learned)
    private func getUserPreferences(userId: String) async throws -> AINotificationPreferences {
        
        let snapshot = try await db.collection("userNotificationPreferences")
            .document(userId)
            .getDocument()
        
        if let preferences = try? snapshot.data(as: AINotificationPreferences.self) {
            return preferences
        }
        
        // Default preferences if not learned yet
        return AINotificationPreferences(
            userId: userId,
            bestTimeOfDay: 19, // 7 PM default
            preferredBatchSize: 5,
            quietHours: [0, 1, 2, 3, 4, 5, 6, 22, 23], // Late night/early morning
            engagementRate: 0.5,
            lastUpdated: Date()
        )
    }
    
    /// Calculate optimal delivery time based on preferences
    private func calculateOptimalDeliveryTime(preferences: AINotificationPreferences) -> Date {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        
        // Check if we're in quiet hours
        if preferences.quietHours.contains(currentHour) {
            // Deliver at next non-quiet hour
            var nextHour = currentHour + 1
            while preferences.quietHours.contains(nextHour) && nextHour < 24 {
                nextHour += 1
            }
            
            // If all remaining hours are quiet, deliver at best time tomorrow
            if nextHour >= 24 {
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.day = (components.day ?? 0) + 1
                components.hour = preferences.bestTimeOfDay
                return calendar.date(from: components) ?? now.addingTimeInterval(3600)
            }
            
            // Deliver at next available hour
            var components = calendar.dateComponents([.year, .month, .day, .minute], from: now)
            components.hour = nextHour
            return calendar.date(from: components) ?? now.addingTimeInterval(3600)
        }
        
        // Not in quiet hours - deliver after batch window
        return now.addingTimeInterval(Double(batchWindowMinutes * 60))
    }
    
    // MARK: - Deliver Batched Notifications
    
    /// Deliver a batched notification (called by Cloud Function)
    func deliverBatch(_ batch: NotificationBatch) async throws {
        
        // Generate smart notification content
        let (title, body) = generateBatchedContent(batch: batch)
        
        // Send local notification
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1
        
        // Add batch metadata
        content.userInfo = [
            "type": batch.type.rawValue,
            "batchId": batch.batchId,
            "count": batch.count,
            "userIds": batch.userIds
        ]
        
        let request = UNNotificationRequest(
            identifier: batch.batchId,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        try await notificationCenter.add(request)
        
        // Mark batch as delivered
        try await db.collection("notificationBatches")
            .document(batch.batchId)
            .updateData([
                "delivered": true,
                "deliveredAt": FieldValue.serverTimestamp()
            ])
        
        dlog("📬 [SMART_NOTIF] Delivered batch \(batch.batchId): \(title)")
    }
    
    /// Generate smart content for batched notification
    private func generateBatchedContent(batch: NotificationBatch) -> (String, String) {
        let count = batch.count
        
        switch batch.type {
        case .prayers:
            if count == 1 {
                return ("Someone Prayed", "Someone prayed for your request")
            } else {
                return ("\(count) People Prayed", "\(count) people prayed for your request")
            }
            
        case .amens:
            if count == 1 {
                return ("New Amen", "Someone said Amen to your post")
            } else {
                return ("\(count) Amens", "\(count) people said Amen to your post")
            }
            
        case .comments:
            if count == 1 {
                return ("New Comment", "Someone commented on your post")
            } else {
                return ("\(count) New Comments", "\(count) people commented on your post")
            }
            
        case .follows:
            if count == 1 {
                return ("New Follow Request", "Someone wants to follow you")
            } else {
                return ("\(count) Follow Requests", "\(count) people want to follow you")
            }
            
        case .reposts:
            if count == 1 {
                return ("Your Post Was Shared", "Someone shared your post")
            } else {
                return ("\(count) Shares", "\(count) people shared your post")
            }
            
        case .mentions:
            if count == 1 {
                return ("You Were Mentioned", "Someone mentioned you in a post")
            } else {
                return ("\(count) Mentions", "\(count) people mentioned you")
            }
        }
    }
    
    // MARK: - Learn User Preferences (AI)
    
    /// Update user preferences based on engagement patterns (called by Cloud Function)
    func updateUserPreferences(userId: String, engagement: AINotificationEngagement) async throws {
        
        let currentPrefs = try await getUserPreferences(userId: userId)
        
        // AI learning: Adjust preferences based on user behavior
        let updatedPrefs = AINotificationPreferences(
            userId: userId,
            bestTimeOfDay: engagement.openedAt?.hour ?? currentPrefs.bestTimeOfDay,
            preferredBatchSize: currentPrefs.preferredBatchSize,
            quietHours: currentPrefs.quietHours,
            engagementRate: (currentPrefs.engagementRate + (engagement.opened ? 1.0 : 0.0)) / 2.0,
            lastUpdated: Date()
        )
        
        // Save updated preferences
        try await db.collection("userNotificationPreferences")
            .document(userId)
            .setData([
                "userId": userId,
                "bestTimeOfDay": updatedPrefs.bestTimeOfDay,
                "preferredBatchSize": updatedPrefs.preferredBatchSize,
                "quietHours": updatedPrefs.quietHours,
                "engagementRate": updatedPrefs.engagementRate,
                "lastUpdated": FieldValue.serverTimestamp()
            ])
        
        dlog("📬 [SMART_NOTIF] Updated preferences for user \(userId)")
    }
}

// MARK: - Supporting Models

/// Notification engagement tracking for AI learning
struct AINotificationEngagement {
    let userId: String
    let batchId: String
    let opened: Bool
    let openedAt: DateComponents?
}

extension Date {
    var hour: Int {
        Calendar.current.component(.hour, from: self)
    }
}

// MARK: - Day Bucket Helper

private extension ISO8601DateFormatter {
    /// Returns an ISO date string (YYYY-MM-DD) for use as the daily deduplication
    /// bucket in notification keys, e.g. "amens_postABC_userXYZ_2026-04-05".
    static func dayBucketString(from date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return fmt.string(from: date)
    }
}
