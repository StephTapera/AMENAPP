# RUN_ME.md — AMEN Deploy Stack Guide

**Run with:** `bash RUN_ME.sh`  
**Branch:** safety-hardening | **HEAD:** 5b4f1f5a  
**Estimated time:** ~65 minutes  
**No flag flips in the script.** It prints the flip registry at the end; you flip.

---

## Stage-by-stage summary

| Stage | What | Why (one line) |
|---|---|---|
| **0 — Preflight** | Git HEAD check, project auth, secrets grep, tsc compile, keystone jest | Abort loudly before touching prod if anything is wrong |
| **1 — Recovery (7 CFs + rules)** | Firestore rules, storage rules, indexes, then 7 safety CFs | Restores DMs, closes COPPA gaps, brings CSAM/anti-harassment/age-sync live |
| **2 — Pepper rotation** | `openssl rand` → `secrets:set PHONE_HASH_PEPPER` → redeploy 3 phone CFs | Rotates HMAC pepper for phone-number privacy; required by SAFETY_RUNBOOK §13 |
| **3 — Stage-3 CFs** | A3 safety (5) → Connect queue (1) → ONE (5) → Spiritual OS (27) → Find Church 2.0 (4) | Makes every new callable available server-side before any flag flip |
| **4 — Rules + storage (conditional)** | Deploys merged `firestore.rules` + `storage.rules` if `RULES_RECONCILIATION_VERDICT.md` says GREEN | Guards against deploying un-reconciled rules; skips with loud notice if verdict absent |
| **5 — Remote Config (15 keys)** | Fetches current RC template, inserts 5 connect_* + 10 findChurch2_* keys (all false), re-deploys | Keys must exist in RC before you can flip them; deploying them activates nothing |
| **6 — Bait-transcript runner** | Calls `contentSafetyScreen`, `assessDogpileRisk`, `evaluateDmRisk` with synthetic bait | Proves fail-closed CF behavior is live; required wave gate for W3-5 surface flags |
| **7 — Smoke checklist** | 10 human-verified pass/fail prompts | Record-of-deploy; any NO means incomplete before flag flip |

---

## Prerequisites (check before running)

- `firebase` CLI installed and authenticated (`firebase login`)
- `gcloud` CLI installed and authenticated for bait-transcript ID token
- `node` 20+ installed
- `openssl` available (standard on macOS/Linux)
- You are on the `safety-hardening` branch at HEAD `5b4f1f5a`
- You have write access to Firebase project `amen-5e359`

---

## What the script does NOT do

- Flip any feature flag (all flags stay false after this script)
- Deploy the iOS app binary
- Set `NCMEC_SUBMISSION_ENABLED=true` (requires legal sign-off; see SAFETY_RUNBOOK §7)
- Seed the Find Church 2.0 corpus (manual step after Stage 3e)
- Fix any Open Questions from SAFETY_RUNBOOK §16

---

## After the script completes

1. **Review** `bait_transcript_results_*.txt` — all tests must PASS before enabling W3-5 surfaces
2. **Set TTL policy** on `connect_idempotency.processedAt` (7 days) in Firebase Console
3. **Flip flags** individually as QA passes — use the preconditions registry printed at the end
4. **Seed Phoenix corpus** when `ingestChurchesFromGooglePlaces` is verified live:
   ```bash
   curl -X POST https://us-central1-amen-5e359.cloudfunctions.net/ingestChurchesFromGooglePlaces \
     -H "Content-Type: application/json" \
     -d '{"data": {"location": {"lat": 33.4484, "lng": -112.0740}, "radiusMeters": 50000}}'
   ```
5. **Resolve SAFETY_RUNBOOK OQs** — particularly OQ-3 (legalReviewer claim), OQ-11 (guardian bug), OQ-25 (CSAM pipeline)

---

## Rollback reference

| Item | Rollback command |
|---|---|
| Firestore rules | `git show HEAD^:firestore.rules > /tmp/rb.rules && firebase deploy --only firestore:rules --project amen-5e359` |
| Any single CF | `firebase functions:delete FUNCTION_NAME --project amen-5e359` |
| PHONE_HASH_PEPPER | `firebase functions:secrets:set PHONE_HASH_PEPPER --project amen-5e359` (generate new value) |
| Remote Config | Firebase Console → Remote Config → Version history → roll back |
| Feature flag | Set flag to `false` in Firebase Console → Remote Config |
