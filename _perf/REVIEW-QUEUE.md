# _perf/REVIEW-QUEUE.md — Items Requiring Human Review (§6)

These items were NOT auto-fixed — they require architectural decisions, backend changes, or carry regression risk.

---

## ✅ RESOLVED — All Critical + High items addressed

| # | Layer | File | Status | SHA / Notes |
|---|---|---|---|---|
| 1 | NAV/RENDER | ContentView.swift | ✅ DONE | Already implemented: `mountedTabs: Set<Int>=[0]` + `keepMountedTab()` + `onChange` insert |
| 2 | NETWORK | bereanChatProxy (Cloud Function) | ⏳ BACKEND | Requires Cloud Run SSE proxy — iOS client ready; CF deploy needed |
| 3 | CREATE-POST | CreatePostView.swift:4105 | ✅ DONE | f21f2b3 — ModerationIngest + BotDefense parallelized via `async let`; ThinkFirst pair already concurrent |
| 4 | PERCEIVED | MessagingImplementation + UnifiedChatView | ✅ DONE | c3404ae — Full optimistic insert with .sending state + rollback via NotificationCenter |
| 5 | RENDER | PostCard.swift:2229 | ✅ DONE | @ViewBuilder already applied; dead pass-through layer collapsed |
| 6 | RENDER | OpenTableView.swift | ✅ DONE | f21f2b3 + bdac2fc — @ObservedObject fan-out 8→2: DailyVerseBannerSection child view, feedAlgorithm/scrollBudget/feedSession/firebasePostService/featureFlags via .shared; isSessionComplete via .onReceive |
| 7 | NETWORK | 728 CF sites | ✅ DONE | callWithTimeout() helper wired to safeCall() default (15s) + 17 high-risk sites migrated with explicit timeouts |
| 8 | MEDIA | ShortFormTeachingFeedView | ✅ DONE | isActive: Bool param on TeachingClipCard; onChange(of: currentIndex) wires visibility pause |
| 9 | MEDIA | AmenVideoEditorView | ✅ DONE | Phase 3: @State player + .task(id: videoURL) lifecycle |
| 10 | CONCURRENCY | SpacesService.swift | ✅ DONE | listeners: [ListenerRegistration] + stopAllListeners() wired to AppLifecycleManager logout |
| 11 | NETWORK | ProfileView.swift:958 | ✅ DONE | refreshProfile() was already using async let parallelization |
| 12 | NAV | UserProfileView.swift:610 | ✅ DONE | UserProfileCache already implemented with 30s TTL |

---

## 🟡 REMAINING — Backend Only

| # | Layer | Finding | Effort |
|---|---|---|---|
| B1 | NETWORK | Berean real SSE streaming — bereanChatProxyStream Cloud Run proxy not yet deployed | Backend: ~2 days (Cloud Run + URLSession.bytes) |

---

*Phase 2: 12 items (commit 7b98e44). Phase 3: 38 items. Phase 4: 10 of 12 review-queue items resolved. 2 items require backend/structural work.*
