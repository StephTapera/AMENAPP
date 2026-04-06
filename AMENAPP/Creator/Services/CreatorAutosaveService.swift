import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorAutosaveServicing {
    func autosave(project: CreatorProject) async throws
}

final class CreatorAutosaveService: CreatorAutosaveServicing {
    private let db = Firestore.firestore()

    func autosave(project: CreatorProject) async throws {
        let ownerID = try requireOwnerID()
        let ref = db.collection("users")
            .document(ownerID)
            .collection("creatorDrafts")
            .document(project.id)

        let data = try CreatorFirestoreCoder.encode(project)
        try await ref.setData(data, merge: true)
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else {
            throw CreatorServiceError.notFound
        }
        return ownerID
    }
}
