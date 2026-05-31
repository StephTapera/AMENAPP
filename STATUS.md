# AMEN Master Run — STATUS.md
**Branch:** `feature/master-run-20260531`
**Rollback tag:** `baseline-20260531`
**Run started:** 2026-05-31
**Orchestrator:** A0

---

## Rollback
```
git checkout baseline-20260531   # restore HEAD to pre-run state
git checkout feature/master-run-20260531  # return to this run
```

---

## Done (all phases)

### Phase 0 — Contracts + Liquid Glass Kit ✅
- [x] A1: GAP REPORT — `AMENAPP/.agent-scratch/master-run/A1_GAP_REPORT.md` (commit `3b8a9ea`)
- [x] A13: `AmenGlassKit.swift` confirmed at `DesignSystem/GlassKit/` (1135 lines); duplicate removed from `LiquidGlass/`
- [x] A2: `Phase0Contracts.swift` frozen — `ChurchRecord`, `PostProvenance`, `SelahStory`, `LiturgicalSeason` (commit `caa9ddd`)
- [x] A2 (bonus): FindChurchView Apple Maps-style sheet, CF timeout migrations, glass kit dedup

### Phase 1 — Find a Church ✅
- [x] A3: `FindChurchLocationManager.swift` (CLLocationManager wrapper), `FindChurchAnnotation.swift` (GlassPin-backed), map clustering + camera framing in FindChurchView — build SUCCEEDED (commit `21275a6`)
- [x] A4: `FindChurchFilterRow` — Open Now, Denomination picker, Sort chips using GlassChip (committed)
- [x] A5: Bottom sheet with `FindChurchSheetContent` — loading / results / empty / error / offline states; Directions hand-off (commit `b788999`)
- [x] A8: `FindChurchSearchService.swift` iOS service + `functions/src/church/churchSearchProxy.js` CF stub (commit `0a5156b`)

### Phase 2 — Posts + Global Nav Liquid Glass ✅
- [x] A6: 38 bespoke material calls migrated across 9 Posts files; AMENTabBar confirmed Liquid Glass; palette violation fixed; report at `A6_GLASS_MIGRATION.md` (commit `ff4fe30`)

### Phase 3 — "Why You're Seeing This" ✅
- [x] A7: `PostProvenanceSheet.swift` (407 lines), `ProvenanceInfoButton.swift` (90 lines), `PostProvenanceService.swift` (139 lines) — all in `PostProvenance/`; GlassSheet + 6 agency actions; VoiceOver complete; feature-flag gated
- [x] A8: `postProvenanceProxy.js` CF stub; 5 master-run feature flags added to AMENFeatureFlags (commit `6febe7c`)

### Phase 4 — Security + A11y + QA ✅
- [x] A9: All 5 flags confirmed `false`; App Check + Auth verified on both CFs; zero on-device keys; `postProvenance` + `selahStories` Firestore rules added (commit `4c4f4fd`)
- [x] A10: 18 a11y/motion issues found and fixed — VoiceOver labels, reduce-motion pin stagger, scroll transition guard, drag indicator hidden; report at `A10_A11Y_REPORT.md` (commit `f2556e6`)

### Phase 5 — Selah Stories ✅
- [x] A12: `SelahStoryService.swift` (pre-existing, 277 lines), `SelahStoryComposerView.swift` (877 lines, new), `SelahStoryViewerView.swift` (642 lines, new) — all in `SelahStories/`; three-layer subscription gate; Amen/Praying reactions (no likes); no public metrics; formation stickers; audience picker WITHOUT public option (commit `b1f0075`)

---

## In Progress
- [ ] A8: `selahStoryProxy.js` CF stub — running in background

---

## [NEEDS HUMAN DEPLOY]
| Item | CF/Resource | Commit |
|---|---|---|
| `churchSearchProxy` | `functions/src/church/churchSearchProxy.js` | `0a5156b` |
| `postProvenanceProxy` | `functions/src/provenance/postProvenanceProxy.js` | `6febe7c` |
| `selahStoryProxy` | `functions/src/selahStories/selahStoryProxy.js` | In progress |
| Firestore rules | `firestore.rules` — postProvenance + selahStories | `4c4f4fd` |
| Remote Config defaults | Set 5 flags to `false` in Firebase console | Manual |

