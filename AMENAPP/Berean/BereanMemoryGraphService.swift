// BereanMemoryGraphService.swift
// AMENAPP — Berean Intelligence OS
//
// MemoryNode abstraction layer — writes BereanMemoryNode documents directly
// to Firestore (not via Cloud Functions). Distinct from BereanMemoryService,
// which uses the `bereanExtended` callable family and manages BereanInsight objects.
//
// Firestore path: users/{uid}/memoryGraph/{nodeId}
// Sensitivity "SENSITIVE" nodes are protected by Firestore rules —
// no cross-user reads are permitted at the rule level.
//
// INVARIANT: .crisis formation nodes are NEVER written to the memory graph.

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Service

@MainActor
final class BereanMemoryGraphService: ObservableObject {
    static let shared = BereanMemoryGraphService()

    @Published var recentNodes: [BereanMemoryNode] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Firestore Path

    private func graphCollection(uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("memoryGraph")
    }

    // MARK: - Write

    /// Writes a BereanMemoryNode to Firestore.
    /// INVARIANT: If node.kind == .formation and the node data signals a crisis
    /// card, the write is rejected — crisis events must never enter the memory graph.
    func addNode(_ node: BereanMemoryNode) async throws {
        if node.kind == .formation {
            guard validateNotCrisis(node) else {
                // Crisis formation entries are handled exclusively by Trust OS —
                // they must never be stored as memory graph nodes.
                return
            }
        }
        try await graphCollection(uid: node.uid)
            .document(node.id)
            .setData(node.toFirestore())
    }

    // MARK: - Read

    /// Fetches nodes matching the requested kinds for the given user.
    func fetchNodes(uid: String, kinds: [BereanMemoryNode.Kind]) async -> [BereanMemoryNode] {
        guard !kinds.isEmpty else { return [] }
        do {
            let snapshot = try await graphCollection(uid: uid)
                .whereField("kind", in: kinds.map(\.rawValue))
                .getDocuments()
            return snapshot.documents.compactMap { decode($0) }
        } catch {
            return []
        }
    }

    // MARK: - Delete

    /// Hard-deletes a single node. Users own their data; no soft-delete.
    func deleteNode(uid: String, nodeId: String) async throws {
        try await graphCollection(uid: uid).document(nodeId).delete()
    }

    // MARK: - Export

    /// Returns every node for the given user — used for data-export / GDPR flows.
    func exportAllNodes(uid: String) async -> [BereanMemoryNode] {
        do {
            let snapshot = try await graphCollection(uid: uid).getDocuments()
            return snapshot.documents.compactMap { decode($0) }
        } catch {
            return []
        }
    }

    // MARK: - Real-time listener

    /// Starts a live listener that keeps `recentNodes` up-to-date.
    /// Call again with a new uid after a user switch; the old listener is removed first.
    func listenToRecentNodes(uid: String, limit: Int = 20) {
        listener?.remove()
        listener = graphCollection(uid: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                Task { @MainActor [weak self] in
                    self?.recentNodes = snapshot.documents.compactMap { self?.decode($0) }
                }
            }
    }

    // MARK: - Private helpers

    /// Returns false when a formation node's data marks it as a crisis card.
    /// This is the last safety gate before a write reaches Firestore.
    private func validateNotCrisis(_ node: BereanMemoryNode) -> Bool {
        node.data["cardKind"]?.uppercased() != FormationCardKind.crisis.rawValue
    }

    private func decode(_ document: QueryDocumentSnapshot) -> BereanMemoryNode? {
        let d = document.data()
        guard
            let id            = d["id"] as? String,
            let uid           = d["uid"] as? String,
            let kindRaw       = d["kind"] as? String,
            let kind          = BereanMemoryNode.Kind(rawValue: kindRaw),
            let data          = d["data"] as? [String: String],
            let sensitivityRaw = d["sensitivity"] as? String,
            let sensitivity   = BereanMemoryNode.Sensitivity(rawValue: sensitivityRaw),
            let createdAt     = d["createdAt"] as? TimeInterval
        else { return nil }

        // Reconstruct with the Firestore id/createdAt so the decoded value matches.
        // `userControlled` defaults true in the type.
        return BereanMemoryNode(
            id: id,
            uid: uid,
            kind: kind,
            data: data,
            sensitivity: sensitivity,
            createdAt: createdAt
        )
    }
}

// MARK: - BereanMemoryNode memberwise init extension
// The public init in BereanFaithOSContracts generates a new UUID + timestamp.
// We need a restore-from-Firestore path that preserves the stored id/createdAt.

private extension BereanMemoryNode {
    init(id: String, uid: String, kind: Kind, data: [String: String],
         sensitivity: Sensitivity, createdAt: TimeInterval) {
        self.id           = id
        self.uid          = uid
        self.kind         = kind
        self.data         = data
        self.sensitivity  = sensitivity
        self.createdAt    = createdAt
        self.userControlled = true
    }
}
