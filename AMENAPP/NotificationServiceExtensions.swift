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
    
    /// Manual refresh of notifications
    func refresh() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot refresh notifications: No user logged in")
            return
        }
        
        print("🔄 Refreshing notifications for user: \(userId)")
        
        await MainActor.run {
            self.isLoading = true
            self.error = nil
        }
        
        do {
            // Fetch notifications from Firestore
            let snapshot = try await db.collection("notifications")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()
            
            var fetchedNotifications: [AppNotification] = []
            
            for document in snapshot.documents {
                do {
                    let notification = try document.data(as: AppNotification.self)
                    fetchedNotifications.append(notification)
                } catch {
                    print("⚠️ Failed to decode notification \(document.documentID): \(error)")
                }
            }
            
            // Remove duplicate follow notifications (keep only the most recent)
            let deduplicated = removeDuplicateFollowNotifications(fetchedNotifications)
            
            await MainActor.run {
                self.notifications = deduplicated
                self.isLoading = false
                print("✅ Refreshed \(deduplicated.count) notifications")
            }
            
        } catch {
            await MainActor.run {
                self.error = .fetchFailed(error)
                self.isLoading = false
            }
            print("❌ Failed to refresh notifications: \(error)")
        }
    }
    
    /// Start listening for real-time notification updates
    func startListening() {
        guard listenerRegistration == nil else {
            print("⚠️ Already listening for notifications")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot start listening: No user logged in")
            return
        }
        
        print("👂 Starting to listen for notifications for user: \(userId)")
        
        isLoading = true
        
        listenerRegistration = db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                Task { @MainActor in
                    if let error = error {
                        print("❌ Notification listener error: \(error)")
                        self.error = .fetchFailed(error)
                        self.isLoading = false
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("⚠️ No notification documents found")
                        self.isLoading = false
                        return
                    }
                    
                    var fetchedNotifications: [AppNotification] = []
                    
                    for document in documents {
                        do {
                            let notification = try document.data(as: AppNotification.self)
                            fetchedNotifications.append(notification)
                        } catch {
                            print("⚠️ Failed to decode notification \(document.documentID): \(error)")
                        }
                    }
                    
                    // Remove duplicate follow notifications
                    let deduplicated = self.removeDuplicateFollowNotifications(fetchedNotifications)
                    
                    self.notifications = deduplicated
                    self.isLoading = false
                    
                    print("✅ Loaded \(deduplicated.count) notifications via listener")
                }
            }
    }
    
    /// Stop listening for notification updates
    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        print("🔇 Stopped listening for notifications")
    }
    
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
            notifications.removeAll { notification in
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

// MARK: - Listener Management Property

extension NotificationService {
    private static var listenerKey = "listenerRegistration"
    
    var listenerRegistration: ListenerRegistration? {
        get {
            objc_getAssociatedObject(self, &Self.listenerKey) as? ListenerRegistration
        }
        set {
            objc_setAssociatedObject(self, &Self.listenerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}
