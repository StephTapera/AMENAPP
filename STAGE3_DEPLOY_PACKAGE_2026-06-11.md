# STAGE-3 DEPLOY PACKAGE
**Date:** 2026-06-11 | **Branch:** safety-hardening | **HEAD:** 4526d792

PRODUCTION FREEZE ABSOLUTE — no flag flips until all deploys in this package land.

---

## Step 0 — Verify clean state before any deploy

```bash
git log --oneline -5    # confirm HEAD == 4526d792
firebase projects:list  # confirm correct project (amen-5e359)
```

---

## Step 1 — Recovery redeploys (if not yet done from prior package)

These were listed in prior deploy packages and remain mandatory preconditions.

| CF / Rule | Command |
|---|---|
| Firestore rules | `firebase deploy --only firestore:rules --project amen-5e359` |
| syncAgeTierClaim | `firebase deploy --only functions:syncAgeTierClaim --project amen-5e359` |
| antiHarassmentEnforcement | `firebase deploy --only functions:antiHarassmentEnforcement --project amen-5e359` |
| commentModerationEnforcement | `firebase deploy --only functions:commentModerationEnforcement --project amen-5e359` |

---

## Step 2 — Safety Wave 3 package

| Item | Command |
|---|---|
| A3 callables (all 5) | `firebase deploy --only functions:evaluateDmRisk,functions:reportDmAbuse,functions:contentSafetyScreen,functions:analyzeRelationshipRisk,functions:assessDogpileRisk --project amen-5e359` |
| Verify post-deploy | Check Firebase console → Functions → evaluateDmRisk exists and status = ACTIVE |

---

## Step 3 — Connect offline queue

| Item | Command |
|---|---|
| processConnectQueuedDraft | `firebase deploy --only functions:processConnectQueuedDraft --project amen-5e359` |
| Firestore idempotency collection TTL | Console: Firestore → connect_idempotency → Add TTL policy on `processedAt` field (7 days) |

---

## Step 4 — ONE private social OS (FLAG-FLIP PREREQUISITE)

| Item | Command | Notes |
|---|---|---|
| one_relayMoment | `firebase deploy --only functions:one_relayMoment --project amen-5e359` | Already written with forwardAllowed rejection |
| one_sendMoment | `firebase deploy --only functions:one_sendMoment --project amen-5e359` | |
| one_expireMoment | `firebase deploy --only functions:one_expireMoment --project amen-5e359` | |
| one_verifyEntitlement | `firebase deploy --only functions:one_verifyEntitlement --project amen-5e359` | |
| one_activateLegacy | `firebase deploy --only functions:one_activateLegacy --project amen-5e359` | |

---

## Step 5 — Spiritual OS callables

```bash
firebase deploy --only \
  functions:detectUnsentThoughtRisk,functions:saveUnsentThought,functions:resolveUnsentThought,\
  functions:analyzeScriptureDrift,functions:generateBalancingScripture,functions:dismissDriftSignal,\
  functions:detectSilencePatterns,functions:resurfaceAvoidedItem,functions:markSilenceSignalResolved,\
  functions:updateRelationalGravity,functions:classifyRelationshipState,functions:generateReconciliationPrompt,\
  functions:evaluateMomentRisk,functions:logMomentInterception,functions:updateMomentLearning,\
  functions:createReflectionPrompt,functions:savePostActionReflection,functions:updateUserGrowthPattern,\
  functions:analyzeTruthVsEmotion,functions:scoreWeightOfWords,functions:generateGracefulRewrite,\
  functions:aggregateDiscernmentSignals,functions:generateCommunityDiscernmentSummary,\
  functions:calculateEternalWeight,functions:updateEternalWeightAfterReflection,\
  functions:generateMeaningPrompt,functions:createWalkWithChristPathFromPattern \
  --project amen-5e359
```

---

## Step 6 — Remote Config additions

Add these keys to Firebase Remote Config (all default `false` until human verifies):

| Key | Default | Enables |
|---|---|---|
| `connect_layout_v2_enabled` | false | Wave 1: V2 shell, glass bar, notch FAB |
| `connect_polish_v2_enabled` | false | Wave 2: Unified Catch Up, ⓘ chip |
| `connect_empty_states_enabled` | false | Wave 3: ConnectEmptyStateView |
| `connect_smart_berean_enabled` | false | Wave 4: Smart Berean pill |
| `connect_offline_queue_enabled` | false | Wave 5: Offline draft queue |

---

## Step 7 — FLAG-FLIP PRECONDITIONS REGISTRY

Do not flip any flag until its preconditions are met.

| Flag | Precondition |
|---|---|
| `connect_layout_v2_enabled` | processConnectQueuedDraft deployed; iOS 26 device tested |
| `connect_smart_berean_enabled` | bereanQuestion CF live; connect_layout_v2 already on |
| `connect_offline_queue_enabled` | processConnectQueuedDraft deployed with TTL policy |
| Any `one_*` flag | ALL one_* CFs deployed; one_relayMoment verified with forwardAllowed rejection |
| `spiritualOS_*` flags | All Step 5 CFs deployed and ACTIVE in console |

