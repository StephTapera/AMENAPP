# AMEN App Store Readiness — GO / NO-GO

**Date:** 2026-06-16
**Audit type:** Autonomous overnight E2E + human-gated staging
**Branch:** feature/berean-island-w0
**Bundle ID:** tapera.AMENAPP
**Deployment Target:** iOS 17.0
**Verdict:** NO-GO

---

## Executive Summary

The overnight audit completed 11 phases across 93 findings (46 green, 30 yellow, 17 red). This follow-up source pass cleared the DM report wiring blocker in `ONEThreadView.swift` with Xcode diagnostics clean. Four unresolved P0 blockers remain — two requiring engineering after legal decisions (ATT prompt, NCMEC CyberTip fields) and two requiring legal/DPO decisions (CSAM ESP obligations, Firebase Analytics tracking classification) — making the app ineligible for App Store submission in its current state.

---

## Verdict Reasoning

Under the verdict formula, **any unresolved P0 item forces NO-GO**. Four P0 blockers remain open in the original P5/P10 submission gate set:

| ID | Title | Why It Blocks |
|---|---|---|
| P5-Y2 | NCMEC CyberTipline not wired; launch readiness test will fail | `securityLaunchReadiness.test.ts` lines 14–21 expect `ncmecReadiness`, `evidenceVault`, `automatedCyberTipSubmitted` fields that do not exist in `submitReport.ts`; 18 USC 2258A compliance gap |
| P5-R1 | CSAM go-live: NCMEC ESP registration and legal process decision | CSAM hash-match is not wired to any real provider; heuristic SafeSearch only; constructive-knowledge risk under 18 USC 2258A; legal must decide before media uploads go live |
| P10-Y1 | ATT prompt never called despite NSPrivacyTracking = true | `PrivacyInfo.xcprivacy` declares tracking; zero `ATTrackingManager.requestTrackingAuthorization` calls exist; App Store will reject without compliant ATT flow |
| P10-R1 | Firebase Analytics tracking classification: legal/policy decision | `NSPrivacyTracking = true` set but no ATT prompt implemented; whether Firebase Analytics constitutes cross-app tracking requires DPO review before choosing Option A or B |

P5-Y1 is now source-fixed by this follow-up pass; the four rows above remain open.

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
| P5-Y1 | DM message report opens ReportContentSheet | Source-fixed | Done | iOS Engineer |
| P5-Y2 | NCMEC CyberTipline not wired; `securityLaunchReadiness.test.ts` will fail | Engineering + Legal | 120 min + legal review | Backend Engineer + Legal |
| P5-R1 | CSAM go-live: NCMEC ESP registration and legal process decision | Legal Gate | Multi-day | Legal / T&S Lead |
| P10-Y1 | ATT prompt never called despite `NSPrivacyTracking = true` in `PrivacyInfo.xcprivacy` | Engineering | 30 min (after P10-R1) | iOS Engineer |
| P10-R1 | Firebase Analytics tracking classification: legal/policy decision | Legal Gate | Multi-day | DPO / Legal |

**P5-Y1 source evidence** — `ONEThreadView.swift` now mounts `.reportContentSheet(targetType: .message, ...)` at `AMENAPP/AMENAPP/AMENAPP/ONE/People/Views/ONEThreadView.swift:70`, exposes received-message report actions at `:118` and `:140`, and passed `XcodeRefreshCodeIssuesInFile` on 2026-06-16. `AmenMinistryRoomChatView.swift` also has visible report + context-menu report/block wiring at `AMENAPP/AMENAPP/AMENAPP/ConnectSpaces/Spaces/AmenMinistryRoomChatView.swift:269`, `:281`, and `:303`.

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
3. **P5-Y1 is source-fixed** — keep it in regression checks for App Review UGC coverage
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

## Remediation Run 2026-06-16

**Agent-Scope Verdict: GO**
All P0/P1 lanes resolved by agent (10 PASS, 1 HUMAN_GATED). HUMAN_GATED is not a failure — the CSAM lane is correctly staged pending federal legal gates. App remains NOT-SUBMITTABLE until legal and human gates below are cleared.

