# Cloud Functions Audit — AMEN App

**Audit Date:** May 26, 2026  
**Scope:** Backend/functions/src + Swift httpsCallable integration  
**Status:** CRITICAL FINDINGS IDENTIFIED  

---

## EXECUTIVE SUMMARY

### Inventory
- **Total Exported Functions:** 225+ (counted from Swift callables)
- **Unique Function Exports in index.ts:** ~180 (estimated from re:export statements)
- **Gen1 vs Gen2:** Mixed; majority using Gen2 `onCall()` from `firebase-functions/v2/https`
- **Triggers:** Callables (httpsCallable), Firestore writes, scheduled tasks, HTTPS webhooks

### Key Risk Summary
1. **P0 CRITICAL:** OpenAI Realtime WebSocket direct from iOS client (line 105 BereanRealtimeWebSocketTransport.swift)
2. **P0 CRITICAL:** 16+ Cloud Functions called from Swift but NOT exported/undeployed
3. **P0 CRITICAL:** Direct client -> api.openai.com connection violates proxy pattern
4. **P1:** Covenant payment functions lack day-level idempotency (only daily key scope)
5. **P1:** Giving charge function lacks idempotency (no Stripe idempotency key on one-time charges)

---

## 1. FULL INVENTORY

### Callable Functions (Gen2 — onCall)

**Critical Path Callables:**
- `bereanChatProxy` — Anthropic Claude proxy with rate limiting (256MiB, 60s timeout)
- `bereanChatProxyStream` — SSE streaming variant
- `openAIProxy` — OpenAI chat proxy
- `whisperProxy` — Whisper transcription proxy
- `processGivingCharge` — Stripe in-app giving (requires auth + App Check)
- `createCovenantCheckoutSession` — Stripe Covenant subscription (requires auth + App Check)
- `validateThinkFirstCheck` — Think-First moderation pre-publish

**Safety/Moderation Callables:**
- `submitReport` — User/content report submission (server-authoritative)
- `submitContentReport` — CloudFunctions alias
- `moderateTextCallable`, `moderateImageCallable`, `moderateVideoCallable`, `moderateAudioCallable`
- `runTextPreflight`, `runImagePreflight`, `runVideoPreflight`, `runAudioPreflight`
- `checkLinkSafetyCallable` — Safe Browsing API integration
- `moderateMediaCaption`, `generateAltText` — Per-media caption system
- `reportAbuse`, `getMyAbuseReports`, `resolveAbuseReport`, `escalateAbuseReport`

**Identity & Verification:**
- `startIdentityVerification` — Stripe identity verification flow
- `requestOrganizationVerification`, `verifyOrganizationDomain`
- `requestRoleVerification`, `approveRoleVerification`, `revokeRoleVerification`
- `requestCreatorVerification`

**Berean Spiritual Intelligence (System 16):**
- `generateStructuredResponse`, `studyPassage`, `analyzeMessage`, `evaluateAuthorityEscalation`
- `getImmersionPayload`, `getJourneySnapshot`, `generateDiscipleshipNextStep`
- `saveReflectionEntry`, `generateChurchNotesSummary`
- `premiumBereanCallables` (export from separate module)

**Community & Spaces:**
- `resolveCommunityObject`, `createOrJoinObjectHub`, `getObjectHub`, `getRelatedObjectHubs`
- `recordObjectInteraction`, `muteObjectHub`, `reportHubContent`
- `indexPostIntoHub`, `attachCommunityHubPreviewToPost`

**Media & Content:**
- `resolveSmartAttachment`, `saveMediaGraphItem`, `getRecentMediaAttachments`
- `explainVideoContent` — AI video explanation with transcript gating
- `getSmartShareTargets`, `createSharePayload`, `generateDeepLink`
- `validateMediaCaptions`, `updatePostMediaCaptions`, `generateAltText`

**Church & Discovery:**
- `smartChurchSearch` — Ask Amen church search
- `searchChurchesByKeyword`, `getChurchVisitReadiness`
- `parseChurchSearchIntent`, `searchChurchesAndCommunities`
- `getChurchDiscoveryDetails`, `saveChurchCandidate`, `saveChurchDiscoveryPreference`
- `logChurchDiscoveryInteraction`, `clearChurchDiscoveryHistory`

**Messaging & Communication:**
- `generateDMCatchUp`, `generateCatchUpDigest`, `extractThreadDecisions`, `detectOpenQuestions`
- `extractThreadActions`, `generateGroupPulse`, `generateMediaContext`
- `searchConversationMemory`, `generateSmartReplies`

