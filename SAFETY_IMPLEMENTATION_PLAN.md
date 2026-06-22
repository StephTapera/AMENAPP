# Amen Safety Implementation Plan

Generated: 2026-06-11
Branch: safety-hardening
Auditor: automated gap analysis

---

## Status: Critical Fixes

### C1 — Broken escalateChildSafety import crashes every user-filed CSAM report

**Status:** PENDING
**File changed:** `functions/moderation/escalation.js`, `functions/safety/blockMuteReport.js`
**Action:**
1. Move `escalateChildSafety` from `functions/moderatePost.js` into `functions/moderation/escalation.js` and export it alongside `createLegalHold` and `reportToNcmec`.
2. Update the import at `functions/safety/blockMuteReport.js:31` from `moderatePost.js` to `moderation/escalation.js`.
3. In the `catch` block at `blockMuteReport.js:235-239`, add a re-throw after logging so failures are never silently swallowed — or write a `childSafetyEscalationFailure` document to a dead-letter Firestore collection so on-call can be paged.
4. Add an integration test: file a report with category `csam_suspected` and assert a `childSafetyEscalations` document exists afterward.

**Deploy command:**
```
firebase deploy --only functions:blockMuteReport,functions:escalation
```

---

### C2 — CSAM image path has no legalHold or NCMEC escalation

**Status:** PENDING
**File changed:** `functions/moderation/imageModeration.js`, `functions/moderatePost.js`, `functions/adminReviewPost.js`
**Action:**
1. In `adminReviewPost` (and any image-review callable), after `imageModeration.js` returns `status='blocked'` with `cs_csam_suspected` or `cs_child_exploitation` categories, call `escalateChildSafety` (or directly call `createLegalHold` + queue the NCMEC stub) before making any moderation decision.
2. Ensure the evidence snapshot and SHA-256 hash are captured from the storage object, not reconstructed after the fact.
3. Wire the same image-moderation path into DM and comment image surfaces so image-only CSAM in those surfaces reaches the same escalation pipeline.
4. Add a test: upload a simulated CSAM-flagged image via the admin review path and assert `legalHolds` and `childSafetyEscalations` documents are both created.

**Deploy command:**
```
firebase deploy --only functions:adminReviewPost,functions:moderatePost
```

---

### C3 — index.js exports moderateContent twice — second export shadows first

**Status:** PENDING
**File changed:** `functions/index.js`
**Action:**
1. Identify whether `aiModeration.moderateContent` is a Firestore `onDocumentCreated` trigger or a callable. If it is a trigger, remove the `exports.moderateContent` assignment at line 300 entirely and register it under a unique name (e.g., `exports.moderateContentAI`).
2. Update all callers (iOS, other CFs) that reference `moderateContent` to use the correct function name.
3. Add a CI lint step (e.g., a Node script in `.github/workflows/`) that asserts no two lines in `index.js` assign to the same `exports.*` key.

**Deploy command:**
```
firebase deploy --only functions
```
(Full functions redeploy required to deregister the duplicate export.)

---

### C4 — Subscription tier entitlement trusts unverified client-supplied transactionId

**Status:** PENDING
**File changed:** `functions/accountSubscriptionFunctions.js`
**Action:**
1. Store the App Store Connect private key as a Secret Manager secret named `APPLE_ASC_PRIVATE_KEY` and the Key ID as `APPLE_ASC_KEY_ID`. Gate the deploy on these secrets being present.
2. In `processAccountSubscription`, before writing any entitlement:
   a. Build an ES256 JWT using the private key.
   b. Call `GET https://api.storekit.itunes.apple.com/inApps/v1/transactions/{transactionId}` (production, with sandbox fallback on 4xx).
   c. Verify the decoded transaction: `productId` matches the claimed `productId`, `inAppOwnershipType` is `PURCHASED`, and the transaction is not expired.
   d. Derive the tier from `productId` server-side rather than accepting the client-supplied `tier`.
3. Only then write the entitlement to Firestore.
4. Do not launch any paid tier publicly until this is verified in staging.

**Deploy command:**
```
firebase functions:secrets:set APPLE_ASC_PRIVATE_KEY
firebase functions:secrets:set APPLE_ASC_KEY_ID
firebase deploy --only functions:processAccountSubscription
```

