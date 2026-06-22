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
| CRITICAL #1 — Berean crisis pill no longer loops back into the AI; "Find immediate help" now presents the always-on `CrisisResourceOverlayView` (988-first) via `.fullScreenCover` + `interactiveDismissDisabled`, mirroring `BereanChatView` escalation. Safety + Companion-Boundary fix. | `AMENAPP/BereanSmartPillSystem.swift` | _pending_ | 0 | ✅ fix landed |

## Remaining CRITICALs (not yet started — gated on user direction / Phase B)
| # | Surface | File:line | Note |
|---|---|---|---|
| 2 | Spaces | `SpacesViewModel.swift:77` | join idempotency → needs transactional CF (Phase D, TS-first) |
| 3 | Spaces | `AmenSpaceModerationDashboardView.swift:631` | moderator data loaders are stubs → wire Firestore |
| 4 | Find a Church | `FindChurchView.swift:1216/1689/2351` | denied-location dead end → geocode-from-text fallback |
| 5 | Resources | `AMENResourceDetailView.swift:332` | media Save ephemeral → persist + load initial |
| 6 | Profile | `CreatorProfileView.swift:237` | hero CTAs `break` → wire or flag-gate off |
