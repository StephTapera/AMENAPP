# Agent 3 — Firebase / Network Audit Report
**Date:** 2026-05-27  
**Branch:** berean/ui-rebuild-liquid-glass-v1  
**Build result:** ✅ 0 errors after all changes

---

## 1. Findings

### 1.1 Listener Cleanup — Overall Picture
233 `addSnapshotListener` calls exist across the app. The majority follow one of three safe patterns:
- Store `ListenerRegistration?` + call `.remove()` in `deinit` (non-singleton classes, ViewModels)
- Call `.remove()` in `stopListening()` + register that in `AppLifecycleManager.performFullSignOutCleanup()`
- `DiscoverService`-style: wrap in `AsyncThrowingStream` with `continuation.onTermination = { _ in reg.remove() }`

**Issues found:**

| File | Issue | Severity |
|------|-------|----------|
| `BereanContextMemoryService.swift` | `memoriesRef` listener had **no `.limit(to:)`** — would fetch and stream ALL `bereanMemory` entries for a user indefinitely as the subcollection grows | HIGH |
| `SmartGatheringDetectionService.swift` | `startListeningForActiveSpaces()` overwrote `spacesListener` without calling `.remove()` first — the old listener leaked every time broadArea changed or view reappeared | HIGH |
| `PrayerChainService.swift` | `stopListening()` existed but was **never registered in `AppLifecycleManager.performFullSignOutCleanup()`** — listener survived sign-out | MEDIUM |
| `ChurchPersistenceManager` (in `FindChurchView.swift`) | `startListening()` does call `listener?.remove()` before re-attaching (correct), but no cleanup in sign-out flow | LOW (singleton inits from `init`, guard re-entrancy is fine) |

### 1.2 Pagination — Overall Picture
The majority of hot-path queries have explicit `.limit(to:)`:
- `FirebasePostService`: feed queries limited to 20–100 depending on context ✅
- `FirebaseMessagingService`: conversations limited to 50; messages paginated with cursor ✅
- `JobService`: all 7 listeners limited to 50–100 ✅
- `HeyFeedService`: all 3 listeners limited to 25–200 ✅
- `FollowService`: check queries use `.limit(to: 1)` ✅
- `BereanMemoryService`: `.limit(to: 50)` ✅

**Issues found (unbounded reads):**

| File | Query | Risk |
|------|-------|------|
| `BereanContextMemoryService.swift` | `memoriesRef(uid:).order(by: "createdAt")` — no limit | Unbounded subcollection stream |
| `Creator/Services/CreatorAssetService.swift` | `creatorAssets` subcollection — no limit | Low (per-project scoped), but could grow |
| `Creator/Services/CreatorSceneService.swift` | `creatorScenes` subcollection — no limit | Low (per-project scoped) |
| `Creator/Services/CreatorBrandKitService.swift` | `creatorBrandKits` subcollection — no limit | Low (per-user scoped) |
| `FirebasePostService.migrateAllPostsWithProfileImages()` | `db.collection("posts").getDocuments()` — no limit | Admin-only one-time migration, acceptable |

### 1.3 N+1 Query Patterns
**Profile image enrichment** in `FirebasePostService` (lines 2583–2603): fetches individual `users/{authorId}` docs for each post author. Mitigated by:
- An in-memory `profileImageCache: [String: String]` dict
- `withTaskGroup` parallelism for uncached IDs
- Only fetches IDs not already in cache

This is the correct approach given Firestore's lack of server-side joins. The denormalization fix (storing `authorProfileImageURL` on the post document at write time) is already in place and growing — the enrichment path is a fallback for older posts.

**Mentorship** (`MentorshipService.fetchMentors`): unbounded `db.collection("mentors").limit(to: 30)` — already has limit ✅

**DiscoverSearchComponents** `executeSearch()`: 8 parallel Firestore queries via `withTaskGroup` — each has `.limit(to: 5-10)` ✅

