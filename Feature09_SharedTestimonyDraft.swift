//
//  Feature09_SharedTestimonyDraft.swift
//  AMENAPP
//
//  Shared Testimony Draft — two co-authors write perspectives,
//  then Claude weaves them into a single narrative for community publishing.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
import Combine

// MARK: - Model

struct TestimonyDraft: Identifiable {
    let id: String
    let authors: [String]
    var perspectives: [String: String]  // uid → text
    var woven: String
    var status: String                  // "drafting" | "weaving" | "woven"
    let createdAt: Date
}

// MARK: - Manager

final class TestimonyDraftManager: ObservableObject {
    static let shared = TestimonyDraftManager()

    @Published var activeDraft: TestimonyDraft?
    @Published var isWeaving = false

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Create

    func createDraft(coAuthorId: String) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { return "" }

        let draftId = UUID().uuidString
        let data: [String: Any] = [
            "authors":      [uid, coAuthorId],
            "perspectives": [String: String](),
            "woven":        "",
            "status":       "drafting",
            "createdAt":    FieldValue.serverTimestamp(),
        ]

        try await db.collection("testimonyDrafts").document(draftId).setData(data)
        dlog("✅ [SharedTestimony] Created draft \(draftId)")
        return draftId
    }

    // MARK: - Update my perspective

    func updatePerspective(draftId: String, text: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("testimonyDrafts").document(draftId).updateData([
            "perspectives.\(uid)": text,
        ])
    }

    // MARK: - Mark ready and weave

    func markReadyAndWeave(draftId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Fetch latest draft to get all perspectives
        let doc = try await db.collection("testimonyDrafts").document(draftId).getDocument()
        guard let data = doc.data(),
              let perspectives = data["perspectives"] as? [String: String],
              let authors = data["authors"] as? [String]
        else { return }

        // Check all authors have contributed
        let allReady = authors.allSatisfy { perspectives[$0]?.isEmpty == false }
        guard allReady else {
            dlog("⚠️ [SharedTestimony] Not all authors have contributed yet")
            return
        }

        await MainActor.run { isWeaving = true }

        // Update status
        try await db.collection("testimonyDrafts").document(draftId).updateData(["status": "weaving"])

        // Call Claude to weave the perspectives
        let combinedText = perspectives.values.joined(separator: "\n\n---\n\n")
        let payload: [String: Any] = [
            "model":      "claude-sonnet-4-6",
            "max_tokens": 512,
            "messages": [[
                "role": "user",
                "content": "Two people are writing a shared testimony. Weave their two perspectives into one cohesive third-person narrative (150 words max) that honors both voices. Return only the woven text.\n\nPerspectives:\n\(combinedText)"
            ]],
        ]

        let result = try await functions.httpsCallable("bereanGenericProxy").call(payload)
        guard let resultDict = result.data as? [String: Any],
              let woven = resultDict["text"] as? String
        else {
            await MainActor.run { isWeaving = false }
            return
        }

        try await db.collection("testimonyDrafts").document(draftId).updateData([
            "woven":  woven,
            "status": "woven",
        ])

        await MainActor.run { isWeaving = false }
        dlog("✅ [SharedTestimony] Woven narrative saved for draft \(draftId)")
    }

    // MARK: - Publish to community feed

    func publishToFeed(draftId: String) async throws {
        let doc = try await db.collection("testimonyDrafts").document(draftId).getDocument()
        guard let data = doc.data(),
              data["status"] as? String == "woven",
              let woven   = data["woven"]   as? String,
              let authors = data["authors"] as? [String]
        else { return }

        try await db.collection("communityFeed").addDocument(data: [
            "type":      "sharedTestimony",
            "authors":   authors,
            "woven":     woven,
            "draftId":   draftId,
            "createdAt": FieldValue.serverTimestamp(),
            "status":    "published",
        ])

        dlog("✅ [SharedTestimony] Published draft \(draftId) to community feed")
    }

    // MARK: - Listen

    func listenToDraft(draftId: String) {
        listener?.remove()
        listener = db.collection("testimonyDrafts").document(draftId)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let d = snap?.data() else { return }
                let draft = TestimonyDraft(
                    id:           snap!.documentID,
                    authors:      d["authors"]      as? [String]      ?? [],
                    perspectives: d["perspectives"] as? [String: String] ?? [:],
                    woven:        d["woven"]        as? String         ?? "",
                    status:       d["status"]       as? String         ?? "drafting",
                    createdAt:    (d["createdAt"]   as? Timestamp)?.dateValue() ?? Date()
                )
                DispatchQueue.main.async { self.activeDraft = draft }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}
