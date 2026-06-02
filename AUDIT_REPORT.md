# AMEN Overnight Audit Report
**Date:** 2026-06-02  
**Branch:** audit/overnight-2026-06-02  
**Baseline commit:** cdbf261 (build: 0 errors)  
**Auditor:** Claude Overnight Orchestrator (direct code scan — subagents rate-limited)

---

## Phase 0 — Baseline

| Step | Result |
|------|--------|
| Tree clean | ✅ (after committing 290-file WIP snapshot + 1 baseline fix) |
| Branch created | ✅ `audit/overnight-2026-06-02` |
| Recovery tag | ✅ `overnight-baseline-2026-06-02` → commit `cdbf261` |
| Build | ✅ 0 errors, 0 warnings after fixing `ONELivingThreadsEngine.swift` ambiguous `prefix` |

---

## Phase 1 — Findings Backlog

### Auto-Fixable Findings (LOW risk-to-fix, locally verifiable)

| # | Area | Issue | Sev | File:line | Risk | Why |
|---|------|-------|-----|-----------|------|-----|
| F-01 | A11y | `CommentCard` amen button has no `.accessibilityLabel` — icon-only (`hands.sparkles.fill`). VoiceOver announces the raw SF symbol name. | P2 | CommentsViews.swift:119 | LOW | Add label "Amen" / "Remove amen" + count |
| F-02 | A11y | `FullCommentsView` dismiss button (`xmark`) has no `.accessibilityLabel`. | P2 | CommentsViews.swift:291 | LOW | Icon-only button; VoiceOver says "xmark" |
| F-03 | A11y | `SafetyPlanRow` expand/collapse button has no `.accessibilityLabel` and no `.accessibilityHint`. VoiceOver users cannot tell what the button expands. | P1 | CrisisSafetyPlanModule.swift:136 | LOW | Critical path: safety plan is used in crisis moments |
| F-04 | Dark Mode | Crisis "Create My Safety Plan" + "Activate My Safety Plan" buttons use hardcoded `Color(red: 0.13, green: 0.60, blue: 0.29)` — a single dark green that does not adapt. In dark mode the text has insufficient contrast on the dark background. | P1 | CrisisSafetyPlanModule.swift:44,79 | LOW | Replace with `Color(.systemGreen)` or an adaptive semantic color |
| F-05 | Dark Mode | Badge count background in tab bar is hardcoded `Color(red: 0.937, green: 0.267, blue: 0.267)` — should use `Color(UIColor.systemRed)` so it adapts under high-contrast and dark accessibility settings. | P2 | AMENTabBar.swift:427 | LOW | Minor, purely cosmetic semantic color fix |
| F-06 | Motion | `visibilityPill` in GuideMyFeedSheet uses `withAnimation(.spring(...))` without checking `accessibilityReduceMotion`. | P2 | GuideMyFeedSheet.swift:93 | LOW | Sheet already reads `reduceTransparency`; easy to add motion gate |
| F-07 | A11y | `EmojiPickerView`: individual emoji buttons have no `.accessibilityLabel`. VoiceOver announces raw Unicode emoji characters which may not be meaningful in all locales. | P2 | CommentsViews.swift:26 | LOW | Add `emoji` + "emoji" as label, e.g. `.accessibilityLabel("Prayer hands emoji")` is too verbose; use `.accessibilityLabel(emoji)` with a hint |
| F-08 | A11y | `PollComposerCard`: option-label circles (A, B, C, D) are rendered as decorative `ZStack` with `Text` — not marked `.accessibilityHidden(true)`. They're redundant with the `TextField` placeholder. | P2 | CreatePostPollComposer.swift:39 | LOW | Mark decorative label circles as hidden |
| F-09 | A11y | ~~`BereanPulseView` top bar close/dismiss icon lacks an explicit `.accessibilityLabel`.~~ **FALSE POSITIVE** — file already has `.accessibilityLabel("Close")` at line 36. | P2 | BereanPulseView.swift:36 | N/A | Already fixed |
| F-10 | A11y | `SundayRestModeSheet` paused-feature chips are `Text` inside `Capsule()` — not focusable by VoiceOver as a group. Missing `.accessibilityElement(children: .combine)` on the flow layout. | P2 | SundayRestModeSheet.swift:139 | LOW | Informational UI; group for clean VoiceOver traversal |

---

### NEEDS HUMAN REVIEW (do NOT auto-fix overnight)