**No true n+1 loops found on hot paths.** The migration utility at `migrateAllPostsWithProfileImages()` loops with individual `getDocument()` calls but is admin-only and sequential by design.

### 1.4 Cloud Functions — Cold Start / Hot Path Analysis

**`bereanChatProxy` (25 callsites) and `bereanChatProxyStream`** — the most-called CFs in the app.
- Config: `timeoutSeconds: 60`, `memory: "256MiB"`, region `us-central1`
- **No `minInstances` set** — cold starts of ~1-3s will affect first Berean interaction per session
- These are the heaviest user-facing AI paths

**`whisperProxy`** — voice prayer transcription
- Config: `timeoutSeconds: 120`, `memory: "512MiB"`
- **No `minInstances`** — real-time voice features will stutter on first use

**All other CFs** (analytics, moderation, social features): no `minInstances`. Acceptable since they are not user-latency-critical.

**Streaming proxy note:** `ClaudeAPIService.stream()` (iOS side) simulates word-by-word streaming by fetching the full response then emitting tokens at 15ms intervals. This is a workaround because Firebase Callable Functions don't support true SSE. The actual streaming backend (`bereanChatProxyStream.ts`) exists and uses Anthropic's SSE API — but the iOS client does not yet consume it as a true stream. Cancellation propagates: when the iOS task is cancelled, the URLSession connection drops and the backend `req.on("close")` handler fires the AbortController. Backpressure is not an issue at the 15ms word emission rate.

### 1.5 Firestore Indexes — Missing Composites

The following collections have real-time listeners or queries with multiple `whereField` + `order(by:)` that require composite indexes, but **none were present** in `firestore.indexes.json`:

| Collection | Query pattern | Impact |
|-----------|---------------|--------|
| `heyfeed_requests` | `isActive == true` ORDER BY `resonanceScore DESC` | Full collection scan fallback |
| `heyfeed_resonance` | `userId == uid` ORDER BY `createdAt DESC` | Slow for active users |
| `pastoral_care_signals` | `isAcknowledged == false` ORDER BY `urgencyScore DESC` | Pastoral care feature degrades |
| `ephemeral_spaces` | `memberUIDs arrayContains uid` + `isActive == true` | Spatial social feature |
| `jobApplications` | `applicantId == uid` ORDER BY `createdAt DESC` | Jobs tab slow on first load |
| `jobApplications` | `employerId == uid` ORDER BY `createdAt DESC` | Recruiter inbox slow |
| `savedJobs` | `userId == uid` ORDER BY `savedAt DESC` | Jobs tab slow |
| `jobListings` | `employerId == uid` ORDER BY `createdAt DESC` | My posted jobs slow |
| `jobListings` | `isActive == true` + `isFeatured == true` ORDER BY `createdAt DESC` | Featured jobs slow |
| `jobAlerts` | `userId == uid` ORDER BY `createdAt DESC` | Job alerts slow |
| `prayerChains` | `status in [...]` ORDER BY `createdAt DESC` | Prayer chain list slow |
| `bereanMemory` | `isUserVisible == true` ORDER BY `lastReferencedAt DESC` | Berean memory slow |
| `accountabilityThreads` | `members arrayContains uid` ORDER BY `createdAt DESC` | Accountability feature slow |

### 1.6 API Response Cache — Adoption Gap
`APIResponseCache` (TTL-based, `NSLock`-threadsafe) exists with the right constants but is **only used by**:
- `UserObservanceProfileService.swift` (writes `cacheProfile`)
- `UserProfileView.swift` (writes `cacheProfileData()`)

It is **not wired into**:
- `UserService.fetchCurrentUser()` — fetches `users/{uid}` on every cold start
- `FirebasePostService` post-author enrichment — already has its own in-memory dict cache
- `ChurchDataService` or `ChurchDetailExperience` — church profiles are read-heavy

