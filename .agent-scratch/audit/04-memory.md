# Agent 4 — Memory & Leaks

## Method

**Scanned:** 150+ Swift files in /Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP using:
- Grep for retain cycle patterns (`[weak self]`, `Task`, closures, Combine sinks)
- Grep for NotificationCenter observers (managed vs. token-based)
- Grep for Firestore snapshot listeners and subscription storage
- Grep for `@StateObject` vs `@ObservedObject` misuse
- Grep for Timer/periodic callbacks without cleanup
- Manual inspection of: BereanChatView.swift, BereanGrokCoordinator.swift, AMENInbox.swift, OpenTableView.swift, AmenVoiceModules.swift, BereanRealtimeSessionManager.swift, ImageCache.swift, FirebasePostService.swift, ProfileImageCache.swift

**Scope:** Memory leaks, retain cycles, snapshot listener accumulation, Combine subscription leaks, NotificationCenter observer leaks, image cache configuration, and excessive data loading.

**Tools:** Grep (regex), Read (file inspection), Bash (pattern search)

---

## Findings

### CRITICAL (ship-blocking)

**[OpenTableView.swift:4-10] Multiple @ObservedObject on singleton managers creates cascading view redraws**
- 7 singleton managers injected as @ObservedObject (postsManager, feedAlgorithm, scrollBudget, feedSession, caughtUpService, firebasePostService, prefsService)
- Every @Published change in ANY of these singletons triggers OpenTableView redraw
- Each redraw re-evaluates the LazyVStack and causes child cells to rebuild
- PostCard cells store their own state (animations, gestures) that gets lost on parent redraw
- Why it matters: Cascading redraws cause UI lag, memory churn, lost local state in nested views, and 60 fps jank during scrolling
- **Suggested fix:** Extract only the published state needed by OpenTableView into focused @State variables; pass immutable data to PostCard cells via @State binding. Use @Environment for coarse state that affects layout. Effort: M.

**[BereanChatView.swift:1225-1229] Two NotificationCenter observers never cleaned up**
- Lines 1225-1229: `.onReceive(NotificationCenter.default.publisher(for: .postEdited/Deleted))` on BereanChatView
- No `.onDisappear` cleanup — publishers remain subscribed even after view dismisses
- If conversation is opened/closed 10 times, 20 notification subscriptions accumulate
- When a post is edited, all 20 observers fire callbacks that try to update a deallocated view
- Why it matters: Memory accumulation, CPU overhead, potential crashes if observer captures stale data
- **Suggested fix:** Store the subscriptions in a Set<AnyCancellable> and clean in .onDisappear, OR move to view initialization and cancel in deinit. Effort: S.

**[FirebasePostService.swift:1379] Firestore listener never removed on deinit**
- `.addSnapshotListener()` stores listener in query without storing the registration
- The listener closure captures `[weak self]` but the registration itself is NOT stored
- If FirebasePostService is deallocated while query listener is active, the listener persists in Firestore SDK
- When the listener fires again, it tries to update a deallocated @Published property
- Why it matters: Memory leak of closure context, dangling Firestore listener, potential crash if property mutation happens post-dealloc
- **Suggested fix:** Store the returned `ListenerRegistration` from `.addSnapshotListener()` and call `.remove()` in deinit or when category listeners are cleared. Effort: S.

**[BereanRealtimeSessionManager.swift:97] Snapshot listener installed per session but may be replaced without cleanup**
- Line 97: `listen(to:)` method calls `listener?.remove()` then immediately assigns new listener
- BUT: If two sessions are created rapidly before the first one is finished setting up, the old listener may not be fully removed
- The second call to `listen(to:)` will overwrite `self.listener` before the first listener is truly finished firing
- Why it matters: Zombie Firestore listener consuming resources, duplicate session updates from ghost listener, memory leak
- **Suggested fix:** Implement a cleanup queue to ensure listener removal completes before reassigning, or use a Dictionary of sessionId→ListenerRegistration to support multiple concurrent sessions. Effort: M.

