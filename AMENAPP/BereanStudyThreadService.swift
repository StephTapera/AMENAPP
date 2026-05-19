// BereanStudyThreadService.swift
// AMENAPP
// Manages Berean study threads — persistent multi-session scripture studies.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Combine

// MARK: - Models

struct BereanStudyThread: Identifiable, Codable {
    var id: String
    var ownerId: String
    var title: String
    var passage: String?
    var topic: String?
    var messageCount: Int
    var summaryText: String?
    var summaryGeneratedAt: Date?
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - Service

@MainActor
final class BereanStudyThreadService: ObservableObject {
    static let shared = BereanStudyThreadService()

    @Published private(set) var threads: [BereanStudyThread] = []
    @Published private(set) var isLoading = false

    private let functions = Functions.functions()
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startObserving() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db.collection("bereanThreads")
            .whereField("ownerId", isEqualTo: uid)
            .order(by: "updatedAt", descending: true)
            .limit(to: 30)
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                self?.threads = snap.documents.compactMap { self?.decodeThread($0) }
            }
    }

    func stopObserving() {
        listener?.remove()
        listener = nil
    }

    func createThread(title: String, passage: String? = nil, topic: String? = nil) async throws -> String {
        var payload: [String: Any] = ["title": title]
        if let passage { payload["passage"] = passage }
        if let topic { payload["topic"] = topic }
        let result = try await functions.httpsCallable("createBereanStudyThread").call(payload)
        let data = result.data as? [String: Any] ?? [:]
        return data["threadId"] as? String ?? UUID().uuidString
    }

    func summarize(threadId: String) async throws -> String {
        let result = try await functions.httpsCallable("summarizeBereanThread").call([
            "threadId": threadId
        ])
        let data = result.data as? [String: Any] ?? [:]
        return data["summary"] as? String ?? ""
    }

    func generateFollowUps(sessionId: String, lastResponse: String, passage: String? = nil) async throws -> [String] {
        var payload: [String: Any] = ["sessionId": sessionId, "lastResponseText": lastResponse]
        if let passage { payload["passage"] = passage }
        let result = try await functions.httpsCallable("generateBereanFollowUps").call(payload)
        let data = result.data as? [String: Any] ?? [:]
        return data["followUps"] as? [String] ?? []
    }

    private func decodeThread(_ doc: DocumentSnapshot) -> BereanStudyThread? {
        guard let data = doc.data() else { return nil }
        return BereanStudyThread(
            id: doc.documentID,
            ownerId: data["ownerId"] as? String ?? "",
            title: data["title"] as? String ?? "",
            passage: data["passage"] as? String,
            topic: data["topic"] as? String,
            messageCount: data["messageCount"] as? Int ?? 0,
            summaryText: data["summaryText"] as? String,
            summaryGeneratedAt: (data["summaryGeneratedAt"] as? Timestamp)?.dateValue(),
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
}
