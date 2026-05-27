// AmenPersistentMemoryGraphService.swift
// AMEN App — Persistent Memory Graph
//
// Layered memory: user / relationship / group / spiritual / organizational / temporal.
// Wraps existing BereanMemoryService and ChatMemoryService — adds Spaces context.
// All writes to confidence/provenance fields go through server callables only.

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AmenPersistentMemoryGraphService: ObservableObject {

    static let shared = AmenPersistentMemoryGraphService()

    @Published private(set) var spaceMemoryNodes: [AmenMemoryNode] = []
    @Published private(set) var userMemoryNodes: [AmenMemoryNode] = []
    @Published private(set) var spiritualContinuity: AmenSpiritualContinuityRecord?
    @Published private(set) var isLoading: Bool = false

    private let db = Firestore.firestore()
    private var userId: String { Auth.auth().currentUser?.uid ?? "" }

    private init() {}

    // MARK: - Load Memory for a Space

    func loadSpaceMemory(spaceId: String) async {
        guard AMENFeatureFlags.shared.persistentMemoryGraphEnabled else { return }
        guard !userId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let snap = try await db
                .collection("spaces").document(spaceId)
                .collection("memory")
                .whereField("dismissed", isEqualTo: false)
                .order(by: "generatedAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            spaceMemoryNodes = snap.documents.compactMap { try? $0.data(as: AmenMemoryNode.self) }
        } catch {
            dlog("[AmenPersistentMemoryGraphService] loadSpaceMemory error: \(error)")
        }
    }

    // MARK: - Load User Memory for a Space

    func loadUserSpaceMemory(spaceId: String) async {
        guard AMENFeatureFlags.shared.persistentMemoryGraphEnabled else { return }
        guard !userId.isEmpty else { return }

        do {
            let snap = try await db
                .collection("users").document(userId)
                .collection("spaceMemory")
                .whereField("spaceId", isEqualTo: spaceId)
                .whereField("dismissed", isEqualTo: false)
                .order(by: "generatedAt", descending: true)
                .limit(to: 10)
                .getDocuments()

            userMemoryNodes = snap.documents.compactMap { try? $0.data(as: AmenMemoryNode.self) }
        } catch {
            dlog("[AmenPersistentMemoryGraphService] loadUserSpaceMemory error: \(error)")
        }
    }

    // MARK: - Load Spiritual Continuity

    func loadSpiritualContinuity(spaceId: String? = nil) async {
        guard AMENFeatureFlags.shared.spiritualContinuityEngineEnabled else { return }
        guard !userId.isEmpty else { return }

        do {
            var query = db.collection("users").document(userId)
                .collection("spiritualContinuity")
                .order(by: "generatedAt", descending: true)
                .limit(to: 1)

            if let sid = spaceId {
                query = db.collection("users").document(userId)
                    .collection("spiritualContinuity")
                    .whereField("spaceId", isEqualTo: sid)
                    .order(by: "generatedAt", descending: true)
                    .limit(to: 1)
            }

            let snap = try await query.getDocuments()
            spiritualContinuity = snap.documents.first.flatMap { try? $0.data(as: AmenSpiritualContinuityRecord.self) }
        } catch {
            dlog("[AmenPersistentMemoryGraphService] loadSpiritualContinuity error: \(error)")
        }
    }

    // MARK: - Dismiss a Memory Node

    func dismissMemoryNode(id: String, spaceId: String) async {
        guard !userId.isEmpty else { return }

        // Try space-level first, then user-level
        let spacePath = db.collection("spaces").document(spaceId)
            .collection("memory").document(id)
        let userPath = db.collection("users").document(userId)
            .collection("spaceMemory").document(id)

        do {
            let batch = db.batch()
            batch.updateData(["dismissed": true], forDocument: spacePath)
            batch.updateData(["dismissed": true], forDocument: userPath)
            try await batch.commit()

            spaceMemoryNodes.removeAll { $0.id == id }
            userMemoryNodes.removeAll { $0.id == id }
        } catch {
            dlog("[AmenPersistentMemoryGraphService] dismissMemoryNode error: \(error)")
        }
    }

    // MARK: - Node Accessors by Layer

    func nodes(for layer: AmenMemoryLayer, spaceId: String) -> [AmenMemoryNode] {
        (spaceMemoryNodes + userMemoryNodes)
            .filter { $0.layer == layer && $0.spaceId == spaceId && $0.isActive }
            .sorted { $0.confidence > $1.confidence }
    }

    func topNodes(spaceId: String, limit: Int = 5) -> [AmenMemoryNode] {
        (spaceMemoryNodes + userMemoryNodes)
            .filter { $0.spaceId == spaceId && $0.isActive }
            .sorted { $0.confidence > $1.confidence }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Spiritual Layer Helpers

    var recurringScriptureThemes: [String] {
        spiritualContinuity?.scriptureJourney.prefix(3).map { $0 } ?? []
    }

    var unfinishedReflectionCount: Int {
        spiritualContinuity?.unfinishedReflections.count ?? 0
    }
}
