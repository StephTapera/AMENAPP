# AMEN Deploy Plan — 2026-06-16 Overnight Readiness

**Branch:** `feature/berean-island-w0`
**Project:** `amen-5e359`
**Operator:** Human-only. Agents do not run `firebase deploy`.
**Region policy:** `us-central1` is at 999/1000 Cloud Run services (quota exhausted). All new functions must deploy to `us-east1`. Update `docs/FUNCTION_INVENTORY.md` Interim Region Table after every new deploy.
**Log all output:** `tee deploy-logs/<batch>-$(date +%Y%m%d-%H%M%S).log`

---

## Pre-Deploy Checklist

Run every step from the repo root before touching any batch:

```sh
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
```

- [ ] **TypeScript check — default codebase**
  ```sh
  npm --prefix Backend/functions run build 2>&1 | tee deploy-logs/tsc-creator-$(date +%Y%m%d-%H%M%S).log
  npx tsc --noEmit --project Backend/functions/tsconfig.json 2>&1 | tee deploy-logs/tsc-default-$(date +%Y%m%d-%H%M%S).log
  ```

- [ ] **v2triggers prep script**
  ```sh
  bash functions/v2triggers/prepare-deploy.sh 2>&1 | tee deploy-logs/v2triggers-prep-$(date +%Y%m%d-%H%M%S).log
  ```

- [ ] **Emulator rule tests (Firestore + Storage)**
  ```sh
  firebase emulators:start --only firestore,storage --project amen-5e359 &
  # run your rules test suite, then
  kill %1
  ```

- [ ] **Backup current Firestore rules**
  ```sh
  cp firestore.rules firestore.rules.backup.2026-06-16
  ```

- [ ] **Backup current Storage rules**
  ```sh
  cp storage.rules storage.rules.backup.2026-06-16
  ```

- [ ] **Confirm active project alias**
  ```sh
  firebase use amen-5e359
  firebase projects:list
  ```

- [ ] **Confirm you are NOT inside a subdirectory** — all firebase commands run from repo root
- [ ] **Confirm `cloud-functions/` is NOT touched** — it is quarantined; has its own `firebase.json`
- [ ] **Check us-central1 quota before deploying anything new**
  ```sh
  gcloud run services list --region us-central1 --project amen-5e359 | wc -l
  # If >= 950: deploy to us-east1 and add to Interim Region Table
  ```

---

## Batch 1: Safety-Critical (DEPLOY FIRST — blocking App Store)

**Why first:** NCMEC CyberTipline gap (P5-Y2) and media moderation pipeline are legal blockers. Firestore/Storage rules enforce content access controls for all downstream batches.

### 1A — Firestore Rules + Indexes

```sh
firebase deploy --only firestore:rules --project amen-5e359 \
  2>&1 | tee deploy-logs/batch1a-rules-$(date +%Y%m%d-%H%M%S).log

firebase deploy --only firestore:indexes --project amen-5e359 \
  2>&1 | tee deploy-logs/batch1a-indexes-$(date +%Y%m%d-%H%M%S).log
```

### 1B — Storage Rules

```sh
firebase deploy --only storage --project amen-5e359 \
  2>&1 | tee deploy-logs/batch1b-storage-$(date +%Y%m%d-%H%M%S).log
```

### 1C — Media Moderation Pipeline + Submit Report (default codebase)

> **LEGAL GATE — P5-Y2:** `submitNCMECCyberTip` must be wired into `mediaModerationPipeline.ts` and NCMEC credentials stored as `NCMEC_API_KEY` / `NCMEC_ENDPOINT` in Cloud Secret Manager before deploying the NCMEC path. Do NOT flip the `csam_hash_scan_enabled` Remote Config flag until legal sign-off is obtained. The media moderation blocking pipeline (no NCMEC tip) may deploy independently.

```sh
firebase deploy \
  --only "functions:default:onPostCreatedRunMediaModeration,functions:default:onPostMediaUpdatedRunModeration,functions:default:submitMediaReviewDecision,functions:default:getPostModerationStatus,functions:default:getAccountMediaRiskScore,functions:default:triggerMediaModeration,functions:default:submitReport" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch1c-moderation-$(date +%Y%m%d-%H%M%S).log
```

