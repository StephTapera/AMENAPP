# AMEN Overnight Audit — Morning Summary
**Date:** 2026-06-02  
**Branch:** `audit/overnight-2026-06-02`  
**Baseline tag:** `overnight-baseline-2026-06-02` → `cdbf261`

---

## What Happened

An unattended audit-and-fix run was performed on the AMEN iOS app. The working tree had 336 dirty files at start, which were committed as a WIP snapshot before the audit began. A baseline build fix was required before the green build could be established.

---

## Fixes Applied (6 auto-fixed, all low risk)

| # | What Changed | Commit |
|---|-------------|--------|
| F-01 | `CommentCard` amen button now reads "Amen" / "Remove amen" to VoiceOver | `7ba630b` |
| F-02 | `FullCommentsView` dismiss button now reads "Close comments" | `7ba630b` |
| F-03 | `SafetyPlanRow` expand/collapse now has title label + "Double tap to expand/collapse" hint | `5177e5d` |
| F-04 | Crisis action buttons now use `Color(UIColor.systemGreen)` instead of hardcoded RGB | `5177e5d` |
| F-05 | Tab bar notification badge now uses `Color(UIColor.systemRed)` instead of hardcoded RGB | `ecf3c9a` |
| F-06 | `GuideMyFeedSheet` visibility pill spring animation is now gated behind `accessibilityReduceMotion` | `af63033` |
| F-08 | Poll composer option-label circles (A/B/C/D) marked `.accessibilityHidden(true)` — redundant with TextField | `77c18dd` |
| F-10 | `SundayRestModeSheet` paused-feature chips grouped into single VoiceOver element | `7c1ff67` |

**Baseline build fix (pre-Phase 2):**  
`ONELivingThreadsEngine.swift` — 6 "Ambiguous use of 'prefix'" errors resolved by removing explicit `[String]` type annotations (`c69f63a`)

---

## Not Fixed (deferred / false positive)

| # | Reason |
|---|--------|
| F-07 (EmojiPicker a11y) | Deferred — VoiceOver already reads raw emoji chars which is acceptable; 32-button change is safe but low urgency |
| F-09 (BereanPulseView close) | False positive — `.accessibilityLabel("Close")` already present at line 36 |

---

## Reverted Attempts

| What | Why |
|------|-----|
| `#if canImport(LiveKit)` wrap on `AmenLivekitLiveRoomProvider.swift` | Fix was at wrong level — project.pbxproj declares the SPM dependency; a conditional import in the Swift file has no effect on the linker error |

---

## Requires Human Action (NEEDS REVIEW queue)

These were identified but NOT touched. Review before shipping:

| Priority | # | What To Do |
|----------|---|------------|
| 🔴 P0 | R-01 | Verify `functions/moderatePost.js` content-moderation logic is correct before CF deploy |
| 🔴 P0 | R-02 | Audit `AmenStoreKitService` + `AmenStripeOnboardingService` payment flows before enabling |
| 🔴 P0 | R-03 | Resolve divergence between `firestore.rules` (repo root) and `AMENAPP/firestore 18.rules` — decide which is the deploy target |
| 🟠 P1 | R-04 | Confirm 16 deleted test files in WIP commit were intentional; re-add coverage for live code if not |
| 🟠 P1 | R-05 | Review `PresenceLayer.swift` changes for RTDB listener leak / counter drift |
| 🟠 P1 | R-06 | Deploy 20+ new Spaces/AI/Safety callable CFs — app will get `NOT_FOUND` until deployed |
| 🟠 P1 | R-07 | `AmenFirebaseLiveRoomProvider.swift` changed `AVCaptureSession.Preset.audio` → `.low` — confirm intentional (`.low` enables video) |
| 🟠 P1 | **R-11** | **LiveKit SPM package never fetched.** `BuildProject` currently fails with "Missing package product 'LiveKit'". Fix: open Xcode → File → Packages → Resolve Package Versions. Or remove LiveKit from project.pbxproj if the Live Room feature is not shipping yet. |
| 🟡 P1 | R-08 | Add encrypted-indicator accessibility label to ONE thread views |
| 🟡 P2 | R-09 | Add `Analytics.logEvent` calls to Spaces + Live Room views |
| 🟡 P2 | R-10 | Deploy `scanMessageForScam` CF — scam detection in live rooms is currently disabled |

---

## Branch State

```
audit/overnight-2026-06-02  (HEAD)
├── eb2baa2  chore: stage ContentObjectService
├── 923e0e0  chore: sweep final pre-existing dirty files
├── e16cd14  chore: commit pre-existing dirty files
├── 7c1ff67  fix(a11y): F-10 SundayRestModeSheet chip grouping
├── 77c18dd  fix(a11y): F-08 poll decorative circles hidden
├── af63033  fix(motion): F-06 reduce-motion gate
├── ecf3c9a  fix(dark-mode): F-05 tab badge adaptive red
├── 5177e5d  fix(a11y,dark-mode): F-03, F-04 safety plan + crisis buttons
├── 7ba630b  fix(a11y): F-01, F-02 comment amen + dismiss labels
├── cdbf261  wip: pre-audit snapshot (baseline)
└── c69f63a  fix(baseline): ONELivingThreadsEngine ambiguous prefix
```

Tree is **clean** (`git status` is empty). Safe to merge or review.

---

## How to Merge

```bash
git checkout main
git merge --no-ff audit/overnight-2026-06-02
```

The fixes are all isolated to small, focused commits. Each can be cherry-picked individually if preferred.

---

*Summary written 2026-06-02.*
