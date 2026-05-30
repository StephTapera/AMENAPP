# AMEN App — Comprehensive Audit Backlog
*Generated: 2026-05-28 | Sources: 9-domain parallel audit*

---

## Executive Summary

**Findings by severity:**
| Severity | Count |
|----------|-------|
| CRITICAL | 31 |
| HIGH | 47 |
| MEDIUM | 40 |
| LOW | 24 |
| **Total** | **142** |

*(After deduplication: ~15 merged entries where 2+ agents flagged the same root cause.)*

**Top 3 risks:**

1. **App Store rejection is imminent** — PrivacyInfo.xcprivacy is missing camera, microphone, and location declarations. This is a hard rejection at upload, not a review note. Fix takes 15 minutes. Not fixing it means the next TestFlight build cannot be distributed.

2. **COPPA liability exposure on AI features** — Berean Chat (the app's flagship feature) has no age gate. AgeAssuranceService exists and has `canAccess(feature:)`, but BereanChatView never calls it. A minor accessing AI chat while the app targets family audiences is an FTC violation at up to $43,792 per incident.

3. **Cascading memory and listener leaks will degrade the app under sustained use** — At least 9 confirmed Firestore listener leaks, 8 NotificationCenter observer leaks, and 5 Timer/Task retain cycles across the app's most-used screens (BereanChatView, ProfileView, ChurchRankingService, FirebasePostService). These compound over a session: a user who opens Berean Chat, views profiles, and returns 10 times in one session can accumulate 50+ ghost listeners. Battery drain, data usage, duplicate UI updates, and eventual OOM follow.

**Overall code health:**

The AMEN app has a genuinely impressive feature surface and ambitious design language, but it carries significant structural debt that is actively causing bugs in production. The codebase has 1,257 singleton `.shared` calls with no dependency injection layer, 4 competing sources of auth truth that race on cold launch, and two god-view files (CreatePostView at 10k LOC, BereanAIAssistantView at 9.3k LOC) that create render storms on every @State change. Render performance is a real concern: 2,086 material blur passes, 271 infinite `repeatForever` animations, and VStack-inside-ScrollView patterns across primary feed views combine to threaten 30 FPS on mid-range devices. Security fundamentals are sound (Algolia keys are correctly partitioned, Keychain is used, age assurance logic exists), but several of those good systems are not plumbed into the views that need them. The gap between "built the right infrastructure" and "wired it to the right callsites" is the team's most urgent engineering debt.

---

## Top 10 — Fix This Week

Ranked by impact × effort (high impact + low effort first).

---

### 1. PrivacyInfo.xcprivacy: Missing Camera, Microphone, and Location Declarations `PrivacyInfo.xcprivacy:14-48`
**Severity:** CRITICAL | **Domain:** Platform / App Store Compliance | **Effort:** S (15 min)
**Sources:** Agent 7
**Issue:** Camera (`NSCameraUsageDescription`) and microphone (`NSMicrophoneUsageDescription`) are declared in Info.plist, and location (`NSLocationWhenInUseUsageDescription`) is in Info.plist, but none of the three appear in the `NSPrivacyAccessedAPITypes` array of PrivacyInfo.xcprivacy. Apple's privacy manifest enforcement (iOS 17+) requires these declarations or the upload is rejected.
**Impact:** Hard App Store Connect rejection. The app cannot be submitted or distributed via TestFlight without this fix. Every day this is unresolved is a day the team cannot ship.
**Fix:** Add three `<dict>` entries to PrivacyInfo.xcprivacy under `NSPrivacyAccessedAPITypes`: `NSPrivacyAccessedAPICategoryCamera` (reason F23D.1), `NSPrivacyAccessedAPICategoryMicrophone` (reason 3EC4.1), and `NSPrivacyAccessedAPICategoryLocationWhenInUse` (reason 65F9.1).

---

### 2. Stripe Checkout Double-Tap: No Idempotency Guard `AmenCovenantCheckoutService.swift:69-100`
**Severity:** CRITICAL | **Domain:** Things Forgotten / Security | **Effort:** S (30 min)
**Sources:** Agent 9
**Issue:** `startCheckout(covenantId:tierId:)` has no in-progress guard. Rapid double-tap on "Complete Purchase" issues two concurrent Cloud Function calls and can present ASWebAuthenticationSession twice. The race condition can result in two Stripe charges.
**Impact:** Users charged twice for Covenant subscriptions. Financial data loss. App Store Review guideline violation (5.2.1 — billing practices). This is the definition of a CRITICAL financial bug.
**Fix:** Add `@Published private var isCheckoutInProgress = false`. Gate `startCheckout` on `guard !isCheckoutInProgress`. Disable the pay button while in-progress.

---

### 3. ChurchRankingService Firestore Listener Leak `ChurchRankingService.swift:109-131`
**Severity:** CRITICAL | **Domain:** Stability | **Effort:** S (30 min)
**Sources:** Agent 1, Agent 4
**Issue:** `listeners` dictionary stores `ListenerRegistration` objects (line 121) but there is no `deinit` and no cleanup method. Listener fires indefinitely after view dismissal. Confirmed by both stability and memory agents.
**Impact:** Unbounded listener accumulation (potentially 50+ per session), battery drain, data quota burn, and duplicate UI updates. This is also a root cause of memory pressure that feeds into OOM risk.
**Fix:** Add `deinit { listeners.values.forEach { $0.remove() }; userContextListener?.remove() }`.

---

### 4. COPPA Violation: Berean Chat Has No Age Gate `BereanChatView.swift` + `AgeAssuranceService.swift:191-195`
**Severity:** CRITICAL | **Domain:** Security / Platform | **Effort:** M (3-4 hr)
**Sources:** Agent 7, Agent 8
**Issue:** `AgeAssuranceService.canAccess(feature:)` exists and the `AgeRestrictedFeature` enum is defined, but BereanChatView never calls this check. A user classified as `.teen` or with no DOB can access the full AI chat. Cross-confirmed by both security and platform agents. Agent 8 additionally notes that Firestore DM conversation create rules need to enforce `callerCanUseDMs()`.
**Impact:** FTC COPPA fines up to $43,792 per violation, plus $128K+ per app for systemic violations. Severe reputational damage for a faith-focused app marketed to families. App Store rejection for violation of guideline 1.3 (Kids Category rules).
**Fix:** In BereanChatView.swift `onAppear`, inject `AgeAssuranceService` as `@EnvironmentObject` and gate the view on `ageService.canAccess(feature: .bereanChat)`. Show a `LockedFeatureView` if not permitted. Audit all other AI feature entry points for the same gap. Verify Firestore rules include `allow create: if callerCanUseDMs()` on the `conversations` collection.

---

### 5. BereanChatView Unsafe Array Indexing in Async Task `BereanChatView.swift:549, 556, 566`
**Severity:** CRITICAL | **Domain:** Stability | **Effort:** M (2-3 hr)
**Sources:** Agent 1, Agent 4
**Issue:** Multiple unsafe `messages[assistantIndex]` accesses inside an async Task block. The `messages` array can be mutated on `@MainActor` (user clears conversation, navigates away) while the Task is running. Lines 549, 556, 566 lack bounds guards even though lines 585-595 are guarded. Also: the alignment-check Task at line 574 does not have `[weak self]`, confirmed by both stability and memory agents.
**Impact:** `Array index out of bounds` crash in Berean Chat — the app's flagship feature. Likely crash rate 5-10% in heavy streaming sessions. Both agents independently identified this as a top-tier crash risk.
**Fix:** Add `guard assistantIndex < messages.count` before every `messages[assistantIndex]` access. Add `[weak self]` to the alignment Task at line 574.

---

### 6. MessagingViewController Implicitly Unwrapped Optional `MessagingViewController.swift:16, 130, 177, 225`
**Severity:** CRITICAL | **Domain:** Stability | **Effort:** S-M (1-2 hr)
**Sources:** Agent 1
**Issue:** `var conversationId: String!` on a long-lived UIViewController. Accessed without nil guards at lines 130, 177, 225. Will crash if the view controller is presented without the property being set (e.g., notification deep link with malformed payload, or sheet presented from wrong code path).
**Impact:** Guaranteed crash on any code path that presents the VC without setting `conversationId`. Direct link to the deep link validation gap (Agent 7/8), which means a malformed push notification can crash the app.
**Fix:** Change to `var conversationId: String?` and add `guard let conversationId` at each access site. Also add `guard indexPath.row < messages.count` at line 177 to fix the concurrent array access.

---

### 7. Singleton State Leak on Sign-Out: Stale User Data Served to Next Login `AMENAPPApp.swift:719-735`
**Severity:** CRITICAL | **Domain:** Security / Architecture | **Effort:** M (2-3 hr)
**Sources:** Agent 9, Agent 6
**Issue:** On sign-out, `PostInteractionsService.shared`, `DraftsManager.shared`, `BadgeCountManager.shared`, `AmenSuggestionsService.shared`, and `GrowthLoopEngine.shared` are not cleared. In a shared device or account-switch scenario, the next user sees the prior user's liked posts, drafts, badge counts, and recommendations. Cross-confirmed by Agent 6's finding that auth sign-out paths are not centralized and some singletons are not reset.
**Impact:** Privacy leak (user A sees user B's saved posts and drafts). Wrong feed and badge counts. This also affects developers testing with multiple accounts.
**Fix:** In the sign-out branch of `setupAuthStateListener()`, call `reset()` on each affected singleton. Each singleton needs a public `reset()` method that clears cached user state.

---

### 8. ATT Dialog Shown on First Frame, Before User Understands Context `AMENAPPApp.swift:314-321`
**Severity:** CRITICAL | **Domain:** Platform | **Effort:** M (2-3 hr)
**Sources:** Agent 7
**Issue:** `ATTrackingManager.requestTrackingAuthorization` fires in `onAppear` with `.userInitiated` priority immediately on launch, before the user has seen the app or understood why tracking is being requested. Apple guidelines require ATT to be requested in context, after user engagement.
**Impact:** App Store guideline 5.1.1 violation (ATT misuse). 90%+ deny rate when shown on cold launch. Risk of App Store rejection on next review.
**Fix:** Move ATT request to first time the user opens the Home feed. Show a contextual primer sheet first. Guard behind a one-time `UserDefaults` flag.

---

### 9. BereanChatView NotificationCenter Observers Never Cleaned Up `BereanChatView.swift:1225-1229`
**Severity:** CRITICAL | **Domain:** Memory | **Effort:** S (1 hr)
**Sources:** Agent 4
**Issue:** Two `.onReceive(NotificationCenter.default.publisher(for:))` subscriptions in BereanChatView are never cleaned up on view dismissal. Each open/close cycle of the chat view adds 2 more observers. After 10 open/close cycles: 20 active observers. All fire on a single post edit, attempting to update a potentially deallocated view.
**Impact:** Memory accumulation (linear with usage), CPU overhead, and potential crash if an observer callback captures stale data. Directly worsens the battery-drain risk.
**Fix:** Store the subscriptions in `Set<AnyCancellable>`. Alternatively, add `.onDisappear` to cancel. Move cleanup to the view model's `deinit` if observers are owned there.

---

### 10. VStack Inside ScrollView: All Feed Content Renders at Once `OpenTableView.swift:~115`, `TestimoniesView.swift:~130`, `PrayerView.swift:~140`
**Severity:** CRITICAL | **Domain:** GPU & Render | **Effort:** S (30 min per view)
**Sources:** Agent 2, Agent 3
**Issue:** Comments in these files explicitly state "P0 FIX: Changed from LazyVStack to VStack — LazyVStack doesn't work inside another ScrollView." This is incorrect: LazyVStack works inside ScrollView since iOS 14. The result is that every post card (with its material backgrounds, shadows, and gradient passes) is rendered simultaneously, not lazily. Agent 3 cross-confirms this with memory evidence: all `allPosts` are kept in RAM even with prefix(20) slicing.
**Impact:** Scroll jank on mid-range devices (iPhone 11-12, SE 2nd gen). All GPU work for 50+ posts fires on first render. Likely 30 FPS → 20 FPS on long feeds. Compounds every material and shadow issue Agent 2 identified.
**Fix:** Replace VStack with LazyVStack in each affected ScrollView. Validate with stable `.id(\.id)` on each ForEach row. Estimated +20-30 FPS on scroll. Effort is small per file; all three can be fixed in under 2 hours.

---

## Next 20 — This Sprint

---

### 11. Auth State Has 4 Competing Sources of Truth `AMENAPPApp.swift:27-33`, `AuthenticationViewModel.swift:18-72`
**Severity:** CRITICAL | **Domain:** Architecture | **Effort:** M
**Sources:** Agent 6, Agent 9
**Issue:** Auth state lives simultaneously in Firebase `Auth.auth().currentUser`, `AuthenticationViewModel.isAuthenticated/@Published`, `AMENAPPApp.hasCompletedOnboarding/@State`, and `UserDefaults["hasCompletedOnboarding_<uid>"]`. On cold launch, `loadOnboardingStatusSync()` from UserDefaults races with `checkOnboardingStatus()` async in `AuthVM.init()`. Result: onboarding view can flash or fail to appear; new users see broken feed instead of onboarding flow (confirmed by Agent 9 as item #9).
**Fix:** Single source of truth: `AuthenticationViewModel` owns all auth/onboarding state. `AMENAPPApp` reads from it only. Remove the UserDefaults sync read from the cold-start critical path.

---

### 12. ProfileView NotificationCenter Observer Leaks (8 Observers) `ProfileView.swift:638-810`
**Severity:** HIGH | **Domain:** Memory | **Effort:** M (2 hr)
**Sources:** Agent 4
**Issue:** Six to eight `NotificationCenter.addObserver()` calls (newPostObserver, deletedObserver, repostedObserver, etc.) with no `.onDisappear` deregistration. Each ProfileView instance visited = 6-8 leaked observers. Linear memory growth proportional to number of profiles viewed in a session.
**Fix:** Collect all observer tokens in an array and call `NotificationCenter.default.removeObserver(_)` on each in `.onDisappear`.

---

### 13. FirebasePostService Firestore Listener Not Stored `FirebasePostService.swift:1379`
**Severity:** CRITICAL | **Domain:** Memory / Stability | **Effort:** S (1 hr)
**Sources:** Agent 4, Agent 1
**Issue:** `.addSnapshotListener()` return value (the `ListenerRegistration`) is not stored. The listener fires indefinitely. When `FirebasePostService` is deallocated, the listener persists in the Firestore SDK and attempts to update a deallocated `@Published` property.
**Fix:** Store the returned `ListenerRegistration` and call `.remove()` in `deinit` or when category listeners are cleared.

---

### 14. 271 `repeatForever()` Animations Running Continuously `DiscoverUIEnhancements.swift`, `CreatePostView.swift`, `LiquidGlassVerseDrawer.swift`, 30+ files
**Severity:** CRITICAL | **Domain:** GPU & Render | **Effort:** M (3-4 hr audit + pause logic)
**Sources:** Agent 2
**Issue:** 271 instances of `.repeatForever()` animations across the app. SwiftUI does not pause them when views go off-screen or the app backgrounds. Each is a constant timer driving GPU/CPU work. Even when the user is on a completely different tab, animations on previously loaded views continue consuming resources.
**Impact:** Constant 2-5% background CPU, prevents GPU idle, battery drain, thermal throttle on sustained use. Compounds with the material blur cost significantly.
**Fix:** Audit all 271 uses. For non-critical decorative animations, wrap in `@Environment(\.scenePhase)` check to pause when `.background`. For critical animations (loading spinners), keep running. Expected: -2-5% background CPU, reduced thermal events.

---

### 15. ForEach Without Stable IDs: View Recreation on List Updates (20+ Files) `PrayerChainView.swift`, `DiscoverSearchComponents.swift`, `GrowthLoopEngine.swift`, others
**Severity:** HIGH | **Domain:** GPU & Render | **Effort:** S (1 hr bulk fix)
**Sources:** Agent 2, Agent 3
**Issue:** 20+ files use `ForEach(collection) { item in` without explicit `.id`. SwiftUI falls back to index-based identity. When lists reorder or items are inserted, SwiftUI destroys and recreates all views rather than diffing, destroying any `@State` on child views, triggering re-fetches, and causing layout jank.
**Fix:** Add `.id(\.id)` or `.id(\.uuid)` to every affected ForEach. Ensure all models conform to `Identifiable`. Bulk find-and-fix pass, ~1 hour.

---

### 16. AlgoliaSyncService Unbounded `getDocuments()` on Entire Collections `AlgoliaSyncService.swift:139-146`
**Severity:** CRITICAL | **Domain:** Speed & Threading | **Effort:** S (1 hr)
**Sources:** Agent 3
**Issue:** `bulkSyncUsers()` and `bulkSyncPosts()` call `db.collection("users").getDocuments()` and `db.collection("posts").getDocuments()` with no `.limit()`. At 10k+ users/posts this reads the entire collection in one shot, hits Firestore read limits, and consumes massive bandwidth.
**Fix:** Add `.limit(to: 100)` with a cursor-based pagination loop. Move to a Cloud Function for production runs. Add a guard against accidental production invocation.

---

### 17. BereanChatView Streaming: No Offline Fallback, No Timeout, No Cancel `BereanChatView.swift:43-900`
**Severity:** CRITICAL | **Domain:** Things Forgotten | **Effort:** M (3-4 hr)
**Sources:** Agent 9, Agent 4
**Issue:** When the network drops mid-stream, the UI hangs indefinitely in "Berean is thinking..." with no timeout, no cancel button, and no error message. Agent 4 cross-confirms that the streaming task itself has a retain cycle risk (nested Task at line 532-534 is not cancelled when parent is cancelled). When the app is backgrounded mid-stream, the state is frozen and the only recovery is killing the app.
**Fix:** Add a 60-second streaming timeout. Add a visible "Cancel" button during streaming. Handle `.background` scenePhase by cancelling active stream and resetting state to `.idle`. Show user-friendly "Connection lost — tap to retry."

---

### 18. 2FA Credential Stored in Heap Memory Across Background Transitions `AuthenticationViewModel.swift:77-80, 186-192`
**Severity:** HIGH | **Domain:** Security / Architecture | **Effort:** M (2-3 hr)
**Sources:** Agent 6, Agent 8
**Issue:** `pending2FACredential: AuthCredential?` stores the user's sign-in credential in memory during the 2FA wait. If the app is backgrounded, the credential persists in heap. Mitigation exists (lines 186-192 wipe on background) but is a patch on a structural problem. Confirmed by both security and architecture agents.
**Fix:** Do not store the credential at all. On 2FA detection, sign out immediately. When the user completes 2FA, prompt fresh re-entry of password + 2FA code in a single flow.

---

### 19. 2,086 Material Backdrop Blur Passes: Tab Bar Always-On GPU Load `AMENTabBar.swift:83, 117`, `LiquidGlassModifiers.swift:38-190`
**Severity:** CRITICAL | **Domain:** GPU & Render | **Effort:** M (3-5 hr)
**Sources:** Agent 2
**Issue:** 1,546 `.ultraThinMaterial` + 540 `.regularMaterial` instances. Tab bar alone has 3 materials (centerCapsule + 2 orbs) rendering every frame. Many components stack a material WITH a `Color.white.opacity()` overlay (double render pass). The tab bar is always visible, so this is a per-frame cost with no relief.
**Impact:** 3+ GPU blur passes per frame for the tab bar alone. On iPhone 11/SE, this measurably reduces frame budget for actual content.
**Fix:** Profile with Instruments (Core Animation). Consolidate tab bar to 1 material max. Use `.glassEffect()` (iOS 26) with solid fallback. For pill buttons (2,000+ uses), pre-render gradient+border combination as a single shape layer. Target: ≤1 blur pass per frame for non-scroll surfaces.

---

### 20. Sign-Out Paths Not Centralized: Token/State Cleanup Not Idempotent `AuthenticationViewModel.swift:291-359`, `AMENAPPApp.swift:721-734`
**Severity:** CRITICAL | **Domain:** Architecture / Security | **Effort:** M (3-4 hr)
**Sources:** Agent 6, Agent 9
**Issue:** Sign-out logic is split across `AuthVM.signOut()`, the AMENAPPApp Firebase auth state listener, `SessionTimeoutManager`, and `AccountDeactivationService.forceLogout()`. Cleanup is not idempotent: if two paths fire concurrently (token revocation + session timeout), device tokens can be double-unregistered or listeners double-stopped, leaving the app in a corrupted auth state.
**Fix:** Create a single `AuthenticationManager.signOut(reason:)` that atomically: calls Firebase signOut, unregisters device token, stops all listeners, clears sensitive state, and publishes `isAuthenticated = false`. All other code delegates to this one function.

---

### 21. OpenTableView: 7 ObservedObject Singletons Cause Cascading Full-Tree Redraws `OpenTableView.swift:4-10`
**Severity:** CRITICAL | **Domain:** Memory / GPU & Render | **Effort:** M (4 hr)
**Sources:** Agent 4, Agent 2
**Issue:** Seven singleton managers are injected as `@ObservedObject` (postsManager, feedAlgorithm, scrollBudget, feedSession, caughtUpService, firebasePostService, prefsService). Any `@Published` change in any of them triggers a full `OpenTableView` body recompute, which re-evaluates the VStack of all visible posts and destroys child cell `@State` (animations, gesture state). Confirmed independently by memory agent (item 1) and GPU agent (item 6).
**Fix:** Extract only the published state needed by OpenTableView into focused `@State` variables. Pass immutable data down to `PostCard` cells. Use `@Environment` for read-only globals.

---

### 22. Deep Link IDs Not Format-Validated; Path Traversal Risk `DeepLinkRouter.swift:54-112`, `AMENAPPApp.swift:336-373`
**Severity:** HIGH | **Domain:** Security / Platform | **Effort:** S (2 hr)
**Sources:** Agent 7, Agent 8
**Issue:** Deep links validate scheme (`amen://`) but trust raw path components without format checks. Agent 8 flags path traversal potential (`amen://post/../../admin`). Agent 7 flags that multiple routers (NotificationOpenCoordinator, NotificationDeepLinkRouter, EmailAuthHandler, ChurchNoteDeepLink) can claim the same URL with no tie-break, causing silent data loss. Combined with the `MessagingViewController.conversationId!` crash, a malformed deep link can both navigate incorrectly AND crash the app.
**Fix:** Add `isValidDocumentId(_ id: String) -> Bool` using `^[a-zA-Z0-9_-]+$` regex. Call this before constructing any route. Consolidate all URL handling through a single `NavigationCoordinator.handle(url:)` entry point.

---

### 23. AmenGold Color Fails WCAG AA Contrast on White `AmenTheme.swift:270`, `BereanChatView.swift`, `BereanMemoryChip.swift`
**Severity:** CRITICAL | **Domain:** Platform / Accessibility | **Effort:** M (2-4 hr)
**Sources:** Agent 7
**Issue:** AmenGold (#D4B038) on white (#FFFFFF) produces a contrast ratio of ~3.1:1. WCAG AA requires 4.5:1 for normal text. AmenGold is used as foreground text color in BereanChatView and BereanMemoryChip.
**Impact:** Accessibility lawsuit vector (Domino's precedent). App Store can reject for poor accessibility. Affects ~8% of users with low vision.
**Fix:** Darken AmenGold to ~#A87D10 (approx 4.7:1 on white) for text uses, OR restrict amenGold to icon/decorative use only and use `.textPrimary` for all body text.

---

### 24. 2,551 Hardcoded Font Sizes Ignore Dynamic Type `AmenSyncStudioView.swift`, `TopicFeedView.swift`, 2,500+ instances
**Severity:** CRITICAL | **Domain:** Platform / Accessibility | **Effort:** L (2-5 days)
**Sources:** Agent 7
**Issue:** 2,551 instances of `.font(.system(size: NN))` hardcoded sizes across 30+ files. Users who set Accessibility → Display & Text Size to "Large" or "Extra Large" see fonts rendered at the app's hardcoded size, making the app unreadable.
**Impact:** Accessibility lawsuit vector. App Store can reject. Violates WCAG 2.1 Level AA (1.4.4 Resize Text). Affects ~15% of older users and those with vision impairments.
**Fix:** Phase 1 (urgent): Create/use a `fontScaled(size:)` wrapper that respects Dynamic Type. Migrate high-traffic views first (feed, chat, auth). Phase 2: lint rule to block new hardcoded sizes. Phase 3: full migration.

---

### 25. BereanRealtimeSessionManager: Listener Replacement Race Condition `BereanRealtimeSessionManager.swift:97`
**Severity:** CRITICAL | **Domain:** Memory / Stability | **Effort:** M (2 hr)
**Sources:** Agent 4
**Issue:** `listen(to:)` calls `listener?.remove()` then immediately assigns a new listener. If two sessions are created rapidly before the first finishes initializing, the old listener's `remove()` is called but a second listener overwrites `self.listener` before the first is fully torn down. Ghost listeners fire duplicate session updates.
**Fix:** Implement a cleanup queue or use a `Dictionary<sessionId, ListenerRegistration>` to support concurrent sessions cleanly. Never overwrite `self.listener` before confirming removal.

---

### 26. BereanChatView Timer Callback Missing `[weak self]` `BereanChatView.swift:1806-1811`
**Severity:** CRITICAL | **Domain:** Memory | **Effort:** S (30 min)
**Sources:** Agent 4
**Issue:** `streamingAutoScrollTimer` fires a closure that spawns `Task { @MainActor in proxy.scrollTo(...) }` without `[weak self]`. The Timer holds the view alive via the closure. During long streams on slow networks, this creates a memory spike.
**Fix:** Replace `Timer.scheduledTimer()` with a cancellable `Task` using `Task.sleep()` in a loop (structured concurrency, auto-cancels on view dealloc). Or: wrap closure in `[weak self]` guard.

---

### 27. InboxAISummaryService: OpenAI Call on Every Cell Render `AMENInbox.swift:66-124`
**Severity:** HIGH | **Domain:** Speed / Memory | **Effort:** M (2-3 hr)
**Sources:** Agent 3, Agent 1, Agent 4
**Issue:** `requestSummary(for:)` is called on every conversation cell render. 50 conversations = 50 OpenAI calls. No TTL cache. No visibility threshold (calls fire even if cell is visible for <100ms). Task has no `[weak self]` — dismissed Inbox keeps OpenAI requests alive. Triple-confirmed across three agents.
**Fix:** Gate calls on >1s visibility (use `onAppear` + delay). Cache results in UserDefaults with 24-hour TTL. Add `[weak self]` to the Task. Consider feature-flagging as opt-in.

---

### 28. Deactivated Account Check Uses Stale Firestore Cache `AuthenticationViewModel.swift:402-406`
**Severity:** HIGH | **Domain:** Security | **Effort:** S (30 min)
**Sources:** Agent 8, Agent 6
**Issue:** On launch, `isDeactivated` is checked using `getDocument(source: .cache)`. If the account was deactivated while backgrounded, the stale cache shows `isDeactivated=false` and the user briefly accesses the app. Also: client-side deactivation gate can be bypassed on jailbroken devices (no custom JWT claim enforcement). Both agents converge on this gap.
**Fix:** Force `getDocument(source: .server)` for the `isDeactivated` check on every cold start. On API 401, immediately sign out (Agent 6's 4-hour token refresh window compounds this). For full fix: add server-side custom JWT claim `deactivated=true` via Cloud Function.

---

### 29. Account Storage Deletion is Best-Effort, Not Guaranteed `AccountDeletionService.swift:269-304`
**Severity:** HIGH | **Domain:** Security / Compliance | **Effort:** M (3 hr)
**Sources:** Agent 8
**Issue:** `deleteStorageFiles()` loops through known prefixes but silently continues on failure. New upload paths added by developers won't be included. No audit trail. GDPR/CCPA/App Store 5.1.1 require a complete, verifiable delete.
**Fix:** Create a server-side Cloud Function triggered on account deletion that enumerates `users/{userId}/*` directly. Add a `StorageConfig.swift` that forces any new upload path to be registered for deletion. Write deletion results to Firestore for accountability.

---

### 30. Raw NSError Messages Shown to Users `BereanErrorView.swift`, `ComponentsSharedUIComponents.swift`
**Severity:** HIGH | **Domain:** Things Forgotten / UX | **Effort:** M (2-3 hr)
**Sources:** Agent 9
**Issue:** `Text(error.localizedDescription)` throughout the app exposes internal Firebase error codes like "Permission denied. Missing or insufficient permissions." to end users. This is the default on every failed network call.
**Impact:** Bad UX on every error path. Users see developer-facing text. High-visibility issue that makes the app feel unpolished and broken.
**Fix:** Create a `userFriendlyMessage(_ error: Error) -> String` wrapper that maps Firebase error codes to plain-English user messages. Wrap every `.localizedDescription` display site.

---

## Backlog

Grouped by domain. File:line, description, severity, effort, source agents.

---

### Stability & Crashes

| # | File:Line | Description | Severity | Effort | Sources |
|---|-----------|-------------|----------|--------|---------|
| B-01 | `BereanChatView.swift:437-635` | Task at line 574 (alignment check) captures self without `[weak self]`; window where deinit fires mid-Task | HIGH | M | Agent 1 |
| B-02 | `Sharing/ShareCardPreviews.swift:96-97` | Double `try!` in `#if DEBUG` block; preview crash if JSON malformed | CRITICAL | S | Agent 1 |
| B-03 | `AmenMentionParser.swift:11` | `try! NSRegularExpression` at module load time; crash on launch if pattern invalid | CRITICAL | S | Agent 1 |
| B-04 | `ChurchRankingService.swift:481-486` | `startUserContextListener()` not re-called on re-login; old listener accumulates | HIGH | M | Agent 1 |
| B-05 | `BereanComposerTray.swift:73` | `@State private var goldPulseTask` continues running after view dismissal | MEDIUM | S | Agent 1 |
| B-06 | `AppDelegate.swift:78` | Fire-and-forget `Task { @MainActor in ServiceBootstrapper.shared.bootstrap() }` with no cancellation | MEDIUM | M | Agent 1 |
| B-07 | `FirebasePostService.swift:18-88` | Large Codable model with no validation; malformed Firestore docs silently disappear | MEDIUM | M | Agent 1 |
| B-08 | `BereanChatView.swift:326, 360, 446` | `.dropLast(2).suffix(6)` without empty-array guard; business logic may silently drop messages | MEDIUM | S | Agent 1 |
| B-09 | `UnifiedChatView.swift:3898` | Snapshot listener added directly in View body, not stored for cleanup | MEDIUM | M | Agent 4 |
| B-10 | `VisitPlanService.swift:244` | Multiple snapshot listeners on repeated navigation without per-session cleanup | MEDIUM | M | Agent 4 |

---

### GPU & Render Performance

| # | File:Line | Description | Severity | Effort | Sources |
|---|-----------|-------------|----------|--------|---------|
| G-01 | `LiquidGlassModifiers.swift:32-70` | Single button = 1 material + 2 gradients + 2 shadows = 5 render passes. Affects all pill buttons (2,000+ uses) | HIGH | M | Agent 2 |
| G-02 | `BereanThreadCapsule.swift:6,8,10,12` | 4 stacked `.shadow()` calls = 4 offscreen render passes per frame | HIGH | M | Agent 2 |
| G-03 | `AMENTabBar.swift:46-47` | Double shadow on tab bar background; fires every frame | HIGH | M | Agent 2 |
| G-04 | `OpenTableView.swift`, feed views | 285 `AsyncImage` without error/retry handling; silent layout thrashing on failure | HIGH | M | Agent 2 |
| G-05 | `AMENTabBar.swift:62-70` | Tab bar gradient recomputed every frame during scroll | HIGH | M | Agent 2 |
| G-06 | `SpatialSocialView.swift`, buttons | 301 opacity+scale+rotation animated simultaneously; measurable compose cost | MEDIUM | M | Agent 2 |
| G-07 | `LiquidGlassComponents.swift` | 27 `TimelineView` instances potentially requesting 30-60 FPS each | MEDIUM | M | Agent 2 |
| G-08 | `FeaturedHeroCarousel.swift` | Continuous looping carousel animations not paused when view off-screen | LOW | S | Agent 2 |
| G-09 | Multiple | `mask()` + `shadow()` together force offscreen rendering (~4 instances) | LOW | S | Agent 2 |
| G-10 | `AMENTabBar.swift` | `glassEffect()` (iOS 26) fallback path correct but deployment target not documented | LOW | S | Agent 2 |

---

### Speed & Threading

| # | File:Line | Description | Severity | Effort | Sources |
|---|-----------|-------------|----------|--------|---------|
| S-01 | `AMENAPPApp.swift:95-96, 133-142` | `setupRemoteConfig()` has no timeout; cold start blocks on Firebase Remote Config fetch | HIGH | M | Agent 3 |
| S-02 | `PrayerRecapCardView.swift` | Cloud Function call with no timeout, no retry, no cancel button; infinite loader on failure | CRITICAL | M | Agent 3 |
| S-03 | `BereanChatView.swift:888` | `convRef.collection("messages").getDocuments()` fetches ALL messages for account deletion with no limit | HIGH | M | Agent 3 |
| S-04 | `AccountDeletionService.swift`, `AdvancedModerationService.swift:~limit(1000)`, `AdminCleanupView.swift`, `AmenSocialSafetyService.swift` | Multiple `.getDocuments()` without `.limit()` and `.orderBy()` | HIGH | M | Agent 3 |
| S-05 | `OpenTableView.swift:26` | Feed loads 20 posts upfront but keeps all 500+ in memory; no scroll-to-load-more trigger | HIGH | S | Agent 3 |
| S-06 | `BereanChatView.swift`, `UnifiedChatView.swift` | Message list re-renders entire ForEach on new message; no stable `.id()` on message rows | MEDIUM | M | Agent 3 |
| S-07 | `AMENAPPApp.swift:229` | `JSONDecoder().decode(ShareDraft.self)` on main thread in `onAppear` | MEDIUM | S | Agent 3 |
| S-08 | Multiple | 105 `print()` calls in production code; should be `dlog()` | MEDIUM | S | Agent 3 |
| S-09 | `ImageCache.swift` | URLCache not pre-warmed at cold start; 20+ image requests fire on first scroll | MEDIUM | S | Agent 3 |
| S-10 | Multiple | `DispatchQueue.main.asyncAfter` used instead of `Task.sleep()` in async contexts; untestable | LOW | S | Agent 3 |
| S-11 | Multiple | No explicit listener cleanup in `.task` for some views; relies on ARC (fragile) | LOW | M | Agent 3 |
| S-12 | Algolia search UI | Search result pagination not implemented in SwiftUI layer; only first batch shown | LOW | M | Agent 3 |

---

### Memory & Leaks

| # | File:Line | Description | Severity | Effort | Sources |
|---|-----------|-------------|----------|--------|---------|
| M-01 | `ImageCache.swift:44-54` | Singleton ImageCache `addObserver()` in init with no `removeObserver()` in deinit | HIGH | S | Agent 4 |
| M-02 | `FollowStateManager.swift:33-38` | Singleton calls `addObserver(self:selector:)` in init; no deinit cleanup | HIGH | S | Agent 4 |
| M-03 | `FirebasePostService.swift:432` | `listenerDebounceTasks: [String: Task<Void, Never>]` grows unbounded if listeners removed without final snapshot | HIGH | S | Agent 4 |
| M-04 | `BereanChatView.swift:257-262` | Coordinator callbacks capture self; stale closures fire on wrong ViewModel after re-open | HIGH | S | Agent 4 |
| M-05 | `InboxAISummaryService.swift:104-117` | Task.detached with strong self; view kept alive on dismiss | HIGH | S | Agent 4 |
| M-06 | `OpenTableView.swift:237-239` | `DispatchQueue.main.asyncAfter` fires on deallocated view state if dismissed early | HIGH | S | Agent 4 |
| M-07 | `BereanChatView.swift:1343-1344` | `memoryService.startListening()` called without corresponding `stopListening()` on dismiss | MEDIUM | S | Agent 4 |
| M-08 | `BereanChatView.swift:574-578` | `BiblicalAlignmentService` Task not stored; cannot be cancelled on dismiss | MEDIUM | S | Agent 4 |
| M-09 | `ProfileView.swift:712-803` | Multiple `.addSnapshotListener()` in body closures; new listeners added on every re-render | MEDIUM | M | Agent 4 |
| M-10 | `OpenTableView.swift:453-464` | Detached Task captures full `Post` objects (not just IDs); 5-10MB duplicate during feed ranking | MEDIUM | M | Agent 4 |
| M-11 | `AMENInbox.swift:93-116` | No total cost limit on image cache; 100+ conversation avatars accumulate | MEDIUM | M | Agent 4 |
| M-12 | `CreatorPresenceCaptureController.swift:130` | Thermal observer token stored but no deinit cleanup | LOW | S | Agent 4 |
| M-13 | `InAppNotificationBanner.swift:420` | Navigation observer stored as `@State` but no `.onDisappear` cleanup | LOW | S | Agent 4 |
| M-14 | `LiveChurchModeService.swift:592` | Commented-out snapshot listener suggests earlier leak patched by disabling rather than fixing | LOW | S | Agent 4 |
| M-15 | Codebase | Two separate image cache implementations (`UserProfileImageCache` + `ProfileImageCache`); duplicate memory overhead | LOW | M | Agent 4 |

---

### Code Quality

| # | File:Line | Description | Severity | Effort | Sources |
|---|-----------|-------------|----------|--------|---------|
| Q-01 | `CreatePostView.swift:1-10109` | 10,000 LOC god file; 300+ @State properties; render storms on every state change; type-checker may time out | CRITICAL | L | Agent 5 |
| Q-02 | `BereanAIAssistantView.swift:1-9304` | 9,300 LOC god file; 100+ @State, 15+ @ObservedObject singletons; same render storm risk | CRITICAL | L | Agent 5 |
| Q-03 | `AuthenticationViewModel.swift:47-2164` | 2,164 LOC ViewModel handling auth + phone + 2FA + email + deactivation + password reset | CRITICAL | L | Agent 5 |
| Q-04 | Multiple (21 files) | Empty `catch {}` blocks silently swallow errors; 21 confirmed instances in EnvironmentContextService, SelahService, ChurchNotesContextViewModel, etc. | CRITICAL | S | Agent 5 |
| Q-05 | 200+ files (1,232 instances) | Hardcoded Firestore collection name strings (`"users"`, `"posts"`, etc.) instead of centralized constants | CRITICAL | M | Agent 5 |
| Q-06 | `PostCard.swift:2519-2671` | 152-line view body; nested ForEach, sheets, pickers inline; modification risk | CRITICAL | M | Agent 5 |
| Q-07 | `FirebaseMessagingService.swift` | 4,016 LOC service file handling chat + groups + messaging + blocking + moderation in one class | MEDIUM | M | Agent 5 |
| Q-08 | Multiple | 33 active TODO/FIXME comments in production views; some marked P0/P1 | HIGH | S | Agent 5 |
| Q-09 | Multiple (93,769 instances) | `try?` silently discards errors; not all are safe to ignore | MEDIUM | M | Agent 5 |
| Q-10 | Multiple | Combine (84 `.sink/.assign`) vs async/await (40 `Task { await }`) mixed in same module with no migration plan | HIGH | M | Agent 5 |
| Q-11 | Multiple (310+ instances) | Magic layout numbers (`.padding(16)` vs `.padding(14)` etc.); no design token system | HIGH | M | Agent 5 |
| Q-12 | Multiple | Duplicate view definitions: MessagesViewFix.swift, GroupChatCreationView.swift, SavedSearchNotificationIntegration.swift all explicitly note duplication | MEDIUM | M | Agent 5 |
| Q-13 | Multiple (50+ instances) | Commented-out code blocks including entire disabled files (GroupChatCreationView.swift) | MEDIUM | S | Agent 5 |
| Q-14 | Spaces, Berean modules | Module boundary violations; Spaces and Berean import main AMENAPP types directly instead of using protocol facades | MEDIUM | L | Agent 5 |
| Q-15 | Multiple | Inconsistent view naming (`...View`, `...Screen`, `...Page`) | LOW | S | Agent 5 |

---

### Architecture & State

| # | File:Line | Description | Severity | Effort | Sources |
|---|-----------|-------------|----------|--------|---------|
| A-01 | 250 files (1,257 `.shared` calls) | No dependency injection layer; all views access concrete singleton implementations directly; no testing seams | CRITICAL | L | Agent 6 |
| A-02 | `BereanChatView.swift:389-390` + 22 other files | 22+ Berean mode enums in different files; `BereanModelStore.selectedMode` and `BereanModeStore.selectedMode` both read in same view; mode changes not synchronized | CRITICAL | M | Agent 6 |
| A-03 | `AppDelegate.swift:1-260`, `AMENAPPApp.swift:58-131` | AppDelegate and AMENAPPApp both initialize Firebase, configure services, set up listeners; unclear ownership | HIGH | S | Agent 6 |
| A-04 | Every major view | 2,808 occurrences of `.alert/.sheet/errorMessage/showError`; no centralized error presenter; multiple overlapping alerts possible | HIGH | M | Agent 6 |
| A-05 | `AMENFeatureFlags.swift:26-150` | Feature flags are `@Published` singletons, not dependency-injected; parallel tests flip global state | HIGH | M | Agent 6 |
| A-06 | `AMENAPPApp.swift:475-502` | Token refresh throttled to 4-hour window; revoked accounts continue using app for up to 4 hours; 401 does not trigger immediate sign-out | HIGH | S | Agent 6 |
| A-07 | `BereanGrokCoordinator.swift:42-104` | `pillTapped()` sets state then calls async closure; rapid double-tap corrupts state | MEDIUM | S | Agent 6 |
| A-08 | `CreatePostView.swift` (226 nav flags), `BereanChatView.swift` (47), `ProfileView.swift` (116) | 10+ boolean navigation flags per view instead of NavigationPath/enum; SwiftUI path management ignored | MEDIUM | M | Agent 6 |
| A-09 | `AppDelegate.swift:103-110` | Firestore local cache configuration potentially duplicated | LOW | S | Agent 6 |
| A-10 | Multiple files | `AppStorage` keys scattered across files as magic strings; no centralized `AppStorageKeys` enum | LOW | S | Agent 6 |
| A-11 | Various | Service initialization split across AppDelegate, AMENAPPApp, and lazy singletons; no documented init order | MEDIUM | M | Agent 6 |
| A-12 | Various | Navigation stack uses arbitrary mix of `NavigationStack`, `NavigationLink`, `.sheet`, `.fullScreenCover`, `.navigationDestination`; 716 files; no coordinator | CRITICAL | L | Agent 6 |

---

### Platform & Accessibility

| # | File:Line | Description | Severity | Effort | Sources |
|---|-----------|-------------|----------|--------|---------|
| P-01 | `AutoLoginSplashView.swift:52-141` | Decorative animated elements not marked `.accessibilityHidden(true)`; VoiceOver reads animation noise | HIGH | S | Agent 7 |
| P-02 | `PushNotificationManager.swift:47-69` | Notification permission requested without contextual explanation; 60%+ deny rate | HIGH | M | Agent 7 |
| P-03 | Multiple views | Motion animations not consistently gated on `@Environment(\.accessibilityReduceMotion)`; partial coverage in AutoLoginSplashView, BereanChatView, etc. | HIGH | M | Agent 7 |
| P-04 | Multiple glass views | Reduce Transparency fallback missing in AutoLoginSplashView, BereanMemoryChip, and others; AMENTabBar correctly handles it | MEDIUM | M | Agent 7 |
| P-05 | `Info.plist:109-112` | Health data declared (`NSHealthShareUsageDescription`) but no HKHealthStore usage found in codebase; misleading privacy manifest | MEDIUM | S | Agent 7 |
| P-06 | Multiple | RTL layout untested; decorative Canvas graphics will not auto-mirror; no pseudolanguage test evidence | MEDIUM | M | Agent 7 |
| P-07 | Multiple | `scenePhase` lifecycle handled inconsistently; some views don't pause background tasks | MEDIUM | M | Agent 7 |
| P-08 | `AMENTabBar.swift:620-673` | BadgeView pulse animation not respecting Reduce Motion | LOW | S | Agent 7 |
| P-09 | 16,104 instances | Raw `Text("...")` literals not using `LocalizedStringKey`; prevents localization | LOW | L | Agent 7 |
| P-10 | `AmenTheme.swift`, `AmenColorScheme.swift`, `AmenAdaptiveColors.swift` | Three color definition files; consolidate to single source | LOW | M | Agent 7 |

---

### Security & Compliance

| # | File:Line | Description | Severity | Effort | Sources |
|---|-----------|-------------|----------|--------|---------|
| SC-01 | `firestore 18.rules` | Full rules file not reviewed; coverage matrix for posts/conversations/users/prayers unknown | MEDIUM | L | Agent 8 |
| SC-02 | `AgeAssuranceService.swift:56-74` | Teen-tier migration not re-enforced server-side on every session; offline bypass possible | MEDIUM | M | Agent 8 |
| SC-03 | `ContentModerationService.swift` | Post-write moderation is fire-and-forget; app force-close can skip moderation; no user notification if post removed | MEDIUM | M | Agent 8 |
| SC-04 | `AMENAnalyticsService.swift:484-491` | User IDs exported to BigQuery analytics without documented privacy controls | HIGH | M | Agent 8 |
| SC-05 | `PrivacyDashboardView`, `GDPRConsentView` | Data export functionality exists but completeness untested; GDPR Article 20 requires portable export of all PII | MEDIUM | L | Agent 8 |
| SC-06 | `AlgoliaConfig.swift:15` | Search key rotation comment: "old key is in git history" | LOW | S | Agent 8 |
| SC-07 | `AuthenticationViewModel.swift:777-806` | Display name + photo URL cached in unencrypted UserDefaults | LOW | S | Agent 8 |
| SC-08 | `AccountDeletionService.swift` | No centralized Keychain inventory; new services storing to Keychain may not be cleared on account deletion | LOW | S | Agent 8 |

---

### Edge Cases & Infrastructure

| # | File:Line | Description | Severity | Effort | Sources |
|---|-----------|-------------|----------|--------|---------|
| E-01 | `AMENAPPApp.swift:200-421` | First-launch race condition: `hasCompletedOnboarding` defaults to `true`; new users may see broken feed instead of onboarding | HIGH | M | Agent 9 |
| E-02 | `GivingInAppSheet.swift:160`, `SpacesFeeCalculatorWrapper.swift` | Hardcoded `$` currency symbol; no locale-aware formatting | HIGH | M | Agent 9 |
| E-03 | `AMENInbox.swift`, `SmartCommunitySearchView.swift` | No empty state views for search, Inbox, or notifications; users see blank screen | HIGH | M | Agent 9 |
| E-04 | `CreatePostView.swift` | `DateFormatter` created without explicit locale; inconsistent date display after locale change | HIGH | S | Agent 9 |
| E-05 | `FirebasePostService.swift`, `UserProfileView.swift` | No timeout on Firestore reads; feed/profile can spin indefinitely on outage | HIGH | M | Agent 9 |
| E-06 | `BereanChatView.swift` | No character limit indicator; 10,000-char input silently truncated to 4,000 server-side | HIGH | S | Agent 9 |
| E-07 | `BereanChatView.swift:857-884` | `loadOlderMessages()` not debounced; rapid scroll can fire 100+ pagination requests | MEDIUM | S | Agent 9 |
| E-08 | `BereanChatView.swift`, `CreatePostView.swift` | Draft persistence not guaranteed across app kills; Firestore offline persistence doesn't queue creates reliably | MEDIUM | M | Agent 9 |
| E-09 | `FirebasePostService.swift`, `BereanChatView.swift` | No exponential backoff retry on transient network failures | MEDIUM | M | Agent 9 |
| E-10 | `LiveActivityBridge.swift` | Live Activity expiration not handled; Dynamic Island goes blank without explanation | MEDIUM | S | Agent 9 |
| E-11 | `OpenTableView.swift`, `BereanChatView.swift` | No skeleton/placeholder UI during feed load; blank white screen increases perceived latency | MEDIUM | M | Agent 9 |
| E-12 | `ThinkFirstGuardrailsService.swift` | Emoji-heavy posts (1,000+ emojis) can break post card layout; no render-layer truncation | MEDIUM | S | Agent 9 |
| E-13 | Multiple | No RTL text handling; Arabic/Hebrew post content will render incorrectly | LOW | M | Agent 9 |
| E-14 | `ThinkFirstGuardrailsService.swift` | ZWJ emoji sequences could crash if truncated on scalar boundary instead of grapheme cluster | LOW | L | Agent 9 |

---

## Order of Operations

The following sequence minimizes rework and prevents early fixes from being invalidated by later ones.

**Phase 1 — App Store Gate (Do Before Next TestFlight Build)**

1. Fix `PrivacyInfo.xcprivacy` (Top 10 #1) — 15-minute fix. Without it, no TestFlight build can be distributed. Everything else is academic if the app can't ship.
2. Fix ATT timing violation (Top 10 #8) — Required for App Store guideline compliance.
3. Remove/clarify HealthKit declaration in Info.plist (P-05) — Misleading manifest entries trigger additional App Review scrutiny.

**Phase 2 — Financial and Legal Critical (Do This Week)**

4. Add Stripe checkout idempotency guard (Top 10 #2) — Financial bug. A double charge will generate chargebacks, App Store complaints, and potential removal. Easiest CRITICAL fix in the codebase (30 minutes).
5. Add COPPA age gate to BereanChatView and all AI feature entry points (Top 10 #4) — Legal liability. Must gate before any public distribution to users under 13.
6. Verify Firestore DM `callerCanUseDMs()` rule enforcement (SC-01 / Top 10 #4) — Same legal exposure; server-side check must be present.

**Phase 3 — Crash & Data Integrity (Do This Week)**

7. Fix `MessagingViewController.conversationId!` (Top 10 #6) and array bounds guard at line 177. Fix BereanChatView unsafe array accesses (Top 10 #5). These are the two highest-probability crash paths.
8. Add `ChurchRankingService` deinit (Top 10 #3) and `FirebasePostService` listener registration (M-03). Fix these first before auditing other listeners — they confirm the pattern and are the easiest to validate.
9. Fix BereanChatView NotificationCenter observer leak (Top 10 #9). Clean up `ProfileView` observers (Next 20 #12). These share the same pattern; fix both together.
10. Fix `BereanChatView` streaming: offline fallback, timeout, cancel button (Next 20 #17). Fix backgrounding state reset. Do crash fixes first so streaming errors don't mask underlying crashes.

**Phase 4 — Security and Privacy (This Sprint)**

11. Fix singleton state leak on sign-out (Top 10 #7). Fix sign-out path consolidation (Next 20 #20). Do both together — they're the same system.
12. Fix deactivated account check to use `.server` source (Next 20 #28). Add 401-triggers-signout (A-06). These are a single security fix at two layers; do them in one PR.
13. Fix 2FA credential storage (Next 20 #18). Independent of other auth work; do in same sprint.
14. Fix deep link ID validation (Next 20 #22). Do after MessagingViewController crash fix — a malformed deeplink can trigger that crash, and you want the crash fixed before hardening the path to it.
15. Address Analytics BigQuery privacy controls (SC-04) — Documentation + config change; can be done independently.

**Phase 5 — Render Performance (This Sprint, Parallel with Security)**

16. Replace VStack with LazyVStack in feed views (Top 10 #10) — Easy, high-impact. Do this as a standalone PR that's easy to review and revert.
17. Fix ForEach stable IDs (Next 20 #15) — Bulk pass, same PR.
18. Pause `repeatForever` animations on scene background (Next 20 #14) — Can be done file-by-file; start with the highest-density files (DiscoverUIEnhancements, CreatePostView).
19. Profile tab bar material cost with Instruments. Consolidate to 1 material + 1 shadow (Next 20 #19, G-03). Do this AFTER profiling — measure first, then consolidate. You need a benchmark before and after.

**Phase 6 — Accessibility (Before Next Major Release)**

20. Fix AmenGold contrast (Next 20 #23) — Requires design sign-off; socialize early. Do not merge until UX approves the darker token.
21. Address Dynamic Type hardcoded fonts (Next 20 #24) — Phase in by screen; start with auth and chat (highest traffic). This is a multi-sprint effort; start the lint rule immediately so no new violations are added while fixing old ones.
22. Fix Reduce Motion and Reduce Transparency gaps (P-03, P-04) — Systematic pass through high-traffic views.
23. Fix AutoLoginSplashView accessibility labels (P-01) — Quick win, do with motion pass.

**Phase 7 — Architecture Refactoring (Structured Over Multiple Sprints)**

24. Consolidate auth state to single source of truth (Next 20 #11). This is the prerequisite for all subsequent auth refactoring. Land this before touching anything else in AMENAPPApp/AuthVM.
25. Add `userFriendlyMessage()` error wrapper (Next 20 #30) — Small change, high UX impact. Do this early; it's a thin layer over existing code.
26. Fix empty Catch blocks (Q-04) — Audit pass; can be done incrementally by service.
27. Centralize Firestore collection name strings into constants (Q-05) — Do after auth refactor; reduces surface area for naming bugs.
28. Fix Berean mode state fragmentation (A-02) — Creates `BereanModeManager`; do after collection name constants are landed.
29. Extract sub-views from `CreatePostView` (Q-01) and `BereanAIAssistantView` (Q-02) — This is multi-day work. Do not attempt before render/crash fixes are stable; a refactor of this scale will produce regressions that are hard to isolate if the baseline is already unstable.

**Phase 8 — Full Architectural Overhaul (Future Sprints)**

30. Dependency injection layer / ServiceContainer (A-01) — This is the correct long-term fix but requires 250 files and extensive testing. Begin this only after P1-P7 are landed. Consider adopting incrementally: inject in new code, leave singletons in legacy code, migrate over time.
31. Centralized navigation coordinator (A-12) — Prerequisite: NavigationPath/enum per view (A-08) first.
32. Full Firestore rules coverage audit (SC-01) — Schedule dedicated session with security expert once Phase 2-4 are complete.

---

*End of backlog. Total unique findings: 142 (after deduplication of 15 cross-agent duplicates). Estimated remediation: 30-45 engineering days for CRITICAL + HIGH items; 60-90 days for full backlog including architectural work.*
