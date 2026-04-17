import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorPublishServicing {
    func publish(projectID: String, targets: [CreatorPublishTarget]) async throws -> CreatorProcessingJob
}

final class CreatorPublishService: CreatorPublishServicing {
    private lazy var db = Firestore.firestore()

    func publish(projectID: String, targets: [CreatorPublishTarget]) async throws -> CreatorProcessingJob {
        let ownerID = try requireOwnerID()
        let projectRef = db.collection("users")
            .document(ownerID)
            .collection("creatorProjects")
            .document(projectID)

        try await projectRef.setData([
            "status": CreatorProjectStatus.published.rawValue,
            "publishedAt": Date()
        ], merge: true)

        let jobRef = db.collection("users")
            .document(ownerID)
            .collection("creatorJobs")
            .document()

        let job = CreatorProcessingJob(
            id: jobRef.documentID,
            projectID: projectID,
            ownerID: ownerID,
            type: .publish,
            status: .completed,
            progress: 1,
            inputRefs: [],
            outputRefs: [],
            outputStoragePath: nil,
            startedAt: nil,
            finishedAt: Date(),
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
