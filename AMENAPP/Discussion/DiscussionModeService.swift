// DiscussionModeService.swift — AMEN App
import Foundation
import FirebaseFirestore

@MainActor
final class DiscussionModeService {
    static let shared = DiscussionModeService()
    private init() {}
    private let db = Firestore.firestore()

    var isEnabled: Bool { AMENFeatureFlags.shared.discussionModesEnabled }

    func getMode(threadId: String) async throws -> DiscussionMode {
        let snap = try await db.collection("threads").document(threadId).getDocument()
        guard let raw = snap.data()?["discussionMode"] as? String,
              let mode = DiscussionMode(rawValue: raw) else { return .general }
        return mode
    }

    func setThreadMode(threadId: String, mode: DiscussionMode) async throws {
        try await db.collection("threads").document(threadId)
            .updateData(["discussionMode": mode.rawValue, "updatedAt": Timestamp(date: Date())])
    }

    func listenMode(
        threadId: String,
        onChange: @escaping (DiscussionMode) -> Void
    ) -> ListenerRegistration {
        db.collection("threads").document(threadId)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    guard let raw = snap?.data()?["discussionMode"] as? String,
                          let mode = DiscussionMode(rawValue: raw) else { return }
                    onChange(mode)
                }
            }
    }
}
