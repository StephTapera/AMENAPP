import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorExportServicing {
    func buildOutputVariants(projectID: String) async throws -> CreatorProcessingJob
    func renderExport(projectID: String, preset: CreatorExportPreset) async throws -> CreatorProcessingJob
}

final class CreatorExportService: CreatorExportServicing {
    private lazy var db = Firestore.firestore()

    func buildOutputVariants(projectID: String) async throws -> CreatorProcessingJob {
        try await createJob(projectID: projectID, type: .exportRender)
    }

    func renderExport(projectID: String, preset: CreatorExportPreset) async throws -> CreatorProcessingJob {
        try await createJob(projectID: projectID, type: .exportRender)
    }

    private func createJob(projectID: String, type: CreatorJobType) async throws -> CreatorProcessingJob {
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
            inputRefs: [],
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
