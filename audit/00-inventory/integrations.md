# AMEN iOS App — External Integrations

**Audit Date:** 2026-06-07  
**Status:** Mixed (some integrated end-to-end, some in development)

---

## Payment Processing

### Stripe (Subscriptions, Connect, Payouts)
- **Status:** ✅ LIVE
- **Wired End-to-End:** YES
- **Functions:** stripeFunctions.js, stripeWebhook.js (index.js gen-1)
- **Collections:** users/{uid}/entitlements, stripe/customers/{uid}
- **Callables:**
  - `createSubscription(productId, priceId)` — Stripe Billing Portal link
  - `cancelAllSubscriptions()` — Auth-gated, self-subscription only
- **Webhook:** stripeWebhook (HTTPS endpoint) — signature verified
- **Fail Mode:** User gets error message, can retry from Settings
- **Currency:** USD (App Store for regional pricing via StoreKit 2)
- **Commission:** Apple 30% + Stripe fees (exact % TBD)

### StoreKit 2 (Apple In-App Purchases)
- **Status:** ✅ LIVE
- **SKUs:**
  - com.amen.pro.monthly ($9.99/mo)
  - com.amen.pro.yearly ($79.99/yr)
  - com.amen.pro.lifetime ($199.99)
  - com.amen.spaces.member.monthly ($4.99/mo)
  - com.amen.spaces.founding.monthly ($9.99/mo)
- **File:** PremiumManager.swift (loadProducts, subscriptionState observer)
- **Entitlements:** catalogEntitlements.js validates purchases
- **Fail Mode:** Purchase dialog fails, user can retry

---

## Search & Discovery

### Algolia
- **Status:** ✅ LIVE (with Firestore fallback)
- **Wired End-to-End:** YES
- **Indexes:** posts, users, works (catalog)
- **Function:** algoliaSync.js (triggered on new posts)
- **Search UIs:** SearchView, DiscoveryFiltersView, catalogSearch.js callable
- **Fail Mode:** Falls back to Firestore direct query (slower, but works)
- **Key Management:** Algolia app ID + write-only API key in Remote Config

### Firestore Full-Text Search (Fallback)
- **Status:** ✅ BUILT-IN
- **Query Pattern:** Collection query with WHERE + ORDER_BY constraints
- **Used When:** Algolia unavailable or not yet synced
- **Performance:** Slower (< 1000 documents recommended per query)

---

## AI & LLM Services

### Google Gemini (Berean, Formation, Summarization)
- **Status:** ✅ LIVE
- **Endpoint:** Google AI Studio REST API
- **Functions:**
  - callModelRouter.js routes all LLM calls
  - amenLive.js — Live session summarization
  - digestBuilder.js — Intelligence brief synthesis
  - berean_os_*.js — Formation guidance (12 functions)
  - churchNotesAICallables.js — Sermon note summarization
- **Key:** BEREAN_LLM_KEY from Remote Config
- **Embeddings:** Same key (EMBEDDING_KEY = BEREAN_LLM_KEY)
- **Fail Mode:** User sees "AI unavailable" error, content still loads without AI
- **Rate Limiting:** Per-user call limits in AppConfig (callModelRouter enforces)

### Claude / Cohere (Optional Alternative)
- **Status:** ❌ NOT INTEGRATED (referenced in callModelRouter.js as option, not active)
- **Fallback Model:** If Gemini is down, config can switch to Claude/Cohere
- **Configuration:** Route preference in callModelRouter

### NVIDIA NeMo Guardrails (AI Safety)
- **Status:** ❌ LEGACY (nvidiaClient.js exists but unused in current codebase)
- **Note:** Likely deprecated in favor of built-in moderation pipelines

---

## Content & Media

### YouTube Provider (Ingestion)
- **Status:** ✅ LIVE (ingestion pipeline)
- **File:** functions/ingestion/providers/youtubeProvider.js
- **Purpose:** Import YouTube videos into catalog as works
- **API:** YouTube Data API v3
- **Flow:** ingestionEngine → youtubeProvider → create works/{workId}
- **Fail Mode:** Import job marked failed, user notified

