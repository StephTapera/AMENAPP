import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorJobServicing {
    func listenJobs(projectID: String, onUpdate: @escaping ([CreatorProcessingJob]) -> Void) throws -> ListenerRegistration
}

final class CreatorJobService: CreatorJobServicing {
    private let db = Firestore.firestore()

    func listenJobs(projectID: String, onUpdate: @escaping ([CreatorProcessingJob]) -> Void) throws -> ListenerRegistration {
        let ownerID = try requireOwnerID()
        return db.collection("users")
            .document(ownerID)
            .collection("creatorJobs")
            .whereField("projectID", isEqualTo: projectID)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                let jobs: [CreatorProcessingJob] = snapshot.documents.compactMap { document in
                    let data = document.data()
                    return try? CreatorFirestoreCoder.decode(CreatorProcessingJob.self, from: data)
                }
                onUpdate(jobs.sorted { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) })
            }
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else {
            throw CreatorServiceError.notFound
        }
        return ownerID
    }
}
