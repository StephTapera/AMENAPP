// AmenGraphQuery.swift
// AMEN App — Community OS / Graph
//
// Higher-level graph traversal queries for Community OS use cases.
// All methods are stateless static functions — no ObservableObject needed.
//
// Supported traversal patterns:
//   childrenOf     — "belongsTo" edges where toRef == ref  (what belongs to this node)
//   parentsOf      — "belongsTo" edges where fromRef == ref (what is this node part of)
//   spawnedFrom    — "spawnedFrom" edges where fromRef == ref
//   linkedTo       — "links" edges involving ref
//   praysForChain  — "praysFor" edges from a prayer request
//   connectionGraph — BFS up to maxDepth hops; caps at 50 edges total
//
// All methods filter out isDeleted == true edges.
// All queries cap at 100 results per Firestore call.

import Foundation
import FirebaseFirestore

// MARK: - AmenGraphQuery

struct AmenGraphQuery {

    private static let db = Firestore.firestore()
    private static var edgesCollection: CollectionReference {
        db.collection("edges")
    }

    // MARK: - childrenOf

    /// Returns all "belongsTo" edges where toRef == ref.
    /// Answers: "What belongs to (or is hosted by) this node?"
    /// Example: childrenOf("/churches/abc") → all Posts, Events, Studies that belong to this church.
    static func childrenOf(ref: String, type: String) async throws -> [AmenEdge] {
        let snap = try await edgesCollection
            .whereField("toRef", isEqualTo: ref)
            .whereField("toType", isEqualTo: type)
            .whereField("edgeType", isEqualTo: "belongsTo")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()
        return snap.documents.compactMap { parseEdge($0) }
    }

    // MARK: - parentsOf

    /// Returns all "belongsTo" edges where fromRef == ref.
    /// Answers: "What is this node part of / owned by?"
    /// Example: parentsOf("/posts/xyz") → the Church or Space it belongs to.
    static func parentsOf(ref: String) async throws -> [AmenEdge] {
        let snap = try await edgesCollection
            .whereField("fromRef", isEqualTo: ref)
            .whereField("edgeType", isEqualTo: "belongsTo")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()
        return snap.documents.compactMap { parseEdge($0) }
    }

    // MARK: - spawnedFrom

    /// Returns all "spawnedFrom" edges where fromRef == ref.
    /// Answers: "What objects were spawned from (created in reaction to) this node?"
    /// Example: spawnedFrom("/posts/abc") → Discussion rooms spawned via Discuss intent.
    static func spawnedFrom(ref: String) async throws -> [AmenEdge] {
        let snap = try await edgesCollection
            .whereField("fromRef", isEqualTo: ref)
            .whereField("edgeType", isEqualTo: "spawnedFrom")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()
        return snap.documents.compactMap { parseEdge($0) }
    }

    // MARK: - linkedTo

    /// Returns all "links" edges where fromRef == ref OR toRef == ref (bidirectional).
    /// Answers: "What is contextually associated with this node?"
    /// Example: linkedTo("/churchNotes/note1") → linked Sermons, BereanInsights.
    static func linkedTo(ref: String) async throws -> [AmenEdge] {
        async let outboundSnap = edgesCollection
            .whereField("fromRef", isEqualTo: ref)
            .whereField("edgeType", isEqualTo: "links")
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 50)
            .getDocuments()

        async let inboundSnap = edgesCollection
            .whereField("toRef", isEqualTo: ref)
            .whereField("edgeType", isEqualTo: "links")
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 50)
            .getDocuments()

        let (outbound, inbound) = try await (outboundSnap, inboundSnap)

        let allEdges = (outbound.documents + inbound.documents).compactMap { parseEdge($0) }
        // Deduplicate by ID in case an edge was picked up in both directions.
        var seen = Set<String>()
        return allEdges.filter { seen.insert($0.id).inserted }
    }

    // MARK: - praysForChain

    /// Returns all active "praysFor" edges for a given prayer request ref.
    /// Answers: "Who is praying for this prayer request / person?"
    /// Example: praysForChain("/prayers/abc") → all users praying for this request.
    ///
    /// NOTE per OQ-16: whether praysFor edges are client-written or CF-only is an
    /// open question. This read method is safe regardless of write origin.
    static func praysForChain(prayerRef: String) async throws -> [AmenEdge] {
        let snap = try await edgesCollection
            .whereField("toRef", isEqualTo: prayerRef)
            .whereField("edgeType", isEqualTo: "praysFor")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()
        return snap.documents.compactMap { parseEdge($0) }
    }

    // MARK: - connectionGraph

    /// Performs a BFS traversal up to `maxDepth` hops from `fromRef`,
    /// returning all edges encountered. Hard cap: 50 edges total to prevent runaway fan-out.
    ///
    /// This gives the "connected ecosystem" view for the Community OS detail screen.
    /// Example: connectionGraph(fromRef: "/churches/abc", maxDepth: 2) shows the full
    /// network: Church → Sermons → Discussion rooms → Studies → Prayers.
    ///
    /// - Parameters:
    ///   - fromRef: Starting Firestore document path.
    ///   - maxDepth: Maximum BFS hops. Default: 2. Recommended max: 3.
    /// - Returns: All distinct edges discovered within maxDepth hops, capped at 50.
    static func connectionGraph(fromRef: String, maxDepth: Int = 2) async throws -> [AmenEdge] {
        var visited = Set<String>()       // visited node refs (Firestore paths)
        var collectedEdges: [AmenEdge] = []
        var frontier: [String] = [fromRef]

        visited.insert(fromRef)

        for _ in 0 ..< maxDepth {
            guard !frontier.isEmpty else { break }
            guard collectedEdges.count < 50 else { break }

            // Fan-out limit: query all outbound edges for the current frontier.
            var nextFrontier: [String] = []

            for nodeRef in frontier {
                guard collectedEdges.count < 50 else { break }

                let remaining = 50 - collectedEdges.count
                let snap = try await edgesCollection
                    .whereField("fromRef", isEqualTo: nodeRef)
                    .whereField("isDeleted", isEqualTo: false)
                    .order(by: "createdAt", descending: true)
                    .limit(to: min(remaining, 100))
                    .getDocuments()

                for doc in snap.documents {
                    guard collectedEdges.count < 50 else { break }
                    guard let edge = parseEdge(doc) else { continue }
                    collectedEdges.append(edge)

                    // Enqueue the target node for the next BFS level if not yet visited.
                    if !visited.contains(edge.toRef) {
                        visited.insert(edge.toRef)
                        nextFrontier.append(edge.toRef)
                    }
                }
            }

            frontier = nextFrontier
        }

        return collectedEdges
    }

    // MARK: - Private: parseEdge

    /// Parses a Firestore DocumentSnapshot into an AmenEdge. Returns nil on failure.
    private static func parseEdge(_ doc: DocumentSnapshot) -> AmenEdge? {
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
