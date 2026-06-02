// ReplyPreviewResolver.swift
// AMEN App — Dynamic Reply Preview Selection Ladder
//
// CONTRACT: CONTRACT.md v1.0.1 — Section 13 (Resolver Ladder), Section 15 (Scoring Formula)
//
// Pure Swift struct — no UIKit, no Firebase, no side effects.
// The backend (rebuildReplyPreviews Cloud Function) runs the same ladder in
// Node.js; this Swift implementation is the canonical client-side reference
// used for testing and for any client-side tiebreak logic.
//
// Inputs
//   postId        — Firestore document ID of the parent post
//   candidates    — raw [ReplyCandidate] scored upstream by the Cloud Function
//   viewerUID     — UID of the current viewer (may be empty for signed-out)
//   viewerFollows — Set<String> of UIDs the viewer follows (from FollowService)
//   replyCount    — current total reply count for the post
//   bereanInsight — optional pre-fetched Berean insight to consider at step 2
//   pulseCandidate — optional pre-aggregated community-pulse candidate for step 3
//
// Output
//   ResolvedReplyPreview? — the selected preview, or nil when nothing qualifies

import Foundation
import CryptoKit

// MARK: - BereanInsightInput

/// Lightweight input describing a pre-fetched Berean insight.
/// The Cloud Function passes these fields; the resolver never calls the AI.
struct BereanInsightInput {
    let postId: String
    let displayText: String
    let confidence: Double        // 0.0–1.0; must be >= 0.72 to qualify (Section 13)
    let safetyPassed: Bool
}

// MARK: - CommunityPulseInput

/// Pre-aggregated community-pulse summary produced by the Cloud Function.
struct CommunityPulseInput {
    let postId: String
    let displayText: String
    let participantUserIds: [String]
    let safetyPassed: Bool
}

// MARK: - ReplyPreviewResolver

struct ReplyPreviewResolver {

    // MARK: - Constants (Section 13)

    /// Minimum replyCount to attempt a bereanInsight (step 2).
    static let bereanInsightVolumeThreshold = 12

    /// Minimum berean confidence to accept a bereanInsight.
    static let bereanConfidenceThreshold: Double = 0.72

    /// Minimum replyCount to attempt a communityPulse (step 3).
    static let communityPulseVolumeThreshold = 5

    // MARK: - Entry Point

    /// Run the selection ladder defined in CONTRACT.md §13.
    ///
    /// - Parameters:
    ///   - postId: Firestore ID of the post.
    ///   - candidates: All scored, safety-checked reply candidates for this post.
    ///   - viewerUID: UID of the signed-in viewer. Pass "" for guest sessions.
    ///   - viewerFollows: Set of UIDs the viewer follows (from FollowService).
    ///   - replyCount: Current total reply count for the post.
    ///   - bereanInsight: Optional Berean insight to evaluate at step 2.
    ///   - pulseCandidate: Optional community-pulse aggregate to evaluate at step 3.
    /// - Returns: A `ResolvedReplyPreview` if any ladder branch qualifies, else `nil`.
    func resolve(
        postId: String,
        candidates: [ReplyCandidate],
        viewerUID: String,
        viewerFollows: Set<String>,
        replyCount: Int,
        bereanInsight: BereanInsightInput? = nil,
        pulseCandidate: CommunityPulseInput? = nil
    ) -> ResolvedReplyPreview? {

        // ── Step 1: followedReply ─────────────────────────────────────────────
        // Always tried first when there is an auth context and the viewer follows
        // at least one candidate author.
        if !viewerUID.isEmpty {
            let followed = candidates.filter { viewerFollows.contains($0.authorUID) && $0.safetyPassed }
            if let best = Self.highestScored(followed) {
                return makePreview(
                    postId: postId,
                    type: .followedReply,
                    displayName: best.authorDisplayName,
                    text: best.text,
                    authorUID: best.authorUID,
                    avatarURL: nil
                )
            }
        }

        // ── Step 2: bereanInsight ─────────────────────────────────────────────
        // Requires: replyCount >= 12 AND confidence >= 0.72 AND safetyPassed.
        if replyCount >= Self.bereanInsightVolumeThreshold,
           let insight = bereanInsight,
           insight.confidence >= Self.bereanConfidenceThreshold,
           insight.safetyPassed {
            return makePreview(
                postId: postId,
                type: .bereanInsight,
                displayName: "Berean Insight",
                text: insight.displayText,
                authorUID: "",
                avatarURL: nil
            )
        }

        // ── Step 3: communityPulse ────────────────────────────────────────────
        // Requires: replyCount >= 5 AND pulse.safetyPassed.
        if replyCount >= Self.communityPulseVolumeThreshold,
           let pulse = pulseCandidate,
           pulse.safetyPassed {
            let displayName = pulse.participantUserIds.count == 1
                ? "1 person"
                : "\(pulse.participantUserIds.count) people"
            return makePreview(
                postId: postId,
                type: .communityPulse,
                displayName: displayName,
                text: pulse.displayText,
                authorUID: "",
                avatarURL: nil
            )
        }

        // ── Step 4: topReply ──────────────────────────────────────────────────
        // Always-available fallback: highest composite score among safe candidates.
        let safe = candidates.filter { $0.safetyPassed }
        if let top = Self.highestScored(safe) {
            return makePreview(
                postId: postId,
                type: .topReply,
                displayName: top.authorDisplayName,
                text: top.text,
                authorUID: top.authorUID,
                avatarURL: nil
            )
        }

        // ── Step 5: no preview ────────────────────────────────────────────────
        return nil
    }

