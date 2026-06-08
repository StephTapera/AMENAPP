// FiniteMediaQueueService.swift
// AMENAPP
//
// Manages finite, curated media queues — opposing infinite-scroll behavior.
// When a queue ends the user must actively choose to build a new one.
// Gated by `finiteMediaQueuesEnabled`; returns empty state gracefully when off.

import Foundation
import Combine
import FirebaseFunctions

@MainActor
final class FiniteMediaQueueService: ObservableObject {

    static let shared = FiniteMediaQueueService()

    // MARK: - Published State

    @Published private(set) var currentQueue: [String] = []   // postIds in order
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isQueueComplete: Bool = false
    @Published private(set) var isBuildingQueue: Bool = false
    @Published private(set) var lastError: String?

    // MARK: - Constants

    private let maxQueueSize = 12

    // MARK: - Dependencies

    private let flags = AMENFeatureFlags.shared
    private let functions = Functions.functions()

    private init() {}

    // MARK: - Queue Construction

    /// Builds a finite media queue from a seed post and topic preferences.
    /// Calls the `buildFiniteMediaQueue` Cloud Function.
    /// - Parameters:
    ///   - seed: A postId to anchor the recommendation context.
    ///   - topics: Topic strings to weight the queue (e.g. ["worship", "testimony"]).
    func buildQueue(seed: String, topics: [String]) async throws {
        guard flags.finiteMediaQueuesEnabled else {
            dlog("[FiniteMediaQueueService] Flag off — skipping queue build")
            return
        }

        dlog("[FiniteMediaQueueService] Building queue — seed: \(seed), topics: \(topics)")
        isBuildingQueue = true
        lastError = nil
        defer { isBuildingQueue = false }

        let payload: [String: Any] = [
            "seed": seed,
            "topics": topics,
            "maxItems": maxQueueSize
        ]

        let result = try await functions
            .httpsCallable("buildFiniteMediaQueue")
            .call(payload)

        guard let data = result.data as? [String: Any],
              let postIds = data["postIds"] as? [String] else {
            dlog("[FiniteMediaQueueService] Unexpected response shape from buildFiniteMediaQueue")
            currentQueue = []
            isQueueComplete = false
            currentIndex = 0
            return
        }

        currentQueue = Array(postIds.prefix(maxQueueSize))
        currentIndex = 0
        isQueueComplete = currentQueue.isEmpty
        dlog("[FiniteMediaQueueService] Queue built — \(currentQueue.count) items")
    }

    // MARK: - Playback Navigation

    /// Advances to the next item in the queue.
    /// - Returns: The postId of the next item, or `nil` if the queue is complete.
    @discardableResult
    func advance() -> String? {
        guard flags.finiteMediaQueuesEnabled else { return nil }
        guard !currentQueue.isEmpty else {
            isQueueComplete = true
            return nil
        }

        let nextIndex = currentIndex + 1
        guard nextIndex < currentQueue.count else {
            isQueueComplete = true
            dlog("[FiniteMediaQueueService] Queue complete at index \(currentIndex)")
            return nil
        }

        currentIndex = nextIndex
        let postId = currentQueue[nextIndex]
        dlog("[FiniteMediaQueueService] Advanced to index \(nextIndex) — postId: \(postId)")
        return postId
    }

    /// Returns the postId for the current queue position without advancing.
    var currentPostId: String? {
        guard flags.finiteMediaQueuesEnabled,
              !currentQueue.isEmpty,
              currentQueue.indices.contains(currentIndex) else { return nil }
        return currentQueue[currentIndex]
    }

    // MARK: - Reset

    /// Clears the queue and resets all state.
    func reset() {
        currentQueue = []
        currentIndex = 0
        isQueueComplete = false
        lastError = nil
        dlog("[FiniteMediaQueueService] Queue reset")
    }

    // MARK: - Completion Reporting

    /// Reports a completed item to the backend for analytics and healthy-use metrics.
    func markItemComplete(_ postId: String) async {
        guard flags.finiteMediaQueuesEnabled else { return }

        dlog("[FiniteMediaQueueService] Marking complete — postId: \(postId)")
        do {
            try await functions
                .httpsCallable("markQueueItemComplete")
                .call(["postId": postId])
        } catch {
            // Non-fatal: analytics loss is acceptable; do not surface to user.
            dlog("[FiniteMediaQueueService] markItemComplete error: \(error.localizedDescription)")
        }
    }

    // MARK: - Progress Helpers

    var remainingCount: Int {
        guard !currentQueue.isEmpty else { return 0 }
        return max(0, currentQueue.count - currentIndex - 1)
    }

    var progressFraction: Double {
        guard !currentQueue.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(currentQueue.count)
    }
}