Region: `us-east1` for any net-new services. Add to Interim Region Table.

### 1D — Safety OS + A3 Callables + Anti-Harassment

```sh
firebase deploy \
  --only "functions:default:safetyOS,functions:default:safetyOSReactionEngine,functions:default:antiHarassmentEnforcement,functions:default:evaluateDmRisk,functions:default:reportDmAbuse,functions:default:contentSafetyScreen,functions:default:analyzeRelationshipRisk,functions:default:assessDogpileRisk" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch1d-safety-$(date +%Y%m%d-%H%M%S).log
```

### 1E — Media Scanning + Report Unsafe AI Response

```sh
firebase deploy \
  --only "functions:default:mediaScanning,functions:default:reportUnsafeAIResponse" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch1e-mediatrust-$(date +%Y%m%d-%H%M%S).log
```

**After Batch 1:** Verify Firestore rules are live and a known-blocked read is still rejected:
```sh
firebase firestore:rules --project amen-5e359
```

---

## Batch 2: Auth + Account Deletion

**Context (Y-P4-01):** iOS `AccountManagementService` calls `functions.httpsCallable("deleteUserAccount")`. The server-side export in `userAccountDeletionCascade.ts` is `userAccountDeletionCascade`. Verify the Cloud Function callable name matches what iOS calls, or update iOS to use the correct callable name, before enabling the hard-delete flow.

```sh
firebase deploy \
  --only "functions:default:userAccountDeletionCascade,functions:default:accountLifecycle,functions:default:accountSuspension,functions:default:twoFactorAuth,functions:default:syncAgeTierClaim,functions:default:deleteAlgoliaUser" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch2-auth-account-$(date +%Y%m%d-%H%M%S).log
```

> **Smoke-test gate:** After deploy, invoke `userAccountDeletionCascade` with a sandboxed test-user UID. Verify subcollections (prayers, posts, messages) are deleted and the Firebase Auth record is removed. Do NOT enable the `ff_account_hard_delete` flag until this passes.

Add `userAccountDeletionCascade` to Interim Region Table at `us-east1` if this is a net-new service.

---

## Batch 3: Posts / Comments / Feed

### 3A — Post lifecycle triggers + feed

```sh
firebase deploy \
  --only "functions:default:onPostCreated,functions:default:postCountTriggers,functions:default:postDeletionCascade,functions:default:postReactions,functions:default:feedBuilder,functions:default:feedContext,functions:default:feedIntelligence,functions:default:generateDynamicReplyPreviews" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch3a-posts-$(date +%Y%m%d-%H%M%S).log
```

### 3B — Comments + moderation

```sh
firebase deploy \
  --only "functions:default:commentModerationEnforcement,functions:default:validateThinkFirstCheck,functions:default:validateMediaCaptions" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch3b-comments-$(date +%Y%m%d-%H%M%S).log
```

### 3C — Discovery feed + Algolia sync

> **Privacy note (P5-Y4):** Before flipping any live feed flags, verify that `assembleDiscoveryFeed` (and the iOS `PostsManager.swift` / `HomeFeedAlgorithm.swift`) excludes posts authored by users in the viewer's `blockedUsers` list. If not present client-side, add the filter before enabling flags.

```sh
firebase deploy \
  --only "functions:default:assembleDiscoveryFeed,functions:default:searchDiscovery,functions:default:algoliaSync,functions:default:mediaPostIndex" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch3c-discovery-$(date +%Y%m%d-%H%M%S).log
```

### 3D — Block + Follow graph

```sh
firebase deploy \
  --only "functions:default:createBlock,functions:default:blockRelationshipCleanup,functions:default:createFollow,functions:default:acceptFollowRequest,functions:default:rejectFollowRequest,functions:default:cancelFollowRequest,functions:default:removeFollower,functions:default:onAccountPrivacyChange,functions:default:reconcileFollowCounts" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch3d-social-graph-$(date +%Y%m%d-%H%M%S).log
```

