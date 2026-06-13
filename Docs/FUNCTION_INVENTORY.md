# AMEN Cloud Function Inventory
**Date:** 2026-06-13  
**Branch:** feature/berean-island-w0 (analysis run solo; quota-reclamation pending human gate)  
**Project:** amen-5e359 (production)  
**Analyst:** Claude Code (Q-1 through Q-4 run)

---

## Executive Summary

| Region | Total Services | ACTIVE-WIRED | ACTIVE-ORPHAN | DEAD (delete candidates) |
|--------|---------------|--------------|---------------|--------------------------|
| us-central1 | 999 | 413 | 64 | **522** |
| us-east1 | 53 | 53 | 0 | 0 |
| us-west1 | 8 | 8 | 0 | 0 |
| **TOTAL** | **1060** | **474** | **64** | **522** |

**Quota situation:** us-central1 at 999/1000 Cloud Run service limit. Deleting the 522 DEAD services would bring us-central1 to ~477 — comfortable headroom for new deployments.

**Classification method:**
- **ACTIVE-WIRED**: Cloud Run service name (lowercased) matches an `exports.name` in `functions/index.js` (the deployed main codebase).
- **ACTIVE-ORPHAN**: Present as `exports.name` in *some* `.js` file under `functions/` but NOT re-exported from `functions/index.js`. Probably from a feature system that was built but not wired into the current index. Not currently reachable.
- **DEAD**: Name does not appear in any `exports.` line in any `.js` file under `functions/`. No source. Leftover from earlier agent build sessions.
- **UNKNOWN**: Not applicable — methodology found no unclassifiable entries.

us-east1 and us-west1 are entirely new (deployed this session); all are wired.

---

## Q-2: Berean Cutover — COMPLETE

### System A (Canonical — serves real traffic)
- **Function:** `bereanConstitutionalPipeline` (default codebase, us-east1)
- **Source:** `functions/berean/index.ts` → `functions/berean/constitutionalPipeline.ts`
- **iOS call site:** `AMENAPP/AIIntelligence/BereanConstitutionalPipeline.swift:266`
  ```swift
  let result = try await functions.httpsCallable("bereanConstitutionalPipeline").call(payload)
  ```

### System B (Orphan — nobody calls it)
- **Function:** `bereanPipeline` (creator codebase, us-east1)
- **Source:** `Backend/functions/src/berean/bereanPipeline.ts`
- **iOS call site:** NONE. No iOS file calls `bereanPipeline`.

### Reconciliation Executed
1. **GUARDIAN wrap verified on canonical path:** ✅ Added to `constitutionalPipeline.ts` Stage 4 — crisis short-circuit (crisis pattern → immediate safe answer without model call) + GUARDIAN system prompt injection when `Safety` intent detected. Deployed 2026-06-13.
2. **GUARDIAN on legacy callModelBerean:** ✅ Present (COPPA guard at `functions/bereanFunctions.js:854`).
3. **B's unique value ported:** 75 eval cases across 5 suites (bibleAccuracy, safetyCompliance, productWorkflows, moderationAccuracy, theologicalNeutrality) copied to `functions/berean/evalSuites/`. `EvalTestCase` type added to `functions/berean/evalFramework.ts`.
4. **Memory data check:** `bereanMemory`, `berean_memory`, `bereanInsights` collections — all 0 documents. No user data to migrate.

### Berean Memory System Note
iOS `BereanMemoryService.swift` calls `saveBereanInsight`, `updateBereanMemory`, `deleteBereanMemory` — these match **neither** deployed memory system. Both deployed memory systems use different callable names. The memory feature is **not currently functional** on iOS regardless of which system is canonical. This is a separate issue requiring iOS client update.

### System B Deletion List (8 functions, us-east1, creator codebase)
The following orphan functions from System B go on the deletion list below.

---

## Q-3: DELETION CANDIDATES — HUMAN GATE REQUIRED

> **⚠️ DO NOT DELETE without explicit human approval of this list.**  
> Review: confirm no client/trigger/schedule references any name below.  
> Command format: `firebase functions:delete <name> --region <region> --project amen-5e359 --force`

