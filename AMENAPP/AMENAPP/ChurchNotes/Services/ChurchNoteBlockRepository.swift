// ChurchNoteBlockRepository.swift
// AMENAPP
//
// Firestore repository for the semantic Church Notes system.
//   - `churchNotes/{noteId}`           — top-level ChurchNoteV2 documents
//   - `churchNotes/{noteId}/blocks/{blockId}` — ChurchNoteBlockV2 subcollection
//
// All writes go through this service. Views use the published arrays.
// Block export (for post card / AI) respects visibility rules.

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ChurchNoteBlockRepository: ObservableObject {

    static let shared = ChurchNoteBlockRepository()

    @Published private(set) var notes: [ChurchNoteV2] = []
    @Published private(set) var activeBlocks: [ChurchNoteBlockV2] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private var notesListener: ListenerRegistration?
    private var blocksListener: ListenerRegistration?
    private var activeNoteId: String?

    private init() {}

    // MARK: - Notes List

    func startListeningToNotes() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        notesListener?.remove()
        notesListener = db
            .collection("churchNotes")
            .whereField("userId", isEqualTo: uid)
            .whereField("schemaVersion", isEqualTo: 2)
            .order(by: "updatedAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                isLoading = false
                guard let docs = snapshot?.documents else { return }
                notes = docs.compactMap { try? $0.data(as: ChurchNoteV2.self) }
            }
    }

    func stopListeningToNotes() {
        notesListener?.remove()
        notesListener = nil
    }

    // MARK: - Blocks for a specific note

    func startListeningToBlocks(noteId: String) {
        guard activeNoteId != noteId else { return }
        activeNoteId = noteId
        blocksListener?.remove()
        blocksListener = db
            .collection("churchNotes").document(noteId)
            .collection("blocks")
            .order(by: "sortOrder")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                activeBlocks = docs
                    .compactMap { try? $0.data(as: ChurchNoteBlockV2.self) }
                    .sorted { $0.sortOrder < $1.sortOrder }
            }
    }

    func stopListeningToBlocks() {
        blocksListener?.remove()
        blocksListener = nil
        activeNoteId = nil
        activeBlocks = []
    }

    // MARK: - Create note

    func createNote(_ note: ChurchNoteV2) async throws {
        try db
            .collection("churchNotes")
            .document(note.id)
            .setData(from: note)
    }

    // MARK: - Update note metadata

    func updateNoteMetadata(
        noteId: String,
        title: String,
        sermonTitle: String?,
        sermonSpeaker: String?,
        tags: [String],
        scriptureReferences: [String]
    ) async throws {
        var update: [String: Any] = [
            "title": title,
            "tags": tags,
            "scriptureReferences": scriptureReferences,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        update["sermonTitle"] = sermonTitle as Any
        update["sermonSpeaker"] = sermonSpeaker as Any
        try await db
            .collection("churchNotes").document(noteId)
            .updateData(update)
    }

    // MARK: - Block CRUD

    func addBlock(_ block: ChurchNoteBlockV2, to noteId: String) async throws {
        try db
            .collection("churchNotes").document(noteId)
            .collection("blocks").document(block.id)
            .setData(from: block)
        try await incrementBlockCount(noteId: noteId, by: 1)
    }

    func updateBlock(_ block: ChurchNoteBlockV2, in noteId: String) async throws {
        var updated = block
        updated = ChurchNoteBlockV2(
            id: block.id,
            sortOrder: block.sortOrder,
            type: block.type,
            semanticType: block.semanticType,
            visibility: block.visibility,
            pinnedState: block.pinnedState,
            text: block.text,
            richSpans: block.richSpans,
            versePayload: block.versePayload,
            calloutPayload: block.calloutPayload,
            sectionPayload: block.sectionPayload,
            checklistPayload: block.checklistPayload,
            createdAt: block.createdAt,
            updatedAt: Date()
        )
        try db
            .collection("churchNotes").document(noteId)
            .collection("blocks").document(block.id)
            .setData(from: updated, merge: true)
        // Update denormalized hasShareableBlocks flag
        try await refreshShareableFlag(noteId: noteId)
    }

    func deleteBlock(blockId: String, from noteId: String) async throws {
        try await db
            .collection("churchNotes").document(noteId)
            .collection("blocks").document(blockId)
            .delete()
        try await incrementBlockCount(noteId: noteId, by: -1)
        try await refreshShareableFlag(noteId: noteId)
    }

    func reorderBlocks(_ blocks: [ChurchNoteBlockV2], in noteId: String) async throws {
        let batch = db.batch()
        for (index, block) in blocks.enumerated() {
            let ref = db
                .collection("churchNotes").document(noteId)
                .collection("blocks").document(block.id)
            batch.updateData(["sortOrder": index], forDocument: ref)
        }
        try await batch.commit()
    }

    // MARK: - Visibility / Pinning

    func updateBlockVisibility(
        blockId: String,
        noteId: String,
        visibility: ChurchNoteVisibility
    ) async throws {
        try await db
            .collection("churchNotes").document(noteId)
            .collection("blocks").document(blockId)
            .updateData([
                "visibility": visibility.rawValue,
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        try await refreshShareableFlag(noteId: noteId)
    }

    func updateBlockPinnedState(
        blockId: String,
        noteId: String,
        pinnedState: ChurchNotePinnedState
    ) async throws {
        try await db
            .collection("churchNotes").document(noteId)
            .collection("blocks").document(blockId)
            .updateData([
                "pinnedState": pinnedState.rawValue,
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        try await refreshPinnedBlockIds(noteId: noteId)
    }

    // MARK: - Delete note

    func deleteNote(noteId: String) async throws {
        // Delete all blocks first
        let blockRefs = try await db
            .collection("churchNotes").document(noteId)
            .collection("blocks")
            .getDocuments()
        let batch = db.batch()
        for doc in blockRefs.documents {
            batch.deleteDocument(doc.reference)
        }
        batch.deleteDocument(db.collection("churchNotes").document(noteId))
        try await batch.commit()
    }

    // MARK: - Export: visibility-safe block payload

    /// Returns only blocks the user has explicitly marked shareable.
    /// Used by post card preview and share sheet. Never exposes .privateOnly blocks.
    func shareableBlocks(noteId: String) async -> [ChurchNoteBlockV2] {
        guard let snapshot = try? await db
            .collection("churchNotes").document(noteId)
            .collection("blocks")
            .whereField("visibility", in: [
                ChurchNoteVisibility.shareable.rawValue,
                ChurchNoteVisibility.selectedForPostPreview.rawValue,
            ])
            .order(by: "sortOrder")
            .getDocuments()
        else { return [] }
        return snapshot.documents
            .compactMap { try? $0.data(as: ChurchNoteBlockV2.self) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Returns only blocks marked for Selah emphasis, plus all non-private blocks.
    func selahBlocks(noteId: String) async -> [ChurchNoteBlockV2] {
        guard let snapshot = try? await db
            .collection("churchNotes").document(noteId)
            .collection("blocks")
            .order(by: "sortOrder")
            .getDocuments()
        else { return [] }
        return snapshot.documents
            .compactMap { try? $0.data(as: ChurchNoteBlockV2.self) }
            .filter { $0.visibility != .privateOnly || $0.visibility == .selectedForSelahEmphasis }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Structured export for AI summarization — plain text, semantic metadata, no private data.
    func aiExportPayload(noteId: String) async -> [String: Any] {
        let blocks = await selahBlocks(noteId: noteId)
        let blockData: [[String: Any]] = blocks.map { block in
            [
                "type": block.type.rawValue,
                "semanticType": block.semanticType.rawValue,
                "text": block.text,
                "visibility": block.visibility.rawValue,
                "pinnedState": block.pinnedState.rawValue,
            ]
        }
        return ["blocks": blockData, "noteId": noteId]
    }

    // MARK: - Private helpers

    private func incrementBlockCount(noteId: String, by delta: Int) async throws {
        try await db
            .collection("churchNotes").document(noteId)
            .updateData([
                "blockCount": FieldValue.increment(Int64(delta)),
                "updatedAt": FieldValue.serverTimestamp(),
            ])
    }

    private func refreshShareableFlag(noteId: String) async throws {
        let snapshot = try await db
            .collection("churchNotes").document(noteId)
            .collection("blocks")
            .whereField("visibility", in: [
                ChurchNoteVisibility.shareable.rawValue,
                ChurchNoteVisibility.selectedForPostPreview.rawValue,
            ])
            .limit(to: 1)
            .getDocuments()
        let hasShareable = !snapshot.documents.isEmpty
        try await db
            .collection("churchNotes").document(noteId)
            .updateData(["hasShareableBlocks": hasShareable])
    }

    private func refreshPinnedBlockIds(noteId: String) async throws {
        let snapshot = try await db
            .collection("churchNotes").document(noteId)
            .collection("blocks")
            .whereField("pinnedState", isNotEqualTo: ChurchNotePinnedState.none.rawValue)
            .order(by: "pinnedState")
            .order(by: "sortOrder")
            .getDocuments()
        let ids = snapshot.documents.map { $0.documentID }
        try await db
            .collection("churchNotes").document(noteId)
            .updateData([
                "pinnedBlockIds": ids,
                "updatedAt": FieldValue.serverTimestamp(),
            ])
    }
}
