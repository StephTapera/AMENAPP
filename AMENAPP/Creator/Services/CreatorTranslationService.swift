import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorTranslationServicing {
    func translate(track: CreatorSubtitleTrack, targetLanguage: String) async throws -> CreatorSubtitleTrack
}

final class CreatorTranslationService: CreatorTranslationServicing {
    private lazy var db = Firestore.firestore()

    func translate(track: CreatorSubtitleTrack, targetLanguage: String) async throws -> CreatorSubtitleTrack {
        let ownerID = try requireOwnerID()
        let trackRef = db.collection("users")
            .document(ownerID)
            .collection("creatorSubtitleTracks")
            .document()

        let translated = CreatorSubtitleTrack(
            id: trackRef.documentID,
            projectID: track.projectID,
            languageCode: targetLanguage,
            style: track.style,
            segments: track.segments,
            createdAt: Date()
        )

        let data = try CreatorFirestoreCoder.encode(translated)
        try await trackRef.setData(data)
        return translated
    }

    private func requireOwnerID() throws -> String {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else {
            throw CreatorServiceError.notFound
        }
        return ownerID
    }
}
