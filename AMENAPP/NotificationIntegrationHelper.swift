//
//  NotificationIntegrationHelper.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/23/26.
//
//  Helper to easily replace existing notifications with AI-powered ones
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Easy Integration Helper

/// Drop-in replacement for your existing notification calls
@MainActor
class NotificationHelper {
    static let shared = NotificationHelper()
    
    private let genkitService = NotificationGenkitService.shared
    private let db = Firestore.firestore()
    
    // MARK: - Simple Notification Methods
    
    /// Send a message notification - AI-powered!
    func notifyNewMessage(
        from senderId: String,
        senderName: String,
        to recipientId: String,
        messageText: String,
        conversationId: String
    ) async {
        do {
            // Fetch sender profile for personalization
            let senderProfile = try? await fetchUserProfile(userId: senderId)
            
            try await genkitService.sendSmartNotification(
                eventType: NotificationEventType.message,
                senderName: senderName,
                senderProfile: senderProfile,
                recipientId: recipientId,
                context: messageText,
                metadata: ["messagePreview": String(messageText.prefix(50))],
                customData: [
                    "senderId": senderId,
                    "conversationId": conversationId,
                    "type": "message"
                ]
            )
            
            print("✅ Message notification sent to \(recipientId)")
        } catch {
            print("❌ Error sending message notification: \(error)")
            // Fallback to basic notification
            await sendBasicNotification(
                to: recipientId,
                title: "\(senderName) sent you a message",
                body: messageText
            )
        }
    }
    
    /// Send a match notification - AI-powered!
    func notifyNewMatch(
        user1Id: String,
        user1Name: String,
        user2Id: String,
        user2Name: String,
        sharedInterests: [String] = []
    ) async {
        do {
            let user1Profile = try? await fetchUserProfile(userId: user1Id)
            let user2Profile = try? await fetchUserProfile(userId: user2Id)
            
            let context = sharedInterests.isEmpty
                ? "You have a new match!"
                : "You both love: \(sharedInterests.joined(separator: ", "))"
            
            // Notify user1
            try await genkitService.sendSmartNotification(
                eventType: NotificationEventType.match,
                senderName: user2Name,
                senderProfile: user2Profile,
                recipientId: user1Id,
                context: context,
                metadata: ["sharedInterests": sharedInterests],
                customData: [
                    "matchId": user2Id,
                    "type": "match"
                ]
            )
            
            // Notify user2
            try await genkitService.sendSmartNotification(
                eventType: NotificationEventType.match,
                senderName: user1Name,
                senderProfile: user1Profile,
                recipientId: user2Id,
                context: context,
                metadata: ["sharedInterests": sharedInterests],
                customData: [
                    "matchId": user1Id,
                    "type": "match"
                ]
            )
            
            print("✅ Match notifications sent to both users")
        } catch {
            print("❌ Error sending match notifications: \(error)")
        }
    }
    
    /// Send a like notification - AI-powered!
    func notifyPostLike(
        likerId: String,
        likerName: String,
        postOwnerId: String,
        postId: String,
        postContent: String
    ) async {
        do {
            let likerProfile = try? await fetchUserProfile(userId: likerId)
            
            try await genkitService.sendSmartNotification(
                eventType: NotificationEventType.like,
                senderName: likerName,
                senderProfile: likerProfile,
                recipientId: postOwnerId,
                context: "liked your post: \(postContent)",
                customData: [
                    "likerId": likerId,
                    "postId": postId,
                    "type": "like"
                ]
            )
            
            print("✅ Like notification sent")
        } catch {
            print("❌ Error sending like notification: \(error)")
        }
    }
    
