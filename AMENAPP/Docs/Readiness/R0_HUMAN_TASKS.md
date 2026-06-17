# R0 — Human Unlock Checklist
## Estimated: ~30 min | Gate: everything downstream queues here

### ✅ Task 1: Exclude BIL Stubs from Xcode Target (~5 min)
**In Xcode (not terminal):**

> **Current status:** As of 2026-06-16, none of the BIL Swift files appear in the `project.pbxproj` — they are on disk but invisible to the build system. However, stale DerivedData artifacts from a previous build exist. Perform a clean before the canonical build (Task 2). If Xcode re-surfaces any of the files below in a future merge, use File Inspector to exclude them.

The 7 BIL stub files on disk (currently not in any Xcode target, but verify after any merge):

- `AMENAPP/BereanOS/BILWaveOneModels.swift`
  - Select file in Project Navigator → File Inspector (right panel) → uncheck **AMENAPP** target checkbox
- `AMENAPP/BereanOS/BILWaveOneHubView.swift`
  - Select file in Project Navigator → File Inspector → uncheck **AMENAPP** target checkbox
- `AMENAPP/BereanOS/BILCompactorView.swift`
  - Select file in Project Navigator → File Inspector → uncheck **AMENAPP** target checkbox
- `AMENAPP/BereanOS/BILLedgerView.swift`
  - Select file in Project Navigator → File Inspector → uncheck **AMENAPP** target checkbox
- `AMENAPP/BereanOS/BILBranchingView.swift`
  - Select file in Project Navigator → File Inspector → uncheck **AMENAPP** target checkbox
- `AMENAPP/BereanOS/BILSourceCardsView.swift`
  - Select file in Project Navigator → File Inspector → uncheck **AMENAPP** target checkbox
- `AMENAPP/BereanOS/BILContextPackagesView.swift`
  - Select file in Project Navigator → File Inspector → uncheck **AMENAPP** target checkbox

Then clear stale DerivedData: **Product → Clean Build Folder** in Xcode (or `rm -rf DerivedData.nosync` from repo root).

### ✅ Task 2: Verify Canonical Build (~10 min)
```sh
xcodebuild -scheme AMENAPP -destination 'generic/platform=iOS' build \
  -clonedSourcePackagesDirPath ./SourcePackages.nosync \
  -derivedDataPath ./DerivedData.nosync
```
On GREEN → record SHA: ___________  
On RED → paste errors to #dev-triage, do not proceed

### ✅ Task 3: Deploy Security Fixes (~5 min)
**From repo root only. Targeted deploys — no quota cost.**
```sh
mkdir -p deploy-logs
firebase deploy --only functions:default:moderatePost 2>&1 | tee deploy-logs/csam-c1c2-$(date +%Y%m%d).txt
firebase deploy --only functions:default:moderateUGC 2>&1 | tee -a deploy-logs/csam-c1c2-$(date +%Y%m%d).txt
firebase deploy --only functions:default:moderateContent 2>&1 | tee deploy-logs/c3-$(date +%Y%m%d).txt
firebase deploy --only functions:creator:accountSubscriptionFunctions 2>&1 | tee deploy-logs/c4-$(date +%Y%m%d).txt
```
Verify each deploy exits 0.

Fixes being deployed:
- **C1:** Broken `escalateChildSafety` import (`moderatePost.js` / `TrustCenterAuditLogStore.swift`)
- **C2:** CSAM vision gate on admin review + UGC paths
- **C2b:** CSAM vision gate on image-only DMs
- **C3:** `index.js` double-export of `moderateContent`
- **C4:** Subscription tier trusting unverified `transactionId` (`accountSubscriptionFunctions.js`)

### ✅ Task 4: File GCP Quota Increase (~5 min)
1. Go to GCP Console → Cloud Run → Quotas
2. Request increase for us-central1 "Maximum number of services" from 1000 → 1500
3. Note ticket number here: ___________

### ✅ Task 5: NCMEC ESP Registration (~5 min today, weeks to complete)
- Email: esp@ncmec.org
- Subject: ESP Registration — AMEN App (iOS)
- Confirm with counsel that 18 U.S.C. § 2258A reporting obligation acknowledged
- Note contact date here: ___________

## Done Signal
All 5 tasks complete → post verified SHA to dev channel → 5 waiting workflows resume.
