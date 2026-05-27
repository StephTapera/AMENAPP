import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Model

struct SermonFeedItem: Identifiable {
    let id: String
    let title: String
    let durationMinutes: Int?
    let thumbnailURL: URL?
    let publishedAt: Date

    var durationLabel: String {
        guard let min = durationMinutes else { return "Teaching" }
        return "\(min) min"
    }
}

// MARK: - Service

/// Listens to `arise/sermons/published` (ordered by publishedAt desc) and
/// exposes the latest item for the Home hero carousel.
/// Collection schema:
///   title: String
///   durationMinutes: Int (optional)
///   thumbnailURL: String (optional, Firebase Storage download URL)
///   publishedAt: Timestamp
@MainActor
final class SermonFeedService: ObservableObject {
    static let shared = SermonFeedService()

    @Published private(set) var latestSermon: SermonFeedItem?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {
        startListening()
    }

    private func startListening() {
        guard Auth.auth().currentUser != nil else { return }
        listener = db.collection("arise")
            .document("sermons")
            .collection("published")
            .order(by: "publishedAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, error == nil,
                      let doc = snapshot?.documents.first else { return }
                self.latestSermon = SermonFeedItem(from: doc)
            }
    }

    func reconnect() {
        listener?.remove()
        startListening()
    }

    deinit { listener?.remove() }
}

private extension SermonFeedItem {
    init?(from doc: QueryDocumentSnapshot) {
        let data = doc.data()
        guard let title = data["title"] as? String else { return nil }
        id = doc.documentID
        self.title = title
        durationMinutes = data["durationMinutes"] as? Int
        thumbnailURL = (data["thumbnailURL"] as? String).flatMap(URL.init(string:))
        publishedAt = (data["publishedAt"] as? Timestamp)?.dateValue() ?? Date()
    }
}
