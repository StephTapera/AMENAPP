# AMEN iOS App — Cloud Functions Inventory

**Total Functions:** 200+  
**Generation Split:** Gen 1 (index.js) + Gen 2 (v2functions.js, v2triggers/)  
**Environments:** Emulator (.env.local, gitignored), Production (Remote Config)  

## Gen 2 Functions (v2functions.js)

All v2 functions use Firebase Functions SDK v2 (modern runtime, better concurrency).

### onRealtimeCommentCreate (v2functions.js:25)

- **Trigger Type:** Firestore `onValueCreated` (RTDB path: `/postInteractions/{postId}/comments/{commentId}`)
- **Generation:** Gen 2
- **Auth Requirement:** No context.auth check (CF runs as Admin SDK)
- **Collections Touched:** 
  - postInteractions/{postId}/comments/{commentId} (read)
  - users/{uid}/notifications (write)
- **Behavior:** 
  - Detects if comment is reply (parentId field)
  - Sends notification to parent comment author or post author
  - Checks Shabbat gate: `isSundayForUser(authorId)` → skips if true
  - Sends FCM push notification
- **Short-Circuiting:** Skips self-replies, skipped when Shabbat active
- **Replication:** Also exists in v2triggers/v2functions.js (dev/testing copy)

---

## Gen 1 Functions (index.js)

### Subscription Management

#### cancelAllSubscriptions (index.js, stripe section)
- **Trigger Type:** Callable (https)
- **Generation:** Gen 1
- **Auth Requirement:** YES, `context.auth` required (throws if no auth)
- **Collections Touched:** 
  - users/{uid}/entitlements (read)
  - stripe/customers/{uid} (write)
- **Behavior:** Cancels all active Stripe subscriptions for caller
- **Safety:** Auth-gated, only self-cancellation allowed

#### stripeWebhook (index.js, stripe section)
- **Trigger Type:** HTTPS endpoint (not callable)
- **Generation:** Gen 1
- **Auth Requirement:** NO (webhook verification via Stripe signature)
- **Collections Touched:** 
  - users/{uid}/billing/transactions (write)
  - stripe/customers/{uid} (update)
- **Behavior:** Handles Stripe charge updates, refunds, disputes
- **Verification:** Stripe signature validation (must match STRIPE_SIGNING_SECRET)

---

## Intelligence Functions (intelligence/ subdirectory)

These are foundational for the Living Intelligence system.

### amenLive.js & amenLiveCallable.js
- **Trigger Type:** `amenLive.js` = Firestore trigger, `.js` callable
- **Auth Requirement:** Context.auth for callable
- **Collections:** amen_live_sessions/{sessionId} (write), users/{uid}/notifications (write)
- **Purpose:** Start/end AMEN Live sessions, notify followers

### churchPulse.js & churchPulseCallable.js
- **Trigger Type:** Scheduled + callable
- **Collections:** church_pulse/{churchId} (write), churches/{churchId} (read)
- **Purpose:** Compute church health metrics (activity, engagement, prayer)
- **Recompute:** Triggered by scheduler (refreshChurchPulses)

### digestBuilder.js
- **Trigger Type:** Firestore trigger (on user activity)
- **Collections:** intelligence_briefs/{userId} (write), posts/{postId} (read), prayers/{prayerId} (read), needs/{needId} (read)
- **Purpose:** Synthesize daily intelligence brief card
- **AI Requirement:** Calls callModelRouter for summarization

### worldResponse.js & worldResponseCallable.js
- **Trigger Type:** Callable + background trigger
- **Collections:** world_response_queue/{eventId} (read), amen_live_sessions (write for GLOBAL card distribution)
- **Purpose:** Global response card generation, world-scale prayer coordination
- **Admin-Only Seeding:** seedWorldResponseSources callable (admin)

### rankingBrain.js
- **Trigger Type:** Firestore trigger
- **Collections:** posts/{postId} (read), prayers/{prayerId} (read), opportunity_graph/{nodeId} (write)
- **Purpose:** ML-based ranking algorithm for feed ordering, opportunity ranking
- **Replication:** Also exists in v2triggers/ directory

