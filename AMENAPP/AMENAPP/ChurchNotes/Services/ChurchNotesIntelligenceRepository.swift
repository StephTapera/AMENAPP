// ChurchNotesIntelligenceRepository.swift
// AMENAPP
//
// Firestore repository for the Church Notes intelligence layer.
// Manages subcollections:
//   churchNotes/{noteId}/reflections/{reflectionId}
//   churchNotes/{noteId}/bridge/main            (singleton per note)
//   userChurchNotesSummary/{userId}             (God Has Been Saying)
//
// All operations enforce ownership. No cross-user reads are possible.

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class ChurchNotesIntelligenceRepository: ObservableObject {

    static let shared = ChurchNotesIntelligenceRepository()

    @Published private(set) var reflections: [ChurchNoteReflection] = []
    @Published private(set) var bridge: CNSermonBridge?
    @Published private(set) var summary: ChurchNotesSummary?
    @Published private(set) var isLoadingSummary = false

    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-east1")
    private var reflectionsListener: ListenerRegistration?
    private var bridgeListener: ListenerRegistration?
    private var activeNoteId: String?

    private init() {}

    deinit {
        reflectionsListener?.remove()
        bridgeListener?.remove()
    }

    // MARK: - Reflections

    func startListeningToReflections(noteId: String) {
        guard activeNoteId != noteId else { return }
        activeNoteId = noteId
        reflectionsListener?.remove()
        reflectionsListener = db
            .collection("churchNotes").document(noteId)
            .collection("reflections")
            .order(by: "surfacedAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] (snapshot, _) in
                guard let self = self, let docs = snapshot?.documents else { return }
                // @Sendable closure implicitly ensured by escaping within addSnapshotListener
                self.reflections = docs.compactMap { try? $0.data(as: ChurchNoteReflection.self) }
            }
    }

    func stopListeningToReflections() {
        reflectionsListener?.remove()
        reflectionsListener = nil
        reflections = []
        activeNoteId = nil // Clear activeNoteId to avoid stale state
    }

    /// Save a reflection response to a note.
    func saveReflection(_ reflection: ChurchNoteReflection) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Ownership check: verify caller owns this note
        let noteRef = db.collection("churchNotes").document(reflection.noteId)
        let noteSnap = try await noteRef.getDocument()
        guard noteSnap.data()?["userId"] as? String == uid else {
            throw ChurchNotesIntelligenceError.notOwner
        }
        try db
            .collection("churchNotes").document(reflection.noteId)
            .collection("reflections").document(reflection.id)
            .setData(from: reflection)
    }

    /// Schedule a future reflection replay (writes a pending document).
    func scheduleReflectionReplay(noteId: String, afterDays: Int) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let surfaceDate = Calendar.current.date(byAdding: .day, value: afterDays, to: Date()) ?? Date()
        let reflection = ChurchNoteReflection(
            noteId: noteId,
            promptType: .boreAnyFruit,
            replayIntervalDays: afterDays,
            surfacedAt: surfaceDate
        )
        let noteRef = db.collection("churchNotes").document(noteId)
        let noteSnap = try await noteRef.getDocument()
        guard noteSnap.data()?["userId"] as? String == uid else {
            throw ChurchNotesIntelligenceError.notOwner
        }
        try db
            .collection("churchNotes").document(noteId)
            .collection("reflections").document(reflection.id)
            .setData(from: reflection)
    }

    /// Load reflections due for replay (surfacedAt <= now, no response yet).
    func loadPendingReplays() async -> [ChurchNoteReflection] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        // Query user's notes, then check reflections subcollection
        guard let notesSnap = try? await db
            .collection("churchNotes")
            .whereField("userId", isEqualTo: uid)
            .limit(to: 20)
            .getDocuments()
        else { return [] }

        var pending: [ChurchNoteReflection] = []
        for doc in notesSnap.documents {
            let noteId = doc.documentID
            guard let reflSnap = try? await db
                .collection("churchNotes").document(noteId)
                .collection("reflections")
                .whereField("surfacedAt", isLessThanOrEqualTo: Date())
                .whereField("responseText", isEqualTo: "")
                .limit(to: 2)
                .getDocuments()
            else { continue }
            let items = reflSnap.documents.compactMap { try? $0.data(as: ChurchNoteReflection.self) }
            pending.append(contentsOf: items)
        }
        return pending
    }

    // MARK: - Sermon Bridge

    func startListeningToBridge(noteId: String) {
        bridgeListener?.remove()
        bridgeListener = db
            .collection("churchNotes").document(noteId)
            .collection("bridge").document("main")
            .addSnapshotListener { [weak self] (snapshot, _) in
                guard let self = self else { return }
                self.bridge = try? snapshot?.data(as: CNSermonBridge.self)
            }
    }

    func stopListeningToBridge() {
        bridgeListener?.remove()
        bridgeListener = nil
        bridge = nil
    }

    func saveBridge(_ bridge: CNSermonBridge) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let noteRef = db.collection("churchNotes").document(bridge.noteId)
        let noteSnap = try await noteRef.getDocument()
        guard noteSnap.data()?["userId"] as? String == uid else {
            throw ChurchNotesIntelligenceError.notOwner
        }
        var updated = bridge
        updated.updatedAt = Date()
        try db
            .collection("churchNotes").document(bridge.noteId)
            .collection("bridge").document("main")
            .setData(from: updated)
    }

    func loadBridge(noteId: String) async -> CNSermonBridge? {
        guard Auth.auth().currentUser?.uid != nil else { return nil }
        guard let snap = try? await db
            .collection("churchNotes").document(noteId)
            .collection("bridge").document("main")
            .getDocument()
        else { return nil }
        guard snap.data()?["noteId"] != nil else { return nil }
        return try? snap.data(as: CNSermonBridge.self)
    }

    // MARK: - God Has Been Saying Summary

    func startListeningToSummary() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoadingSummary = true
        db.collection("userChurchNotesSummary").document(uid)
            .addSnapshotListener { [weak self] (snapshot, _) in
                guard let self = self else { return }
                self.isLoadingSummary = false
                self.summary = try? snapshot?.data(as: ChurchNotesSummary.self)
            }
    }

    func dismissSummary() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("userChurchNotesSummary").document(uid)
            .updateData([
                "showInsights": false,
                "dismissedAt": FieldValue.serverTimestamp(),
            ])
    }

    func restoreSummaryVisibility() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("userChurchNotesSummary").document(uid)
            .updateData(["showInsights": true, "dismissedAt": NSNull()])
    }

    func generateServerSideSummary(userId: String, noteIds: [String]) async -> ChurchNotesSummary? {
        guard AMENFeatureFlags.shared.churchNotesServerSummaryEnabled else { return nil }
        guard let currentUserId = Auth.auth().currentUser?.uid, currentUserId == userId else { return nil }

        let uniqueNoteIds = Array(Set(noteIds)).filter { !$0.isEmpty }
        guard !uniqueNoteIds.isEmpty else { return nil }

        do {
            let notePayloads = try await loadServerSummaryPayloads(userId: userId, noteIds: uniqueNoteIds)
            guard !notePayloads.isEmpty else { return nil }

            let result = try await functions
                .httpsCallable("bereanGenerateChurchNotesSummary")
                .safeCall([
                    "userId": userId,
                    "noteIds": uniqueNoteIds,
                    "notes": notePayloads,
                    "isPrivateNote": true,
                ])

            guard let data = result.data as? [String: Any] else { return nil }
            let summaryJSON = (data["summary"] as? [String: Any]) ?? data
            return try decodeSummary(from: summaryJSON)
        } catch {
            return nil
        }
    }

    // MARK: - Prayer Bridge

    /// Mark a block as linked to a prayer. Writes a lightweight link doc and increments count atomically.
    /// Uses Firestore transaction for atomicity and consistency.
    func linkBlockToPrayer(noteId: String, blockId: String, prayerId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let noteRef = db.collection("churchNotes").document(noteId)
        // Atomic transaction to write link doc and increment prayer count
        // Updated to match Firestore runTransaction closure signature with errorPointer for throwing errors
        _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
            do {
                let noteSnap = try transaction.getDocument(noteRef)
                guard noteSnap.data()?["userId"] as? String == uid else {
                    let nsError = NSError(domain: "ChurchNotesIntelligenceRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: ChurchNotesIntelligenceError.notOwner.errorDescription ?? "Not owner"])
                    errorPointer?.pointee = nsError
                    return nil
                }
                let linkRef = noteRef.collection("linkedPrayers").document(prayerId)
                let link: [String: Any] = [
                    "prayerId": prayerId,
                    "blockId": blockId,
                    "createdAt": FieldValue.serverTimestamp(),
                ]
                transaction.setData(link, forDocument: linkRef)
                transaction.updateData(["linkedPrayerCount": FieldValue.increment(Int64(1))], forDocument: noteRef)
                return nil
            } catch let error {
                errorPointer?.pointee = error as NSError
                return nil
            }
        })
    }

    // MARK: - Private Helpers

    private func loadServerSummaryPayloads(userId: String, noteIds: [String]) async throws -> [[String: Any]] {
        var payloads: [[String: Any]] = []

        for noteId in noteIds {
            let noteRef = db.collection("churchNotes").document(noteId)
            let noteSnap = try await noteRef.getDocument()
            guard noteSnap.data()?["userId"] as? String == userId,
                  let note = try? noteSnap.data(as: ChurchNoteV2.self) else {
                continue
            }

            let blocksSnap = try await noteRef
                .collection("blocks")
                .order(by: "sortOrder")
                .getDocuments()

            let blocks = blocksSnap.documents.compactMap { try? $0.data(as: ChurchNoteBlockV2.self) }
            // H-25: Explicitly exclude .privateOnly blocks from LLM payload.
            // Private notes must never leave the device for AI processing.
            let llmBlocks = blocks.filter { block in
                block.visibility != .privateOnly
            }
            let allowedBlocks = llmBlocks.filter { block in
                block.visibility == .shareable
                    || block.visibility == .selectedForSelahEmphasis
                    || block.visibility == .selectedForPostPreview
            }

            let trimmedTexts = allowedBlocks.map { block in
                block.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }
            let noteText = trimmedTexts
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            guard !noteText.isEmpty else { continue }

            payloads.append([
                "noteId": note.id,
                "title": note.title,
                "sermonTitle": note.sermonTitle as Any,
                "sermonSpeaker": note.sermonSpeaker as Any,
                "scriptureReferences": note.scriptureReferences,
                "text": noteText,
                "isPrivateNote": true,
            ])
        }

        return payloads
    }

    private func decodeSummary(from data: [String: Any]) throws -> ChurchNotesSummary {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(ChurchNotesSummary.self, from: jsonData)
    }
}

// MARK: - Errors

enum ChurchNotesIntelligenceError: LocalizedError {
    case notOwner
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .notOwner:    return "You can only modify your own notes."
        case .saveFailed:  return "Unable to save. Please try again."
        }
    }
}

