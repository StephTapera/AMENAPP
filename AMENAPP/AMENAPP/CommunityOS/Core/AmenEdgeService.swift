// AmenEdgeService.swift
// AMEN App — CommunityOS / Core
//
// Phase 1 — Agent A1 (Core Platform Architecture)
// Typed Firestore CRUD service for the /edges top-level collection.
//
// Distinction from AmenEdgeStore (CommunityOS/Graph/AmenEdgeStore.swift):
//   - AmenEdgeStore: string-typed fields, listener-based (@Published arrays).
//   - AmenEdgeService: typed enums (EdgeType, ObjectType), fetch-based (not listeners),
//                      designed for the Core platform use cases (spawn, follow, praysFor).
//
// Both write to the same /edges collection and are compatible at the Firestore level.
// AmenEdgeStore and AmenEdgeService may coexist until the string-typed store is migrated.
//
// Rules:
//   - async/await only — no Combine.
//   - @MainActor on the ObservableObject.
//   - Soft-delete only: { isDeleted: true }. Never calls .delete().
//   - All writes use FieldValue.serverTimestamp() for createdAt.

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

    /// Creates a new edge document in /edges. Returns the new document ID.
    ///
    /// Uses typed enums for fromType, toType, and edgeType — stored as raw strings
    /// in Firestore for compatibility with AmenEdgeStore's string-typed reads.
    ///
    /// - Parameters:
    ///   - fromRef: Firestore document path of the source, e.g. "/posts/abc123".
    ///   - fromType: ObjectType of the source.
    ///   - toRef: Firestore document path of the target, e.g. "/churches/xyz".
    ///   - toType: ObjectType of the target.
    ///   - edgeType: EdgeType relationship value.
    ///   - createdBy: Firebase Auth UID of the creating user.
    ///   - visibility: EdgeVisibility; defaults to `.private`.
    /// - Returns: The new Firestore document ID.
    /// - Throws: Firestore write errors.
    func createEdge(
        fromRef: String,
        fromType: ObjectType,
        toRef: String,
        toType: ObjectType,
        edgeType: EdgeType,
        createdBy: String,
        visibility: EdgeVisibility = .private
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
            "visibility":       visibility.rawValue,
            "createdAt":        FieldValue.serverTimestamp(),
            "isDeleted":        false,
            "deletedInCascade": false
        ]
        try await docRef.setData(payload)
        return docRef.documentID
    }

    // MARK: - fetchEdgesFrom

    /// Queries /edges for all active edges where `fromRef == ref`.
    /// Optionally filtered by `edgeType`.
    /// Sorted by createdAt descending. Capped at 100 results.
    ///
    /// - Parameters:
    ///   - ref: Firestore document path of the source object.
    ///   - edgeType: Optional EdgeType filter.
    /// - Returns: Array of AmenEdge (string-typed struct from AmenEdgeStore.swift).
    /// - Throws: Firestore read errors.
    func fetchEdgesFrom(ref: String, type edgeType: EdgeType? = nil) async throws -> [AmenEdge] {
        let query = buildQuery(field: "fromRef", ref: ref, edgeType: edgeType)
        let snap = try await query.getDocuments()
        return snap.documents.compactMap { parseEdge($0) }
    }

    // MARK: - fetchEdgesTo

    /// Queries /edges for all active edges where `toRef == ref`.
    /// Optionally filtered by `edgeType`.
    /// Sorted by createdAt descending. Capped at 100 results.
    ///
    /// - Parameters:
    ///   - ref: Firestore document path of the target object.
    ///   - edgeType: Optional EdgeType filter.
    /// - Returns: Array of AmenEdge.
    /// - Throws: Firestore read errors.
    func fetchEdgesTo(ref: String, type edgeType: EdgeType? = nil) async throws -> [AmenEdge] {
        let query = buildQuery(field: "toRef", ref: ref, edgeType: edgeType)
        let snap = try await query.getDocuments()
        return snap.documents.compactMap { parseEdge($0) }
    }

    // MARK: - softDeleteEdge

    /// Marks a single edge as deleted by setting `{ isDeleted: true }`.
    /// Never hard-deletes.
    ///
    /// - Parameter id: Firestore document ID of the edge to soft-delete.
    func softDeleteEdge(id: String) async throws {
        try await edgesCollection.document(id).updateData([
            "isDeleted": true
        ])
    }

    // MARK: - softDeleteEdgesFromNode

    /// When a node (object) is soft-deleted, cascade soft-delete all its active
    /// outbound edges. Uses a Firestore WriteBatch (safe for ≤ 500 per Firestore limits).
    ///
    /// For objects predicted to have > 50 outbound edges (C1 §4e fan-out rule),
    /// callers should use an async Cloud Function queue instead of calling this directly.
    ///
    /// - Parameter ref: Firestore document path of the node being deleted.
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
                    "isDeleted": true,
                    "deletedInCascade": true
                ],
                forDocument: doc.reference
            )
        }
        try await batch.commit()
    }

    // MARK: - Private Helpers

    /// Builds the Firestore query for fetching edges by field (fromRef or toRef).
    /// Applies: isDeleted == false, optional edgeType filter, order by createdAt DESC, limit 100.
    private func buildQuery(
        field: String,
        ref: String,
        edgeType: EdgeType?
    ) -> Query {
        var query: Query = edgesCollection
            .whereField(field, isEqualTo: ref)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)

        if let edgeType {
            query = edgesCollection
                .whereField(field, isEqualTo: ref)
                .whereField("edgeType", isEqualTo: edgeType.rawValue)
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
        }

        return query
    }

    /// Parses a Firestore DocumentSnapshot into an AmenEdge.
    /// Returns nil on decode failure — never crashes.
    ///
    /// NOTE: Uses the AmenEdge struct defined in AmenEdgeStore.swift (string-typed fields).
    /// This ensures compatibility with the existing store while AmenEdgeService provides
    /// typed-enum entry points.
    private func parseEdge(_ doc: DocumentSnapshot) -> AmenEdge? {
        guard let data = doc.data() else { return nil }
        let id = doc.documentID
        guard
            let fromRef     = data["fromRef"]   as? String,
            let fromType    = data["fromType"]  as? String,
            let toRef       = data["toRef"]     as? String,
            let toType      = data["toType"]    as? String,
            let edgeType    = data["edgeType"]  as? String,
            let createdBy   = data["createdBy"] as? String,
            let visibility  = data["visibility"] as? String
        else { return nil }

        let createdAt       = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let isDeleted       = data["isDeleted"] as? Bool ?? false
        let deletedInCascade = data["deletedInCascade"] as? Bool ?? false

        return AmenEdge(
            id: id,
            fromRef: fromRef,
            fromType: fromType,
            toRef: toRef,
            toType: toType,
            edgeType: edgeType,
            createdBy: createdBy,
            visibility: visibility,
            createdAt: createdAt,
            isDeleted: isDeleted,
            deletedInCascade: deletedInCascade
        )
    }
}
