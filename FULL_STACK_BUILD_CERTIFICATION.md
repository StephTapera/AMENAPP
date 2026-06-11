# FULL-STACK BUILD CERTIFICATION

Generated: 2026-06-11 10:55:42 MST
Report write HEAD: `b2974e08`
Certification started while HEAD was `9956e02a`; HEAD advanced through `d3b6434e` to `b2974e08` while the run was in progress. Result is therefore not a stable current-HEAD green certificate.

## Result

| Layer | Status | Evidence |
|---|---|---|
| Layer 1 - iOS app clean canonical CLI | 🔴 RED / HARNESS-LIMITED | `xcodebuild -resolvePackageDependencies` completed with `resolved source packages:`. Canonical CLI build then failed before Swift compile with missing package products after CoreSimulator service failures: `Missing package product 'LiveKit'`, `Missing package product 'FirebaseFirestore'`, `Missing package product 'AlgoliaSearch'`, and related package products. |
| Layer 1 - iOS app Xcode MCP route | ✅ GREEN | `BuildProject` succeeded, elapsed `46.903s`, log `BuildProject-Log-20260611-104121.txt`. |
| Layer 2 - Test targets compile | ✅ GREEN | `BuildProject(buildForTesting: true)` first returned dependency-graph failure, retry timed out at MCP layer but continued in Xcode; `GetBuildLog` final result: `The build succeeded`, log `26C7F080-BF20-4939-BB82-FF49B0536392.txt`. |
| Layer 3 - Backend TS compile/build | ✅ GREEN | `Backend/functions`: `npx tsc --noEmit` exited `0` with no output; `npm run build` exited `0` with `> build` / `> tsc`. Legacy `functions`: corrected deployed-code syntax sweep excluding all `node_modules` and `.history` paths exited `0` with no output. |
| Layer 4 - Test suites execute | 🔴 RED | `Backend/functions npm test`: `Test Suites: 30 failed, 30 passed, 60 total`; `Tests: 257 failed, 654 passed, 911 total`. Legacy `functions npm test`: `5 passed, 5 total`; `137 passed, 137 total`. |
| Layer 5 - Rules compile | ✅ GREEN | `XDG_CONFIG_HOME=/tmp/firebase-config firebase deploy --only firestore:rules,storage --project amen-5e359 --dry-run` returned `storage.rules compiled successfully`, `firestore.rules compiled successfully`, `Dry run complete!`. |
| Layer 5 - Rules emulator suites | 🔴 BLOCKED | Direct `Backend/rules-tests npm test` failed because emulators were not running. `firebase emulators:exec --only firestore,database,storage "cd Backend/rules-tests && npm test"` started Firestore and Database, then stalled while starting/downloading Storage runtime; process was terminated after no progress. |
| Final Layer 1 repeat | 🔴 CANCELLED | Final `BuildProject` repeat was cancelled externally after `88.108s`; MCP message: `The build was cancelled. This most likely happened because of a user interaction.` |

## Verbatim Tails

### Layer 1 Canonical CLI Failure Tail

```text
/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP.xcodeproj: error: Missing package product 'LiveKit' (in target 'AMENAPP' from project 'AMENAPP')
/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP.xcodeproj: error: Missing package product 'FirebaseFirestore' (in target 'AMENAPP' from project 'AMENAPP')
/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP.xcodeproj: error: Missing package product 'AlgoliaSearch' (in target 'AMENAPP' from project 'AMENAPP')
warning: duplicate output file '/Users/stephtapera/Desktop/AMEN/AMENAPP copy/DerivedData.nosync/Build/Products/Debug-iphonesimulator/AMENAPP.app/CONTRACTS.md' on task: CpResource /Users/stephtapera/Desktop/AMEN/AMENAPP copy/DerivedData.nosync/Build/Products/Debug-iphonesimulator/AMENAPP.app/CONTRACTS.md /Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/Shared/Contracts/CONTRACTS.md (in target 'AMENAPP' from project 'AMENAPP')
** BUILD FAILED **
```

### Layer 2 Xcode MCP Tail

```text
buildResult: The build succeeded
Link AMENAPP.debug.dylib (arm64)
Link AMENAPP (arm64)
Link AMENWidgetExtensionExtension.debug.dylib (arm64)
Link AMENWidgetExtensionExtension (arm64)
Link AMENNotificationServiceExtension.debug.dylib (arm64)
Link AMENNotificationServiceExtension (arm64)
```

### Layer 3 Backend Tail

```text
Backend/functions:
> build
> tsc

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
✔  firebase.storage: rules file storage.rules compiled successfully
✔  cloud.firestore: rules file firestore.rules compiled successfully

✔  Dry run complete!
```

### Layer 5 Emulator Blocker Tail

```text
Firebase emulator is not running.
Could not reach 127.0.0.1 on port(s): 8080, 9000, 9199.

firebase emulators:exec:
i  emulators: Starting emulators: firestore, database, storage
✔  firestore: Firestore Emulator was started in standard edition.
i  database: Database Emulator logging to database-debug.log
i  storage: downloading cloud-storage-rules-runtime-v1.1.3.jar...
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
