import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Protocol

protocol DiscoverServing {
    func featuredStream() -> AsyncThrowingStream<[FeaturedEntry], Error>
    func continueStream(uid: String) -> AsyncThrowingStream<[ContinueEntry], Error>
    func markEngaged(uid: String, ref: ContentRef) async throws
}

// MARK: - Live implementation

final class DiscoverService: DiscoverServing {
    static let shared = DiscoverService()
    private let db = Firestore.firestore()
    private init() {}

    /// Streams `featured` documents (active + moderation-cleared, ordered by `order`).
    /// Composite index required: active ASC + moderationCleared ASC + order ASC.
    func featuredStream() -> AsyncThrowingStream<[FeaturedEntry], Error> {
        AsyncThrowingStream { continuation in
            let reg = db.collection("featured")
                .whereField("active", isEqualTo: true)
                .whereField("moderationCleared", isEqualTo: true)
                .order(by: "order")
                .limit(to: 10)
                .addSnapshotListener { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }
                    let entries = snapshot?.documents
                        .compactMap { try? $0.data(as: FeaturedEntry.self) } ?? []
                    continuation.yield(entries)
                }
            continuation.onTermination = { _ in reg.remove() }
        }
    }

    /// Streams `users/{uid}/continue` ordered by `lastEngagedAt` descending.
    func continueStream(uid: String) -> AsyncThrowingStream<[ContinueEntry], Error> {
        AsyncThrowingStream { continuation in
            let reg = db.collection("users").document(uid)
                .collection("continue")
                .order(by: "lastEngagedAt", descending: true)
                .limit(to: 10)
                .addSnapshotListener { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }
                    let entries = snapshot?.documents
                        .compactMap { try? $0.data(as: ContinueEntry.self) } ?? []
                    continuation.yield(entries)
                }
            continuation.onTermination = { _ in reg.remove() }
        }
    }

    /// Upserts an engagement record into the user's `continue` subcollection.
    /// Call this when the user opens a post, starts a video, or enters a study.
    func markEngaged(uid: String, ref: ContentRef) async throws {
        let data: [String: Any] = [
            "contentRef": ["kind": ref.kind.rawValue, "refID": ref.refID],
            "lastEngagedAt": FieldValue.serverTimestamp()
        ]
        try await db.collection("users").document(uid)
            .collection("continue")
            .document("\(ref.kind.rawValue)_\(ref.refID)")
            .setData(data, merge: true)
    }
}