### callModelRouter.js
- **Trigger Type:** Callable (internal)
- **Auth Requirement:** Admin SDK or specific service account
- **Purpose:** Route AI calls to Gemini/Claude/Cohere based on model config
- **Environment Variables:** 
  - `BEREAN_LLM_KEY` (Gemini API key) — from .env.local
  - `EMBEDDING_KEY` (same as BEREAN_LLM_KEY)

### contracts.js (intelligence/)
- **Trigger Type:** Data definitions (no trigger)
- **Gen2 Only:** YES (v2triggers/intelligence/contracts.js contains canonical definitions)
- **Purpose:** Exports frozen contract types: CapabilityTier, Domain, FormationCardKind, etc.
- **Note:** TypeScript file (contracts.ts) with .js export

### needDetection.js
- **Collections:** needs/{needId} (write), posts/{postId} (read), prayers/{prayerId} (read)
- **Purpose:** Classify post/prayer as community need (material, prayer, volunteer, donation, community)
- **Callable:** classifyPostNeed(postId, contentType)

### prayerGraph.js
- **Collections:** prayers/{prayerId} (read), opportunity_graph (write prayer-need edges)
- **Purpose:** Build prayer-response opportunity graph (who should pray for what)

### opportunityGraph.js
- **Collections:** opportunity_graph/{nodeId} (write), volunteerOpportunities (read), mentorshipRequests (read)
- **Purpose:** ML ranking of volunteer/mentorship opportunities by user relevance

---

## Berean OS Functions

### bereanFunctions.js, bereanFeaturesFunctions.js, bereanFeaturesFunctions.js
- **Collections Touched:**
  - berean/{uid}/memory/{memoryId} (write)
  - berean/{uid}/threads/{threadId} (write)
  - berean/{uid}/messages/{messageId} (write, assistant role only)
- **Purpose:** AI formation assistant, daily guide, memory graph updates
- **Auth Requirement:** User-scoped (berean/{uid} requires uid == auth.uid)

### berean_os_*.js (12 specialized files)
- `berean_os_advisory.js` — Advisory boards, wisdom synthesis
- `berean_os_debate.js` — Theological debate facilitation
- `berean_os_documents.js` — Document management
- `berean_os_graph.js` — Memory graph topology
- `berean_os_memory.js` — Memory node creation/retrieval
- `berean_os_mentor.js` — Mentorship intelligence
- `berean_os_perspectives.js` — Multi-perspective synthesis
- `berean_os_projects.js` — Formation project management
- `berean_os_research.js` — Deep research compilation
- `berean_os_sources.js` — Source tracking, citation
- `berean_os_truth.js` — Truth claim analysis
- `berean_os_wisdom.js` — Wisdom synthesis from notes

---

## Church Notes Functions

### churchNotesAICallables.js
- **Callable:** AI-powered note summarization, sermon extraction
- **Collections:** churchNotes/{noteId} (write), users/{uid}/media (read transcripts)
- **Purpose:** Process uploaded audio, generate sermon notes, key points extraction

### churchNotesMediaPipeline.js
- **Trigger Type:** Storage object finalize (audio upload)
- **Purpose:** Transcode audio, extract transcripts, queue for AI processing
- **Integration:** Whisper API or similar transcription service

### transcribeChurchNotesAudio.js
- **Collections:** churchNotes/{noteId}/transcriptTracks/{trackId} (write)
- **Purpose:** Audio transcription service integration

### aiChurchNotes.js
- **Purpose:** AI-powered insights on sermon notes (summary, themes, action items)

---

## Creator & Content Publishing

### creatorDraftFunctions.js
- **Collections:** users/{uid}/drafts/{draftId} (read/write), posts (write on publish)
- **Purpose:** Auto-save drafts, version control, publish workflow

### publishPipelineFunctions.js
- **Collections:** posts/{postId} (write), users/{uid}/actionThreads (write)
- **Purpose:** Publishing coordination, schedule posts, notify followers

