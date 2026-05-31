# _perf/FIXED.md — Auto-Fixed Items (§5)

Format: `SHA | Layer | File | What | Expected Win`

---

## Phase 2 — Safe Fixes (commit 7b98e44)

| SHA | Layer | File | What | Expected Win |
|---|---|---|---|---|
| 7b98e44 | NETWORK | ClaudeService.swift | typewriterStream `try?`→`try`+`checkCancellation` — zombie playback task now exits immediately on dismiss | CPU-free dismissal; was up to 36s of orphaned work |
| 7b98e44 | FIRESTORE | BereanConversationService.swift | `.limit(to:50)` on messages listener | Caps initial snapshot for long Berean conversations |
| 7b98e44 | FIRESTORE | UserProfileView.swift | `.limit(to:50)` on profile posts listener | Caps O(N) post snapshot for prolific creators |
| 7b98e44 | FIRESTORE | MessagingImplementation.swift | `.limit(to:200)` on conversation scan in `createConversationWithPermissions` | Caps O(N) DM open cost |
| 7b98e44 | RENDER | BereanAIAssistantView.swift | `VStack → LazyVStack` in `chatMessageList` | ~40-60% faster initial chat render |
| 7b98e44 | GLASS | AMENTabBar.swift | `.drawingGroup()` on `LiquidGlassTabBarBackground` | Single GPU layer for 4-layer glass; stable scroll fps on A14/A15 |
| 7b98e44 | RENDER | PostCard.swift | `_printChanges()` gated behind `AMEN_VERBOSE_RENDER` flag | Eliminates ~20 stdout writes/frame in DEBUG |
| 7b98e44 | LAUNCH | AMENAPPApp.swift | `hasStartedStartupTasks` session guard | Eliminates `preloadCacheSync` + listener re-fire on every foreground |
| 7b98e44 | NAV | AMENDiscoveryView.swift | Staleness guard on `feedService.loadAll()` in `onAppear` | Eliminates 6 parallel network requests on every tab-switch return |
| 7b98e44 | SEARCH | DiscoveryService.swift | Typeahead debounce 200ms → 300ms | ~30% fewer Algolia typeahead RPCs |
| 7b98e44 | SEARCH | SearchViewComponents_New.swift | Remove double-layer debounce (internal 300ms sleep removed) | -300ms search latency on type-then-pause |
| 7b98e44 | PERCEIVED | AMENAPP/OpenTableView.swift | Skeleton safety timeout 4s → 2s | Faster empty-state reveal on slow connections |

## Phase 1.5 — Instrumentation (commit 89ced6d)

| SHA | Layer | File | What | Expected Win |
|---|---|---|---|---|
| 89ced6d | INFRA | CreatePostView.swift | `PerfBegin("post_safety_gauntlet")` | Enables Instruments measurement of publish latency |
| 89ced6d | INFRA | YourFeedView.swift | `PerformanceLog.event("feed_appear")` | Measures feed cold-open cost |
| 89ced6d | INFRA | BereanChatView.swift | `berean_ask` → `berean_first_token` signposts | Measures ask→first-token latency |
| 89ced6d | INFRA | MessagingImplementation.swift | `PerfBegin("dm_send")` | Measures DM send latency |
| 89ced6d | INFRA | AMENTabBar.swift | `PerformanceLog.event("tab_switch")` | Measures tab-switch latency |
| 89ced6d | INFRA | DiscoverSearchComponents.swift | `search_execute` signposts | Measures search latency |