---

## Step 8 — Context System W3-5 (HUMAN-PENDING)

Bait-transcript runner must be executed against live CFs. Output proves
volunteered-excluded-content isolation. Required before W3-5 surfaces go live.

---

## Step 9 — W3-12 deployed-storage check (HUMAN-PENDING)

Verify in Firebase console that all Firestore rules from the safety-hardening branch
are live and that the age-tier custom claims sync is running without errors.

---

## Step 10 — Find Church 2.0 (append-only diffs — ship after Steps 1–9)

### 10a — Firestore rules (append-only, folded into safety rules deploy)

The four new `findChurch2_*` collections are guarded in `firestore.rules` with deny-by-default
catch-all still in place. Deploy as part of Step 1's `firebase deploy --only firestore:rules`:

```
/gatherings/{gatheringId}   — read: isSignedIn + isPublic==true; write: Admin SDK only
/seekerProfiles/{uid}       — read/write: isSignedIn + auth.uid == uid; Admin SDK bypass
/visitPlans/{planId}        — read: owner; create: owner with required fields; delete: false
/claimRequests/{claimId}    — create: owner + status==submitted; read: owner or Admin; update/delete: false
```

No new rules file needed — diffs are already committed to `firestore.rules` on this branch.

### 10b — Find Church 2.0 Cloud Functions

Auth + App Check + rate-limit confirmed at:
- `requireAuth()` — `ingestion.ts:107-113` (throws `unauthenticated` when `auth.uid` absent)
- `requireAppCheck()` — `ingestion.ts:115-120` (throws `failed-precondition` when `app.appId` absent; emulator-exempt)
- Rate limit — `ingestion.ts:122-125` via `_systemLocks/ingestChurches` Firestore lock, 5000 ms minimum

```bash
firebase deploy --only \
  functions:ingestChurchesFromGooglePlaces,\
  functions:computeAvailabilityStatus,\
  functions:scheduleAvailabilityRefresh,\
  functions:detectChurchMedia \
  --project amen-5e359
```

**Prerequisite:** Set `GOOGLE_PLACES_API_KEY` before deploying ingestion:
```bash
firebase functions:config:set places.api_key="YOUR_KEY" --project amen-5e359
```

### 10c — Remote Config (all default OFF — flip individually after verification)

Upload the `remoteconfig.template.json` diff (10 new keys):
```
findChurch2_onboarding        false   3-phase LG onboarding
findChurch2_matchExplain      false   MatchExplanation drawer
findChurch2_gatherings        false   Gatherings surface
findChurch2_visitPlanner      false   Visit Planner
findChurch2_claimPortal       false   Claim flow + admin portal
findChurch2_concierge         false   Berean concierge (local-only)
findChurch2_mapHybrid         false   Map/list toggle
findChurch2_availability      false   AvailabilityStatus pills
findChurch2_trustSignals      false   Trust signals section
findChurch2_designRefresh     false   Full UI refresh (header, cards, profile expansion)
```

### 10d — Seed Phoenix metro corpus (after 10b is live)

```bash
# Call via Firebase console or a Cloud Shell authenticated curl:
curl -X POST https://us-central1-amen-5e359.cloudfunctions.net/ingestChurchesFromGooglePlaces \
  -H "Content-Type: application/json" \
  -d '{"data": {"location": {"lat": 33.4484, "lng": -112.0740}, "radiusMeters": 50000}}'
```

### 10e — Flag-flip preconditions

| Flag | Precondition |
|---|---|
| `findChurch2_availability` | `computeAvailabilityStatus` + `scheduleAvailabilityRefresh` deployed and ACTIVE |
| `findChurch2_gatherings` | `gatherings/` Firestore rules live (Step 10a) |
| `findChurch2_visitPlanner` | `seekerProfiles/` + `visitPlans/` rules live; EventKit + UNNotification plist entries confirmed present |
| `findChurch2_claimPortal` | `claimRequests/` rules live; Aegis review queue handler confirmed in place |
| `findChurch2_concierge` | No CF dependency — local-only; can flip independently |
| `findChurch2_matchExplain` | No CF dependency — local-only; can flip independently |
| `findChurch2_designRefresh` | `findChurch2_matchExplain` already ON; test on smallest + largest device |
| `findChurch2_onboarding` | `seekerProfiles/` rules live; Privacy policy updated to describe SeekerProfile |

---

## Post-deploy smoke test checklist

- [ ] `firebase functions:log --only evaluateDmRisk` — no cold-start errors
- [ ] `firebase functions:log --only one_relayMoment` — forwardAllowed=false returns permission-denied
- [ ] `firebase functions:log --only processConnectQueuedDraft` — idempotency key deduplication working
- [ ] iOS 26 simulator: flip `connect_layout_v2_enabled` to true, verify glass bar renders
- [ ] iOS 17 simulator: same flag, verify fallback matte Capsule bar renders
