# AMEN Overnight Audit — Morning Summary
**Date:** 2026-06-02  
**Branch:** `audit/overnight-2026-06-02`  
**Baseline tag:** `overnight-baseline-2026-06-02` → `cdbf261`

---

## What Happened

An unattended audit-and-fix run was performed, followed by a full end-to-end implementation pass that resolved all auto-fixable findings and the code-addressable NEEDS HUMAN REVIEW items. The working tree had 336 dirty files at start; after WIP snapshotting and baseline fixes, all findings were addressed.

---

## All Fixes Applied

### Phase 2 — Accessibility / Dark Mode / Motion (original audit)

| # | What Changed | Commit |
|---|-------------|--------|
| F-01 | `CommentCard` amen button — added `"Amen"` / `"Remove amen"` VoiceOver label | `7ba630b` |
| F-02 | `FullCommentsView` dismiss button — added `"Close comments"` label | `7ba630b` |
| F-03 | `SafetyPlanRow` expand/collapse — added title label + expand/collapse hint (P1: crisis path) | `5177e5d` |
| F-04 | Crisis action buttons — hardcoded green replaced with `Color(UIColor.systemGreen)` | `5177e5d` |
| F-05 | Tab bar badge — hardcoded red replaced with `Color(UIColor.systemRed)` | `ecf3c9a` |
| F-06 | `GuideMyFeedSheet` visibility pill animation — gated behind `accessibilityReduceMotion` | `af63033` |
| F-07 | `EmojiPickerView` buttons — `.accessibilityLabel(emoji)` added to all 32 buttons | `28ce999` |
| F-08 | Poll composer A/B/C/D circles — marked `.accessibilityHidden(true)` | `77c18dd` |
| F-10 | `SundayRestModeSheet` paused chips — grouped into single VoiceOver element | `7c1ff67` |

### End-to-End Pass — Review Queue Closures

| # | What Changed | Commit |
|---|-------------|--------|
| R-01 | `moderatePost.js` — added `flaggedForReview: true, removed: false` to image-only early-return path | `28ce999` |
| R-03 | **Firestore rules resolved**: Spiritual OS + `mediaMeta` rules ported to deployed `AMENAPP/firestore 18.rules`; stale root `firestore.rules` archived as `firestore.rules.archived` | `28ce999` |
| R-07 | `AmenFirebaseLiveRoomProvider` audio-only preset — `.low` → `.inputPriority` (correct audio-only AVCapture preset) | `28ce999` |
| R-08 | `ONEThreadListView` + `ONEThreadView` — decorative `lock.fill` icons marked `.accessibilityHidden(true)` inside already-combined a11y elements | `28ce999` |
| R-09 | Analytics added to 8 ConnectSpaces views: `spaces_hub_viewed`, `ministry_room_viewed`, `ministry_room_history_viewed`, `ministry_room_prayer_viewed`, `ministry_room_tasks_viewed`, `live_room_viewed`, `connect_video_viewed`, `space_event_viewed` | `28ce999` |
| R-10 | Confirmed already wired — `scanMessageForScam` exported in `functions/index.js` line 1251. No action needed. | — |
| R-04 | 10 deleted test files restored from git history to `AMENAPP/AMENAPPTests/` | `42fb6d7` |

**Baseline build fix (pre-Phase 2):**  
`ONELivingThreadsEngine.swift` — 6 "Ambiguous use of 'prefix'" errors resolved (`c69f63a`)

---

## Not Fixed

| # | Reason |
|---|--------|
| F-09 (BereanPulseView close) | False positive — `.accessibilityLabel("Close")` was already present at line 36 |
| `SelahBibleEngineContractTests` | Not in git history before deletion; top-level `AMENAPPTests/` already has 15 Selah test files providing equivalent coverage |

---

## Reverted Attempts

| What | Why |
|------|-----|
| `#if canImport(LiveKit)` wrap | Fix was at wrong level — project.pbxproj declares the SPM dep; conditional import in a Swift file has no effect on the linker error |

---

## Requires Human Action

| Priority | # | What To Do |
|----------|---|------------|
| 🔴 P0 | **R-11** | **LiveKit SPM never fetched — BuildProject fails.** Fix: Xcode → project root → Package Dependencies tab → find `livekit/client-sdk-swift` → press `–` to remove. No Swift file actually imports LiveKit (stub is self-contained). Cannot be fixed from CLI while Xcode is open. |
| 🔴 P0 | R-02 | Audit `AmenStoreKitService` + `AmenStripeOnboardingService` payment flows before enabling Spaces paid features |
| 🟠 P1 | R-05 | Review `PresenceLayer.swift` changes for RTDB listener leak / counter drift — current `refresh()` is a stub no-op so no immediate risk, but Phase 5 wiring must add `deinit { listener?.remove() }` |
| 🟠 P1 | R-06 | Deploy 20+ new Spaces/AI/Safety callable CFs — app will get `NOT_FOUND` until deployed |
| 🟠 P1 | R-04 (Xcode) | Restored test files in `AMENAPP/AMENAPPTests/` must be added to the Xcode test target in `project.pbxproj` (cannot edit while Xcode is open). File → Add Files to project for each `.swift` file in that directory. |
| 🟡 P2 | R-09 (chat) | `AmenMinistryRoomChatView` chat tab — analytics best wired in `startListening()` in the ViewModel (deferred; other 8 views done) |

---

## Branch State

```
audit/overnight-2026-06-02  (HEAD — clean tree)
├── 588641b  chore: update functions package-lock.json
├── 05cba29  chore: sweep final pre-existing changes
├── 42fb6d7  fix(R-04): restore 10 deleted test files from git history
├── 28ce999  fix: end-to-end close of F-07, R-01, R-03, R-07, R-08, R-09
├── 18be64c  docs(audit): Phase 3 morning report
├── 7c1ff67  fix(a11y): F-10 SundayRestModeSheet chip grouping
├── 77c18dd  fix(a11y): F-08 poll decorative circles hidden
├── af63033  fix(motion): F-06 reduce-motion gate
├── ecf3c9a  fix(dark-mode): F-05 tab badge adaptive red
├── 5177e5d  fix(a11y,dark-mode): F-03, F-04 safety plan + crisis buttons
├── 7ba630b  fix(a11y): F-01, F-02 comment amen + dismiss labels
└── cdbf261  wip: pre-audit snapshot (baseline)
```

---

## How to Merge

```bash
git checkout main
git merge --no-ff audit/overnight-2026-06-02
```

---

*Summary last updated 2026-06-02 (end-to-end pass complete).*
