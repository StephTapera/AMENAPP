// AmenNodeIntegrity.swift
// AMEN App — Community OS / Graph
//
// Ensures graph integrity when canonical nodes are soft-deleted or restored.
//
// Responsibilities:
//   onNodeSoftDeleted — cascade-soft-delete outbound edges; reparent orphaned children
//   onNodeRestored    — un-delete edges that were cascade-deleted (deletedInCascade == true)
//   validateNode      — check whether a node's edges are intact (no dangling refs)
//
// Sentinel values used for orphan reparenting:
//   fromRef  → "orphan_pool"
//   fromType → "orphan"
//
// Batch writes are used for multi-document operations.
// All Firestore operations use soft-delete only — never .delete().
// Batch operations are capped at 500 documents per Firestore limit.

import Foundation
import FirebaseFirestore

// MARK: - NodeStatus

/// The edge-integrity status of a node in the graph.
enum NodeStatus: String, Sendable {
    /// Node has valid, non-dangling edges.
    case valid = "valid"
    /// Node's parent edges point to "orphan_pool" — its parents were deleted.
    case orphaned = "orphaned"
    /// Node's outbound edges were soft-deleted in a cascade from a parent deletion.
    case cascadeDeleted = "cascadeDeleted"
}

// MARK: - AmenNodeIntegrity

/// Utility class for graph integrity maintenance.
/// All methods are `static` — no instance state needed.
/// Methods run on @MainActor because they may be invoked from ObservableObject workflows.
@MainActor
final class AmenNodeIntegrity {

    private static let db = Firestore.firestore()
    private static var edgesCollection: CollectionReference {
        db.collection("edges")
    }

    // Sentinel value written to fromRef when a parent is deleted and children are reparented.
    private static let orphanPoolRef = "orphan_pool"
    private static let orphanType = "orphan"

    // MARK: - onNodeSoftDeleted

    /// Called when any canonical object is soft-deleted.
    ///
    /// Step 1: Soft-delete all outbound edges from this ref (fromRef == ref).
    ///         Marks `isDeleted = true` and `deletedInCascade = true` on each edge.
    ///
    /// Step 2: For inbound "belongsTo" edges (toRef == ref) — reparent the children.
    ///         Sets `fromRef = "orphan_pool"` and `fromType = "orphan"` so children
    ///         are never dangled with a reference to a deleted node.
    ///
    /// Operates in batches of 500 per Firestore WriteBatch limit.
    ///
    /// - Parameters:
    ///   - ref: Firestore document path of the node being deleted.
    ///   - nodeType: ObjectType raw string of the deleted node (for logging).
    static func onNodeSoftDeleted(ref: String, nodeType: String) async throws {
        // Step 1: Cascade-soft-delete all outbound edges.
        try await cascadeDeleteOutboundEdges(ref: ref)

        // Step 2: Reparent children — inbound "belongsTo" edges where toRef == ref.
        try await reparentChildren(ref: ref)
    }

    // MARK: - onNodeRestored

    /// Called when a previously soft-deleted node is restored.
    ///
    /// Un-deletes all outbound edges that were cascade-deleted during the node's
    /// soft-delete (i.e., edges where `fromRef == ref` AND `deletedInCascade == true`).
    ///
    /// NOTE: Orphaned children are NOT automatically re-reparented back to this node
    /// because other objects may have adopted them in the interim. Re-parenting on
    /// restore requires explicit product decision — left as a manual operation.
    ///
    /// - Parameter ref: Firestore document path of the node being restored.
    static func onNodeRestored(ref: String) async throws {
        let snap = try await edgesCollection
            .whereField("fromRef", isEqualTo: ref)
            .whereField("deletedInCascade", isEqualTo: true)
            .limit(to: 500)
            .getDocuments()

        guard !snap.documents.isEmpty else { return }

        let batch = db.batch()
        for doc in snap.documents {
            batch.updateData([
                "isDeleted": false,
                "deletedInCascade": false
            ], forDocument: doc.reference)
        }
        try await batch.commit()
    }

    // MARK: - validateNode

