import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorTranscriptionServicing {
    func transcribe(assetID: String, projectID: String) async throws -> CreatorProcessingJob
}

final class CreatorTranscriptionService: CreatorTranscriptionServicing {
    private let db = Firestore.firestore()

    func transcribe(assetID: String, projectID: String) async throws -> CreatorProcessingJob {
        let ownerID = try requireOwnerID()
        let jobRef = db.collection("users")
            .document(ownerID)
            .collection("creatorJobs")
            .document()

        let job = CreatorProcessingJob(
            id: jobRef.documentID,
            projectID: projectID,
            ownerID: ownerID,
            type: .transcription,
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
