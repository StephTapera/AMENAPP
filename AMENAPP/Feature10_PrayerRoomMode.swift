//
//  Feature10_PrayerRoomMode.swift
//  AMENAPP
//
//  Prayer Room Mode — converts any thread into a focused prayer room.
//  Live prayedLog streaming, AI entry prayer summary, "Mark Answered" flow.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
import Combine

// MARK: - Model

struct PrayerRoomLog: Identifiable {
    let id: String   // uid
    let timestamp: Date
}

// MARK: - Manager

final class PrayerRoomManager: ObservableObject {
    static let shared = PrayerRoomManager()

    @Published var prayedLog: [PrayerRoomLog] = []
    @Published var entryPrayerSummary: String?   // AI-generated for first-time viewers
    @Published var isPrayerRoom: Bool = false
    @Published var prayerRoomStatus: String = "active"

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()
    private var logListener: ListenerRegistration?

    private init() {}

    // MARK: - Convert thread to Prayer Room

    func activatePrayerRoom(threadId: String, requestText: String) async throws {
        try await db.collection("threads").document(threadId).updateData([
            "isPrayerRoom":      true,
            "prayerRoomRequest": [
                "text":      requestText,
                "createdAt": FieldValue.serverTimestamp(),
                "status":    "active",
            ],
        ])
        dlog("✅ [PrayerRoom] Thread \(threadId) converted to prayer room")
    }

    // MARK: - Record "🙏 Prayed"

    func markPrayed(threadId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db
            .collection("threads").document(threadId)
            .collection("prayedLog").document(uid)
            .setData([
                "uid":       uid,
                "timestamp": FieldValue.serverTimestamp(),
            ])
        dlog("✅ [PrayerRoom] \(uid) prayed in thread \(threadId)")
    }

    // MARK: - Mark Answered

    func markAnswered(threadId: String, authorName: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Update thread status
        try await db.collection("threads").document(threadId).updateData([
            "prayerRoomRequest.status": "answered",
        ])

        // System message to thread
        try await db.collection("conversations").document(threadId)
            .collection("messages").addDocument(data: [
                "type":      "system",
                "text":      "Prayer request answered ✓",
                "senderId":  uid,
                "createdAt": FieldValue.serverTimestamp(),
            ])

        // Fan-out FCM via Cloud Function
        _ = try? await functions.httpsCallable("notifyPrayerRoomAnswered").call([
            "threadId":   threadId,
            "authorName": authorName,
        ])

        dlog("✅ [PrayerRoom] Thread \(threadId) marked as answered")
    }

    // MARK: - Generate entry prayer summary (first-time viewer)

    func loadEntrySummary(threadId: String, userId: String, recentMessages: [[String: String]]) async {
        // Check if user has already seen this prayer room
        let summaryDoc = try? await db
            .collection("users").document(userId)
            .collection("prayerRoomSummaries").document(threadId)
            .getDocument()

        if let cached = summaryDoc?.data()?["summary"] as? String {
            await MainActor.run { entryPrayerSummary = cached }
            return
        }

        // First visit: generate AI prayer summary
        let messagesText = recentMessages.prefix(30).map { $0["text"] ?? "" }.joined(separator: "\n")
        let payload: [String: Any] = [
            "model":      "claude-sonnet-4-6",
            "max_tokens": 128,
            "messages": [[
                "role": "user",
                "content": "Summarize this prayer request thread into a 2-sentence prayer that a newcomer can pray. Start with 'Lord,'. Return only the prayer text.\n\nThread:\n\(messagesText.prefix(1500))"
            ]],
        ]

        do {
            let result = try await functions.httpsCallable("bereanGenericProxy").call(payload)
            guard let dict = result.data as? [String: Any],
                  let summary = dict["text"] as? String
            else { return }

            // Cache in user doc
            try? await db
                .collection("users").document(userId)
                .collection("prayerRoomSummaries").document(threadId)
                .setData(["summary": summary, "createdAt": FieldValue.serverTimestamp()])

            // Mark thread viewedBy
            try? await db.collection("threads").document(threadId).updateData([
                "viewedBy": FieldValue.arrayUnion([userId]),
            ])

            await MainActor.run { entryPrayerSummary = summary }
        } catch {
            dlog("⚠️ [PrayerRoom] Entry summary error: \(error.localizedDescription)")
        }
    }

    // MARK: - Listen to prayedLog

    func listenToPrayedLog(threadId: String) {
        logListener?.remove()
        logListener = db
            .collection("threads").document(threadId)
            .collection("prayedLog")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let entries: [PrayerRoomLog] = snap?.documents.compactMap { doc in
                    guard let ts = doc.data()["timestamp"] as? Timestamp else { return nil }
                    return PrayerRoomLog(id: doc.documentID, timestamp: ts.dateValue())
                } ?? []
                DispatchQueue.main.async { self.prayedLog = entries }
            }
    }

    func stopListening() {
        logListener?.remove()
        logListener = nil
    }
}
