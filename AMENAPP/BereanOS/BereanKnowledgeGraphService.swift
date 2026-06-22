// BereanKnowledgeGraphService.swift
// AMENAPP/BereanOS
// Manages the personal knowledge graph for Berean OS — CRUD, linking, and AI discovery.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Service

@MainActor
final class BereanKnowledgeGraphService: ObservableObject {
    static let shared = BereanKnowledgeGraphService()

    @Published private(set) var nodes: [BereanKnowledgeNode] = []
    @Published private(set) var isDiscovering = false

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private init() {}

    // MARK: - Firestore Helpers

    private func graphCollection(uid: String) -> CollectionReference {
        db.collection(BereanOSFirestore.knowledgeGraph(uid: uid))
    }

    // MARK: - Add Node

    /// Writes a new knowledge node to Firestore.
    func addNode(_ node: BereanKnowledgeNode) async throws {
        guard AMENFeatureFlags.shared.bereanOSKnowledgeGraphEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let data: [String: Any] = [
            "id": node.id,
            "ownerUid": node.ownerUid,
            "title": node.title,
            "nodeType": node.nodeType.rawValue,
            "linkedNodeIds": node.linkedNodeIds,
            "projectIds": node.projectIds,
            "metadata": node.metadata,
            "createdAt": Timestamp(date: node.createdAt),
            "updatedAt": Timestamp(date: node.updatedAt)
        ]

        try await graphCollection(uid: uid)
            .document(node.id)
            .setData(data)

        // Insert or update in local cache
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            nodes[index] = node
        } else {
            nodes.append(node)
        }
    }

    // MARK: - Link Nodes

    /// Adds a mutual link between two nodes (appends each id to the other's `linkedNodeIds`).
    func linkNodes(_ nodeAId: String, _ nodeBId: String, relationshipType: String) async throws {
        guard AMENFeatureFlags.shared.bereanOSKnowledgeGraphEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let collection = graphCollection(uid: uid)
        let batch = db.batch()

        let refA = collection.document(nodeAId)
        let refB = collection.document(nodeBId)

        batch.updateData([
            "linkedNodeIds": FieldValue.arrayUnion([nodeBId]),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: refA)

        batch.updateData([
            "linkedNodeIds": FieldValue.arrayUnion([nodeAId]),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: refB)

        try await batch.commit()

        // Reflect changes in local cache
        for index in nodes.indices {
            if nodes[index].id == nodeAId, !nodes[index].linkedNodeIds.contains(nodeBId) {
                nodes[index].linkedNodeIds.append(nodeBId)
            }
            if nodes[index].id == nodeBId, !nodes[index].linkedNodeIds.contains(nodeAId) {
                nodes[index].linkedNodeIds.append(nodeAId)
            }
        }
    }

    // MARK: - Fetch Related Nodes

    /// Returns nodes whose `linkedNodeIds` array contains the given nodeId.
    func fetchRelatedNodes(for nodeId: String, limit: Int) async throws -> [BereanKnowledgeNode] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }

        let snapshot = try await graphCollection(uid: uid)
            .whereField("linkedNodeIds", arrayContains: nodeId)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap { decodeNode($0) }
    }

    // MARK: - Discover Hidden Relationships

    /// Calls the `bereanDiscoverKnowledgeLinks` Cloud Function.
    func discoverHiddenRelationships() async throws {
        guard AMENFeatureFlags.shared.bereanOSKnowledgeGraphEnabled else { return }

        isDiscovering = true
        defer { isDiscovering = false }

        _ = try await functions
            .httpsCallable("bereanDiscoverKnowledgeLinks")
            .call(["limit": 50])

        // Re-fetch to pick up newly linked nodes
        try await fetchNodes()
    }

    // MARK: - Fetch All Nodes

    /// Loads the current user's knowledge graph nodes from Firestore.
    func fetchNodes() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let snapshot = try await graphCollection(uid: uid)
            .order(by: "updatedAt", descending: true)
            .limit(to: 200)
            .getDocuments()

        nodes = snapshot.documents.compactMap { decodeNode($0) }
    }

    // MARK: - Decoding

    private func decodeNode(_ document: QueryDocumentSnapshot) -> BereanKnowledgeNode? {
        let data = document.data()
        guard
            let id = data["id"] as? String,
            let ownerUid = data["ownerUid"] as? String,
            let title = data["title"] as? String,
            let nodeTypeRaw = data["nodeType"] as? String,
            let nodeType = BereanKnowledgeNodeType(rawValue: nodeTypeRaw),
            let createdAtTs = data["createdAt"] as? Timestamp,
            let updatedAtTs = data["updatedAt"] as? Timestamp
        else { return nil }

        return BereanKnowledgeNode(
            id: id,
            title: title,
            nodeType: nodeType,
            ownerUid: ownerUid,
            linkedNodeIds: data["linkedNodeIds"] as? [String] ?? [],
            projectIds: data["projectIds"] as? [String] ?? [],
            metadata: data["metadata"] as? [String: String] ?? [:],
            createdAt: createdAtTs.dateValue(),
            updatedAt: updatedAtTs.dateValue()
        )
    }
}