Region: `createFollow`, `acceptFollowRequest`, `rejectFollowRequest`, `cancelFollowRequest`, `removeFollower`, `onAccountPrivacyChange`, `blockRelationshipCleanup`, `reconcileFollowCounts` are already in the Interim Region Table at `us-east1`. Confirm before redeploying.

### 3E — Notification revocation (on content delete)

```sh
firebase deploy \
  --only "functions:default:revokeNotificationsOnCommentDelete,functions:default:revokeNotificationsOnPostDelete" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch3e-notification-revocation-$(date +%Y%m%d-%H%M%S).log
```

Region: Both are in Interim Region Table at `us-east1`.

---

## Batch 4: Messaging / Notifications

### 4A — DM callables + smart inbox

```sh
firebase deploy \
  --only "functions:default:resolveOrCreateConversation,functions:default:generateDMCatchUp,functions:default:extractThreadDecisions,functions:default:detectOpenQuestions,functions:default:extractThreadActions,functions:default:generateGroupPulse,functions:default:generateMediaContext,functions:default:privateMessageActions,functions:default:generateSmartReplies,functions:default:searchConversationMemory,functions:default:productionIntelligenceActions" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch4a-messaging-$(date +%Y%m%d-%H%M%S).log
```

### 4B — Notifications (push + digest)

```sh
firebase deploy \
  --only "functions:default:onSocialEvent,functions:default:counts,functions:default:maintenance,functions:default:invalidation,functions:default:sendNotification,functions:default:prayerAnsweredBatch,functions:default:deliverQuietHoursDigest" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch4b-notifications-$(date +%Y%m%d-%H%M%S).log
```

### 4C — v2triggers: Realtime comment + DM + daily digest

```sh
firebase deploy \
  --only "functions:v2triggers:onRealtimeCommentCreate,functions:v2triggers:onMessageSent,functions:v2triggers:sendDailyNotificationDigest" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch4c-v2triggers-$(date +%Y%m%d-%H%M%S).log
```

### 4D — ONE Private Social OS callables

```sh
firebase deploy \
  --only "functions:default:oneRelayMoment,functions:default:oneSendMoment,functions:default:oneExpireMoment,functions:default:oneVerifyEntitlement,functions:default:oneActivateLegacy,functions:default:processConnectQueuedDraft" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch4d-one-$(date +%Y%m%d-%H%M%S).log
```

### 4E — Global Resilience (us-east1)

```sh
firebase deploy \
  --only "functions:default:sendMessageGlobal,functions:default:getThreadOfflineCache" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch4e-global-resilience-$(date +%Y%m%d-%H%M%S).log
```

Add `sendMessageGlobal` and `getThreadOfflineCache` to Interim Region Table at `us-east1` if net-new.

---

## Batch 5: AI / Berean

> **Consent gate (P6-Y1):** `assemblePrayerChain` must enforce per-user AI consent server-side before being used in production. Verify `selahConnection.ts:assemblePrayerChain` reads the user's AI consent flag from Firestore before invoking the LLM. Do NOT flip `berean_prayer_chain_enabled` until this is confirmed.

> **Region:** All Berean + AI callables go to **us-east1** (us-central1 quota exhausted). Add each to the Interim Region Table.

### 5A — Berean pipeline + constitutional review (default codebase)

```sh
firebase deploy \
  --only "functions:default:bereanPipeline,functions:default:constitutionalReview,functions:default:bereanChatProxy,functions:default:bereanChatProxyStream,functions:default:bereanHelperPipeline,functions:default:bereanExtended,functions:default:bereanPulse,functions:default:bereanOperatingLayer,functions:default:bereanMemory,functions:default:modelRouter,functions:default:legacyAiSafetyBridge" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch5a-berean-core-$(date +%Y%m%d-%H%M%S).log
```

### 5B — Berean intelligence controllers (default codebase)