    /// Send a comment notification - AI-powered!
    func notifyNewComment(
        commenterId: String,
        commenterName: String,
        postOwnerId: String,
        postId: String,
        commentText: String
    ) async {
        do {
            let commenterProfile = try? await fetchUserProfile(userId: commenterId)
            
            try await genkitService.sendSmartNotification(
                eventType: NotificationEventType.comment,
                senderName: commenterName,
                senderProfile: commenterProfile,
                recipientId: postOwnerId,
                context: commentText,
                customData: [
                    "commenterId": commenterId,
                    "postId": postId,
                    "type": "comment"
                ]
            )
            
            print("✅ Comment notification sent")
        } catch {
            print("❌ Error sending comment notification: \(error)")
        }
    }
    
    /// Send a prayer request notification - HIGH PRIORITY!
    func notifyPrayerRequest(
        requesterId: String,
        requesterName: String,
        prayerCircleIds: [String],
        prayerText: String,
        isUrgent: Bool = false
    ) async {
        for memberId in prayerCircleIds {
            do {
                let requesterProfile = try? await fetchUserProfile(userId: requesterId)
                
                let context = isUrgent ? "URGENT: \(prayerText)" : prayerText
                
                try await genkitService.sendSmartNotification(
                    eventType: NotificationEventType.prayerRequest,
                    senderName: requesterName,
                    senderProfile: requesterProfile,
                    recipientId: memberId,
                    context: context,
                    metadata: ["urgent": isUrgent],
                    customData: [
                        "requesterId": requesterId,
                        "type": "prayer_request",
                        "priority": isUrgent ? "high" : "medium"
                    ]
                )
                
                print("✅ Prayer notification sent to \(memberId)")
            } catch {
                print("❌ Error sending prayer notification: \(error)")
            }
        }
    }
    
    /// Send event reminder notification - AI-powered!
    func notifyEventReminder(
        eventId: String,
        eventTitle: String,
        eventLocation: String,
        eventTime: Date,
        organizerName: String,
        attendeeIds: [String],
        minutesUntilStart: Int
    ) async {
        let context = "\(eventTitle) starts in \(minutesUntilStart) minutes at \(eventLocation)"
        
        for attendeeId in attendeeIds {
            do {
                try await genkitService.sendSmartNotification(
                    eventType: NotificationEventType.eventReminder,
                    senderName: organizerName,
                    senderProfile: nil,
                    recipientId: attendeeId,
                    context: context,
                    metadata: ["minutesUntil": minutesUntilStart],
                    customData: [
                        "eventId": eventId,
                        "eventTitle": eventTitle,
                        "eventLocation": eventLocation,
                        "type": "event_reminder"
                    ]
                )
                
                print("✅ Event reminder sent to \(attendeeId)")
            } catch {
                print("❌ Error sending event reminder: \(error)")
            }
        }
    }
    
    /// Send group invite notification - AI-powered!
    func notifyGroupInvite(
        groupId: String,
        groupName: String,
        inviterId: String,
        inviterName: String,
        inviteeId: String
    ) async {
        do {
            let inviterProfile = try? await fetchUserProfile(userId: inviterId)
            
            try await genkitService.sendSmartNotification(
                eventType: NotificationEventType.groupInvite,
                senderName: inviterName,
                senderProfile: inviterProfile,
                recipientId: inviteeId,
                context: "invited you to join '\(groupName)'",
                customData: [
                    "groupId": groupId,
                    "groupName": groupName,
                    "inviterId": inviterId,
                    "type": "group_invite"
                ]
            )
            
            print("✅ Group invite sent")
        } catch {
            print("❌ Error sending group invite: \(error)")
        }
    }
    
    // MARK: - Batch Notifications
    
