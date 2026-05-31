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

## Phase 4 — Review Queue Fixes (commits f21f2b3, ef98c63 + background agent commits)

| SHA | Layer | File | What | Expected Win |
|---|---|---|---|---|
| confirmed | NAV | ContentView.swift | keepMountedTab already implemented: @State mountedTabs: Set<Int>=[0], ZStack gating, onChange insert | ~200-400ms launch; ~30-80MB RSS savings confirmed |
| f21f2b3 | CREATE-POST | CreatePostView.swift | ModerationIngest + BotDefense parallelized via async let | ~200-600ms off publish wait |
| f21f2b3 | RENDER | OpenTableView.swift | networkMonitor extracted via onReceive; PaginationLoadingIndicator child view for firebasePostService.isLoadingMore | Eliminates 2 @ObservedObject cascade redraws |
| confirmed | PERCEIVED | MessagingImplementation.swift + UnifiedChatView.swift | Optimistic DM insert already implemented (commit c3404ae): clientId-keyed FirebaseMessage with .sending state; rollback via notification | Message appears instantly on Send |
| confirmed | CONCURRENCY | SpacesService.swift | Listener tracking array + stopAllListeners() wired to logout | Eliminates 4 orphaned Firestore sockets per Space |
| confirmed | MEDIA | ShortFormTeachingFeedView.swift | isActive: Bool param on TeachingClipCard; onChange(of: vm.currentIndex) wires visibility-driven pause | Off-screen AVPlayer instances paused on page-away |
| ef98c63 | NETWORK | 6 CF files (Feature03-06, PrayerSafetyEscalation, PrayerArcCard, SmartChurchSearch) | callWithTimeout() — 30s AI calls, 15s moderation/data | Worst-case hang reduced from 70s to 15-30s |
| 9035f30 | NETWORK | 11 additional CF files (BereanMemory, Whisper, TestimonyIntegrity, BereanRealtime, BereanContext, BereanVisual, BereanSourceGrounding, BereanCompass, BereanGrok, SmartSuggestions, AmenDailyDigest) | callWithTimeout() across Berean AI stack | 70s → 15-30s hang ceiling; recoverable timeout error |
| confirmed | RENDER | PostCard.swift | Dead AnyView pass-through layer (cardWithMuteBlockAlerts) collapsed; chain shortened by 1 indirection | Marginally faster per-cell SwiftUI diffing |

## Phase 3 — Session 2 Fixes (commits 9035f30, b441424, 5ab2ef6, 2e55266, 2bc75fa)

