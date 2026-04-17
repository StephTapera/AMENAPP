import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorDraftRecoveryServicing {
    func recoverLastProject(ownerID: String) async throws -> CreatorProject?
}

final class CreatorDraftRecoveryService: CreatorDraftRecoveryServicing {
    private lazy var db = Firestore.firestore()

    func recoverLastProject(ownerID: String) async throws -> CreatorProject? {
        let snapshot = try await db.collection("users")
            .document(ownerID)
            .collection("creatorDrafts")
            .order(by: "lastEditedAt", descending: true)
            .limit(to: 1)
            .getDocuments()

        guard let document = snapshot.documents.first else { return nil }
        return try? CreatorFirestoreCoder.decode(CreatorProject.self, from: document.data())
    }
}
