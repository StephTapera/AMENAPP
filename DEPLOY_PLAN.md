# Deploy Plan — Human-Triggered Runbook
Generated: 2026-06-16 | Branch: app-store-readiness-overnight

> NEVER run `firebase deploy` without a specific `--only` target. Bare `firebase deploy` triggers orphan deletion prompts and redeploys all functions.
> NEVER run firebase commands from a subdirectory (`cd functions && firebase deploy`).
> ALWAYS deploy from repo root.
> us-central1 is at ~999-1000/1000 Cloud Run services. ALL new functions must deploy to us-east1.
> Add every new function to the Interim Region Table in `docs/FUNCTION_INVENTORY.md`.

---

## Pre-Deploy Checklist

Run these steps before ANY deploy:

```bash
# 1. Confirm you are in the repo root, not a subdirectory
pwd
# Expected: /Users/stephtapera/Desktop/AMEN/AMENAPP copy

# 2. Confirm correct project alias
firebase use --list
# Confirm amen-5e359 is active

# 3. Confirm you are NOT on main
git branch --show-current
# Must NOT be main or master

# 4. Backup current rules before any rules deploy
cp firestore.rules "firestore.rules.backup.$(date +%Y%m%d%H%M)"
cp storage.rules "storage.rules.backup.$(date +%Y%m%d%H%M)"

# 5. Confirm us-central1 quota before deploying any new function
gcloud run services list --region us-central1 | wc -l
# If >= 950, deploy to us-east1 (current: ~999, effectively full)

# 6. Confirm node modules are installed in both function directories
ls Backend/functions/node_modules/.bin/tsc && echo "Backend/functions deps OK"
ls functions/node_modules/.bin/tsc && echo "functions deps OK"

# 7. Type-check both codebases before deploying
cd Backend/functions && npx tsc --noEmit && cd ../..
cd functions && npx tsc --noEmit && cd ..
```

---

## Group 1 — Safety and Moderation (P0 — Deploy First)

These functions must be live before any public user-facing traffic.

```bash
# Fix FIRE-010: createSpaceTier space-owner authorization gap
# Edit functions/src/spaces/callable.ts to add space-owner check before deploying
firebase deploy --only functions:default:createSpaceTier --project amen-5e359

# Safety reporting pipeline
firebase deploy --only functions:creator:bereanConstitutionalReview --project amen-5e359
firebase deploy --only functions:creator:accountSuspension_suspend --project amen-5e359
firebase deploy --only functions:creator:accountSuspension_restore --project amen-5e359
```

**Smoke test after Group 1:**
```bash
# Verify createSpaceTier now rejects non-owners
# (requires a test user and a space not owned by that user)
curl -X POST "https://us-east1-amen-5e359.cloudfunctions.net/createSpaceTier" \
  -H "Content-Type: application/json" \
  -d '{"data": {"spaceId": "test-space-123", "tierName": "Premium", "price": 9.99}}'
# Expected: permission-denied error (not a 200)
```

---

## Group 2 — Auth and Account Deletion (P0)

```bash
# These are backend validators for the account deletion pipeline.
# Confirm the 30-day purge scheduled job exists before enabling soft-delete flows.
# See AUTH-013 in HUMAN_GATE_QUEUE.md.

# If scheduled purge job needs to be deployed:
firebase deploy --only functions:creator:scheduledAccountPurge --project amen-5e359
# (If this function does not exist, implement it first per AUTH-013 decision brief)

# Account management callables
firebase deploy --only functions:creator:socialGraph_follow --project amen-5e359
firebase deploy --only functions:creator:socialGraph_unfollow --project amen-5e359
```

**Smoke test after Group 2:**
```bash
# Verify soft-delete writes deletionScheduledFor field
# (requires a test account and Firebase console inspection)
# Check Firestore: /users/{testUid} should have deletedAt and deletionScheduledFor fields after soft-delete
```

---

## Group 3 — Posts, Comments, and Feed

```bash
# Context engine callables (with App Check enforcement confirmed)
firebase deploy --only functions:default:contextEngine_getGrants --project amen-5e359
firebase deploy --only functions:default:contextEngine_getAuditLog --project amen-5e359
firebase deploy --only functions:default:capabilityRegistry_list --project amen-5e359

# Daily verse
firebase deploy --only functions:default:dailyVerse_fetch --project amen-5e359
```

**Smoke test after Group 3:**
```bash
# Verify capabilityRegistry_list returns expected capabilities for an authenticated user
# (use Firebase Functions shell or a test harness)
```

---

## Group 4 — Messaging and Notifications

```bash
# Visit verification
firebase deploy --only functions:default:visitVerification_confirm --project amen-5e359

# Note Give (charitable giving bridge)
firebase deploy --only functions:default:noteGive_process --project amen-5e359
```

---

## Group 5 — AI and Berean

```bash
# Berean AI callables
firebase deploy --only functions:creator:bereanChat --project amen-5e359
firebase deploy --only functions:creator:bereanSuggest --project amen-5e359

# Berean Island and sermon companion
firebase deploy --only functions:default:bereanIsland_trigger --project amen-5e359
firebase deploy --only functions:default:writeWithBerean_assist --project amen-5e359
firebase deploy --only functions:default:sermonCompanion_session --project amen-5e359

# After deploying: add rate limiting to these callables per FIRE-016
# Edit functions/src/ to import rateLimit.ts, then redeploy
```

**Smoke test after Group 5:**
```bash
# Verify bereanChat returns a valid response for an authenticated user
# Verify bereanIsland_trigger rejects unauthenticated requests
```

---

## Group 6 — Church Discovery, Scripture, and Resources