---

## Status: High Fixes

### H1 — Berean AI callables do not enforce App Check

**Status:** PENDING
**File changed:** `functions/v2functions.js` (lines 479-484, 551-557, 607-612)
**Action:** Add `enforceAppCheck: true` to the options object for `bereanChat`, `bereanMemory`, and `bereanCrisisDetect`:
```js
{ region: 'us-central1', enforceAppCheck: true, timeoutSeconds: 60, secrets: [...] }
```
Verify the Firebase Console App Check enforcement toggle is enabled for the production project before deploying, otherwise `enforceAppCheck: true` is a no-op.

**Deploy command:**
```
firebase deploy --only functions:bereanChat,functions:bereanMemory,functions:bereanCrisisDetect
```

---

### H2 — Universal age gate (ff_onboarding_v2) is default OFF

**Status:** PENDING
**File changed:** `AMENAPP/AMENFeatureFlags.swift`, Firebase Remote Config console
**Action:**
1. Set the Remote Config default for `ff_onboarding_v2` to `true` in the Firebase Console for the production project.
2. Update the local default in `AMENFeatureFlags.swift:218` to `true` so the gate is active even before Remote Config fetches.
3. In any profile-creation Cloud Function, add a server-side check: if `ageTier` is absent from the user document, create a default age profile (unknown tier) and flag the account for age verification.
4. Confirm `isMinorAccount()` in Firestore rules returns a safe default when `ageTier` is absent (see also M10 for the authoritative fix).

**Deploy command:**
```
firebase remoteconfig:set --project amen-5e359
# Set ff_onboarding_v2 = true in Remote Config JSON or console
```

---

### H3 — publishQuotePost() writes directly to Firestore, bypassing moderation

**Status:** PENDING
**File changed:** `AMENAPP/PostsManager.swift` (lines 1568-1592), `functions/` (new or extended `publishPost` callable)
**Action:**
1. Refactor `publishQuotePost()` to call a Cloud Function callable (e.g., `publishPost` with `type: 'quote'`) rather than writing directly to Firestore.
2. The callable must set `visible: false` on the new document before returning, letting the `moderatePost` trigger re-enable visibility after a safe verdict.
3. At minimum (as a short-term guard), add a Firestore rule that forces `visible: false` on any post `create` operation from the client if the client does not explicitly set it to `false`.
4. Validate `quotedContent` and `quotedAuthorName` server-side by fetching the original post from Firestore inside the CF rather than trusting client-supplied values.

**Deploy command:**
```
firebase deploy --only functions:publishPost
firebase deploy --only firestore:rules
```

---

### H4 — Two parallel legalHolds schema implementations

**Status:** PENDING
**File changed:** `functions/moderation/legalHold.js`, `functions/moderatePost.js`, `functions/moderation/escalation.js`
**Action:**
1. Define a canonical `legalHolds` schema in `functions/moderation/legalHoldSchema.js` with fields: `holdId` (UUID), `caseId`, `contentType`, `contentId`, `authorUID`, `contentSnapshot` (full), `snapshotHash` (deterministic — see L2), `evidenceRefs` (array), `createdAt`, `createdBy`, `status`.
2. Route all three write paths through `legalHold.js:createLegalHold` as the single writer.
3. Write a migration script to normalize existing `legalHolds` documents to the canonical schema.
4. Update `cyberTiplineInterface.js` to read only from the canonical schema fields.

**Deploy command:**
```
firebase deploy --only functions:moderatePost,functions:escalation,functions:legalHold
# Run migration script separately after deploy
```

---

### H5 — one_users witnesses subcollection allows any authenticated write

**Status:** PENDING
**File changed:** `firestore.rules` (line 1684)
**Action:** Replace:
```
allow write: if isSignedIn();
```
With:
```
allow create: if isSignedIn()
    && request.resource.data.witnessUID == request.auth.uid;
allow update: if isSignedIn()
    && (request.auth.uid == uid || request.auth.uid == resource.data.witnessUID)
    && request.resource.data.keys().hasOnly(['status', 'acceptedAt', 'updatedAt']);
allow delete: if false;
```
The Cloud Function that creates the initial witness invitation should write via Admin SDK (bypassing these rules) and own the canonical create path.

