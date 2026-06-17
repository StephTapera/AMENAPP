# FULL-STACK BUILD CERTIFICATION

## Reanchored Certification Attempt - 2026-06-16

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
