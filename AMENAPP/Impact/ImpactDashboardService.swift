import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class ImpactDashboardService: ObservableObject {
    @Published var metrics: ImpactMetrics = .empty
    @Published var badges: [ImpactBadge] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private var metricsListener: ListenerRegistration?
    private var badgesListener: ListenerRegistration?

    var userId: String? { Auth.auth().currentUser?.uid }

    func startListening() {
        guard let uid = userId else { return }
        isLoading = true
        metricsListener = db.collection("users").document(uid)
            .collection("impactMetrics")
            .order(by: "updatedAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                isLoading = false
                if let doc = snapshot?.documents.first {
                    self.metrics = (try? doc.data(as: ImpactMetrics.self)) ?? .empty
                }
            }
        badgesListener = db.collection("users").document(uid)
            .collection("badges")
            .order(by: "earnedAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snapshot, _ in
                self?.badges = (snapshot?.documents ?? []).compactMap { try? $0.data(as: ImpactBadge.self) }
            }
    }

    deinit {
        metricsListener?.remove()
        badgesListener?.remove()
    }
}