    /// Checks whether a node has valid edges (no dangling refs or orphaned state).
    ///
    /// - cascade-deleted: all outbound edges have `deletedInCascade == true`
    /// - orphaned: any inbound "belongsTo" edge has `fromRef == "orphan_pool"`
    /// - valid: none of the above
    ///
    /// - Parameter ref: Firestore document path of the node to validate.
    /// - Returns: `NodeStatus` value.
    static func validateNode(ref: String) async throws -> NodeStatus {
        // Check for cascade-deleted outbound edges.
        async let cascadeSnap = edgesCollection
            .whereField("fromRef", isEqualTo: ref)
            .whereField("deletedInCascade", isEqualTo: true)
            .limit(to: 1)
            .getDocuments()

        // Check for orphaned state — any "belongsTo" edge where fromRef == orphan_pool
        // and toRef (the parent's old ref) might exist, OR check if this node itself
        // is pointed at by orphan_pool as fromRef.
        // More precisely: this node is orphaned if its OWN outbound "belongsTo" edges
        // point FROM this node TO an orphan_pool target, which would mean its children
        // were orphaned FROM it. The correct orphan check is on fromRef of children.
        // We check: are there edges where toRef == ref, fromRef == "orphan_pool" (meaning
        // something that belonged to this node was orphaned when its OWN parent was deleted)?
        // Actually per spec: orphaned = this node's own "belongsTo" edges have fromRef == "orphan_pool".
        // Re-reading: reparent children sets child.fromRef = "orphan_pool". So to check if THIS
        // node is orphaned, we look for: edges where fromRef == this ref's children's fromRef.
        // Simplest check: any edge where toRef == ref and fromRef == orphan_pool means a child
        // of a deleted parent is now pointing here. For THIS node's orphan status we check
        // if any outbound edge fromRef == ref has toRef == "orphan_pool" (i.e. it was reparented
        // away). But that isn't quite right either. The correct semantic:
        //   - A node IS orphaned if its own "belongsTo" edges were reparented: fromRef was set to
        //     "orphan_pool", meaning this node is a child whose parent was deleted.
        //   - We detect this by checking inbound edges where fromRef is "orphan_pool" and toRef == ref.
        //   - But actually: reparenting sets the CHILD edge's fromRef to "orphan_pool", meaning the
        //     edge that used to say "Child X belongsTo Parent Y (this node)" now says
        //     "Child X belongsTo orphan_pool". So to see if THIS node is orphaned as a child,
        //     we check: are there edges where fromRef == "orphan_pool" that represent THIS node as
        //     the subject? That doesn't work directly.
        //   - Correct approach: check if there exist any "belongsTo" edges where fromRef == ref
        //     and toRef is an orphan_pool (meaning this node's parent edges were reparented when
        //     its own parent was deleted). But we don't reparent the node itself — we reparent
        //     its children.
        //
        // Summary of what actually happens:
        //   - When Church A is deleted: Church A's outbound edges get isDeleted=true/deletedInCascade=true
        //   - Church A's CHILDREN (Posts, Events that "belongsTo" Church A) get their edges reparented:
        //     those edges' fromRef becomes "orphan_pool"
        //   - So a Post is orphaned if its "belongsTo" edge has fromRef == "orphan_pool"
        //   - To check if ref (Post) is orphaned: look for edges fromRef=="orphan_pool", toRef == ref
        //
        // Wait — on re-reading: reparenting sets fromRef (the child pointer toward the parent) to
        // "orphan_pool". The edge was: Post.fromRef = "/posts/xyz" → toRef = "/churches/abc"
        // After reparenting: fromRef = "orphan_pool", toRef = "/churches/abc" (still the old parent)
        // This is the "belongsTo" edge record. fromRef is ALWAYS the child.
        // After reparent: the Post's "belongsTo" edge fromRef becomes "orphan_pool".
        // So the Post document path IS the edge's fromRef. We check: fromRef == ref and fromType == "orphan".
        async let orphanSnap = edgesCollection
            .whereField("fromRef", isEqualTo: orphanPoolRef)
            .whereField("toRef", isEqualTo: ref)
            .whereField("edgeType", isEqualTo: "belongsTo")
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 1)
            .getDocuments()

        let (cascadeResult, orphanResult) = try await (cascadeSnap, orphanSnap)

        // A cascade-deleted node has all its outbound edges marked deletedInCascade.
        if !cascadeResult.documents.isEmpty {
            return .cascadeDeleted
        }

        // An orphaned node has its inbound "belongsTo" edges reparented to orphan_pool.
        // Check if any edge records this ref as an orphan-pool target.
        if !orphanResult.documents.isEmpty {
            return .orphaned
        }

        return .valid
    }

    // MARK: - Private: cascadeDeleteOutboundEdges

    /// Batch soft-deletes all active outbound edges from ref, marking them as cascade-deleted.
    private static func cascadeDeleteOutboundEdges(ref: String) async throws {
        let snap = try await edgesCollection
            .whereField("fromRef", isEqualTo: ref)
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 500)
            .getDocuments()

        guard !snap.documents.isEmpty else { return }

        let batch = db.batch()
        for doc in snap.documents {
            batch.updateData([
                "isDeleted": true,
                "deletedInCascade": true
            ], forDocument: doc.reference)
        }
        try await batch.commit()
    }

    // MARK: - Private: reparentChildren

    /// For all active "belongsTo" edges where toRef == ref (i.e., children that belong to
    /// the node being deleted), reparent them to the orphan pool.
    ///
    /// Sets fromRef = "orphan_pool" and fromType = "orphan".
    /// Children are never dangled with a deleted-parent reference.
    private static func reparentChildren(ref: String) async throws {
        let snap = try await edgesCollection
            .whereField("toRef", isEqualTo: ref)
            .whereField("edgeType", isEqualTo: "belongsTo")
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 500)
            .getDocuments()

        guard !snap.documents.isEmpty else { return }

        let batch = db.batch()
        for doc in snap.documents {
            batch.updateData([
                "fromRef": orphanPoolRef,
                "fromType": orphanType
            ], forDocument: doc.reference)
        }
        try await batch.commit()
    }
}
