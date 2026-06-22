# AIL_BUILD_REPORT.md — Phase 2/3 Build Report

Branch `feature/ail` (isolated worktree `../ail-wt`) · 2026-06-09 · **deploy held for checkpoint.**

## Shipped (commit-per-item on feature/ail)
| Commit | Item |
|---|---|
| `739dfbb8` | Phase 2 shared Swift foundation (contracts mirror + AILTransformService + AILProfileService) |
| `9dcc3c02` | AGENT_LANES.md isolated-worktree pattern + lane registration |
| `87d14946` | **A2** `ailTransform` callable (routes 10 tasks through callModel) |
| `132b4f3c` | **A3** language (C1 translate+culture notes, C2 reading level, scripture explanation) |
| `e7e8a89c` | **A4** perception (C4 captions+SpeechProvider, C5 alt text, C6 audio summary) |
| `e3c1b929` | **A5** interaction (C7 voice nav, C8 intent picker, C9 touch targets, C13 calm mode) |
| `d69b8b0a` | **A6** protection (C10 reply-care, C11 cooldown, C12 safety filter, C14 re-entry) |
| `e80b5abd` | **A7** settings section + one-time setup flow |

22 Swift files under `AMENAPP/AMENAPP/Accessibility/AIL/` (3 foundation + 19 surface) + `functions/ail/{ail.contracts.ts, ailTransform.js}` + `amenRouting.config.js` delta.

## Contracts touched
- Added `functions/ail/ail.contracts.ts` (frozen) + Swift mirror `AILContracts.swift`.
- Appended 10 AIL task routes to `functions/router/amenRouting.config.js` (additive).
- Appended `ailTransform` export to `functions/index.js` (append-only).
- No existing collections/enums modified; `A11yProvenance` net-new (maps into ONEProvenanceClass family).

## Proof obtained (build-system-independent)
- ✅ `node --check` clean: `ailTransform.js`, `index.js`.
- ✅ All 10 AIL routes resolve in `amenRouting.config.js`; Claude-only tasks have no fallover; `explain_scripture` fail_closed; others fail-open.
- ✅ `xcrun swiftc -parse` clean on all 22 Swift files; **zero duplicate top-level type names** across lanes.
- ✅ Iron-rule greps: **0** tier gates in AIL paths; fail-open in 11 files; Reduce Transparency in 12 files; re-entry numeric scrubber present; DM/crisis never cached (`cacheable = !isDirectMessage && !crisisContext`); a11yProfile writes filtered to `allowedKeys` (forbidden fields cannot persist); require-targets verified.

## NOT done / held (honest)
- **Full Xcode build + live deploy**: the shared build system returned `Could not compute dependency graph` (infra failure, not code), and the integration branch is being rewritten by ~15 concurrent lanes. A real `BuildProject` and `firebase deploy --only functions:ailTransform --project amen-5e359` are **held for your checkpoint** and must run on a stable tree.
- **Surface mounting (A8)**: the 9 host views (PostDetailView, BereanChatView, MediaPlayerView, AmenNotificationCard, etc.) are actively owned by other active lanes. Editing them in this worktree (older base) would manufacture merge conflicts against those lanes. The mounts are therefore specified as a minimal additive pass in `AIL_WIRING.md`, to apply in one sweep at merge time on the quiet tree. Components themselves are fully wired to real logic (AILTransformService → callModel → providers) — no stubs, no dead handlers.
- **Media multimodal**: `describe_image` (image bytes) and `summarize_audio` (raw audio) route through callModel's text interface; A4 supplies the on-device transcript (SpeechProvider) / image ref. A true multimodal dispatch in callModel is a follow-up; until then those degrade → fail open (honest, non-fabricating).

## Open risks
1. Merge will be 3-way (feature/ail diverged from 115b48c9); new AIL files are conflict-free, but `amenRouting.config.js` / `functions/index.js` / `AGENT_LANES.md` could conflict if another lane appended to the same regions — both are append-only so resolution is mechanical.
2. SwiftUI type-level correctness is parse-verified only; a full compile is required (held) to catch any API mismatch against app-only helpers (A7 deliberately avoided `.systemScaled` for this reason).
3. New feature flags (`ailToneHintsEnabled`, etc.) are named in the contract but **not yet added** to `AMENFeatureFlags.swift` (a contested hotspot) — add append-only at merge, default OFF.

## Deploy checklist (HELD — run at checkpoint on stable tree)
1. `firebase deploy --only functions:ailTransform --project amen-5e359`
2. Firestore rules for `transformCache` (server-write only) + `users/{uid}/settings/a11yProfile` (owner r/w, forbidden-field schema validation) + captions subcollection (deny-by-default, inherits parent read) — single-claimant append to `firestore.rules`.
3. Append AIL feature-flag properties to `AMENFeatureFlags.swift` (default OFF).
4. Full `BuildProject` green; then apply `AIL_WIRING.md` mounts.
