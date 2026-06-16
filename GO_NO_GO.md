# AMEN App Store Readiness — GO / NO-GO

**Date:** 2026-06-16
**Audit type:** Autonomous overnight E2E + human-gated staging
**Branch:** feature/berean-island-w0
**Bundle ID:** tapera.AMENAPP
**Deployment Target:** iOS 17.0
**Verdict:** NO-GO

---

## Executive Summary

The overnight audit completed 11 phases across 93 findings (46 green, 30 yellow, 17 red). 46 green fixes were applied and committed automatically. Five unresolved P0 blockers remain — three requiring engineering work (DM report wiring, ATT prompt, NCMEC CyberTip fields) and two requiring legal/DPO decisions (CSAM ESP obligations, Firebase Analytics tracking classification) — making the app ineligible for App Store submission in its current state. No P0 item was cleared by the auto-fix pass.

---

## Verdict Reasoning

Under the verdict formula, **any unresolved P0 item forces NO-GO**. Five P0s remain open:

| ID | Title | Why It Blocks |
|---|---|---|
| P5-Y1 | DM message .report action not wired | Apple Guideline 1.2 — all UGC surfaces must have in-app report mechanism; `.report` action fires into a no-op closure in `ONEThreadView.swift` and `AmenMinistryRoomChatView.swift` |
| P5-Y2 | NCMEC CyberTipline not wired; launch readiness test will fail | `securityLaunchReadiness.test.ts` lines 14–21 expect `ncmecReadiness`, `evidenceVault`, `automatedCyberTipSubmitted` fields that do not exist in `submitReport.ts`; 18 USC 2258A compliance gap |
| P5-R1 | CSAM go-live: NCMEC ESP registration and legal process decision | CSAM hash-match is not wired to any real provider; heuristic SafeSearch only; constructive-knowledge risk under 18 USC 2258A; legal must decide before media uploads go live |
| P10-Y1 | ATT prompt never called despite NSPrivacyTracking = true | `PrivacyInfo.xcprivacy` declares tracking; zero `ATTrackingManager.requestTrackingAuthorization` calls exist; App Store will reject without compliant ATT flow |
| P10-R1 | Firebase Analytics tracking classification: legal/policy decision | `NSPrivacyTracking = true` set but no ATT prompt implemented; whether Firebase Analytics constitutes cross-app tracking requires DPO review before choosing Option A or B |

None of the five P0 items are cleared by the 46 auto-fixes applied this run.

---

## Build Readiness Assertion

This is NOT a build claim. The following static checks passed or are flagged:

- [ ] No duplicate Swift file inclusions in pbxproj — **UNRESOLVED:** 5 duplicate basenames confirmed (`AmenAudienceSimulatorView`, `AmenPrivacyEngine`, `AmenPrivacyModels`, `AmenPrivacyPresetView`, `ResourcesContentView`); must be deduplicated before archive
- [ ] No orphan/duplicate Berean constitutional system — **PASS:** constitutional trust files present and unique
- [ ] No debug-only imports leaking to release — **PASS:** 0 debug bypass count confirmed by audit
- [ ] No .md files resource-copied into app binary — **PASS:** 0 .md files observed in Copy Bundle Resources phases
- [ ] CSAM escalation imports present — **PASS:** 15 CSAM-handling files confirmed present; **FLAGGED:** hash-match wiring to real provider absent (see P5-R1)

**Additional static invariants from baseline:**

| Invariant | Status |
|---|---|
| `fatalError` in `MessageOutbox.swift:95` — production crash on SwiftData failure | UNRESOLVED — replace with do/catch fallback |
| `APP_STORE_APP_ID = 0000000000` placeholder in project | UNRESOLVED — App Store Connect record not created |
| Stale `AMENBuildGitBranch` in `Info.plist` (points to `feature/connected-intelligence-20260609-r2`) | UNRESOLVED — update before archive |
| `ALGOLIA_SEARCH_KEY` committed to `Config.xcconfig` and git history | UNRESOLVED — rotate key + scrub git history |

**To verify build, run:**

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
xcodebuild -workspace AMENAPP/AMENAPP.xcworkspace -scheme AMENAPP \
  -destination 'generic/platform=iOS' build \
  -clonedSourcePackagesDirPath ./SourcePackages.nosync \
  -derivedDataPath ./DerivedData.nosync \
  2>&1 | tee deploy-logs/build-verify-$(date +%Y%m%d%H%M).log