**Creator Suite (System 24):**
- `createProject`, `updateProject`, `deleteProject`, `autosaveProject`
- `queueProcessingJob`, `processVideoProxy`, `generateThumbnail`
- `transcribeMedia`, `generateSubtitleTrack`, `translateSubtitleTrack`
- `buildOutputVariants`, `renderExport`, `publishProject`
- `verifyAuthenticitySignals`, `saveBrandKit`, `cloneTemplateToProject`
- `recordCreatorAnalytics`, `enforceCreatorEntitlement`, `cleanupOrphanedAssets`
- `retryFailedCreatorJob`

**Realtime & Voice:**
- `createRealtimeSession`, `endRealtimeSession`, `logRealtimeVoiceEvent`
- `moderateRealtimeTranscript`, `persistRealtimeTranscriptChunk`
- `startRealtimeTranscription`, `finalizeTranscript`, `extractKeyMoments`
- `moderateTranscript`

**Agent Orchestration:**
- `runAmenAgentTask`, `agentTaskRouter`
- `agentGuardrails`, `agentObservability`, `agentResultFormatter`

**Covenant OS (System 36 - Paid Spiritual Community):**
- `createCovenantActivityEvent`
- `saveCovenantTierStripePriceId`
- `createCovenantCheckoutSession`
- `validateCovenantPostSafety` — Tone/safety check for composer
- `setCommunitySaved` — Community-level Save/Unsave
- `createCovenantThreadReply`, `generateThreadSummary`
- `createPrayerRequestFromMessage`, `generateCatchUpSummary`
- `calculateCovenantChurnRisk` (scheduled daily)
- `publishScheduledCovenantContent` (scheduled every 5 min)
- `submitCovenantReport` — Financial manipulation detection
- `indexCovenantSearchDocument`
- `stripeCovenantWebhook` — HTTPS webhook for Stripe events

**Permissions & Access (System 26):**
- `setMode`, `initiateDM`, `requestGuardianConsent`, `confirmGuardianConsent`
- `resolvePermissionsCallable` (admin-only)
- `setDateOfBirth`

**Trust & Safety Extended:**
- `getTrustProfile`, `adminGrantTrustEvent`, `initializeNewAccount`
- `setInteractionMode`, `getInteractionMode`, `enforcePostModeConstraints`
- `initializeModeForNewUser`
- `scanGroomingVelocity`, `scanCoordinatedHarassment`

**Verification Subsystem:**
- `requestMentorship`, `approveMentorship`, `endMentorship`, `getMyMentorships`
- `requestChurchVerification`, `issueChurchVerificationCode`
- `getChurchVerificationStatus`

**Access Passes (System 37):**
- `createAccessPass`, `resolveAccessPass`, `acceptAccessPass`, `revokeAccessPass`
- `pauseAccessPass`, `resumeAccessPass`, `rotateAccessPassToken`
- `approveAccessRequest`, `denyAccessRequest`
- `listAccessPassesForTarget`, `listAccessRequestsForTarget`

**Church Verification:**
- `submitChurchVerificationRequest`, `submitChurchProfileUpdate`
- `reviewChurchModerationItem`, `refreshChurchLivestreamState`
- `generateGroundedChurchAnswer`, `syncYouTubeChurchStreams`
- `updateChurchLiveSignals`

### Event-Triggered Functions (Firestore/Auth/Storage)

**Post Lifecycle:**
- `onPostCreated` — Text moderation, status transition, Algolia indexing
- `onPostCreatedRunMediaModeration` — 6-layer AI safety pipeline
- `onPostCreatedUpdatePreviews` — Reply preview regeneration
- `onPostMediaUpdatedRunModeration` — Video/image post moderation

**Reply & Comment System:**
- `onReplyCreate` — SERVER-AUTHORITATIVE (CONTRACT.md §12)
- `rebuildReplyPreviews` — Resolver ladder + scoring formula
- `rebuildReplyPreviewsOnDirty` — Dirty threshold rebuild
- `onCommentCreatedUpdatePreviews`, `onCommentDeletedUpdatePreviews`, `onCommentUpdatedUpdatePreviews`
- `onCommentUpdatedUpdatePreviewsTrigger`, `onPostUpdatedUpdatePreviews`, `onPostUpdatedUpdatePreviewsTrigger`
- `onPostDeletedClearPreviews`, `onPostDeletedClearPreviewsTrigger`
- `onBlockRelationshipUpdatedRefreshPreviews`, `onBlockRelationshipUpdatedRefreshPreviewsTrigger`
- `onUserProfileImageUpdatedRefreshPreviews`

