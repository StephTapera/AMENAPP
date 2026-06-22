//
//  SelahNoteService.swift
//  AMENAPP
//
//  Firestore + Cloud Functions bridge for the user's personal scripture note
//  corpus (SelahNote).
//
//  Firestore schema (from selah.contracts.ts §3):
//    users/{uid}/selahNotes/{noteId}
//
//  CF callable: "indexSelahNote"
//  HARD CONTRACT: `translationRead` is NEVER included in any CF call payload.
//  Soft-delete only: `softDeleteNote` sets `deletedAt`; it never calls
//  `document.delete()`.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - SelahNoteError

enum SelahNoteError: LocalizedError {
    case notAuthenticated
    case invalidNoteKind
    case firestoreWriteFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to manage scripture notes."
        case .invalidNoteKind:
            return "The note kind is not valid."
        case .firestoreWriteFailed(let underlying):
            return "Could not save note: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - SelahNoteService

/// Singleton service for create / update / soft-delete / fetch of SelahNotes.
///
/// All methods require an authenticated user; they throw `.notAuthenticated`
/// if `Auth.auth().currentUser` is nil or has an empty uid.
///
/// Published state (`notes`) is keyed by `verseRef` so UI can efficiently
/// show per-verse annotations.
@MainActor
final class SelahNoteService: ObservableObject {

    // MARK: Singleton

    static let shared = SelahNoteService()
    private init() {}

    // MARK: Published State

    /// Active notes grouped by verseRef. Only active (non-deleted) notes appear.
    @Published var notes: [String: [SelahNote]] = [:]

    // MARK: Private Dependencies

    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions(region: "us-central1")

    // MARK: - Auth Guard

