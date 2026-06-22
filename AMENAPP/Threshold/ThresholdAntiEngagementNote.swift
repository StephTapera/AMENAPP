// ThresholdAntiEngagementNote.swift
// AMEN — THRESHOLD Smart Profile / Identity Switcher
//
// W0 ANTI-ENGAGEMENT CONSTRAINT — 2026-06-16
// ============================================================
//
// PURPOSE
// This file exists to make the binding anti-engagement constraint a
// first-class, reviewable artifact in the codebase — not just a note
// in a doc. Every engineer and agent touching Threshold must be aware
// of it. It is NOT documentation-for-documentation's-sake; violating
// this constraint is a product defect equivalent in severity to a
// privacy breach.
//
// THE CONSTRAINT (verbatim from spec §0)
// -----------------------------------------------------------------------
//   Minimize median taps-to-first-intended-action.
//   NEVER optimize session length, DAU, or return rate.
// -----------------------------------------------------------------------
//
// WHAT THIS MEANS IN CODE
//
//   ALLOWED — Threshold may:
//     • Reorder profiles by likelihood of being the intended one NOW.
//     • Show a short, honest reason chip explaining the reorder.
//     • Restore the last-active surface, drafts, and scroll position.
//     • Pre-stage a surface/action the user probably came to take.
//     • Record on-device: taps-to-first-intended-action (the success metric).
//
//   FORBIDDEN — Threshold must never:
//     • Emit a notification, push, badge, or "come back" nudge.
//     • Optimize for session duration, daily active users, return rate,
//       or any engagement proxy. No streaks, no unread-count-as-bait.
//     • Auto-select a profile without explicit user opt-in (D6).
//     • Send any SwitchSignal, usage history, or score off-device (D2).
//     • Add a feature that cannot be traced to "reduce friction to the
//       user's own intent." If you cannot trace it, stop and ask.
//     • Log session length, DAU, or return-rate metrics anywhere in the
//       Threshold module. Use the on-device taps counter only (W6).
//
// REVIEW CHECKLIST (for every PR touching this module)
//   □ Does the change reduce taps-to-intended-action?
//   □ Does the change add any signal, metric, or behavior that increases
//     time-in-app, return rate, or re-engagement? (If yes: REJECT.)
//   □ Does any new signal leave the device? (If yes: REJECT. D2.)
//   □ Is prediction explainable with a ≤60-char reason string? (D3)
//   □ Is step-up auth fail-closed? (D4)
//   □ Are all flags still default OFF? (D6)
//
// D1 DECISION (confirmed 2026-06-16)
//   Primitive = contexts under one verified identity.
//   personal / ministry / creator / org.
//   Linked-separate-accounts deferred to v2.

import Foundation

/// Namespace for the anti-engagement metric. On-device only; never sent to server.
enum ThresholdMetric {
    /// The only metric Threshold is allowed to record.
    /// Incremented locally when the user reaches their first intended action after a switch.
    /// Stored on-device; never included in any analytics event that leaves the device.
    static let tapsToFirstIntendedAction = "threshold.local.tapsToFirstIntendedAction"

    // Sentinel: any other metric name appearing in the Threshold module should be treated
    // as a code-review defect and rejected before merge.
}