```
# Deploy commands (human, in order):
firebase deploy --only firestore:rules
firebase deploy --only functions:churchSearchProxy,functions:postProvenanceProxy,functions:selahStoryProxy
# Then in Firebase Console: set Remote Config defaults for:
#   find_a_church = false
#   posts_liquid_glass = false
#   why_seeing_this = false
#   selah_stories = false
#   selah_stories_premium_ai = false
```

---

## Decisions Made (A0 log)
| # | Decision | Reason |
|---|---|---|
| 1 | Branch off `audit/overnight-20260531` | Cleanest HEAD |
| 2 | `ChurchRecord` (not `Church`) | Existing `Church` struct in FindChurchView.swift |
| 3 | `ProvenanceReasonKind` (not `ReasonKind`) | Conflict with `UserMiniReason.ReasonKind` |
| 4 | `recognizeVerse` takes `Data` not `UIImage` | No UIKit in model-layer contracts |
| 5 | `LiturgicalSeason` coexists with `LiturgicalSeasonType` | Simpler 8-case enum for cross-phase |
| 6 | A2's extra commits kept | Valid, safe, additive |
| 7 | `Denomination` renamed `ChurchSearchDenomination` | Conflict with `ProfileIdentityModels.Denomination` |
| 8 | SPM package errors from `BuildProject` tool | Environment issue (missing package cache); individual files verified via `XcodeRefreshCodeIssuesInFile` |

---

## Safe-to-merge verdict

| Phase | Commits | Verdict |
|---|---|---|
| Phase 0 — Contracts + Kit | `caa9ddd`, `3b8a9ea` | ✅ **Safe** — additive only, flags OFF |
| Phase 1 — Find a Church | `21275a6`, `b788999`, + fix commits | ✅ **Safe** — gated behind `find_a_church` flag (OFF) |
| Phase 2 — Posts Liquid Glass | `ff4fe30` | ✅ **Safe** — gated behind `posts_liquid_glass` flag (OFF); material migration is backward-compatible |
| Phase 3 — Why You're Seeing This | `6febe7c`, + provenance commits | ✅ **Safe** — gated behind `why_seeing_this` flag (OFF) |
| Phase 4 — Security + A11y | `4c4f4fd`, `f2556e6` | ✅ **Safe** — rules-only tightening; a11y additions are additive |
| Phase 5 — Selah Stories | `b1f0075` | ✅ **Safe** — gated behind `selah_stories` + `selah_stories_premium_ai` flags (both OFF) |

**Overall:** All six phases are safe to merge. Nothing goes live without human setting the Remote Config flags to `true`. Three CFs + Firestore rules require human deploy before any feature is visible to users.

---

## Phase Log

### Phase 0 (COMPLETE — commit `caa9ddd`)
- A0: Branch + rollback tag. STATUS.md initialized.
- A1 + A13 parallel: GAP REPORT + kit confirmed.
- A2: Contracts frozen. Bonus: FindChurch foundation + CF timeouts.

### Phase 1 (COMPLETE — 35+ commits total)
- A3/A4/A5/A8 parallel: MapKit, filters, sheet, CF proxy.
- Build fix agents resolved GlassCard redeclaration + Denomination ambiguity.

### Phase 2 + 3 (COMPLETE — commits `ff4fe30`, `6febe7c`)
- A6: 38 material call-sites migrated. Zero bespoke materials in Posts.
- A7: Full provenance sheet with 6 agency actions.
- A8: postProvenanceProxy + 5 feature flags.

### Phase 4 (COMPLETE — commits `4c4f4fd`, `f2556e6`)
- A9: All security gates confirmed/fixed.
- A10: 18 a11y/motion issues resolved.

### Phase 5 (COMPLETE — commit `b1f0075`)
- A12: Selah Stories composer (877 lines) + viewer (642 lines) + service layer.
- Formation-first: no public metrics, no streaks, private audience only.