### Spotify Provider (Podcast/Music)
- **Status:** ✅ LIVE (ingestion pipeline)
- **File:** functions/ingestion/providers/spotifyProvider.js
- **Purpose:** Index Spotify playlists, podcasts as catalog items
- **API:** Spotify Web API
- **Fail Mode:** Import job marked failed

### Substack Provider (Newsletter Ingestion)
- **Status:** ✅ LIVE (ingestion pipeline)
- **File:** functions/ingestion/providers/substackProvider.js
- **Purpose:** Import Substack newsletter archives
- **API:** Substack public RSS feeds (or internal API)
- **Fail Mode:** Import marked failed

### Podcast RSS Provider
- **Status:** ✅ LIVE (ingestion pipeline)
- **File:** functions/ingestion/providers/podcastRSSProvider.js
- **Purpose:** Index podcasts from RSS feeds
- **API:** Standard RSS/Atom feed protocol
- **Fail Mode:** Import marked failed

### Google Books Provider (Book Catalog)
- **Status:** ✅ LIVE (ingestion pipeline)
- **File:** functions/ingestion/providers/googleBooksProvider.js
- **Purpose:** Import book metadata into catalog
- **API:** Google Books API
- **Fail Mode:** Import marked failed

---

## Bible & Scripture

### Selah Bible Provider Adapter
- **Status:** ✅ LIVE
- **File:** functions/selah/bibleProviderAdapter.js
- **Active Providers:**
  - YouVersion API (primary)
  - OpenLicense Verses (free fallback)
  - BibleProject (optional)
- **Function:** bibleProviderAdapter (callable) — returns scripture text
- **Collections:** selahNotes/{noteId}, discernmentChecks (context for interpretation)
- **Fail Mode:** "Scripture unavailable" message, user can retry

### OpenLicense Verse Service
- **Status:** ✅ LIVE
- **File:** functions/selah/openLicenseVerseService.js
- **Purpose:** Free Bible text (OpenLicense translations)
- **API:** openbiblproject.com REST API (no key required)
- **Used When:** YouVersion quota exceeded

### YouVersion Bible API
- **Status:** ✅ LIVE (primary)
- **API Key:** In Remote Config
- **Available Versions:** 1000+ Bible translations
- **Fail Mode:** Falls back to OpenLicense

---

## Spiritual Discernment

### Discernment Engine (AI Interpretation)
- **Status:** ✅ LIVE
- **File:** functions/selah/discernmentEngine.js
- **Purpose:** AI analysis of scripture passages for personal relevance
- **Uses:** Gemini LLM (via callModelRouter)
- **Collections:** discernmentChecks/{checkId} (stores results)
- **Visibility Rules:** Private by default, shareable to thread participants only
- **Fail Mode:** Discernment unavailable, scripture still readable

### Discernment Prompts Library
- **Status:** ✅ LIVE
- **File:** functions/selah/discernmentPrompts.js
- **Purpose:** Pre-crafted AI prompts for guided reflection
- **Data:** Hardcoded prompt templates (not config-driven)

---

## Safety & Trust

### NCMEC CyberTipline Integration
- **Status:** ✅ LIVE (automated)
- **File:** functions/ncmecReporter.js
- **Trigger:** CSAM detection (imageModeration.js → aiModeration.js → CSAM score > threshold)
- **API:** National Center for Missing & Exploited Children CyberTipline HTTPS endpoint
- **Reporting:** Automatic (no human gate — mandatory by US law)
- **Record:** crisisEscalations/{uid}/{timestamp} (human follow-up)
- **Key:** NCMEC_API_KEY in Remote Config
- **Fail Mode:** Report queued for retry (never silent failure)

---

## Communication & Messaging

