# AMEN Distinctives Blocked Tasks

## Wave 1 Function Deployment - Blocked

Task: deploy new AMEN Distinctives Cloud Functions to Firebase project `amen-5e359`, region `us-central1`.

Status: blocked on 2026-06-13 by Google Cloud quota, not by TypeScript compilation.

Attempts:

1. Targeted deploy for all new creator codebase functions:
   `firebase deploy --only functions:creator:resurfacePrayers,functions:creator:resurfacePrayersScheduled,functions:creator:groundClaim,functions:creator:inviteWitness,functions:creator:acceptCovenant,functions:creator:witnessCheckIn,functions:creator:publishLiturgicalContext,functions:creator:liturgicalContextProvider,functions:creator:generateDailyOffice,functions:creator:generateDailyOfficeScheduled --project amen-5e359`

   Result: source uploaded successfully, then Cloud Functions v2 creation returned HTTP 429 quota errors for at least `resurfacePrayers`, `groundClaim`, and `generateDailyOffice`. CLI exited nonzero after Firebase tools update-check failure.

2. Verification command:
   `firebase functions:list --project amen-5e359 | grep -E 'resurfacePrayers|groundClaim|inviteWitness|acceptCovenant|witnessCheckIn|Liturgical|liturgicalContext|generateDailyOffice'`

   Result: no function list returned; CLI exited nonzero after Firebase tools update-check failure.

3. Narrow deploy for one lightweight callable:
   `firebase deploy --only functions:creator:liturgicalContextProvider --project amen-5e359`

   Result: source uploaded successfully, then Cloud Functions v2 creation returned HTTP 429: `Could not create Cloud Run service liturgicalcontextprovider. Operation failed due to insufficient quota.` CLI exited nonzero after Firebase tools update-check failure.

Diagnostics:

- `npm --prefix Backend/functions run build` passed before deploy.
- `npm --prefix Backend/functions test -- distinctives.static.test.ts` passed.
- The deployment blocker is project quota for new Cloud Run backed 2nd gen functions.
- Firebase CLI also reports local update-check config write failure at `/Users/stephtapera/.config`, but the quota error is the substantive deployment blocker.

Next required action:

- Increase Cloud Run / Cloud Functions v2 quota for project `amen-5e359` in `us-central1`, or consolidate these endpoints into an existing deployed function/service before redeploying.

## Wave 3 Test Target Gate - Blocked

Task: run full Xcode test suite after SwiftUI integration.

Status: blocked on 2026-06-13 by pre-existing test target file references, not by the new distinctives Swift files.

Attempts:

1. `RunAllTests`
   Result: failed during test build. Initial error was in `AmenDistinctives.swift` at line 640 (`ShapeStyle` had no member `accent`). Fixed.

2. `RunAllTests`
   Result: failed during test build after the Swift fix. Build log reports missing test input files:
   `/Users/stephtapera/Desktop/AMENAPP/AMENAPP/Resources/ResourcesContentView.swift`,
   `/Users/stephtapera/Desktop/AMENAPP/AMENAPP/CommunityOS/Privacy/AmenAudienceSimulatorView.swift`,
   `/Users/stephtapera/Desktop/AMENAPP/AMENAPP/CommunityOS/Privacy/AmenPrivacyPresetView.swift`,
   `/Users/stephtapera/Desktop/AMENAPP/AMENAPP/CommunityOS/Privacy/AmenPrivacyEngine.swift`,
   `/Users/stephtapera/Desktop/AMENAPP/AMENAPP/CommunityOS/Privacy/AmenPrivacyModels.swift`.

Diagnostics:

- `BuildProject` for the app target succeeded after the Swift fix.
- The remaining test gate failure is the `AMENAPPTests` target referencing files at a different root (`/Users/stephtapera/Desktop/AMENAPP/...`) than the active workspace (`/Users/stephtapera/Desktop/AMEN/AMENAPP copy/...`).

Next required action:

- Repair the `AMENAPPTests` target file references or remove stale test compile inputs, then rerun the full suite.
