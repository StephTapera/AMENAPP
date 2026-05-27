import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class CrisisIndicatorService: ObservableObject {
    @Published var supportStatus: SupportStatus?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    var userId: String? { Auth.auth().currentUser?.uid }

    func startListening() {
        guard let uid = userId else { return }
        listener = db.collection("users").document(uid)
            .collection("supportStatus").document("current")
            .addSnapshotListener { [weak self] snapshot, _ in
                self?.supportStatus = try? snapshot?.data(as: SupportStatus.self)
            }
    }

    func logCrisisPageAccess() async {
        guard let uid = userId else { return }
        try? await db.collection("users").document(uid)
            .collection("supportStatus").document("current")
            .setData(["lastCrisisPageAccess": Timestamp(date: Date())], merge: true)
    }

    func optOutOfProactiveSupport() async {
        guard let uid = userId else { return }
        try? await db.collection("users").document(uid)
            .collection("supportStatus").document("current")
            .setData(["optedIntoProactiveSupport": false], merge: true)
    }

    func optInToProactiveSupport() async {
        guard let uid = userId else { return }
        try? await db.collection("users").document(uid)
            .collection("supportStatus").document("current")
            .setData(["optedIntoProactiveSupport": true], merge: true)
    }

    deinit { listener?.remove() }
}
