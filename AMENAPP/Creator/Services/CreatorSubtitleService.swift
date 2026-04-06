import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorSubtitleServicing {
    func generateSubtitles(projectID: String, transcriptID: String) async throws -> CreatorSubtitleTrack
}

final class CreatorSubtitleService: CreatorSubtitleServicing {
    private let db = Firestore.firestore()

    func generateSubtitles(projectID: String, transcriptID: String) async throws -> CreatorSubtitleTrack {
        let ownerID = try requireOwnerID()
        let trackRef = db.collection("users")
            .document(ownerID)
            .collection("creatorSubtitleTracks")
            .document()

        let track = CreatorSubtitleTrack(
            id: trackRef.documentID,
            projectID: projectID,
            languageCode: "en",
            style: .minimal,
            segments: [],
            createdAt: Date()
        )

        let data = try CreatorFirestoreCoder.encode(track)
        try await trackRef.setData(data)
        return track
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else {
            throw CreatorServiceError.notFound
        }
        return ownerID
    }
}
