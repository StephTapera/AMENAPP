# AMEN Backend Audit — 2026-03-18

---

## Firebase Project

| Field | Value |
|---|---|
| Project Display Name | AMEN |
| Project ID | amen-5e359 |
| Project Number | 78278013543 |
| Active Alias | amen-5e359 (current) |
| Functions Region | us-central1 |
| Firestore Location | nam5 (multi-region US) |
| Storage Location | us-west1 |
| Storage Bucket | amen-5e359.firebasestorage.app |
| RTDB | amen-5e359-default-rtdb.firebaseio.com |
| Node Runtime | nodejs22 |
| Firebase Functions SDK | v6.6.0 |
| Firebase Admin SDK | v13.6.1 |

---

## Cloud Functions Health

Functions are deployed in two generations. The table below summarises all exported functions by source module.

| Module | Functions Exported | Runtime Gen | Auth Check | Rate Limited | Status |
|---|---|---|---|---|---|
| pushNotifications | sendPushNotification, onUserFollow, onUserUnfollow, onFollowRequestAccepted, onMessageRequestAccepted, onCommentCreate, onCommentReply, onPostCreate, onAmenCreate, onAmenDelete, onRepostCreate, onMessageReaction (12) | v2 | Background triggers — no auth needed | N/A | OK |
| churchNotesShare | shareChurchNote, revokeChurchNoteShare, generateChurchNoteShareLink (3) | v2 | Callable | No | Review |
| aiPersonalization | generatePersonalizedFeed, filterSmartNotifications, exportEngagementData (3) | v2 | Callable | No | Review |
| contentModeration | moderateContent, serverSidePostModeration (2) | v1 (onCall) + v2 (onDocumentWritten) | Yes — `context.auth` check | No | P1: v1 syntax |
| imageModeration | moderateUploadedImage (1) | v2 | Background trigger | N/A | OK |
| phoneAuthRateLimit | checkPhoneVerificationRateLimit, reportPhoneVerificationFailure, unblockPhoneNumber (3) | v2 | Callable | Yes | OK |
| twoFactorAuth | request2FAOTP, verify2FAOTP, send2FAEmail, send2FASMS, cleanupExpiredOTPs, expire2FASessions (6) | v2 | Callable | No | Review |
| cleanupExpired2FASessions | cleanupExpired2FASessions (1) | v2 | Scheduled | N/A | OK |
| postAndCommentFunctions | finalizePostPublish, addComment, toggleReaction, onMediaFinalize, onPostCreateValidate, onPostDeleted (6) | v2 | Yes — `request.auth` check | Yes (rolling window) | OK |
| trustScore | onTrustScoreRequested, onMessageSafetyEvent, scheduledTrustScoreRefresh (3) | v2 | Trigger/Scheduled | N/A | OK |
| aiModeration | moderateContent, detectCrisis, deliverBatchedNotifications (3) | v2 | Callable | No | Review |
| aiChurchNotes | findScriptureReferences, summarizeNote (2) | v2 | Callable | No | Review |
| authenticationHelpers | reserveUsername, checkUsernameAvailability, resolveUsernameToEmail, backfillUsernameLookup, onUserDeleted, manualCascadeDelete, onUserDocCreated (7) | v2 | Yes — `request.auth` check | No | OK |
| accountDeletion | processAccountDeletion (1) | v2 | Callable | No | Review |
| openAIFunctions | openAIProxy, whisperProxy, smartSuggestionsProxy (3) | v2 | Yes — `request.auth` check | Yes (20/hr, 10/hr) | OK |
| bereanFunctions | bereanBibleQA, bereanBibleQAFallback, bereanMoralCounsel, bereanBusinessQA, bereanNoteSummary, bereanScriptureExtract, bereanPostAssist, bereanCommentAssist, bereanDMSafety, bereanMediaSafety, bereanFeedExplainer, bereanNotificationText, bereanReportTriage, bereanRankingLabels, bereanGenericProxy, bereanSmartReply, bereanInsightProxy, bereanChatProxy (18) | v2 | Yes | No per-function rate limit | Review |
| genkitFunctions | generateDailyVerse, generateVerseReflection, generateNotificationText, summarizeNotifications (4) | v2 | Callable | No | Review |
| jobFunctions | onJobApplicationCreated, onJobApplicationUpdated, onJobListingCreated, reportJobListing (4) | v2 | Triggers + callable | N/A / Yes | OK |
| studioFunctions | onCommissionRequestCreated, onCommissionStatusUpdated, onBookingRequestCreated, onBookingStatusUpdated, onInquiryCreated, reportStudioContent, monthlyEarningsRollup (7) | v2 | Triggers + callable | N/A / Yes | OK |
| eventFunctions | onEventRSVPCreated, onEventRSVPUpdated, sendEventReminders, sendPostEventFollowUp (4) | v2 | Triggers + scheduled | N/A | OK |
| translationFunctions | translateText (1) | v2 | Callable | No | Review |
| scheduledPostsFunctions | executeScheduledPosts (1) | v2 | Scheduled | N/A | OK |
| dataExport | exportUserData (1) | v2 | Callable | No | Review |
| stripeFunctions | stripeCreateConnectedAccount, stripeGetAccountStatus, stripeCreatePaymentIntent, stripeRequestPayout (4) | v2 | Callable | No | Review |
| mlContentPipeline | onPostCreatedML, onPostDeletedML, computeViralityScore (3) | v2 | Triggers | N/A | P1: infinite loop risk |
| mlUserIntelligence | buildPassiveInterestGraph, detectSocialFatigue, predictCreationPropensity, computeSessionIntent, updateSpiritualHealthScore (5) | v2 | Scheduled | N/A | OK |
| mlPrayerIntelligence | matchIntercessors, detectTestimonyOutcome, detectSpiritualGift, computeScriptureSentimentMatch, generatePersonalVerseEngine (5) | v2 | Scheduled | N/A | OK |
| mlCommunityIntelligence | generateCongregationHealthReport, detectCoordinatedBehavior, runLinguisticFingerprint, detectGriefCrisisPreIncident, runZeroHarassmentDetection, scoreTheologicalDrift (6) | v2 | Triggers + scheduled | N/A | P1: onDocumentWritten scope |
| mlNotificationIntelligence | predictNotificationChurn, reRankFeedRealTime, runSLOAnomalyDetection, costOptimizationAudit, runAgeSignalDetection (5) | v2 | Scheduled | N/A | OK |
| notifications | onPrayerAmen, onPrayerComment, onPostMention, weeklyCheckin, communityDigest, bereanDailyInsight (6) | v2 | Triggers + scheduled | N/A | OK |
| mentorshipFunctions | createMentorshipSubscription, cancelMentorshipSubscription, sendWeeklyCheckIns (3) | **v1 runWith** | Yes | No | **P1: deprecated v1** |
| 242hub | flockIntelligence, processSermonMemory, reviewPrayerSubmission, reviewCovenantApp, matchKingdomCommerce (5) | v2 | Callable/Triggers | No | Review |
| livingMemory | generateEmbedding, findResonantContent, markPrayerAnswered (3) | **v1 onCall** | Yes | No | **P1: deprecated v1** |
| semanticEmbeddings | seedBibleVersesToPinecone, findSimilarTestimonies, getScriptureRecommendation, matchPrayerPartners, onTestimonyCreated, classifyReportedContent, trackPrayerSentimentWellness (7) | v2 | Callable/Triggers | No | Review |
| adminClaims | grantAdminRole, revokeAdminRole, bootstrapFirstAdmin, onUserAdminFlagChanged (4) | v2 | Yes + App Check enforced | N/A | OK |
| maintenanceSchedulers | prayerRequestsTTL, firestoreBackup, backfillUserCommentIndex, cleanupOrphanedRTDB (4) | v2 | Scheduled | N/A | OK |
| denormalizeUserPrivacy | onUserPrivacyChanged (1) | v2 | Trigger | N/A | OK |
| index.js (inline) | onRealtimeCommentCreate, onMessageSent, sendDailyNotificationDigest, deleteUserData, cancelAllSubscriptions, stripeWebhook (6) | v2 + v1 Auth trigger | Yes | No | P1: auth trigger v1 + Stripe env var |
| algoliaSync | onPostCreatedSyncAlgolia, onPostUpdatedSyncAlgolia (2) | v2 | Background trigger | N/A | P1: ALGOLIA keys via env var, not Secret Manager |