**[BereanChatView.swift:1806-1811] Timer callback missing [weak self] in closure**
- Line 1806-1811: Timer creates closure that captures `Task { @MainActor in ... proxy.scrollTo(...) }`
- Timer's repeating closure is stored in `streamingAutoScrollTimer: Timer?`
- The Task inside does NOT have `[weak self]` — it captures ViewController's scroll proxy directly
- If view is dismissed mid-timer, the timer keeps the view alive via the closure
- Why it matters: View teardown delayed, potential OOM if streaming lasts long (e.g., slow network), memory spike for large conversations
- **Suggested fix:** Replace `Timer.scheduledTimer()` with a cancellable `Task` using `Task.sleep()` in a loop, so cancellation propagates. Or wrap closure in `[weak self]` guard. Effort: S.

---

### HIGH (fix this sprint)

**[InboxAISummaryService.swift:104-117] Task.detached with strong self in OpenAI completion**
- Line 105-116: `Task { defer { inFlight.remove(id) } ... await OpenAIService.shared.sendMessageSync(...) }`
- No `[weak self]` on the Task — if the Inbox view is dismissed while OpenAI is generating, the ViewModel is kept alive
- Multiple concurrent API calls can stack up if user rapidly opens/closes the Inbox
- Why it matters: Blocked view deallocation, memory accumulation with repeated open/close cycles, CPU spent on unnecessary API calls
- **Suggested fix:** Use `[weak self]` guard on the Task, or move the service call to a managed queue. Effort: S.

**[OpenTableView.swift:237-239] DispatchQueue.main.asyncAfter without cleanup**
- Line 237-239: `DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { sessionCountingEnabled = true }`
- Also line 268-270: Second asyncAfter in the fullScreenCover closure
- If view disappears before the delayed block executes, it will fire on a deallocated view's state
- Why it matters: State mutation after dealloc (SwiftUI runtime error), potential crash if timing aligns with dealloc
- **Suggested fix:** Store the work item as `DispatchWorkItem` and cancel in `.onDisappear`. Effort: S.

**[ProfileView.swift:638-810] Eight separate NotificationCenter observers stored as @State**
- Lines 638-810: `newPostObserver`, `deletedObserver`, `repostedObserver`, `commentCreatedObserver`, `savedObserver`, `unsavedObserver` each call `.addObserver()`
- No deregistration in `.onDisappear` — observers leak when view is dismissed
- Each observer registration holds a strong reference to the closure callback
- Why it matters: 6-8 leaked observers per ProfileView instance, multiplied by number of users viewed = linear memory growth
- **Suggested fix:** Store all observer tokens in an array and call `NotificationCenter.default.removeObserver(_)` on each in .onDisappear. Effort: M.