### 1.7 Firebase Storage — Image Sizing
`ImageCache.swift` implements client-side resize (NSCache + NSImage resize queue, 75MB cap, 150 images). No Firebase Storage Resize Extension (`thumb_` prefixed variants) detected in Storage paths. Profile image URLs and post image URLs are served at their upload resolution. The client-side resize is a reasonable mitigation for feed cells but originals are transferred over the wire.

### 1.8 App Launch Network Waterfall
`AMENAPPApp.swift` launches with the following parallel critical tasks (via `withTaskGroup`):
1. `fetchCurrentUserForWelcome()` — uses `.cache` source first ✅
2. `FirebasePostService.preloadCacheSync()` → `startListening(category: .openTable)` 
3. `startFollowServiceListeners()` — `loadCurrentUserFollowing` + `loadCurrentUserFollowers` in parallel
4. `setupFCMForExistingUser()` — gated by `fcmSetupDone` flag ✅
5. `MessageSettingsService.loadSettings()` → `startListening()`
6. `BlessLaterService.startListening()`

All of (1)-(6) are gated on `Auth.auth().currentUser != nil` ✅  
A `getIDToken()` force-refresh happens before the group to ensure Firestore rules pass ✅  
Low-priority `warmUpServices()` task deferred to `.utility` priority ✅

**Observation:** `BereanContextMemoryService.startListening()` is not called at launch — it starts lazily when the Berean screen opens. This is correct. `JobService.setupListeners()` is similarly comment-documented as lazy. Both are correct non-eager patterns.

### 1.9 Berean SSE / Streaming
The true SSE path (`bereanChatProxyStream.ts`) exists on the backend:
- Cancellation: `req.on("close")` fires AbortController — propagates to Anthropic SDK ✅
- No backpressure concern: Firebase Callable Function buffers full response; SSE events are emitted sequentially ✅

The iOS client (`ClaudeAPIService.swift`) uses the **non-streaming** proxy exclusively, simulating word-by-word emission at 15ms intervals. The `bereanChatProxyStream` endpoint is deployed but unused from iOS. This is intentional based on Firebase Callable Function SSE limitations.

### 1.10 Pinecone / Algolia Call Patterns
- Algolia sync runs server-side via Cloud Functions (`algoliaSync.js`) triggered on Firestore writes
- No direct Algolia SDK calls from iOS — all search queries go through Firestore prefix queries or the `bereanGenericProxy` CF
- Pinecone calls are proxied through `semanticEmbeddings.js` (server-only) — no direct Pinecone calls from iOS
- No duplicate query patterns found in hot paths

---

## 2. Implemented (Changes Made)

### Fix A — `BereanContextMemoryService.swift` — Missing limit on memories listener
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanContextMemoryService.swift`  
**Line ~94**  
Added `.limit(to: 100)` to the `memoriesRef` snapshot listener. Without this, the listener would download every `bereanMemory` entry ever created for the user on every change event. 100 entries covers ~2 years of heavy Berean usage; a server-side CF can prune oldest entries when the count exceeds 200.

### Fix B — `SmartGatheringDetectionService.swift` — Double-attach listener leak
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/SpatialSocial/SmartGatheringDetectionService.swift`  
**Line ~91**  
Added `spacesListener?.remove()` before re-assigning `spacesListener` in `startListeningForActiveSpaces()`. Previously, every call to this method (triggered by `SpatialSocialViewModel.refresh()`) would create a new listener without detaching the previous one, accumulating uncleaned listeners over time.

