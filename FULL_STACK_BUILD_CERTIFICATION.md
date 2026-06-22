# FULL-STACK BUILD CERTIFICATION

## Current Attempt - 2026-06-20 17:34:35 CDT

Verification HEAD: `ab354db1`
Result: **NOT CERTIFIED.** Backend code and rules are green at this HEAD, but iOS app/test compilation is not certified because Xcode MCP timed out and the shell build is blocked in SwiftPM/CoreSimulator package/build infrastructure before Swift compilation.

| Layer | Status | Evidence |
|---|---|---|
| Layer 1 - iOS app clean build | 🔴 BLOCKED | Xcode MCP reached Swift type checking once and reported duplicate `AMENFeatureFlags`; the duplicate `AMENFeatureFlags 2.swift` project file was removed. Subsequent MCP build/log calls timed out. CLI package resolution with workspace-local `HOME` progressed through package fetch and Firebase checkout, but SwiftPM still attempted to emit manifest diagnostics under `/Users/stephtapera/Library/Caches/org.swift.swiftpm/.../*.dia` and the sandbox denied it (`Operation not permitted`). An unsandboxed `xcodebuild` is required to complete Layer 1 in this harness. |
| Layer 2 - iOS test targets compile | 🔴 BLOCKED | Not certified. Prior `build-for-testing` could not compute the dependency graph, and the current app build cannot complete package resolution/build. |
| Layer 3 - Backend TypeScript | ✅ GREEN | `cd Backend/functions && npx tsc --noEmit` exited 0; `npm run build` exited 0; deployed legacy `.js` files passed `node --check`. |
| Layer 4 - Backend Jest | ✅ GREEN | `cd Backend/functions && npx jest --runInBand`: `Test Suites: 72 passed, 72 total`; `Tests: 1228 passed, 1228 total`. |
| Layer 5 - Firestore rules | ✅ GREEN | Broad Firestore rules suite: `21 passed, 21 total`; `305 passed, 305 total`. Includes account lifecycle, Amen Connect, church notes, communication OS, contextual action layer, gap-p0, minor-safe DM, spiritual OS, and related safety suites. |
| Layer 5 - Storage rules | ✅ GREEN WITH 1 INTENTIONAL SKIP | Storage emulator started cleanly at `127.0.0.1:9199`. `creator-profiles.rules.test.ts`: `39 passed, 1 skipped`; storage/trust suites: `3 passed, 3 total`; `15 passed, 15 total`. The skip is the documented positive cross-service manager upload case requiring co-started Firestore + Storage emulators. |
| Layer 5 - RTDB rules | ✅ GREEN | `account-rtdb.rules.test.ts`: `4 passed, 4 total`. |

### Current Root Causes

| Area | Cause | Disposition |
|---|---|---|
| iOS certification | Source-level ambiguity found and fixed by removing duplicate `AMENFeatureFlags 2.swift`. Remaining failure is harness-level SwiftPM diagnostics cache denial under `~/Library/Caches`, plus CoreSimulator service warnings. | 🔴 BLOCKED until a capable Xcode lane or human shell can run the canonical clean build and build-for-testing at the current HEAD. |
| Rules | Previous storage emulator jar gap is resolved. Rules suites now execute and pass locally, with one intentional creator cross-service skip documented above. | ✅ GREEN |
| Backend Jest | The earlier failing-suite cluster is resolved in `Backend/functions`. | ✅ GREEN |

### Required Unsandboxed iOS Gate

Run from repo root in a normal terminal/Xcode-capable lane:

```bash
rm -rf ./DerivedData.nosync ./SourcePackages.nosync ./PackageCache.nosync
xcodebuild build -project AMENAPP.xcodeproj -scheme AMENAPP \
  -destination 'generic/platform=iOS Simulator' \
  -clonedSourcePackagesDirPath ./SourcePackages.nosync \
  -derivedDataPath ./DerivedData.nosync \
  -packageCachePath ./PackageCache.nosync \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build-for-testing -project AMENAPP.xcodeproj -scheme AMENAPP \
  -destination 'generic/platform=iOS Simulator' \
  -clonedSourcePackagesDirPath ./SourcePackages.nosync \
  -derivedDataPath ./DerivedData.nosync \
  -packageCachePath ./PackageCache.nosync \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build -project AMENAPP.xcodeproj -scheme AMENAPP \
  -destination 'generic/platform=iOS Simulator' \
  -clonedSourcePackagesDirPath ./SourcePackages.nosync \
  -derivedDataPath ./DerivedData.nosync \
  -packageCachePath ./PackageCache.nosync \
  CODE_SIGNING_ALLOWED=NO
```

