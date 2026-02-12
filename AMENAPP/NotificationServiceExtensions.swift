//
//  NotificationServiceExtensions.swift
//  AMENAPP
//
//  Extensions for NotificationService with refresh, listeners, and duplicate prevention
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - NotificationService Extension

extension NotificationService {
    
    // NOTE: The refresh(), startListening(), and stopListening() methods 
    // are now in NotificationService.swift to avoid duplication
    
    /// Remove duplicate follow notifications (keep most recent from each user)
    private func removeDuplicateFollowNotifications(_ notifications: [AppNotification]) -> [AppNotification] {
        var seenFollows: [String: AppNotification] = [:] // actorId -> most recent notification
        var result: [AppNotification] = []
        
        for notification in notifications {
            if notification.type == .follow, let actorId = notification.actorId {
                // Check if we've seen a follow from this user
                if let existing = seenFollows[actorId] {
                    // Keep the more recent one
                    if notification.createdAt.seconds > existing.createdAt.seconds {
                        seenFollows[actorId] = notification
                    }
                } else {
                    seenFollows[actorId] = notification
                }
            } else {
                // Not a follow notification, keep it
                result.append(notification)
            }
        }
        
        // Add all unique follow notifications
        result.append(contentsOf: seenFollows.values)
        
        // Sort by creation date (most recent first)
        result.sort { $0.createdAt.seconds > $1.createdAt.seconds }
        
        return result
    }
    
    /// Delete old follow notification when user unfollows
    func deleteFollowNotification(actorId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "NotificationService", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "No user logged in"])
        }
        
        // Find and delete the follow notification from this actor
        let snapshot = try await db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
            .whereField("type", isEqualTo: "follow")
            .whereField("actorId", isEqualTo: actorId)
            .getDocuments()
        
        for document in snapshot.documents {
            try await document.reference.delete()
            print("🗑️ Deleted old follow notification from \(actorId)")
        }
        
        // Also remove from local array
        await MainActor.run {
            removeNotifications { notification in
                notification.type == .follow && notification.actorId == actorId
            }
        }
    }
    
    /// Clean up duplicate notifications in database (run once or periodically)
    func cleanupDuplicateFollowNotifications() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        print("🧹 Cleaning up duplicate follow notifications...")
        
        do {
            let snapshot = try await db.collection("notifications")
                .whereField("userId", isEqualTo: userId)
                .whereField("type", isEqualTo: "follow")
                .getDocuments()
            
            var followsByActor: [String: [QueryDocumentSnapshot]] = [:]
            
            // Group by actorId
            for document in snapshot.documents {
                if let actorId = document.data()["actorId"] as? String {
                    followsByActor[actorId, default: []].append(document)
                }
            }
            
            // For each actor, keep only the most recent notification
            for (actorId, documents) in followsByActor where documents.count > 1 {
                // Sort by timestamp (most recent first)
                let sorted = documents.sorted { doc1, doc2 in
                    let ts1 = (doc1.data()["createdAt"] as? Timestamp)?.seconds ?? 0
                    let ts2 = (doc2.data()["createdAt"] as? Timestamp)?.seconds ?? 0
                    return ts1 > ts2
                }
                
                // Delete all except the first (most recent)
                for document in sorted.dropFirst() {
                    try await document.reference.delete()
                    print("🗑️ Deleted duplicate follow notification from \(actorId)")
                }
            }
            
            print("✅ Cleanup complete")
            
            // Refresh notifications
            await refresh()
            
        } catch {
            print("❌ Error cleaning up duplicates: \(error)")
        }
    }
}