### studioFunctions.js, studioExport.js, studioImageGeneration.js
- **Purpose:** Studio workspace management, media export, AI image generation (DALL-E/Midjourney)
- **Auth:** User-scoped (studio/{uid})

---

## Moderation & Safety

### aiModeration.js, imageModeration.js
- **Trigger Type:** Firestore `onDocumentCreated` (posts, comments, images)
- **Collections Touched:** 
  - posts/{postId}, comments/{commentId} (read)
  - moderationQueue/{itemId} (write)
  - humanReviewQueue/{itemId} (write if escalated)
- **Scoring:** Toxicity, spam, CSAM, grooming, doxxing, self-harm (each 0.0-1.0)
- **Decision:** EnforcementAction enum (allow, nudge, hold_review, shadow_restrict, remove_permanent, ban)
- **Confidence:** decisionConfidence field (0.0-1.0)

### ncmecReporter.js
- **Trigger Type:** CSAM detection (ai-triggered)
- **Collections:** posts/{postId} (read), mediaModeration/{docId} (read), crisisEscalations/{uid}/{ts} (write)
- **Purpose:** Report suspected CSAM to NCMEC CyberTipline API
- **External Integration:** NCMEC CyberTipline endpoint
- **Escalation:** Creates crisisEscalations/{uid} document for human follow-up

### reportFunctions.js
- **Collections:** userReports/{reportId} (write), moderationQueue (write)
- **Purpose:** Handle user-submitted reports (content, user, community)
- **Callable:** submitReport(contentId, contentType, reason)

### adminModerationFunctions.js
- **Collections:** moderationQueue/{itemId} (update), auditLog/{eventId} (write)
- **Purpose:** Admin actions on moderation queue (approve, reject, appeal)
- **Auth:** Moderator+ claims only (enforced by callable auth check)

---

## Authentication & User Account

### twoFactorAuth.js
- **Callable:** Enable/disable 2FA, verify code
- **Collections:** users/{uid}/private/2fa_config (write)
- **Provider:** Firebase Phone Auth or TOTP (code generation)

### accountDeactivation.js, accountDeletion.js
- **Collections:** users/{uid} (update isDeleted flag), all user subcollections (soft-delete)
- **Purpose:** GDPR data subject rights (deactivate = hide profile, deletion = wipe data)
- **Timeline:** Deletion takes 30 days (grace period for reversal)

### phoneAuthOnly.js, phoneAuthRateLimit.js
- **Purpose:** Phone number authentication (alternative to email/social)
- **Rate Limiting:** 3 attempts per phone per 24hr window

---

## Search & Discovery

### algoliaSync.js
- **Trigger Type:** Firestore `onDocumentCreated` (posts, profiles, works)
- **Purpose:** Index new posts/users to Algolia for full-text search
- **Fallback:** Firestore direct query if Algolia is unavailable
- **Index Names:** `posts`, `users`, `works`

### search/catalogSearch.js
- **Callable:** Search catalog (works) by topic/creator/keyword
- **Collections:** works/{workId} (read), follows/{uid}_{creatorId} (read for visibility check)

### search/followKnowledge.js
- **Purpose:** Search user's followed topics/creators

---

## Notification & Engagement

### pushNotifications.js, pushNotifications_enhanced.js
- **Trigger Type:** Firestore listener on notifications subcollection
- **Purpose:** Send FCM push notifications for user engagement
- **Shabbat Guard:** Checks `isSundayForUser()` before sending
- **Rate Limiting:** maxNotifications per user per hour

### notificationRoutingPipeline.entry.ts
- **Trigger Type:** Callable (TypeScript)
- **Purpose:** Centralized notification routing, deduplication, batching
- **Collections:** users/{uid}/notifications (write), notificationCounts/{userId} (update)

### engagementNotifications.js
- **Purpose:** Trigger notifications for engagement milestones (100 likes, first follower, etc)

---

## Billing & Monetization

### stripeFunctions.js
- **Callable:** Create/cancel subscriptions, manage payment methods
- **Auth:** User-scoped (caller is customer)
- **External:** Stripe API (requires STRIPE_SECRET_KEY from Remote Config)