```sh
firebase deploy \
  --only "functions:default:generateStructuredResponse,functions:default:studyPassage,functions:default:analyzeMessage,functions:default:evaluateAuthorityEscalation,functions:default:getImmersionPayload,functions:default:getJourneySnapshot,functions:default:generateDiscipleshipNextStep,functions:default:saveReflectionEntry,functions:default:generateChurchNotesSummary,functions:default:premiumBereanCallables" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch5b-berean-controllers-$(date +%Y%m%d-%H%M%S).log
```

### 5C — Berean Island Wave 0 stubs (v2triggers codebase, us-east1)

```sh
firebase deploy \
  --only "functions:v2triggers:bereanIsland_trigger,functions:v2triggers:bereanLens_analyze,functions:v2triggers:writeWithBerean_assist,functions:v2triggers:sermonCompanion_session" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch5c-berean-island-$(date +%Y%m%d-%H%M%S).log
```

Add all four to Interim Region Table at `us-east1`.

### 5D — Selah Berean + Selah Connection callables (us-east1)

```sh
firebase deploy \
  --only "functions:default:joinTable,functions:default:assemblePrayerChain,functions:default:closeTheLoopNudge,functions:default:sunsetTable,functions:default:generateDiscussionGuide,functions:default:retrievePersonalContext,functions:default:selahSafety,functions:default:selahMedia" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch5d-selah-$(date +%Y%m%d-%H%M%S).log
```

Add `joinTable`, `assemblePrayerChain`, `closeTheLoopNudge`, `sunsetTable`, `generateDiscussionGuide`, `retrievePersonalContext` to Interim Region Table at `us-east1`.

### 5E — AI Proxy + translation + graphics

```sh
firebase deploy \
  --only "functions:default:openAIProxy,functions:default:whisperProxy,functions:default:refineTranslation,functions:default:transformContent,functions:default:translateMultilingualContent,functions:default:generateAmenGraphic,functions:default:editAmenGraphic,functions:default:moderateGraphicPrompt,functions:default:saveGeneratedGraphic" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch5e-ai-proxy-$(date +%Y%m%d-%H%M%S).log
```

### 5F — Agent OS

```sh
firebase deploy \
  --only "functions:default:runAmenAgentTask,functions:default:agentTaskRouter,functions:default:agentGuardrails,functions:default:agentObservability,functions:default:agentResultFormatter" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch5f-agents-$(date +%Y%m%d-%H%M%S).log
```

### 5G — v2triggers Context Engine (us-east1)

```sh
firebase deploy \
  --only "functions:v2triggers:contextEngine_getGrants,functions:v2triggers:contextEngine_setGrant,functions:v2triggers:contextEngine_getAuditLog,functions:v2triggers:resolveContextAccess" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch5g-context-engine-$(date +%Y%m%d-%H%M%S).log
```

Add all four to Interim Region Table at `us-east1`.

### 5H — Living Intelligence + v2triggers scheduler

```sh
firebase deploy \
  --only "functions:default:getGlobalIntelligenceCards,functions:default:submitWorldEvent,functions:default:buildIntelligenceBriefs,functions:default:triggerIntelligenceBriefForUser,functions:default:matchEventsForUser,functions:default:matchPrayerSupport,functions:default:onPrayerCreated,functions:default:classifyPostNeed,functions:default:matchNeedsToVolunteers,functions:default:semanticIntelligence,functions:default:trustIntelligence,functions:default:amenConnect,functions:default:actionIntelligence,functions:default:actionThreads" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch5h-intelligence-$(date +%Y%m%d-%H%M%S).log

firebase deploy \
  --only "functions:v2triggers:buildDailyIntelligenceBriefs,functions:v2triggers:getIntelligenceBrief,functions:v2triggers:recordIntelligenceAction" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch5h-v2triggers-intelligence-$(date +%Y%m%d-%H%M%S).log
```

---

## Batch 6: Church / Search / Resources

### 6A — Church discovery + journey

