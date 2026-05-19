import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class RelationalGravityService: ObservableObject {
    static let shared = RelationalGravityService()

    @Published var nodes: [RelationalGravityNode] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    func upsertNode(personId: String, displayName: String, relationshipType: RelationshipType) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let docRef = db.collection("users").document(uid)
            .collection("relationalGravityNodes").document(personId)

        do {
            let snapshot = try await docRef.getDocument()
            if !snapshot.exists {
                let node = RelationalGravityNode(
                    id: personId,
                    userId: uid,
                    personId: personId,
                    displayName: displayName,
                    relationshipType: relationshipType,
                    currentState: .peaceful,
                    stateConfidence: 0.5,
                    unresolvedThreadIds: [],
                    encouragementScore: 0.5,
                    conflictScore: 0.0,
                    prayerCount: 0,
                    lastInteractionAt: nil
                )
                try docRef.setData(from: node)
            }
        } catch { dlog("⚠️ RelationalGravityService.upsertNode: \(error)") }
    }

    func recordInteraction(personId: String, type: String) async {
        guard Auth.auth().currentUser != nil else { return }

        do {
            let callable = Functions.functions().httpsCallable("updateRelationalGravity")
            _ = try await callable.call([
                "personId": personId,
                "interactionType": type
            ])
        } catch { dlog("⚠️ RelationalGravityService.recordInteraction: \(error)") }
    }

    func prayForPerson(_ node: RelationalGravityNode) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid)
                .collection("relationalGravityNodes").document(node.personId)
                .updateData([
                    "prayerCount": FieldValue.increment(Int64(1)),
                    "updatedAt": FieldValue.serverTimestamp()
                ])
        } catch { dlog("⚠️ RelationalGravityService.prayForPerson: \(error)") }
    }

    func getReconciliationPrompt(for node: RelationalGravityNode) async -> String? {
        do {
            let callable = Functions.functions().httpsCallable("generateReconciliationPrompt")
            let result = try await callable.call(["nodeId": node.id ?? ""])
            if let data = result.data as? [String: Any] {
                return data["prompt"] as? String
            }
        } catch { dlog("⚠️ RelationalGravityService.getReconciliationPrompt: \(error)") }
        return nil
    }

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db.collection("users").document(uid)
            .collection("relationalGravityNodes")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                self.nodes = docs.compactMap { try? $0.data(as: RelationalGravityNode.self) }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }
}