**Deploy command:**
```
firebase deploy --only firestore:rules
```

---

### H6 — stripeWebhook 2.js — duplicate legacy webhook file

**Status:** PENDING
**File changed:** `functions/stripeWebhook 2.js` (DELETE)
**Action:**
1. Confirm `functions/stripeWebhook 2.js` is NOT referenced in `functions/index.js`.
2. Delete the file: `rm "functions/stripeWebhook 2.js"`.
3. Add a CI check (pre-commit hook or GitHub Actions step) that fails if any file in `functions/` matches the pattern `*[0-9].js` or `* [0-9].js`.
4. Audit the Firebase Console deployed functions list to confirm no `stripeWebhook2` function is live. If it is, delete it via `firebase functions:delete stripeWebhook2`.

**Deploy command:**
```
firebase functions:delete stripeWebhook2 --force   # if deployed
firebase deploy --only functions:stripeWebhook
```

---

### H7 — detectGroomingRisk is exported but never called

**Status:** PENDING
**File changed:** `functions/v2functions.js` or `functions/moderation/moderateUGC.js`
**Action:**
1. In the `onMessageSent` trigger (or `moderateDMMessage` handler), after the message is written, fetch the prior N messages for the conversation thread.
2. Pass them to `detectGroomingRisk(messages, senderUID, recipientUID)`.
3. If `risk >= 'elevated'`, write a `safetyAlerts` document and a `moderationQueue` entry.
4. Add a time-window filter to the prior-reply query (e.g., only messages within the last 72 hours) to bound the fetch cost.

**Deploy command:**
```
firebase deploy --only functions:moderateDMMessage,functions:onMessageSent
```

---

### H8 — User profile bios, display names, and testimonies have no moderation trigger

**Status:** PENDING
**File changed:** `functions/profilePropagation.js`, `functions/testimonyFeatures.js`
**Action:**
1. In `onUserProfileUpdated`, add a `moderateText()` call on `displayName` and `bio` before propagating changes. If unsafe, revert the field to its prior value and write a `moderationQueue` entry.
2. Add an `onDocumentCreated` / `onDocumentWritten` trigger on the `testimonies` collection that calls `moderateText()` on the `body` field. If unsafe, set `status: 'pending_review'` and suppress display.

**Deploy command:**
```
firebase deploy --only functions:onUserProfileUpdated,functions:onTestimonyWritten
```

---

## Status: Medium / Low Fixes

### M1 — Rate limit check-then-increment is non-atomic

**Status:** PENDING
**File changed:** `functions/safety/rateLimits.js`
**Fix:** Merge `checkRateLimit` and `incrementCounter` into a single Firestore transaction. The transaction reads the counter, throws `RateLimitError` if `count >= limit`, then increments and commits in one operation.

---

### M2 — iOS moderationAuditLogs collection silently denied

**Status:** PENDING
**File changed:** `AMENAPP/ModerationAuditLog.swift`, `functions/` (new `submitAuditEvent` callable)
**Fix:** Replace direct Firestore writes in `ModerationAuditLog.swift` with a CF callable `submitAuditEvent` that validates the audit event schema and writes to the canonical `moderationAuditLog` collection via Admin SDK.

---

### M3 — TrueSource audit contract is entirely unimplemented

**Status:** PENDING
**File changed:** `AMENAPP/ModerationAuditLog.swift` (lines 242-254)
**Fix:** Implement each log method by constructing a `TrueSourceEventEntry` and calling the `submitAuditEvent` CF callable introduced in M2. Wire at minimum: `logPostCreated`, `logContentRemoved`, `logSafetyScanned`, `logHumanReviewRequested`.

---

### M4 — Appeal submission has no rate limit

**Status:** PENDING
**File changed:** `functions/moderation/appeals.js` (line 33)
**Fix:** Add `rateLimits.checkRateLimit(db, uid, 'appeal', currentWindowBucket)` at the start of `submitAppeal`. Limit: 5 appeals per day per user. Increment after the appeal document is written.

---

### M5 — decideAppeal uses stale JWT claim for moderator check

