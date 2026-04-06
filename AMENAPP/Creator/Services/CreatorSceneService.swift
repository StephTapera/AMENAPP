import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorSceneServicing {
    func fetchScenes(projectID: String) async throws -> [CreatorScene]
    func createScene(projectID: String, assetID: String, orderIndex: Int) async throws -> CreatorScene
    func updateScene(sceneID: String, fields: [String: Any]) async throws
}

final class CreatorSceneService: CreatorSceneServicing {
    private let db = Firestore.firestore()

    func fetchScenes(projectID: String) async throws -> [CreatorScene] {
        let ownerID = try requireOwnerID()
        let snapshot = try await db.collection("users")
            .document(ownerID)
            .collection("creatorScenes")
            .whereField("projectID", isEqualTo: projectID)
            .order(by: "orderIndex", descending: false)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            guard let data = document.data() as [String: Any]? else { return nil }
            return try? CreatorFirestoreCoder.decode(CreatorScene.self, from: data)
        }
    }

    func createScene(projectID: String, assetID: String, orderIndex: Int) async throws -> CreatorScene {
        let ownerID = try requireOwnerID()
        let sceneRef = db.collection("users")
            .document(ownerID)
            .collection("creatorScenes")
            .document()

        let scene = CreatorScene(
            id: sceneRef.documentID,
            projectID: projectID,
            assetID: assetID,
            orderIndex: orderIndex,
            startTimeMs: nil,
            endTimeMs: nil,
            textOverlayIDs: [],
            transition: nil,
            suggestedHook: nil
        )

        let data = try CreatorFirestoreCoder.encode(scene)
        try await sceneRef.setData(data)
        return scene
    }

    func updateScene(sceneID: String, fields: [String: Any]) async throws {
        let ownerID = try requireOwnerID()
        try await db.collection("users")
            .document(ownerID)
            .collection("creatorScenes")
            .document(sceneID)
            .updateData(fields)
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else {
            throw CreatorServiceError.notFound
        }
        return ownerID
    }
}