### Fix C — `AppLifecycleManager.swift` — PrayerChainService not in sign-out cleanup
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AppLifecycleManager.swift`  
**Lines ~126–130** (after JobService.stopListening)  
Added `PrayerChainService.shared.stopListening()` to `performFullSignOutCleanup()`. The PrayerChain snapshot listener was surviving sign-out, leaving a cross-user data contamination path.

### Fix D — `firestore.indexes.json` — 13 missing composite indexes
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/firestore.indexes.json`  
Added composite indexes for:
- `heyfeed_requests`: `isActive ASC + resonanceScore DESC`
- `heyfeed_resonance`: `userId ASC + createdAt DESC`
- `pastoral_care_signals`: `isAcknowledged ASC + urgencyScore DESC`
- `ephemeral_spaces`: `memberUIDs CONTAINS + isActive ASC`
- `jobApplications` (×2): applicant and employer queries
- `savedJobs`: `userId ASC + savedAt DESC`
- `jobListings` (×2): employer and featured queries
- `jobAlerts`: `userId ASC + createdAt DESC`
- `prayerChains`: `status ASC + createdAt DESC`
- `bereanMemory` (COLLECTION_GROUP): `isUserVisible ASC + lastReferencedAt DESC`
- `accountabilityThreads`: `members CONTAINS + createdAt DESC`

**Deploy command:** `firebase deploy --only firestore:indexes`

### Fix E — Creator subcollection queries — Missing limits
**Files:**
- `Creator/Services/CreatorAssetService.swift` — added `.limit(to: 200)` to `fetchAssets`
- `Creator/Services/CreatorSceneService.swift` — added `.limit(to: 100)` to `fetchScenes`
- `Creator/Services/CreatorBrandKitService.swift` — added `.limit(to: 50)` to `fetchBrandKits`

These are user-scoped subcollections so growth is bounded per user, but no limit meant that a user with a large creative history would download all records on every editor open.

---

## 3. Deferred (Not Implemented — with Effort Estimates)

### D1 — `bereanChatProxy` + `whisperProxy`: Add `minInstances: 1` [S — backend only]
**Reason deferred:** Requires redeployment of Cloud Functions; no iOS code changes needed.  
**Effort:** S (30 min, edit `bereanChatProxy.ts` and `whisperProxy` config, redeploy)  
**Impact:** Eliminates 1–3s cold start on first Berean chat per session. High user-visible impact.  
**How:** In `bereanChatProxy.ts`, change `onCall({...})` options to include `minInstances: 1`. Same for `whisperProxy` in `openAIFunctions.js`.

### D2 — `APIResponseCache` wiring to UserService and ChurchDataService [M — 2–3 files]
**Reason deferred:** Requires auditing cache invalidation paths (profile updates, church profile edits) to avoid serving stale data. Risk of showing stale profile images after the user updates their photo.  
**Effort:** M (2–3 hours across `UserService.swift`, `ChurchDataService.swift`, `ChurchDetailExperience.swift`)  
**Impact:** Eliminates repeat `getDocument()` calls for the same user/church within a session. Medium impact (Firestore local disk cache already provides most of this for reconnects).

### D3 — Firebase Storage Resize Extension for profile and post images [L — infra + iOS]
**Reason deferred:** Requires enabling the Resize Images Firebase Extension, creating `_200x200` thumbnail variants, and updating iOS image loading to prefer the thumbnail URL.  
**Effort:** L (4–6 hours: extension config, storage rules update, iOS `ImageLoader` update)  
**Impact:** Reduces initial bytes-over-wire for feed cell avatar loads by ~85% (200×200 vs original 2048×2048 upload). High bandwidth impact on cellular.

### D4 — `ClaudeAPIService.stream()` — migrate to true SSE backend [L — iOS + backend]
**Reason deferred:** Firebase Callable Functions don't natively support SSE; the true stream endpoint (`bereanChatProxyStream.ts`) uses HTTP streaming which requires a direct `URLSession` or `EventSource` approach — not the Functions SDK.  
**Effort:** L (6–8 hours: implement custom `AsyncBytes`-based SSE reader in iOS, update all 25 callsites of `bereanChatProxy` to route through stream endpoint where applicable)  
**Impact:** Eliminates the artificial 15ms/word delay; text appears as it streams from Claude. No cold-start improvement (same CF). Major UX improvement for long responses.