| SHA | Layer | File | What | Expected Win |
|---|---|---|---|---|
| 9035f30 | MEDIA | SpaceFeedView.swift | AsyncImage → CachedAsyncImage (3 sites) | Zero re-fetches on scroll for cover/avatar images |
| 9035f30 | MEDIA | DiscussionMoreFromOrgShelf.swift | AsyncImage → CachedAsyncImage | Cache miss eliminated per shelf card |
| 9035f30 | MEDIA | DiscussionTopPicksCard.swift | AsyncImage → CachedAsyncImage | Cache miss eliminated per carousel card |
| 9035f30 | MEDIA | MediaCard.swift | AsyncImage → CachedAsyncImage (targetSize 240px) | Full-res decode eliminated for 120pt thumbnail |
| 9035f30 | MEDIA | RepostQuoteComponents.swift | AsyncImage → CachedAsyncImage (2 sites) | Avatar cache hits across repost cells |
| 9035f30 | MEDIA | SuggestedAccountCard.swift | AsyncImage → CachedAsyncImage | Avatar cache in discovery rails |
| 9035f30 | MEDIA | SuggestedForYouModule.swift | AsyncImage → CachedAsyncImage | Avatar cache in discovery rails |
| 9035f30 | MEDIA | SearchSuggestionsView.swift | AsyncImage → CachedAsyncImage | Same avatar URL not re-fetched per keystroke |
| 9035f30 | MEDIA | NowPlayingBar.swift | AsyncImage → CachedAsyncImage | Album art cached across 30 Hz state ticks |
| 9035f30 | MEDIA | DiscussionHeroHeader.swift | AsyncImage → CachedAsyncImage (2 sites) | Hero image cached; avoids 20-40 MB RAM spike |
| 9035f30 | MEDIA | MediaPlayerView.swift | AsyncImage → CachedAsyncImage (2 sites) | Related shelf no longer re-fetches on progress tick |
| 9035f30 | MEDIA | SpaceAvatarView.swift | AsyncImage → CachedAsyncImage | Space avatar cached in feed cells |
| 9035f30 | MEDIA | SpaceCardView.swift | AsyncImage → CachedAsyncImage | Space avatar cached in rail |
| 9035f30 | MEDIA | AMENTabBar.swift | AsyncImage → CachedAsyncImage for user avatar | Tab bar orb cached; avoids re-fetch on every tab switch |
| 9035f30 | MEDIA | VideoAttachmentHandler.swift | AVPlayer() inline → @State + onAppear/onDisappear + preferredForwardBufferDuration=3.0 | Eliminates ~8-15MB AVPlayer re-alloc per sheet open |
| 9035f30 | MEDIA | AmenVideoEditorView.swift | AVPlayer() inline → .task(id: videoURL) + preferredForwardBufferDuration=3.0 | Eliminates player re-init on every @State change |
| 9035f30 | MEDIA | PinnedProfileHeroSurface.swift | AVPlayer() inline → .task(id: url) + preferredForwardBufferDuration=3.0 | Eliminates player re-alloc at ~60fps during scroll |
| 9035f30 | MEDIA | WitnessCameraView.swift | AVPlayer() inline → @State reviewPlayer + preferredForwardBufferDuration=3.0 | Cleaner camera review lifecycle |
| 9035f30 | MEDIA | FullscreenMediaViewer.swift | setupPlayer() guard player == nil + player = nil on teardown | Prevents double-player on rapid appear/disappear |
| 9035f30 | FIRESTORE | AntiHarassmentEngine.swift | .limit() on 5 unbounded enforcement queries (100/100/20/100/50) | Closes O(N) abuse vector on safety collections |
| 9035f30 | FIRESTORE | ChannelService.swift | .order + .limit(to:100) on 2 snapshot listeners | Caps channel message snapshot payload |
| 9035f30 | FIRESTORE | CommunalChatView.swift | guard listener == nil in start() | Prevents duplicate listeners on rapid nav |
| 9035f30 | FIRESTORE | SacredChatView.swift | guard listener == nil in start() | Prevents duplicate listeners on rapid nav |
| 9035f30 | NAV | BereanChatView.swift | loadMessageCount() moved from init() to initialSetupTask() | Eliminates Firestore read blocking sheet open animation |
| 9035f30 | NAV | MessagesView.swift | BadgeCountManager.clearMessages() guarded by mainTabSelection == 2 | Prevents badge clear on background mount |
| 9035f30 | NAV | ProfileView.swift | profileDataUpdated observer: userId payload filter | Eliminates spurious own-profile reloads |
| 9035f30 | CONCURRENCY | ScreenCrashLogger.swift | assert(!Thread.isMainThread) before queue.sync | Documents off-main contract; panics in DEBUG if violated |
| 9035f30 | CONCURRENCY | WriteOpTracer.swift | assert(!Thread.isMainThread) before queue.sync | Same as above |
| 9035f30 | CONCURRENCY | VideoAttachmentHandler.swift | @discardableResult Task return from uploadAndSend() | Callers can now cancel upload on dismiss |
| 9035f30 | CONCURRENCY | MediaPlayerView.swift | [weak vm] in Task in setupPlayer() | Prevents ViewModel retention by orphaned duration-load task |
| 9035f30 | CONCURRENCY | BereanSmartChannelHook.swift | Listener tracking dict + stopListening(groupId:) + stopAllListeners() | Eliminates indefinite Firestore socket leak |
| 9035f30 | CONCURRENCY | NotificationImageCache.swift | @ObservedObject → let for singleton | Eliminates global render-storm risk from future @Published additions |
| b441424 | RENDER | AMENNotificationsView.swift | CachedAsyncImage API updated (phase → content/placeholder); LazyVStack in section ForEach | Rows created on-demand; no re-fetch on scroll |
| b441424 | RENDER | ProfileView.swift | CachedAsyncImage for hero banner cover + blurred avatar | Avoids uncached URLSession round-trip per profile open |
| b441424 | GLASS | SettingsDestinationViews.swift | 43× .regularMaterial → Color(.secondarySystemGroupedBackground) over static bg | Eliminates 43 GPU blur passes per settings open |
| b441424 | CREATE-POST | CreatePostView.swift | Support gate moved into Task (main thread free during open) | ~30-60ms faster compose sheet appearance |
| b441424 | CREATE-POST | CreatePostView.swift | Client-side Firestore idempotency pre-check removed | -200ms per post publish |
| 5ab2ef6 | CONCURRENCY | AmenCommunitySpaceTabs.swift | PrayerRequestsTabView updated to stopListening(groupId:) API | Eliminates orphaned prayer listener on tab dismiss |
| 2e55266 | CONCURRENCY | CommentsView.swift | Highlight-scroll Task{} → .task(id: highlightedCommentIds.first) with isCancelled guards | Orphaned animation state cancelled on nav away |
| 2bc75fa | CONCURRENCY | BereanAIAssistantView.swift | Timer.publish → .task sleep loop (cancellable) | Retained Combine subscription eliminated on sheet dismiss |

## Phase 1.5 — Instrumentation (commit 89ced6d)

| SHA | Layer | File | What | Expected Win |
|---|---|---|---|---|
| 89ced6d | INFRA | CreatePostView.swift | `PerfBegin("post_safety_gauntlet")` | Enables Instruments measurement of publish latency |
| 89ced6d | INFRA | YourFeedView.swift | `PerformanceLog.event("feed_appear")` | Measures feed cold-open cost |
| 89ced6d | INFRA | BereanChatView.swift | `berean_ask` → `berean_first_token` signposts | Measures ask→first-token latency |
| 89ced6d | INFRA | MessagingImplementation.swift | `PerfBegin("dm_send")` | Measures DM send latency |
| 89ced6d | INFRA | AMENTabBar.swift | `PerformanceLog.event("tab_switch")` | Measures tab-switch latency |
| 89ced6d | INFRA | DiscoverSearchComponents.swift | `search_execute` signposts | Measures search latency |
