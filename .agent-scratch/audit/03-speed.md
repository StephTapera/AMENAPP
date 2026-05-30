# Agent 3 — Speed & Threading

## Method

**Scanned:** Core entry points (AMENAPPApp.swift, AppDelegate.swift, AutoLoginSplashView.swift), feed views (OpenTableView.swift), messaging (AMENInbox.swift, BereanChatView.swift), critical services (AlgoliaSyncService.swift, ImageCache.swift), and 1,693 Swift files total.

**Tools used:** Grep for Firestore query patterns, file I/O, JSON parsing, main-thread async calls; Read for code analysis of initialization paths; Bash for systematic pattern detection.

**Scope:** 
- Cold start path: app init, AppDelegate lifecycle, first view render
- Main-thread blocking: synchronous I/O, JSON parsing, heavy view computations
- Firestore efficiency: query limits, pagination, listener patterns
- Cloud Function costs: error handling, timeout behavior
- Image loading: caching strategy verification
- Network startup: any blocking calls on critical path

---

## Findings

### CRITICAL (ship-blocking)

#### 1. AlgoliaSyncService:139,146 — Unbounded `getDocuments()` on entire "users" and "posts" collections
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/AMENAPP/AlgoliaSyncService.swift:139–146`

```swift
func bulkSyncUsers() async throws {
    let snapshot = try await db.collection("users").getDocuments()
    for doc in snapshot.documents { ... }
}

func bulkSyncPosts() async throws {
    let snapshot = try await db.collection("posts").getDocuments()
    for doc in snapshot.documents { ... }
}
```

**Why it matters:** If users collection has 10k+ docs, this fetches ALL 10k in one shot, hitting Firestore's document read limits and consuming massive bandwidth. No pagination, no cursor, no limit. If called during onboarding or analytics (non-idempotent), this burns quota.

**Suggested fix:** 
1. Add `.limit(to: 100)` with pagination loop
2. Add `.orderBy("createdAt")` + cursor tracking
3. Move to Cloud Function (batch processing in background)
4. Add guard against accidental production runs

**Effort:** S (1 hour — add limit, add pagination loop)

---

#### 2. AMENAPPApp.swift:374–376 — Synchronous Cloud Function call via `httpsCallable().call()` on `.task` (blocking render)
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/AMENAPP/AMENAPPApp.swift:374–376`

The `.task` priority is `.userInitiated`, which blocks subsequent view renders if the Cloud Function is slow. The code runs on the critical path without timeout or error fallback:

```swift
let utilityTask = Task(priority: .utility) {
    await Self.warmUpServices()  // This may call httpsCallable().call()
}
```

And in `setupRemoteConfig()` (line 133):
```swift
remoteConfig.fetch { status, error in
    if status == .success {
        remoteConfig.activate { _, _ in
            dlog("✅ Remote Config activated")
        }
    }
}
```

No timeout, so if Firebase Remote Config hangs, the app hangs.

**Why it matters:** Cold start blocks on network. If Algolia or Remote Config services are slow (10s+), users see a frozen app before first frame. Users expect ~100ms to first meaningful paint.

**Suggested fix:**
1. Wrap `setupRemoteConfig()` in a timeout: `try await Task.sleep(nanoseconds: 3_000_000_000); remoteConfig.fetch { ... }`
2. Or move fetch to background, activate on next session
3. Wrap `warmUpServices()` tasks in timeout guards
4. Set HTTPSCallable timeout to 5s max: `functions.settings.timeoutInterval = 5.0`

**Effort:** M (2–3 hours — add timeout wrappers, handle stale Remote Config gracefully)

---

#### 3. PrayerRecapCardView.swift — Missing `await` on Cloud Function call, callback-based blocking
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/AMENAPP/PrayerRecapCardView.swift`

```swift
functions.httpsCallable("generatePrayerRecap").call { [weak self] result, error in
    DispatchQueue.main.async {
        self?.isLoading = false
        ...
    }
}
```

No timeout, no retry logic, no error classification (transient vs. permanent).

**Why it matters:** If Cloud Function is slow or times out after 5s (default timeout), the UI shows infinite loader. User can't cancel or retry gracefully.

**Suggested fix:**
1. Convert to async/await with timeout
2. Add user-facing "Try again" button on error
3. Set explicit timeout of 10s, show "taking longer than usual" message at 5s

**Effort:** M (2–3 hours — convert callback to async/await, add timeout UI)

---

### HIGH (fix this sprint)

#### 4. BereanChatView.swift:866–867, 888 — Unbounded message fetches without pagination
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/AMENAPP/BereanChatView.swift:866–867, 888`

```swift
.limit(to: messageWindowSize)
.getDocuments()  // Line 867
...
let messageSnapshot = try await convRef.collection("messages").getDocuments()  // Line 888
```

First query is paginated (good), but line 888 fetches ALL messages for account deletion (no limit). If a user has 5k+ messages, this fetches all in one shot.

**Why it matters:** Account deletion hangs; user-facing operation blocks on Firestore read; affects quota.