**Status:** PENDING
**File changed:** `functions/moderation/appeals.js`
**Fix:** Replace `request.auth.token.moderator` with a fresh `admin.auth().getUser(uid)` call using the `requireModerator()` pattern from `adminModerationFunctions.js`.

---

### M6 — No circuit breaker on NVIDIA NIM provider

**Status:** PENDING
**File changed:** `functions/moderation/providerRouter.js`
**Fix:** Add an in-memory (or Firestore-backed for cross-instance) circuit breaker: open after 3 consecutive failures within a 60-second window; half-open after a 30-second cooldown. During open state, skip NVIDIA NIM and route directly to the fallback provider or dead-letter. Reduce `MAX_ATTEMPTS` to 2 to bound the cold-path latency to 20s maximum.

---

### M7 — Comment edits have no moderation trigger

**Status:** PENDING
**File changed:** `functions/` (new `onCommentUpdated` trigger)
**Fix:** Add an `onDocumentUpdated` trigger on `comments/{commentId}` that calls `textModeration.moderateText()` on any change to the `body` / `content` field. If unsafe, revert to the previous value and write a `moderationQueue` entry.

---

### M8 — Password reset rate limiting is client-side only

**Status:** PENDING
**File changed:** `AMENAPP/AuthenticationViewModel.swift` (lines 56-58, 993-1028), `functions/rateLimits.js`
**Fix:** Add a `sendPasswordReset` action to `rateLimits.js` (3/15min limit). Wrap the reset email send in a CF callable that enforces the server-side counter before invoking `admin.auth().generatePasswordResetLink()`. Remove or clearly document the in-memory client-side counter as UI-only debounce, not a security control.

---

### M9 — resolveAlert audit entry writes to adminClaimLog instead of unified moderationAuditLog

**Status:** PENDING
**File changed:** `functions/adminModerationFunctions.js`
**Fix:** Replace the direct `adminClaimLog.add()` call with `logModerationAction({ actionType: 'alert_resolved', actorUid: uid, ... })`. Add `'alert_resolved'` to `VALID_ACTION_TYPES` in `auditLog.js`.

---

### M10 — isMinorAccount() performs a Firestore get() on every DM creation

**Status:** PENDING
**File changed:** `firestore.rules` (lines 205-207), Firebase Auth custom claims pipeline
**Fix:** Set `ageTier` as a Firebase Auth custom claim during age verification. Replace `get(/databases/$(database)/documents/users/$(uid)).data.ageTier` in `isMinorAccount()` with `request.auth.token.get('ageTier', '')` so the rules engine reads from the token without an extra Firestore read.

---

### L1 — providerRouter.js hardcodes JPEG MIME type in data-URI

**Status:** PENDING
**File changed:** `functions/moderation/providerRouter.js`
**Fix:** Accept an optional `mimeType` parameter in `callVisionModel`. Construct the data-URI prefix from the actual MIME type; fall back to `image/jpeg` only when unknown.

---

### L2 — snapshotHash uses non-deterministic JSON.stringify

**Status:** PENDING
**File changed:** `functions/moderation/legalHold.js` (line 53)
**Fix:** Replace `JSON.stringify` with `json-stable-stringify` (or equivalent deterministic serializer) before hashing. Add `json-stable-stringify` to `functions/package.json`.

---

### L3 — getLegalHoldEvidence has no role enforcement inside the function body

**Status:** PENDING
**File changed:** `functions/moderation/legalHold.js`
**Fix:** Add explicit role assertion: call `admin.auth().getUser(uid)` and verify the caller has `trust_safety_admin` or `legal_admin` custom claim before returning any evidence snapshot.

---

### L4 — minorProtection unknown-age path does not write a safetyAlert

**Status:** PENDING
**File changed:** `functions/safety/minorProtection.js`
**Fix:** When `validateMinorInteraction` returns `{ allowed: true, requiresReview: true }` for `sanctuary_invite` or `reply` content types with an unknown-age participant, write a `safetyAlerts` record so the review requirement is persisted.

---

### L5 — AmenAppCheckService.configure() is a stale dead-code path

**Status:** PENDING
**File changed:** `AMENAPP/AMENAPP/CommunityOS/Security/AmenAppCheckService.swift` (lines 74-79)
**Fix:** Either update `configure()` to use `AmenAppCheckProviderFactory` (matching the active `AppDelegate` path) or add a fatalError / deprecation warning so it cannot be called by mistake in future.