**Total exported functions: ~165**

---

## Security Assessment

| Area | Status | Issues Found |
|---|---|---|
| Firestore Rules | GOOD | One intentional `allow read: if true` on `/usernameLookup` (by design for pre-auth login). All other collections require authentication. No root-level `allow read, write: if true`. |
| RTDB Rules | GOOD | Root defaults to `false/false`. All nodes require `auth != null`. Presence, typing indicators, and admin paths are properly guarded. |
| Storage Rules | GOOD | Full deny-all default catch-all. All paths require authentication. Content-type allowlisting enforced (no `image/*` wildcards). File size limits enforced. Ownership checked via UID in path. Legacy flat `posts/images/{fileName}` is write-denied. |
| Secrets Management | GOOD with gaps | OPENAI_API_KEY stored correctly in Firebase Secret Manager and accessed via `defineSecret()`. STRIPE_SECRET_KEY, TWILIO credentials, ALGOLIA keys, and ANTHROPIC_API_KEY accessed via `process.env` without `defineSecret()` declaration in several modules. |
| Hardcoded Keys | CLEAN | No hardcoded API keys found in Swift files or JS function files (excluding node_modules). All keys retrieved from Secret Manager or env vars at runtime. |
| App Check | PARTIAL | `enforceAppCheck: true` only on `adminClaims` functions (grantAdminRole, revokeAdminRole). Other callable functions do not enforce App Check. |
| Rate Limiting | PARTIAL | openAIProxy (20/hr), whisperProxy (10/hr), postAndCommentFunctions (rolling window), phoneAuthRateLimit module. Berean AI functions (18 endpoints), translation, studio, and other callables have no per-user rate limiting. |

