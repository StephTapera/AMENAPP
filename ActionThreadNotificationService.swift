//
//  ActionThreadNotificationService.swift
//  AMENAPP
//
//  Handles smart notification delivery for Action Thread events.
//  Supports grouped notifications, rate limiting, and respectful wording.
//  Integrates with the existing NotificationService for delivery.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ActionThreadNotificationService {
    
    static let shared = ActionThreadNotificationService()
    private let db = Firestore.firestore()
    
    // Rate limiting: max N thread notifications per user per hour
    private var notificationCounts: [String: (count: Int, windowStart: Date)] = [:]
    private let maxNotificationsPerHour = 10
    
    private init() {}
    
    // MARK: - Send Invite Notification
    
    /// Notify a user they've been invited to a support flow.
    func sendInviteNotification(
        threadId: String,
        postId: String,
        inviteeUserId: String,
        inviterName: String
    ) async {
        guard rateLimitCheck(userId: inviteeUserId) else { return }
        
        let notificationData: [String: Any] = [
            "userId": inviteeUserId,
            "type": "action_thread_invite",
            "actorId": Auth.auth().currentUser?.uid ?? "",
            "actorName": inviterName,
            "postId": postId,
            "groupId": "action_thread_\(threadId)",
            "read": false,
            "createdAt": Timestamp(date: Date()),
            "idempotencyKey": "action_thread_invite_\(threadId)_\(inviteeUserId)"
        ]
        
        do {
            try await db.collection("users").document(inviteeUserId)
                .collection("notifications")
                .document("action_thread_invite_\(threadId)_\(inviteeUserId)")
                .setData(notificationData, merge: true)
        } catch {
            dlog("[ActionThreadNotifications] Failed to send invite: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Send Thread Update Notification
    
    /// Notify participants about updates (step completed, new step, etc.).
    /// Groups notifications by threadId to prevent spam.
    func sendThreadUpdateNotification(
        threadId: String,
        postId: String,
        participantUserIds: [String],
        actorName: String,
        updateSummary: String
    ) async {
        guard let actorId = Auth.auth().currentUser?.uid else { return }
        
        let batch = db.batch()
        var batchCount = 0
        
        for userId in participantUserIds {
            guard userId != actorId else { continue }  // Don't self-notify
            guard rateLimitCheck(userId: userId) else { continue }
            
            let notificationData: [String: Any] = [
                "userId": userId,
                "type": "action_thread_update",
                "actorId": actorId,
                "actorName": actorName,
                "postId": postId,
                "commentText": updateSummary,
                "groupId": "action_thread_\(threadId)",
                "read": false,
                "createdAt": Timestamp(date: Date()),
                "idempotencyKey": "action_thread_update_\(threadId)_\(actorId)_\(Int(Date().timeIntervalSince1970 / 3600))"
            ]
            
            let ref = db.collection("users").document(userId)
                .collection("notifications").document()
            batch.setData(notificationData, forDocument: ref)
            batchCount += 1
            
            if batchCount >= 499 { break }
        }
        
        guard batchCount > 0 else { return }
        
        do {
            try await batch.commit()
        } catch {
            dlog("[ActionThreadNotifications] Failed to send updates: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Send Reminder Notification
    
    /// Send a scheduled reminder for an action thread step.
    func sendReminderNotification(
        reminder: ActionReminder
    ) async {
        guard rateLimitCheck(userId: reminder.recipientUserId) else { return }
        
        let notificationData: [String: Any] = [
            "userId": reminder.recipientUserId,
            "type": "action_thread_reminder",
            "actorId": "system",
            "actorName": "AMEN",
            "postId": reminder.threadId,
            "commentText": reminder.body,
            "groupId": "action_thread_\(reminder.threadId)",
            "read": false,
            "createdAt": Timestamp(date: Date()),
            "idempotencyKey": "action_thread_reminder_\(reminder.id)"
        ]
        
        do {
            try await db.collection("users").document(reminder.recipientUserId)
                .collection("notifications")
                .document("action_thread_reminder_\(reminder.id)")
                .setData(notificationData, merge: true)
        } catch {
            dlog("[ActionThreadNotifications] Failed to send reminder: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Rate Limiting
    
    private func rateLimitCheck(userId: String) -> Bool {
        let now = Date()
        if let entry = notificationCounts[userId] {
            if now.timeIntervalSince(entry.windowStart) < 3600 {
                if entry.count >= maxNotificationsPerHour {
                    return false  // Rate limited
                }
                notificationCounts[userId] = (entry.count + 1, entry.windowStart)
            } else {
                notificationCounts[userId] = (1, now)  // New window
            }
        } else {
            notificationCounts[userId] = (1, now)
        }
        return true
    }
}