### D5 — Post schema denormalization: `authorProfileImageURL` on every post document [S — backend only]
**Reason deferred:** The Cloud Function that writes posts already populates `authorProfileImageURL`. The enrichment path in `FirebasePostService` handles older posts without the field. The migration utility `migrateAllPostsWithProfileImages()` exists but has not been run against prod.  
**Effort:** S (1 hour: run migration, verify index, disable enrichment path after 30 days)  
**Impact:** Eliminates the parallel `getDocument(users/{authorId})` enrichment entirely once all older posts are migrated.

### D6 — `HeyFeedService.myResonances` listener: limit 200 → paginate [M]
**Reason deferred:** 200 resonances is generous and likely sufficient for active users. A proper paginated approach would require server-side aggregation.  
**Effort:** M  
**Impact:** Low (200 documents is small; Firestore cache makes re-reads cheap).

### D7 — `ChurchChemistryService` `memberHashedPhones` fetch: limit 1000 [M]
**Reason deferred:** Large church congregations could have > 1000 members. Requires server-side hashing or pagination with continuation tokens.  
**Effort:** M (3–4 hours: server-side CF for contact matching, remove client-side bulk fetch)  
**Impact:** Medium — security and bandwidth (sending 1000 hashed phones to client for local comparison is wasteful).

### D8 — Navigation-intent prefetch for ProfileView [M]
**Reason deferred:** `FeedPrefetchService` exists and implements position-based prefetch for feed posts. Profile data prefetching (anticipate tap on a user card) would require attaching to the hover/press state in SwiftUI — complex, low iOS support.  
**Effort:** M  
**Impact:** Medium — 200–400ms perceived latency reduction on profile open.

### D9 — `migrateAllPostsWithProfileImages()` cleanup after prod migration [S]
**Reason deferred:** Migration has not been run in prod. Once run, this function can be deleted.  
**Effort:** S  
**Impact:** Remove dead code only.

### D10 — `CreatorAssetService` composite index [S — backend only]
**Reason deferred:** `projectID ASC + createdAt ASC` composite index missing. Firestore will auto-create it after the first query in prod but adding it explicitly is cleaner.  
**Effort:** S (add 2 entries to `firestore.indexes.json`, deploy)

---

## 4. Risk Notes

### Listener Cleanup Strategy
The app follows a consistent `stopListening()` → `AppLifecycleManager.performFullSignOutCleanup()` pattern. The 233 `addSnapshotListener` calls are spread across ~120 files but the sign-out cleanup path is thorough. The 3 issues fixed (BereanContextMemory limit, SmartGathering double-attach, PrayerChain sign-out) were the only confirmed leaks.

### @MainActor Compliance
All listener callback assignments use `[weak self]` and route mutations through `Task { @MainActor in ... }` where the service is not already `@MainActor`-isolated. No new concurrency patterns were introduced in this audit — all fixes are additive (limit clause, nil check before assign, one function call registration).

### firestore.indexes.json Deployment
The 13 new indexes are additive (no deletions). Deploying them requires `firebase deploy --only firestore:indexes`. Index build time in production is typically 2–30 minutes depending on collection size. During the build window, affected queries may fall back to full collection scans — this is a degraded but not failing state. Deploy during low-traffic hours.

### Migration Safety (Fix D5)
`migrateAllPostsWithProfileImages()` is a one-time admin utility. It reads ALL posts (`getDocuments()` without limit) and writes back. Running it on prod requires rate-limiting or batching — do not run as-is against a large prod database. Wrap in a Cloud Function with Firestore batch writes (500 docs/batch) before executing.

### APIResponseCache Thread Safety
`APIResponseCache` uses `NSLock` for thread safety. It is not `@MainActor`-isolated, making it safe to call from background tasks. However, it stores `Any` types. Callers must cast carefully — type mismatches return `nil` silently (the `as?` cast in `get<T>` is correct behavior). Do not store value types that do not conform to `AnyObject` by reference (arrays/dicts stored as `Any` are boxed and will be a copy).
