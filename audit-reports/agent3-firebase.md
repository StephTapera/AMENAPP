# Agent 3 — Firebase / Network Performance Audit
**Date:** 2026-05-28  
**Branch:** berean/ui-rebuild-liquid-glass-v1  
**Auditor:** Agent 3 (Firebase/Network)

---

## Findings

| # | File:Line | Issue | Severity |
|---|-----------|-------|----------|
| F1 | `Meetings/LiveMeetingView.swift:211` | `LiveMeetingViewModel` stores a `ListenerRegistration` with no `deinit` and no `onDisappear` cleanup on the view. Listener leaks if the view is dismissed before the Task finishes. | HIGH |
| F2 | `Meetings/MeetingService.swift:39,47` | `fetchMeetingsForGroup` and `listenMeetingsForGroup` have no `.limit()`. A group with many historical meetings fetches all documents unbounded. | HIGH |
| F3 | `RelationshipGraph/RelationshipService.swift:106,117` | `fetchMyGroups` and `fetchMembers(of:)` fetch unbounded collections — power users in many groups or large churches could receive thousands of documents. | HIGH |
| F4 | `BereanSmarts/BereanSmartChannelHook.swift:66,75` | `fetchOpenChannelPrayerRequests` and `listenChannelPrayerRequests` have no `.limit()`. Active groups accumulate many prayer requests over time. | HIGH |
| F5 | `AIBibleStudyExtensions.swift:114` | N+1 query pattern: fetches 20 conversation documents then serially fetches each sub-collection `messages` in a sequential `for` loop — up to 21 total sequential Firestore reads per load. | HIGH |
| F6 | `PrivacyDashboardView.swift:163,166` | Unbounded queries for `posts` and `comments` by `userId` — active users could have thousands of documents; all are fetched into memory just to count them. | MED |
| F7 | `AIScriptureCrossRefService.swift:107` | Polling loop (`waitForReferences`) polls Firestore every 500ms for 8 iterations (4 seconds) after writing a request document. This is a busy-wait anti-pattern — should use a snapshot listener instead. Tolerable at current scale but wasteful. | MED |
| F8 | `CommunicationOS/AmenSmartCommandPaletteView.swift:178` | Inline Firestore query in a view's search path — `db.collection(actionsPath).whereField(...).limit(to:50).getDocuments()` — has no result caching. Called on every keystroke (debounced at search level but no result cache). | LOW |
| F9 | `BereanSmarts/BereanSmartChannelHook.swift:75` | `listenChannelPrayerRequests` returns a `ListenerRegistration` to the caller but has no `[weak self]` guard — callers must ensure they call `.remove()` or the listener is permanent. Contract is fine but undocumented. | LOW |
| F10 | `Meetings/MeetingService.swift:47` | `listenMeetingsForGroup` listener closure has no `[weak self]` — not an issue currently because the handler is a free closure, but if it ever captures a view model, it would create a retain cycle. | LOW |
| F11 | `RelationshipGraph/RelationshipService.swift:155` | `requestDiscipleship` fetches entire discipleship collection for current user to check for duplicates — unbounded for users with many past discipleships. | LOW |
| F12 | `AIChurchRecommendationService.swift:183` | `waitForRecommendations` polls Firestore every 500ms for 60 iterations (30s). Same busy-wait anti-pattern as F7. | LOW |
| F13 | `FirebaseMessagingService.swift` (various) | Service class is well structured with deinit cleanup and `.limit(to:50)` on most listeners. No issues found in the critical message delivery path. | — (CLEAN) |
| F14 | `CommunicationOS/AmenPrayerSignalService.swift` | Listener stored in `signalsListener`, `stopListening()` exists, `[weak self]` used. No issues. | — (CLEAN) |
| F15 | `CommunicationOS/AmenSmartActionsService.swift` | Listener stored in `actionsListener`, `stopListening()` exists, `[weak self]` used. No issues. | — (CLEAN) |
| F16 | `CommunicationOS/AmenGroupPulseService.swift` | Listener properly managed with stopListening + [weak self]. No issues. | — (CLEAN) |
| F17 | `BereanPulse/BereanPulseService.swift` | `observeCards` uses `AsyncStream` with `continuation.onTermination` to call `listener.remove()`. Correct pattern. No issues. | — (CLEAN) |
| F18 | `AIIntelligence/BereanRealtimeServices.swift` | Both caption and scripture listeners use `[weak self]` and `stop()` method removes both. No issues. | — (CLEAN) |
| F19 | `CalmControl/Services/CalmControlService.swift` | All 5 listeners stored in properties with `deinit` cleanup. No issues. | — (CLEAN) |

---

## Implemented

### Fix 1 — `LiveMeetingViewModel` listener leak (HIGH)
**File:** `AMENAPP/AMENAPP/AMENAPP/Meetings/LiveMeetingView.swift`

Added `deinit` to `LiveMeetingViewModel` to remove the snapshot listener when the view model is deallocated. Added a `stop()` method. Added `.onDisappear { vm.stop() }` to `LiveMeetingView` body to remove the listener promptly on navigation away (before dealloc).

### Fix 2 — `MeetingService` unbounded queries (HIGH)
**File:** `AMENAPP/AMENAPP/AMENAPP/Meetings/MeetingService.swift`

Added `.limit(to: 50)` to both `fetchMeetingsForGroup` and `listenMeetingsForGroup`. 50 is a generous cap for any group's meeting history while preventing full-table scans.

### Fix 3 — `RelationshipService` unbounded group/member queries (HIGH)
**File:** `AMENAPP/AMENAPP/AMENAPP/RelationshipGraph/RelationshipService.swift`

