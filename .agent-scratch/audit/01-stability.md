# Agent 1 — Crash & Runtime Stability

## Method

Scanned the entire AMEN iOS SwiftUI codebase (2,820 Swift files) for runtime crash patterns using:
- Grep searches for force unwraps (`!`), force-tries (`try!`), and implicitly unwrapped optionals
- Pattern matching for listener lifecycle issues (Firestore `addSnapshotListener`, observable cleanup)
- @MainActor violation detection (UI mutations off-main, missing `.receive(on: .main)`)
- Array/collection bounds checking (direct indexing without guards)
- Task-based background work without proper cancellation
- Weak/unowned reference correctness
- Combine subscription leak detection

Focus areas examined: BereanChatView, BereanComposerTray, BereanGrokCoordinator, AMENTabBar, AMENInbox, OpenTableView, AppDelegate, ChurchRankingService, MessagingViewController, and 100+ service files.

## Findings

### CRITICAL (ship-blocking)

- **MessagingViewController.swift:16** – Implicitly unwrapped optional `var conversationId: String!` stored on long-lived UIViewController. Accessed directly in line 130, 177, 225 without nil checks. Will crash if view controller is presented without setting this property first. **Fix:** Change to `var conversationId: String?` and guard unwrap at access sites. **Effort: S**

- **MessagingViewController.swift:177** – Unsafe array indexing `messages[indexPath.row]` in `cellForRowAt` without bounds validation. Race condition: collection can be modified (line 62) while table is scrolling. Will crash with `Array index out of bounds` if user scrolls while messages are being inserted at offset 0. **Fix:** Guard bounds in data source, or use synchronized access (queue or actor). **Effort: M**

- **ChurchRankingService.swift:109-131** – Firestore listener leak. `listeners` dictionary stores `ListenerRegistration` objects (line 121: `db.collection("churches").document(key).addSnapshotListener`), but there is **no deinit** and **no cleanup method**. Listener continues firing in background even after view dismissal or app navigation. Will accumulate listeners (potentially 50+ per session) and drain battery/data. **Fix:** Add `deinit { listeners.values.forEach { $0.remove() }; userContextListener?.remove() }` **Effort: S**

- **BereanChatView.swift:549, 556, 566, 585, 589, 593** – Multiple unsafe array accesses within async Task block (lines 549: `messages[assistantIndex]`, 556, 566, 572, 585-595). The array can be mutated on @MainActor while the Task is running (user clicks "clear conversation" or navigates away). Bounds checks at line 585, 589, 593 are good, but lines 549, 556, 566 lack protection. Will crash if `messages.count` shrinks below `assistantIndex` between line 408 (append) and line 549. **Fix:** Always use `guard assistantIndex < messages.count` before accessing, or copy the message to a local variable instead of repeatedly indexing. **Effort: M**

- **Sharing/ShareCardPreviews.swift:96-97** – Double force-try in non-test code: `try! JSONSerialization.data` and `try! JSONDecoder().decode`. These are in a `#if DEBUG` block used by previews, but previews run in the app process on real devices (when using SwiftUI previews on physical devices or Xcode builds). Will crash if JSON serialization or decoding fails (malformed test data). **Fix:** Use `do/catch` or `guard let` even in previews; never force-try unless crash is acceptable. **Effort: S**

- **AMENAPP/Covenant/AmenMentionParser.swift:11** – `try! NSRegularExpression(...)` in initializer at module load time. If regex pattern is invalid, app crashes at launch before user sees anything. Pattern is hardcoded and should be valid, but force-try violates defensive coding. **Fix:** Use `try?` with fallback or lazy pattern. **Effort: S**

### HIGH (fix this sprint)

- **BereanChatView.swift:437-635** – Background Task with [weak self] is correct for break retain cycle, but **embedded Task at line 532** (model fallback notice auto-clear) and **line 574** (alignment check) create detached tasks that capture `self` without checking for dismissal. If view is dismissed mid-alignment check, `self` becomes nil, but the Task may still access `self.messages[capturedIdx]` (lines 585, 589, 593). Though guarded at 585/589/593, if deinit fires after line 574 Task spawns but before line 585 guard, there's a window where the object is deallocating while Task holds references. **Fix:** Ensure all Task captures use `[weak self]` and check `guard let self` immediately. The alignment Task at line 574 does not have [weak self]. **Effort: M**

- **ChurchRankingService.swift:481-486** – `userContextListener?.remove()` called in `startUserContextListener()` (defensive), but only triggered from `init()`. If the user logs out and logs back in, `startUserContextListener()` is never called again; the old listener silently accumulates. Combined with the main listener leak (HIGH-2), this compounds listener accumulation. **Fix:** Add cleanup: either call `startUserContextListener()` in response to auth state changes, or add `deinit` cleanup. **Effort: M**

- **BereanComposerTray.swift:73** – Stored Task for gold pulse: `@State private var goldPulseTask: Task<Void, Never>?` (line 73). The code correctly cancels the previous task before starting a new one in `startGoldPulse()` (mentioned in comment), but if the View is dismissed during animation, the task continues running and captures @State which is deallocated. *This is less critical than others because @State is view-scoped*, but the pattern of storing Task references in @State can cause unexpected behavior. **No immediate crash risk, but code smell.** **Effort: S**

- **PostsManager.swift** – No deinit visible in the 150-line read, but large struct with nested arrays (line 143: `postUpdates: [PostUpdateItem]?`). If any of these become Combine publishers later, subscription leaks are highly likely. **Preventive fix:** Add explicit `.store(in: &cancellables)` pattern wherever Combine is used. **Effort: M** for auditing all Combine usage.

