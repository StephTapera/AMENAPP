import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class EternalWeightService: ObservableObject {
    static let shared = EternalWeightService()

    @Published var signals: [EternalWeightSignal] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    func fetchSignal(for contentId: String) async -> EternalWeightSignal? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        do {
            let doc = try await db.collection("users").document(uid)
                .collection("eternalWeightSignals").document(contentId)
                .getDocument()
            return try? doc.data(as: EternalWeightSignal.self)
        } catch {
            return nil
        }
    }

    func calculateWeight(for contentId: String) async {
        guard Auth.auth().currentUser != nil else { return }

        do {
            let callable = Functions.functions().httpsCallable("calculateEternalWeight")
            _ = try await callable.call(["contentId": contentId])
        } catch {
            dlog("⚠️ EternalWeightService.calculateWeight: \(error)")
        }
    }

    func afterReflection(signalId: String, reflectionOutcome: String) async {
        guard Auth.auth().currentUser != nil else { return }

        do {
            let callable = Functions.functions().httpsCallable("updateEternalWeightAfterReflection")
            _ = try await callable.call([
                "signalId": signalId,
                "reflectionOutcome": reflectionOutcome
            ])
        } catch {
            dlog("⚠️ EternalWeightService.afterReflection: \(error)")
        }
    }

    func getMeaningPrompt(for contentId: String) async -> String? {
        do {
            let callable = Functions.functions().httpsCallable("generateMeaningPrompt")
            let result = try await callable.call(["contentId": contentId])
            if let data = result.data as? [String: Any] {
                return data["prompt"] as? String
            }
        } catch {
            dlog("⚠️ EternalWeightService.getMeaningPrompt: \(error)")
        }
        return nil
    }

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db.collection("users").document(uid)
            .collection("eternalWeightSignals")
            .order(by: "updatedAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                self.signals = docs.compactMap { try? $0.data(as: EternalWeightSignal.self) }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }
}
