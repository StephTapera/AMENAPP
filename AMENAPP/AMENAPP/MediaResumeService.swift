// MediaResumeService.swift
// AMENAPP
//
// Firestore CRUD for persisting media playback positions
// across sessions. Collection: users/{uid}/mediaResumeState/{compositeId}

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class MediaResumeService {

    static let shared = MediaResumeService()

    private lazy var db = Firestore.firestore()

    private init() {}

    // MARK: - Collection Path

    private func collectionRef(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("mediaResumeState")
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - Save

    func save(_ state: MediaPlaybackState) async {
        guard let uid = currentUserId else { return }
        do {
            try await collectionRef(for: uid).document(state.firestoreDocId).setData([
                "postId": state.postId,
                "mediaItemId": state.mediaItemId,
                "positionSeconds": state.positionSeconds,
                "durationSeconds": state.durationSeconds,
                "completed": state.completed,
                "lastPlayedAt": FieldValue.serverTimestamp(),
            ], merge: true)
        } catch {
            dlog("[MediaResume] Save error: \(error)")
        }
    }

    // MARK: - Load

    func load(postId: String, mediaItemId: String) async -> MediaPlaybackState? {
        guard let uid = currentUserId else { return nil }
        let docId = "\(postId)_\(mediaItemId)"
        do {
            let doc = try await collectionRef(for: uid).document(docId).getDocument()
            guard let data = doc.data() else { return nil }
            return parseState(data: data, docId: docId)
        } catch {
            dlog("[MediaResume] Load error: \(error)")
            return nil
        }
    }

    func loadRecent(limit: Int = 50) async -> [MediaPlaybackState] {
        guard let uid = currentUserId else { return [] }
        do {
            let snap = try await collectionRef(for: uid)
                .whereField("completed", isEqualTo: false)
                .order(by: "lastPlayedAt", descending: true)
                .limit(to: limit)
                .getDocuments()

            return snap.documents.compactMap { doc in
                parseState(data: doc.data(), docId: doc.documentID)
            }
        } catch {
            dlog("[MediaResume] LoadRecent error: \(error)")
            return []
        }
    }

    // MARK: - Delete

    func markCompleted(postId: String, mediaItemId: String) async {
        guard let uid = currentUserId else { return }
        let docId = "\(postId)_\(mediaItemId)"
        do {
            try await collectionRef(for: uid).document(docId).updateData([
                "completed": true,
                "lastPlayedAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            dlog("[MediaResume] MarkCompleted error: \(error)")
        }
    }

    // MARK: - Parse

    private func parseState(data: [String: Any], docId: String) -> MediaPlaybackState? {
        guard let postId = data["postId"] as? String,
              let mediaItemId = data["mediaItemId"] as? String else { return nil }

        let position = data["positionSeconds"] as? Double ?? 0
        let duration = data["durationSeconds"] as? Double ?? 0
        let completed = data["completed"] as? Bool ?? false
        let lastPlayed = (data["lastPlayedAt"] as? Timestamp)?.dateValue() ?? Date()

        return MediaPlaybackState(
            postId: postId,
            mediaItemId: mediaItemId,
            positionSeconds: position,
            durationSeconds: duration,
            completed: completed,
            lastPlayedAt: lastPlayed
        )
    }
}