    /// Returns the authenticated uid or throws `.notAuthenticated`.
    private func requireUID() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw SelahNoteError.notAuthenticated
        }
        return uid
    }

    // MARK: - Firestore Path

    /// Collection reference for this user's selahNotes subcollection.
    private func notesCollection(uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("selahNotes")
    }

    // MARK: - Create

    /// Persist a new note to Firestore, update the local cache, and async-
    /// index it via the `indexSelahNote` Cloud Function.
    ///
    /// - Parameter note: A `SelahNote` created with `SelahNote.new(...)`.
    func createNote(_ note: SelahNote) async throws {
        let uid = try requireUID()
        guard uid == note.userId else { throw SelahNoteError.notAuthenticated }

        let docRef = notesCollection(uid: uid).document(note.id)
        do {
            try docRef.setData(from: note, merge: false)
        } catch {
            throw SelahNoteError.firestoreWriteFailed(error)
        }

        // Update local cache immediately so UI reflects the new note.
        updateLocalCache(with: note)

        // Async CF indexing — fire and forget; local save already succeeded.
        Task {
            await indexNote(note)
        }
    }

    // MARK: - Update

    /// Update an existing note in Firestore (sets updatedAt to now),
    /// refresh the local cache, and re-index via CF.
    func updateNote(_ note: SelahNote) async throws {
        let uid = try requireUID()
        guard uid == note.userId else { throw SelahNoteError.notAuthenticated }

        var updated = note
        updated.updatedAt = Date().timeIntervalSince1970

        let docRef = notesCollection(uid: uid).document(updated.id)
        do {
            try docRef.setData(from: updated, merge: true)
        } catch {
            throw SelahNoteError.firestoreWriteFailed(error)
        }

        updateLocalCache(with: updated)

        Task {
            await indexNote(updated)
        }
    }

    // MARK: - Soft Delete

    /// Soft-delete a note by writing `deletedAt` to the current timestamp.
    ///
    /// HARD INVARIANT: This method NEVER calls `document.delete()`.
    /// The Firestore document persists; only `deletedAt` is set.
    /// The CF is called with `deletedAt` set so Pinecone removes the vector.
    func softDeleteNote(id: String, userId: String) async throws {
        let uid = try requireUID()
        guard uid == userId else { throw SelahNoteError.notAuthenticated }

        let docRef = notesCollection(uid: uid).document(id)

        // Fetch current document to build the full updated note for CF indexing.
        let snapshot: DocumentSnapshot
        do {
            snapshot = try await docRef.getDocument()
        } catch {
            throw SelahNoteError.firestoreWriteFailed(error)
        }

        guard snapshot.exists else { return } // Already gone — no-op.

        let deletedAt = Date().timeIntervalSince1970

        // Write only the soft-delete fields — never delete the document.
        do {
            try await docRef.updateData([
                "deletedAt": deletedAt,
                "updatedAt": deletedAt
            ])
        } catch {
            throw SelahNoteError.firestoreWriteFailed(error)
        }

        // Remove from local cache.
        removeFromLocalCache(id: id)

        // Tell Pinecone to remove the vector by sending deletedAt in the payload.
        if var note = try? snapshot.data(as: SelahNote.self) {
            note.deletedAt = deletedAt
            note.updatedAt = deletedAt
            Task {
                await indexNote(note)
            }
        }
    }

    // MARK: - Fetch (single verse)

    /// Fetch active notes for a specific verse reference.
    /// Updates the local cache and returns notes sorted by `createdAt` ascending.
    @discardableResult
    func fetchNotes(for verseRef: String, userId: String) async throws -> [SelahNote] {
        let uid = try requireUID()
        guard uid == userId else { throw SelahNoteError.notAuthenticated }

        let query = notesCollection(uid: uid)
            .whereField("verseRef", isEqualTo: verseRef)
            .whereField("deletedAt", isEqualTo: NSNull())

        let snapshot: QuerySnapshot
        do {
            snapshot = try await query.getDocuments()
        } catch {
            throw SelahNoteError.firestoreWriteFailed(error)
        }

        let fetched: [SelahNote] = snapshot.documents.compactMap {
            try? $0.data(as: SelahNote.self)
        }
        .filter { $0.deletedAt == nil }
        .sorted { $0.createdAt < $1.createdAt }

        // Update cache for this specific verseRef.
        notes[verseRef] = fetched

        return fetched
    }

    // MARK: - Fetch (all)

    /// Fetch all active notes for the authenticated user, grouped by verseRef.
    /// Replaces the full local cache with the server result.
    @discardableResult
    func fetchAllNotes(userId: String) async throws -> [String: [SelahNote]] {
        let uid = try requireUID()
        guard uid == userId else { throw SelahNoteError.notAuthenticated }

        let query = notesCollection(uid: uid)
            .whereField("deletedAt", isEqualTo: NSNull())

        let snapshot: QuerySnapshot
        do {
            snapshot = try await query.getDocuments()
        } catch {
            throw SelahNoteError.firestoreWriteFailed(error)
        }

        let allActive: [SelahNote] = snapshot.documents.compactMap {
            try? $0.data(as: SelahNote.self)
        }
        .filter { $0.deletedAt == nil }

        // Group by verseRef, sort each group by createdAt.
        var grouped: [String: [SelahNote]] = [:]
        for note in allActive {
            grouped[note.verseRef, default: []].append(note)
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.createdAt < $1.createdAt }
        }

        notes = grouped
        return grouped
    }

    // MARK: - Private: Local Cache Helpers

    private func updateLocalCache(with note: SelahNote) {
        guard note.deletedAt == nil else {
            removeFromLocalCache(id: note.id)
            return
        }
        var bucket = notes[note.verseRef] ?? []
        if let idx = bucket.firstIndex(where: { $0.id == note.id }) {
            bucket[idx] = note
        } else {
            bucket.append(note)
        }
        bucket.sort { $0.createdAt < $1.createdAt }
        notes[note.verseRef] = bucket
    }

    private func removeFromLocalCache(id: String) {
        for key in notes.keys {
            notes[key]?.removeAll { $0.id == id }
            if notes[key]?.isEmpty == true {
                notes.removeValue(forKey: key)
            }
        }
    }

    // MARK: - Private: CF Indexing

    /// Call the `indexSelahNote` Cloud Function.
    ///
    /// HARD CONTRACT: `translationRead` is NEVER included in the payload.
    /// If the CF call fails, the error is logged but NOT rethrown — the local
    /// Firestore write has already succeeded and indexing can retry later.
    private func indexNote(_ note: SelahNote) async {
        // Build payload — explicitly omit translationRead per contract.
        var payload: [String: Any] = [
            "noteId":    note.id,
            "verseRef":  note.verseRef,
            "kind":      note.kind.rawValue,
            "createdAt": note.createdAt,
            "deletedAt": note.deletedAt as Any   // NSNull when nil → signals active to CF
        ]
        if let body = note.body    { payload["body"]  = body }
        if let color = note.color  { payload["color"] = color }

        // Firestore encodes nil as NSNull; make sure deletedAt is explicitly null
        // when the note is active so the CF can distinguish active vs. deleted.
        if note.deletedAt == nil {
            payload["deletedAt"] = NSNull()
        }

        do {
            _ = try await functions.httpsCallable("indexSelahNote").call(payload)
        } catch {
            // Index failure is non-fatal: local save succeeded; Pinecone sync
            // can be retried on next update. Log and continue.
            print("[SelahNoteService] indexSelahNote CF failed (non-fatal): \(error.localizedDescription)")
        }
    }
}
