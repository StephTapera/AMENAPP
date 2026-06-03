import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class TrustInfrastructureService: ObservableObject {
    static let shared = TrustInfrastructureService()

    @Published private(set) var verifiedMinistryIds: [String] = []
    @Published private(set) var moderationCouncilQueueCount: Int = 0

    private lazy var db = Firestore.firestore()
    // H-13 FIX: audit log writes go through a callable CF so userId is server-authoritative.
    private let functions = Functions.functions()

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

    /// H-13 FIX: Audit trail writes are now server-authoritative via the `writeBereanAuditEntry`
    /// Cloud Function. The server stamps `userId` from `request.auth.uid`, so the client
    /// cannot forge the actor identity. The `collection` and `entityId` are forwarded as
    /// metadata so the audit record retains context about which entity was affected.
    func appendAuditTrail(
        collection: String,
        entityId: String,
        action: String,
        metadata: [String: String] = [:]
    ) async throws {
        guard Auth.auth().currentUser?.uid != nil else { return }
        var fullMetadata = metadata
        fullMetadata["collection"] = collection
        fullMetadata["entityId"] = entityId
        let payload: [String: Any] = [
            "event": action,
            "metadata": fullMetadata
        ]
        _ = try await functions.httpsCallable("writeBereanAuditEntry").call(payload)
    }
}
