# Settings Safety Train Build Request

## Scope
R1/R2 safe wiring scaffold for the Settings/Safety release train.

## Changed files
- `AMENAPP/AMENAPP/AMENSettingsSystem.swift`
- `AMENAPP/AMENAPP/AMENAPP/Features/Settings/Shell/SettingsSafetyReleaseTrainView.swift`
- `AMENAPP/AMENAPP/AMENAPP/Features/Settings/ACCEPTANCE.md`
- `AMENAPP/AMENAPP/AMENAPP/Features/Settings/BUILD_REQUEST.md`

## What is wired
- Added a reachable `Settings Safety Train` row to the existing `AMENSettingsView` section list.
- Added `SettingsSafetyReleaseTrainView` as the destination for the new section.
- Added a release-train hub listing every Settings/Safety surface from the spec.
- Every new surface is visible but safe: flags default off, callable dependencies are named, and live actions stay disabled until deploy/rules/audit gates pass.
- Added `ACCEPTANCE.md` with honest `blocked` / `stubbed` / `wired` states for R0-R6 and launch gates.

## Verification performed
- `XcodeRefreshCodeIssuesInFile` on `SettingsSafetyReleaseTrainView.swift`: no issues.
- `XcodeRefreshCodeIssuesInFile` on `AMENSettingsSystem.swift`: no issues.
- `XcodeRefreshCodeIssuesInFile` on `SettingsComponentContracts.swift`: SourceEditor diagnostic retrieval still fails with error 5.
- `BuildProject`: failed before compilation with `Could not compute dependency graph: Failed to receive dependency graph response`.

## Remaining blockers
- Human/canonical build must pass before ratifying/freeze.
- Lane A-G live implementations are still not done; this patch only wires safe route visibility and status scaffolding.
- `TODO(dependency:)` remains by design until Lane G callables are implemented and human-deployed per function.
- Launch gates in `ACCEPTANCE.md` remain blocked until human/legal/security verification.

## No deploys
No Firebase functions, Firestore rules, or backend deploys were changed or run.
