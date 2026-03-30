import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

/// Service for bundling low-priority notifications into digests
@MainActor
class NotificationDigestService: ObservableObject {
    static let shared = NotificationDigestService()
    
    private let db = Firestore.firestore()
    @Published var pendingDigest: NotificationDigest?
    @Published var digestHistory: [NotificationDigest] = []
    
    // MARK: - Fetch Current Digest
    
    /// Load the current pending digest for the user
    func loadCurrentDigest() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let digestId = "\(userId)_\(today.timeIntervalSince1970)"
        
        let doc = try await db.collection("notificationDigests").document(digestId).getDocument()
        
        if let data = doc.data(),
           let jsonData = try? JSONSerialization.data(withJSONObject: data),
           var digest = try? JSONDecoder().decode(NotificationDigest.self, from: jsonData) {
            
            // Group items by category
            digest = groupDigestItems(digest)
            self.pendingDigest = digest
        } else {
            self.pendingDigest = nil
        }
    }
    
    /// Load digest history (last 30 days)
    func loadDigestHistory() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        
        let snapshot = try await db.collection("notificationDigests")
            .whereField("userId", isEqualTo: userId)
            .whereField("createdAt", isGreaterThan: Timestamp(date: thirtyDaysAgo))
            .order(by: "createdAt", descending: true)
            .limit(to: 30)
            .getDocuments()
        
        var digests: [NotificationDigest] = []
        for doc in snapshot.documents {
            if let data = try? JSONSerialization.data(withJSONObject: doc.data()),
               let digest = try? JSONDecoder().decode(NotificationDigest.self, from: data) {
                digests.append(digest)
            }
        }
        
        self.digestHistory = digests
    }
    
    // MARK: - Group Items
    
    private func groupDigestItems(_ digest: NotificationDigest) -> NotificationDigest {
        // Aggregate raw items by category into DigestItem buckets
        var countsByCategory: [NotificationCategory: Int] = [:]
        var previewsByCategory: [NotificationCategory: [String]] = [:]
        var deepLinksByCategory: [NotificationCategory: [String]] = [:]

        for item in digest.items {
            let cat = item.category
            countsByCategory[cat, default: 0] += item.count
            previewsByCategory[cat, default: []].append(contentsOf: item.preview.prefix(2))
            deepLinksByCategory[cat, default: []].append(contentsOf: item.deepLinks.prefix(2))
        }

        let grouped: [NotificationDigest.DigestItem] = countsByCategory.map { (category, count) in
            NotificationDigest.DigestItem(
                category: category,
                count: count,
                preview: Array(previewsByCategory[category, default: []].prefix(3)),
                deepLinks: Array(deepLinksByCategory[category, default: []].prefix(3))
            )
        }.sorted { $0.count > $1.count }  // Highest-count category first

        return NotificationDigest(
            id: digest.id,
            userId: digest.userId,
            period: digest.period,
            items: grouped,
            createdAt: digest.createdAt,
            deliveredAt: digest.deliveredAt,
            opened: digest.opened
        )
    }
    
    // MARK: - Deliver Digest
    
    /// Send digest notification (called by scheduled Cloud Function)
    func deliverDigest(digestId: String) async throws {
        let digestDoc = try await db.collection("notificationDigests").document(digestId).getDocument()
        
        guard let data = digestDoc.data(),
              let userId = data["userId"] as? String,
              let items = data["items"] as? [[String: Any]] else {
            return
        }
        
        // Group by category and count
        var categoryCounts: [String: Int] = [:]
        var previews: [String: [String]] = [:]
        
        for item in items {
            guard let category = item["category"] as? String,
                  let title = item["title"] as? String else { continue }
            
            categoryCounts[category, default: 0] += 1
            previews[category, default: []].append(title)
        }
        
        // Build summary text
        let summaryParts = categoryCounts.map { (category, count) -> String in
            let categoryName = NotificationCategory(rawValue: category)?.displayName.lowercased() ?? "notifications"
            return "\(count) \(categoryName)\(count == 1 ? "" : "s")"
        }
        
        let summary = summaryParts.joined(separator: ", ")
        
        // Send push notification
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let fcmToken = userDoc.data()?["fcmToken"] as? String else { return }
        
        let fcmPayload: [String: Any] = [
            "to": fcmToken,
            "priority": "normal",
            "notification": [
                "title": "Your Daily Summary",
                "body": "You have \(summary)",
                "sound": "default",
                "badge": items.count
            ],
            "data": [
                "digestId": digestId,
                "deepLink": "amen://notifications/digest/\(digestId)",
                "type": "digest"
            ]
        ]
        
        // Send via Cloud Function
        let notificationRef = db.collection("pendingNotifications").document()
        try await notificationRef.setData([
            "payload": fcmPayload,
            "createdAt": FieldValue.serverTimestamp(),
            "status": "pending"
        ])
        
        // Mark digest as delivered
        try await db.collection("notificationDigests").document(digestId).updateData([
            "delivered": true,
            "deliveredAt": FieldValue.serverTimestamp()
        ])
    }
    
    // MARK: - Mark Digest Opened
    
    func markDigestOpened(digestId: String) async throws {
        try await db.collection("notificationDigests").document(digestId).updateData([
            "opened": true,
            "openedAt": FieldValue.serverTimestamp()
        ])
        
        // Mark all individual notifications in digest as read
        let digestDoc = try await db.collection("notificationDigests").document(digestId).getDocument()
        guard let data = digestDoc.data(),
              let userId = data["userId"] as? String,
              let items = data["items"] as? [[String: Any]] else {
            return
        }
        
        for item in items {
            if let notificationId = item["notificationId"] as? String {
                try? await db.collection("users").document(userId)
                    .collection("notifications").document(notificationId)
                    .updateData(["read": true, "readAt": FieldValue.serverTimestamp()])
            }
        }
    }
}
