import Foundation
import FirebaseFirestore

actor TrustEventRecorder {

    static let shared = TrustEventRecorder()

    private let db = Firestore.firestore()
    private var eventBuffer: [TrustEvent] = []
    private let maxBufferSize = 10

    private init() {}

    func record(_ event: TrustEvent) async {
        eventBuffer.append(event)
        if eventBuffer.count >= maxBufferSize {
            await flush()
        }
    }

    func recordPostCreated(userId: String, postId: String, category: String) async {
        await record(.init(id: UUID().uuidString, userId: userId, eventType: .postCreated, category: .both, value: 0.3, source: "PostCreation", relatedEntityId: postId, timestamp: Date(), metadata: ["category": category]))
    }

    func recordComposerIntegrity(userId: String, typedRatio: Double) async {
        await record(.init(id: UUID().uuidString, userId: userId, eventType: .composerIntegrity, category: .human, value: typedRatio, source: "ComposerIntegrityTracker", relatedEntityId: nil, timestamp: Date(), metadata: nil))
    }

    func flush() async {
        guard !eventBuffer.isEmpty else { return }
        let events = eventBuffer
        eventBuffer.removeAll()
        let batch = db.batch()
        for event in events {
            let ref = db.collection("users").document(event.userId)
                .collection("trust").document("events")
                .collection("items").document(event.id)
            do {
                try batch.setData(from: event, forDocument: ref)
            } catch {
                dlog("[TrustEventRecorder] encode failed: \(error.localizedDescription)")
            }
        }
        do {
            try await batch.commit()
        } catch {
            dlog("[TrustEventRecorder] flush failed: \(error.localizedDescription)")
        }
    }
}
