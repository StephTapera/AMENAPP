# DEPLOY PACKAGE — SAFETY WAVE 3

Production freeze: this package is for human review only. Nothing was deployed.

## Scope

| Area | Files | Status |
|---|---|---|
| Canonical age-tier vocabulary | `functions/ageTier.js`, `functions/authHelpersV1.js`, `functions/authenticationHelpers.js`, `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyModels.swift` | Prepared |
| Client age verification | `AMENAPP/AgeVerificationOnboardingView.swift` | Prepared |
| Minor search exclusion | `AMENAPP/AlgoliaSyncService.swift` | Prepared |
| CSAM fail-loud path | `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift`, `firestore.rules` | Prepared |
| Firestore immutable legal/reporting collections | `firestore.rules` | Prepared |
| Storage quarantine/MIME/org media controls | `storage.rules`, `firebase.json` | Prepared |
| NCMEC queue SLA/dark flag | `functions/ncmecReporter.js` | Prepared |
| Contract tests | `functions/test/ageTier.test.js`, `AMENAPP/AMENAPPTests/SafetyWave3AgeTierTests.swift` | Prepared |

## Human Review Required

| Item | Decision |
|---|---|
| Current deployed Storage ruleset | HUMAN-PENDING: verify in Firebase Console, or resolve by deploying this reviewed W3 storage package. This harness can compile local rules but cannot prove the live console ruleset. |
| NCMEC CyberTipline HTTP submission | Keep disabled until NCMEC ESP registration, CyberTipline API credentials, and counsel-approved procedure are complete. |
| Existing minor Algolia records | Run a one-time migration that reads `users` and deletes `blocked`/`tierB`/`tierC`, `isMinor == true`, or `minorScoped == true` records from the people index. |
| Existing media in serving paths | Grandfather existing media, then run a sweep to classify/promote/quarantine before enforcing any destructive cleanup. |

## Verification

| Check | Result |
|---|---|
| `npm --prefix functions test -- --runTestsByPath test/ageTier.test.js` | PASS: 11/11 |
| Xcode diagnostics: `AgeVerificationOnboardingView.swift` | PASS: no issues |
| Xcode diagnostics: `AmenChildSafetyModels.swift` | PASS: no issues |
| Xcode navigator errors before focused Swift test | PASS after stale issue sweep: no current navigator errors |
| CLI focused Swift tests | BLOCKED by harness simulator wall: `CoreSimulatorService connection became invalid`, `simdiskimaged` unavailable, command interrupted after hang |
| Firebase dry run: `firestore.rules`, `storage.rules` | Rules compiled successfully; CLI exited nonzero after dry run due Firebase update-check config-store permission |

## Deploy Command For Human

Review this package against the currently live ruleset first, then deploy only the reviewed surfaces:

```sh
npx firebase deploy --only firestore:rules,storage,functions:onCSAMDetected,functions:flagForNCMECReview,functions:onModerationRequiresMandatoryReport,functions:updateBirthYear --project amen-5e359
```

Do not set `NCMEC_SUBMISSION_ENABLED=true` until the decision items above are complete.
