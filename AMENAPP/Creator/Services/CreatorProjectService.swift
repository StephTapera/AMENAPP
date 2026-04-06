import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorProjectServicing {
    func createProject(title: String, type: CreatorProjectType) async throws -> CreatorProject
    func fetchProject(projectID: String) async throws -> CreatorProject
    func updateProject(_ project: CreatorProject) async throws
    func deleteProject(projectID: String) async throws
    func listProjects(ownerID: String) async throws -> [CreatorProject]
}

final class CreatorProjectService: CreatorProjectServicing {
    private let db = Firestore.firestore()

    func createProject(title: String, type: CreatorProjectType) async throws -> CreatorProject {
        let ownerID = try requireOwnerID()
        let projectRef = db.collection("users").document(ownerID).collection("creatorProjects").document()
        let now = Date()
        let project = CreatorProject(
            id: projectRef.documentID,
            ownerID: ownerID,
            title: title,
            projectType: type,
            status: .draft,
            visibility: .private,
            thumbnailURL: nil,
            aspectRatio: .portrait,
            assetIDs: [],
            layerIDs: [],
            sceneIDs: [],
            subtitleTrackIDs: [],
            templateID: nil,
            brandKitID: nil,
            coverAssetID: nil,
            coverImageURL: nil,
            coverFrameTimeMs: nil,
            outputVariants: [],
            publishTargets: [],
            autosaveVersion: 0,
            lastEditedAt: now,
            createdAt: now,
            publishedAt: nil,
            sourceContext: nil,
            premiumRequired: false
        )

        let data = try CreatorFirestoreCoder.encode(project)
        try await projectRef.setData(data)
        return project
    }

    func fetchProject(projectID: String) async throws -> CreatorProject {
        let ownerID = try requireOwnerID()
        let snapshot = try await db.collection("users")
            .document(ownerID)
            .collection("creatorProjects")
            .document(projectID)
            .getDocument()

        guard let data = snapshot.data() else {
            throw CreatorServiceError.notFound
        }
        return try CreatorFirestoreCoder.decode(CreatorProject.self, from: data)
    }

    func updateProject(_ project: CreatorProject) async throws {
        let ownerID = try requireOwnerID()
        let projectRef = db.collection("users")
            .document(ownerID)
            .collection("creatorProjects")
            .document(project.id)

        let data = try CreatorFirestoreCoder.encode(project)
        try await projectRef.setData(data, merge: true)
    }

    func deleteProject(projectID: String) async throws {
        let ownerID = try requireOwnerID()
        try await db.collection("users")
            .document(ownerID)
            .collection("creatorProjects")
            .document(projectID)
            .delete()
    }

    func listProjects(ownerID: String) async throws -> [CreatorProject] {
        let snapshot = try await db.collection("users")
            .document(ownerID)
            .collection("creatorProjects")
            .order(by: "lastEditedAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            guard let data = document.data() as [String: Any]? else { return nil }
            return try? CreatorFirestoreCoder.decode(CreatorProject.self, from: data)
        }
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else {
            throw CreatorServiceError.notFound
        }
        return ownerID
    }
}
