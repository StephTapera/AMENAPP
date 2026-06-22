import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class SilenceIntelligenceService: ObservableObject {
    static let shared = SilenceIntelligenceService()

    @Published var silenceSignals: [SilenceSignal] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // Call when user skips/snoozes an item to record avoidance
    func recordAvoidance(targetType: SilenceTargetType, targetId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let docRef = db.collection("users").document(uid)
            .collection("silenceSignals")
            .document("\(targetType.rawValue)_\(targetId)")

        do {
            let snapshot = try await docRef.getDocument()
            if snapshot.exists {
                try await docRef.updateData([
                    "avoidanceCount": FieldValue.increment(Int64(1)),
                    "lastAvoidedAt": FieldValue.serverTimestamp()
                ])
            } else {
                let signal = SilenceSignal(
                    id: "\(targetType.rawValue)_\(targetId)",
                    userId: uid,
                    targetType: targetType,
                    targetId: targetId,
                    avoidanceCount: 1,
                    lastAvoidedAt: nil,
                    suggestedAction: nil,
                    status: .active
                )
                try docRef.setData(from: signal)
            }
        } catch {
            dlog("⚠️ SilenceIntelligenceService.recordAvoidance: \(error)")
        }
    }

    func resolveSilenceSignal(_ signal: SilenceSignal) async {
        guard let uid = Auth.auth().currentUser?.uid, let id = signal.id else { return }
        do {
            try await db.collection("users").document(uid)
                .collection("silenceSignals").document(id)
                .updateData(["status": SilenceSignalStatus.resolved.rawValue])
        } catch {
            dlog("⚠️ SilenceIntelligenceService.resolveSilenceSignal: \(error)")
        }
    }

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db.collection("users").document(uid)
            .collection("silenceSignals")
            .whereField("status", isEqualTo: "active")
            .whereField("avoidanceCount", isGreaterThanOrEqualTo: 2)
            .order(by: "avoidanceCount", descending: true)
            .limit(to: 10)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                self.silenceSignals = docs.compactMap { try? $0.data(as: SilenceSignal.self) }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }
}