```sh
firebase deploy \
  --only "functions:default:churchDiscovery,functions:default:churchDiscoveryPhase2,functions:default:churchDiscoveryPhase3,functions:default:churchVisitLifecycle,functions:default:churchJourney,functions:default:churchPulseFunctions" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch6a-church-$(date +%Y%m%d-%H%M%S).log
```

### 6B — Church notes pipeline

```sh
firebase deploy \
  --only "functions:default:createChurchNotesAIDraft,functions:default:churchNotesProcessingJobs,functions:default:churchNotesAudioProcessing,functions:default:churchNotesImageOCR,functions:default:churchNotesContentGeneration,functions:default:churchNotesDraftApproval,functions:default:churchNotesExtendedCallables,functions:default:churchNotesPrivacyAudit" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch6b-church-notes-$(date +%Y%m%d-%H%M%S).log
```

### 6C — Search + verification + social suggestions

```sh
firebase deploy \
  --only "functions:default:algoliaSync,functions:default:algoliaUserSync,functions:default:algoliaWorkSync,functions:default:deleteAlgoliaUser,functions:default:verificationEngine,functions:default:antiImpersonation,functions:default:suggestedAccounts,functions:default:followKnowledge" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch6c-search-$(date +%Y%m%d-%H%M%S).log
```

Note: Algolia post sync triggers (`algoliaPostUpdateSync`, `algoliaPostDeleteSync`) are already in the Interim Region Table at `us-east1`.

### 6D — Spiritual systems + Sabbath + Daily verse + Pulse

```sh
firebase deploy \
  --only "functions:default:spiritualSystems,functions:default:spiritualOSPhase23,functions:default:evaluateSabbathMode,functions:default:setSabbathPreference,functions:default:syncFamilySabbathPresence,functions:default:onSabbathNotificationWrite,functions:default:generateDailyVerse,functions:default:getAmenDailyDigest,functions:default:pulse,functions:default:restModeEvaluator,functions:default:holidayCalendarGenerator" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch6d-spiritual-$(date +%Y%m%d-%H%M%S).log
```

### 6E — Catalog + AI catalog (creator codebase)

> **Note (file naming):** `Backend/functions/src/selahConnection 2.ts` has a space in the filename. Rename it before the creator codebase build step or the TypeScript compiler may emit an error. The canonical file is `selahConnection.ts`.

```sh
firebase deploy \
  --only "functions:creator:askCreatorQuery,functions:creator:topicClusterEngine,functions:creator:embedCatalogWork,functions:creator:affiliateLinkWrapper,functions:creator:affiliateTierHelper,functions:creator:catalogEntitlements,functions:creator:signedUrlService" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch6e-catalog-$(date +%Y%m%d-%H%M%S).log
```

Add any net-new catalog functions to Interim Region Table at `us-east1`.

### 6F — Ingestion providers (creator codebase)

```sh
firebase deploy \
  --only "functions:creator:manualEntry,functions:creator:googleBooksProvider,functions:creator:substackMediumProvider,functions:creator:youtubeProvider,functions:creator:catalogSearch,functions:creator:importHub,functions:creator:continuousSync,functions:creator:reviewWorkflow" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch6f-ingestion-$(date +%Y%m%d-%H%M%S).log
```

### 6G — Camera OS + Ambient + Selah Creation

```sh
firebase deploy \
  --only "functions:default:contextLens,functions:default:getAmbientContext,functions:default:summarizeAmbientContext,functions:default:generateC2PAManifest,functions:default:createRemixLineage,functions:default:explainVideoContent,functions:default:voicePrayerComments,functions:default:validateMediaCaptions" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch6g-camera-ambient-$(date +%Y%m%d-%H%M%S).log
```

---

## Batch 7: Subscriptions / Payments

> **HUMAN LEGAL GATE:** Do not deploy any payment or giving functions until legal and finance sign-off is confirmed. The NCMEC legal gate (P5-Y2) must also be resolved before this batch.

### 7A — Giving / donations

> **Stripe nonprofit URL decision (D-1 from UX audit):** giving currently stubs to a Stripe nonprofit URL. Confirm the production Stripe account is live and the nonprofit URL is correct before deploying.