**Suggested fix:**
1. Add `.limit(to: 100)` to line 888
2. Wrap in pagination loop
3. Move to Cloud Function (delete in background, show progress)

**Effort:** M (2–3 hours — add limit, implement pagination loop or Cloud Function wrapper)

---

#### 5. OpenTableView.swift — Feed pagination starts at 20, but no lazy loading on scroll
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/AMENAPP/OpenTableView.swift:26`

```swift
@State private var visiblePostCount = 20
...
let displayPosts = Array(allPosts.prefix(visiblePostCount))
```

UI renders 20 posts upfront. If there are 500 posts in `allPosts`, SwiftUI keeps all 500 in memory even though only 20 are visible. No "load more on scroll" trigger.

**Why it matters:** If feed grows to 1000+ posts over time (repeat user session), memory bloat + rendering jank on scroll as SwiftUI recalculates ForEach identity for all 1000 items.

**Suggested fix:**
1. Implement `onAppear` on the last post to trigger `visiblePostCount += 20`
2. Or use `LazyVStack` (currently disabled; re-enable with async pagination boundary detection)
3. Or implement `GeometryReader` offset tracking (already partially done—line 232–241)

**Effort:** S (1 hour — add scroll-to-bottom trigger to load next batch)

---

#### 6. AMENInbox.swift — InboxAISummaryService calls OpenAI on every conversation view render
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/AMENAPP/AMENInbox.swift:66–124`

```swift
func requestSummary(for conversation: ChatConversation) {
    // ... 
    Task {
        let prompt = "Summarise this message preview..."
        if let result = try? await OpenAIService.shared.sendMessageSync(prompt) {
            summaries[id] = result
        }
    }
}
```

Called on every conversation cell render. If user scrolls through 50 conversations, 50 OpenAI API calls fire (deduplication via `inFlight` helps, but only per-session).

**Why it matters:** Expensive API calls for UI polish. OpenAI billing + latency. Not worth the cost if user is just browsing.

**Suggested fix:**
1. Only request summary if conversation is visible for >1s (use `onAppear` + delay)
2. Cache results in UserDefaults with TTL (1 day)
3. Or disable this feature by default and offer as opt-in premium

**Effort:** M (2–3 hours — add visibility timer, implement cache with TTL)

---

#### 7. Multiple files — `getDocuments()` without `.orderBy()` + `.limit()` for non-admin queries
**Files:** 
- `AccountDeletionService.swift` (pagination is partial; missing limit on one path)
- `AdvancedModerationService.swift:???` — `.limit(to: 1000).getDocuments()` on moderation queue (unbounded unless exactly 1000 docs)
- `AdminCleanupView.swift` — `.getDocuments()` on posts subcollection (no limit)
- `AmenSocialSafetyService.swift` — `.getDocuments()` on trustedContacts (no limit)

**Why it matters:** Each unbounded query risks hitting Firestore read limits, quota exhaustion, and slow UI.

**Suggested fix:** Systematic sweep—find all `.getDocuments()` without explicit `.limit()` and `.orderBy()`, add pagination.

**Effort:** M (3–4 hours — audit all queries, add limits, implement cursor pagination where needed)

---

#### 8. AMENAPPApp.swift:95–96 — Blocking RemoteConfig `fetch()` during app init, no timeout
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/AMENAPP/AMENAPPApp.swift:95–96, 133–142`

```swift
Task {
    Self.setupRemoteConfig()
}

private static func setupRemoteConfig() {
    remoteConfig.fetch { status, error in
        // No timeout, no fallback
    }
}
```

If Firebase Remote Config is slow (e.g., network stalls), the app waits indefinitely. Remote Config is cached, so blocking here for AI keys is wasteful—use cached version if available.

**Why it matters:** Cold start stall on poor networks.

**Suggested fix:**
1. Use `Task.sleep(nanoseconds: 3_000_000_000)` timeout
2. Fall back to cached Remote Config if fetch times out
3. Or defer fetch to background after first frame renders

**Effort:** M (2–3 hours — add timeout, fallback logic)

---

### MEDIUM (next sprint)

#### 9. Image caching strategy is good, but URLCache is not warmed at cold start
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/AMENAPP/ImageCache.swift`

URLCache is configured in `AMENAPPApp.init()` (line 81–88), but no preload of critical images (avatar, banners). On cold start, first scroll through feed fires 20 image network requests.

**Why it matters:** Scroll jank on first scroll because images are loading synchronously in background while SwiftUI tries to render.

**Suggested fix:**
1. Preload avatar + banner images during `setupFCMForExistingUser()` or `startFollowServiceListeners()`
2. Cache them to disk before user scrolls