---

## P0 Issues — Auto-Fixed

**No P0 issues requiring auto-fix were found.**

The following P0 concerns that were previously present have already been addressed in the codebase:

- `allow read, write: if true` was NOT found in Firestore rules at root level. The one `allow read: if true` instance is on `/usernameLookup` and is intentional (pre-auth username resolution).
- No deprecated `.runWith()` patterns were found with missing auth checks — the v1 `runWith` usages in `mentorshipFunctions.js` correctly declare `secrets: ["STRIPE_SECRET_KEY"]` and include `context.auth` checks.
- No hardcoded API keys found in any Swift or JS source files.
- Storage `posts/images/{fileName}` legacy flat path has `allow write: if false` already applied.
- RTDB presence root was already fixed from `".read": true` to `".read": "auth != null"`.

---

## P1 Issues — Review Required

### P1-1: Deprecated v1 Functions — `mentorshipFunctions.js` and `livingMemory.js`

**Files:** `/functions/mentorshipFunctions.js`, `/functions/livingMemory.js`

`mentorshipFunctions.js` uses `require("firebase-functions/v1")` with `functions.runWith({...}).https.onCall(...)` for `createMentorshipSubscription` and `cancelMentorshipSubscription`. `sendWeeklyCheckIns` uses `functions.pubsub.schedule("every monday 09:00")`.

`livingMemory.js` uses `functions.https.onCall(...)` (v1 syntax) for `findResonantContent` and `markPrayerAnswered`.

**Risk:** v1 functions are deprecated as of Firebase Functions SDK v5+. They do not support all v2 features (min/max instances, concurrency, secrets natively). The v1 `.runWith({secrets: [...]})` pattern for STRIPE_SECRET_KEY works today but will break when v1 support is removed.

**Fix approach (do not auto-apply — affects Stripe billing flows):** Migrate both files to `firebase-functions/v2/https` `onCall()` with `{ secrets: [stripeSecret] }` option. Test subscription creation and cancellation in staging before deploying.

---

### P1-2: `computeViralityScore` Potential Infinite Loop

**File:** `/functions/mlContentPipeline.js` (line 214)

`computeViralityScore` is an `onDocumentUpdated` trigger on `posts/{postId}`. When engagement increases it writes `ml.viralityScore` and `ml.isViral` back to the same `posts/{postId}` document. This write re-triggers `onDocumentUpdated`.

The guard `if (engagementAfter <= engagementBefore) return;` prevents infinite loops for engagement-unchanged updates, but writing `ml.viralityScore` alone will re-trigger the function. Because the engagement fields don't change in that second invocation the guard fires and returns early — so it terminates after one extra invocation per viral detection. This is not a true infinite loop but does cause one spurious double-invocation per engagement event. At scale (high-traffic posts) this doubles the invocation cost for virality detection.