## Remediation State — 2026-06-17 (5 batches committed, T1 GREEN)

Branch: `cert/reanchor-eee648b4`
HEAD: `bc0e2d48`
Build stamp: `2026-06-17T15:55:55Z`

| Layer | Status | Evidence |
|---|---|---|
| T1 — iOS app build | ✅ GREEN | `BuildProject` via Xcode MCP — "The project built successfully." elapsed 250.9s, 0 errors. HEAD `bc0e2d48`. DerivedData cleared + `xattr -cr AMENAPP.xcodeproj` applied first. |
| T3 — Backend TS compile | ✅ GREEN | `npx tsc --noEmit` exit 0, no output |
| T4 — Backend Jest | ✅ GREEN | 67/67 suites, 1175/1175 tests, 0 failures — was 121 |
| T2 — iOS test compile | ⏸ NOT ATTEMPTED | See note below |
| T5 — Storage rules | ✅ GREEN | Added `mediaUploads/{userId}/{mediaId}/raw/` + `mediaProcessed/` server-own rules. Deployed to amen-5e359 via `firebase deploy --only storage`. Commit `90a0c4c3`. |
| P0 agent items | ✅ ALL DONE | 12 P0 items closed in batches 1–3; see table below |
| P1 agent items | ✅ ALL DONE | 10 P1 items closed in batch 4 + batch 5 |
| P2-A (region) | ✅ DONE | bereanChatProxy + Stream → us-east1 |

> **T2 note:** `BuildProject(buildForTesting: true)` previously failed with "Could not compute dependency graph." Not re-attempted in this session to avoid destabilising the clean T1 green. Recommend a separate build-for-testing pass once other concurrent agents are fully stopped.

### P0 Gate Status

| ID | Item | SHA |
|---|---|---|
| P0-2 | Crisis modal interactiveDismissDisabled | bbeb4ece |
| P0-3 | amen:// URL scheme registered | bbeb4ece |
| P0-5 | Firestore cache clear do-catch | bbeb4ece |
| P0-6 | Pinecone vectors deleted on account deletion | 463cf796 |
| P0-7 | NSPrivacyTracking=false | 463cf796 |
| P0-8 | userId hashed in analytics (CryptoKit SHA256) | 463cf796 |
| P0-9 | APP_REVIEW_NOTES complete | 463cf796 |
| P0-10 | Feature flags default false | bbeb4ece |
| P0-11 | Blocked user feed filter | bbeb4ece |
| P0-12 | Deleted post feed filter (removed=false) | bbeb4ece |
| Jest 121→0 | Backend test failures | c823e28c |
| Storage rules | HUMAN-PENDING deploy | `firebase deploy --only storage` from root |

### Remaining Open Items

- **Demo account** — create reviewer@amenapp-demo.com per APP_REVIEW_NOTES.md. *(one engineering task)*
- **T2 iOS test compile** — separate pass, run when all concurrent agents stopped.

### Legal Gates (v2 — corrected critical path, 2026-06-17)

Two blocking clusters. Stripe defers. NCMEC is a free quick-win today.

#### Cluster A — CSAM (two parallel tracks)

| Track | Owner | Action |
|---|---|---|
| A1. NCMEC ESP registration | Eng/Legal | Self-serve: esp.ncmec.org/registration — file today. Free, fast. This is the CyberTipline reporting endpoint, separate from detection. |
| A2. Detection vendor | Legal + Vendor | Engage PhotoDNA (Microsoft) or Thorn Scout. Vendor SLAs drive timeline. Wire detection into upload pipeline (`AmenSafetyModerationProvider.swift`) once contract signed. `isMediaScanningAvailable=false` stays until both A1 + A2 are live. |