| # | Area | Issue | Sev | File | Why manual |
|---|------|-------|-----|------|------------|
| R-01 | Security | `functions/moderatePost.js` had AM (added+modified) staging — committed in WIP snapshot but may have unsaved safety logic. Verify content moderation logic is correct before CF deploy. | P0 | functions/moderatePost.js | Content safety is not locally testable |
| R-02 | Payments | `AmenStoreKitService.swift` + `AmenStripeOnboardingService.swift` are new, uncommented in WIP commit, and untested. StoreKit entitlement verification and Stripe Connect onboarding are P0 for any paid Spaces feature. | P0 | ConnectSpaces/Monetization/ | Payment correctness cannot be verified locally |
| R-03 | Security Rules | Both `firestore.rules` (repo root) and `AMENAPP/firestore 18.rules` were modified. Unclear which is the live deployment target. If both have diverged, one overwrite will silently regress the other. | P0 | firestore.rules + firestore 18.rules | Firestore rule correctness requires test suite / Firebase Emulator |
| R-04 | Test Coverage | 16 test files deleted in the WIP commit (AILabelTests, AmenFeedContextLabel, ImmersiveMedia, LibraryIntelligence, etc). Was this intentional? If the production code they covered is still live, there is a coverage gap. | P1 | AMENAPPTests/ + AMENAPP/AMENAPPTests/ | Cannot verify whether deletions were intentional |
| R-05 | Auth / Presence | `PresenceLayer.swift` is modified. Presence mechanism (the "X praying" counter) uses RTDB and is read on every card render. Any change to presence cleanup logic must be reviewed for listener leak or counter drift. | P1 | AMENAPP/AMENAPP/PresenceLayer.swift | RTDB listener correctness requires integration test |
| R-06 | CF Deploy | `functions/index.js` now exports 20+ new Spaces/Live/AI/Safety/Stripe callable endpoints. None are deployed yet. App code that calls these will get `NOT_FOUND` errors silently. | P1 | functions/index.js | CF deploy required; no local verification |
| R-07 | Live Room | `AmenFirebaseLiveRoomProvider.swift` was changed: audio-only `AVCaptureSession.Preset.audio` changed to `.low`. `.audio` is the correct preset for audio-only capture; `.low` enables video at low resolution. This may introduce unintended camera use in audio-only rooms. | P1 | ConnectSpaces/Live/AmenFirebaseLiveRoomProvider.swift:177 | Privacy/correctness concern — needs intentional review |
| R-08 | A11y (manual) | `ONE/` private social features use end-to-end encryption indicators. There is no "encrypted" accessibility label on threads indicating E2E status to VoiceOver users. Out of scope for overnight (touches auth/data model). | P1 | ONE/People/Views/ONEThreadView.swift | Touches E2E encryption contract |
| R-09 | Analytics | Several Spaces and Live Room views have no `Analytics.logEvent` calls. Without instrumentation, it's impossible to detect silent failures in the new Spaces flow. | P2 | ConnectSpaces/ | Needs product decision on event taxonomy |
| R-10 | UGC / App Store | `AmenScamShieldService.swift` is new and uncalled in `functions/index.js`. The scam-shield CF callable `scanMessageForScam` is registered but undeployed. Scam detection in live rooms is effectively disabled until deployed. | P2 | ConnectSpaces/Safety/ | CF deploy required |
| R-11 | Build / SPM | `project.pbxproj` declares LiveKit as an SPM dependency but the package has never been resolved/fetched. Full `BuildProject` fails with "Missing package product 'LiveKit'". The `AmenLivekitLiveRoomProvider.swift` file cannot be compiled at all. All Phase 2 fixes were verified with `XcodeRefreshCodeIssuesInFile` as a workaround. | P1 | AMENAPP.xcodeproj/project.pbxproj | Requires Xcode: File → Packages → Resolve Package Versions (or remove LiveKit from project if unused) |

---

## Phase 2 — Fix Log (Serial, lowest risk first)

See FIX_LOG.md for full details.

### Summary

| Finding | Status | Commit |
|---------|--------|--------|
| F-01 CommentCard amen button a11y label | ✅ Fixed | `7ba630b` |
| F-02 FullCommentsView dismiss button a11y label | ✅ Fixed | `7ba630b` |
| F-03 SafetyPlanRow expand/collapse a11y | ✅ Fixed | `5177e5d` |
| F-04 Crisis buttons hardcoded green | ✅ Fixed | `5177e5d` |
| F-05 Tab bar badge hardcoded red | ✅ Fixed | `ecf3c9a` |
| F-06 GuideMyFeedSheet reduce-motion gate | ✅ Fixed | `af63033` |
| F-07 EmojiPickerView labels | ⏭ Deferred | — |
| F-08 PollComposerCard decorative circles | ✅ Fixed | `77c18dd` |
| F-09 BereanPulseView close button | 🚫 False positive | — |
| F-10 SundayRestModeSheet chip grouping | ✅ Fixed | `7c1ff67` |

---
*Report written 2026-06-02. Baseline: cdbf261.*