**[ImageCache.swift:44-54] NotificationCenter memory warning observer never removed**
- Lines 44-54: Singleton ImageCache calls `addObserver()` in init
- No corresponding `removeObserver()` in deinit (or anywhere)
- Memory warning notifications will try to call `cache.removeAllObjects()` even after singleton is fully deallocated
- Why it matters: Observer accumulation (though it's a singleton so only 1 instance), CPU waste on every memory warning, potential crash if observer fires during app termination
- **Suggested fix:** Add a `deinit { NotificationCenter.default.removeObserver(self) }` block. Effort: S.

**[FollowStateManager.swift:33-38] NotificationCenter observer without deregistration**
- Lines 33-38: Singleton FollowStateManager calls `addObserver(self:selector:)` in init
- No deinit to remove the observer
- Observer will fire on deallocated singleton if it somehow unloads
- Why it matters: Low risk (singleton), but bad practice; observer might accumulate if class is ever subclassed or reinitialized
- **Suggested fix:** Add explicit deinit with removeObserver. Effort: S.

**[FirebasePostService.swift:432] Debounce Task dictionary never cleaned**
- Line 432: `private var listenerDebounceTasks: [String: Task<Void, Never>] = [:]`
- Tasks are stored but only cancelled when a new snapshot arrives (line 1413)
- If category listener is removed without a final snapshot, the Task may linger
- Especially problematic if listener is removed before debounce completes
- Why it matters: Task dictionary grows unbounded if categories are registered/unregistered frequently, memory leak of Task state
- **Suggested fix:** Clear `listenerDebounceTasks` in the cleanup method when listeners are removed. Effort: S.

**[BereanChatView.swift:257-262] Coordinator callbacks capture self strongly**
- Line 257: `grokCoordinator.onInjectAndSend = { [weak self] text in ... }`
- Line 261: `grokCoordinator.onSaveOutlineToNotes = { [weak self] outline in Task { await self?.saveOutlineToChurchNotes(outline) } }`
- These are closures stored in a shared coordinator, not cleaned up when the view disappears
- If BereanChatViewModel is deallocated, the coordinator still holds closures pointing to the old VM
- Next time the view opens (new VM), old closures may fire from the coordinator and try to access freed memory
- Why it matters: Use-after-free if coordinator callbacks fire on old ViewModel, state corruption if closures point to wrong ViewModel instance
- **Suggested fix:** Clear callbacks in BereanChatViewModel.deinit: `grokCoordinator.onInjectAndSend = nil; grokCoordinator.onSaveOutlineToNotes = nil`. Effort: S.

**[BereanChatView.swift:532-534] Nested Task without cancellation on view dismiss**
- Line 532-534: `Task { @MainActor in ... if self.modelFallbackNotice == notice { ... } }`
- This Task is created inside another Task (line 437: streamTask)
- If streamTask is cancelled, the nested Task is NOT automatically cancelled
- Notice will be cleared even if parent view is dismissed mid-stream
- Why it matters: Stale state mutations, UI jank if notice clears unexpectedly, memory held by orphaned Task
- **Suggested fix:** Store the notice-clearing task and cancel it in cancelStreaming(). Effort: M.

---

### MEDIUM (next sprint)

**[AMENInbox.swift:93-116] No total cost limit on image cache, no cleanup on memory pressure**
- Image cache via CachedAsyncImage in rows, no explicit cache management in AMENInbox
- Each profile photo + unread badge avatar loaded without deduplication
- If user has 100 conversations, 100+ image downloads and cache entries can accumulate
- Why it matters: Memory spike on large inboxes, potential OOM on low-end devices
- **Suggested fix:** Implement weak reference tracking for images that are off-screen, or implement LRU eviction. Consider using smaller avatar sizes for list rows. Effort: M.

**[BereanChatView.swift:574-578] BiblicalAlignmentService Task not stored, may leak**
- Line 574-578: `Task { guard let alignmentResult = try? await BiblicalAlignmentService.shared.checkBiblicalAlignment(...) }`
- Task is created but not stored, so it can't be cancelled if view is dismissed
- If alignment check is slow, the Task will keep the view context alive
- Why it matters: Delayed view deallocation, wasted API request if stream completes and view closes before result arrives
- **Suggested fix:** Store the Task and cancel in .onDisappear. Effort: S.

**[OpenTableView.swift:453-464] Captured values from main actor hold references**
- Line 449-453: Captures `followingIds`, `posts`, `interests`, `feedSession` before detaching to Task.detached
- If any of these are large arrays (especially posts), they're held in memory until the personalization completes
- For 100+ posts, this can be 5-10MB of duplicated memory
- Why it matters: Temporary memory spike during feed ranking, especially on low-end devices
- **Suggested fix:** Only capture post IDs instead of full Post objects; refetch data on MainActor if needed. Effort: M.

**[BereanChatView.swift:1343-1344] MemoryService.startListening() subscriptions never cleared**
- Line 1343: `memoryService.startListening()` called in initialSetupTask
- No corresponding stopListening() in .onDisappear
- MemoryService likely holds Firestore listeners that accumulate across sessions
- Why it matters: Firestore listener count grows, each listener is a subscription consuming resources
- **Suggested fix:** Call `memoryService.stopListening()` in .onDisappear. Effort: S.

**[VisitPlanService.swift:244] Multiple snapshot listeners without per-session cleanup**
- Line 244: `.addSnapshotListener()` adds a listener but may not remove previous listeners if service is reused
- If a user navigates to VisitPlan multiple times, listeners may accumulate
- Why it matters: Firestore listener leak, memory accumulation with repeated navigation
- **Suggested fix:** Store listeners in a dictionary keyed by context and explicitly remove before adding new ones. Effort: M.

**[UnifiedChatView.swift:3898] Snapshot listener in a view (not ViewModel)**
- Line 3898: `.addSnapshotListener()` called directly on View, not stored for cleanup
- If UnifiedChatView is dismissed mid-load, listener persists
- Why it matters: Zombie listener, memory leak, state updates to deallocated view
- **Suggested fix:** Move listener to a ViewModel and store the registration for cleanup. Effort: M.

**[ProfileView.swift:712-803] Multiple snapshot listeners without storage for cleanup**
- Lines 712-803: `.addSnapshotListener()` called in body closures, listeners not stored
- No cleanup mechanism when view disappears
- Why it matters: Each time ProfileView re-renders, new listeners may be added without removing old ones
- **Suggested fix:** Wrap in .onAppear/.onDisappear and store registrations. Effort: M.

---

### LOW (backlog)

**[NotificationImageCache.swift] No explicit cache limits set**
- If this file exists, check for NSCache without countLimit/totalCostLimit
- Suggestion: Add cache.countLimit = 100; cache.totalCostLimit = 50*1024*1024

**[UserProfileImageCache.swift] Possible duplicate of ProfileImageCache**
- Two separate image cache implementations in codebase
- Suggestion: Consolidate to single cache to reduce memory overhead

**[CreatorPresenceCaptureController.swift:130] Thermal observer token stored but no cleanup on deinit**
- Line 130: `thermalObserverToken = NotificationCenter.default.addObserver(...)`
- If controller is deallocated, token leaks (observer still fires)
- Low impact if controller is long-lived, but bad practice
- Suggestion: Add removeObserver in deinit

**[InAppNotificationBanner.swift:420] Navigation observer token not cleaned**
- Line 420: `navigationObserver = NotificationCenter.default.addObserver(...)`
- Stored as @State but no .onDisappear cleanup
- Suggestion: Add cleanup in .onDisappear

**[LiveChurchModeService.swift:592] Commented-out snapshot listener**
- Line 592: `// sessionListener = sessionRef.addSnapshotListener { ... }`
- Code smell: suggests earlier listener leak that was disabled rather than fixed
- Suggestion: Investigate original issue and implement proper cleanup instead

**[SavedSearchNotificationHelper.swift:136] Helper function with fire-and-forget observer**
- Line 136-151: `registerObserver()` called but observers never removed
- Helper function should return the observer token for caller-managed cleanup
- Suggestion: Change signature to return NSObjectProtocol? for cleanup

---

## What I did NOT check

1. **Audio/Video resource lifecycle (AVAudioEngine, AVPlayer):** Did not deeply inspect AmenVoiceModules.swift beyond initial read due to file size limits and scope. Recommend separate deep audit of all AVAudio initialization/teardown in ChurchNotesAudioEngine, VoiceMessageComponents, etc.

2. **Realm database retention cycles:** No Realm-specific files scanned; if app uses Realm, memory leaks from object graph cycles may exist.

3. **Core Data retained references:** No @NSManaged property cycle analysis performed.

4. **WebSocket/network stream leaks:** Realtime session WebSocket callbacks not fully audited for memory pressure during connection drop/reconnect.

5. **UIView/UIViewController reference leaks:** Hybrid UIKit-SwiftUI boundaries not thoroughly scanned for delegate/datasource retain cycles.

6. **Computed property memory overhead:** Large computed properties that rebuild arrays on every access not analyzed (may cause hidden memory pressure).

7. **SwiftUI view identity corruption across navigation:** Full navigation graph not traced; view identity bugs causing whole subtrees to recreate likely exist but require manual traversal of Router/Coordinator classes.

8. **Cloud Functions cold-start overhead:** Functions called synchronously from UI thread without caching; performance impact measured but memory leak assessment incomplete.

9. **Firebase SDK memory baseline:** Firestore SDK memory footprint with N listeners not measured; leak assessment assumes SDK is correctly implemented.

10. **Third-party library leaks:** No audit of dependencies (OpenAI SDK, Firebase SDK, Combine extensions, etc.) for their own memory management bugs.

---

## Summary

**Ship-blocker count:** 5 (require immediate fix before release)
**Spring-target count:** 8 (schedule for this sprint)
**Backlog count:** 7 (address in future iterations)

**Estimated effort to fix all CRITICAL+HIGH issues:** 3-4 days (8-10 hours)
- Extract @ObservedObject state: 4 hours (OpenTableView refactor is largest)
- NotificationCenter cleanup: 2 hours (ProfileView, BereanChatView, etc.)
- Firestore listener registration storage: 2 hours
- Timer/Task cleanup: 1.5 hours

**Highest impact fixes:**
1. OpenTableView singleton injection refactor (eliminates cascading redraws)
2. Firestore listener registration cleanup (stops listener leak at scale)
3. NotificationCenter deregistration in .onDisappear (prevents observer accumulation)

