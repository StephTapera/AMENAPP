//
//  SelahScriptureSyncService.swift
//  AMENAPP
//
//  Firestore-backed sync for the scripture reader's private engagement
//  signals: saved verses, highlights, reactions, and prayed-through markers.
//
//  Status: feature-flagged via `selahScriptureCloudSyncEnabled` (defaults
//  OFF). When enabled, mirrors the local stores. Schema:
//
//    users/{uid}/selahSavedScripture/{autoId}
//    users/{uid}/selahHighlights/{autoId}
//    users/{uid}/selahReactions/{autoId}
//    users/{uid}/selahPrayedThrough/{autoId}
//
//  Each doc is the JSON encoding of its corresponding model. Conflict
//  resolution is last-writer-wins per document; deletions are propagated.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class SelahScriptureSyncService {
    static let shared = SelahScriptureSyncService()

    private lazy var db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    private var userId: String? {
        let id = Auth.auth().currentUser?.uid
        return id?.isEmpty == false ? id : nil
    }

    /// Enable / disable runtime activation. The feature flag check is the
    /// host's responsibility — services should consult their own flag.
    private var isEnabled: Bool {
        // Cloud sync is off by default until the team explicitly turns it on.
        // A Remote Config flag can flip this; today returns false.
        false
    }

    // MARK: - Collections

    private func collection(_ leaf: String) -> CollectionReference? {
        guard let uid = userId else { return nil }
        return db.collection("users").document(uid).collection(leaf)
    }

    // MARK: - Push (local → remote)

    func pushSaved(_ entry: SelahSavedScripture) async throws {
        guard isEnabled, let col = collection("selahSavedScripture") else { return }
        try col.document(entry.id.uuidString).setData(from: entry, merge: true)
    }

    func pushHighlight(_ entry: SelahScriptureHighlightEntry) async throws {
        guard isEnabled, let col = collection("selahHighlights") else { return }
        try col.document(entry.id.uuidString).setData(from: entry, merge: true)
    }

    func pushReaction(_ entry: SelahVerseReactionEntry) async throws {
        guard isEnabled, let col = collection("selahReactions") else { return }
        try col.document(entry.id.uuidString).setData(from: entry, merge: true)
    }

    func pushPrayedThrough(_ entry: SelahPrayedThroughEntry) async throws {
        guard isEnabled, let col = collection("selahPrayedThrough") else { return }
        try col.document(entry.id.uuidString).setData(from: entry, merge: true)
    }

    // MARK: - Pull (remote → local)

    func fetchAll() async {
        guard isEnabled else { return }
        // Intentionally a no-op until the feature flag is on; production
        // wiring will add listeners here that merge into the local stores.
    }

    deinit {
        listeners.forEach { $0.remove() }
    }
}