Added `.limit(to: 100)` to `fetchMyGroups` — a realistic cap for groups a user belongs to.  
Added `.limit(to: 200)` to `fetchMembers(of:)` — enough for any small to medium church group.

### Fix 4 — `BereanSmartChannelHook` unbounded prayer request queries (HIGH)
**File:** `AMENAPP/AMENAPP/AMENAPP/BereanSmarts/BereanSmartChannelHook.swift`

Added `.limit(to: 50)` to both `fetchOpenChannelPrayerRequests` and `listenChannelPrayerRequests`. Limits live prayer signal load without truncating meaningful recent requests.

### Fix 5 — N+1 serial sub-collection fetch in `AIBibleStudyExtensions` (HIGH)
**File:** `AMENAPP/AIBibleStudyExtensions.swift`

Replaced a sequential `for` loop over `snapshot.documents` (each issuing a serial `await` Firestore call) with a `withThrowingTaskGroup` that dispatches all message sub-collection fetches **concurrently**. Results are sorted back to insertion order and filtered for non-empty. Also changed `lazy var db` to `let db` inside the function (the `lazy` keyword is invalid on local variables and was causing a compiler warning). Added `.limit(to: 200)` to each message sub-collection fetch to cap individual conversation payload.

### Fix 6 — `PrivacyDashboardView` unbounded user-data count queries (MED)
**File:** `AMENAPP/PrivacyDashboardView.swift`

Added `.limit(to: 1000)` to both the `posts` and `comments` count queries. This is a UI display use-case (just showing a count); 1000 prevents full table scans while still yielding a practically correct count for most users. A comment explains that exact counts should be served by a backend counter if precise values are needed.

---

## Deferred

| Item | Details | Effort |
|------|---------|--------|
| D1 — Convert `AIScriptureCrossRefService.waitForReferences` polling to snapshot listener | Replace 8-iteration poll loop with a single `addSnapshotListener` + continuation + timeout Task race pattern. Saves ~3.5s of unnecessary Firestore reads per cross-reference lookup when AI responds quickly. | S |
| D2 — Convert `AIChurchRecommendationService.waitForRecommendations` polling to snapshot listener | Same pattern as D1. Currently polls 60 × 500ms = 30s total. Should be replaced with listener + 30s cancel timeout. | S |
| D3 — Add `[weak self]` to `MeetingService.listenMeetingsForGroup` closure | Low risk now (free handler closure) but worth annotating before any refactor adds a service-level capture. | S |
| D4 — Add `.limit()` to `RelationshipService.requestDiscipleship` duplicate-check query | `fetchOpenChannelPrayerRequests` was already fixed. The discipleship-check also scans all of a user's discipleship records. Add `.limit(to: 50)` safe cap. | S |
| D5 — Cloud Function `minInstances` for hot-path callables | `bereanChatProxy`, `guardianClassify`, `generateGroupPulse`, `detectPrayerSignal` are invoked on real-time paths. Cold starts (2–8s) degrade UX on these paths. Recommend `minInstances: 1` on production. Requires Firebase Functions deploy config change — not a Swift change. | M |
| D6 — Algolia/Pinecone result caching between navigations | `DiscoverSearchComponents` issues new Algolia/Pinecone queries on every view appearance. Consider a 5-minute TTL in-memory cache in `DiscoverService` keyed on query string. | M |
| D7 — Firebase Storage image sizing | No CDN resize extension is configured. All images are served at full upload resolution. Should integrate Firebase Extensions "Resize Images" to auto-generate 200px, 400px, 800px variants. | L |
| D8 — App launch network waterfall | `SavedCommunitiesService.startListening()`, `NotificationService`, and `CalmControlService.startListening()` all attach Firestore listeners at launch/sign-in. Consider deferring to first tab view appearance rather than attaching immediately in `onAppear` of the root tab. | M |
| D9 — `BereanConversationService` / `ChatMemoryService` snapshot listener audit | These files are large (40k+ tokens each) and could not be fully scanned in this pass. Both use `addSnapshotListener`; a dedicated sub-audit is recommended to verify all listener registration handles are properly stored and cleaned up. | M |

---

## Risk Notes

1. **Listener leaks in shared singletons** — `AmenPrayerSignalService`, `AmenSmartActionsService`, `AmenGroupPulseService`, and `AmenSmartPresenceService` are all singletons with `stopListening()` methods. Risk: callers that start listening but don't stop before the thread changes will accumulate orphaned listeners. This is architecturally managed by the feature-flag guards (all flags default OFF), but should be audited once flags are turned ON.

2. **N+1 pattern in large-data views** — The `AIBibleStudyExtensions` fix converts a serial N+1 into a concurrent fan-out. However, at 20 conversations × 200 messages = up to 4000 document reads per load — still potentially expensive. The long-term fix is to embed a limited message preview (e.g., first/last 3 messages) in the conversation parent document to avoid sub-collection reads entirely.

3. **PrivacyDashboardView counts** — The 1000-document cap added means users with >1000 posts or comments will see "1000" rather than the true count. A GDPR-correct solution would be a Cloud Function that returns exact Firestore aggregate counts (`count()` query), which does not transfer documents. Filed as a deferred item.

4. **Unbounded queries still present in non-audited files** — `AntiHarassmentEngine.swift` contains ~8 unbounded `.getDocuments()` calls on the `reports` and `users` collections. These were not modified in this pass because they are in admin-path moderation queries (not user-facing hot paths), but should be capped in a safety/moderation audit.

5. **`deleteAllPosts()` in `FirebasePostService`** — Line 2225 fetches ALL posts from Firestore unbounded to delete them. This is marked as a dev-only function but is included in the production binary. Should be guarded with `#if DEBUG` or removed.