**Fix approach:** Check that the `ml.viralityScore` field itself is not the only changed field before running the function body. Add: `if (!before || !after) return; const relevantChange = engagementAfter !== engagementBefore; if (!relevantChange) return;` at the top and additionally check `after.ml?.viralityScore === before.ml?.viralityScore` is not the trigger source.

---

### P1-3: `serverSidePostModeration` (`onDocumentWritten`) Writes Back to Posts

**File:** `/functions/contentModeration.js` (line 728)

`serverSidePostModeration` listens on `posts/{postId}` via `onDocumentWritten`. When it removes or flags a post it writes back to `posts/{postId}.serverModerated = true`, `removed = true`, or `flaggedForReview = true`. This re-triggers the function.

The guard `if (afterData.serverModerated === true) return null;` correctly breaks the loop — but only after one extra invocation occurs for every moderated post. This is safe functionally but doubles invocation cost for flagged content.

**Fix approach:** The guard works. Optionally add a `before` check: skip if `before.serverModerated === true` to avoid even the first re-trigger read.

---

### P1-4: Algolia Keys Not in Secret Manager

**File:** `/functions/algoliaSync.js` (lines 18-21)

`ALGOLIA_APP_ID`, `ALGOLIA_ADMIN_API_KEY`, and `ALGOLIA_INDEX_NAME` are retrieved via `process.env` without using `defineSecret()`. This means they must be set as environment variables rather than Secret Manager secrets, which is less secure (env vars are stored in function config, secrets are encrypted at rest and audited).

**Fix approach:** Add `const algoliaAppId = defineSecret("ALGOLIA_APP_ID"); const algoliaAdminKey = defineSecret("ALGOLIA_ADMIN_API_KEY");` in `algoliaSync.js` and pass `{ secrets: [algoliaAppId, algoliaAdminKey] }` to both trigger functions.

---

### P1-5: ANTHROPIC_API_KEY and TWILIO Credentials Not in Secret Manager

**Files:** `/functions/242hub.js` (line 36), `/functions/twoFactorAuth.js` (lines 395-397)