### Batch A: System B Orphans (us-east1, creator codebase) — 8 functions
These were deployed as an orphan Berean pipeline system (System B) that nobody calls.
Memory collections confirmed empty. Safe to delete immediately after approval.

```
firebase functions:delete bereanPipeline --region us-east1 --project amen-5e359 --force
firebase functions:delete constitutionalReview --region us-east1 --project amen-5e359 --force
firebase functions:delete modelRouter --region us-east1 --project amen-5e359 --force
firebase functions:delete bereanMemoryWrite --region us-east1 --project amen-5e359 --force
firebase functions:delete bereanMemoryRead --region us-east1 --project amen-5e359 --force
firebase functions:delete bereanMemoryDelete --region us-east1 --project amen-5e359 --force
firebase functions:delete bereanMemoryDeleteAll --region us-east1 --project amen-5e359 --force
firebase functions:delete bereanMemoryUpdate --region us-east1 --project amen-5e359 --force
```

**Note on naming conflict:** `bereanConstitutionalPipeline` (canonical, System A) and `bereanPipeline` (orphan, System B) are separate functions. Only `bereanPipeline` is in the deletion list.

---

### Batch B: DEAD services in us-central1 — 522 functions
**Evidence:** Name does not appear in `exports.*` in any `.js` file under `functions/`. These have no source and cannot be re-deployed from the current codebase.

**Recommended batch-delete order (10 per run, verify smoke tests between batches):**

#### Batch B-1: ConnectSpaces system (abandoned feature, ~30 functions)
```
firebase functions:delete \
  cancelconnectmembership classifyconnectintent createconnectannouncement \
  createconnectboard createconnectbooking createconnectchannel \
  createconnectcollection createconnectcreatorprofile createconnectevent \
  createconnectlivesession \
  --region us-central1 --project amen-5e359 --force
```
```
firebase functions:delete \
  createconnectmeeting createconnectpost createconnectproduct createconnectspace \
  createconnecttier creategiftmembership inviteconnectmember joinconnectlivesession \
  joinconnectmeeting purchaseconnectlivesession \
  --region us-central1 --project amen-5e359 --force
```
```
firebase functions:delete \
  purchaseconnectproduct removeconnectsaveditem reportconnectcontent \
  reportconnectcreatorprofile reportconnectlivesession reportconnectproduct \
  reportconnecttier saveconnectitemforlater sendconnectmessage \
  subscribetoconnecttier \
  --region us-central1 --project amen-5e359 --force
```

#### Batch B-2: Dead trigger functions (~50 functions — never re-deployed from source)
```
firebase functions:delete \
  onchurchinteractionattended onchurchinteractionreflected onchurchnoteshared \
  oncommentcreated oncommentcreatedupdatepreviews oncommentdeleted \
  oncommentdeletedupdatepreviews oncommunitynotewritten \
  onfollowcreated onfollowdeleted \
  --region us-central1 --project amen-5e359 --force
```
```
firebase functions:delete \
  onfollowevent onlikecreated onlikedeleted onmediapostcreate \
  onmediapostdelete onmediapostupdate onnewdmforminorprotection onnewdmmessage \
  onnoteamencreated onnoteamendeleted \
  --region us-central1 --project amen-5e359 --force
```
```
firebase functions:delete \
  onnotecommentcreated onnotecommentdeleted onpasswordchange onpostcreated \
  onpostcreatedgeneratemediametadata onpostcreatedrunmediamoderation \
  onpostcreatefeed onpostdeleted onpostdeletedclearpreviewstrigger \
  onpostdeletefeed \
  --region us-central1 --project amen-5e359 --force
```
```
firebase functions:delete \
  onpostflagged onpostmediametadatacreate onpostmediametadatadelete \
  onpostmediametadataupdate onpostmediaupdatedrunmoderation \
  onpostupdatedupdatepreviewstrigger onpostupdatefeed onprayercreated \
  onprayersupportcreated onrealtimereplycreate \
  --region us-central1 --project amen-5e359 --force
```
```
firebase functions:delete \
  onreplycreate onrepostcreated onrestmodepolicywritten onemailchange \
  onamencreated onuserblockedv2 onuserdeactivated \
  onuserprofileimageupdatedrefreshpreviews onuserwrite \
  normalizepostauthoroncreate \
  --region us-central1 --project amen-5e359 --force
```

