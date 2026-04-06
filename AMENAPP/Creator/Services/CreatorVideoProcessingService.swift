import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

protocol CreatorVideoProcessingServicing {
    func createProxy(for asset: CreatorAsset) async throws -> CreatorProcessingJob
    func generateThumbnail(for asset: CreatorAsset) async throws -> CreatorProcessingJob
}

final class CreatorVideoProcessingService: CreatorVideoProcessingServicing {
    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    func createProxy(for asset: CreatorAsset) async throws -> CreatorProcessingJob {
        let job = try await createJob(projectID: asset.projectID, assetID: asset.id, type: .proxy)
        let outputStoragePath = "creator/users/\(job.ownerID)/projects/\(asset.projectID)/assets/proxies/\(asset.id).mov"
        _ = try? await functions.httpsCallable("processVideoProxy").call([
            "jobID": job.id,
            "sourceStoragePath": asset.storagePath ?? "",
            "outputStoragePath": outputStoragePath
        ])
        return job
    }

    func generateThumbnail(for asset: CreatorAsset) async throws -> CreatorProcessingJob {
        let job = try await createJob(projectID: asset.projectID, assetID: asset.id, type: .thumbnail)
        let outputStoragePath = "creator/users/\(job.ownerID)/projects/\(asset.projectID)/thumbnails/\(asset.id).jpg"
        _ = try? await functions.httpsCallable("generateThumbnail").call([
            "jobID": job.id,
            "sourceStoragePath": asset.storagePath ?? "",
            "outputStoragePath": outputStoragePath
        ])
        return job
    }

    private func createJob(projectID: String, assetID: String, type: CreatorJobType) async throws -> CreatorProcessingJob {
        let ownerID = try requireOwnerID()
        let jobRef = db.collection("users")
            .document(ownerID)
            .collection("creatorJobs")
            .document()

        let job = CreatorProcessingJob(
            id: jobRef.documentID,
            projectID: projectID,
            ownerID: ownerID,
            type: type,
            status: .queued,
            progress: 0,
            inputRefs: [assetID],
            outputRefs: [],
            outputStoragePath: nil,
            startedAt: nil,
            finishedAt: nil,
            createdAt: Date(),
            errorCode: nil,
            errorMessage: nil,
            retryCount: 0
        )

        let data = try CreatorFirestoreCoder.encode(job)
        try await jobRef.setData(data)
        return job
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else {
            throw CreatorServiceError.notFound
        }
        return ownerID
    }
}
