// AmenEdgeStore.swift
// AMEN App — Community OS / Graph
//
// Primary Firestore interface for the /edges/{edgeId} collection.
// Handles object-to-object many-to-many relationships across all canonical object types.
// This is DISTINCT from /follows (user-to-user follows) and
// /communityGraph/{uid}/edges (meaning-graph affinity edges).
//
// Collection: /edges/{edgeId}
// Indexes required:
//   1. fromRef ASC, edgeType ASC, createdAt DESC
//   2. toRef ASC, edgeType ASC, createdAt DESC
//   3. fromType ASC, toType ASC, edgeType ASC, createdAt DESC
//
// OPEN: unify AmenEdge definition with contracts/stubs/AmenCoreModels.swift once
//       Core/ module is authored (OQ-17 resolution pending).

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - AmenEdge

/// Many-to-many relationship document stored in /edges/{edgeId}.
///
/// NOTE: AmenCoreModels.swift (contracts/stubs) defines a richer AmenEdge with
/// typed enums (EdgeType, EdgeVisibility, ObjectType). This file uses String-typed
/// fields to avoid importing the stub before a Core/ target is established.
///
// OPEN: unify with CommunityOS/Core/AmenCoreModels.swift AmenEdge
struct AmenEdge: Identifiable, Codable, Equatable, Sendable {
    /// Firestore document ID.
    let id: String
    /// Firestore document path of the source object, e.g. "/posts/abc123".
    let fromRef: String
    /// ObjectType raw value of the source, e.g. "post", "church".
    let fromType: String
    /// Firestore document path of the target object, e.g. "/churches/xyz".
    let toRef: String
    /// ObjectType raw value of the target.
    let toType: String
    /// EdgeType raw value: "belongsTo" | "spawnedFrom" | "links" | "follows" | "praysFor"
    let edgeType: String
    /// UID of the user who created this edge.
    let createdBy: String
    /// Visibility raw value: "public" | "members" | "private"
    let visibility: String
    /// Creation timestamp.
    let createdAt: Date
    /// Soft-delete flag — never hard-delete edges.
    var isDeleted: Bool
    /// Set to true on outbound edges cascade-deleted via onNodeSoftDeleted.
    /// Used by onNodeRestored to reverse the cascade.
    var deletedInCascade: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fromRef
        case fromType
        case toRef
        case toType
        case edgeType
        case createdBy
        case visibility
        case createdAt
        case isDeleted
        case deletedInCascade
    }
}

// MARK: - AmenEdgeStore

/// @MainActor ObservableObject that is the primary Firestore interface for /edges.
///
/// Scope: object-to-object relationships (Church→Sermon, Post→Discussion,
/// User→Space, etc.). Does NOT replace:
///   - /follows (user-to-user social graph, handled by SocialGraphService)
///   - /communityGraph (meaning-graph affinity, handled by CommunityGraphService)
///   - /socialGraph/{uid}/following (legacy follow subcollection)
///
/// The "follows" EdgeType in /edges handles following of non-user objects
/// (e.g., User follows Church, User follows Space). User-to-user follows remain
/// in the /follows collection owned by SocialGraphService (OQ-17 deferred).
@MainActor
final class AmenEdgeStore: ObservableObject {

    // MARK: Published State

    @Published var outboundEdges: [AmenEdge] = []
    @Published var inboundEdges: [AmenEdge] = []

    // MARK: Private

    private let db = Firestore.firestore()

    private var edgesCollection: CollectionReference {
        db.collection("edges")
    }

    // MARK: - createEdge

    /// Creates a new edge document in /edges. Performs a deduplication check first.
    /// Returns the newly created edge document ID.
    ///
    /// - Parameters:
    ///   - fromRef: Firestore document path of the source object.
    ///   - fromType: ObjectType raw string of the source.
    ///   - toRef: Firestore document path of the target object.
    ///   - toType: ObjectType raw string of the target.
    ///   - edgeType: EdgeType raw string.
    ///   - createdBy: UID of the creating user.
    ///   - visibility: Visibility raw string; defaults to "private".
    /// - Returns: The new edge document ID.
    func createEdge(
        fromRef: String,
        fromType: String,
        toRef: String,
        toType: String,
        edgeType: String,
        createdBy: String,
        visibility: String = "private"
    ) async throws -> String {
        // Deduplication check — do not create duplicate active edges.
        let alreadyExists = try await edgeExists(
            fromRef: fromRef,
            toRef: toRef,
            edgeType: edgeType
        )
        if alreadyExists {
            // Return a stable virtual ID for idempotent callers.
            // The caller may choose to treat this as success or as a no-op signal.
            let query = buildQuery(
                collection: edgesCollection,
                ref: fromRef,
                field: "fromRef",
                edgeType: edgeType
            ).whereField("toRef", isEqualTo: toRef)
                .limit(to: 1)
            let snap = try await query.getDocuments()
            if let existing = snap.documents.first {
                return existing.documentID
            }
        }

        let ref = edgesCollection.document()
        let payload: [String: Any] = [
            "id": ref.documentID,
            "fromRef": fromRef,
            "fromType": fromType,
            "toRef": toRef,
            "toType": toType,
            "edgeType": edgeType,
            "createdBy": createdBy,
            "visibility": visibility,
            "createdAt": FieldValue.serverTimestamp(),
            "isDeleted": false,
            "deletedInCascade": false,
            "_type": "edge"
        ]
        try await ref.setData(payload)
        return ref.documentID
    }