```sh
firebase deploy \
  --only "functions:default:processGivingCharge,functions:default:analyzePostTrustLogoMatch" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch7a-giving-$(date +%Y%m%d-%H%M%S).log
```

### 7B — Covenant / Spaces subscriptions (Stripe Connect)

```sh
firebase deploy \
  --only "functions:default:createCovenantCheckoutSession,functions:default:saveCovenantTierStripePriceId,functions:default:stripeCovenantWebhook,functions:default:verifyCovenantMembership,functions:default:calculateCovenantChurnRisk" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch7b-covenant-billing-$(date +%Y%m%d-%H%M%S).log

firebase deploy \
  --only "functions:v2triggers:createSpaceTier,functions:v2triggers:getSpaceEntitlement,functions:v2triggers:processSubscription,functions:v2triggers:processRefund,functions:v2triggers:getPayoutSummary,functions:v2triggers:hostKYCOnboarding,functions:v2triggers:createStripeConnectAccount" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch7b-spaces-billing-$(date +%Y%m%d-%H%M%S).log
```

### 7C — Creator monetization functions

```sh
firebase deploy \
  --only "functions:default:enforceCreatorEntitlement,functions:default:publishProject,functions:default:processVideoProxy,functions:default:queueProcessingJob,functions:default:recordCreatorAnalytics,functions:default:renderExport,functions:default:retryFailedCreatorJob,functions:default:autosaveProject,functions:default:moderateCreatorAsset" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch7c-creator-$(date +%Y%m%d-%H%M%S).log
```

---

## Batch 8: Admin / Maintenance

### 8A — Scheduled maintenance + rate limiting + server flags

```sh
firebase deploy \
  --only "functions:default:scheduledMaintenance,functions:default:rateLimit,functions:default:serverFeatureFlags,functions:default:counterReconciliation" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch8a-admin-$(date +%Y%m%d-%H%M%S).log
```

### 8B — Spaces OS (community AI, events, livestream, mentorship, discussion)

```sh
firebase deploy \
  --only "functions:default:communityAI,functions:default:eventBroadcast,functions:default:livestreamAI,functions:default:monetizationExt,functions:default:discoveryAndLegal,functions:default:mentorship,functions:default:discussionAI,functions:default:spaceLifecycle,functions:default:spaceEvents,functions:default:generateLiveKitToken,functions:default:getLivekitToken" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch8b-spaces-$(date +%Y%m%d-%H%M%S).log
```

### 8C — Community hubs + Covenant activity + Composer

```sh
firebase deploy \
  --only "functions:default:resolveCommunityObject,functions:default:createOrJoinObjectHub,functions:default:getObjectHub,functions:default:getRelatedObjectHubs,functions:default:recordObjectInteraction,functions:default:muteObjectHub,functions:default:reportHubContent,functions:default:indexPostIntoHub,functions:default:createCovenantActivityEvent,functions:default:generateThreadSummary,functions:default:generateCatchUpSummary,functions:default:validateCovenantPostSafety,functions:default:submitCovenantReport,functions:default:indexCovenantSearchDocument,functions:default:publishScheduledCovenantContent" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch8c-hubs-covenant-$(date +%Y%m%d-%H%M%S).log

firebase deploy \
  --only "functions:default:unfurlLink,functions:default:generateCalendarPayload,functions:default:incrementVolunteerSlot,functions:default:aggregatePrayerCount" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch8c-composer-$(date +%Y%m%d-%H%M%S).log
```

### 8D — Realtime session + media pipeline

```sh
firebase deploy \
  --only "functions:default:createRealtimeSession,functions:default:endRealtimeSession,functions:default:logRealtimeVoiceEvent,functions:default:moderateRealtimeTranscript,functions:default:startRealtimeTranscription,functions:default:finalizeTranscript,functions:default:extractKeyMoments,functions:default:moderateTranscript,functions:default:reportMedia" \
  --project amen-5e359 \
  2>&1 | tee deploy-logs/batch8d-realtime-$(date +%Y%m%d-%H%M%S).log
```

