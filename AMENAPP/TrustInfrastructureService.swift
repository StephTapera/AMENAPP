import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class TrustInfrastructureService: ObservableObject {
    static let shared = TrustInfrastructureService()

    @Published private(set) var verifiedMinistryIds: [String] = []
    @Published private(set) var moderationCouncilQueueCount: Int = 0

    private lazy var db = Firestore.firestore()

    private init() {}

    func loadTrustInfrastructureSnapshot() async throws {
        let ministriesSnapshot = try await db.collection("verified_ministries")
            .limit(to: 50)
            .getDocuments()

        verifiedMinistryIds = ministriesSnapshot.documents.map(\.documentID)

        let moderationSnapshot = try await db.collection("moderation_queue")
            .whereField("escalated", isEqualTo: true)
            .limit(to: 200)
            .getDocuments()

        moderationCouncilQueueCount = moderationSnapshot.documents.count
    }

    func appendAuditTrail(
        collection: String,
        entityId: String,
        action: String,
        metadata: [String: String] = [:]
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection(collection)
            .document(entityId)
            .collection("audit_log")
            .addDocument(data: [
                "actorId": uid,
                "action": action,
                "metadata": metadata,
                "createdAt": FieldValue.serverTimestamp()
            ])
    }
}
