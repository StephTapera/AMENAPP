// BereanWorkspaceService.swift
// AMENAPP — Berean Intelligence OS
//
// Manages BereanWorkspaceModel documents in Firestore.
// Firestore path: users/{uid}/bereanWorkspaces/{workspaceId}
//
// All reads and writes are isolated to the authenticated user's
// own sub-collection — no cross-user access is permitted.

import Foundation
import FirebaseFirestore

// MARK: - Service

@MainActor
final class BereanWorkspaceService: ObservableObject {
    static let shared = BereanWorkspaceService()

    @Published var workspaces: [BereanWorkspaceModel] = []

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Firestore Path

    private func workspacesCollection(uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("bereanWorkspaces")
    }

    // MARK: - Fetch

    /// Loads all workspaces for the given user and updates `workspaces`.
    func fetchWorkspaces(uid: String) async {
        do {
            let snapshot = try await workspacesCollection(uid: uid)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            workspaces = snapshot.documents.compactMap { decode($0) }
        } catch {
            // Surface load errors silently; workspaces retains its previous value.
        }
    }

    // MARK: - Create

    /// Creates a new workspace document in Firestore and appends it to `workspaces`.
    @discardableResult
    func createWorkspace(
        uid: String,
        kind: BereanWorkspaceModel.Kind,
        title: String
    ) async throws -> BereanWorkspaceModel {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        let data: [String: Any] = [
            "id": id,
            "ownerUid": uid,
            "kind": kind.rawValue,
            "title": title,
            "items": [String](),
            "createdAt": now
        ]
        try await workspacesCollection(uid: uid).document(id).setData(data)
        let model = BereanWorkspaceModel(
            id: id,
            ownerUid: uid,
            kind: kind,
            title: title,
            items: [],
            createdAt: now
        )
        workspaces.insert(model, at: 0)
        return model
    }

    // MARK: - Update

    /// Renames a workspace both in Firestore and in the local `workspaces` array.
    func updateTitle(
        workspace: BereanWorkspaceModel,
        newTitle: String,
        uid: String
    ) async throws {
        try await workspacesCollection(uid: uid)
            .document(workspace.id)
            .updateData(["title": newTitle])
        if let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[idx].title = newTitle
        }
    }

    // MARK: - Delete

    /// Deletes a workspace document and removes it from the local `workspaces` array.
    func deleteWorkspace(id: String, uid: String) async throws {
        try await workspacesCollection(uid: uid).document(id).delete()
        workspaces.removeAll { $0.id == id }
    }

    // MARK: - Private helpers

    private func decode(_ document: QueryDocumentSnapshot) -> BereanWorkspaceModel? {
        // Try Codable path first.
        if let model = try? Firestore.Decoder().decode(BereanWorkspaceModel.self, from: document.data()) {
            return model
        }
        // Manual fallback to guard against minor schema drifts.
        let d = document.data()
        guard
            let id       = d["id"] as? String,
            let owner    = d["ownerUid"] as? String,
            let kindRaw  = d["kind"] as? String,
            let kind     = BereanWorkspaceModel.Kind(rawValue: kindRaw),
            let title    = d["title"] as? String,
            let createdAt = d["createdAt"] as? TimeInterval
        else { return nil }
        let items = d["items"] as? [String] ?? []
        return BereanWorkspaceModel(
            id: id,
            ownerUid: owner,
            kind: kind,
            title: title,
            items: items,
            createdAt: createdAt
        )
    }
}

// MARK: - BereanWorkspaceModel memberwise init extension
// The synthesised Codable init is internal; this private extension exposes
// a restore-from-Firestore path that preserves the stored id and createdAt.

private extension BereanWorkspaceModel {
    init(id: String, ownerUid: String, kind: Kind, title: String,
         items: [String], createdAt: TimeInterval) {
        self.id        = id
        self.ownerUid  = ownerUid
        self.kind      = kind
        self.title     = title
        self.items     = items
        self.createdAt = createdAt
    }
}