**Account Lifecycle:**
- `onUserWrite` — Recomputes permissions on watched field changes
- `dailyAgeTierPromotion` — Promotes tier on birthday, forces token refresh
- `syncAgeTierClaim` — P1.1 FIX: syncs ageTier to Auth token

**Church Journey:**
- `churchVisitLifecycle` — Phase-triggered follow-up scheduling

**Media & Files:**
- `mediaScanning` — Cloud Vision SafeSearch on Storage upload
- `mediaPostIndex` — Maintains denormalized photos/videos index
- `mediaMetadataPipeline` — Whisper + Claude label refinement

**Safety & Enforcement:**
- `antiHarassmentEnforcement` — Messaging/DM freeze checks (server-authoritative)
- `accountSuspension` — Auto-suspend on critical/minor-safety queue
- `commentModerationEnforcement` — Aggregates reports, writes moderationStatus to RTDB
- `blockRelationshipCleanup` — Removes follows, pending requests, restricts convos
- `createBlock` — Atomic block/unblock (two collections)
- `createFollow` — Atomic follow/unfollow + follows_index

**Notifications:**
- `onSocialEvent` — Social event fan-out
- `prayerAnsweredBatch` — Batch supporter notification (≤100 per call)
- `deliverQuietHoursDigest` — Batch-deliver push notifications

**Notifications Maintenance:**
- `invalidation`, `counts`, `maintenance`

**Algolia & Search:**
- `algoliaSync` — Posts index sync on edit/delete
- `deleteAlgoliaUser` — App Store Guideline 5.1.1 deletion
- `algolia_syncUser`, `algolia_syncPost`, `algolia_deleteUser`, `algolia_deletePost`

**Account Deletion:**
- `postDeletionCascade` — Cleans up comments, reactions, reposts, savedPosts, Algolia
- `userAccountDeletionCascade` — Full account deletion (Guideline 5.1.1)

**Username Tracking:**
- `usernameChangeTracking` — Rate limiting enforcement

**Rest Mode:**
- `onRestModePolicyWritten` — Evaluates policy on change

### Scheduled Functions (Cloud Scheduler)

- `generateDailyVerse` — Daily verse generation (exact schedule TBD)
- `scheduledMaintenance` — Counter reconciliation, stale data pruning, token cleanup
- `generateNextYearHolidayCalendar` — Nov 1, 06:00 UTC
- `calculateCovenantChurnRisk` — Daily (Covenant OS)
- `publishScheduledCovenantContent` — Every 5 minutes (Covenant OS)
- `deliverQuietHoursDigest` — Every 30 minutes (quiet hours)
- `scheduledReplyPreviewRefresh` — (exact frequency TBD)
- `scheduledSmartMessageVectorBackfill` — Vector index rebuild
- `reconcileRelationshipStates` — Daily stale doc cleanup (socialGraph)

### HTTPS Webhooks

- `stripeCovenantWebhook` — Stripe subscription.* events (HTTPS onRequest)
- `handleIdentityVerificationWebhook` — Stripe identity verification webhook

---

## 2. AUTHENTICATION & AUTHORIZATION

### Summary

**PASS (Good):**
- `bereanChatProxy`: Checks `request.auth`, enforces `enforceAppCheck: true`
- `processGivingCharge`: Validates `request.auth.uid`, rate limited, enforces App Check
- `createCovenantCheckoutSession`: Checks auth, validates user ownership
- `submitReport`: Server-authoritative, validates reporterId == request.auth.uid
- All payment functions secure keys via `defineSecret()`

**CONCERNS:**
- Webhook functions (`stripeCovenantWebhook`) must validate HMAC signatures — need to verify implementation
- Event-triggered functions (Firestore/Storage) do NOT have `request.auth` context — rely on Firestore rules to gate write access

### Critical Findings

**CF-001: OpenAI Realtime WebSocket Direct Client → API Connection (P0)**

File: `AMENAPP/AIIntelligence/BereanRealtimeWebSocketTransport.swift` (lines 105-112)

```swift
let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(encodedModel)") else {
    ...
}
var request = URLRequest(url: url)
request.setValue("Bearer \(clientSecret.value)", forHTTPHeaderField: "Authorization")
```

