import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - GuardianService
//
// iOS-side counterpart to the guardianClassify Cloud Function.
//
// Cloud Function flow (communal + monitored channels only):
//   1. ChannelService writes message with isDelivered=false
//   2. Firestore onCreate triggers `guardianClassify`
//   3. Function calls Claude via existing `bereanChatProxy` callable with GUARDIAN system prompt
//   4. Function writes back: isDelivered, guardianDecision, supportResourcesAttached
//   5. block   → isDelivered=false; sender notified
//   6. escalate→ isDelivered=false; written to moderationQueue/{id} (admin-only)
//              → route=="legal" additionally triggers CSAM/legal path
//   7. allow_with_support → isDelivered=true + supportResourcesAttached=true
//
// Sacred channels: this service NEVER touches sacredMessages or keyMaterial subcollections.
// That invariant must also be enforced in the Cloud Function (deny reads of those subcollections).

@MainActor
final class GuardianService: ObservableObject {
    static let shared = GuardianService()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Await Verdict

    /// Listens for the Guardian Cloud Function to write back a decision on a sent message.
    /// Resolves on the first non-nil guardianDecision update.
    /// Times out after 10 seconds and returns .allow (fail-open on timeout to avoid blocking UX).
    func awaitVerdict(messageId: String, channelId: String) async throws -> GuardianDecision {
        try await withThrowingTaskGroup(of: GuardianDecision.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    var listener: ListenerRegistration?
                    listener = Firestore.firestore()
                        .collection("channels").document(channelId)
                        .collection("messages").document(messageId)
                        .addSnapshotListener { snap, _ in
                            guard let raw = snap?.data()?["guardianDecision"] as? String,
                                  let decision = GuardianDecision(rawValue: raw) else { return }
                            listener?.remove()
                            continuation.resume(returning: decision)
                        }
                }
            }
            // Timeout task — fail-open so slow classifications don't block the composer
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                return .allow
            }
            let result = try await group.next() ?? .allow
            group.cancelAll()
            return result
        }
    }

    // MARK: - Crisis Resources

    func crisisResources() -> [GuardianCrisisResource] {
        GuardianCrisisResource.forRegion()
    }
}

// MARK: - Cloud Function Reference
//
// The guardianClassify function should be deployed to your Firebase project.
// See CloudFunctions/guardian.ts in this repo for the implementation.
// It uses the GUARDIAN system prompt from the spec and calls `bereanChatProxy`.