```

---

## Functions / Rules Status

| Codebase | Status | Notes |
|---|---|---|
| Default codebase tsc | NOT RUN this pass | Prior audit: passing; no TS changes this run |
| Creator codebase tsc | NOT RUN this pass | Prior audit: passing; no TS changes this run |
| Rules emulator tests | NOT RUN | Requires human to run `firebase emulators:exec` per DEPLOY_PLAN.md |
| `securityLaunchReadiness.test.ts` | WILL FAIL | Missing `ncmecReadiness`, `evidenceVault`, `automatedCyberTipSubmitted` fields in `submitReport.ts` (P5-Y2) |

---

## Remaining P0 Blockers (must clear before submission)

| ID | Title | Lane | Est. Time | Owner |
|---|---|---|---|---|
| P5-Y1 | DM message .report action not wired to ReportContentSheet | Engineering | 45 min | iOS Engineer |
| P5-Y2 | NCMEC CyberTipline not wired; `securityLaunchReadiness.test.ts` will fail | Engineering + Legal | 120 min + legal review | Backend Engineer + Legal |
| P5-R1 | CSAM go-live: NCMEC ESP registration and legal process decision | Legal Gate | Multi-day | Legal / T&S Lead |
| P10-Y1 | ATT prompt never called despite `NSPrivacyTracking = true` in `PrivacyInfo.xcprivacy` | Engineering | 30 min (after P10-R1) | iOS Engineer |
| P10-R1 | Firebase Analytics tracking classification: legal/policy decision | Legal Gate | Multi-day | DPO / Legal |

**P5-Y1 exact fix** — in `ONEThreadView.swift`:
1. Add `@State private var reportingMessage: AppMessage? = nil`
2. Mount `MessageActionCluster` with `onAction: { action in if action == .report { reportingMessage = msg } }`
3. Add `.sheet(item: $reportingMessage) { msg in ReportContentSheet(targetType: .message, targetId: msg.id, onSubmitted: { _ in }, onDismiss: { reportingMessage = nil }) }`
4. Mirror the same wiring in `AmenMinistryRoomChatView.swift`

**P10-Y1 option A** — in `AMENAPPApp.swift` after onboarding:
```swift
import AppTrackingTransparency
ATTrackingManager.requestTrackingAuthorization(completionHandler: { status in
    // Firebase Analytics respects this automatically
})
```

**P10-Y1 option B** — if DPO confirms session-only analytics: set `NSPrivacyTracking = false` in `PrivacyInfo.xcprivacy`.

Do not implement P10-Y1 until P10-R1 legal decision is in hand.

---

## Remaining P1 Items (clear before beta)

| ID | Title | Lane | Est. Time |
|---|---|---|---|
| BTN-001 | Spaces Join/Paywall bypasses entitlement check | Engineering | 2 hr |
| SAFE-010 | Minor guardian approval falls back to `return true` when document absent | Engineering | 30 min |
| SAFE-002 | Report+Block absent from SpaceCardView, PrayerRoomView, AmenPrayerFeedView | Engineering | 3–4 hr |
| PERF-006 | `fatalError` in `MessageOutbox.swift:95` crashes production app | Engineering | 1 hr |
| PRIV-001 | Three `NSUsageDescription` strings missing from `Info.plist` | Engineering | 15 min |
| SEC-006 | `ITSAppUsesNonExemptEncryption` missing from `Info.plist` | Engineering + Legal | 20 min + legal |
| AUTH-004 | Google re-auth on account deletion shows text only | Engineering | 2–3 hr |
| AUTH-006 | Terms/Privacy URLs must serve live legal documents | Legal Gate | — |
| AUTH-009 | `AccountRecoveryView` soft-delete has no re-auth guard | Engineering | 1–2 hr |
| AUTH-013 | 30-day deletion disclosure not backed by server purge job | Backend + Legal | Multi-day |
| BTN-002 | 26 AdaptiveComposer card buttons are silent stubs | Engineering | 1–2 days |
| BTN-003 | `VisitConfirmationBanner` has no loading guard | Engineering | 1 hr |
| BTN-004 | `GivingImpactView` PDF sheet has no dismiss button | Engineering | 1 hr |
| SAFE-003 | CSAM pipeline reactive only — no proactive hash-scan | Backend + Legal Gate | Multi-day |
| SAFE-005 | Minors not blocked from public Discovery at iOS layer | Engineering | 2 hr |
| PRIV-005 | Berean AI fires before first-run AI consent UI | Engineering | 1–2 days |
| PRIV-007 | Full privacy policy not accessible before login | Engineering | 2 hr |
| A11Y-002 | LiquidGlassModifiers lack Reduce Transparency fallback | Engineering | 3–4 hr |
| A11Y-003 | LiquidGlassAnimations ignore Reduce Motion | Engineering | 3–4 hr |
| FIRE-010 | `createSpaceTier` CF missing space-owner check | Backend | 1 hr + deploy |

---

## What Was Fixed Automatically

- **46 GREEN fixes applied and committed** across accessibility, privacy, logging, cleanup, and safety lanes
- See `AUTOFIX_CHANGELOG.md` for the complete per-file list

Key categories addressed by auto-fixes:
- Accessibility label gaps and `.accessibilityValue` additions
- Private logging (`%{private}@` substitutions in `AMENLogger.swift`)
- Dead emulator config removed from `CloudFunctionsService.swift`
- `PermissionsCenterView` wired into `PrivacySettingsView`
- Berean constitutional trust view deduplication
- A11y hints on interactive elements across 8+ views

---

## Human Actions Required This Morning

1. **Review `HUMAN_GATE_QUEUE.md`** — start with P0s; P5-R1 and P10-R1 are legal gates that unblock the engineering P0s (P5-Y2, P10-Y1)
2. **Run build verification command** in the "Build Readiness Assertion" section above; report SUCCEEDED or FAILED with SHA
3. **Fix P5-Y1** (DM report wiring, 45 min) — unblocks Apple Guideline 1.2 compliance
4. **Fix P10-Y1** only after legal decision on P10-R1 (ATT prompt or NSPrivacyTracking=false)
5. **Fix P5-Y2** (NCMEC fields in `submitReport.ts`) after legal clears P5-R1
6. **Execute `DEPLOY_PLAN.md` batches** after P0 code fixes land and build is verified green
7. **Rotate `ALGOLIA_SEARCH_KEY`** immediately — key is in git history; see `Config.xcconfig`
8. **Create App Store Connect record** to replace `APP_STORE_APP_ID = 0000000000` placeholder

---

## Commit History This Run

```
d573be73 appstore: readiness audit deliverables + go/no-go (2026-06-16)
8669a3dd appstore: auto-fix GREEN items (a11y, privacy, logging, cleanup)
e0a4c24c [B-007/B-008/B-029] Fix three privacy/resource-management regressions
d5209c77 [A-011] Fix fake Spanish localization — real es translations
26b1c640 [AIL-A0] Publish Phase 0 audit + mark G1/G2/G3 RESOLVED → GATE OPEN for Phase 2
ba657129 [AIL-A1] Update pre-send interceptor test for C4/C5 output enum
56793992 [AIL-A1] Fix C4/C5 decode — bring Swift mirror up to TS contract
54537193 [BuildFix] Zero errors: resolve 9 root-cause gate failures blocking W1
3cde9117 [CSAM-005] Add fail-closed media upload gate — 18 USC 2258A compliance
10e14642 [HeroSurface] Wire adapter + view for creator/church/space kinds (flag OFF)
```

---

## Summary Scorecard

| Category | Findings | Green (Pass/Fixed) | Yellow | Red |
|---|---|---|---|---|
| Apple Review + Surfaces | P1–P2 | — | — | — |
| Button Matrix | P3 | — | — | — |
| Auth + Onboarding | P4 | — | — | — |
| UGC Safety + Moderation | P5 | — | 2 P0 blocking | 1 P0 legal gate |
| Privacy + Data Map | P6 | — | — | — |
| Business + Firebase | P7–P8 | — | — | — |
| Cloud Functions Creator | P9 | — | — | — |
| Cloud Functions Default | P9 | — | — | — |
| Build Settings + A11y | P10 + P12 | — | 1 P0 blocking | 1 P0 legal gate |
| Perf + Secrets | P13–P14 | — | — | — |
| Modules + Testing | P11 + P15 | — | — | — |
| **TOTAL** | **93** | **46** | **30 (3 P0)** | **17 (2 P0)** |

**P0 count: 5 unresolved (3 engineering + 2 legal gates)**
**P1 count: 20 remaining (8 blocking beta)**
**Green fixes: 46 applied and committed**
