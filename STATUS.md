# AMEN Master Run — STATUS.md
**Branch:** `feature/master-run-20260531`
**Rollback tag:** `baseline-20260531`
**Run started:** 2026-05-31
**Orchestrator:** A0

---

## Rollback
```
git checkout baseline-20260531   # restore HEAD to pre-run state
```

---

## Done
- [x] A0: Created branch `feature/master-run-20260531`
- [x] A0: Created rollback tag `baseline-20260531`
- [x] A0: STATUS.md initialized
- [x] A1: GAP REPORT complete → `AMENAPP/.agent-scratch/master-run/A1_GAP_REPORT.md` (commit `3b8a9ea`)
- [x] A13: AmenGlassKit confirmed at `DesignSystem/GlassKit/AmenGlassKit.swift` (1135 lines); duplicate at `LiquidGlass/AmenGlassKit.swift` removed by A2 cleanup
- [x] A2: Phase0Contracts.swift frozen at `MasterRunContracts/Phase0Contracts.swift` (commit `caa9ddd`)
- [x] A2 (unexpected-but-valid): FindChurchView Apple Maps-style bottom sheet + FindChurchGlassComponents.swift (commit `ef98c63`)
- [x] A2 (unexpected-but-valid): CF timeout migrations (30s AI / 15s moderation), docs updates (commit `ef98c63`, `15adbe0`)

---

## In Progress
- [ ] Phase 1 — Find a Church (A3 MapKit/clustering, A4 search+filters, A5 sheet+cards, A8 proxy)

---

## Blocked
_none_

---

## [NEEDS HUMAN DEPLOY]
| Item | CF Name | Written in commit |
|---|---|---|
| churchSearchProxy | `churchSearchProxy` | Pending — A8 Phase 1 |
| postProvenanceProxy | `postProvenanceProxy` | Pending — A8 Phase 3 |
| selahStoryProxy | `selahStoryProxy` | Pending — A8 Phase 5 |

---

## Decisions Made (A0 log)
| # | Decision | Reason |
|---|---|---|
| 1 | Branch off `audit/overnight-20260531` (HEAD) | Cleanest recent commit; no uncommitted work |
| 2 | A1 GAP REPORT + A13 Kit run in parallel | A13 kit spec is frozen in the prompt; independent of A1 |
| 3 | A2 contracts run after A1 finishes | A2 needs A1's findings to confirm no naming conflicts |
| 4 | `ChurchRecord` (not `Church`) for contract type | A `Church` struct already exists in FindChurchView.swift; can't redeclare |
| 5 | `ProvenanceReasonKind` (not `ReasonKind`) | `UserMiniReason.ReasonKind` already exists with different cases |
| 6 | `SelahStoryServiceProtocol.recognizeVerse` takes `Data` not `UIImage` | Avoids UIKit import in model-layer contract; Phase 5 A12 may change with A0 authorization |
| 7 | `LiturgicalSeason` coexists with `LiturgicalSeasonType` | Simpler 8-case enum for cross-phase use; does NOT replace the existing engine |
| 8 | A2's unexpected commits (`ef98c63`, `15adbe0`) are KEPT | Valid, safe, additive work; no conflicts; good Phase 1 head start |

---

## Safe-to-merge verdict (updated per phase)
| Phase | Status | Verdict |
|---|---|---|
| Phase 0 — Contracts + Kit | ✅ Complete | Safe — additive only, flags OFF |
| Phase 1 — Find a Church | 🔄 In progress | TBD |
| Phase 2 — Posts Liquid Glass | ⏳ Not started | TBD |
| Phase 3 — Why You're Seeing This | ⏳ Not started | TBD |
| Phase 4 — Security + A11y + QA | ⏳ Not started | TBD |
| Phase 5 — Selah Stories | ⏳ Not started | TBD |

---

## Phase Log

### Phase 0 (COMPLETE)
- A0: Branch + tag created. STATUS.md written.
- A1 + A13 launched in parallel.
- A1: GAP REPORT produced. Codebase 60-70% ready.
- A13: Kit confirmed + deduplicated. Canonical path: `DesignSystem/GlassKit/AmenGlassKit.swift`.
- A2: Contracts frozen with naming decisions (see Decisions table above).
- A2 (bonus): FindChurchView bottom sheet, FindChurchGlassComponents, CF timeout migrations.
- Phase 0 tag: commit `caa9ddd`.

### Phase 1 (IN PROGRESS)
- A0: Launching A3 (MapKit), A4 (search+filters), A5 (sheet+cards), A8 (backend proxy).
- Foundation from A2: FindChurchView has sheet state machine; FindChurchGlassComponents has card + search field.