```bash
# Scripture callables (add rate limiting per FIRE-016 before deploying to production)
firebase deploy --only functions:default:scripture_detectReferences --project amen-5e359
firebase deploy --only functions:default:scripture_searchVerses --project amen-5e359
firebase deploy --only functions:default:scripture_getVerses --project amen-5e359
```

**Smoke test after Group 6:**
```bash
# Verify scripture_searchVerses returns results for "John 3:16"
# Verify scripture_searchVerses rate-limits after 10 calls/minute (after FIRE-016 fix)
```

---

## Group 7 — New Undeployed Functions (from this branch's git status)

**PREREQUISITE:** Rename `Backend/functions/src/selahConnection 2.ts` to a name without a space before deploying.

```bash
# Catalog and AI catalog functions
firebase deploy --only functions:creator:affiliateTierHelper --project amen-5e359
firebase deploy --only functions:creator:askCreatorQuery --project amen-5e359
firebase deploy --only functions:creator:topicClusterEngine --project amen-5e359

# Ingestion providers
firebase deploy --only functions:creator:manualEntry --project amen-5e359
firebase deploy --only functions:creator:googleBooksProvider --project amen-5e359
firebase deploy --only functions:creator:substackMediumProvider --project amen-5e359
firebase deploy --only functions:creator:youtubeProvider --project amen-5e359

# Search
firebase deploy --only functions:creator:catalogSearch --project amen-5e359
```

**Region requirement:** All of the above must deploy to us-east1. Add each to `docs/FUNCTION_INVENTORY.md` Interim Region Table immediately after deployment.

---

## Group 8 — Prayer OS

```bash
firebase deploy --only functions:default:prayerOS_createCard --project amen-5e359
firebase deploy --only functions:default:prayerOS_listCards --project amen-5e359
firebase deploy --only functions:default:prayerOS_updateCard --project amen-5e359
firebase deploy --only functions:default:prayerOS_deleteCard --project amen-5e359
firebase deploy --only functions:creator:prayer_createCard --project amen-5e359
firebase deploy --only functions:creator:prayer_listCards --project amen-5e359
firebase deploy --only functions:creator:prayer_updateCard --project amen-5e359
```

---

## Rules Deploy (After All Functions)

Deploy rules only after all function deploys succeed:

```bash
# From repo root only
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"

# Backup rules first
cp firestore.rules "firestore.rules.backup.$(date +%Y%m%d%H%M)"
cp storage.rules "storage.rules.backup.$(date +%Y%m%d%H%M)"

# Apply pending fixes before deploying (see FIREBASE_RULES_AND_FUNCTIONS.md):
# 1. Remove duplicate /safetyAuditLog block at ~line 3195 (FIRE-008)
# 2. Replace deprecated MIME helpers on churchNotes paths (FIRE-022)
# 3. Decide on /testimonies unauthenticated read (FIRE-009)
# 4. Decide on uploads/approved public read (FIRE-020)

# Deploy Firestore rules
firebase deploy --only firestore:rules --project amen-5e359

# Deploy Storage rules
firebase deploy --only storage --project amen-5e359
```

**Verification after rules deploy:**
```bash
# Test that a known-working read still works (e.g., reading own user document)
# Test that a known-blocked read is still blocked (e.g., reading /ncmecReports)
# Test that the safetyAuditLog client create allowlist still works
```

---

## iOS Build Readiness Checks (Not Deploys)

Before archiving for App Store:

```bash
# 1. Add missing Info.plist usage description strings (PRIV-001)
# Edit AMENAPP/AMENAPP/Info.plist to add:
# NSMicrophoneUsageDescription
# NSPhotoLibraryUsageDescription
# NSLocationWhenInUseUsageDescription

# 2. Add ITSAppUsesNonExemptEncryption to Info.plist (SEC-006)
# Value: false (if only standard TLS) or true (if E2EE counts as non-exempt)

# 3. Verify the canonical build command succeeds
xcodebuild \
  -workspace "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPP.xcworkspace" \
  -scheme AMENAPP \
  -destination 'generic/platform=iOS' \
  -clonedSourcePackagesDirPath "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/SourcePackages.nosync" \
  -derivedDataPath "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/DerivedData.nosync" \
  build
```

---

## Remote Config Flags — Final State

The following flags must be verified in the Firebase Remote Config console before releasing to users. All should be `false` until the corresponding feature is fully deployed and tested:

| Flag | Current State (per prior audit) | Should be for App Store submission |
|---|---|---|
| amen_pulse_enabled | false | false until pulse backend deployed |
| berean_island_enabled | false | false until Wave 0 human verifications complete |
| capabilities_core_enabled | false | true — capabilities are deployed |
| prayer_os_v2_enabled | false | false until prayer encryption (FIRE-023) addressed |
| spaces_paywall_enabled | false | false until BTN-001 fix verified |
| csam_hash_scan_enabled | false | false until NCMEC registration complete |
| guardian_portal_enabled | false | false until OPEN-2 resolved with T&S Lead |

---

## Emergency Rollback Procedure

If a deploy introduces a production regression:

```bash
# List recent deploy history
firebase functions:log --project amen-5e359 --limit 50

# Roll back a single function to previous version
# (Firebase does not have a one-click rollback; you must redeploy the previous source)
git log --oneline | head -10  # Find the last known-good commit SHA
git checkout <SHA> -- functions/src/spaces/callable.ts  # Restore specific file
firebase deploy --only functions:default:createSpaceTier --project amen-5e359

# Roll back Firestore rules
cp firestore.rules.backup.YYYYMMDDHHII firestore.rules
firebase deploy --only firestore:rules --project amen-5e359

# Roll back Storage rules
cp storage.rules.backup.YYYYMMDDHHII storage.rules
firebase deploy --only storage --project amen-5e359
```