    /// Send daily summary if user has multiple pending notifications
    func sendDailySummaryIfNeeded(userId: String) async {
        do {
            let pendingNotifications = try await fetchPendingNotifications(userId: userId)
            
            if pendingNotifications.count >= 3 {
                try await genkitService.sendBatchNotificationSummary(
                    userId: userId,
                    pendingNotifications: pendingNotifications
                )
                print("✅ Daily summary sent to \(userId)")
            } else {
                print("ℹ️ Not enough notifications for batching (\(pendingNotifications.count))")
            }
        } catch {
            print("❌ Error sending daily summary: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func fetchUserProfile(userId: String) async throws -> NotificationUserProfile {
        let doc = try await db.collection("users").document(userId).getDocument()
        
        guard let data = doc.data() else {
            throw NSError(domain: "NotificationHelper", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        return NotificationUserProfile(
            id: userId,
            name: data["name"] as? String ?? "User",
            interests: data["interests"] as? [String] ?? [],
            denomination: data["denomination"] as? String,
            location: data["location"] as? String
        )
    }
    
    private func fetchPendingNotifications(userId: String) async throws -> [PendingNotification] {
        let snapshot = try await db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
            .whereField("read", isEqualTo: false)
            .whereField("batched", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let type = data["type"] as? String,
                  let senderName = data["senderName"] as? String,
                  let message = data["body"] as? String,
                  let timestamp = data["createdAt"] as? Timestamp else {
                return nil
            }
            
            return PendingNotification(
                id: doc.documentID,
                type: type,
                senderName: senderName,
                message: message,
                timestamp: timestamp.dateValue()
            )
        }
    }
    
    private func sendBasicNotification(to userId: String, title: String, body: String) async {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            guard let fcmToken = doc.data()?["fcmToken"] as? String else {
                print("⚠️ No FCM token for user: \(userId)")
                return
            }
            
            // Queue basic notification
            try await db.collection("notificationQueue").addDocument(data: [
                "token": fcmToken,
                "title": title,
                "body": body,
                "data": ["type": "basic"],
                "createdAt": FieldValue.serverTimestamp()
            ])
            
            print("✅ Basic notification queued")
        } catch {
            print("❌ Error sending basic notification: \(error)")
        }
    }
}

// MARK: - Quick Migration Guide

/*
 
 MIGRATION GUIDE: Replace Your Existing Notifications
 ====================================================
 
 OLD CODE:
 ---------
 func sendMessageNotification() {
     let title = "\(senderName) sent you a message"
     let body = messageText
     // Send via FCM...
 }
 
 NEW CODE (AI-Powered):
 ----------------------
 func sendMessageNotification() {
     Task {
         await NotificationHelper.shared.notifyNewMessage(
             from: senderId,
             senderName: senderName,
             to: recipientId,
             messageText: messageText,
             conversationId: conversationId
         )
     }
 }
 
 EXAMPLES:
 ---------
 
 1. Messages:
    await NotificationHelper.shared.notifyNewMessage(
        from: message.senderId,
        senderName: message.senderName,
        to: message.recipientId,
        messageText: message.text,
        conversationId: conversationId
    )
 
 2. Matches:
    await NotificationHelper.shared.notifyNewMatch(
        user1Id: user1.id,
        user1Name: user1.name,
        user2Id: user2.id,
        user2Name: user2.name,
        sharedInterests: computeSharedInterests(user1, user2)
    )
 
 3. Likes:
    await NotificationHelper.shared.notifyPostLike(
        likerId: currentUser.id,
        likerName: currentUser.name,
        postOwnerId: post.authorId,
        postId: post.id,
        postContent: post.content
    )
 
 4. Prayer Requests:
    await NotificationHelper.shared.notifyPrayerRequest(
        requesterId: currentUser.id,
        requesterName: currentUser.name,
        prayerCircleIds: prayerCircle.memberIds,
        prayerText: prayerText,
        isUrgent: true
    )
 
 5. Event Reminders:
    await NotificationHelper.shared.notifyEventReminder(
        eventId: event.id,
        eventTitle: event.title,
        eventLocation: event.location,
        eventTime: event.startTime,
        organizerName: event.organizerName,
        attendeeIds: event.attendeeIds,
        minutesUntilStart: 30
    )
 
 6. Daily Summaries (run once per day):
    await NotificationHelper.shared.sendDailySummaryIfNeeded(userId: userId)
 
 */