---

### L6 — textModeration.js rawResponse truncated at 500 chars

**Status:** PENDING
**File changed:** `functions/moderation/textModeration.js`
**Fix:** Write the full `categories` array as a separate field in the audit log entry, independent of the `rawResponse` truncation. The categories are already extracted — ensure they are not lost.

---

### L7 — setMinorFlag allows isMinor=false with minorAgeBand set

**Status:** PENDING
**File changed:** `functions/safety/minorProtection.js`
**Fix:** Add validation: if `isMinor === false` and `minorAgeBand` is non-null, reject the call with `invalid-argument`.

---

### L8 — providerRouter.js MAX_ATTEMPTS comment is self-contradictory

**Status:** PENDING
**File changed:** `functions/moderation/providerRouter.js`
**Fix:** Correct the comment to accurately document the retry budget (4 total attempts = 1 initial + 3 retries, or adjust the constant to match the comment).

---

### L9 — sendDailyNotificationDigest queries entire users collection without pagination

**Status:** PENDING
**File changed:** `functions/v2functions.js`
**Fix:** Add pagination using `limit(500)` + `startAfter(cursor)`. Store the cursor in Firestore between scheduled invocations to allow resumption.

---

### L10 — Legacy profilePhotos/ storage path allows direct client writes

**Status:** PENDING
**File changed:** `storage.rules`
**Fix:** Once the `profile_photos/` quarantine path is confirmed as the sole active path across all live client builds, change the `profilePhotos/{uid}/{photoId}` rule to `allow read, write: if false`. Set a migration deadline and communicate it to any external integrators.

---

## Deployment Order

Deploy in this exact sequence to avoid a window where code expects rules or secrets that are not yet live.

### 1. Set Firebase Secrets

```bash
# App Store Connect key (required before C4 deploy)
firebase functions:secrets:set APPLE_ASC_PRIVATE_KEY
firebase functions:secrets:set APPLE_ASC_KEY_ID

# Confirm NVIDIA and Anthropic keys are already set
firebase functions:secrets:access NVIDIA_API_KEY --project amen-5e359
firebase functions:secrets:access CLAUDE_API_KEY --project amen-5e359
```

### 2. Deploy Firestore Rules

Fixes H5 (witnesses write restriction) and H2 (age gate Firestore fallback), M10 (isMinorAccount token claim).

```bash
firebase deploy --only firestore:rules --project amen-5e359
```

### 3. Deploy Storage Rules

Fix L10 (legacy profilePhotos path).

```bash
firebase deploy --only storage:rules --project amen-5e359
```

### 4. Deploy Cloud Functions

Deploy in this sub-order because earlier functions are depended on by later ones.

```bash
# Step 4a: shared moderation modules (C1, C3, H4, L2, L3)
firebase deploy --only functions:escalation,functions:legalHold --project amen-5e359

# Step 4b: core moderation pipeline (C2, M6, M7, L1, L6, L8)
firebase deploy --only functions:moderatePost,functions:adminReviewPost,functions:onCommentUpdated,functions:providerRouter --project amen-5e359

# Step 4c: safety and minor protection (C1 consumer, H7, H8, L4, L7)
firebase deploy --only functions:blockMuteReport,functions:moderateDMMessage,functions:onMessageSent,functions:onUserProfileUpdated,functions:onTestimonyWritten,functions:minorProtection --project amen-5e359

# Step 4d: Berean AI endpoints (H1)
firebase deploy --only functions:bereanChat,functions:bereanMemory,functions:bereanCrisisDetect --project amen-5e359

# Step 4e: account and subscription (C4)
firebase deploy --only functions:processAccountSubscription --project amen-5e359

# Step 4f: appeals, audit, rate limits (M1, M2, M4, M5, M9)
firebase deploy --only functions:submitAppeal,functions:decideAppeal,functions:submitAuditEvent,functions:resolveAlert --project amen-5e359

# Step 4g: profile and password reset (H3, M8)
firebase deploy --only functions:publishPost,functions:sendPasswordReset --project amen-5e359

# Step 4h: full redeploy to deregister duplicate export (C3)
firebase deploy --only functions --project amen-5e359
```