### Firebase Cloud Messaging (Push Notifications)
- **Status:** ✅ LIVE
- **Service:** FCM token management in AppDelegate
- **Listener:** NotificationService.shared.startListening() triggers CloudFunction
- **Functions:**
  - pushNotifications.js (v1, Shabbat-aware)
  - pushNotifications_enhanced.js
  - notificationRoutingPipeline.entry.ts (v2, deduplication)
- **Fail Mode:** Push silent fails (user sees badge count, may miss notification)

### Firebase Realtime Database (Comments, Interactions)
- **Status:** ✅ LIVE
- **Usage:** Real-time post interactions (likes, comments)
- **Function:** onRealtimeCommentCreate (v2functions.js) — Firestore trigger
- **Collections Synced:** /postInteractions/{postId}/comments/{commentId}
- **Fail Mode:** Writes to Firestore only (RTDB loss won't break app)

---

## Analytics & Monitoring

### Firebase Crashlytics
- **Status:** ✅ LIVE
- **Init:** AppDelegate.FirebaseCrashlytics.crashlytics()
- **Purpose:** App crash reporting, error tracking
- **Console:** Google Firebase Console → AMEN-5e359 project
- **Fail Mode:** Non-blocking; crashes logged locally if Crashlytics unavailable

### Firebase Analytics
- **Status:** ✅ LIVE (implied by FirebaseCore)
- **Purpose:** User event tracking, screen views
- **Data:** Sent to Google Analytics (Firebase-integrated)

---

## Location & Maps

### Google Places API (Find Church)
- **Status:** ⚠️ PARTIAL (referenced in FindChurchView, integration TBD)
- **Purpose:** Church location search, geocoding
- **Fail Mode:** Falls back to manual church database search

### Apple Maps (Alternative to Google)
- **Status:** ⚠️ ALTERNATIVE (available, not confirmed as primary)
- **Purpose:** Church location display, routing to service
- **Used In:** FindChurchView (map view)

---

## Live Streaming

### LiveKit (Spaces Live Sessions)
- **Status:** ⚠️ INTEGRATION IN PROGRESS
- **Files:** functions/spaces/*Livekit*.js
- **Purpose:** Real-time video/audio for spaces events
- **Collections:** amen_live_sessions/{sessionId} (created by CF)
- **Fail Mode:** User cannot start live, can post static instead

---

## Integration Summary Table

| Integration | Status | End-to-End | Fail Mode | Criticality |
|-------------|--------|-----------|-----------|-----------|
| Stripe (payments) | ✅ LIVE | YES | Error message + retry | P0 (revenue) |
| StoreKit 2 (IAP) | ✅ LIVE | YES | Dialog fails, can retry | P0 (revenue) |
| Algolia (search) | ✅ LIVE | YES | Falls back to Firestore | P2 (convenience) |
| Gemini AI (LLM) | ✅ LIVE | YES | "AI unavailable" message | P2 (feature) |
| Selah Bible | ✅ LIVE | YES | "Scripture unavailable" | P2 (feature) |
| YouVersion Bible | ✅ LIVE | YES | Falls back to OpenLicense | P2 (feature) |
| NCMEC Reporting | ✅ LIVE | YES | Queued + retry | P0 (legal compliance) |
| FCM (push) | ✅ LIVE | YES | Silent (badge still shows) | P2 (notification) |
| RTDB (comments) | ✅ LIVE | PARTIAL | Firestore fallback | P1 (real-time) |
| Crashlytics (monitoring) | ✅ LIVE | PARTIAL | Non-blocking | P3 (observability) |
| YouTube Ingestion | ✅ LIVE | PARTIAL | Import job fails | P3 (onboarding) |
| Spotify Ingestion | ✅ LIVE | PARTIAL | Import job fails | P3 (onboarding) |
| Google Places | ⚠️ TBD | NO | Manual search | P3 (find church) |
| LiveKit (live video) | ⚠️ IN PROGRESS | NO | Cannot stream | P3 (spaces) |
| NeMo Guardrails | ❌ LEGACY | NO | Not used | Deprecated |