    // MARK: - loadOutbound

    /// Loads all active edges where fromRef == ref, optionally filtered by edgeType.
    /// Populates `outboundEdges`. Capped at 100 results.
    ///
    /// - Parameters:
    ///   - fromRef: Firestore document path of the source object.
    ///   - edgeType: Optional EdgeType filter.
    func loadOutbound(fromRef: String, edgeType: String? = nil) async throws {
        let query = buildQuery(
            collection: edgesCollection,
            ref: fromRef,
            field: "fromRef",
            edgeType: edgeType
        )
        let snap = try await query.getDocuments()
        outboundEdges = snap.documents.compactMap { parseEdge($0) }
    }

    // MARK: - loadInbound

    /// Loads all active edges where toRef == ref, optionally filtered by edgeType.
    /// Populates `inboundEdges`. Capped at 100 results.
    ///
    /// - Parameters:
    ///   - toRef: Firestore document path of the target object.
    ///   - edgeType: Optional EdgeType filter.
    func loadInbound(toRef: String, edgeType: String? = nil) async throws {
        let query = buildQuery(
            collection: edgesCollection,
            ref: toRef,
            field: "toRef",
            edgeType: edgeType
        )
        let snap = try await query.getDocuments()
        inboundEdges = snap.documents.compactMap { parseEdge($0) }
    }

    // MARK: - edgeExists

    /// Checks whether an active (non-deleted) edge already exists between two objects
    /// with the given edgeType. Used for deduplication before createEdge.
    func edgeExists(fromRef: String, toRef: String, edgeType: String) async throws -> Bool {
        let snap = try await edgesCollection
            .whereField("fromRef", isEqualTo: fromRef)
            .whereField("toRef", isEqualTo: toRef)
            .whereField("edgeType", isEqualTo: edgeType)
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 1)
            .getDocuments()
        return !snap.documents.isEmpty
    }

    // MARK: - softDeleteEdge

    /// Marks a single edge as deleted. Never hard-deletes.
    func softDeleteEdge(id: String) async throws {
        try await edgesCollection.document(id).updateData([
            "isDeleted": true
        ])
    }

    // MARK: - softDeleteAllEdgesFrom

    /// Batch soft-deletes all active edges where fromRef == ref.
    /// Uses a Firestore WriteBatch; safe for up to 500 documents per Firestore limits.
    /// For objects with > 500 outbound edges, caller must paginate or use a Cloud Function.
    func softDeleteAllEdgesFrom(ref: String) async throws {
        let snap = try await edgesCollection
            .whereField("fromRef", isEqualTo: ref)
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 500)
            .getDocuments()

        guard !snap.documents.isEmpty else { return }

        let batch = db.batch()
        for doc in snap.documents {
            batch.updateData(["isDeleted": true], forDocument: doc.reference)
        }
        try await batch.commit()
    }

    // MARK: - Private Helpers

    /// Shared query builder used by both loadOutbound and loadInbound.
    /// Applies: isDeleted == false, optional edgeType filter, orderBy createdAt DESC, limit 100.
    private func buildQuery(
        collection: CollectionReference,
        ref: String,
        field: String,
        edgeType: String?
    ) -> Query {
        var query: Query = collection
            .whereField(field, isEqualTo: ref)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)

        if let edgeType {
            query = collection
                .whereField(field, isEqualTo: ref)
                .whereField("edgeType", isEqualTo: edgeType)
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
        }

        return query
    }

    /// Parses a Firestore DocumentSnapshot into an AmenEdge. Returns nil on failure.
    private func parseEdge(_ doc: DocumentSnapshot) -> AmenEdge? {
        guard let data = doc.data() else { return nil }
        let id = doc.documentID
        guard
            let fromRef = data["fromRef"] as? String,
            let fromType = data["fromType"] as? String,
            let toRef = data["toRef"] as? String,
            let toType = data["toType"] as? String,
            let edgeType = data["edgeType"] as? String,
            let createdBy = data["createdBy"] as? String,
            let visibility = data["visibility"] as? String
        else { return nil }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let isDeleted = data["isDeleted"] as? Bool ?? false
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
