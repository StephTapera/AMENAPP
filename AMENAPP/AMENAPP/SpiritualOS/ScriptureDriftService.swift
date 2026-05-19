import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class ScriptureDriftService: ObservableObject {
    static let shared = ScriptureDriftService()

    @Published var driftSignals: [ScriptureDriftSignal] = []
    @Published var isAnalyzing = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    func requestAnalysis() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let callable = Functions.functions().httpsCallable("analyzeScriptureDrift")
            _ = try await callable.call(["userId": uid])
        } catch {
            // Silent — background analysis
        }
    }

    func generateBalancingScripture(for signal: ScriptureDriftSignal) async -> [String] {
        do {
            let callable = Functions.functions().httpsCallable("generateBalancingScripture")
            let result = try await callable.call(["signalId": signal.id ?? ""])
            if let data = result.data as? [String: Any],
               let refs = data["scriptures"] as? [String] {
                return refs
            }
        } catch {
            dlog("⚠️ ScriptureDriftService.generateBalancingScripture: \(error)")
        }
        return []
    }

    func dismissSignal(_ signal: ScriptureDriftSignal) async {
        guard let uid = Auth.auth().currentUser?.uid, let id = signal.id else { return }
        do {
            try await db.collection("users").document(uid)
                .collection("scriptureDriftSignals").document(id)
                .updateData(["dismissed": true])
        } catch {
            dlog("⚠️ ScriptureDriftService.dismissSignal: \(error)")
        }
    }

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db.collection("users").document(uid)
            .collection("scriptureDriftSignals")
            .whereField("dismissed", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                self.driftSignals = docs.compactMap { try? $0.data(as: ScriptureDriftSignal.self) }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }
}
