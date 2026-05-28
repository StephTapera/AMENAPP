// SpacesTypingService.swift
// AMENAPP — Spaces Chat Core (Agent B)
//
// Thin wrapper around the RTDB typing presence path used by Spaces chat.
//
// RTDB path: typing/{spaceId}/{threadId}/{userId}
//   Payload: { "userId": String, "timestamp": ServerValue.timestamp() }
//
// This path is compatible with the write path already in SpacesChatService.
// SpacesTypingService provides a lightweight, re-usable facade for views
// that need to manage typing state without holding a full SpacesChatService.
//
// Client-side stale expiry: indicators older than 5 seconds are discarded.
//
// Architecture rules:
//   - No Combine. Uses closures only.
//   - All onUpdate callbacks are dispatched to MainActor via Task { @MainActor in }.
//   - RTDB writes are fire-and-forget (presence is ephemeral).

import Foundation
import FirebaseAuth
import FirebaseDatabase

// MARK: - SpacesTypingService

final class SpacesTypingService {

    // MARK: - Constants

    static let staleThresholdSeconds: TimeInterval = 5.0

    // MARK: - Private State

    private let rtdb = Database.database().reference()
    private var observerHandle: DatabaseHandle?
    private var observedSpaceId: String?
    private var observedThreadId: String?

    // MARK: - Init / Deinit

    init() {}

    deinit {
        // Remove RTDB observer synchronously — safe from any thread.
        if let handle = observerHandle,
           let spaceId = observedSpaceId,
           let threadId = observedThreadId {
            rtdb.child("typing").child(spaceId).child(threadId)
                .removeObserver(withHandle: handle)
        }
    }

    // MARK: - Write: start / stop

    /// Writes `{ userId, timestamp }` to `typing/{spaceId}/{threadId}/{userId}`.
    /// Fire-and-forget; does not throw.
    func startTyping(spaceId: String, threadId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let ref = typingRef(spaceId: spaceId, threadId: threadId, userId: userId)
        let payload: [String: Any] = [
            "userId": userId,
            "timestamp": ServerValue.timestamp()
        ]
        ref.setValue(payload)
    }

    /// Removes the current user's node from `typing/{spaceId}/{threadId}/{userId}`.
    func stopTyping(spaceId: String, threadId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        typingRef(spaceId: spaceId, threadId: threadId, userId: userId).removeValue()
    }

    // MARK: - Observe

    /// Subscribes to the RTDB typing node for a thread.
    /// `onUpdate` is called on MainActor whenever the typing set changes.
    /// Previous observer (if any) is detached automatically.
    ///
    /// - Parameters:
    ///   - spaceId: Owning space.
    ///   - threadId: Active thread.
    ///   - onUpdate: Closure called with the array of non-stale `SpacesChatTypingIndicator`s.
    func observe(
        spaceId: String,
        threadId: String,
        onUpdate: @escaping @MainActor ([SpacesChatTypingIndicator]) -> Void
    ) {
        stopObserving()

        let currentUserId = Auth.auth().currentUser?.uid
        let ref = rtdb.child("typing").child(spaceId).child(threadId)
        let threshold = Self.staleThresholdSeconds

        // Use the `with:` label to select the single-argument (DataSnapshot) overload.
        let handle = ref.observe(.value, with: { snapshot in
            var indicators: [SpacesChatTypingIndicator] = []
            let now = Date()

            for child in snapshot.children {
                guard let childSnap = child as? DataSnapshot,
                      let dict = childSnap.value as? [String: Any] else { continue }

                let userId = dict["userId"] as? String ?? childSnap.key

                // Skip self.
                if let currentUserId, userId == currentUserId { continue }

                // RTDB ServerValue.timestamp() is milliseconds since epoch.
                let tsMillis = dict["timestamp"] as? Double ?? 0
                let ts = Date(timeIntervalSince1970: tsMillis / 1_000.0)

                // Discard stale nodes (> 5 s old).
                guard now.timeIntervalSince(ts) < threshold else { continue }

                let displayName = dict["displayName"] as? String ?? "Member"
                indicators.append(
                    SpacesChatTypingIndicator(userId: userId, displayName: displayName, timestamp: ts)
                )
            }

            Task { @MainActor in
                onUpdate(indicators)
            }
        })

        observerHandle = handle
        observedSpaceId = spaceId
        observedThreadId = threadId
    }

    /// Removes the active RTDB observer and clears observer state.
    func stopObserving() {
        if let handle = observerHandle,
           let spaceId = observedSpaceId,
           let threadId = observedThreadId {
            rtdb.child("typing").child(spaceId).child(threadId)
                .removeObserver(withHandle: handle)
        }
        observerHandle = nil
        observedSpaceId = nil
        observedThreadId = nil
    }

    // MARK: - Helpers

    private func typingRef(
        spaceId: String,
        threadId: String,
        userId: String
    ) -> DatabaseReference {
        rtdb.child("typing").child(spaceId).child(threadId).child(userId)
    }
}
