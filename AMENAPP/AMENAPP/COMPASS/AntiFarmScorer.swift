//  AntiFarmScorer.swift
//  AMEN — COMPASS · Anti-Farming · pure deterministic burst/sybil scorer.
//
//  This is NOT a public person score and NOT a model. It is a deterministic, side-effect-free
//  function over coarse, already-collected behavioral counters that produces an INTERNAL
//  `IntegrityEvaluation` consumed BEFORE ranking. Its only outputs are evidence categories
//  (`AntiFarmSignal`) and an internal `integrityPenalty` demotion magnitude.
//
//  INVARIANTS:
//    - Deterministic: identical input => identical output. No clocks, no randomness, no I/O.
//      (The caller supplies `evaluatedAtUTC` so the timestamp is an input, not a side effect.)
//    - Fail-closed: when the flag is OFF, the penalty is exactly 0 and no originality leaks.
//    - Never a person score: the result is attached to a subject (post/account) as a demotion
//      input, never displayed and never composed into a public number.
//
//  NEW FILE — auto-included via the AMENAPP PBXFileSystemSynchronizedRootGroup (no pbxproj edit).

import Foundation

// MARK: - Coarse input features

/// Coarse, already-collected behavioral counters for one subject. These are inputs only —
/// no GPS, no content, no identity. The scorer derives signals purely from these.
struct AntiFarmFeatures: Equatable, Sendable {
    /// Count of accounts in the subject's interaction cluster sharing low-cost device traits.
    let sybilClusterSize: Int
    /// Fraction (0...1) of follows that are reciprocal within a tight ring.
    let reciprocalFollowRatio: Double
    /// Count of near-simultaneous reshares within the burst window.
    let synchronizedBurstCount: Int
    /// Observed repost-chain depth (longer => lower originality).
    let repostLineageDepth: Int
    /// Coarse provenance basis (reuses ProvenanceStatus).
    let provenanceBasis: ProvenanceStatus

    init(
        sybilClusterSize: Int = 0,
        reciprocalFollowRatio: Double = 0,
        synchronizedBurstCount: Int = 0,
        repostLineageDepth: Int = 0,
        provenanceBasis: ProvenanceStatus = .unknown
    ) {
        self.sybilClusterSize = sybilClusterSize
        self.reciprocalFollowRatio = reciprocalFollowRatio
        self.synchronizedBurstCount = synchronizedBurstCount
        self.repostLineageDepth = repostLineageDepth
        self.provenanceBasis = provenanceBasis
    }
}

// MARK: - AntiFarmScorer

/// Pure deterministic burst/sybil scorer. Stateless — all methods are `static`.
enum AntiFarmScorer {

    /// Deterministic thresholds. Tunable constants, never user-visible.
    enum Thresholds {
        static let sybilClusterMin = 5            // >= this cluster size => sybilCluster signal
        static let reciprocalFollowMin = 0.6      // >= this ratio => followFarm signal
        static let synchronizedBurstMin = 8       // >= this many synced reshares => amplification

        /// Per-signal additive demotion weights; the total is clamped to [0, 1].
        static let sybilPenalty = 0.4
        static let followFarmPenalty = 0.3
        static let amplificationPenalty = 0.4
    }

    /// Evaluate a subject. When `flagEnabled` is false this is fully fail-closed:
    /// zero penalty, no signals, no originality leakage — identical to the unweighted form.
    static func evaluate(
        subjectId: String,
        subjectKind: IntegritySubjectKind,
        features: AntiFarmFeatures,
        flagEnabled: Bool,
        evaluatedAtUTC: Double
    ) -> IntegrityEvaluation {
        guard flagEnabled else {
            return .unweighted(
                subjectId: subjectId,
                subjectKind: subjectKind,
                evaluatedAtUTC: evaluatedAtUTC
            )
        }

        let signals = detectSignals(features)
        let penalty = integrityPenalty(for: signals)
        let originality = originalityScore(features)

        return IntegrityEvaluation(
            subjectId: subjectId,
            subjectKind: subjectKind,
            signals: signals,
            integrityPenalty: penalty,
            originality: originality,
            flagEnabled: true,
            evaluatedAtUTC: evaluatedAtUTC
        )
    }

    /// Deterministic signal detection from coarse counters. Order is fixed for stable output.
    static func detectSignals(_ features: AntiFarmFeatures) -> [AntiFarmSignal] {
        var signals: [AntiFarmSignal] = []
        if features.sybilClusterSize >= Thresholds.sybilClusterMin {
            signals.append(.sybilCluster)
        }
        if features.reciprocalFollowRatio >= Thresholds.reciprocalFollowMin {
            signals.append(.followFarm)
        }
        if features.synchronizedBurstCount >= Thresholds.synchronizedBurstMin {
            signals.append(.coordinatedAmplification)
        }
        return signals
    }

    /// Additive per-signal penalty, clamped to [0, 1]. INTERNAL — never displayed.
    static func integrityPenalty(for signals: [AntiFarmSignal]) -> Double {
        var total = 0.0
        for signal in signals {
            switch signal {
            case .sybilCluster:             total += Thresholds.sybilPenalty
            case .followFarm:               total += Thresholds.followFarmPenalty
            case .coordinatedAmplification: total += Thresholds.amplificationPenalty
            }
        }
        return Swift.max(0, Swift.min(1, total))
    }

    /// INTERNAL originality assessment. Deeper repost lineage lowers originality linearly.
    static func originalityScore(_ features: AntiFarmFeatures) -> OriginalityScore {
        let decay = Swift.min(1.0, Double(Swift.max(0, features.repostLineageDepth)) * 0.2)
        let value = Swift.max(0, Swift.min(1, 1.0 - decay))
        return OriginalityScore(
            value: value,
            provenanceBasis: features.provenanceBasis,
            repostLineageDepth: features.repostLineageDepth
        )
    }
}
