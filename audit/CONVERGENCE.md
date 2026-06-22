# AMEN Interaction Audit — Convergence Ledger

"Done" = committed + hash recorded here + the touched module compiles (per-file diagnostics clean).
Full-app `xcodebuild` + on-device QA remain **HUMAN-PENDING** and are never asserted green by the agent.

## Phase A — Inventory
| Item | Commit | Status |
|---|---|---|
| `audit/INTERACTION_MAP.md` — §13 surfaces interaction map (6 CRITICAL, 14 HIGH) | `6863da56` | ✅ committed |

## Phase C — Targeted CRITICAL fixes (ahead of full foundation)
| Item | File | Commit | Per-file diags | Status |
|---|---|---|---|---|
| CRITICAL #1 — Berean crisis pill no longer loops back into the AI; "Find immediate help" now presents the always-on `CrisisResourceOverlayView` (988-first) via `.fullScreenCover` + `interactiveDismissDisabled`, mirroring `BereanChatView` escalation. Safety + Companion-Boundary fix. | `AMENAPP/BereanSmartPillSystem.swift` | `cdcb326a` | 0 | ✅ landed |
| CRITICAL #5 — Media Save was ephemeral `@State` (silently lost). Now persists to `users/{uid}/savedResources/{entry.id}` (same store/scheme as `AMENResourcesHubView`): loads initial state on appear, optimistic write, double-tap guard, rollback + error alert on failure, adds VoiceOver label. | `AMENAPP/AMENResourceDetailView.swift` | `684cb976` | 0 | ✅ landed |
| CRITICAL #4 — Denied-location dead end. Added `performTextGeocodedSearch()` (forward-geocodes the typed city/zip via `CLGeocoder`, then searches around it via `ChurchSearchService`). Wired into search-bar submit (`performSearchWithText`) and the inline error-card retry. Manual search now returns churches without GPS. Follow-ups (not CRITICAL): `performMKLocalSearch` still GPS-guarded; `kCLLocationAccuracyBest`→reduced — both deferred to surface repair. | `AMENAPP/FindChurchView.swift` | _this commit_ | 0 | ✅ landed |

## Phase B — Shared foundation
Per repo memory ("prefer appending types to existing in-target files"), foundation
types are housed in the already-indexed `DeepLinkRouter.swift` (the existing
coordinator) rather than a new synced-folder file — new files cannot be per-file
compile-verified in this environment (not yet indexed; `RunCodeSnippet` is blocked
by a pre-existing `TestingMacros` plugin failure unrelated to this work).

| Item | File | Commit | Per-file diags | Status |
|---|---|---|---|---|
| `AmenInteractionStateMachine` (§4 lifecycle w/ valid-transition enforcement + reset) + `ToastCoordinator` (single app-wide queue → kills the "silent failure" pattern) + `ModalCoordinator` (one-active-at-a-time → kills modal-stacking/recursive-sheet). Pure infra, inert until Phase C consumes it. | `AMENAPP/DeepLinkRouter.swift` | _this commit_ | 0 | ✅ landed |
| `ButtonActionRouter` (debounced/in-flight dispatch → kills double-submit), `PaywallCoordinator` (+`AmenTier`/`AmenPaywallRequest` → consolidates ×5 paywalls), `PermissionCoordinator` (+priming sheet → explain-before-prompt). `NavigationCoordinator` = existing `DeepLinkRouter` (not forked, documented in-file). | `AMENAPP/DeepLinkRouter.swift` | _this commit_ | 0 | ✅ landed |
| `AmenToastHost` (renders the ToastCoordinator queue; calm, two-accent, reduce-transparency aware, VoiceOver announce) + `.amenToastHost()` + `AmenLoadingButton` (state-machine-driven loading/disabled, double-tap-safe, ≥44pt, labeled). | `AMENAPP/AmenGlassButtonSystem.swift` | _this commit_ | 0 | ✅ landed |

**Phase B status: substantively complete.** State machine + ModalCoordinator + ButtonActionRouter + PaywallCoordinator + PermissionCoordinator + AmenLoadingButton, all compile-verified. NavigationCoordinator = existing DeepLinkRouter (not forked). Toasts = existing `ToastManager` (not forked — see correction below).

### Reconciliation (extend-don't-fork correction)
Mid-Phase-C discovery: the app already has a canonical, app-wide toast system —
`ToastManager` + `ToastManagerExtensions` (`success`/`info`/`showError(retry:)`),
used in dozens of call sites. The `ToastCoordinator`/`AmenToastModel`/`AmenToastHost`
I had added in the two prior commits were therefore a **fork**. Removed them;
added a `failure(_:retry:)` convenience to `ToastManagerExtensions` and standardized
on `ToastManager`. (Commits fc23fce7 / 57667051 introduced the fork; this commit
removes it. State machine + the other 4 coordinators + AmenLoadingButton retained.)

## Phase C — Surface repair (consuming the foundation)
| Item | File | Commit | Per-file diags | Status |
|---|---|---|---|---|
| Silent block/mute failure now surfaces `ToastManager.shared.failure(...)` instead of a bare `dlog` (false sense of protection). | `AMENAPP/CommentsView.swift` | _this commit_ | 0 | ✅ landed |
| `ToastManager.failure(_:retry:)` convenience (canonical cure for swallowed errors). | `AMENAPP/ToastManagerExtensions.swift` | _this commit_ | 0 | ✅ landed |

## Finding correction
- **#6 (CreatorProfile hero CTAs)** — downgraded from CRITICAL-shipping to **latent dead code**. The surface is already gated by `isGateOpen` (the `enabled` param) and the only `CreatorProfileView(...)` call site is a DEBUG preview with `enabled: false` — no production caller passes `enabled: true`, so the `break` CTAs are not reachable in a shipped build. Real fix (wire the actions) belongs to the Wave-4 work that owns the surface; no urgent change made.

## Remaining CRITICALs
| # | Surface | File:line | Note |
|---|---|---|---|
| 2 | Spaces | `SpacesViewModel.swift:77` | join idempotency → needs transactional CF (Phase D, TS-first) |
| 3 | Spaces | `AmenSpaceModerationDashboardView.swift:631` | moderator data loaders are stubs → wire Firestore |
| 4 | Find a Church | `FindChurchView.swift:1216/1689/2351` | denied-location dead end → geocode-from-text fallback (in progress) |
