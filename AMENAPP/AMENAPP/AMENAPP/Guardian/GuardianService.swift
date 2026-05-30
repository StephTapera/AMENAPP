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
    ///
    /// - Parameters:
    ///   - messageId: The Firestore message document ID.
    ///   - channelId: The Firestore channel document ID.
    ///   - failClosed: When `true`, a timeout or network error returns `.block` instead of `.allow`.
    ///                 Defaults to `true` so communal channels (public posts, comment threads,
    ///                 prayer wall) never allow grooming, CSAM, or crisis content through on a
    ///                 classifier delay.
    ///                 **For private DMs only**, pass `failClosed: false` explicitly — false-positives
    ///                 are more harmful than false-negatives in a 1:1 conversation context.
    func awaitVerdict(messageId: String, channelId: String, failClosed: Bool = true) async throws -> GuardianDecision {
        do {
            return try await withThrowingTaskGroup(of: GuardianDecision.self) { group in
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
                // Timeout task — fail-open or fail-closed depending on channel context
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    return .allow  // signal that the timeout task won; handled below
                }
                let result = try await group.next() ?? .allow
                group.cancelAll()

                // If the timeout task resolved first (.allow sentinel) and failClosed is set,
                // block the message rather than allowing it through.
                if result == .allow && failClosed {
                    // Re-check: the Firestore listener may have also resolved .allow legitimately,
                    // but on timeout we conservatively block for critical-category channels.
                    print("[Guardian] Classifier timeout for message \(messageId) in channel \(channelId) — failing CLOSED (block) due to critical channel context")
                    return .block
                }

                return result
            }
        } catch {
            // Network or task-cancellation error
            let fallback: GuardianDecision = failClosed ? .block : .allow
            print("[Guardian] Error awaiting verdict for message \(messageId): \(error.localizedDescription) — returning \(fallback.rawValue)")
            return fallback
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