**Evidence:** iOS client constructs WebSocket directly to `api.openai.com`, passing OpenAI API token in Authorization header. This violates the proxy pattern established by `bereanChatProxy` and `openAIProxy` Cloud Functions.

**Risk:**
- Token exposed in memory on client (harder to rotate)
- No server-side rate limiting or quota enforcement
- No audit trail of API consumption
- Token subject to network sniffing (though WSS mitigates)
- Billing attribution unclear

**Recommendation:** Route realtime connection through a Cloud Function that obtains ephemeral session tokens from OpenAI and returns them to the client. Client should connect using those short-lived tokens, not persistent API keys.

---

## 3. INPUT VALIDATION

### Summary

**PASS:**
- `bereanChatProxy`: Validates message length (4000 chars max), non-empty check
- `processGivingCharge`: Amount ranges validated, currency code checked, nonprofit existence verified
- `submitReport`: All fields validated against enum, dedup check, rate limiting
- Covenant functions validate tierId existence before Stripe call

**GAPS:**

**CF-002: Covenant Checkout Missing User Membership Check (P1)**

File: `Backend/functions/src/covenant/createCovenantCheckoutSession.ts` (lines 71-192)

**Evidence:** Function loads covenant doc and tier, but does NOT validate that the user is not already a member. A user could:
1. Complete a checkout (payment charged)
2. Be denied membership creation by webhook due to existing subscription
3. Have payment processed but membership denied

**Recommendation:** Before creating session, query `covenants/{covenantId}/members/{uid}` to check if membership exists. Reject with "already_member" if found.

---

## 4. SECRET HANDLING

### Summary

**PASS (100%):**
- All API keys use `defineSecret()` from `firebase-functions/params`
- `ANTHROPIC_API_KEY` — declared at index.ts:10, bound to all functions using it
- `STRIPE_SECRET_KEY` — declared as secret in processGivingCharge, createCovenantCheckoutSession
- `OPENAI_API_KEY` — declared as secret in openAIProxy, whisperProxy, spatialRooms
- `PERSPECTIVE_API_KEY` — declared as secret in media moderation functions

**No hardcoded secrets found** in source files.

**Potential gap:**
- Verify `.env.production.required` is not committed with actual keys (check .gitignore)
- Verify CI/CD passes secrets via environment (not from file)

---

## 5. IDEMPOTENCY

### Summary

**GOOD:**
- `createCovenantCheckoutSession`: Uses daily-scoped idempotency key
  ```typescript
  const dayKey = new Date().toISOString().slice(0, 10);
  const idempotencyKey = `checkout_${uid}_${covenantId}_${tierId}_${dayKey}`;
  ```
  This allows retries within a day but prevents re-checkout the next day.

**CF-003: Stripe Customer Creation Uses Per-UID Idempotency (P1)**

File: `Backend/functions/src/covenant/createCovenantCheckoutSession.ts` (lines 51-54)

```typescript
idempotencyKey: `stripe_customer_create_${uid}`,
```

**Evidence:** Idempotency key uses only `uid`, no timestamp. If a user's first customer creation fails and is retried days/weeks later, the idempotency key is still the same. This is actually GOOD for preventing duplicate customers, but create additional duplicate customer if the first creation succeeded but response was lost.

**Recommendation:** Current approach is acceptable (protects against duplicate customers). Just ensure Stripe error responses are handled correctly.

**CF-004: processGivingCharge One-Time Charges Lack Idempotency (P1)**

File: `Backend/functions/src/giving/processGivingCharge.ts` (lines 90-135)

**Evidence:** Function uses raw `fetch` to Stripe but does NOT set `Idempotency-Key` header on PaymentIntent creation. A network failure or timeout causes client to retry, potentially charging donor twice.

**Risk:** Loss of user trust, chargebacks, regulatory issues.

**Recommendation:** Add Idempotency-Key header:
```typescript
const idempotencyKey = `donation_${uid}_${nonprofitId}_${Date.now()}`;
headers['Idempotency-Key'] = idempotencyKey;
```

Store the key in Firestore before calling Stripe so client retries use the same key.

---

## 6. ERROR HANDLING

### Summary

**PASS:**
- Functions use `HttpsError` with proper codes (unauthenticated, invalid-argument, not-found, etc.)
- Stripe errors caught and logged without exposing internals
- Payment token never logged

**Gaps:**

**CF-005: Unhandled Promise Rejections in Notification Pipeline (P1)**