### 8E — Remote Config template

```sh
firebase deploy --only remoteconfig --project amen-5e359 \
  2>&1 | tee deploy-logs/batch8e-remoteconfig-$(date +%Y%m%d-%H%M%S).log
```

---

## Remote Config Changes

Enable the following flags **only after** their backing Cloud Functions are deployed and smoke-tested. Do NOT batch-enable all at once.

| Flag | Enable After Batch | Notes |
|------|--------------------|-------|
| `ff_media_moderation_v2` | Batch 1C | Moderation pipeline live |
| `ff_account_hard_delete` | Batch 2 | After smoke-test with sandboxed test user |
| `ff_feed_block_enforcement` | Batch 3C | After verifying feed filters blocked users client-side |
| `ff_one_private_social` | Batch 4D | ONE relay/expire/entitlement deployed |
| `ff_berean_island_w0` | Batch 5C | Wave 0 stubs deployed |
| `ff_selah_tables` | Batch 5D | joinTable + sunsetTable deployed |
| `ff_berean_prayer_chain_enabled` | Batch 5D + P6-Y1 gate | AI consent gate must be wired first |
| `capabilities_core_enabled` | Batch 5G | Context Engine deployed |
| `ff_church_notes_ai` | Batch 6B | Church notes pipeline deployed |
| `amen_pulse_enabled` | Batch 6D | pulse.ts deployed |
| `ff_sabbath_mode` | Batch 6D | Sabbath callables deployed |
| `ff_giving_enabled` | Batch 7A | LEGAL GATE required |
| `ff_livekit_rooms` | Batch 8B | LiveKit secrets set in Cloud Secret Manager |
| `csam_hash_scan_enabled` | BLOCKED | Requires NCMEC ESP registration + legal sign-off (P5-Y2) |

---

## Post-Deploy Smoke Tests

Run from repo root after each batch. Replace `TEST_UID` with a sandboxed test-user UID.

### After Batch 1 (Safety/Rules)
```sh
# Verify Firestore rules are deployed
firebase firestore:rules --project amen-5e359
# Verify a known-blocked path is still rejected
# Verify media moderation trigger is active
gcloud functions describe onPostCreatedRunMediaModeration --region us-east1 --project amen-5e359
```

### After Batch 2 (Account Deletion)
```sh
gcloud functions describe userAccountDeletionCascade --region us-east1 --project amen-5e359
# iOS smoke test with a sandboxed test UID — verify:
#   1. users/{uid} document deleted
#   2. posts/{uid}/* subcollection deleted
#   3. prayers/{uid}/* subcollection deleted
#   4. messages involving uid cleaned up
#   5. Firebase Auth record deleted
```

### After Batch 3 (Posts/Feed)
```sh
gcloud functions describe assembleDiscoveryFeed --region us-east1 --project amen-5e359
# Verify a blocked user's posts do not appear in the blocker's feed
```

### After Batch 4 (Messaging/Notifications)
```sh
gcloud functions describe resolveOrCreateConversation --region us-east1 --project amen-5e359
gcloud functions describe oneRelayMoment --region us-east1 --project amen-5e359
gcloud functions describe sendMessageGlobal --region us-east1 --project amen-5e359
```

### After Batch 5 (AI/Berean)
```sh
gcloud functions describe bereanPipeline --region us-east1 --project amen-5e359
gcloud functions describe assemblePrayerChain --region us-east1 --project amen-5e359
# Test a Berean chat call from iOS; confirm constitutional review stage fires
# Confirm AI consent gate is enforced before assemblePrayerChain proceeds
gcloud functions describe bereanIsland_trigger --region us-east1 --project amen-5e359
```

### After Batch 6 (Church/Search)
```sh
gcloud functions describe churchDiscovery --region us-east1 --project amen-5e359
gcloud functions describe evaluateSabbathMode --region us-east1 --project amen-5e359
gcloud functions describe askCreatorQuery --region us-east1 --project amen-5e359
```