### stripeWebhook.js
- **Trigger Type:** HTTPS endpoint (not callable)
- **Verification:** Stripe signature (STRIPE_SIGNING_SECRET)
- **Purpose:** Handle charge.updated, charge.refunded, invoice.payment_failed events

### catalog/billing/catalogEntitlements.js
- **Callable:** Validate StoreKit purchases, grant catalog access
- **Collections:** users/{uid}/entitlements/catalog (write)
- **Purpose:** Cross-platform entitlement verification (App Store + Stripe)

---

## Catalog & Knowledge Network

### ingestionEngine.js, importHub.js
- **Trigger Type:** Callable (user-initiated)
- **Purpose:** Ingest books, podcasts, articles, videos from external providers
- **Collections:** ingestionJobs/{jobId}, works/{workId} (write)

### ingestion/providers/*.js (5 providers)
- `googleBooksProvider.js` — Google Books API
- `podcastRSSProvider.js` — Podcast RSS feeds
- `spotifyProvider.js` — Spotify (music/podcasts)
- `substackProvider.js` — Substack newsletters
- `youtubeProvider.js` — YouTube videos (via Data API)
- **Auth:** Each provider has own API key (stored in Remote Config)

---

## Selah / Bible Functions

### selah/bibleProviderAdapter.js
- **Purpose:** Route bible requests to active provider (YouVersion, OpenLicense, custom)
- **Providers:** YouVersion API, OpenLicense Verses, BibleProject
- **Collections:** selahNotes/{noteId}, discernmentChecks/{checkId} (read for context)

### selah/discernmentEngine.js
- **Purpose:** Spiritual discernment check for scripture interpretation
- **Callable:** evaluateDiscernment(scriptureReference, userContext)

### selah/openLicenseVerseService.js
- **Purpose:** Free Bible API for OpenLicense texts
- **Integration:** openBibleProject.com

---

## Middleware & Utilities

### middleware/requireAuth.js
- **Purpose:** Auth guard wrapper for callables
- **Check:** `if (!context.auth) throw new Error("Unauthenticated")`

### rateLimiter.js
- **Purpose:** Token bucket rate limiting for function calls
- **Key Format:** `{uid}:{functionName}:{window}`
- **Collections:** `rateLimit/{uid}/{key}` (read/write counters)

### retryHelper.js
- **Purpose:** Exponential backoff retry logic for flaky external APIs

---

## Environment & Secrets

### .env.local (gitignored template example)
```
BEREAN_LLM_KEY=your-gemini-api-key-here
EMBEDDING_KEY=your-gemini-api-key-here
```

### Remote Config Keys (Production)
- `stripe_secret_key` — Stripe API key
- `stripe_signing_secret` — Webhook verification
- `ncmec_api_key` — NCMEC CyberTipline
- `algolia_app_id` — Algolia application ID
- `algolia_api_key` — Algolia API key (write-only)
- `openai_api_key` — (if OpenAI is used instead of Gemini)
- `cohere_api_key` — (if Cohere is used for embeddings)
- Various feature flags (boolean)

---

## Summary Table

| Category | Count | Gen | Auth | CF-Only |
|----------|-------|-----|------|---------|
| Intelligence | 12 | 1+2 | Mixed | Partial |
| Berean OS | 13 | 1 | Yes | Yes |
| Church Notes | 4 | 1 | Yes | Yes |
| Creator/Publish | 3 | 1 | Yes | Partial |
| Moderation | 5 | 1 | No (triggers) | Yes |
| Auth & Account | 4 | 1 | Yes (callable) | Yes |
| Search & Catalog | 8 | 1 | Mixed | Partial |
| Notification | 5 | 1 | No (triggers) | Yes |
| Billing & Payment | 3 | 1 | Yes | Yes |
| Utilities | 3 | 1 | N/A | N/A |
| **TOTAL** | **60+** | **1** | **Yes for Callables** | **90%** |
| **Gen 2** | **1** | **2** | **No** | **Yes** |