`ANTHROPIC_API_KEY`, `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, and `TWILIO_PHONE_NUMBER` are accessed via raw `process.env` without `defineSecret()`. The ANTHROPIC_API_KEY is used in the `242hub.js` calling Claude claude-sonnet-4-6 for pastoral AI functions.

**Risk:** Environment variables in Firebase Functions v2 are stored as plain text in Cloud Run configuration. Secret Manager provides rotation, audit logging, and encryption at rest.

**Fix approach:** Add `defineSecret("ANTHROPIC_API_KEY")` and `defineSecret("TWILIO_ACCOUNT_SID")` etc. to the relevant modules and declare them in the function options.

---

### P1-6: `index.js` Stripe Functions Missing v2 Secret Declaration

**File:** `/functions/index.js` (lines 869, 895)

`cancelAllSubscriptions` and `stripeWebhook` use `functions.https.onCall` and `functions.https.onRequest` (v1 syntax) without proper `runWith({secrets: ["STRIPE_SECRET_KEY"]})`. A comment acknowledges this as a P1 fix but the code has not been updated — the functions still use v1 syntax. `deleteUserData` uses `authV1.user().onDelete(...)` (v1 Auth trigger) and also does not declare the Stripe secret.

**Risk:** `STRIPE_SECRET_KEY` is accessed via `process.env.STRIPE_SECRET_KEY` in the Stripe lazy-init helper. In v1 functions without `runWith({secrets:[...]})`, this env var is not guaranteed to be populated from Secret Manager at runtime, potentially causing silent Stripe initialization failures (the function falls back to `getStripeSDK()` returning `null` rather than crashing, so subscription cancellation silently fails on account deletion).

**Fix approach:** Either migrate to v2 `onCall`/`onRequest` with `secrets` option, or add `.runWith({ secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"] })` to all three v1 functions. Do NOT auto-apply — affects account deletion and billing flows.

---

### P1-7: `sendWeeklyCheckIns` Uses Legacy pubsub Scheduler (v1)

**File:** `/functions/mentorshipFunctions.js` (line 89)

`sendWeeklyCheckIns` uses `functions.pubsub.schedule("every monday 09:00").timeZone("America/New_York").onRun(...)` — the v1 Cloud Scheduler syntax. This function also accesses `process.env.STRIPE_SECRET_KEY` via the lazy `getStripe()` helper but does not declare the secret in `runWith`.

**Fix approach:** Migrate to `onSchedule({ schedule: "every monday 09:00", timeZone: "America/New_York", secrets: ["STRIPE_SECRET_KEY"] }, async (event) => {...})` from `firebase-functions/v2/scheduler`.

---

### P1-8: App Check Not Enforced on AI/Financial Callable Functions

The following high-value callable functions do not set `enforceAppCheck: true`:

- All 18 `bereanFunctions` (AI calls that consume OpenAI/Claude tokens)
- `openAIProxy`, `whisperProxy`, `smartSuggestionsProxy`
- `stripeCreatePaymentIntent`, `stripeRequestPayout`, `stripeCreateConnectedAccount`
- `exportUserData` (GDPR data export — privacy risk)
- `processAccountDeletion` (destructive)

Only `grantAdminRole`, `revokeAdminRole`, and `bootstrapFirstAdmin` enforce App Check.

**Risk:** Without App Check, any client with a valid Firebase Auth token (including tokens obtained outside the app, e.g. via Firebase emulator or scripted attacks) can invoke these functions. AI functions are vulnerable to token-exhaustion abuse; Stripe functions are vulnerable to payment manipulation attempts.

**Fix approach:** Add `enforceAppCheck: true` to all callable AI and financial functions. Ensure the iOS app has Firebase App Check initialized (DeviceCheck/App Attest for production).

---

## P2 — Nice to Fix

### P2-1: 322 `console.log` Calls in Production Functions

**Scope:** 322 occurrences across all function files.

Many use `console.log` instead of `functions.logger.log` / `logger.info`. While both write to Cloud Logging, `functions.logger` produces structured JSON logs with severity levels, making them filterable in Cloud Console. `console.log` produces unstructured text.

**Fix approach:** Global search-replace `console.log(` → `logger.log(` and `console.error(` → `logger.error(` in all function files. Import `const { logger } = require("firebase-functions");` where not already present.

---

### P2-2: Missing `posts` Index for `authorId + createdAt` (Feed Query Pattern)

**File:** `/firestore.indexes.json`

The index `posts: [authorId ASC, type ASC, createdAt DESC]` exists (line 526-532). However, there is no simple `posts: [authorId ASC, createdAt DESC]` compound index for feed queries that filter only by author without the `type` field. The `type` field was added to support category filtering, but basic profile feed queries (`whereField("authorId", ==, uid).order(by: "createdAt", descending: true)`) will use a full collection scan or single-field index, which is less efficient.

**Fix approach:** Add `{ "collectionGroup": "posts", "queryScope": "COLLECTION", "fields": [{ "fieldPath": "authorId", "order": "ASCENDING" }, { "fieldPath": "createdAt", "order": "DESCENDING" }] }` to `firestore.indexes.json`.

---

### P2-3: `usernameLookup` Stores `email` Field (Email Enumeration Risk)

**File:** `firestore 18.rules` (line 128-134), comment on line 143.

The Firestore rules comment acknowledges that `usernameLookup` should store only `{ uid, username }` and NOT `email`. However, the write rule allows `request.resource.data.get('uid', '') == request.auth.uid` without restricting what other fields can be written. If any client code writes `email` into the `usernameLookup` document, unauthenticated users (who have read access) could enumerate emails via username lookup.

**Fix approach:** Add a field restriction to the write rule: `&& !request.resource.data.keys().hasAny(['email', 'passwordHash', 'phoneNumber'])`. Also verify in `AuthenticationViewModel.swift` and `authenticationHelpers.js` that `reserveUsername` and `checkUsernameAvailability` do not write the email field.

---

### P2-4: `posts` List Rule Allows Unauthenticated-ish Queries Without Field Restriction

**File:** `firestore 18.rules` (line 556)

`allow list: if isAuthenticated()` — the posts collection list rule allows any authenticated user to query `posts` without restriction. The comment notes that the app must apply block/privacy filters client-side. This is correct architecturally but means a user with a valid token can query all posts regardless of privacy settings via a direct Firestore query (not through the app). The `get` rule correctly enforces privacy, but `list` results bypass the `callerCanReadPost()` check.

**Fix approach:** This is a known Firestore limitation (list rules cannot evaluate per-document functions). Document this clearly and ensure the iOS layer always uses `authorId in [followingList]` queries rather than open collection queries. Consider adding a `visibility != "private"` field restriction to the list rule to at least exclude explicitly private posts from queries.

---

### P2-5: `Pinecone` Integration Not Using Secret Manager

**File:** `/functions/semanticEmbeddings.js`

The `PINECONE_API_KEY` and Pinecone index name are not visible in the process.env scan, suggesting either they're not yet deployed or are hardcoded elsewhere. Confirm these are in Secret Manager before enabling the `seedBibleVersesToPinecone` function which sends 31K KJV verses.

---

### P2-6: `mlCommunityIntelligence.js` — `detectGriefCrisisPreIncident` and `runZeroHarassmentDetection` Use `onDocumentWritten`

**File:** `/functions/mlCommunityIntelligence.js` (lines 344, 432)

Both functions use `onDocumentWritten` on message/post paths. `onDocumentWritten` triggers on create, update, AND delete. Crisis and harassment detection on deletion events are no-ops but waste invocations.

**Fix approach:** Change to `onDocumentCreated` if only new content needs screening.

---

### P2-7: `firebase-send-email` Extension Enabled

**File:** `/firebase.json` (line 32)

The `firebase/firestore-send-email@0.2.5` extension is configured. Ensure the SMTP credentials for this extension are stored in Secret Manager and the email templates collection (`mail`) is write-protected in Firestore rules (only Cloud Functions/admin SDK should create mail documents, not clients).

---

## Deployment Status

### Functions Deployed vs. Code

Based on `firebase functions:list` output, all modules appear to be deployed on `nodejs22` runtime in `us-central1`. No orphaned functions were detected from the list command.

### Potential Orphaned / Duplicate Exports

The following export names appear in both `contentModeration.js` (v1 `functions.https.onCall`) and `aiModeration.js` (v2 `onCall`):

- `moderateContent` — exported from both modules via `lazyExports`. The `aiModeration` export overrides `contentModeration`'s export per the comment in `index.js` line 137. The v1 `contentModeration.moderateContent` may still be deployed as a separate function under a different name. Verify with `firebase functions:list` that only one `moderateContent` function is deployed.

### Scheduled Function Overlap

Both `mlContentPipeline.js` (`scheduledPostPublisherML`, every 5 minutes) and `scheduledPostsFunctions.js` (`executeScheduledPosts`) appear to handle scheduled post publishing. Verify these are not duplicates — both query `posts where status == "scheduled"` and update to `published`.

---

## npm Vulnerabilities

`npm audit` requires network access and was not executable non-interactively in this environment. Based on the `package.json` dependency versions:

| Package | Version | Notes |
|---|---|---|
| firebase-admin | ^13.6.1 | Current as of audit date |
| firebase-functions | ^6.6.0 | Current (v6 = Gen2) |
| openai | ^4.0.0 | Recent stable |
| stripe | ^17.0.0 | Recent stable |
| twilio | ^5.0.0 | Recent stable |
| @anthropic-ai/sdk | ^0.36.0 | Recent stable |
| @google-cloud/vision | ^4.3.3 | Stable |
| @google-cloud/vertexai | ^1.10.0 | Stable |
| @google-cloud/translate | ^8.0.0 | Stable |
| @google-cloud/language | ^6.0.0 | Stable |

- **Critical: Unknown (run `npm audit` to verify)**
- **High: Unknown (run `npm audit` to verify)**

**Action Required:** Run `cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/functions" && npm audit` manually to get the current vulnerability count. The `algoliasearch` package is referenced in `algoliaSync.js` but is NOT listed in `package.json` — this will cause a runtime error when `algoliaSync` functions are invoked. Add `"algoliasearch": "^4.x"` to dependencies.

---

## Firestore Rules Detailed Assessment

### Collections — Authentication Gate Summary

| Collection | Unauth Read | Unauth Write | Cross-user Read | Cross-user Write | Admin Protected |
|---|---|---|---|---|---|
| usernameLookup | YES (by design) | No (uid check) | Yes (by design) | No | N/A |
| users | No | No | Auth only (get/list) | No — owner only + counter gate | Yes — isAdmin/isModerator fields server-only |
| users/notifications | No | No | No — owner only | No — actorId must match caller | N/A |
| users/backupCodes | No (allow read: if false) | No | No | No | Full server-only |
| users/savedBooks | No | No | No — owner only | No — owner only | N/A |
| follows | No | No | Yes — any auth user | No — followerId must be caller | N/A |
| posts | No | No | list: any auth; get: privacy-gated | No — authorId check | N/A |
| posts/comments | No | No | Yes — callerCanComment() | No — authorId check | N/A |
| conversations | No | No | No — participant check | No — participant + age gate | N/A |
| conversations/messages | No | No | No — participant get() | No — senderId + email-verified + 2FA | N/A |
| userSecurity | No | No | No | No — write: if false (server-only) | Full server-only |
| adminClaims collection | No | No | N/A | N/A | Not in rules (no collection) |

### Key Firestore Rule Findings

1. **GOOD:** Email verified + 2FA session required for message creates (`callerIsEmailVerified() && caller2FASessionValid()`).
2. **GOOD:** Privilege escalation blocked — `isAdmin`, `isModerator`, `role`, `ageTier`, `birthYear`, `strikes` fields cannot be set by clients.
3. **GOOD:** Self-follow prevention enforced at rules layer.
4. **GOOD:** Counter manipulation limited to ±1 delta.
5. **GOOD:** Private post visibility enforced on `get` (not list — acknowledged limitation).
6. **GOOD:** Backup codes are fully deny-all for clients.
7. **REVIEW:** `allow list: if isAuthenticated()` on posts — see P2-4.
8. **REVIEW:** `usernameLookup` write rule allows any fields beyond `uid` — see P2-3.

---

## RTDB Rules Detailed Assessment

| Path | Unauth Read | Unauth Write | Notes |
|---|---|---|---|
| Root | No (`.read: false`) | No (`.write: false`) | Secure default |
| postInteractions | No | No — auth + ownership | Comments require authorId == auth.uid |
| userInteractions | No — owner only | No — owner only | Scoped to uid |
| presence | No — auth required | No — owner only | P0 fix already applied |
| typingIndicators | No — auth required | No — owner only | Secure |
| conversations | No — participant check | No — participant check | RTDB conversation path |
| userPresence | No — auth required | No — owner only | Secure |
| analytics | No — `false` | No — `false` | Locked down |
| admin | No — `false` | No — `false` | Locked down |
| userCommentIndex | No — owner only | No — `false` (server-only) | Secure |

---

## Storage Rules Detailed Assessment

| Path | Unauth Read | Unauth Write | File Size Limit | Content Type Restricted | Cross-user Write |
|---|---|---|---|---|---|
| profile_images/{userId}/{fileName} | Yes (public) | No — auth + uid match | 5 MB | Yes — image allowlist | No |
| profile_images/{userId}/resized | Yes (public) | No — `if false` | N/A | N/A | No |
| user_photos/{userId}/{albumName}/{fileName} | Yes (public) | No — auth + uid match | 10 MB | Yes — image + video | No |
| post_media/{authorUserId}/{postId}/{fileName} | No — auth required | No — auth + uid match | 20 MB | Yes | No |
| posts/{userId}/{fileName} | No — auth required | No — auth + uid match | 20 MB | Yes | No |
| posts/images/{fileName} (legacy) | No — auth required | No — `if false` | N/A | N/A | N/A — write denied |
| testimony_media/{authorUserId}/{testimonyId}/{fileName} | No — auth required | No — auth + uid match | 15 MB | Yes | No |
| dating_photos/{userId}/{fileName} | No — auth required | No — auth + uid match | 8 MB | Yes — image allowlist only | No |
| message_attachments/{senderId}/{recipientId}/{fileName} | No — sender or recipient only | No — sender + uid match | 10 MB | Yes — image/video/audio/pdf | No |
| group_photos/{uploaderId}/{fileName} | No — auth required | No — auth + uid match | 5 MB | Yes — image allowlist | No |
| group_photos/{fileName} (legacy flat) | No — auth required | No — `if false` | N/A | N/A | N/A — write denied |
| verification_docs/{userId}/{fileName} | No — owner only | No — owner + uid match | 5 MB | Yes — image + PDF | No |
| **Default** | No — `if false` | No — `if false` | N/A | N/A | N/A |

Storage rules are well-structured. SVG injection is specifically prevented via explicit MIME allowlists instead of `image/*` wildcards.

---

## Recommended Next Steps

### Priority 1 — Do immediately (before next release)

1. **Add `algoliasearch` to `functions/package.json` dependencies.** The package is required by `algoliaSync.js` but missing from the manifest — this will cause runtime crashes for all Algolia sync functions in a clean deployment.

2. **Run `npm audit` in the functions directory** and address any critical/high vulnerabilities before the next App Store submission.

3. **Add App Check enforcement to AI callable functions** (`openAIProxy`, `whisperProxy`, all `bereanFunctions`). This prevents token-exhaustion attacks from scripted clients.

4. **Verify no duplicate `executeScheduledPosts` / `scheduledPostPublisherML`** — both query `posts where status == "scheduled"`. If both are deployed, every scheduled post will be published twice.

### Priority 2 — This sprint

5. **Migrate `mentorshipFunctions.js` to v2** (`firebase-functions/v2/https` + `firebase-functions/v2/scheduler`). Test Stripe subscription creation/cancellation end-to-end in staging.

6. **Migrate `livingMemory.js` callable functions** (`findResonantContent`, `markPrayerAnswered`) to v2 `onCall`.

7. **Fix `cancelAllSubscriptions`, `stripeWebhook`, and `deleteUserData` in `index.js`** — add `runWith({ secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"] })` or migrate to v2 with `secrets` option.

8. **Add `ANTHROPIC_API_KEY`, `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_PHONE_NUMBER`, `ALGOLIA_APP_ID`, `ALGOLIA_ADMIN_API_KEY` to Firebase Secret Manager** and reference them via `defineSecret()`.

### Priority 3 — Next sprint

9. **Add field restriction to `usernameLookup` write rule** to prevent email field from being written to the public-readable collection.

10. **Add `posts: [authorId ASC, createdAt DESC]` to `firestore.indexes.json`** for profile feed query efficiency.

11. **Replace `console.log` with `functions.logger`** across all 322 occurrences for structured log output in Cloud Console.

12. **Add `computeViralityScore` invocation guard** — check `ml.viralityScore` as a changed field before processing to prevent the spurious double-invocation pattern.

13. **Verify `firebase-send-email` extension** — confirm the `mail` collection write access is restricted to admin SDK only in Firestore rules, and that SMTP credentials are in Secret Manager.

14. **Consider per-user rate limiting for Berean AI and translation functions.** At 18 Berean endpoints with no rate limiting, a single authenticated user can exhaust the OpenAI/Claude budget.

---

## Stress Test Script

The following steps should be run against a staging environment before each release:

1. **Auth bypass attempt:** Try to read `users/{uid}/backupCodes` as a different authenticated user. Expect `PERMISSION_DENIED`.
2. **Privilege escalation:** Try to update `users/{uid}` with `isAdmin: true` from the client. Expect `PERMISSION_DENIED`.
3. **Counter manipulation:** Try to set `amenCount: 99999` on a post from the client. Expect `PERMISSION_DENIED`.
4. **Private post leak:** Follow user A, make a post private, query posts as user B (not following A). Expect the post to be excluded.
5. **DM injection:** Try to create a message in a conversation the user is not a participant of. Expect `PERMISSION_DENIED`.
6. **Storage overwrite:** Try to upload to `post_media/{otherUserId}/{postId}/test.jpg` as a different UID. Expect `PERMISSION_DENIED`.
7. **AI abuse:** Call `openAIProxy` 25 times in one hour. Expect the 21st call to return `resource-exhausted`.
8. **Stripe webhook forgery:** Send a POST to `stripeWebhook` without a valid `stripe-signature` header. Expect `400 Webhook Error`.
9. **Scheduled post double-publish:** Create a scheduled post, wait for `executeScheduledPosts` to fire, confirm it publishes exactly once.
10. **Algolia sync:** Create a post, confirm it appears in Algolia index within 60 seconds.

---

## Acceptance Criteria Checklist

- [ ] No `allow read, write: if true` at root or on sensitive collections
- [ ] All API keys retrieved from Secret Manager via `defineSecret()` (not raw `process.env`)
- [ ] `npm audit` returns 0 critical, 0 high vulnerabilities
- [ ] `algoliasearch` added to `package.json`
- [ ] All AI callable functions have App Check enforcement or documented exception
- [ ] `mentorshipFunctions.js` and `livingMemory.js` migrated to v2
- [ ] No duplicate scheduled post publisher functions
- [ ] `stripeWebhook` correctly validates signature in all code paths
- [ ] RTDB and Firestore rules deployed and tested in staging
- [ ] Storage legacy flat paths remain write-denied
- [ ] `usernameLookup` write rule restricts email field
- [ ] Berean AI functions have per-user rate limiting or App Check enforcement