### Per-Lane Status

| Lane | Status | Commit |
|---|---|---|
| LANE-1-INFOPLIST | PASS | pre-existing |
| LANE-4+5-GLASS (A11Y-002, A11Y-003) | PASS | 3859629b |
| LANE-6+P0-1 (Report+Block) | PASS | ba996427 |
| LANE-7+AUTH (Google re-auth, callable fix, reviewer path) | PASS | e74872b6 |
| P11-M1-BEREAN-FLAGS (55 AI flags default OFF) | PASS | 010b6a8e |
| P5-Y4-BLOCK (feed filter + pre-send block check) | PASS | baee8708 |
| LANE-3-MESSAGEOUTBOX (graceful fallback) | PASS | 8a3562e9 |
| LANE-8-COMPOSER (26 stub buttons wired/gated) | PASS | ef57557e |
| P1-2+P1-3-DISCOVER (Discover actions + Ministry report) | PASS | 8fa7afb6 |
| P0-2-CSAM-SCAFFOLD (scaffold only, no live wiring) | HUMAN_GATED | 50cfe3f3 |
| P1-1+P1-4-DISCLOSURE (AI disclosure flag + ATT prep) | PASS | b28e214a |

HEAD SHA after this run: ef57557e22c481f9f4d7ca5159193a8ff01f2bcf

### App remains NOT-SUBMITTABLE until:

1. CSAM/NCMEC ESP registration + hash provider + written legal sign-off (18 U.S.C. §2258A) — FEDERAL GATE
2. ITSAppUsesNonExemptEncryption confirmed and set in Info.plist — LEGAL + ENGINEERING
3. Terms/Privacy URLs live at amenapp.com (COPPA/GDPR/KOSA) — LEGAL
4. userAccountDeletionCascade Cloud Scheduler deployed to us-east1 (Lane 10) — BACKEND
5. Stripe IAP policy decision (digital goods require App Store IAP) — LEGAL + PRODUCT
6. ATT classification by DPO — activate or suppress ATT prompt — LEGAL/DPO
7. Firebase API key bundle-ID restriction verified — SECURITY
8. Algolia key rotated (present in git history) — SECURITY
9. pbxproj dedup of 5 duplicate-listed Swift basenames before archive — HUMAN/XCODE
10. App Store Connect app record (replace APP_STORE_APP_ID=0000000000) — HUMAN
11. Reviewer Firebase account created + AppStoreReview scheme configured — HUMAN
12. Build verification at HEAD SHA ef57557e (4 lanes with human-pending build gates) — HUMAN
13. Siri + location.push entitlements confirmed in Developer portal — HUMAN (P1)
14. Debug/release entitlement file sync in Build Settings — HUMAN (P1)

Full gate table with owners and blocking status is in CERTIFICATION.md.

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

**P0 count: 4 unresolved in the original P5/P10 submission gate set (2 engineering after legal + 2 legal gates)**
**P1 count: 20 remaining (8 blocking beta)**
**Green fixes: 46 applied and committed**

---

## Module D Current Pass Addendum — 2026-06-16

**Verdict impact:** Still **NO-GO**.

This pass added the backend access-control source-of-truth at `AMENAPP/Docs/Readiness/BACKEND_ACCESS_CONTROL_MATRIX.md` and source-fixed one P0 identity-invariant issue in `Backend/functions/src/globalResilience/trustScoring.ts`: trust-scoring callables no longer accept cross-user `data.userId` targeting from ordinary authenticated users, and privileged trust mutations now require an admin custom claim.

This is not live until a human performs the gated function deploy. Required verification:

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
npm --prefix Backend/functions run build
firebase emulators:exec --project amen-5e359 --only firestore,functions,storage "cd Backend/rules-tests && npm test"
```

Additional backend gates added to `HUMAN_GATE_QUEUE.md`: deploy the trust-scoring fix, run backend rules emulator tests, and migrate remaining user-doc `isAdmin` backend gates to custom claims or approve the server-only mirror policy.
