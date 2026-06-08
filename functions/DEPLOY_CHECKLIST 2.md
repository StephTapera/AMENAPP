# Berean AI — Audit Fix Deploy Checklist

> **Quick deploy:** `bash deploy-berean.sh` from the repo root runs all steps 1–6 automatically
> (secret pre-checks, Firestore rules, then all 8 audit CFs in dependency order).

Tracks all pending deploy steps from the Berean AI audit (berean-audit-report.md)
and the Pinecone draft cleanup work.

---

## Pre-deploy (one-time secrets)

- [ ] `firebase functions:secrets:set PINECONE_API_KEY`
- [ ] `firebase functions:secrets:set PINECONE_HOST`
- [ ] `firebase functions:secrets:set OPENAI_API_KEY` (if not already set)
- [ ] `firebase functions:secrets:set ANTHROPIC_API_KEY` (if not already set)
- [ ] `firebase functions:secrets:set CLAUDE_API_KEY` (bereanShield, bereanFeaturesFunctions, bereanFunctions — Anthropic SDK direct key)
- [ ] `firebase functions:secrets:set GOOGLE_VISION_API_KEY` (bereanFunctions — image safety)
- [ ] `firebase functions:secrets:set NVIDIA_API_KEY` (for NeMo Guard moderatePost)
- [ ] `firebase functions:secrets:set BEREAN_LLM_KEY` (discussionFunctions — Gemini key for askBerean; falls back to mock if unset)
- [ ] `firebase functions:secrets:set EMBEDDING_KEY` (discussionFunctions — Gemini embeddings for detectDuplicate; falls back to mock if unset)
- [ ] `firebase functions:secrets:set TRUESOURCE_SIGNING_KEY` (trueSource.js — content provenance signing)
- [ ] `firebase functions:secrets:set ALGOLIA_APP_ID` (algoliaSync.js)
- [ ] `firebase functions:secrets:set ALGOLIA_ADMIN_API_KEY` (algoliaSync.js)
- [ ] `firebase functions:secrets:set ALGOLIA_INDEX_NAME` (algoliaSync.js)
- [ ] `firebase functions:secrets:set IDEOGRAM_API_KEY` (studioImageGeneration.js)

---

## CF deploys

Deploy each function individually to reduce blast radius:

```sh
firebase deploy --only functions:createRealtimeSession --project amen-5e359
firebase deploy --only functions:bereanSLOCheck --project amen-5e359
firebase deploy --only functions:writeBereanAuditEntry --project amen-5e359
firebase deploy --only functions:cleanupDraftVectors --project amen-5e359
firebase deploy --only functions:reportUnsafeAIResponse --project amen-5e359
firebase deploy --only functions:deleteAccount --project amen-5e359
```

Or batch them:

```sh
firebase deploy \
  --only functions:createRealtimeSession,functions:bereanSLOCheck,functions:writeBereanAuditEntry,functions:cleanupDraftVectors,functions:reportUnsafeAIResponse,functions:deleteAccount \
  --project amen-5e359
```

- [ ] `createRealtimeSession` — H-22: ephemeral OpenAI Realtime token broker
- [ ] `bereanSLOCheck` — H-33: SLO anomaly detection + kill switch
- [ ] `writeBereanAuditEntry` — H-13: server-authoritative Berean audit trail
- [ ] `cleanupDraftVectors` — H-30: one-time Pinecone draft vector purge
- [ ] `reportUnsafeAIResponse` — C-04: user-facing unsafe AI response report pipeline
- [ ] `deleteAccount` — H-18: now deletes Pinecone vectors for the user on deletion
- [ ] `bereanShieldAnalyze` — Berean Shield: claim truth-check (5 dimensions)
- [ ] `bereanCompassAnalyze` — Berean Compass: DM manipulation arc detection
- [ ] `dailyVerseDrop` — scheduled: personalized daily verse push (7am CT)
- [ ] `weeklyPrayerRecap` — scheduled: AI prayer journal recap (Sunday 8pm CT)
- [ ] `generatePrayerRecap` — callable: on-demand prayer recap for current user
- [ ] `askBerean` — discussion: AI thread summary (BEREAN_LLM_KEY)
- [ ] `detectDuplicate` — discussion: cosine-similarity duplicate comment check
- [ ] `computeReputation` — discussion: points aggregation + badge tier
- [ ] `postComment` — discussion: write comment after threshold passes
- [ ] `markHelpful` — discussion: idempotent helpful-mark + reputation event
- [ ] `updateWatchProgress` — discussion: upsert watch-progress doc
- [ ] `getWatchProgress` — discussion: read watch-progress + shouldNudge flag

---

## Post-deploy one-time operations

Run the Pinecone draft cleanup. Must be called by a user with admin custom claim
(`claims.admin == true` or `claims.superAdmin == true`):

```sh
firebase functions:call cleanupDraftVectors --data '{}' --project amen-5e359
```

Expected response: `{ "deleted": N, "scanned": M, "durationMs": D }`

If `scanned == 0`, the index was already clean (or Pinecone returned no matches
for `dominantType == "draft"`). Safe to re-run — idempotent.

- [ ] Run `cleanupDraftVectors` as admin user (check bereanAuditLog for confirmation)

---

## App Check setup (Firebase Console)

- [ ] Firebase Console → App Check → Apps → AMEN iOS → Register with **App Attest**
- [ ] Enable enforcement for: **Authentication, Firestore, Functions, Storage**
- [ ] Add debug token for CI/simulator:
      Firebase Console → App Check → Apps → (select app) → Add debug token
      Set `FirebaseAppCheckDebugToken` in the Xcode scheme environment variables.
- [ ] After enabling enforcement, flip `enforceAppCheck: false` → `true` on:
      - `bereanChatProxy` (bereanFunctions.js)
      - `deleteAccount` (bereanFunctions.js)

---

## Firestore rules

- [ ] `firebase deploy --only firestore:rules --project amen-5e359`

Key rules added by the audit fixes:
- `bereanAuditLog` — write: functions only; read: admin only
- `aiReports` — write: auth; read: admin only
- `pastoralCareAlerts` — write: functions only; read: admin + ministry roles only

---

## Verification checklist

After all deploys:

- [ ] Call `cleanupDraftVectors` and confirm `bereanAuditLog` has a new entry
- [ ] Delete a test account and confirm Pinecone vectors are removed
      (check Cloud Function logs for `[deleteAccount] Pinecone vectors deleted`)
- [ ] Verify `bereanSLOCheck` is listed as a scheduled function in Firebase Console
- [ ] Submit a test unsafe AI response report and confirm `aiReports` collection has entry
- [ ] Confirm App Check enforcement is active (check Firebase Console metrics)