### 5. Remote Config

```bash
# Enable age gate (H2) — do this BEFORE any public sign-up traffic
# In Firebase Console: Remote Config > ff_onboarding_v2 = true
# Or via CLI:
firebase remoteconfig:get --project amen-5e359 > rc.json
# Edit rc.json: set ff_onboarding_v2 default value to "true"
firebase remoteconfig:set --project amen-5e359 rc.json
```

### 6. Post-Deploy Verification

```bash
# Verify no duplicate exports remain
node -e "const f=require('./functions/index.js'); const keys=Object.keys(f); const dupes=keys.filter((k,i)=>keys.indexOf(k)!==i); if(dupes.length){console.error('DUPLICATE EXPORTS:',dupes);process.exit(1);}"

# Confirm stripeWebhook 2.js is deleted and not deployed
ls "functions/stripeWebhook 2.js" 2>/dev/null && echo "FILE STILL EXISTS - DELETE IT" || echo "OK"
firebase functions:list --project amen-5e359 | grep -i stripe
```

---

## Security Test Plan

The following 15 test cases must pass (with expected allow/deny) before the safety-hardening branch is merged to main.

| # | Surface | Test Case | Expected Result |
|---|---------|-----------|-----------------|
| T1 | blockMuteReport | File a user report with category `csam_suspected`. Assert `childSafetyEscalations/{docId}` document is created within 5 seconds. | ALLOW (escalation created) |
| T2 | blockMuteReport | File a `csam_suspected` report while `escalateChildSafety` intentionally throws. Assert the error propagates (not swallowed) and a dead-letter record exists. | DENY silent swallow |
| T3 | adminReviewPost | Submit an image post where `imageModeration` returns `cs_csam_suspected`. Assert `legalHolds/{holdId}` and `childSafetyEscalations/{docId}` are both created before the review decision is written. | ALLOW (both records created) |
| T4 | processAccountSubscription | Call with a fabricated `transactionId` and `tier: 'amen_pro'` without a valid App Store Server API response. Assert the entitlement is NOT written to Firestore. | DENY (no entitlement) |
| T5 | processAccountSubscription | Call with a valid verified `transactionId` matching `tier: 'amen_pro'`. Assert entitlement is written with the server-derived tier. | ALLOW (entitlement written) |
| T6 | bereanCrisisDetect | Call the callable from an unatteested client (no App Check token). Assert the call is rejected with `app-check-token-invalid`. | DENY |
| T7 | Firestore rules: one_users witnesses | Authenticated user B attempts to write a witness document under user A's `one_users/{uidA}/witnesses/{docId}` with `witnessUID: uidB`. Assert write succeeds. | ALLOW |
| T8 | Firestore rules: one_users witnesses | Authenticated user B attempts to write a witness document under user A's witnesses with `witnessUID: uidC` (a third party). Assert write is denied. | DENY |
| T9 | Firestore rules: one_users witnesses | Authenticated user B attempts to delete a witness document under user A's witnesses. Assert delete is denied. | DENY |
| T10 | blockMuteReport | File 11 reports in a single day from the same UID. Assert the 11th report is rejected with `rate-limit-exceeded`. | DENY (rate limit) |
| T11 | minorProtection + DM | User with no `ageTier` (social sign-in, age gate OFF simulation) attempts to DM an adult. With `ff_onboarding_v2 = true`, assert the DM creation fails or routes to age verification. | DENY or redirect |
| T12 | publishQuotePost | Call `publishQuotePost()` (old client path) with `visible: true` in the payload. Assert the Firestore rule or CF callable forces `visible: false` on the created document. | DENY visible:true |
| T13 | appeals | User submits 6 appeals in one day. Assert the 6th is rejected with `rate-limit-exceeded`. | DENY |
| T14 | detectGroomingRisk (DMs) | Send a message containing known grooming-pattern phrases (off-platform solicitation + secrecy language) in a conversation where the recipient is flagged as a minor. Assert a `safetyAlerts` document is created. | ALLOW (alert created) |
| T15 | legalHolds schema | Trigger a CSAM escalation via `blockMuteReport` and separately via `moderatePost` text path. Assert both resulting `legalHolds` documents contain all canonical schema fields (`holdId`, `caseId`, `contentSnapshot`, `snapshotHash`, `evidenceRefs`, `createdAt`, `status`) with no schema divergence. | ALLOW (canonical schema) |

