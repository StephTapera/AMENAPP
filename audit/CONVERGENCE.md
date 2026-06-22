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
| Reusable components (extend `AmenGlassButtonSystem`/`AmenToast`/`AmenActionPill`; add ToastHost, Loading/Destructive buttons) | `AMENAPP/AmenGlassButtonSystem.swift` | _next_ | — | ⏳ in progress |

## Finding correction
- **#6 (CreatorProfile hero CTAs)** — downgraded from CRITICAL-shipping to **latent dead code**. The surface is already gated by `isGateOpen` (the `enabled` param) and the only `CreatorProfileView(...)` call site is a DEBUG preview with `enabled: false` — no production caller passes `enabled: true`, so the `break` CTAs are not reachable in a shipped build. Real fix (wire the actions) belongs to the Wave-4 work that owns the surface; no urgent change made.

## Remaining CRITICALs
| # | Surface | File:line | Note |
|---|---|---|---|
| 2 | Spaces | `SpacesViewModel.swift:77` | join idempotency → needs transactional CF (Phase D, TS-first) |
| 3 | Spaces | `AmenSpaceModerationDashboardView.swift:631` | moderator data loaders are stubs → wire Firestore |
| 4 | Find a Church | `FindChurchView.swift:1216/1689/2351` | denied-location dead end → geocode-from-text fallback (in progress) |
