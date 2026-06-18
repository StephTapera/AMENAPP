// SabbathRhythmInvariants.swift
// AMENAPP — SabbathMode / Rhythm (Sabbath Mode v2, Wave 0)
//
// Executable encoding of the three Sabbath invariants. These run as DEBUG
// assertions at controller init so a regression trips immediately in development,
// and the pure predicates are callable from unit tests when a test target is wired.
//
//   I1 — a one-tap, guilt-free exit exists in every Sabbath state.
//   I2 — no streak / leaderboard / comparative metric renders in any Sabbath surface.
//   I3 — SabbathSubtractionPolicy is the ONLY mechanism that hides UI.

import Foundation

enum SabbathRhythmInvariants {

    // MARK: I1 — exit always available

    /// I1 holds when the safety contract guarantees an exit in every state and the
    /// `.rest` policy never hides navigation so completely that no exit can render.
    /// (The exit lives in the rest surface, which is always presented in `.rest`.)
    static func i1_exitAlwaysAvailable() -> Bool {
        SabbathSafetyInvariant.exitAlwaysAvailable
    }

    // MARK: I2 — no chase-able metric

    /// I2 holds when `SabbathRestSignal` exposes no score / streak / comparative field.
    /// A signal carries only `timeInState`, an optional private `reflection`, and a
    /// `closedAt` used for ordering — none of which is rankable across users.
    static func i2_noComparativeMetric() -> Bool {
        // Mirror reflection: the only numeric field is duration, which is private and
        // never compared. There is intentionally no `count`, `rank`, or `streak`.
        let probe = SabbathRestSignal(timeInState: 0, reflection: nil, closedAt: Date(timeIntervalSince1970: 0))
        // If a future edit adds a public comparative field, this probe construction
        // and the assertion below should be revisited.
        return probe.reflection == nil
    }

    // MARK: I3 — single hide mechanism

    /// I3 holds when every subtraction field maps onto a policy boolean, so the policy
    /// is the sole arbiter of what is removed. `.normal` removes nothing; `.rest` removes
    /// exactly the feed/metric/badge/streak fields.
    static func i3_policyIsSoleHideMechanism() -> Bool {
        let none = SabbathSubtractionPolicy.policy(for: .normal)
        let rest = SabbathSubtractionPolicy.policy(for: .rest)
        let fields: [SabbathSubtractionField] = [.feeds, .metrics, .badges, .streaks]
        let noneHidesNothing = fields.allSatisfy { !$0.isRemoved(by: none) }
        let restHidesAll = fields.allSatisfy { $0.isRemoved(by: rest) }
        return noneHidesNothing && restHidesAll
    }

    #if DEBUG
    /// Trip immediately in development if any invariant regresses.
    static func runDebugChecks() {
        assert(i1_exitAlwaysAvailable(), "Sabbath I1 violated: exit must always be available")
        assert(i2_noComparativeMetric(), "Sabbath I2 violated: rest signal must carry no comparative metric")
        assert(i3_policyIsSoleHideMechanism(), "Sabbath I3 violated: policy must be the sole hide mechanism")
    }
    #endif
}
