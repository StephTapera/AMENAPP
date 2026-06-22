import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorBrandKitServicing {
    func fetchBrandKits(ownerID: String) async throws -> [CreatorBrandKit]
    func saveBrandKit(_ kit: CreatorBrandKit) async throws
}

final class CreatorBrandKitService: CreatorBrandKitServicing {
    private lazy var db = Firestore.firestore()

    func fetchBrandKits(ownerID: String) async throws -> [CreatorBrandKit] {
        let snapshot = try await db.collection("users")
            .document(ownerID)
            .collection("creatorBrandKits")
            .order(by: "updatedAt", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { document in
            guard let data = document.data() as [String: Any]? else { return nil }
            return try? CreatorFirestoreCoder.decode(CreatorBrandKit.self, from: data)
        }
    }

    func saveBrandKit(_ kit: CreatorBrandKit) async throws {
        let ownerID = try requireOwnerID()
        let ref = db.collection("users")
            .document(ownerID)
            .collection("creatorBrandKits")
            .document(kit.id)
        let data = try CreatorFirestoreCoder.encode(kit)
        try await ref.setData(data, merge: true)
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else {
            throw CreatorServiceError.notFound
        }
        return ownerID
    }
}