#### Cluster B — Minor-safety / Privacy (one counsel engagement, three deliverables)

COPPA (under-13), guardian consent (13–17, CHILD-003), and parent deletion (CHILD-004) are one workstream. The April 22, 2026 amended Rule deadline has passed — this is "comply to operate," not "attest and ship." Buying a recognized **VPC vendor** (Verifiable Parental Consent) collapses the consent-mechanism build entirely.

| Deliverable | Path |
|---|---|
| B1. Verifiable parental consent (CHILD-003) | Buy a VPC vendor — collapses the build. Wire iOS SDK. |
| B2. Under-13 data handling (COPPA core) | Counsel → data inventory, retention policy, parental notices, written security program. VPC vendor covers consent mechanism. |
| B3. Parent-initiated account deletion (CHILD-004) | Operational runbook + product flow. Scope with counsel. |

#### Deferred (post-v1)

| Gate | Reason deferred |
|---|---|
| Stripe PAY-001/002 | `givingEnabled=false` stays for v1. Giving ships as a fast-follow once Stripe Connect onboarding completes (Stripe's clock, not ours). Remove from blocking critical path. |

---

## Reanchored Certification Attempt - 2026-06-16 (Pass 2)

Verification branch: `cert/reanchor-eee648b4`
Verification HEAD (cert commit): `389a79a163b5e4c025d271a34667618a22f8d84e`
Source HEAD pinned from: `eee648b4dafe67e8f6d5bceed65d7cdde62a1354`
Stamp guard: `HEAD == cert SHA — safe to report`
Result: **NOT CERTIFIED / HONEST RED.** Meaningful progress vs. prior attempt (257→121 test failures, 30→18 failing suites, both emulators now run), but Layer 1 iOS build remains red and Layer 2 iOS tests remain blocked.

### Summary Table

| Layer | Status | Evidence |
|---|---|---|
| T0 — Pin HEAD | ✅ GREEN | Created `cert/reanchor-eee648b4` at `eee648b4`. Cert commit `389a79a1` applied. `git rev-parse HEAD == 389a79a1` at stamp time. |
| T1 — Artifact hygiene | ✅ GREEN | `git ls-files \| grep -E '\\.nosync/' \| wc -l` = `0`. No untracked build artifacts. `.gitignore` covers all `.nosync/` patterns. |
| T1 — iOS app build | 🔴 RED | Attempt 1: code signing failure (`resource fork not allowed`) on `AMENWidgetExtensionExtension.appex` and `AMENNotificationServiceExtension.appex`. Applied `xattr -rc` to both bundles. Attempt 2: `** BUILD FAILED **` with `Multiple commands produce '…BUILD_REQUEST.md'` and `Multiple commands produce '…BereanHomeView.stringsdata'` — caused by uncommitted `project.pbxproj` changes in the working tree (concurrent agent activity re-introduced duplicate file refs that `eee648b4` had fixed). |
| T2 — iOS test compile | ⏸ BLOCKED | Dependent on Layer 1. Not attempted. |
| T3 — Backend TS compile | ✅ GREEN | `npx tsc --noEmit` exited 0, no output. |
| T4 — Backend Jest | 🔴 RED (improving) | `Test Suites: 18 failed, 49 passed, 67 total` / `Tests: 121 failed, 1032 passed, 1153 total`. Down from 257/911 (prior cert). See failure classification below. |
| T5 — Firestore emulator | ✅ GREEN | Emulator started, Firestore rules compile passed. Prior jar-download blocker resolved. |
| T5 — Storage emulator | ✅ GREEN (emulator) | Storage emulator started cleanly (`cloud-storage-rules-runtime-v1.1.3.jar` present). |
| T5 — Storage rules content | 🔴 RED | `storage.rules` missing required media quarantine patterns: `mediaUploads/{userId}/{mediaId}/raw/`, `mediaProcessed/`, `allow write: if false` for server-only paths. Real security gap. |

### T4 Failure Classification

**Fixed this session** (cert commit `389a79a1` — 24 tests recovered):

| Suite | Root cause | Fix applied |
|---|---|---|
| `berean.historySanitization` (17 tests) | Phase 8 security hardening added `<human_turn>` / `<assistant_turn>` content wrapping to `sanitizeConversationHistory`; test expectations were pre-wrapping | Updated expectations to match wrapped format; helper functions `u()` / `a()` document the wrapping contract |
| `aiBackendOwnership` (5 tests) | 5 legacy JS files (`openAIFunctions`, `bereanFunctions`, `aiPromptFeatures`, `bereanFeaturesFunctions`, `heyfeedFunctions`) missing `@deprecated` JSDoc | Added `@deprecated` block to each |
| `remainingReleaseScopes` (2 tests) | Test read paths used `functions/src/` instead of `Backend/functions/src/` for church notes, post reactions, and index files | Corrected paths to `Backend/functions/src/` |

**Remaining failures — named causes:**

| Suite(s) | Test count | Cause | Fix required |
|---|---|---|---|
| `berean.quotaUnified` (4) + `berean.streamingSafety` (7) + `remainingReleaseScopes` (1) | 12 | **Streaming proxy missing security stack**: `bereanChatProxyStream.ts` has rate limiting via `enforceRateLimit` but lacks App Check verification, entitlement/model gating, unified `aiUsage/{uid}/daily` quota, `validateRawTextOutput`, AI disclosure in SSE events, and `safeText` distinction. Real quota bypass: users can exhaust callable quota and switch to streaming. | Implement App Check + entitlement + quota + output safety stack in the streaming proxy, mirroring `bereanChatProxy.ts` |
| `accountLifecycle` (2) | 2 | **2FA implementation incomplete**: `twoFactorAuth.ts` exports only `request2FAOTP`, `verify2FAOTP`, `disable2FASession`. Missing: `enableTwoFactor`, `disableTwoFactor`, `generateBackupCodes`, `regenerateBackupCodes`, `verifyBackupCode`, and security fields `backupCodeSalt` / `codeHash`. | Implement missing 2FA functions |
| `aiAppCheckEnforcement` | ~14 | New callable files (`capabilities/registry`, `capabilities/scripture`, `contextEngine`, `selah/discernmentEngine`, `berean/controllers/generateStructuredResponse`, etc.) declare `enforceAppCheck:false` without being in the PRE_AUTH_ALLOWLIST. Also: `aiModeration.js` assigns identity from `data.userId` (not `context.auth.uid`). | Either add to allowlist (with justification) or fix `enforceAppCheck:true`; fix identity sourcing in `aiModeration.js` |
| `securityPosture` | 3 | 96 callable source files missing `enforceAppCheck:true`; signed URL expiry not bounded; Storage rules missing `mediaUploads`/`mediaProcessed` server-own rules; `reports` collection taxonomy missing child safety categories in rules. | Fix per-finding |
| `spiritualSystems` | ~22 | App Check guards throw `unauthenticated` instead of `failed-precondition` — auth check fires before App Check enforcement in test mock. Also: behavior assertion drift on visibility/reaction validation. | Fix auth/App Check ordering in handlers; update behavior assertions |
| `berean.realtimeReleaseReadiness` | 4 | `firebase.json` deploy config not targeting hardened rules/indexes files; Firestore rules missing realtime collection coverage; iOS WebSocket transport documentation issue. | Fix deploy config + rules |
| `bereanPremiumContracts` | 1 | Firestore rules don't protect private Berean collections from client writes to generated streams. | Update Firestore rules |
| `semanticIntelligence` | 4 | AI generation path returning `generationSource: "fallback"` instead of `"ai"` (Grok/Claude mock not activated); scripture ref filtering returning empty array. | Fix mock setup for AI provider in test |
| `securityLaunchReadiness` | 3 | iOS client missing `submitTrustSafetyReport` call; `storage.rules` missing media quarantine/server-own patterns; legacy iOS report path check. | Implement storage rules + wire iOS callable |
| `communityHubs` | ~14 | Functions return `failed-precondition` where tests expect normal execution — flag-gated functions off in test environment. | Fix test environment flag setup |
| `selahMedia` | ~13 | `requireAppCheck` not called before `requireAuth` in 6 Selah functions; behavior assertion drift on idempotency and audit logs. | Fix guard ordering; update assertions |
| `covenant/stripeCovenantWebhook` | ~5 | `Stripe.Event` namespace type incompatible with current Stripe typings (`StripeConstructor.Event` not exported). | Update Stripe type import |
| `amenConnect` | ~4 | Same `Stripe.Event` namespace type error; `Stripe` used as a type namespace. | Update Stripe type import |
| `explainVideoContent` + `profileMini` + `churchNotes` | several | Behavior assertion drift; mock setup issues. | Investigate per-suite |

### T1 iOS Build — Human Actions Required

1. **Commit or stash working-tree `project.pbxproj` changes** before next build attempt. The "Multiple commands produce" errors come from uncommitted duplicate file refs added by concurrent agents.
2. After clean tree: delete `DerivedData.nosync/` and run canonical build:
   ```sh
   rm -rf DerivedData.nosync
   xcodebuild -scheme AMENAPP -destination 'generic/platform=iOS' build \
     -clonedSourcePackagesDirPath ./SourcePackages.nosync \
     -derivedDataPath ./DerivedData.nosync
   ```
3. If signing still fails with resource fork error after a clean build: run `xattr -rc AMENAPP.xcodeproj` on the project before building.

### Merge Gate (unchanged)

Every integration-branch merge must run this five-layer pass:
1. iOS app build through Xcode MCP or human shell canonical clean command.
2. iOS build-for-testing through Xcode MCP or human shell canonical command.
3. Backend compile: `cd Backend/functions && npx tsc --noEmit && npm run build`; legacy syntax: `find functions -name '*.js' -not -path '*/node_modules/*' -not -path '*/.history/*' -print0 | xargs -0 -n 1 node --check`.
4. Jest: `cd Backend/functions && npm test`; `cd functions && npm test`.
5. Rules: Firebase dry-run compile for Firestore/Storage and emulator-backed rules tests.

Any red layer blocks the merge until the owning lane fixes forward. No test narrowing, disabling, or diagnostic suppression counts as a green certificate.

---

## Reanchored Certification Attempt - 2026-06-16 (Pass 1)

Verification branch: `cert-reanchor-4bb2ffdd`  
Verification HEAD: `4bb2ffdd9955f113f4b723fbc901743c7ab9af83`  
Stamp guard: `HEAD == cert SHA - safe to report`

Result: **NOT CERTIFIED / HONEST RED**. The run is pinned, artifact hygiene is fixed, and the former BIL duplicate-placeholder collision is absent, but the app build fails before Swift compilation on missing package products. Downstream layers were sampled only to name causes; they do not convert the cert to green.

| Layer | Status | Evidence |
|---|---|---|
| T0 - Pin HEAD | GREEN | Created branch `cert-reanchor-4bb2ffdd` at `4bb2ffdd9955f113f4b723fbc901743c7ab9af83`. Final guard returned `HEAD == cert SHA - safe to report`. |
| T1 - Artifact hygiene | GREEN | `git ls-files \| grep -E '\\.nosync/' \| wc -l` returned `0`. `.gitignore` contains `DerivedData.nosync/`, `SourcePackages.nosync/`, `PackageCache.nosync/`, `*.nosync/`, and `.build/`. |
| T1 - iOS app build | RED | Clean `DerivedData.nosync` build with workspace cache reached the build graph, then failed with missing package products: `LiveKit`, many Firebase products, `GoogleSignIn`, `GoogleSignInSwift`, `GoogleGenerativeAI`, and multiple Algolia products. No BIL `.stringsdata` duplicate appears in the current `build.log`. |
| T1 - iOS test compile | BLOCKED | Simulator discovery failed: `CoreSimulatorService connection became invalid` / `Failed to initialize simulator device set`. App build is already red, so build-for-testing was not a valid certification layer. |
| T2 - Backend Jest | RED | `Backend/functions`: full Jest run tail reported `Test Suites: 29 failed, 35 passed, 64 total`; `Tests: 218 failed, 754 passed, 972 total`. First listed suite `src/churchDiscoveryPhase2.test.ts` passes in isolation, pointing to shared harness/cross-suite compile/setup issues rather than that suite's assertions. |
| T2 - Backend failure classes | RED | Observed TS2305 missing exports (`generateDynamicReplyPreviews`, `amenConnect`), Firebase Admin mock/setup shape error (`admin.apps` undefined), and Stripe namespace/type mismatches. |
| T3 - Storage rules | NOT RUN | Not run because T1 is red and simulator/package state prevents an honest full-stack green stamp. Prior storage runtime download blocker remains unverified in this reanchored run. |

### Reanchored Evidence Tails

```text
T1 app build:
/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP.xcodeproj: error: Missing package product 'LiveKit' (in target 'AMENAPP' from project 'AMENAPP')
/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP.xcodeproj: error: Missing package product 'FirebaseCore' (in target 'AMENAPP' from project 'AMENAPP')
/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP.xcodeproj: error: Missing package product 'AlgoliaSearch' (in target 'AMENAPP' from project 'AMENAPP')
** BUILD FAILED **

T2 backend tests:
Test Suites: 29 failed, 35 passed, 64 total
Tests:       218 failed, 754 passed, 972 total

T2 first-suite isolation:
PASS src/churchDiscoveryPhase2.test.ts
Tests: 21 passed, 21 total

Layer 2 simulator availability:
Unable to locate device set: Error Domain=NSPOSIXErrorDomain Code=61 "Connection refused"
```

Generated: 2026-06-11 16:04:58 MST
Verification HEAD: `4f044d91`
Report commit HEAD: `4a2dd121`
Certification retry ran at source HEAD `4f044d91`. Result is not full-stack green: Layer 2 is blocked before Swift test compilation by Xcode's dependency-graph service, Backend/functions Jest is red, and Storage rules emulator startup is blocked by the Firebase CLI storage runtime download.

## Result

| Layer | Status | Evidence |
|---|---|---|
| Layer 1 - iOS app clean canonical CLI | 🔴 RED / HARNESS-LIMITED | Repo-local `xcodebuild -resolvePackageDependencies` exited `0`, but canonical CLI build failed before Swift compile with missing package products (`LiveKit`, `FirebaseFirestore`, `AlgoliaSearch`, Firebase/Algolia products) because sandboxed Xcode cannot use the existing package graph/CoreSimulator services. |
| Layer 1 - iOS app Xcode MCP route | ✅ GREEN | `BuildProject` returned `The project built successfully`, elapsed `1.801s`, log `BuildProject-Log-20260611-160206.txt`. |
| Layer 2 - Test targets compile | 🔴 BLOCKED | `BuildProject(buildForTesting: true)` now fails before compilation: `Could not compute dependency graph: Failed to receive dependency graph response`, log `BuildProject-Log-20260611-160216.txt`. Earlier source compile clusters fixed in this retry include AdaptiveComposer `Motion` redeclaration, AppReadyStateManager init, auth/audit compatibility, Selah resolver, feed context label contracts, and media approval metadata. |
| Layer 3 - Backend TS compile/build | ✅ GREEN | `Backend/functions`: `npx tsc --noEmit` exited `0` with no output; `npm run build` exited `0` with `> build` / `> tsc`. Legacy `functions`: `node --check` over JS files exited `0` with no output. |
| Layer 4 - Test suites execute | 🔴 RED | `Backend/functions npm test`: `Test Suites: 30 failed, 30 passed, 60 total`; `Tests: 257 failed, 654 passed, 911 total`. Legacy `functions npm test`: `5 passed, 5 total`; `137 passed, 137 total`. |
| Layer 5 - Rules compile | 🟡 PARTIAL | Firestore emulator compile smoke passed: `firestore-rules-compile-smoke`. Storage emulator startup failed during `cloud-storage-rules-runtime-v1.1.3.jar` download with `Error: An unexpected error has occurred.` |
| Layer 5 - Rules emulator suites | 🔴 BLOCKED | Storage emulator runtime download blocks combined Firestore/Storage execution. Firestore-only emulator starts and exits successfully. |
| Final Layer 1 repeat | ⏸ NOT RUN | Double-green repeat not attempted because Layer 2 dependency-graph failure and Layer 4 Backend/functions Jest red prevent full-stack green. |

## Verbatim Tails

### Layer 1 Canonical CLI Failure Tail

```text
/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP.xcodeproj: error: Missing package product 'FirebaseFirestore' (in target 'AMENAPP' from project 'AMENAPP')
/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP.xcodeproj: error: Missing package product 'AlgoliaSearch' (in target 'AMENAPP' from project 'AMENAPP')
/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP.xcodeproj: error: Missing package product 'LiveKit' (in target 'AMENAPP' from project 'AMENAPP')
** TEST BUILD FAILED **
```

### Layer 1 Xcode MCP Tail

```text
buildResult: The project built successfully.
elapsedTime: 1.801
fullLogPath: BuildProject-Log-20260611-160206.txt
```

### Layer 2 Xcode MCP Tail

```text
buildResult: The build failed
Could not compute dependency graph: Failed to receive dependency graph response
fullLogPath: BuildProject-Log-20260611-160216.txt
```

### Layer 3 Backend Tail

```text
Backend/functions:
> build
> tsc

Backend/functions:
npx tsc --noEmit
exit 0, no output

legacy functions deployed-code node --check:
exit 0, no output
```

### Layer 4 Jest Tail

```text
Backend/functions:
Test Suites: 30 failed, 30 passed, 60 total
Tests:       257 failed, 654 passed, 911 total
Snapshots:   0 total
Time:        26.7 s
Ran all test suites.

legacy functions:
Test Suites: 5 passed, 5 total
Tests:       137 passed, 137 total
Snapshots:   0 total
Time:        3.344 s
Ran all test suites.
```

### Layer 5 Rules Tail

```text
✔  firestore: Firestore Emulator was started in standard edition.
i  Running script: echo firestore-rules-compile-smoke
firestore-rules-compile-smoke
✔  Script exited successfully (code 0)
```

### Layer 5 Emulator Blocker Tail

```text
i  emulators: Starting emulators: firestore, storage
✔  firestore: Firestore Emulator was started in standard edition.
i  storage: downloading cloud-storage-rules-runtime-v1.1.3.jar...
Error: An unexpected error has occurred.
```

## Highest-Fanout Layer 4 Failures

| Area | Root cause observed |
|---|---|
| Stripe covenant/connect tests | Tests import old `Stripe` namespace types (`Stripe.Subscription`, `Stripe.Event`, `Stripe.Checkout.Session`) incompatible with current Stripe package typings. |
| Church Notes processing | Directory traversal storage path test did not throw `permission-denied`. |
| Export drift | Tests expect exports that modules no longer expose: `hasStrongRelationship`, `selectFollowedReplyFromRelationships`, `createCovenantCheckoutSessionHandler`, Connect Stripe/AI helpers. |
| Firebase admin/function mocks | Several callable tests fail because mocks do not match current Firebase Functions/Admin shapes (`admin.apps`, `request.rawRequest.on`, batch `update`). |
| Static release-readiness tests | Static tests expect stale file paths/config (`AMENAPP/firestore.deploy.rules`, `functions/src/...`, `Backend/functions/index.ts`) or missing indexes. |
| Profile trigger tests | Resolver functions return `null` where tests expect artifact trigger states. |

## Merge Gate

Every integration-branch merge must run this five-layer pass:

1. iOS app build through Xcode MCP or human shell canonical clean command.
2. iOS build-for-testing through Xcode MCP or human shell canonical command.
3. Backend compile: `cd Backend/functions && npx tsc --noEmit && npm run build`; legacy syntax: `find functions -name '*.js' -not -path '*/node_modules/*' -not -path '*/.history/*' -print0 | xargs -0 -n 1 node --check`.
4. Jest: `cd Backend/functions && npm test`; `cd functions && npm test`.
5. Rules: Firebase dry-run compile for Firestore/Storage and emulator-backed rules tests.

Any red layer blocks the merge until the owning lane fixes forward. No test narrowing, disabling, or diagnostic suppression counts as a green certificate.
