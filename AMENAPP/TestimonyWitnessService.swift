import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// Manages real-time witness presence for testimony posts.
/// Writes/deletes the current user's presence doc and listens to the active count.
@MainActor
final class TestimonyWitnessService: ObservableObject {
    @Published var activeWitnesses: [WitnessPresence] = []

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var currentPostId: String?

    struct WitnessPresence: Identifiable {
        let id: String      // uid
        let uid: String
        let displayName: String
        let photoURL: String?
        let timestamp: Date
    }

    func startWitnessing(postId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        currentPostId = postId

        // Write presence doc
        let ref = db.collection("witnesses").document(postId)
            .collection("active").document(uid)
        ref.setData(["uid": uid, "timestamp": Timestamp(date: Date())])

        // Permanent history for ripple tracking (not cleaned up by cleanStaleWitnesses)
        db.collection("witnesses").document(postId)
            .collection("history").document(uid)
            .setData(["uid": uid, "viewedAt": Timestamp(date: Date())], merge: true)

        // Listen to active subcollection
        let cutoff = Date().addingTimeInterval(-90) // 90s window for real-time feel
        listener = db.collection("witnesses").document(postId)
            .collection("active")
            .whereField("timestamp", isGreaterThan: Timestamp(date: cutoff))
            .addSnapshotListener { [weak self] snap, _ in
                guard let docs = snap?.documents else { return }
                let now = Date()
                // Filter to last 60 seconds
                let fresh = docs.filter {
                    guard let ts = ($0.data()["timestamp"] as? Timestamp)?.dateValue() else { return false }
                    return now.timeIntervalSince(ts) < 60
                }
                // Map to WitnessPresence — display name/photo fetched lazily
                self?.activeWitnesses = fresh.map { doc in
                    WitnessPresence(
                        id: doc.documentID,
                        uid: doc.documentID,
                        displayName: doc.data()["displayName"] as? String ?? "",
                        photoURL: doc.data()["photoURL"] as? String,
                        timestamp: (doc.data()["timestamp"] as? Timestamp)?.dateValue() ?? now
                    )
                }
            }

        // Also fetch display names for presence docs missing them
        Task { await enrichPresenceDocs(postId: postId, uid: uid) }
    }

    func stopWitnessing() {
        listener?.remove()
        listener = nil
        if let postId = currentPostId, let uid = Auth.auth().currentUser?.uid {
            db.collection("witnesses").document(postId)
                .collection("active").document(uid).delete()
        }
        currentPostId = nil
    }

    private func enrichPresenceDocs(postId: String, uid: String) async {
        guard let userDoc = try? await Firestore.firestore()
            .collection("users").document(uid).getDocument(),
              let data = userDoc.data() else { return }
        let name = data["displayName"] as? String ?? data["username"] as? String ?? ""
        let photo = data["profileImageURL"] as? String ?? ""
        try? await db.collection("witnesses").document(postId)
            .collection("active").document(uid)
            .setData(["uid": uid, "timestamp": Timestamp(date: Date()),
                      "displayName": name, "photoURL": photo], merge: true)
    }
}
