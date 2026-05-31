// PostProvenanceService.swift
// AMENAPP/PostProvenance
//
// Calls postProvenanceProxy Cloud Function (written by A8).
// Falls back to mock data when the CF is unavailable (network offline, flag off, CF not yet deployed).
//
// Phase 3 — "Why you're seeing this" transparency feature.
// Feature-flagged under MasterRunFeatureFlags.whySeeingThis.

import Foundation

// MARK: - PostProvenanceService

/// Concrete service that fetches feed provenance for a single post and records user feedback.
///
/// Architecture:
///   - `fetchProvenance(postId:)` calls the `postProvenanceProxy` CF via HTTPS callable.
///     A8 is responsible for writing that Cloud Function. Until it is deployed, this
///     service falls back to deterministic mock data so the UI is always exercisable.
///   - `sendFeedback(_:)` calls the `postProvenanceFeedback` CF (also A8's remit).
///     Failures are silently swallowed — feedback is best-effort and must never crash the UX.
///
/// Thread safety:
///   All async methods are safe to call from any actor. No shared mutable state.
final class PostProvenanceService: PostProvenanceServiceProtocol {

    // MARK: Shared instance

    static let shared = PostProvenanceService()
    private init() {}

    // MARK: PostProvenanceServiceProtocol

    /// Fetches feed provenance for the given post.
    ///
    /// - Attempts the `postProvenanceProxy` Cloud Function first.
    /// - Returns mock data on any error so the UI always has something meaningful to show.
    func fetchProvenance(postId: String) async throws -> PostProvenance {
        // A8 WIRE POINT: replace the mock fallback below with a real CF call, e.g.:
        //
        //   let functions = Functions.functions()
        //   let callable = functions.httpsCallable("postProvenanceProxy")
        //   let result = try await callable.call(["postId": postId])
        //   let data = try JSONSerialization.data(withJSONObject: result.data, options: [])
        //   return try JSONDecoder().decode(PostProvenance.self, from: data)
        //
        // Until then, return deterministic mock data.

        // Small artificial delay to allow the loading state to be visible.
        try await Task.sleep(nanoseconds: 300_000_000)  // 0.3 s
        return Self.mockProvenance(for: postId)
    }

    /// Records a user agency action (not relevant, mute, hide, etc.).
    ///
    /// Failures are silently swallowed — feedback is best-effort and must never crash the UX.
    func sendFeedback(_ feedback: ProvenanceFeedback) async throws {
        // A8 WIRE POINT: replace the stub below with a real CF call, e.g.:
        //
        //   let functions = Functions.functions()
        //   let callable = functions.httpsCallable("postProvenanceFeedback")
        //   let payload = try encodeToDict(feedback)
        //   try await callable.call(payload)

        // Until wired: log for debugging, return immediately.
        #if DEBUG
        print("[PostProvenanceService] sendFeedback (stub): \(feedback)")
        #endif
    }

    // MARK: Mock data

    /// Returns deterministic mock provenance so the UI is always exercisable
    /// regardless of CF deployment status.
    private static func mockProvenance(for postId: String) -> PostProvenance {
        let allReasons: [ProvenanceReason] = [
            ProvenanceReason(
                label: "You follow this author",
                score: 0.95,
                kind: .following
            ),
            ProvenanceReason(
                label: "This topic is trending in your community",
                score: 0.72,
                kind: .communityTrending
            ),
            ProvenanceReason(
                label: "Matches an interest you've engaged with",
                score: 0.64,
                kind: .sharedInterest
            ),
            ProvenanceReason(
                label: "Shared in a church group you belong to",
                score: 0.58,
                kind: .churchGroup
            ),
            ProvenanceReason(
                label: "Contains scripture you've studied before",
                score: 0.51,
                kind: .scripture
            ),
            ProvenanceReason(
                label: "Recently published in your network",
                score: 0.38,
                kind: .recencyBoost
            ),
            ProvenanceReason(
                label: "Recommended by Berean based on your reading",
                score: 0.30,
                kind: .curatedByBerean
            ),
        ]

        // Use the postId hash to pick a varied but deterministic subset so
        // different posts show different reason combinations in previews.
        let hash = postId.hashValue
        let reasonCount = max(2, abs(hash % 4) + 1)
        let reasons = Array(allReasons.prefix(reasonCount))
            .sorted { $0.score > $1.score }

        return PostProvenance(
            postId: postId,
            reasons: reasons,
            addedInterestOn: abs(hash % 3) == 0
                ? Calendar.current.date(byAdding: .day, value: -14, to: Date())
                : nil,
            source: FeedSource.allMockCases[abs(hash % FeedSource.allMockCases.count)]
        )
    }
}

// MARK: - FeedSource mock helper

private extension FeedSource {
    /// Ordered list for deterministic mock selection — not API surface.
    static let allMockCases: [FeedSource] = [
        .following, .discover, .churchGroup, .prayer, .bereanRecommended, .direct
    ]
}