File: `Backend/functions/src/notifications/prayerAnsweredBatch.ts` (if exists)

**Recommendation:** Audit all Firestore trigger functions to ensure try/catch wraps all async operations. Missing error handling can cause silent failures or function timeout.

---

## 7. DEAD vs LIVE FUNCTION CROSS-REFERENCE

### Functions Called from Swift But NOT Exported

Swift calls these functions, but they are NOT exported from `index.ts`:

| Function Name | Called From | Status | Risk |
|---|---|---|---|
| `bereanGenericProxy` | Feature05, Feature06, Feature03, Feature09, Feature10, PostComposerServices.swift | UNDEPLOYED | P0 — Core AI feature unavailable |
| `createMediaReflection` | AmenMediaReflectionSheet.swift | UNDEPLOYED | P1 — Media reflection feature broken |
| `sermonSnapProxy` | BereanSnapService.swift | UNDEPLOYED | P1 — Sermon snapshot feature broken |
| `acceptSafeConnection` | SafeConnectionService.swift | UNDEPLOYED | P1 — Safe connection flow broken |
| `askAmenCompanion` | AskAmenCompanionRouter.swift | UNDEPLOYED | P1 — Amen Companion feature broken |
| `bereanEmbedProxy` | (may be in BereanChatProxyTypes comment) | UNDEPLOYED | P1 — Embed proxy missing |
| `checkCreatorSpaceEntitlement` | CreatorSpacesService.swift:124 | UNDEPLOYED | P1 — Paywall enforcement broken |
| `classifyBereanSafety` | BereanSourceGroundingService.swift | EXPORTED? | Check index.ts line 74 |
| `classifyEnvironment` | EnvironmentContextService.swift:56 | UNDEPLOYED | P1 — Environment classification broken |
| `bereanShieldAnalyze` | BereanShieldService.swift:137 | UNDEPLOYED | P1 — Shield analysis broken |
| `syncPremiumEntitlement` | PremiumManager.swift:286 | CHECK | May be exported via safety module |
| `approveMediaMetadata` | AmenMediaAIMetadataReviewSheet.swift:575 | UNDEPLOYED | P1 — Media approval broken |

**CF-006: 16+ Undeployed Functions Called from iOS (P0)**

**Evidence:** Search of Swift source finds 16+ httpsCallable() calls to functions not exported from `Backend/functions/src/index.ts`.

**Risk:** Critical user-facing features are broken (AI features, media, creator tools, safety checks).

**Recommendation:**
1. Cross-reference each function name against index.ts exports
2. For each MISSING function, either:
   - Implement and export it, OR
   - Remove the Swift call and fallback UI, OR
   - Mark as deprecated in release notes
3. Add automated test to detect new httpsCallable calls that lack backend implementation

---

## 8. COLD START & PERFORMANCE

### Summary

**Concern Areas:**

**CF-007: bereanChatProxy Heavy Initialization (P1)**

File: `Backend/functions/src/bereanChatProxy.ts` (lines 1-100)

