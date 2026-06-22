# AMEN — Autonomous QA Sweep · FINAL REPORT

**Date:** 2026-06-17 · **Orchestrator:** Claude (Opus 4.8)
**Branch:** none created (sweep never reached a write-to-source wave — see below)

## Summary

The live in-Simulator sweep (Waves 1–3 driving the app) is **NO-GO** and was not run: the app
has no emulator wiring, the default Firebase project is **production** (`amen-5e359`), and the
CSAM/NCMEC + Aegis outbound is not stubbed for the emulator. Each is an independent hard STOP
(see `qa/RUN_LEDGER.md`). Launching would risk prod writes and/or **real child-safety reports
from test traffic** — the most serious red line.

In place of the blocked runtime sweep, a **read-only static defect pass** (5 parallel explorers
across the roster flow groups) produced a file-specific ticket set. **No source was edited** —
fixes can't be runtime-verified without the app, and another agent is concurrently editing the
same UI files, so editing now would violate the "no two writers on overlapping files" rule.

### Counts
| Category | Count |
|---|---|
| Flows mapped & frozen (`FLOW_CONTRACT.md`) | 15 |
| Static tickets filed | 15 defects across 13 files (1 grouped a11y ticket = 10 sites) |
| → broken-flow / logic | 8 |
| → visual / code-quality | 7 |
| Fixed (agent, Tier 1) | 6 tickets / 13 edits / 9 files — **build GREEN 2026-06-17 (0 errors)**; runtime verify still pending (see UPDATE below) |
| Deferred to runtime sweep (Tier 2) | 5 (FEED-01, NOTIF-02, NOTIF-03, PROFILE-01, PROFILE-02) |
| Could-not-fix (agent) | 0 |
| Human-gated (report-only) | 2 + 5 Wave-0 env blockers |
| Runtime crashes observed | n/a — app not launched |

## Flows exercised
None at runtime (NO-GO). All 15 flows were **statically** mapped in `qa/FLOW_CONTRACT.md`
(cold start, sign up, email verify, sign in, sign out, onboarding, permissions, navigation,
composer, feed actions, profile edit, settings, Berean entry, notifications/Live Activity, deep links).

**Controls correctly blocked by safety/auth (EXPECTED, not bugs):** COPPA age gate, 2FA gate,
email-verification gate, OTP attempt cap, post moderation/hold, report→safety queue,
delete-account re-auth. These are tagged `[EXPECTED-BLOCK]` in the contract and must never be
weakened to make a test pass.

## Failed → FIXED
Six Tier-1 tickets fixed and **build-verified GREEN (AMENAPP scheme, 0 errors, 2026-06-17)**:
SIGNOUT-01, POST-01, POST-02, BEREAN-01, CODE-LAZYDB, A11Y-LABELS. Compile-level verified; runtime
(VoiceOver, discard-draft, sign-out-throw) verification still pending the unblocked Simulator sweep.
See the change manifest in the UPDATE section below.

## Static defects filed (OPEN — not runtime-verified)
| Ticket | Sev | File | One-line |
|---|---|---|---|
| SIGNOUT-01 | broken-flow | AuthenticationViewModel.swift:~1015 | signOut error path leaves `isAuthenticated` true |
| POST-01 | broken-flow | CreatePostView.swift:~797 | "Discard Post" doesn't clear auto-saved draft |
| FEED-01 | broken-flow | PostCard.swift:~3365 | quote/repost optimistic update never rolls back |
| BEREAN-01 | broken-flow | BereanLandingView.swift:~107 | continue button = empty closure when nil (dead) |
| NOTIF-02 | broken-flow | AMENAPPApp.swift:~431 | onOpenURL lacks early-return; multi-route risk |
| NOTIF-03 | broken-flow | CompositeNotificationDelegate.swift:~73 | church notif taps bypass unified router |
| PROFILE-01 | logic | ProfileView.swift:~4039 | reformatted bio URL may not be the saved value |
| CODE-LAZYDB | quality | SignInView / NotificationDeepLinkRouter | `lazy var db` inside async fns |
| POST-02 | quality | CreatePostView.swift:~2320 | redundant `shouldPersistDraftOnExit=false` |
| PROFILE-02 | UX | ProfileView.swift:~4115 | error path dismisses instead of retry |
| A11Y-LABELS | visual | 10 sites (see ticket) | missing `.accessibilityLabel` on controls |

Full detail in `qa/tickets/`. Explorers re-examined and **dismissed** several candidates as
intentional/correct (image-count timing, dismissal cancellation, tab-index mapping, verse
suggestion suppression, URL query-item guards, Live Activity cleanup) — not filed.

## Failed → COULD NOT FIX (agent)
None — no fix attempted (no green-build verification path while NO-GO; concurrent edits).

## Human-gated (not attempted, by design) — see `qa/tickets/HUMAN-GATED.md`
- **DEL-01** account-deletion currentUser handling — red line: auth security / account-recovery.
- **SET-02** delete-account re-auth presentation — red line: auth security.
- **5 Wave-0 environment blockers** (emulator wiring, NCMEC/Aegis stub, storage emulator port,
  seed data, prod default project) — red line: never run against prod; never weaken child-safety.