---

## Rollback Plan

### Rollback Trigger Criteria

Initiate rollback if any of the following are observed within 1 hour of deployment:

- P99 latency on `moderatePost` exceeds 10 seconds (circuit breaker or retry regression).
- `childSafetyEscalations` collection error rate exceeds 0.1% (C1 fix regression).
- `processAccountSubscription` error rate exceeds 5% (C4 App Store API integration failure).
- Any `legalHolds` document written with missing `snapshotHash` field (H4 regression).
- Firebase Functions error rate increases more than 3x baseline.

### Rollback Steps

#### Step 1 — Revert Cloud Functions to the previous revision

```bash
# List recent versions to find the last good deployment tag
firebase functions:list --project amen-5e359

# Revert by redeploying from the last known-good git tag
git checkout <last-good-tag>
firebase deploy --only functions --project amen-5e359
```

#### Step 2 — Revert Firestore Rules

```bash
git checkout <last-good-tag> -- firestore.rules
firebase deploy --only firestore:rules --project amen-5e359
```

#### Step 3 — Revert Storage Rules

```bash
git checkout <last-good-tag> -- storage.rules
firebase deploy --only storage:rules --project amen-5e359
```

#### Step 4 — Revert Remote Config

```bash
# In Firebase Console: Remote Config > Rollback to previous version
# Or reset ff_onboarding_v2 to false if the age gate causes sign-up failures
firebase remoteconfig:rollback --project amen-5e359 --version-number <previous-version>
```

#### Step 5 — Secrets

Secrets cannot be easily rolled back. If `APPLE_ASC_PRIVATE_KEY` causes issues:

```bash
# Disable processAccountSubscription temporarily
firebase functions:delete processAccountSubscription --force --project amen-5e359
# Re-deploy the previous version of accountSubscriptionFunctions.js without the ASC call
```

#### Step 6 — Notify On-Call

After any rollback, page the on-call engineer and file an incident report in the audit log. Specifically note:
- Whether any `childSafetyEscalations` records were lost during the rollback window.
- Whether any `legalHolds` records are in an inconsistent state.
- Whether any `processAccountSubscription` calls during the window granted unverified entitlements.

### Pre-Deploy Snapshot Checklist

Before deploying, capture:

```bash
# Snapshot current function versions for reference
firebase functions:list --project amen-5e359 > deploy-snapshot-$(date +%Y%m%d-%H%M).txt

# Snapshot current Firestore rules
firebase firestore:rules:list --project amen-5e359

# Record the current git SHA
git rev-parse HEAD >> deploy-snapshot-$(date +%Y%m%d-%H%M).txt
```

---

## Open Questions (Must Resolve Before Launch)

1. **NCMEC SLA (OPEN-5):** What is the mandatory reporting SLA for CSAM escalations? The `reportToNcmec` stub must not be unblocked until a compliance-approved submission flow and SLA timer are in place.
2. **COPPA/KOSA jurisdiction (OPEN-1):** Is the EU GDPR-K age threshold 13 or 16? This determines whether `isMinorAccount()` must block all EU users under 16.
3. **Guardian consent model (OPEN-2):** Can guardians read all their minor's DMs, or only safety alerts? This affects the consent record schema.
4. **App Check Console enforcement:** Has the Firebase Console App Check enforcement toggle been enabled for `amen-5e359`? If not, `enforceAppCheck: true` on Cloud Functions is a no-op.
5. **NCMEC reporting decision:** Has legal/compliance reviewed the automated submission flow? What is the go/no-go criterion for replacing the stub with the live NCMEC API call?
6. **Spaces UGC coverage:** Spaces-specific post collections are not covered by `moderatePost.js`. Is this an accepted gap or must a dedicated Spaces moderation trigger be built before launch?
7. **stripeWebhook 2.js live deployment:** Has the legacy duplicate been deployed to any environment? If so, subscription entitlements for those events need an audit for double-writes.