    func resolve(
        candidates: [DynamicReplyPreview],
        viewerFollowing: Set<String>
    ) -> DynamicReplyPreview? {
        let eligible = candidates.filter { candidate in
            candidate.isSafe && !candidate.isExpired
        }

        let priorities: [ReplyPreviewType] = [
            .followedReply,
            .bereanInsight,
            .communityPulse,
            .topReply
        ]

        for priority in priorities {
            let matching = eligible.filter { candidate in
                guard candidate.type == priority else { return false }
                if priority == .followedReply {
                    return !viewerFollowing.isDisjoint(with: Set(candidate.participantUserIds))
                }
                return true
            }
            if let best = matching.max(by: { $0.score < $1.score }) {
                return best
            }
        }

        return nil
    }

    // MARK: - Scoring Formula (Section 15)

    /// Composite score for a single candidate.
    ///
    /// ```
    /// compositeScore = 0.35 × relevanceScore
    ///               + 0.25 × spiritualUsefulness
    ///               + 0.25 × engagementScore
    ///               + 0.15 × recencyScore
    /// recencyScore = 1.0 - min(1.0, hoursSinceCreated / 168.0)
    /// ```
    static func compositeScore(for candidate: ReplyCandidate, now: Date = Date()) -> Double {
        let hoursOld = now.timeIntervalSince(candidate.createdAt) / 3600.0
        let recencyScore = 1.0 - min(1.0, hoursOld / 168.0)
        return 0.35 * candidate.relevanceScore
             + 0.25 * candidate.spiritualUsefulness
             + 0.25 * candidate.engagementScore
             + 0.15 * recencyScore
    }

    // MARK: - Helpers

    /// Returns the candidate with the highest composite score, or nil if empty.
    static func highestScored(_ candidates: [ReplyCandidate], now: Date = Date()) -> ReplyCandidate? {
        candidates.max { compositeScore(for: $0, now: now) < compositeScore(for: $1, now: now) }
    }

    /// Constructs a `ResolvedReplyPreview` using SHA-256 for contentHash.
    ///
    /// contentHash = sha256(postId + type.rawValue + text), hex-encoded.
    /// Used as the SwiftUI `.id()` stable identity for list diffing.
    private func makePreview(
        postId: String,
        type: ReplyPreviewType,
        displayName: String,
        text: String,
        authorUID: String,
        avatarURL: String?
    ) -> ResolvedReplyPreview {
        let raw = postId + type.rawValue + text
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return ResolvedReplyPreview(
            postId: postId,
            type: type,
            displayName: displayName,
            text: text,
            authorUID: authorUID,
            avatarURL: avatarURL,
            contentHash: hash
        )
    }
}

typealias BackendReplyPreviewResolver = ReplyPreviewResolver
