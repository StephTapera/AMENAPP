import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class SpiritualGraphService: ObservableObject {
    static let shared = SpiritualGraphService()

    @Published private(set) var affinitySnapshot: SpiritualAffinitySnapshot?
    @Published private(set) var recentMemories: [SpiritualMemoryRecord] = []

    private lazy var db = Firestore.firestore()

    private init() {}

    func recordEdge(_ edge: SpiritualGraphEdge) async throws {
        let data = try Firestore.Encoder().encode(edge)
        try await db.collection("spiritual_graph").document("edges")
            .collection("items")
            .document(edge.id)
            .setData(data, merge: true)
    }

    func saveMemory(_ record: SpiritualMemoryRecord) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data = try Firestore.Encoder().encode(record)
        try await db.collection("users")
            .document(uid)
            .collection("spiritual_memory")
            .document(record.id)
            .setData(data, merge: true)
    }

    func loadRecentMemory(limit: Int = 12) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snapshot = try await db.collection("users")
            .document(uid)
            .collection("spiritual_memory")
            .limit(to: limit)
            .getDocuments()

        let decoder = Firestore.Decoder()
        recentMemories = snapshot.documents.compactMap { try? decoder.decode(SpiritualMemoryRecord.self, from: $0.data()) }
    }

    func loadAffinitySnapshot() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snapshot = try await db.collection("users")
            .document(uid)
            .collection("spiritual_graph_state")
            .document("affinity")
            .getDocument()

        guard let data = snapshot.data() else {
            affinitySnapshot = nil
            return
        }

        affinitySnapshot = try Firestore.Decoder().decode(SpiritualAffinitySnapshot.self, from: data)
    }

    func exportMemoryPayload() async throws -> [SpiritualMemoryRecord] {
        try await loadRecentMemory(limit: 200)
        return recentMemories
    }

    func deleteAllSpiritualMemory() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snapshot = try await db.collection("users")
            .document(uid)
            .collection("spiritual_memory")
            .getDocuments()

        let batch = db.batch()
        snapshot.documents.forEach { batch.deleteDocument($0.reference) }
        try await batch.commit()
        recentMemories = []
    }
}
