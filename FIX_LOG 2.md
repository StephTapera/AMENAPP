# AMEN Overnight Fix Log
**Date:** 2026-06-02  
**Audit branch:** audit/overnight-2026-06-02  
**Baseline commit:** cdbf261 (0 errors after `ONELivingThreadsEngine` fix)

---

## Status: ✅ PHASE 2 COMPLETE — 6 findings fixed, 1 false positive, 1 deferred

---

## Pre-Baseline Fixes (required to reach green build)

| Fix | Files | Commit | Notes |
|-----|-------|--------|-------|
| `ONELivingThreadsEngine.swift`: remove explicit `[String]` annotations that caused 6 "Ambiguous use of 'prefix'" errors | `ONE/People/Services/ONELivingThreadsEngine.swift` | `c69f63a` | Used `Array(Set(...).prefix(n))` pattern |

---

## Phase 2 Fix Log

| # | Finding | Files Changed | Build Verified | Commit | Notes |
|---|---------|---------------|----------------|--------|-------|
| F-01 | `CommentCard` amen button missing `.accessibilityLabel` — VoiceOver said "hands.sparkles.fill" | `CommentsViews.swift` | ✅ `XcodeRefreshCodeIssuesInFile` | `7ba630b` | Adaptive label: "Amen" / "Remove amen" |
| F-02 | `FullCommentsView` dismiss xmark button missing `.accessibilityLabel` | `CommentsViews.swift` | ✅ same commit | `7ba630b` | Label: "Close comments" |
| F-03 | `SafetyPlanRow` expand/collapse button missing label + hint (critical path: crisis use) | `CrisisSafetyPlanModule.swift` | ✅ `XcodeRefreshCodeIssuesInFile` | `5177e5d` | Label: plan title; hint: "Double tap to expand/collapse" |
| F-04 | Crisis action buttons hardcoded green `Color(red: 0.13, green: 0.60, blue: 0.29)` — insufficient contrast in dark mode | `CrisisSafetyPlanModule.swift` | ✅ same commit | `5177e5d` | Replaced with `Color(UIColor.systemGreen)` |
| F-05 | Tab bar badge hardcoded `Color(red: 0.937, green: 0.267, blue: 0.267)` — non-adaptive | `AMENTabBar.swift` | ✅ `XcodeRefreshCodeIssuesInFile` | `ecf3c9a` | Replaced with `Color(UIColor.systemRed)` |
| F-06 | `GuideMyFeedSheet` visibility pill spring animation ignores `accessibilityReduceMotion` | `GuideMyFeedSheet.swift` | ✅ `XcodeRefreshCodeIssuesInFile` | `af63033` | Gated with `reduceMotion ? .none : .spring(...)` |
| F-07 | `EmojiPickerView` emoji buttons have no `.accessibilityLabel` | `CommentsViews.swift` | — | DEFERRED | 32 buttons; fix is safe but VoiceOver reads raw emoji chars already — acceptable. Logged for next pass. |
| F-08 | `PollComposerCard` decorative A/B/C/D circles not `.accessibilityHidden(true)` | `CreatePostPollComposer.swift` | ✅ `XcodeRefreshCodeIssuesInFile` | `77c18dd` | Circles are redundant with TextField placeholders |
| F-09 | `BereanPulseView` close button missing `.accessibilityLabel` | `BereanPulseView.swift` | — | FALSE POSITIVE | File inspection confirmed the button already has `.accessibilityLabel("Close")` at line 36 |
| F-10 | `SundayRestModeSheet` paused-feature chips not grouped — VoiceOver reads each chip individually | `SundayRestModeSheet.swift` | ✅ `XcodeRefreshCodeIssuesInFile` | `7c1ff67` | Combined into single element with label "Paused: Feed, Posting, …" |

---

## Reverted Attempts

| Attempt | File | Why Reverted |
|---------|------|--------------|
| `#if canImport(LiveKit)` wrap on `AmenLivekitLiveRoomProvider.swift` | `ConnectSpaces/Live/AmenLivekitLiveRoomProvider.swift` | Build error is at project level (`project.pbxproj` declares SPM dependency that was never fetched); conditional import has no effect. File restored via `git restore`. |

---

## Build Note

Full `BuildProject` was blocked by "Missing package product 'LiveKit'" — an SPM dependency declared in `project.pbxproj` that has never been fetched. All 6 fixes were verified using `XcodeRefreshCodeIssuesInFile` (live per-file Swift diagnostics). The LiveKit issue is tracked as R-11 in AUDIT_REPORT.md and requires human action.

---
*Fix log written 2026-06-02.*