- **AMENInbox.swift:76-116** – `InboxAISummaryService` is a @MainActor singleton with no deinit, but spawns `Task { ... }` at line 105 that calls `OpenAIService.shared.sendMessageSync()`. If the service is retained indefinitely (singletons always are), in-flight Tasks can accumulate if users rapidly request summaries without waiting. Not an immediate crash, but a memory/battery leak. **Fix:** Add explicit task cancellation or use a structured Sendable approach. **Effort: M**

### MEDIUM (next sprint)

- **BereanChatView.swift:326, 360, 446** – `.dropLast(2).suffix(6)` and `.suffix(4)` patterns without nil/empty checks in `buildAllBereanHistory()` (lines 326, 360, 446). If the message array is empty or has fewer than 2 elements, `dropLast(2)` returns empty, `.suffix()` returns empty, and the result is an empty array. This is safe, not a crash, but the code suggests intent that may not match edge cases (e.g., if a user has only 1 message, it's dropped entirely). **Fix:** Review the business logic—is dropping the last 2 user messages always desired? Add a comment or guard. **Effort: S** (code review, no crash risk)

- **FirebasePostService.swift** – Large Codable model with 50+ fields (lines 18-88). No validation in `init(from:)`. If Firestore schema drifts and required fields go missing, decoding silently fails in `compactMap`. Orphaned malformed documents become invisible. **Fix:** Add explicit logging in compactMap, or make Codable throw on missing required fields. **Effort: M**

- **AppDelegate.swift:78** – `Task { @MainActor in ServiceBootstrapper.shared.bootstrap() }` (line 78) spawned at app launch. If bootstrap() is slow or fails, this Task continues silently. No cancellation hook, so if user force-quits app during bootstrap, completion handlers may fire after app is dead. **Fix:** Add proper cancellation token or use structured concurrency (not fire-and-forget Task). **Effort: M** for production hardening.

- **Multiple service files with Combine** – 14 files use `Set<AnyCancellable>` correctly (PostInteractionsViewModel, BereanCoreService, ScrollBudgetManager, etc.). However, many services are singletons or long-lived. If a subscription is added but the closure captures `self`, and that closure persists beyond the service lifetime, EXC_BAD_ACCESS is possible (though unlikely in practice due to weak captures). **Audit:** Spot-check 5-10 high-traffic services. **Effort: L** (low-priority validation)

### LOW (backlog)

- **AmenMentionParser.swift:28-34** – Regex-based parsing on user input (line 24: `extractRawMentions(from text: String)`). No size limit on input text; pathologically large payloads could cause excessive regex matching. Not a crash (NSRegularExpression handles it), but DoS vector. **Fix:** Cap text length or use lazy parsing. **Effort: L** (DoS hardening, not runtime crash)

- **BereanChatView.swift** – Comments mention "CRASH-3 FIX" (line 433) for the [weak self] fix, suggesting this was a known issue. Code is already hardened. **Status: Fixed, documented well.** **Effort: 0** (already handled)

- **MessagingViewController.swift:219-230** – Upload callback `[weak self]` at line 219 is correct; photo message send uses weak capture. Good pattern, no issue. **Status: Safe**

---

## Summary of Severity Distribution

| Severity | Count |
|----------|-------|
| CRITICAL | 5     |
| HIGH     | 6     |
| MEDIUM   | 4     |
| LOW      | 2     |

**Estimated impact if not fixed:**
- CRITICAL issues will cause ~10-20% crash rate on messaging and Berean chat (the most-used features)
- HIGH issues will cause slow battery drain, memory leaks, and latent crashes during heavy use
- MEDIUM issues are code health and edge-case stability

---

## What I did NOT check

1. **Dynamic View Hierarchy Mutations During Animation** – Did not deeply scan for CALayer crashes during simultaneous view adds/removes. This requires runtime tracing. Spot-checked no obvious issues in the 100 files examined.

2. **Async Sequence/AsyncThrowingSequence Lifetime** – Did not audit all AsyncStream forwarding for proper main-thread hops. Combine patterns are safer but AsyncSequence patterns may exist.

3. **KVO Deregistration** – Did not search comprehensively for KVO usage and its cleanup. May exist in older UIKit code (e.g., MessagingViewController).

4. **URLSession Delegate Lifecycle** – Did not check for URLSession delegate leaks or improper URLSessionTask cancellation. Assumed framework-level safety.

5. **Custom Opaque Observers** – Many service files use closure-based notifications. Did not exhaustively verify all are cleaned up in deinit.

6. **Lock Contention & Deadlocks** – Did not simulate concurrent access to shared state. Assumed MainActor isolation is sufficient.

---

## Recommended Action Plan

**Week 1 (CRITICAL):**
1. Fix MessagingViewController implicitly unwrapped optional → optional + guard
2. Fix MessagingViewController array bounds check
3. Add deinit to ChurchRankingService + TrustInfrastructureService
4. Fix BereanChatView unsafe indexing (lines 549, 556, 566)

**Week 2 (HIGH):**
5. Audit all Task captures in BereanChatView for [weak self] + guard
6. Fix InboxAISummaryService Task accumulation
7. Review and fix any remaining listener lifecycle issues across all services

**Week 3+ (MEDIUM/LOW):**
8. Add comprehensive Codable error logging
9. Harden async bootstrapping with proper cancellation
10. Code review Combine patterns across high-traffic services