## Regressions / residual risk
- No code changed → no regressions introduced.
- **Residual risk:** every ticket is static and **unverified at runtime**. Severities are best-effort
  from code reading; a real Simulator pass (once unblocked) is required to confirm repro and to run
  Wave 2 repair with verification. The medium-confidence routing tickets (NOTIF-02/03, BEREAN-01)
  especially need runtime confirmation before fixing.

## To unblock the full sweep (then re-run this prompt)
1. Add `#if DEBUG` + `-useFirebaseEmulator` wiring after `FirebaseApp.configure()` (companion §2).
2. Guard NCMEC/Aegis real-send behind `FUNCTIONS_EMULATOR` — keep blocking ON (companion §0).
3. Add `storage:9199` to the `firebase.json` emulators block.
4. Create `./emulator-seed` (test users + posts).
5. Start emulators; confirm UI at http://127.0.0.1:4000.

Then the existing `AMENAPPUITests/` target drives Waves 1–3: runtime exploration → verify each
static ticket → Wave-2 repair (smallest safe change, new paths flag-OFF) → re-verify → report.

## Deliverables produced this session (all in `qa/`)
- `RUN_LEDGER.md` — Wave-0 detection + NO-GO verdict
- `FLOW_CONTRACT.md` — frozen 15-flow contract
- `tickets/` — 11 ticket files (15 defects)
- `REPORT.md` — this file

Nothing was committed, merged, deployed, or deleted. No app launched. No Firebase project contacted.

---

## UPDATE 2026-06-17 — Tier 1 safe-repair wave APPLIED

Six in-scope, no-runtime-dependency tickets were applied per the human-approved repair plan.
Guardrails honored: `AMENAPPApp.swift` untouched; no safety/auth/human-gated path touched;
in-place only (no flags, no new files, no schema); **no git, no build self-certification** — the
human build broker runs the canonical `BuildProject` on the `AMENAPP` scheme. Collision check:
none of the nine files were dirty in the main tree at edit time.

### Change manifest (13 edits / 9 files)
| Ticket | File | Change |
|---|---|---|
| SIGNOUT-01 | `AMENAPP/AuthenticationViewModel.swift` | catch branch now resets `isAuthenticated`/`needsOnboarding` so local sign-out is deterministic on throw (teardown already ran unconditionally above) |
| POST-01 | `AMENAPP/CreatePostView.swift` | "Discard Post" now calls `clearRecoveredDraft()` before dismiss |
| POST-02 | `AMENAPP/CreatePostView.swift` | hoisted shared `shouldPersistDraftOnExit = false` (kept explicit — default is `true`; the plan's "delete else" would have been a bug) |
| BEREAN-01 | `AMENAPP/BereanLandingView.swift` | continue card only renders when `onContinuePrevious != nil` (no empty-closure dead control) |
| CODE-LAZYDB | `AMENAPP/SignInView.swift` (×2), `AMENAPP/NotificationDeepLinkRouter.swift` (×1) | `lazy var db` → `let db` |
| A11Y-LABELS | `OnboardingFlowView.swift` (×6), `SettingsView.swift`, `FollowThroughInteractions.swift`, `AMENAuthLandingView.swift`, `BereanLandingView.swift` (×2) | added labels / `.isSelected` traits / combined elements on 10 controls |

### Notes / honest caveats
- **POST-02 corrected vs ticket:** the literal "delete the else assignment" would have left the
  persistence flag `true` (its `@State` default) on a no-content close → an empty-draft save. The
  applied fix hoists the assignment instead, preserving behavior. Tickets `POST-02` updated.
- **AUTH-05 reclassified:** `rememberedAccountCard` is **display-only** (a "Welcome back" header
  above the real sign-in buttons), not an interactive dead control. Applied only an
  `.accessibilityElement(children: .combine)` polish, not a button label.
- **A11Y approach:** for checkbox/option toggles, added `.isSelected` traits rather than overriding
  the visible text with a generic label (preserves the meaningful text, conveys state) — a more
  correct fix than the ticket's suggested static labels.

### Fast-diagnostics sanity (per-file, not a full build)
| File | Result |
|---|---|
| AuthenticationViewModel, CreatePostView, OnboardingFlowView, SignInView, SettingsView, FollowThroughInteractions, AMENAuthLandingView | ✅ no issues (2 pre-existing `weak self` warnings in AuthenticationViewModel at L2099/2109 — unrelated) |
| BereanLandingView, NotificationDeepLinkRouter | ⚠️ tool "could not resolve file path" — not indexed at that path (BereanLandingView is a known unwired view); edits are trivially valid Swift; defer to full build |

**Gate state: BUILD GREEN.** `BuildProject` (AMENAPP scheme) SUCCEEDED 2026-06-17 — 37.36s, 0 errors,
2 warnings total (neither in the 9 edited files). First attempt failed on transient SwiftPM
dependency-graph contention from concurrent agents; retry was clean. Tier-1 tickets → FIXED.
Tier-2 (FEED-01, NOTIF-02, NOTIF-03, PROFILE-01, PROFILE-02) and the human-gated set remain for the
post-unblock runtime sweep.

**Working-tree caveat for commit:** the tree contains many changes from other concurrent agents
(Selah Sensory Layer, QA-framework, UI change) and pre-existing session staging — NOT from this
wave. Scope any commit to the 9 source files + the `qa/` docs listed in the manifest. Do not
`git add -A`.
