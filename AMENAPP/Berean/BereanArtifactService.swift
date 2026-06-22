// BereanArtifactService.swift
// AMENAPP — Berean Intelligence OS
//
// Manages BereanArtifactModel documents in Firestore.
// Firestore path: users/{uid}/bereanArtifacts/{artifactId}
//
// All reads and writes are isolated to the authenticated user's
// own sub-collection — no cross-user access is permitted.
// shareScope is user-controlled; Firestore rules enforce the boundary.

import Foundation
import FirebaseFirestore

// MARK: - Service

@MainActor
final class BereanArtifactService: ObservableObject {
    static let shared = BereanArtifactService()

    @Published var artifacts: [BereanArtifactModel] = []

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Firestore Path

    private func artifactsCollection(uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("bereanArtifacts")
    }

    // MARK: - Fetch

    /// Loads all artifacts for the given user and updates `artifacts`.
    func fetchArtifacts(uid: String) async {
        do {
            let snapshot = try await artifactsCollection(uid: uid)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            artifacts = snapshot.documents.compactMap { decode($0) }
        } catch {
            // Surface load errors silently; artifacts retains its previous value.
        }
    }

    // MARK: - Create

    /// Creates a new artifact document in Firestore and appends it to `artifacts`.
    @discardableResult
    func createArtifact(
        uid: String,
        kind: BereanArtifactModel.Kind,
        title: String,
        shareScope: String = "private"
    ) async throws -> BereanArtifactModel {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        let data: [String: Any] = [
            "id": id,
            "kind": kind.rawValue,
            "title": title,
            "shareScope": shareScope,
            "ownerUid": uid,
            "createdAt": now
        ]
        try await artifactsCollection(uid: uid).document(id).setData(data)
        let model = BereanArtifactModel(
            id: id,
            kind: kind,
            title: title,
            shareScope: shareScope,
            ownerUid: uid,
            createdAt: now
        )
        artifacts.insert(model, at: 0)
        return model
    }

    // MARK: - Update

    /// Updates the shareScope of an artifact both in Firestore and in the local `artifacts` array.
    func updateShareScope(
        artifact: BereanArtifactModel,
        newScope: String,
        uid: String
    ) async throws {
        try await artifactsCollection(uid: uid)
            .document(artifact.id)
            .updateData(["shareScope": newScope])
        if let idx = artifacts.firstIndex(where: { $0.id == artifact.id }) {
            artifacts[idx].shareScope = newScope
        }
    }

    // MARK: - Delete

    /// Deletes an artifact document and removes it from the local `artifacts` array.
    func deleteArtifact(id: String, uid: String) async throws {
        try await artifactsCollection(uid: uid).document(id).delete()
        artifacts.removeAll { $0.id == id }
    }

    // MARK: - Private helpers

    private func decode(_ document: QueryDocumentSnapshot) -> BereanArtifactModel? {
        // Try Codable path first.
        if let model = try? Firestore.Decoder().decode(BereanArtifactModel.self, from: document.data()) {
            return model
        }
        // Manual fallback to guard against minor schema drifts.
        let d = document.data()
        guard
            let id         = d["id"] as? String,
            let kindRaw    = d["kind"] as? String,
            let kind       = BereanArtifactModel.Kind(rawValue: kindRaw),
            let title      = d["title"] as? String,
            let shareScope = d["shareScope"] as? String,
            let ownerUid   = d["ownerUid"] as? String,
            let createdAt  = d["createdAt"] as? TimeInterval
        else { return nil }
        return BereanArtifactModel(
            id: id,
            kind: kind,
            title: title,
            shareScope: shareScope,
            ownerUid: ownerUid,
            createdAt: createdAt
        )
    }
}

