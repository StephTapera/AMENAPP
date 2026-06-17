# Firebase Rules and Functions Audit — 2026-06-16

Generated: 2026-06-16 | Branch: feature/berean-island-w0
Firebase Project: amen-5e359 | Functions Runtime: node22

---

## Firestore Rules Status

- **Deny by default:** YES — explicit catch-all at bottom of file: `match /{document=**} { allow read, write: if false; }` (line 3391)
- **Sensitive collections protected:** YES — full coverage confirmed:
  - `ncmecReports`, `ncmecSubmissionQueue`, `mandatory_reports` — all false (client-inaccessible)
  - `auditLog` — client writes denied; CF Admin SDK only
  - `crisisEscalations` — CF only
  - `legalHolds` — legalReviewer custom claim only; no client writes
  - `moderationAuditLog` — all false
  - `bereanModelLogs`, `bereanEvalRuns` — all false
  - `one_evidence` — all false
  - `connectorTokens` — all false
  - `opportunity_graph`, `world_response_queue` — CF internal only
- **Known gaps:**
  - OPEN-1: Minor age-gate threshold — 13 (US COPPA) vs 16 (EU GDPR-K); T&S + Legal must confirm before EU deploy
  - OPEN-2: Guardian tools scope — guardians have zero read access to minor's private data; not yet implemented
  - OPEN-3: Anonymous prayer identity shielding — currently Option B (ownerUidEncrypted blocked from all clients)
  - OPEN-4: NCMEC CyberTipline SLA and escalation key-holder undefined
  - OPEN-5: Unauthenticated reads of public posts are permitted; T&S Lead must decide if SEO priority warrants this
  - OPEN-6: Cross-church data access intentionally DENIED (confirmed intended)
  - Duplicate `safetyAuditLog` rule block — one grants client create with field allowlist (~line 2987), one at ~line 3200 denies all writes (`allow write: if false`). First matching rule wins in Firestore; the second block overrides the first for writes — intent must be confirmed and duplicate removed
  - `testimonies/{testimonyId}` — read is `if resource.data.visibility == 'published'` with no `isSignedIn()` guard; unauthenticated clients can read published testimonies (T&S policy decision)
  - `notes/{noteId}/detections/{detectionId}` — has conflicting `allow read, write` and `allow write: if false` blocks; last write rule wins (deny); client read is granted to all `isSignedIn()`
  - GAP A4-P1: Wildcard `match /users/{uid}/{coll}/{docId}` allows writes to a named list of collections without individual rule review; any future addition bypasses granular control
- **Staged fixes:** No source-level changes made to `firestore.rules` this session. All fixes from prior sessions are present (followers-only ACL, trusted-circle ACL, moderation field guards, DM participantIds fallback, comment permission gate, premium field spoofing, ageTier immutability, role/safety fields, CSAM/NCMEC collections, Berean Island Wave 0, SELAH Wave 0, Context Intelligence OS)
- **Deploy status:** STAGED (not deployed) — `firebase.json` correctly points to `firestore.rules`. Deploy command: `firebase deploy --only firestore:rules --project amen-5e359`

---

## Storage Rules Status

- **Deny by default:** YES — explicit catch-all: `match /{allPaths=**} { allow read, write: if false; }` (line 733)
- **Sensitive collections protected:** YES
  - `uploads/blocked/`, `uploads/legalHold/` — no client access
  - Quarantine pipeline enforced: clients upload to `uploads/quarantine/` only; `approved/`, `blocked/`, `legalHold/` are client-write-denied
  - All upload paths are create-only (update: false) — prevents mid-flight evidence substitution
  - Profile photos quarantine path (`profile_photos/`) is owner-read-only (not public)
