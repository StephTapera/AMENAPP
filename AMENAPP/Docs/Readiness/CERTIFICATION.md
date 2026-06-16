# AMEN — Agent-Scope Remediation Certification
Run date: 2026-06-16
Baseline SHA: 914356481796e03bf39ec2392528dc912be551c3
HEAD SHA: ef57557e22c481f9f4d7ca5159193a8ff01f2bcf

## Agent-Scope Verdict: GO

Note: HUMAN_GATED does not equal FAIL for agent scope. Human gates are correctly staged.
Note: App is NOT-SUBMITTABLE until all residual human/legal gates listed below are cleared.

---

## Per-Lane Status

| Lane | Status | Evidence Summary | Commit |
|---|---|---|---|
| LANE-1-INFOPLIST | PASS | All required NSUsageDescription keys present with AMEN-specific strings (no changes needed) | pre-existing |
| LANE-4+5-GLASS | PASS | reduceTransparency + reduceMotion fallbacks added to LiquidGlassMaterial, LiquidGlassComposerBar, LivingEntryLiquidGlassCard | 3859629b |
| LANE-6+P0-1 | PASS | Report+Block wired on Spaces, Prayer feed, Prayer room, ONE DMs, Ministry Room Chat via TrustSpineService/BlockService | ba996427 |
| LANE-7+AUTH | PASS | Google re-auth real flow, callable name fix (userAccountDeletionCascade), reviewer demo path (#if APPSTORE_REVIEW_BUILD) | e74872b6 |
| P11-M1-BEREAN-FLAGS | PASS | 55 AI/Berean flag defaults set to false across 7 files; Remote Config activates after consent-gate verification | 010b6a8e |
| P5-Y4-BLOCK | PASS | Block enforcement added to PostsManager.fetchFilteredPosts; pre-send block re-check in ONEMessageComposerView | baee8708 |
| LANE-3-MESSAGEOUTBOX | PASS | MessageOutbox init: in-memory ModelContainer fallback replaces container=nil on SwiftData failure | 8a3562e9 |
| LANE-8-COMPOSER | PASS | 26 AdaptiveComposer stub buttons resolved: 14 wired to real implementations, 12 flag-gated with .disabled(true) + accessibilityHint | ef57557e |
| P1-2+P1-3-DISCOVER | PASS | Discover onPray/onSave/onShare wired; Ministry Room discussion thread report context menu added | 8fa7afb6 |
| P0-2-CSAM-SCAFFOLD | HUMAN_GATED | Scaffold fields added to submitReport.ts (hashScanEnabled=false, automatedCyberTipSubmitted=false); federal law gate comment embedded; no live NCMEC endpoint | 50cfe3f3 |
| P1-1+P1-4-DISCLOSURE | PASS | AI disclosure flag (berean_ai_disclosure_enabled, default false) + ATT usage string prep; no ATT prompt activated | b28e214a |

---

## Build-Readiness Assertion

These are static checks only — NOT a build claim. Full build must be run by a human per CLAUDE.md.

### 3a. Duplicate Swift Basenames

Grep for `AmenAudienceSimulatorView|AmenPrivacyEngine|AmenPrivacyModels|AmenPrivacyPresetView|ResourcesContentView` in AMENAPP/ (*.swift):

- `AmenAudienceSimulatorView.swift` — 1 physical file at `AMENAPP/CommunityOS/Privacy/`
- `AmenPrivacyEngine.swift` — 1 physical file at `AMENAPP/CommunityOS/Privacy/`
- `AmenPrivacyModels.swift` — 1 physical file at `AMENAPP/CommunityOS/Privacy/`
- `AmenPrivacyPresetView.swift` — 1 physical file at `AMENAPP/CommunityOS/Privacy/`
- `ResourcesContentView.swift` — 1 physical file at `AMENAPP/Resources/` (`ResourcesView.swift` references it but is not a duplicate)

Physical files are not duplicated. However, the prior audit (GO_NO_GO.md) flagged that the pbxproj may list these basenames twice. Agent cannot inspect or modify project.pbxproj (Xcode file format, not agent-editable safely).

**HUMAN-PENDING at SHA ef57557e22c481f9f4d7ca5159193a8ff01f2bcf:** Verify and deduplicate any double-listed basenames in Xcode project navigator / Build Phases before archive. Archive will fail if a source file is compiled twice.

### 3b. CSAM Guards

- `csam_hash_scan_enabled.*true` in *.swift: **0 matches** — CLEAR
- `hashScanEnabled.*=.*true` in *.swift: **0 matches** — CLEAR
- `hashScanEnabled.*=.*true` in Backend/functions/src/*.ts: **0 live assignments** (matches are in comments only, values are `false`) — CLEAR
- `automatedCyberTipSubmitted.*=.*true` in Backend/functions/src/*.ts: **0 live assignments** (comment-only, value is `false`) — CLEAR

**Result: PASS — no CSAM flag is live.**

### 3c. Debug Bypass in Release

- `bypassAuthForTesting` in `MinimalAuthenticationView.swift:426` — inside `#if DEBUG` guard at line 423
- `bypassAuthForTesting` in `AMENAuthLandingView.swift:163` — inside `#if DEBUG` guard at line 160
- `bypassAuthForTesting` declaration in `AuthenticationViewModel.swift:2420` — inside `#if DEBUG` guard at line 2417

**Result: PASS — all bypass calls are behind #if DEBUG; none reach release builds.**

---

## Canonical Build Command (HUMAN RUNS)

```bash
echo "session:$(whoami)-remediation" > "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/.build-lock"
xcodebuild \
  -workspace "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPP.xcworkspace" \
  -scheme AMENAPP \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -clonedSourcePackagesDirPath "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/SourcePackages.nosync" \
  -derivedDataPath "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/DerivedData.nosync" \
  clean build 2>&1 | tee "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/deploy-logs/build-remediation-$(date +%Y%m%d%H%M).log"
rm "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/.build-lock"
```

---

## NOT-SUBMITTABLE-UNTIL (residual human/legal gates — ordered by severity)

| # | Gate | Owner | Action | Blocking |
|---|---|---|---|---|
| 1 | CSAM/NCMEC registration (federal) | Legal | Register as ESP; contract hash provider; written sign-off from counsel; non-engineer review of pipeline | YES — 18 U.S.C. §2258A |
| 2 | ITSAppUsesNonExemptEncryption | Legal + Engineering | Confirm E2EE scope in AMENEncryptionService; set key in Info.plist | YES |
| 3 | Terms/Privacy URLs live | Legal | Publish compliant COPPA/GDPR/KOSA documents at amenapp.com | YES |
| 4 | 30-day deletion Cloud Scheduler (Lane 10) | Backend | Verify or deploy userAccountDeletionCascade purge job — Lane 7 enqueues, Lane 10 executes (BOTH required) | YES |
| 5 | Stripe IAP policy decision | Legal + Product | Choose IAP model (App Store required for digital goods) | YES |
| 6 | ATT classification | Legal/DPO | DPO classifies tracking; wire or suppress ATT prompt after P10-R1 decision | YES |
| 7 | Firebase key bundle-ID restriction | Security | Verify API key is restricted to bundle ID in Firebase console; rotate if repo has been public | YES |
| 8 | Algolia key rotation | Security | Check git history; rotate ALGOLIA_SEARCH_KEY if confirmed present; add to .gitignore | YES |
| 9 | pbxproj dedup (5 Swift basenames) | Human/Xcode | Deduplicate double-listed entries in Xcode navigator before archive | YES (archive fails) |
| 10 | App Store Connect app record | Human | Replace APP_STORE_APP_ID=0000000000 with real record | YES |
| 11 | Reviewer Firebase account | Human | Create reviewer@amenapp-review.com; add REVIEWER_PASSWORD_ENV to AppStoreReview scheme; add -DAPPSTORE_REVIEW_BUILD Swift flag | YES |
| 12 | LANE-6+P0-1 build verify | Human | Run canonical xcodebuild at SHA ba996427 — new ReportTargetType cases + AMENSpace.createdBy field must compile clean | YES |
| 13 | LANE-7+AUTH build verify | Human | Run canonical xcodebuild at SHA e74872b6 — GoogleSignIn import + reauth flow must compile clean | YES |
| 14 | LANE-8-COMPOSER build verify | Human | Run canonical xcodebuild at SHA ef57557e — EventKit/CoreLocation imports must compile clean | YES |
| 15 | P1-2+P1-3 build verify | Human | Run canonical xcodebuild at SHA 8fa7afb6 — Discover actions + Ministry Room report must compile clean | YES |
| 16 | Siri + location.push entitlements | Human | Confirm approved in Developer portal and provisioning profile | P1 |
| 17 | Debug/release entitlement divergence | Human | Sync entitlements files in Xcode Build Settings | P1 |

Total residual human/legal gates: **17**

---

## DEPLOY_PLAN.md Batch Status

| Batch | Status | Notes |
|---|---|---|
| 1A (moderation blocking) | CLEARED | Run once FIRE-010 CF fix deployed |
| 1B/1C (CSAM reporting) | BLOCKED | Federal gate (#1 above) must clear first |
| 2 (account deletion) | CLEARED | Deploy userAccountDeletionCascade to us-east1 (us-central1 at quota); smoke-test before enabling hard-delete button |
| 3A-B (posts/comments) | CLEARED | |
| 3C (feed block enforcement) | CLEARED | Deploy once P5-Y4 changes confirmed green in build |
| 4 (messaging) | CLEARED | |
| 5 (AI/Berean) | CLEARED (partial) | Non-prayer-room features clear; prayer-chain consent (PRIV-005) must clear before prayer AI features |
| 6 (church/search) | CLEARED | |
| 7 (payments/giving) | BLOCKED | Stripe IAP policy decision required first (#5 above) |
| 8 (admin) | CLEARED | |

---

## Confirmed Guardrails

- csam_hash_scan_enabled: false — verified by grep (no live true assignment)
- automatedCyberTipSubmitted: false — verified by grep (no live true assignment)
- No project.pbxproj edits by agent
- No firebase deploy executed
- No secrets committed
- All new flags default OFF
- Not on main branch (current: feature/berean-island-w0)
- All debug bypasses inside #if DEBUG guards

---

## Commits in This Remediation Run (baseline → HEAD)

```
ef57557e fix(composer): gate/wire 26 AdaptiveComposer stub buttons (BTN-002, LANE-8)
8fa7afb6 fix(discover): wire Discover actions + Ministry Room report (P1-2, P1-3)
b28e214a scaffold(ai+privacy): AI disclosure stub + ATT usage string prep (P1-1, P1-4)
50cfe3f3 scaffold(csam): launch-readiness fields only — NO live NCMEC wiring (P0-2)
ba996427 fix(safety): Report+Block on Spaces/Prayer/DM surfaces (SAFE-002, P0-1)
010b6a8e fix(berean): AI feature flags default OFF — rely on Remote Config (P11-M1)
e74872b6 fix(auth): Google re-auth + callable name + reviewer demo path (AUTH-004, P0-4)
baee8708 fix(safety): block enforcement in feed filter + pre-send check (P5-Y4)
3859629b fix(glass): Reduce Transparency + Reduce Motion fallbacks (A11Y-002, A11Y-003)
8a3562e9 fix(perf): MessageOutbox fatalError → graceful in-memory fallback (PERF-006, LANE-3)
```
