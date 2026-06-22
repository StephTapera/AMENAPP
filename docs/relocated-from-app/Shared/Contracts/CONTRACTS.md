# AMEN Context Intelligence OS Contracts

STATUS: FROZEN

## Changelog

- 2026-06-10: Initial Wave 0 freeze for the context signal spine, consent edges, and entitlement gate.

## ContextSignal

`ContextSignal` is the typed event spine for context-aware product behavior. It carries a `SignalType`, source `TierCeiling`, graph subject references, a small JSON-safe payload, an occurrence date, decay half-life, and an optional required `ConsentEdge`.

Tier-S signals are device-only. Server mirrors must reject any envelope with `tierCeiling === "s"`.

## ConsentEdge

`ConsentEdge` enumerates explicit user-controlled graph flows. `ConsentState.defaults()` enables only `activityToRhythm`; all other consent edges default off until the user turns them on.

## EntitlementGate

`Capability` is the canonical surface for monetization and feature access. `EntitlementGating.canAccess(_:)` returns a `GateDecision` with one of the sanctioned reasons: entitled, feature flag off, tier required, grace preview, or crisis suppressed.

During crisis dampening, upsell-rendering capabilities must resolve to `.crisisSuppressed` from the gate rather than from individual views.

## Mirrors

Swift contract files live in `Shared/Contracts/`. The Cloud Functions event envelope mirror lives in `Backend/functions/src/contracts/contextSignal.ts`.
