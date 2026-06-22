// TableService.swift
// AMEN — Table Service
//
// Manages Table lifecycle in Firestore at tables/{id}.
// memberLimit enforced 8...12. Join cap enforced both client-side and server-side
// (joinTable Cloud Function runs a transaction).
// Flag-gated: AMENFeatureFlags.shared.tables

import Foundation
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class TableService: ObservableObject {

    // MARK: - Dependencies

    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-east1")

    // MARK: - Create

    /// Creates a Table in Firestore at tables/{id}.
    /// Validates memberLimit is within 8...12.
    func createTable(
        name: String,
        anchor: TableAnchor,
        sunsetAt: Date,
        memberLimit: Int
    ) async throws -> Table {
        guard AMENFeatureFlags.shared.tables else {
            throw TableServiceError.featureDisabled
        }

        let clampedLimit = max(8, min(12, memberLimit))
        let id = UUID().uuidString
        let now = Date()

        let table = Table(
            id: id,
            name: name,
            memberLimit: clampedLimit,
            members: [],
            anchor: anchor,
            sunsetAt: sunsetAt,
            notebookId: nil,
            spaceId: nil,
            createdAt: now,
            createdBy: "" // caller sets via context
        )

        var data: [String: Any] = [
            "id": id,
            "name": name,
            "memberLimit": clampedLimit,
            "members": [String](),
            "sunsetAt": Timestamp(date: sunsetAt),
            "createdAt": Timestamp(date: now),
            "archived": false
        ]

        // Encode anchor
        data["anchor"] = try encodeAnchor(anchor)

        try await db.collection("tables").document(id).setData(data)
        return table
    }

    // MARK: - Join

    /// Joins a table via the joinTable Cloud Function (transaction-based, cap-enforced).
    /// Client also enforces the cap for a fast, friendly failure before the network call.
    func joinTable(tableId: String, uid: String) async throws {
        guard AMENFeatureFlags.shared.tables else {
            throw TableServiceError.featureDisabled
        }

        // Client-side cap check for fast feedback.
        let doc = try await db.collection("tables").document(tableId).getDocument()
        if let data = doc.data() {
            let members = data["members"] as? [String] ?? []
            let limit = data["memberLimit"] as? Int ?? 12
            if members.count >= limit {
                throw TableServiceError.tableFull
            }
        }

        // Server-side transaction via Cloud Function (authoritative).
        // uid is NOT passed in the payload — the CF reads it from request.auth.uid.
        let callable = functions.httpsCallable("joinTable")
        _ = try await callable.call(["tableId": tableId])
    }

    // MARK: - Leave

    /// Removes a user from a table.
    func leaveTable(tableId: String, uid: String) async throws {
        guard AMENFeatureFlags.shared.tables else {
            throw TableServiceError.featureDisabled
        }

        try await db.collection("tables").document(tableId).updateData([
            "members": FieldValue.arrayRemove([uid])
        ])
    }

    // MARK: - Live Stream

    /// Returns an AsyncThrowingStream of Tables the user belongs to.
    func myTables(for uid: String) -> AsyncThrowingStream<[Table], Error> {
        AsyncThrowingStream { continuation in
            guard AMENFeatureFlags.shared.tables else {
                continuation.finish()
                return
            }

            let query = db.collection("tables")
                .whereField("members", arrayContains: uid)
                .whereField("archived", isEqualTo: false)
                .order(by: "createdAt", descending: true)

            let listener = query.addSnapshotListener { snapshot, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let documents = snapshot?.documents else {
                    continuation.yield([])
                    return
                }

                let decoder = Firestore.Decoder()
                let tables: [Table] = documents.compactMap { doc in
                    try? doc.data(as: Table.self, decoder: decoder)
                }
                continuation.yield(tables)
            }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    // MARK: - Helpers

    private func encodeAnchor(_ anchor: TableAnchor) throws -> [String: Any] {
        switch anchor {
        case .study(let ref):
            return ["type": "study", "studyRef": ref]
        case .season(let ref):
            return ["type": "season", "seasonRef": ref]
        case .topic(let t):
            return ["type": "topic", "topic": t]
        }
    }
}

// MARK: - Error

enum TableServiceError: Error, LocalizedError {
    case featureDisabled
    case tableFull

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Tables is not available right now."
        case .tableFull:
            return "This Table has reached its limit. Another Table may have room."
        }
    }
}
