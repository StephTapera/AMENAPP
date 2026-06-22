# AMEN — Interaction Audit & Repair Report (Deliverables A–G)

**Companion to** `audit/INTERACTION_MAP.md` (Phase A inventory) and `audit/CONVERGENCE.md` (commit ledger).
**Date:** 2026-06-22 · **Branch:** `feature/volunteer-board-wave0`
**Verification bar:** every code change recorded here is committed + 0 per-file diagnostics. **Full `xcodebuild` + on-device QA remain HUMAN-PENDING and are not asserted green.**

---

## E. Code Changes (committed this effort)

| Commit | Phase | Change |
|---|---|---|
| `6863da56` | A | `INTERACTION_MAP.md` — full §13 inventory (6 CRITICAL, 14 HIGH) |
| `cdcb326a` | C | **CRITICAL #1** crisis pill → `CrisisResourceOverlayView` (988), not the AI |
| `684cb976` | C | **CRITICAL #5** media Save persisted to Firestore (was ephemeral/lost) |
| `4e417fb1` | C | **CRITICAL #4** Find-a-Church geocodes typed city/zip (denied-location dead end) |
| `fc23fce7` | B | state machine + (later de-forked) Toast/Modal coordinators |
| `091e5ec6` | B | `ButtonActionRouter`, `PaywallCoordinator`, `PermissionCoordinator` |
| `57667051` | B | `AmenLoadingButton` + (later de-forked) `AmenToastHost` |
| `4a671c31` | B/C | de-fork toast onto existing `ToastManager`; surface comment block/mute failures |

**Shared foundation now available for Phase C (all compile-verified):**
`AmenInteractionStateMachine`, `ModalCoordinator`, `ButtonActionRouter`, `PaywallCoordinator`, `PermissionCoordinator` (in `DeepLinkRouter.swift`); `AmenLoadingButton` (in `AmenGlassButtonSystem.swift`); `ToastManager.failure(_:retry:)` (in `ToastManagerExtensions.swift`). Navigation = existing `DeepLinkRouter`. Toasts = existing `ToastManager`.

---

## A. Button Audit Report (summary)

Full per-element tables live in `INTERACTION_MAP.md` §1–6. Headline status by surface:

| Surface | Dead/stub | Idempotency risk | A11y gaps | Notable fixed |
|---|---|---|---|---|
| Feed/Comments | FeedUtilityDrawer, comment-Amen, GIFPicker | comment heart no debounce | Send button no label | block/mute failure now surfaced ✅ |
| Profile/Onboarding/Settings | CreatorProfile CTAs (gated, latent) | slide5 follow no lock | toolbar icon buttons | — |
| Connect/Spaces | section tiles, "See all", volunteer "Help", mod loaders | **join `increment(+1)`** | filter pills | — |
| Berean | reader action surface, leader/recent rows | reader AI re-tap | composer <44pt | **crisis pill ✅** |
| Selah/Resources | bundle Preview, ContentView rails, Add-a-Note | like/save no reconcile | scripture chips | **media Save ✅** |
| Find a Church | Suggest-times stub | visit-plan/calendar dup | save bookmark no label | **denied-location ✅** |

## B. Pop-up / Modal Audit Report (summary)

- **Modal stacking / recursion:** related-content uses recursive `.sheet(item:)` (Resources + Selah detail) → can stack indefinitely. **Fix path:** `ModalCoordinator.present(.sheet(id:))` rejects a second sheet; or push via `DeepLinkRouter`. (Coordinator landed; wiring is Phase C.)
- **Paywall conflicts:** ≥5 fragmented paywall surfaces. **Fix path:** route all through `PaywallCoordinator.present(requiredTier:feature:)`. (Coordinator landed; call-site migration is Phase C.)
- **Permission timing:** onboarding "Enable Notifications" fires the OS prompt with no rationale / silently advances when denied. **Fix path:** `PermissionCoordinator.requestWithRationale(...)`. (Coordinator landed; wiring is Phase C.)
- **False success modals:** calendar "Added" on EventKit denial; SignUp "You're in!" on purchase cancel. **Fix:** branch on actual outcome (recipes below).

