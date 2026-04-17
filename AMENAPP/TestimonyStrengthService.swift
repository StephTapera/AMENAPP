import Foundation
import FirebaseFirestore
import Combine

/// Observes post.testimonyStrength and exposes counts for the UI chips.
final class TestimonyStrengthService: ObservableObject {
    @Published var strength: Int = 0         // 0-100
    @Published var witnessCount: Int = 0
    @Published var prayerEchoCount: Int = 0
    @Published var scriptureCount: Int = 0
    @Published var isAtMax: Bool = false

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startListening(postId: String) {
        listener = db.collection("posts").document(postId)
            .addSnapshotListener { [weak self] snap, _ in
                guard let data = snap?.data() else { return }
                let s = data["testimonyStrength"] as? Int ?? 0
                self?.strength        = min(s, 100)
                self?.witnessCount    = data["witnessCount"] as? Int ?? 0
                self?.prayerEchoCount = data["prayerEchoCount"] as? Int ?? 0
                self?.scriptureCount  = data["scriptureCount"] as? Int ?? 0
                self?.isAtMax         = s >= 100
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}
