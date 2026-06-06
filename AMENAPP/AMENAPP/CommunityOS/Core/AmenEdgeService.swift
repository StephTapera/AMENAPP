// AmenEdgeService.swift
// AMEN App — CommunityOS / Core
//
// Phase 1 — Agent A1 (Core Platform Architecture)
// Firestore-direct typed service for the /edges collection.
//
// DISTINCT FROM:
//   EdgeService (EdgeService.swift)         — CF-backed singleton; uses Firebase Callables.
//   AmenCallableEdgeStore (Graph/AmenCallableEdgeStore.swift) — listener-based; string-typed fields.
//
// AmenEdgeService provides:
//   - Typed enum parameters (AmenCallableEdgeType, AmenObjectType).
//   - Firestore-direct reads/writes (no CF round-trip for local operations).
//   - Batch soft-delete for node cascade.
//   - Compatible with existing /edges documents written by EdgeService / AmenCallableEdgeStore.
//
// Rules:
//   - async/await only — no Combine.
//   - @MainActor on the ObservableObject.
//   - Soft-delete only: { isDeleted: true }. Never calls .delete().
//   - All writes use FieldValue.serverTimestamp() for createdAt.
//
// SHARED TYPES (do NOT redefine here):
//   AmenCallableEdge      →  Core/EdgeService.swift
//   AmenCallableEdgeType  →  CommunityObjectTypes.swift
//   AmenObjectType →  CommunityObjectTypes.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - AmenEdgeService

@MainActor
final class AmenEdgeService: ObservableObject {

    // MARK: - Private

    private let db = Firestore.firestore()

    private var edgesCollection: CollectionReference {
        db.collection("edges")
    }

    // MARK: - createEdge

    /// Creates a new edge document in /edges with typed enum parameters.
    /// Stores raw string values for compatibility with EdgeService and AmenCallableEdgeStore reads.
    ///
    /// - Parameters:
    ///   - fromRef: Firestore document path of the source, e.g. "/posts/abc123".
    ///   - fromType: AmenObjectType of the source.
    ///   - toRef: Firestore document path of the target, e.g. "/churches/xyz".
    ///   - toType: AmenObjectType of the target.
    ///   - edgeType: AmenCallableEdgeType relationship value.
    ///   - createdBy: Firebase Auth UID of the creating user.
    ///   - visibility: "public" | "members" | "private"; defaults to "private".
    /// - Returns: The new Firestore document ID.
    /// - Throws: Firestore write errors.
    func createEdge(
        fromRef: String,
        fromType: AmenObjectType,
        toRef: String,
        toType: AmenObjectType,
        edgeType: AmenCallableEdgeType,
        createdBy: String,
        visibility: String = "private"
    ) async throws -> String {
        let docRef = edgesCollection.document()
        let payload: [String: Any] = [
            "id":               docRef.documentID,
            "_type":            "edge",
            "fromRef":          fromRef,
            "fromType":         fromType.rawValue,
            "toRef":            toRef,
            "toType":           toType.rawValue,
            "edgeType":         edgeType.rawValue,
            "createdBy":        createdBy,
            "visibility":       visibility,
            "createdAt":        FieldValue.serverTimestamp(),
            "isDeleted":        false,
            "deletedInCascade": false
        ]
        try await docRef.setData(payload)
        return docRef.documentID
    }

    // MARK: - fetchEdgesFrom

    /// Queries /edges for all active edges where `fromRef == ref`.
    /// Optionally filtered by `edgeType`. Sorted by createdAt DESC. Capped at 100.
    ///
    /// Returns `[AmenCallableEdge]` from Core/EdgeService.swift (typed edgeType field).
    func fetchEdgesFrom(ref: String, type edgeType: AmenCallableEdgeType? = nil) async throws -> [AmenCallableEdge] {
        let query = buildQuery(field: "fromRef", ref: ref, edgeType: edgeType)
        let snap = try await query.getDocuments()
        return snap.documents.compactMap { parseEdge($0) }
    }

    // MARK: - fetchEdgesTo

    /// Queries /edges for all active edges where `toRef == ref`.
    /// Optionally filtered by `edgeType`. Sorted by createdAt DESC. Capped at 100.
    func fetchEdgesTo(ref: String, type edgeType: AmenCallableEdgeType? = nil) async throws -> [AmenCallableEdge] {
        let query = buildQuery(field: "toRef", ref: ref, edgeType: edgeType)
        let snap = try await query.getDocuments()
        return snap.documents.compactMap { parseEdge($0) }
    }

    // MARK: - softDeleteEdge

    /// Marks a single edge as deleted. Never hard-deletes.
    func softDeleteEdge(id: String) async throws {
        try await edgesCollection.document(id).updateData([
            "isDeleted": true
        ])
    }

    // MARK: - softDeleteEdgesFromNode

    /// Cascade soft-deletes all active outbound edges for a node (when the node is deleted).
    /// Uses Firestore WriteBatch (safe for ≤ 500 per Firestore limits).
    ///
    /// C1 §4e: for objects with predicted fan-out > 50, callers should use an async
    /// Cloud Function queue rather than calling this directly.
    func softDeleteEdgesFromNode(ref: String) async throws {
        let snap = try await edgesCollection
            .whereField("fromRef", isEqualTo: ref)
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 500)
            .getDocuments()

        guard !snap.documents.isEmpty else { return }

        let batch = db.batch()
        for doc in snap.documents {
            batch.updateData(
                [
                    "isDeleted":        true,
                    "deletedInCascade": true
                ],
                forDocument: doc.reference
            )
        }
        try await batch.commit()
    }

    // MARK: - Private Helpers

    /// Builds the Firestore query filtered by field (fromRef or toRef), optional edgeType,
    /// isDeleted == false, ordered by createdAt DESC, limited to 100.
    private func buildQuery(
        field: String,
        ref: String,
        edgeType: AmenCallableEdgeType?
    ) -> Query {
        if let edgeType {
            return edgesCollection
                .whereField(field, isEqualTo: ref)
                .whereField("edgeType", isEqualTo: edgeType.rawValue)
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
        }
        return edgesCollection
            .whereField(field, isEqualTo: ref)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
    }

    /// Parses a DocumentSnapshot into an AmenCallableEdge (from Core/EdgeService.swift).
    /// AmenCallableEdge.edgeType is a typed AmenCallableEdgeType — requires a valid raw value.
    /// Returns nil if required fields are missing or edgeType is unrecognised.
    private func parseEdge(_ doc: DocumentSnapshot) -> AmenCallableEdge? {
        guard let data = doc.data() else { return nil }
        guard
            let fromRef    = data["fromRef"]    as? String,
            let fromType   = data["fromType"]   as? String,
            let toRef      = data["toRef"]      as? String,
            let toType     = data["toType"]     as? String,
            let edgeRaw    = data["edgeType"]   as? String,
            let edgeType   = AmenCallableEdgeType(rawValue: edgeRaw),
            let createdBy  = data["createdBy"]  as? String,
            let visibility = data["visibility"] as? String
        else { return nil }

        let createdAt: Date
        if let epoch = data["createdAt"] as? TimeInterval {
            createdAt = Date(timeIntervalSince1970: epoch)
        } else if let ts = data["createdAt"] as? Timestamp {
            createdAt = ts.dateValue()
        } else {
            createdAt = Date()
        }

        return AmenCallableEdge(
            fromRef:    fromRef,
            fromType:   fromType,
            toRef:      toRef,
            toType:     toType,
            edgeType:   edgeType,
            createdBy:  createdBy,
            visibility: visibility,
            createdAt:  createdAt
        )
    }
}