## C. Duplicate / Gaps Report

**Duplicates removed / corrected:**
- **Toast fork (self-caught):** new `ToastCoordinator`/`AmenToastHost` duplicated the existing app-wide `ToastManager`. Removed; standardized on `ToastManager` (commit `4a671c31`).
- **NavigationCoordinator not forked:** `DeepLinkRouter` already serves the role; documented instead of duplicated.
- **Comment Delete** has two entry points (ellipsis dialog + contextMenu) — consolidation queued (recipe below).

**Gaps fixed:** crisis-resource routing (#1), persisted media Save (#5), denied-location manual search (#4), surfaced block/mute failures.
**Gaps remaining:** see "Remaining Phase C" + "Backend CRITICALs" below.

## D. Performance Report (interaction latency)

Audit-level observations (Instruments pass is HUMAN-PENDING):
- **Media play** (`AMENResourceDetailView`) spins a `WKWebView` with no spinner/poster → perceived hang. Recipe below.
- **Card-expand** paths in Find a Church use `Motion.adaptive`-guarded springs (good).
- **Double-submit** sources (join/RSVP/reply/visit-plan) now have a shared cure (`ButtonActionRouter` / `AmenLoadingButton`) — migration is Phase C.
- Reduce-Motion / Reduce-Transparency respected by the new components.

## F. Tests Added

**Status: HUMAN-PENDING wiring.** New test files in this Xcode-16 synced-folder project are not added to the test target without a human one-time scaffold (same gate as new app files; `RunCodeSnippet`/test runs are also blocked here by a pre-existing `TestingMacros` plugin failure). **Test plan ready to drop in** once the target is wired:
- `AmenInteractionStateMachineTests` — legal vs illegal transitions; reset; double-tap rejection.
- `ButtonActionRouterTests` — in-flight dedup; debounce window.
- `PaywallCoordinatorTests` — one-at-a-time; tier comparison.
- `ModalCoordinatorTests` — reject-stacking; `dismiss(kind:)` only clears matching active.
- Surface regression: crisis-pill presents overlay (not follow-up); media-Save persists+reloads; denied-location geocode path returns results.

## G. Final QA Checklist (status)

| Check | Status |
|---|---|
| No dead buttons | ◑ CRITICAL dead paths addressed; HIGH/LOW stubs enumerated w/ recipes |
| No duplicate pop-ups | ◑ coordinators landed; call-site migration pending |
| No duplicate submissions | ◑ shared cure landed (`ButtonActionRouter`/`AmenLoadingButton`); migration pending |
| No broken navigation | ✅ denied-location dead end fixed; others none-found |
| No missing loading/failure states | ◑ block/mute + media-save fixed; batch pending |
| No inaccessible buttons | ◑ recipes for ~40 label/44pt fixes |
| No unsafe sensitive actions | ✅ crisis routing fixed; mod-action confirms pending |
| Two-accent / Calm / Reduce-Motion+Transparency | ✅ honored by new foundation |
| Full `xcodebuild` + device QA | ⏳ **HUMAN-PENDING** |

---

## Remaining Phase C — fix recipes (drop-in, per finding)

Each is a self-contained edit to an **existing (indexed) file**, so each is per-file verifiable.

1. **Silent failures → `ToastManager.shared.failure(...)`** (pattern, ~12 sites): privacy pickers (`PrivacyControlsSettingsView.swift:41/120/165` — also revert optimistic value), photo upload/delete (`ProfilePhotoEditView.swift`), AskSelah stream (`AskSelahView.swift:312` — render `errorMessage`), Selah Church-Notes save (`SelahView.swift:1091`), media Berean Ask (`SelahMediaDetailView.swift:606`), Timestamped/Full comment submit (restore text + toast).
2. **Double-submit → `AmenLoadingButton` or `ButtonActionRouter.perform(id)`**: forum reply (`ConnectForumView.swift:360`), comment heart (`CommentsView.swift:2433`), SpaceCard Join (`SpaceCardView.swift:123`), visit-plan (`FindChurch2VisitPlannerView.swift:195` + deterministic doc id `{uid}_{churchId}_{serviceDate}`), `PlanVisitManager` (`ChurchProfileView.swift:1105` guard `step==.idle`).
3. **Calendar false-success** (`ChurchCommunityProfileView.swift:255`): on the `guard granted else` branch show `ToastManager.shared.failure(...)`, do NOT set `showCalendarConfirmation`; dedup events by stable identifier.
4. **SignUp false success** (`AMENConnectSignUpView.swift:338`): branch success copy on actual purchase outcome (cancel ≠ joined).
5. **Paywalls → `PaywallCoordinator`**: replace `AmenAccountPaywallView`/inline `PaywallOverlay`/`AmenSubscriptionPaywall`/`AmenFeatureGateView` call sites with `PaywallCoordinator.shared.present(requiredTier:feature:)` + one host sheet.
6. **Permission priming → `PermissionCoordinator`**: onboarding notifications (`OnboardingFlowView.swift:1107`), Find-a-Church location (also set `kCLLocationAccuracyReduced`).
7. **Recursive sheets → `ModalCoordinator`** or NavigationPath push: `AMENResourceDetailView.swift:583`, `SelahMediaDetailView.swift:70`.
8. **RSVP 3-state** (`SpaceDashboardView.swift:242`): Going/Maybe/Not + error surface + ≥44pt.
9. **A11y batch (~40):** add `.accessibilityLabel` to icon-only controls (comment Send `CommentsView.swift:1198`, profile toolbar `UserProfileView.swift:2042–2070`, Discovery FAB/clear, neighborhood `?`); raise sub-44pt targets to `minHeight: 44`.
10. **Dead controls:** gate-off or wire FeedUtilityDrawer, Connect section tiles/"See all"/presence, Berean reader action surface + leader/recent rows, Resources ContentView rails + bundle Preview, volunteer "Help", Suggest-times.
11. **Destructive confirms + audit log:** moderator Block/Remove/Deny (`AmenSpaceModerationDashboardView.swift`) via `.destructiveConfirm` + server audit.

---

## Backend CRITICALs — TS-first specs (deploy is a HUMAN step per CLAUDE.md)

### #2 — Spaces join idempotency (`SpacesViewModel.swift:77`)
Client optimistic insert + unconditional `increment(+1)` with `try?` → member-count drift.
**TS-first CF (callable, region `us-east1`):** `joinSpace({ spaceId })`
- Firestore **transaction**: read `spaces/{spaceId}/members/{uid}`; if absent → create member doc AND `memberCount = increment(+1)`; if present → no-op. Leave mirrors with `arrayRemove`/`increment(-1)` guarded the same way. → membership-idempotent regardless of taps/retries.
- Enforce entitlement + rate limit server-side; return `{ joined: Bool, memberCount: Int }`.
**Swift mirror:** `SpacesViewModel.toggleJoin` calls the callable, disables via `ButtonActionRouter`, applies returned `memberCount`, `ToastManager.failure` on error (no silent `try?`).

### #3 — Moderation dashboard stubs (`AmenSpaceModerationDashboardView.swift:631`)
`loadReports/loadJoinRequests/loadMembers` sleep then assign `[]`.
**Fix:** wire to Firestore subcollections (`spaces/{id}/reports`, `/joinRequests`, `/members`) with server-side moderator-role rules; show loading/empty/error states (no fabricated empties). If the backing collections don't exist yet, that's a backend schema task (TS-first) before the iOS wiring.

---

## Notes
- Foundation lives in existing indexed files (`DeepLinkRouter.swift`, `AmenGlassButtonSystem.swift`, `ToastManagerExtensions.swift`) because new synced-folder files can't be per-file compile-verified in this environment.
- Anything net-new behavioral should ship behind a flag defaulting OFF; the coordinators are inert infrastructure until consumed.
