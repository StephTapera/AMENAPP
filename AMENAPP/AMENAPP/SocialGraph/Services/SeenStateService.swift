// SeenStateService.swift
// AMENAPP
//
// Marks relationship activity as "seen" by calling the `markRelationshipSeen`
// Cloud Function. Debounces rapid calls (e.g. scrolling past many rows).
// Local-optimistic: updates cache immediately, syncs in background.

import Foundation
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class SeenStateService {

    static let shared = SeenStateService()

    private let functions = Functions.functions()
    private var pendingMarkSeen: Set<String> = []
    private var debounceTask: Task<Void, Never>?

    private init() {}

    // MARK: - Mark Seen

    /// Queue a "mark seen" for targetId. Debounced — batches calls within 1.5s.
    func markSeen(targetId: String) {
        pendingMarkSeen.insert(targetId)
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    func flushImmediately() async {
        debounceTask?.cancel()
        await flush()
    }

    // MARK: - Private

    private func flush() async {
        guard !pendingMarkSeen.isEmpty,
              let viewerId = Auth.auth().currentUser?.uid else { return }

        let batch = Array(pendingMarkSeen)
        pendingMarkSeen.removeAll()

        do {
            _ = try await functions.httpsCallable("markRelationshipSeen").call([
                "viewerId": viewerId,
                "targetIds": batch,
            ])
        } catch {
            dlog("[SeenState] markSeen error: \(error)")
            // Re-queue on failure (best-effort)
            pendingMarkSeen.formUnion(batch)
        }
    }
}
