# BEREAN-01 — Berean "Continue previous study" button can be a silent no-op

- **Flow:** Berean entry (smoke)
- **File:** `BereanLandingView.swift:~107`
- **Severity:** broken-flow
- **Scope:** IN-SCOPE
- **Status:** FIXED (Tier-1) — card renders only when handler exists; build GREEN 2026-06-17; runtime verify still pending

**Expected:** The continue button only appears when actionable, or it is disabled when there is nothing to continue.
**Actual:** `BereanContinueCard(onTap: onContinuePrevious ?? {})` passes an empty closure when the callback is nil, so the card renders as a tappable control that does nothing.

**Static repro:** `?? {}` fallback makes the button visually active but inert when `onContinuePrevious == nil`.

**Suspected fix:** Hide or `.disabled(true)` the card when `onContinuePrevious == nil` instead of substituting an empty closure.