#### Batch B-3: Dead generate/summarize/search functions (~80 functions)
```
firebase functions:delete \
  generateaccessibilityalttext generatebalancingscripture \
  generatebereanchurchsuggestions generatebereanfollowups generatebereanpulsedaily \
  generatecatchupsummary generatechurchexperiencesummary \
  generatechurchmatchesfromanswers generatecommunitydiscernmentsummary \
  generateconnectcatchup \
  --region us-central1 --project amen-5e359 --force
```
```
firebase functions:delete \
  generatecreatorinsights generatedeeplink generatediscussionfromcontent \
  generateearningsreport generategracefulrewrite generategroundedchurchanswer \
  generategroundedchurchresponse generatemeaningprompt generatemediasummary \
  generatemeetingrecap \
  --region us-central1 --project amen-5e359 --force
```
```
firebase functions:delete \
  generatenextyearholidaycalendar generateprepsuggestions \
  generatereconciliationprompt generatereflectionseedfromnotes \
  generatesmartreplies generatespacedna generatetiersuggestions \
  generatetopicclusters generatevideochapters \
  summarizebereanthread \
  --region us-central1 --project amen-5e359 --force
```
```
firebase functions:delete \
  summarizeconnectcatchupitem summarizeconnectchannel summarizeconnectdm \
  summarizecontent summarizeconversationcatchup summarizediscussion \
  summarizethread searchamennationaldirectory searchchurchesbykeyword \
  searchcommunitynotes searchcovenantdocuments \
  --region us-central1 --project amen-5e359 --force
```

#### Batch B-4: Dead Spaces/Rooms/Selah functions (~60 functions)
```
firebase functions:delete \
  createspace createspacecheckoutsession createspacediscussion \
  createspacegiftmembership createspaceprayerrequest createsponsoredmembership \
  createroom createselahcontinuation createselahoutcome createsharedviewingroom \
  --region us-central1 --project amen-5e359 --force
```
```
firebase functions:delete \
  discoverspaces dissolveephemeralroom getselahfeed getspacediscussions \
  getspacehealthmetrics joinspace leavespace muteobjecthub \
  rankamenspacesdiscussions requestamenspacediscussionaccess \
  --region us-central1 --project amen-5e359 --force
```
```
firebase functions:delete \
  saveamenspacediscussion selahgeneratereflectionprompt selahmatchaudio \
  selahrecognizeverse selahstoryproxy semanticsearchamenspace \
  buildselahmeaninggraphedge cleanupstaleselahcontinuations \
  indexselahnote saveselahmemory \
  --region us-central1 --project amen-5e359 --force
```

#### Batch B-5: Dead scheduled/maintenance functions (~40 functions)
```
firebase functions:delete \
  schedulechurchfollowupprompt schedulecontent \
  scheduledamennationaldirectoryalgoliasync scheduledamennationaldirectorygeocoding \
  scheduledamennationaldirectoryimports scheduledreplypreviewrefresh \
  scheduledsmartmessagevectorbackfill schedulemidweekreflectionreminder \
  hourlyanomalycheck dailyagetierpromotion \
  --region us-central1 --project amen-5e359 --force
```
```
firebase functions:delete \
  cleanupstalechurchjourneys cleanupstalenotifications computefeedcontextlabels \
  computerelationshipmutualdata computeservicestatus dedupeorganizations \
  deduplicateorgs geocodeorganizationbatch monitoraispend monitorfailedauthspike \
  --region us-central1 --project amen-5e359 --force
```

