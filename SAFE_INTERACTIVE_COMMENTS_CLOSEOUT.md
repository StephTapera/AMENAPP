# Safe Interactive Comments — Path C Closeout

**Branch:** `review/safe-interactive-comments-final`
**Path:** C — isolated worktree from a frozen base SHA (immune to shared-branch churn)
**Frozen base SHA:** `6cc44ca6b35f17e59394ea3e5921b28871da5d65`
**Worktree:** `/Users/stephtapera/Desktop/AMEN/AMENAPP-safe-comments-review`

## Why Path C
The shared branch `feature/liquid-glass-hero` was advancing ~2 commits/min and being
rewritten (history surgery) by ~14 concurrent agents, with a dedicated
"Build AMEN safe comments system across 20 features" agent live on the same surface.
Direct work was repeatedly `BLOCKED — NOT QUIET`. An isolated worktree from a frozen
SHA lets this lane finish deterministically without being invalidated mid-build.

## Registry / type decision (duplicate-safe)
- **Reused** existing `ModerationCategory` (SmartCommentsContracts.swift:132) — no new taxonomy.
- **No second top-level `Comment` type.** All new types are `AMEN`-namespaced.
- **No second moderation gateway.** `AMENModerationGate` is a thin fail-closed facade that
  wraps a server-backed resolver; it does not reimplement `ModerationGatewayService`.
- **No edit to `AMENFeatureFlags.swift`** (hot/contested). Dedicated fail-closed flag file used.

This directly avoids the previous duplicate-`Comment`-type build break (patch `0371`).

## What was implemented (new files)
- `AMENAPP/CommentsInteractive/AMENSafeInteractiveCommentsFlags.swift`
  - Master kill switch + 4 group gates. All default OFF, fail-closed. Missing/malformed
    config → OFF. No network when OFF. DEBUG-only dev opt-in for testing the ON path.
- `AMENAPP/CommentsInteractive/AMENCommentInteractiveContracts.swift`
  - `AMENModerationDecision` (fail-closed value; `.failClosed` blocks; `permitsPublish`)
  - `AMENModerationGate` (the ONE authoritative block; no resolver / OFF → `.failClosed`)
  - The 4 registration protocols: `AMENCommentComposeMode`, `AMENCommentMediaProvider`
    (preflight → default-deny), `AMENCommentInteraction` (safety actions `isAlwaysAvailable`),
    `AMENThreadDynamicsObserver`
  - `AMENCommentInteractiveRegistry` (`@MainActor`, single owner; inert while OFF)
  - `AMENSafeInteractiveComments.activateIfEnabled()` (no-op while OFF)
- `AMENAPPTests/AMENSafeInteractiveCommentsTests.swift` (8 tests)

## What was wired
- `AMENAPP/CommentsView.swift` `body`: `.onAppear { AMENSafeInteractiveComments.activateIfEnabled() }`
  - **OFF (default) = literal no-op = zero behavioral diff.** Existing comment behavior
    (reply, react, report, block, delete, edit, mentions, attachments) is untouched.

## Safety posture
- Moderation **fail-closed**: no resolver / lane OFF → `.block`. Only `.allow`/`.warn` publish.
- Media providers **preflight → default-deny** on any failure.
- Safety interactions (`report`/`block`) carry `isAlwaysAvailable` — cannot be overflow-hidden.
- Registry refuses registration while the corresponding group flag is OFF.

## Scope of THIS wave (honest)
This is the **Phase-0 backbone + safe gated wiring**, not the 20 feature UIs. The backbone is
what every feature group plugs into; it ships dark (OFF) and inert. The 20 feature surfaces,
their Berean/media/NCMEC integrations, and the human-gated decisions (voting, NCMEC/COPPA,
privacy zone) remain subsequent waves and are NOT claimed here.

## Verification
- Build: isolated `xcodebuild` (DerivedData `/private/tmp/amen-comments-dd`, SourcePackages
  `/private/tmp/amen-comments-sp`). See `deploy-logs/comments/build-*.log`.
- Tests: `AMENAPPTests/AMENSafeInteractiveCommentsTests` (fail-closed, OFF-inert, gate matrix).
- Backend/deploy: **none required** — no Functions/rules/Storage/Remote Config/index changes;
  the gate facade is client-side and fail-closed, server enforcement remains the existing
  deployed `enforceCommentModerationVisibility` / `callModelCommentCoach`.

## Not claimed
Full App Store / TestFlight readiness. Runtime simulator smoke of the *feature* UIs (there are
none in this wave; the lane ships OFF/inert).
