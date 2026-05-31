//
//  DraftSyncService.swift
//  AMENAPP
//
//  Backs up Studio drafts to Firestore so a device reset or migration
//  does not destroy in-progress work.
//
//  Collection layout:
//    studioUserDrafts/{uid}/{sessionId}
//      tool, userInput, scriptureRef, tone, generatedText, savedAt, version
//
//  Strategy: each Studio session maps to one Firestore doc (upsert via merge).
//  Local SwiftData is still the primary store; Firestore is a recovery backup only.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class DraftSyncService {

    static let shared = DraftSyncService()
    private let db = Firestore.firestore()
    private init() {}

    // MARK: - Upload

    func sync(
        sessionId: String,
        tool: String,
        userInput: String,
        scriptureRef: String,
        tone: String,
        generatedText: String,
        version: Int
    ) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let ref = db.collection("studioUserDrafts").document(uid).collection("sessions").document(sessionId)
        let data: [String: Any] = [
            "tool": tool,
            "userInput": userInput,
            "scriptureRef": scriptureRef,
            "tone": tone,
            "generatedText": generatedText,
            "savedAt": FieldValue.serverTimestamp(),
            "version": version,
        ]
        // Fire-and-forget — failure is non-fatal; local SwiftData is the primary store.
        ref.setData(data, merge: true)
    }

    // MARK: - Fetch for recovery

    func fetchLatest(sessionId: String) async -> [String: Any]? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let ref = db.collection("studioUserDrafts").document(uid).collection("sessions").document(sessionId)
        guard let snap = try? await ref.getDocument(), snap.exists else { return nil }
        return snap.data()
    }

    // MARK: - List all backed-up sessions

    func listSessions() async -> [[String: Any]] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let ref = db.collection("studioUserDrafts").document(uid).collection("sessions")
            .order(by: "savedAt", descending: true)
            .limit(to: 20)
        guard let snap = try? await ref.getDocuments() else { return [] }
        return snap.documents.map { $0.data() }
    }
}