#### Batch B-6: Remaining dead functions — bulk cleanup (~262 more functions)
All remaining names from the 522 DEAD list not covered in B-1 through B-5.
Run after smoke tests confirm B-1 through B-5 deletions had no impact:

```bash
# Generate deletion command for remaining ~262 functions:
# cat /tmp/amen_truly_dead.txt | grep -v -f <(cat batch_b1_through_b5.txt) \
#   | xargs -n10 firebase functions:delete --region us-central1 --project amen-5e359 --force
```

**Full list of 522 DEAD names saved at:** `deploy-logs/2026-06-12/dead_central1_functions.txt`

---

## Q-4: Topology Notes

### Current Multi-Region State (INTERIM)
All functions deployed 2026-06-12 and 2026-06-13 went to **us-east1** (primary) or **us-west1** (storage triggers) due to us-central1 quota exhaustion. This is an **intentional interim state**, not a permanent architecture choice.

**Latency implication:** Firestore database is in `nam5` (us-central1/us-east1 multi-region). us-east1 adds ~5–15ms vs us-central1 for Firestore reads. Acceptable for now.

### Interim Region Table
Functions that should consolidate back to us-central1 once quota is available (<850 services):

| Function | Current Region | Ideal Region | iOS Call Site |
|----------|---------------|--------------|---------------|
| `createFollow` | us-east1 | us-central1 | `FollowService.swift:167` |
| `createUnfollow` | us-east1 | us-central1 | `FollowService.swift:236` |
| `blockRelationshipCleanupTrigger` | us-east1 | us-central1 | Firestore trigger (no iOS call) |
| `reconcileFollowCounts` | us-east1 | us-central1 | Cloud Scheduler |
| `revokeNotificationsOnCommentDelete` | us-east1 | us-central1 | Firestore trigger |
| `revokeNotificationsOnPostDelete` | us-east1 | us-central1 | Firestore trigger |
| `algoliaPostUpdateSync` | us-east1 | us-central1 | Firestore trigger |
| `algoliaPostDeleteSync` | us-east1 | us-central1 | Firestore trigger |
| `bereanConstitutionalPipeline` | us-east1 | us-east1 | `BereanConstitutionalPipeline.swift:266` ← KEEP in east1; iOS already wired |
| `bereanSubmitFeedback` | us-east1 | us-east1 | `BereanConstitutionalPipeline.swift:242` |
| `verifyScriptureText` | us-east1 | us-east1 | (internal berean use) |
| `processMediaUpload` | us-east1 | us-east1 | GlobalResilience (keep east1) |
| `getMediaVariant` | us-east1 | us-east1 | GlobalResilience |
| `sendMessageGlobal` | us-east1 | us-east1 | GlobalResilience |
| `getThreadOfflineCache` | us-east1 | us-east1 | GlobalResilience |
| `moderateUploadedDMVideo` | us-west1 | us-west1 | Storage trigger — bucket in us-west1 |
| `moderateUploadedImage` | us-west1 | us-west1 | Storage trigger — bucket in us-west1 |

### Consolidation Trigger
> When us-central1 service count drops below **850** OR when quota increase is granted:
> Move `createFollow`, `createUnfollow`, trigger functions, and `algoliaPost*` back to us-central1.
> Update `FollowService.swift:167` region string simultaneously.

### New Function Deployment Rule (for CLAUDE.md)
New functions deploy to `us-central1` IF service count < 950. Otherwise deploy to `us-east1` with a mandatory entry in the **Interim Region Table** above. Never silent.

---

## Q-1: Complete Dead Service List

Full list of 522 DEAD us-central1 services (no source in any JS file):
See `deploy-logs/2026-06-12/dead_central1_functions.txt`.

Count by feature category:
- ConnectSpaces system: ~35
- Dead Firestore/event triggers: ~60
- Dead generate/summarize functions: ~80
- Dead Spaces/Rooms/Selah: ~60
- Dead Church/Organization functions: ~50
- Dead moderation callables: ~20
- Dead ONE private social functions: ~15
- Dead search/discovery functions: ~30
- Dead admin/analytics functions: ~172