- **Known gaps:**
  - `profilePhotos/{uid}/{photoId}` — direct client writes still allowed for continuity until CF quarantine pipeline is fully deployed (noted in file as TODO)
  - Three separate profile-photo path names (`profile_photos/`, `profilePhotos/`, `profile_images/`) — consolidation to one canonical path is a TODO
  - Legacy `churchNotes/{uid}/{noteId}/audio|images|video` paths still use deprecated regex MIME helpers (`isAudioType()`, `isImageType()`, `isVideoType()`) instead of explicit allowlists; crafted content-type bypass still possible on these paths
  - `uploads/approved/{uid}/{mediaId}` — `allow read: if true` (unauthenticated public read); intended for CDN delivery but no comment documents this explicitly
  - `organizations/` and `churches/` media paths allow public read (`allow read: if true`)
- **Staged fixes:** No source-level changes made to `storage.rules` this session. All prior session fixes are present (explicit MIME allowlists, quarantine-first pipeline, chat video/file/group avatar rules, church note attachment rule, AmenSync rule, profile photo quarantine gate, sanctuary media role check)
- **Deploy status:** STAGED (not deployed) — deploy command: `firebase deploy --only storage --project amen-5e359`

---

## Cloud Functions Inventory

| Function | Codebase | Gen | Region | Auth? | AppCheck? | Rate Limit? | Deploy Status | iOS Caller |
|----------|----------|-----|--------|-------|-----------|-------------|---------------|------------|
| berean/callables (bereanIsland_trigger, signalCascade, sermonCompanion, writeWithBerean) | default | Gen-2 | us-east1 | YES | YES | Partial | Deployed | BereanIslandService.swift |
| capabilities/prayerOS (createCard, listCards, updateCard, deleteCard, scheduled) | default | Gen-2 | us-east1 | YES | YES | YES | Deployed | CapabilityModels.swift |
| capabilities/registry (listCapabilities) | default | Gen-2 | us-east1 | YES | NO (documented) | NO | Deployed | CapabilityModels.swift |
| capabilities/scripture (detectReferences, searchVerses, getVerses) | default | Gen-2 | us-east1 | YES | NO | NO | Deployed | CapabilityModels.swift |
| contextEngine/callables (resolveContextAccess, getGrants, getAuditLog) | default | Gen-2 | us-east1 | YES | NO (documented) | NO | Deployed | ContextBusBackfillAdapters.swift |
| heyFeed (callable, scheduled) | default | Gen-2 | us-east1 | YES | Partial | YES | Deployed | HeyFeedService.swift |
| sanctuary/index | default | Gen-1 | us-east1 | YES | NO | NO | Deployed | SanctuaryService.swift |
| spaces/callable (createSpace, joinSpace, leaveSpace) | default | Gen-2 | us-east1 | YES | YES | Partial | Deployed | ConnectSpacesView.swift |
| spacesAI/callable | default | Gen-2 | us-east1 | YES | YES | Partial | Deployed | SpacesAI.swift |
| spacesEvents/callable | default | Gen-2 | us-east1 | YES | YES | NO | Deployed | SpacesEventsView.swift |
| spacesLive/callable | default | Gen-2 | us-east1 | YES | YES | NO | Deployed | SpacesLiveView.swift |
| spacesSafety/callable | default | Gen-2 | us-east1 | YES | YES | YES | Deployed | SpacesSafetyService.swift |
| spacesStripe/callable | default | Gen-2 | us-east1 | YES | YES | YES | Deployed | SpacesStripeService.swift |
| discussion/callable | default | Gen-1 | us-east1 | YES | NO | NO | Deployed | DiscussionService.swift |
| cameraOS/callable | default | Gen-1 | us-east1 | YES | NO | NO | Deployed | CameraOSService.swift |
| notificationRoutingPipeline.entry | default | Gen-1 | us-east1 | YES | NO | YES | Deployed | PushNotificationService.swift |
| socialGraph (follow, unfollow, block) | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | SocialGraphService.swift |
| globalResilience/crisisBulletins | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | GlobalResilienceService.swift |
| globalResilience/feedRanking | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | FeedView.swift |
| globalResilience/trustScoring | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | TrustProfileView.swift |
| globalResilience/adaptiveMedia | creator | Gen-2 | us-east1 | YES | NO | NO | Deployed | MediaPlayerView.swift |
| globalResilience/localePolicyPacks | creator | Gen-2 | us-east1 | YES | NO | NO | Deployed | LocaleContentWarning.swift |
| globalResilience/messaging | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | MessagingService.swift |
| creator/createProject | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | CreatorProjectService.swift |
| creator/updateProject | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | CreatorProjectService.swift |
| creator/publishProject | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | CreatorPublishService.swift |
| creator/renderExport | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | StudioExportService.swift |
| creator/transcribeMedia | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | ChurchNotesMediaService.swift |
| creator/generateSubtitleTrack | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | SubtitleService.swift |
| creator/translateSubtitleTrack | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | SubtitleService.swift |
| creator/moderateCreatorAsset | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | MediaModerationPipeline.swift |
| creator/enforceCreatorEntitlement | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | EntitlementService.swift |
| creator/autosaveProject | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | CreatorProjectService.swift |
| creator/cloneTemplateToProject | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | CreatorProjectService.swift |
| creator/retryFailedCreatorJob | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | CreatorJobQueue.swift |
| creator/recordCreatorAnalytics | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | AnalyticsService.swift |
| creator/verifyAuthenticitySignals | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | AuthenticityService.swift |
| ingestion/importHub | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | CatalogService.swift |
| ingestion/continuousSync | creator | Gen-2 | us-east1 | YES (scheduled) | NO | N/A | Deployed | N/A |
| ingestion/reviewWorkflow | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | CatalogReviewView.swift |
| ai-catalog/embedCatalogWork | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | CatalogSearch.swift |
| distinctives | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | AmenDistinctives.swift |
| pulseEngine | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | Pulse/PulseView.swift |
| agents/runAmenAgentTask | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | BereanAgent/*.swift |
| agents/agentTaskRouter | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | BereanAgent/*.swift |
| aiSafety/reportUnsafeAIResponse | creator | Gen-2 | us-east1 | YES | NO | NO | Deployed | BereanView.swift |
| accountLifecycle (suspend, restore, deletion cascade) | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | AccountDeletionService.swift |
| algoliaSync / deleteAlgoliaUser | creator | Gen-2 | us-east1 | YES (trigger) | NO | NO | Deployed | Search backend |
| bereanChatProxyStream | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | BereanAgentSurface.swift |
| followRequests | creator | Gen-2 | us-east1 | YES | NO | YES | Deployed | SocialGraphService.swift |
| generateDailyVerse | creator | Gen-2 | us-east1 | Scheduled | NO | N/A | Deployed | DailyVerseCard.swift |
| churchDiscoveryPhase3 | creator | Gen-2 | us-east1 | YES | Partial | NO | Deployed | FindAChurchView.swift |
| explainVideoContent | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | MediaPlayerView.swift |
| alignmentPipeline | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | BereanConstitutionalTrust.swift |
| scheduledMaintenance | creator | Gen-2 | us-east1 | Cron | NO | N/A | Deployed | N/A |
| serverFeatureFlags | creator | Gen-2 | us-east1 | YES | NO | NO | Deployed | FeatureFlagService.swift |
| ambient/getAmbientContext | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | AmbientOS/*.swift |
| ambient/summarizeAmbientContext | creator | Gen-2 | us-east1 | YES | YES | YES | Deployed | AmbientOS/*.swift |
| thinkFirst/validateThinkFirstCheck | creator | Gen-2 | us-east1 | YES | YES | NO | Deployed | ThinkFirstValidator.swift |
| ranking/dynamicReplyPreviewRanking | creator | Gen-2 | us-east1 | Trigger | NO | N/A | Deployed | FeedView.swift |
| **ai-catalog/askCreatorQuery** | creator | Gen-2 | us-east1 | YES | YES | UNKNOWN | **UNDEPLOYED (new)** | CatalogSearch.swift |
| **ai-catalog/topicClusterEngine** | creator | Gen-2 | us-east1 | YES | YES | UNKNOWN | **UNDEPLOYED (new)** | CatalogSearch.swift |
| **billing/affiliateTierHelper** | creator | Gen-2 | us-east1 | YES | YES | UNKNOWN | **UNDEPLOYED (new)** | BillingService.swift |
| **ingestion/manualEntry** | creator | Gen-2 | us-east1 | YES | YES | UNKNOWN | **UNDEPLOYED (new)** | CatalogService.swift |
| **ingestion/providers/googleBooksProvider** | creator | Gen-2 | us-east1 | YES | YES | UNKNOWN | **UNDEPLOYED (new)** | CatalogService.swift |
| **ingestion/providers/substackMediumProvider** | creator | Gen-2 | us-east1 | YES | YES | UNKNOWN | **UNDEPLOYED (new)** | CatalogService.swift |
| **ingestion/providers/youtubeProvider** | creator | Gen-2 | us-east1 | YES | YES | UNKNOWN | **UNDEPLOYED (new)** | CatalogService.swift |
| **search/catalogSearch** | creator | Gen-2 | us-east1 | YES | YES | UNKNOWN | **UNDEPLOYED (new)** | CatalogSearch.swift |

---

## TypeScript Compilation Status

- **functions/ (default):** PASS — 0 errors. All sub-tsconfigs (`tsconfig.berean.json`, `tsconfig.capabilities.json`, `tsconfig.context.json`, `tsconfig.sanctuary.json`) compile clean. Note: `functions/` has no root `tsconfig.json`; it uses module-specific configs. The main entrypoint (`functions/index.js`) is pre-compiled JavaScript.
- **Backend/functions/ (creator):** PASS — 0 errors. `npx tsc --noEmit` produced no output (clean exit).

---

## Staged Changes (not deployed)

No source-level changes to function files or rules files were made in this audit session. The following are present in the working tree as untracked files (per `git status`) and have not been deployed:

| File | Status | Notes |
|------|--------|-------|
| `Backend/functions/src/ai-catalog/askCreatorQuery.ts` | Untracked | New AI catalog callable |
| `Backend/functions/src/ai-catalog/topicClusterEngine.ts` | Untracked | New AI catalog callable |
| `Backend/functions/src/billing/affiliateTierHelper.ts` | Untracked | New billing helper callable |
| `Backend/functions/src/ingestion/manualEntry.ts` | Untracked | New ingestion callable |
| `Backend/functions/src/ingestion/providers/googleBooksProvider.ts` | Untracked | New ingestion provider |
| `Backend/functions/src/ingestion/providers/substackMediumProvider.ts` | Untracked | New ingestion provider |
| `Backend/functions/src/ingestion/providers/youtubeProvider.ts` | Untracked | New ingestion provider |
| `Backend/functions/src/search/catalogSearch.ts` | Untracked | New search callable |
| `Backend/rules-tests/distinctives.rules.test.ts` | Untracked | New Firestore rules test |
| `Backend/functions/src/selahConnection 2.ts` | Untracked | **FILENAME HAS SPACE — rename before deploy** |
| `AMENAPP/AMENAPP/Features/Bridges/NoteGive/` | Untracked (directory) | New iOS bridge files; verify Xcode target membership |
| `AMENAPP/AMENAPP/Features/Bridges/VerseResonance/DailyVerseCard.swift` | Untracked | New Swift file; verify target membership |
| `AMENAPP/AMENAPP/Features/Bridges/Visits/VisitVerificationService.swift` | Untracked | New Swift file; verify target membership |

**CRITICAL:** `selahConnection 2.ts` has a space in the filename. Firebase CLI will reject this. Rename to `selahConnectionV2.ts` before any deploy attempt.

**Quota note:** us-central1 is at ~999-1000/1000 Cloud Run services. ALL new functions must deploy to us-east1. Add each to the Interim Region Table in `docs/FUNCTION_INVENTORY.md`. Deploy command format: `firebase deploy --only functions:creator:functionName --project amen-5e359`

---

## Emulator Tests

- **Rules tests:** FOUND — `Backend/rules-tests/` contains 30+ `.rules.test.ts` files: account-lifecycle, account-rtdb, account-storage, action-intelligence, amen-connect, berean-pulse, church-notes (media, intelligence, storage, account-deletion), communication-os, communities, contextual-action-layer, current-stack, **distinctives** (new untracked), dynamic-reply-preview, gap-p0-dm-and-minor, gap-p0-sensitive-collections, messaging-private-actions, minor-safe-dm, note-share-security-closers, pinned-post, trust-safety-launch. Also `emulatorConfig.ts`, `jest.globalSetup.ts`, `jest.globalTeardown.ts`. **Run status: not verified this session** (requires emulator + `npm test` in `Backend/rules-tests/`)
- **Function unit tests:** FOUND — `functions/tests/` and `functions/test/` contain: `healthyImmersiveMediaCallableGuards.test.js`, `mediaSecurityRules.test.js`, `musicAttachmentResolver.test.js`, `notificationRoutingPipeline.test.ts`, `actionIntelligenceFunctions.test.js`, `ageTier.test.js`, `aiPipeline.test.js`, `churchNotesMediaPipeline.test.js`, `connectorFetch.test.js`, `feedContextFunctions.test.js`, `moderation-safety.test.js`, `phoneAuthPii.test.js`, `rules.spec.js`, `safety-rules.test.js`. **Run status: not verified this session.**
- **Backend/functions `__tests__`:** FOUND — 22+ test files covering AI App Check enforcement, AI backend ownership, Berean AI disclosure, history sanitization, quota, rate limiting, realtime, streaming safety, formation governor, media callables, note share, pulse engine, semantic intelligence, smart attachments, social graph privacy/RAG ACL/rate limiting, ThinkFirst validator. **Run status: not verified this session.**

To run emulator tests (human step):
```bash
# From repo root only (NEVER from a subdirectory)
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
firebase emulators:exec \
  --project amen-5e359 \
  --only firestore,functions,storage \
  "cd Backend/rules-tests && npm test"
```

---

## Module D Addendum — 2026-06-16 Current Pass

Current Git branch observed by this agent: `app-store-readiness-overnight`.

### Access-Control Matrix

Created `AMENAPP/Docs/Readiness/BACKEND_ACCESS_CONTROL_MATRIX.md` as the Module D source-of-truth spine for roles, operations, field partitioning, and plane-consistency status. All rows remain `UNVERIFIED` until emulator/function tests run.

### Source Fix Staged, Not Deployed

| ID | File | Lane | Status |
|---|---|---|---|
| D-IDENTITY-001 | `Backend/functions/src/globalResilience/trustScoring.ts` | GREEN source fix + YELLOW deploy | Patched `evaluateTrustProfile` and `detectRiskPatterns` so callers can only target their own `userId` unless they have an admin custom claim. Privileged trust mutations (`verification_approved`, `profile_photo_match`, `abuse_report`) now require an admin claim. |

Deploy remains human-gated. After verification, deploy only the affected creator functions, not the entire codebase.

### Additional Findings

| ID | Severity | Finding | Required Action |
|---|---|---|---|
| D-ADMIN-001 | P1 | Some admin callables still use Firestore user-doc `isAdmin` as authority (`digestBuilder.ts`, `crisisBulletins.ts`). | Migrate to server-verified custom claims or document a deliberate server-only mirror policy. |
| D-STORAGE-001 | P1 | Public storage reads remain for `uploads/approved`, organization media, church media, and event media. | Link reads to Firestore visibility/moderation status or record T&S approval for public CDN behavior. |
| D-STORAGE-002 | P1 | `profilePhotos/{uid}/{photoId}` still allows direct client owner writes outside quarantine-first upload. | Lock this path to Cloud Functions after quarantine deployment is confirmed live. |

### Verification

`npm --prefix Backend/functions run build` passed after the source patch in this pass. Emulator tests are still human-gated unless explicitly run:

```bash
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
firebase emulators:exec --project amen-5e359 --only firestore,functions,storage "cd Backend/rules-tests && npm test"
```
