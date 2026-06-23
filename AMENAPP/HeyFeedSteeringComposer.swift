//
//  HeyFeedSteeringComposer.swift
//  AMENAPP
//
//  HeyFeed v2 — layers a user-owned, transparent, additive + CLAMPED steering delta on top of the
//  unchanged HeyFeedAlgorithm score. Pure value logic — no network, no Firestore.
//
//  The base score ALWAYS stays HeyFeedAlgorithm.weightedTotal (passed in as `baseScore`).
//  The composer only adds bounded deltas and records a truthful RankingSignal for each.
//  A forbidden floor target (SteeringBounds.isFloorTargetForbidden) contributes ZERO boost —
//  preferences can never launder unsafe content through steering.
//

import Foundation

enum SteeringComposer {

    /// Composes the final steered ranking result for a single post.
    ///
    /// - Parameters:
    ///   - postId:        stable post identifier.
    ///   - baseScore:     HeyFeedAlgorithm.weightedTotal — the unchanged scorer output.
    ///   - matchedEntries: the active PreferenceVocabulary entries that match this post
    ///                      (matching is done upstream against the post's topics/tone/etc.).
    ///   - liturgicalDelta: an additive, already-clamped seasonal context delta (default 0).
    static func compose(
        postId: String,
        baseScore: Double,
        matchedEntries: [PreferenceVocabularyEntry],
        liturgicalDelta: Double = 0
    ) -> SteeredRankingResult {

        var signals: [RankingSignal] = []
        var rawSteering: Double = 0

        for entry in matchedEntries {
            // Skip inactive / paused / expired entries — they contribute nothing.
            guard entry.active, !entry.paused else { continue }
            if let expiry = entry.expiresAt, Date() > expiry { continue }

            // Forbidden floor targets can never be boosted (fail-closed). A "lessOf"/"mute" on
            // such a target is still permitted (it only makes the feed stricter).
            let isForbidden = SteeringBounds.isFloorTargetForbidden(entry.target)
            let direction = entry.verb.signedMagnitude
            if isForbidden && direction > 0 { continue }

            let contribution = direction * entry.strength
            rawSteering += contribution

            signals.append(
                RankingSignal(
                    kind: .userSteering,
                    contribution: contribution,
                    origin: entry.source.rawValue,
                    rationaleText: Self.rationale(for: entry)
                )
            )
        }

        // Clamp the AGGREGATE steering delta to ±SteeringBounds.clamp (== 0.35).
        let steeringDelta = SteeringBounds.clampSteering(rawSteering)

        // Clamp the liturgical delta independently — it is additive seasonal context only.
        let boundedLiturgical = SteeringBounds.clampSteering(liturgicalDelta)
        if boundedLiturgical != 0 {
            signals.append(
                RankingSignal(
                    kind: .liturgicalSeason,
                    contribution: boundedLiturgical,
                    origin: "liturgical_season",
                    rationaleText: "Seasonal context (additive)"
                )
            )
        }

        // Final score = unchanged base + bounded additive deltas. The delta scales relative to the
        // base magnitude so a ±0.35 clamp behaves as a bounded proportional nudge, never a rewrite.
        let appliedDelta = (steeringDelta + boundedLiturgical) * abs(baseScore)
        let finalScore = baseScore + appliedDelta

        return SteeredRankingResult(
            postId: postId,
            baseScore: baseScore,
            steeringDelta: steeringDelta,
            liturgicalDelta: boundedLiturgical,
            signals: signals,
            finalScore: finalScore
        )
    }

    /// Truthful, user-facing reason for a steering entry (used by the transparency UI).
    private static func rationale(for entry: PreferenceVocabularyEntry) -> String {
        let label = entry.target.label
        switch entry.verb {
        case .moreOf:      return "You asked for more \(label)"
        case .lessOf:      return "You asked for less \(label)"
        case .prioritize:  return "You prioritized \(label)"
        case .mute:        return "You muted \(label)"
        case .explore:     return "You're exploring \(label)"
        case .reset:       return "Reset \(label)"
        }
    }
}

// MARK: - Verb signed magnitude

private extension SteeringVerb {
    /// Direction of the steering delta: positive boosts, negative demotes.
    /// `reset` is neutral (0); `mute` is a strong demotion.
    var signedMagnitude: Double {
        switch self {
        case .moreOf:      return 1.0
        case .prioritize:  return 1.0
        case .explore:     return 0.6
        case .lessOf:      return -1.0
        case .mute:        return -1.0
        case .reset:       return 0.0
        }
    }
}