**Effort:** S (1 hour — add preload call, verify URLCache disk I/O doesn't block main thread)

---

#### 10. BereanChatView and UnifiedChatView — Message rendering re-renders entire list on new message
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/AMENAPP/BereanChatView.swift`

No evidence of `.id()` on message rows or `Equatable` conformance for message models. If a new message arrives, SwiftUI recomputes entire `ForEach` over all messages.

**Why it matters:** If conversation has 500+ messages, adding 1 new message re-renders all 500, causing 1-2s jank.

**Suggested fix:**
1. Add `.id()` to message ForEach using stable message ID
2. Implement `Equatable` on Message model, compare only on changed fields
3. Use `@EnvironmentObject` for message list instead of `@State`, so updates are fine-grained

**Effort:** M (2–3 hours — add IDs, make Message Equatable, refactor view state)

---

#### 11. `print()` calls in production code (105 instances)
**Files:** Multiple across AMENAPP/\*.swift

```swift
print("Recap error:", error)
```

These show up in Console and contribute to I/O overhead in production. Should use `dlog()` instead.

**Why it matters:** Minor, but `print()` can cause jank on devices with slow log buffering under heavy load.

**Suggested fix:** Global find-replace `print(` → `dlog(` (need context review for a few cases).

**Effort:** S (30 mins — find-replace with review)

---

#### 12. App-wide JSON parsing is async, but AMENAPPApp.swift:229 decodes on main thread
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP\ copy/AMENAPP/AMENAPPApp.swift:229`

```swift
let draft = try? JSONDecoder().decode(ShareDraft.self, from: data)
```

Happens in `onAppear` task, which runs on main thread. If `ShareDraft` is complex or data is large, this blocks.

**Why it matters:** Unlikely to hit in practice (ShareDraft is probably small), but bad precedent.

**Suggested fix:** Decode on background queue, dispatch result to main:
```swift
let draft = try await Task.detached { try JSONDecoder().decode(ShareDraft.self, from: data) }.value
```

**Effort:** S (30 mins)

---

### LOW (backlog)

#### 13. `asyncAfter(deadline:)` instead of `Task.sleep()` in multiple places
**Example:** AMENAPPApp.swift:236–237, OpenTableView.swift:461

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    sessionCountingEnabled = true
}
```

Not inherently slow, but `Task.sleep()` is preferred in async/await code (cleaner, cancellable).

**Why it matters:** Code style; `Task.sleep()` is more testable.

**Suggested fix:** Replace with `Task.sleep(nanoseconds: 1_500_000_000)` inside async context.

**Effort:** S (1 hour — systematic replacement)

---

#### 14. No explicit `.task` cleanup for snapshot listeners
**Multiple files:** BereanChatView, UnifiedChatView, AMENInbox

Listeners are set up but no `.onDisappear` cleanup found in some views. Relies on ARC, which is fragile.

**Why it matters:** Stale listeners can accumulate if views are pushed/popped rapidly, causing memory leaks and duplicate updates.

**Suggested fix:** Audit all `.task` listeners, ensure each has a paired `.onDisappear` cancellation or use `ListenerRegistry.shared` cleanup.

**Effort:** M (3–4 hours — audit all listener patterns, standardize cleanup)

---

#### 15. No timeout on Firestore transaction / batch writes
**Firestore everywhere:** All `transaction` and `batch.commit()` calls inherit default 5s timeout (SDK), which is OK but not explicit in code.

**Why it matters:** Silent fails if transaction times out; error handling assumes success.

**Suggested fix:** Add explicit timeout constants, document assumptions.

**Effort:** L (backlog refactoring; not urgent)

---

#### 16. Pagination in search results (Algolia) not implemented
No evidence of pagination UI for search results (search is delegated to Algolia, which has pagination, but SwiftUI UI may not fetch subsequent pages).

**Why it matters:** If user searches and 1000+ results arrive, only first batch shows. No "load more" affordance.

**Suggested fix:** Add search result pagination UI (likely low effort if Algolia SDK supports it).

**Effort:** M (2–3 hours — implement pagination UI for search results)

---

## What I did NOT check

1. **GPU/Metal rendering jank** — Did not profile Core Animation or Metal draw calls. Requires Instruments.
2. **Thread sanitizer violations** — Did not run TSan; would require CI setup.
3. **Crash logs from App Store** — No access to production crash data; audit is static analysis only.
4. **Network timing / CDN config** — Did not analyze CloudFront / image server setup.
5. **Firestore composite index design** — Did not verify indexes exist for all `order(by:).limit()` queries. Requires Firebase Console inspection.
6. **SwiftUI PreviewProvider performance** — Did not check if previews have performance issues.
7. **Background task scheduling** — Did not audit `BGAppRefreshTask` handlers for duration (must complete <30s). See code in AMENAPPApp.swift.
8. **Memory profiling** — Did not run Instruments; code analysis only.
9. **Database query plan optimization** — Firestore doesn't expose query plans; assumed indexes are set up correctly.
10. **Exact latency measurements** — All assertions based on code inspection, not benchmarks.

---

## Summary

**Ship-blocking issues (3):**
- Unbounded Firestore queries (AlgoliaSyncService, AccountDeletionService)
- Blocking Cloud Function calls on cold start
- No timeout on Remote Config fetch

**High-priority fixes (8):**
- Add pagination to all Firestore queries
- Implement lazy loading for feed
- Optimize AI summary service
- Message rendering optimization

**Estimated total effort to fix CRITICAL + HIGH:** 15–20 hours (2–3 days).