**Evidence:**
- Imports from 7+ modules (berean/prompts, berean/services, berean/models, agents/*)
- Per-request: calls classifySpiritualState(), resolveBereanAgentIdentity(), startAgentRun()
- 256MiB memory allocation — high for serverless function

**Risk:** Cold start latency 5–10 seconds on first request after deploy/long idle.

**Recommendation:**
- Profile actual cold start time
- Consider lazy-loading heavy modules (dynamic imports)
- Consolidate agent identity resolution into single module
- Monitor production metrics: p50/p99 latency per day

**CF-008: Media Moderation Pipeline Concurrency (P1)**

File: `Backend/functions/src/mediaModerationPipeline.ts`

**Evidence:** Runs 6 layers sequentially: hash check → image safety → OCR → text safety → fusion → action engine. Each layer makes external API calls.

**Risk:** Total latency 30–60s for a single post with media. Could timeout on large uploads.

**Recommendation:**
- Parallelize independent layers (hash check + image safety can run concurrently)
- Consider async queuing: enqueue moderation job, return early, process in background

---

## 9. CLAUDE/OPENAI PROXY PATTERN VERIFICATION

### Summary

**Verified Proxies:**
- ✓ `bereanChatProxy` — Anthropic Claude proxy (calls api.anthropic.com server-side)
- ✓ `openAIProxy` — OpenAI chat proxy (calls api.openai.com server-side)
- ✓ `whisperProxy` — Whisper transcription proxy (calls api.openai.com server-side)
- ✓ `bereanChatProxyStream` — SSE streaming variant

**CRITICAL VIOLATION:**
- ✗ `BereanRealtimeWebSocketTransport` — Connects directly to `api.openai.com` from iOS client (P0)

**CF-009: Direct OpenAI Realtime Connection Breaks Proxy Pattern (P0)**

File: `AMENAPP/AIIntelligence/BereanRealtimeWebSocketTransport.swift` (lines 101-119)

**Evidence:** Client constructs WebSocket URL to OpenAI API directly:
```swift
let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(encodedModel)")
request.setValue("Bearer \(clientSecret.value)", forHTTPHeaderField: "Authorization")
```

**Risk:**
- API key exposed in client memory
- No server-side audit trail
- Token rotation and revocation difficult
- Billing attribution unclear
- Possible regulatory violation (key should not be on client per security best practices)

**Recommendation:** Implement Cloud Function that:
1. Client calls `createRealtimeSession` to request ephemeral token
2. Cloud Function calls OpenAI to get session token
3. Returns token to client
4. Client connects to OpenAI using short-lived session token
5. Server validates session ownership when WebSocket connects

---

## 10. GEN1 vs GEN2 MIGRATION

### Summary

**Gen2 Functions (Modern - firebase-functions/v2):**
- Most callables are using `onCall()` from `firebase-functions/v2/https`
- Secrets properly declared with `defineSecret()`
- Example: `bereanChatProxy`, `processGivingCharge`, Covenant functions

**Gen1 Functions (Legacy - firebase-functions):**
- Some imports still reference `firebase-functions` directly (not v2)
- Example: `submitReport.ts` uses `import * as functions from "firebase-functions"`

**No simultaneous Gen1/Gen2 exports of same function found** — good.

**Recommendation:** Audit for remaining Gen1 code and migrate to Gen2 for consistency.

---

## 11. SUMMARY FINDINGS TABLE

| ID | Severity | Category | Issue | File | Risk |
|---|---|---|---|---|---|
| CF-001 | P0 | proxy_pattern | OpenAI Realtime WebSocket direct client connection | BereanRealtimeWebSocketTransport.swift:105 | CRITICAL |
| CF-002 | P0 | undeployed_function | 16+ functions called from Swift but NOT exported | Multiple | CRITICAL |
| CF-003 | P1 | idempotency | Giving charge one-time payments lack Stripe idempotency key | processGivingCharge.ts:117 | HIGH |
| CF-004 | P1 | validation | Covenant checkout missing user membership pre-check | createCovenantCheckoutSession.ts:71 | HIGH |
| CF-005 | P1 | error_handling | Potential unhandled promise rejections in triggers | notifications/*.ts | MEDIUM |
| CF-006 | P1 | cold_start | bereanChatProxy heavy initialization (256MiB, 7+ imports) | bereanChatProxy.ts:92 | MEDIUM |
| CF-007 | P1 | cold_start | Media moderation pipeline sequential (30–60s latency) | mediaModerationPipeline.ts | MEDIUM |

---

## TOP 3 LAUNCH-BLOCKING FINDINGS

### 1. **CF-001: Direct OpenAI API Connection from iOS Client (P0)**
**Blocks:** Security review approval, App Store review  
**Fix:** Implement Cloud Function proxy for realtime sessions  
**Effort:** 2–3 days  
**Risk of Fix:** Low  

### 2. **CF-002: 16+ Undeployed Functions (P0)**
**Blocks:** Feature completeness, user experience  
**Fix:** Either deploy missing functions or remove Swift calls  
**Effort:** 1 day (audit) + 3–5 days (per implementation)  
**Risk of Fix:** Medium (may need UI changes)  

### 3. **CF-003: Giving Charge Idempotency Missing (P0)**
**Blocks:** Payment safety, financial compliance  
**Fix:** Add Stripe Idempotency-Key header + Firestore dedup  
**Effort:** 0.5 day  
**Risk of Fix:** Low  

---

## SUMMARY

The AMEN Cloud Functions infrastructure is **mostly secure** with proper Auth + App Check enforcement, good secret management, and Gen2 modernization. However, **3 critical findings block launch:**

1. Direct OpenAI realtime connection violates proxy pattern and security posture
2. 16+ functions called from Swift but not deployed — core features broken
3. Payment functions lack idempotency — financial safety risk

All three findings require server-side changes with low-to-medium implementation risk.

