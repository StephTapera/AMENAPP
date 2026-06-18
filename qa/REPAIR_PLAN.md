# AMEN — QA Repair Plan (tracked, corrected)

**Date:** 2026-06-17 · **Owner:** human (Steph) · **Source tickets:** `qa/tickets/`, `qa/FLOW_CONTRACT.md`, `qa/RUN_LEDGER.md`

> This is the in-tree, corrected copy of the repair plan. It supersedes any inline draft.
> The most important correction is **POST-02** (see ⚠️ below): the original draft said "delete the
> else assignment," which would have introduced an empty-draft-save bug. The correct action is to
> **hoist** the shared assignment. A future agent reusing this plan must read this version.

---

## Guardrails (unchanged)
- No two writers on one file; another agent may be live in UI/launch files — hold overlapping tickets.
- `AMENAPPApp.swift` is off-limits to agents this wave (contested: emulator wiring §2 + NOTIF-02).
- `project.pbxproj` never edited by an agent. No safety/auth/human-gated path edited by an agent.
- Never weaken an `[EXPECTED-BLOCK]` control to make a test pass.
- Tier-1 = in-place corrections (no flags). Tier-2 routing changes (NOTIF-02/03) = flag-gated OFF.
- Build broker: agent declares "ready for build"; a human runs canonical `BuildProject` (AMENAPP scheme).
- Human runs all git. Path-scoped commits only; never `git add -A` in a multi-agent tree.

---

## TIER 1 — safe repair wave — STATUS: ✅ APPLIED + BUILD GREEN (0 errors), commit 88324f5e

| Ticket | File | Status |
|---|---|---|
| SIGNOUT-01 | `AuthenticationViewModel.swift` | FIXED — catch resets `isAuthenticated`/`needsOnboarding` (teardown already ran above) |
| POST-01 | `CreatePostView.swift` | FIXED — Discard now calls `clearRecoveredDraft()` before dismiss |
| POST-02 | `CreatePostView.swift` | FIXED — **hoisted** shared assignment (see ⚠️) |
| BEREAN-01 | `BereanLandingView.swift` | FIXED — continue card renders only when handler exists |
| CODE-LAZYDB | `SignInView.swift`, `NotificationDeepLinkRouter.swift` | FIXED — `lazy var db` → `let db` ×3 |
| A11Y-LABELS | 6 files / 10 controls | FIXED — labels / `.isSelected` traits / combined elements |

### ⚠️ POST-02 — CORRECTED FROM ORIGINAL PLAN
**Original (WRONG):** "remove the redundant `shouldPersistDraftOnExit = false` in the else branch;
it's redundant with the `@State` default."
**Why wrong:** the `@State` default is **`true`**, not false. The else branch sets it `false` to
prevent a draft save on a *no-content* close. Deleting it would leave the flag `true` → an
empty-draft save on close → a phantom draft-recovery prompt next launch.
**Correct fix (applied):** hoist the shared `shouldPersistDraftOnExit = false` above the `if`, so
both the has-content and no-content branches keep it `false`; only `saveDraft()` stays conditional.
Behavior preserved, duplication removed.

### Other applied deviations (both endorsed by human)
- **A11Y toggles:** added `.isSelected` traits (preserve visible text + convey state) instead of
  overriding text with a generic label.
- **AUTH-05 reclassified:** `rememberedAccountCard` is display-only, not a dead button —
  applied `.accessibilityElement(children: .combine)` only.

---

## TIER 2 — verify + repair during the runtime sweep (do NOT fix blind) — STATUS: PENDING

| Ticket | File | Fix direction (apply only after runtime confirms) |
|---|---|---|
| FEED-01 | `PostCard.swift` | `await publishQuotePost`; roll back `hasReposted`/`repostCount` + error toast |
| NOTIF-02 | `AMENAPPApp.swift` (hot file) | handlers return `Bool`; `if handled { return }` preserving order |
| NOTIF-03 | `CompositeNotificationDelegate.swift` | route church taps through `NotificationOpenCoordinator` |
| PROFILE-01 | `ProfileView.swift` | assign normalized `bioURL` back to state before `updateData` |
| PROFILE-02 | `ProfileView.swift` | `dismiss()` only on success; keep sheet + retry on error |

Routing changes (NOTIF-02/03) land behind an OFF-by-default flag.

---

## TIER 3 — human-only, never an agent (report-only) — STATUS: OPEN
- **DEL-01** `AccountDeletionService.swift` — auth/recovery/E2EE red line.
- **SET-02** `SettingsView.swift` re-auth sheet — auth-security red line.
- **5 env blockers** — emulator wiring (§2), NCMEC/Aegis emulator stub (§0, keep blocking ON),
  `storage:9199`, seed data, prod-default project. (Unblock kit in `qa/RUN_LEDGER.md`.)

---

## Outstanding after Tier 1
- **Runtime verification still owed:** VoiceOver (A11Y-LABELS), discard-draft (POST-01),
  sign-out-on-throw (SIGNOUT-01). Build-green ≠ runtime-verified.
- **Isolated build before merge:** the green build was on a mixed tree (this wave + other agents'
  uncommitted work). Confirm the branch builds in isolation before the PR merges.