### After Batch 7 (Payments — LEGAL GATE)
```sh
# Only after legal sign-off is confirmed
gcloud functions describe processGivingCharge --region us-east1 --project amen-5e359
# Run a $0.01 Stripe test charge in sandbox mode before enabling the live flag
```

### After Batch 8 (Admin/Maintenance)
```sh
gcloud functions describe scheduledMaintenance --region us-east1 --project amen-5e359
firebase remoteconfig:get --project amen-5e359 | grep -E "ff_|enabled"
```

---

## iOS Changes Required (No Firebase Deploy Needed)

These changes require a new binary upload to App Store Connect, not Firebase deploys.

### ATT Purpose String (Y-P12-02)
- **File:** `AMENAPP/AMENAPP/Info.plist`
- **Key:** `NSUserTrackingUsageDescription`
- **Current (vague — will be rejected by Apple review):**
  > "AMEN uses this to understand how our community discovers spiritual content, so we can improve formation features for you."
- **Required (specific — App Review compliant):**
  > "AMEN uses your device's advertising identifier to measure app installs and attribute them to ad campaigns via Firebase Analytics (app-measurement.com) and Crashlytics crash attribution. No data is shared with third-party advertising networks."
- **Steps:** Update Info.plist, archive in Xcode, upload to App Store Connect. No Firebase deploy needed.

---

## Rollback

### Rules Rollback
```sh
cp firestore.rules.backup.2026-06-16 firestore.rules
cp storage.rules.backup.2026-06-16 storage.rules
firebase deploy --only firestore:rules,storage --project amen-5e359
```

### Single Function Rollback
```sh
git checkout <previous-sha> -- Backend/functions/src/path/to/function.ts
firebase deploy --only "functions:default:<functionName>" --project amen-5e359
```

### Remote Config Flag Kill Switch
If a flag flip causes issues, disable immediately via Firebase Console:
```
Firebase Console → Remote Config → search flag → set to false → Publish Changes
```

### Full Default Codebase Rollback
```sh
git checkout <known-good-sha> -- Backend/functions/src/
firebase deploy --only functions:default --project amen-5e359 \
  2>&1 | tee deploy-logs/rollback-default-$(date +%Y%m%d-%H%M%S).log
```

> WARNING: `firebase deploy --only functions:creator --force` deletes ~120 orphaned Cloud Run services. Never run this without explicit human approval. See CLAUDE.md.

> NEVER run `firebase deploy` (bare) or `firebase deploy --only functions` (untargeted). Both are forbidden per CLAUDE.md.

---

## Open Items (Do Not Deploy Until Resolved)

| ID | Item | Blocking | Status |
|----|------|----------|--------|
| P5-Y2 | NCMEC CyberTipline wiring | Yes | LEGAL GATE — register as ESP at missingkids.org first |
| Y-P4-01 | `deleteUserAccount` callable name mismatch | Yes | Verify exported name matches iOS httpsCallable("deleteUserAccount") before Batch 2 |
| P5-Y4 | Feed block enforcement unverified | No | Check `PostsManager.swift` + `HomeFeedAlgorithm.swift` before Batch 3C flag flip |
| P6-Y1 | `assemblePrayerChain` AI consent gate | Yes | Verify per-user consent check in `selahConnection.ts` before flipping prayer chain flag |
| Y-P12-02 | ATT string revision | No | Update `Info.plist` + re-archive before next App Store submission |
| D-1 | Stripe nonprofit URL | Yes | Confirm production Stripe nonprofit account before Batch 7A |
| — | `selahConnection 2.ts` filename has a space | Yes | Rename before creator codebase build; canonical file is `selahConnection.ts` |

---

*Generated: 2026-06-16. All deploy commands must be run from the repo root at `/Users/stephtapera/Desktop/AMEN/AMENAPP copy`. NEVER run `firebase deploy` bare or `firebase deploy --only functions` untargeted. All net-new Cloud Run services go to `us-east1` (us-central1 at quota). Update `docs/FUNCTION_INVENTORY.md` Interim Region Table after every new deploy.*
