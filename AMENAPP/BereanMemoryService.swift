// BereanMemoryService.swift
// AMENAPP
// Server-authoritative Berean memory CRUD — bridges to bereanExtended callables.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Combine

// MARK: - Models

struct BereanInsight: Identifiable, Codable {
    var id: String
    var sessionId: String
    var text: String
    var linkedVerses: [String]
    var tags: [String]
    var category: String
    var createdAt: Date
    var lastReferencedAt: Date
    var timesReferenced: Int
    var isUserVisible: Bool
}

// MARK: - Service

@MainActor
final class BereanMemoryService: ObservableObject {
    static let shared = BereanMemoryService()

    @Published private(set) var insights: [BereanInsight] = []
    @Published private(set) var isLoading = false
    @Published var saveError: String?

    private let functions = Functions.functions()
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    // MARK: Fetch / observe

    func startObserving() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db.collection("users").document(uid)
            .collection("bereanMemory")
            .whereField("isUserVisible", isEqualTo: true)
            .order(by: "lastReferencedAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] (snap: QuerySnapshot?, _: Error?) in
                guard let snap else { return }
                self?.insights = snap.documents.compactMap { self?.decodeInsight($0) }
            }
    }

    func stopObserving() {
        listener?.remove()
        listener = nil
    }

    deinit {
        listener?.remove()
    }

    // MARK: Write

    func saveInsight(
        sessionId: String,
        text: String,
        linkedVerses: [String] = [],
        tags: [String] = [],
        category: String = "insight"
    ) async throws -> String {
        do {
            let result = try await functions.callWithTimeout("saveBereanInsight", data: [
                "sessionId": sessionId,
                "text": text,
                "linkedVerses": linkedVerses,
                "tags": tags,
                "category": category
            ], timeout: 15)
            let data = result.data as? [String: Any] ?? [:]
            return data["entryId"] as? String ?? UUID().uuidString
        } catch {
            saveError = error.localizedDescription
            throw error
        }
    }

    func update(entryId: String, updates: [String: Any]) async throws {
        do {
            _ = try await functions.callWithTimeout("updateBereanMemory", data: [
                "entryId": entryId,
                "updates": updates
            ], timeout: 10)
        } catch {
            saveError = error.localizedDescription
            throw error
        }
    }

    func delete(entryId: String) async throws {
        do {
            _ = try await functions.callWithTimeout("deleteBereanMemory", data: [
                "entryId": entryId
            ], timeout: 10)
            insights.removeAll { $0.id == entryId }
        } catch {
            saveError = error.localizedDescription
            throw error
        }
    }

    // MARK: Decode

    private func decodeInsight(_ doc: DocumentSnapshot) -> BereanInsight? {
        guard let data = doc.data() else { return nil }
        return BereanInsight(
            id: doc.documentID,
            sessionId: data["sessionId"] as? String ?? "",
            text: data["text"] as? String ?? "",
            linkedVerses: data["linkedVerses"] as? [String] ?? [],
            tags: data["tags"] as? [String] ?? [],
            category: data["category"] as? String ?? "insight",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            lastReferencedAt: (data["lastReferencedAt"] as? Timestamp)?.dateValue() ?? Date(),
            timesReferenced: data["timesReferenced"] as? Int ?? 0,
            isUserVisible: data["isUserVisible"] as? Bool ?? true
        )
    }
}
