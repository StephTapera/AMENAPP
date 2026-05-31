# _perf/REVIEW-QUEUE.md — Items Requiring Human Review (§6)

These items were NOT auto-fixed — they require architectural decisions, backend changes, or carry regression risk.

---

## 🔴 CRITICAL — Do First

| # | Layer | File | Finding | Risk | Approach |
|---|---|---|---|---|---|
| 1 | NAV/RENDER | ContentView.swift:544-639 | `keepMountedTab` mounts all 8 tabs at app open — 8× ViewModels + listeners live before first frame | HIGH: scroll position preservation; onAppear timing | `@State mountedTabs: Set<Int> = [0]`; gate with `if mountedTabs.contains(i)`; insert on first visit |
| 2 | NETWORK | ClaudeService+bereanChatProxy.ts | Blocking CF call — full LLM awaited before first char; 36s typewriter for 400-word response | HIGH: requires Cloud Run + streaming client | Cloud Run SSE proxy; `URLSession.bytes(for:)` on iOS |
| 3 | CREATE-POST | CreatePostView.swift:4105 | 5 serial safety awaits block UI for 1-4s before Firestore write | MEDIUM: correctness of parallel moderation results | `withTaskGroup`; take strictest result |
| 4 | PERCEIVED | FirebaseMessagingService+Impl | No optimistic DM insert; user sees blank chat 200-800ms after Send | MEDIUM: rollback on CF error needed | Local `.sending`-state message pre-await; rollback via notification |
| 5 | RENDER | PostCard.swift:2229 | 3 chained `AnyView` wrappers prevent SwiftUI diffing; O(cells) heap allocation per parent invalidation | MEDIUM: complex, 7013-line file | Replace with `@ViewBuilder` computed properties |

## 🟠 HIGH — Second Pass

| # | Layer | File | Finding | Risk | Approach |
|---|---|---|---|---|---|
| 6 | RENDER | OpenTableView.swift:4 | 9 @ObservedObject singletons; any @Published change = full body redraw; FirebasePostService has 9 @Published | MEDIUM: requires child view extraction | Extract per-singleton child views with `removeDuplicates()` |
| 7 | NETWORK | 728 CF call sites | No `timeoutInterval`; SDK default 70s = >1min hang on poor signal | LOW: safe but high diff count | Shared `callWithTimeout(_, _, timeout: 15)` helper; migrate all sites |
| 8 | MEDIA | ShortFormTeachingFeedView | Off-screen pages keep playing; CPU/GPU/battery waste | LOW: visibility-driven AVPlayer control | `onDisappear { player.pause() }` / `onAppear { player.play() }` |
| 9 | MEDIA | AmenVideoEditorView | `AVPlayer()` inline in view body — re-created on every @State change | LOW: straightforward | Move to `@StateObject` wrapper |
| 10 | CONCURRENCY | SpacesService.swift | 4 `addSnapshotListener` sites with no cleanup; orphaned listeners on nav-away | LOW: needs deinit path | Store in `[ListenerRegistration]`; `stopAll()` on reset |
| 11 | NETWORK | ProfileView.swift:958 | `refreshProfile()` runs 4 independent fetches serially; sum(P95) ≈ 2400ms pull-to-refresh | LOW: `async let` pattern already proven in same file | Match `loadProfileData()` pattern at line 1199 |
| 12 | NAV | UserProfileView.swift:610 | 4 Firestore reads on every external profile push; no cross-session cache | LOW: cache TTL logic | In-memory 30s TTL cache keyed on userId |

---

*12 items auto-fixed in Phase 2 (commit 7b98e44). 38 additional items fixed in Phase 3 (commits 9035f30, b441424, 5ab2ef6, 2e55266, 2bc75fa). 12 items queued here — require human review.*
