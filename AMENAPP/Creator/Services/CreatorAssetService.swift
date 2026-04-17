import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

protocol CreatorAssetServicing {
    func fetchAssets(projectID: String) async throws -> [CreatorAsset]
    func updateAsset(assetID: String, fields: [String: Any]) async throws
    func resolveDownloadURL(storagePath: String) async throws -> String
}

final class CreatorAssetService: CreatorAssetServicing {
    private lazy var db = Firestore.firestore()
    private lazy var storage = Storage.storage()

    func fetchAssets(projectID: String) async throws -> [CreatorAsset] {
        let ownerID = try requireOwnerID()
        let snapshot = try await db.collection("users")
            .document(ownerID)
            .collection("creatorAssets")
            .whereField("projectID", isEqualTo: projectID)
            .order(by: "createdAt", descending: false)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            guard let data = document.data() as [String: Any]? else { return nil }
            return try? CreatorFirestoreCoder.decode(CreatorAsset.self, from: data)
        }
    }

    func updateAsset(assetID: String, fields: [String: Any]) async throws {
        let ownerID = try requireOwnerID()
        try await db.collection("users")
            .document(ownerID)
            .collection("creatorAssets")
            .document(assetID)
            .updateData(fields)
    }

    func resolveDownloadURL(storagePath: String) async throws -> String {
        let ref = storage.reference(withPath: storagePath)
        return try await withCheckedThrowingContinuation { continuation in
            ref.downloadURL { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: CreatorServiceError.invalidState)
                    return
                }
                continuation.resume(returning: url.absoluteString)
            }
        }
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else {
            throw CreatorServiceError.notFound
        }
        return ownerID
    }
}
