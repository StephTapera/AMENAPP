# _perf/MANIFEST.md — Surface Inventory
# Generated: 2026-05-31 | Branch: overnight/perf-pass-20260531
# Phase 0 read-only pass — no code modified

---

## SCREENS / SURFACES

| Surface | Primary File | Init Cost | onAppear / .task Work |
|---|---|---|---|
| AMENAPPApp (root) | AMENAPP/AMENAPPApp.swift | HIGH | BGTask registration × 2, URLCache resize, RemoteConfig fetch (Task), UserDefaults migration, HapticManager.prepareAll(), AmenIntentDonationService.donateIntents() — all in init() |
| AppDelegate | AMENAPP/AppDelegate.swift | HIGH | FirebaseApp.configure(), AppCheck pre-warm (Task), Firestore persistence settings, Realtime DB persistence, ServiceBootstrapper.bootstrap() (Task @MainActor), PushNotificationManager.setupFCMToken(), FCM topic subscribes × 2, registerForRemoteNotifications() |
| ContentView | AMENAPP/ContentView.swift | HIGH | @StateObject: ContentViewModel, AuthenticationViewModel (triggers Firestore read), MessagingCoordinator, MediaCaptureCoordinator, FollowRequestsViewModel, WelcomeScreenManager; onAppear: starts 5-task parallel group including preloadCacheSync(), startListening(), FollowService loads, FCM setup, MessageSettingsService |
| HomeView | AMENAPP/ContentView.swift (line 1676) | MED | @StateObject HomeViewModel; mounts multiple child feed views |
| OpenTableView | AMENAPP/AMENAPP/OpenTableView.swift | HIGH | 9 × @ObservedObject singletons; .task: feedAlgorithm.loadInterests() + personalizeFeeds() (Cloud Run call); onAppear: startScrollSession, startNewSession, resetSession, 1.5s counting delay Task; onChange(postsManager.openTablePosts.count): debounced Cloud Run rankPosts every 500ms |
| PostCard | AMENAPP/PostCard.swift | HIGH | 7013 lines; 3 × AnyView wrappers for modifier chaining; 55 animation calls; GeometryReader at action-menu level (lines 675, 2145, 2181, 3163, 3791, 6055); Self._printChanges() in DEBUG body |
| ProfileView (own) | AMENAPP/ProfileView.swift | HIGH | 6896 lines; @ObservedObject: FollowService, FollowRequestsViewModel, PostsManager, PostInteractionsService; onAppear: setupNotificationObservers(), 1.5s delayed digest fetch Task; 2 × raw AsyncImage in hero banner (lines 1819, 1832) |
| UserProfileView (other user) | AMENAPP/UserProfileView.swift | MED | Likely similar to ProfileView — Firestore user + posts fetch on appear |
| BereanChatView | AMENAPP/BereanChatView.swift | HIGH | 4 × @ObservedObject (intelligence coordinator, model store, memory service); GeometryReader at scroll root; contentScrollView uses LazyVStack + ForEach(vm.messages) |
| MessagesView (Inbox) | AMENAPP/MessagesView.swift | HIGH | 7 × @ObservedObject singletons; ScrollView > LazyVStack > GeometryReader (height sensor) at line 658; onAppear line 387 runs even for non-active keepMountedTab; .onAppear inside ForEach at line 783 triggers aiSummaryService.requestSummary per conversation row |
| UnifiedChatView (1-1 DM) | AMENAPP/UnifiedChatView.swift | HIGH | 8 × @ObservedObject singletons; GeometryReader inside ScrollView for scroll offset; LazyVStack + ForEach(messages); onAppear line 969 runs network fetches |
| AMENNotificationsView | AMENAPP/AMENAPP/AMENNotificationsView.swift | MED | LazyVStack(line 683); 3 × raw AsyncImage for actor avatars and thumbnails (lines 219, 282, 297); ForEach inside VStack (UrgentSection line 517, TimeBucketSection line 551) — not lazy |
| PrayerView | AMENAPP/PrayerView.swift | MED | 2 × @ObservedObject (PostsManager, PrayerAlgorithm); LazyVStack+ForEach for posts; CachedAsyncImage used in row cells |
| TestimoniesView | AMENAPP/TestimoniesView.swift | MED | 2 × @ObservedObject; LazyVStack+ForEach for posts |
| CreatePostView | AMENAPP/CreatePostView.swift | HIGH | 15 × @ObservedObject/@StateObject at top level; GeometryReader (line 3060); Algolia user search on compose (line 6589) |
| ChurchNotesView | AMENAPP/ChurchNotesView.swift | MED | Rich editor; Firestore listener for notes |
| FindChurchView | AMENAPP/FindChurchView.swift | MED | Google Maps SDK, location permission, Firestore church reads |
| DiscoverView (hero) | AMENAPP/AMENAPP/Discover/DiscoverView.swift | LOW | Wraps FeaturedHeroCarousel; uses @State DiscoverViewModel; 1 × raw AsyncImage in hero |
| AMENDiscoveryView | AMENAPP/AMENDiscoveryView.swift | MED | Hosts DiscoverView; Algolia/Firestore reads on appear |
| SpacesDiscoveryView | AMENAPP/SpacesDiscoveryView.swift | MED | @StateObject SpacesViewModel; LazyVStack+ForEach; onAppear: vm.load() |
| SabbathModeView | AMENAPP/CalmControl/SabbathModeView.swift | LOW | Preference toggle; minimal network |
| ResourcesView (Tab 3) | — | MED | Mounted via keepMountedTab; always resident in memory |
| AmenGatheringsHomeView (Tab 6) | — | MED | Mounted via keepMountedTab; always resident |
| SpacesRootView (Tab 7) | — | MED | Mounted via keepMountedTab; SpacesViewModel.load() on task |

---

## TABS / NAVIGATION STRUCTURE

The app uses a **keepMountedTab** pattern (ContentView.swift:639). All 8 tabs are mounted simultaneously in a ZStack; inactive tabs receive `.opacity(0)` but remain fully allocated in memory with their ViewModels and onAppear side-effects potentially firing. This is the single largest memory and startup-cost contributor.

Tab index map:
- 0: HomeView (OpenTable + feed)
- 1: AMENDiscoveryView
- 2: MessagesView
- 3: ResourcesView (Church Notes / Find Church)
- 4: AMENNotificationsView
- 5: ProfileView
- 6: AmenGatheringsHomeView (gated)
- 7: SpacesRootView (gated, flag default OFF)
- 8: ChurchNotesView (communityNotes tab)

---

## KEY FLOWS — END TO END

### 1. Cold Launch → First Frame
1. `AppDelegate.didFinishLaunchingWithOptions` — FirebaseApp.configure(), AppCheck pre-warm, Firestore settings, RTDB persistence, `ServiceBootstrapper.bootstrap()` (Tier 0-1 singletons)
2. `AMENAPPApp.init()` — BGTask register × 2, URLCache resize, RemoteConfig.fetch() (background Task), UserDefaults migration
3. SwiftUI instantiates `ContentView` → `@StateObject` init chain (ContentViewModel, AuthenticationViewModel, MessagingCoordinator, ...) — AuthVM immediately calls `checkOnboardingStatus` in a background Task which reads Firestore
4. `AMENAPPApp.body` / `.task` → `loadOnboardingStatusSync` (UserDefaults only), `LiveActivityManager.restoreActiveActivities()`
5. `ContentView.onAppear` → 5-task parallel startup group: `fetchCurrentUserForWelcome()` (Firestore), `preloadCacheSync()` + `startListening(category: .openTable)`, `startFollowServiceListeners()`, `setupFCMForExistingUser()`, `MessageSettingsService.loadSettings()`
6. Auth state listener fires → additional parallel Tasks: FollowService load × 2, PostInteractionsService.prepareForNewUser(), AMENSecureMessagingService key bundle (detached background)
7. First frame renders (authenticated returning user path: main tab bar)
8. `onChange(scenePhase .active)` → DailyVerseGenkitService.generatePersonalizedDailyVerse() + others

### 2. Feed Scroll (OpenTable)
- PostsManager.openTablePosts `@Published` fires → OpenTableView body re-evaluates (9 @ObservedObject subscribers)
- `onChange(postsManager.openTablePosts.count)` → debounced Cloud Run `rankPosts` call (HTTP POST to Cloud Run)
- Each new scroll position → `FeedScrollOffsetKey` preference change → `onPreferenceChange` callback
- Pagination trigger: `loadMorePosts()` → Firestore `.getDocuments` paginated by cursor

### 3. Create New Post
- CreatePostView sheet opens → 15 StateObject/ObservedObject inits
- User types `@mention` → Algolia `searchUsers` call (line 6589)
- Scripture auto-detect → ScriptureAutoDetectService evaluation
- Post submit → `FirebasePostService.createPost()` → Firestore write + optimistic UI NC notification

### 4. Berean AI Ask + Stream
- BereanChatView init → 4 @ObservedObject singletons
- User sends message → Cloud Function or Genkit streaming call
- Stream chunks arrive → `vm.messages` @Published updates → ForEach re-renders each chunk

### 5. Profile Open
- ProfileView.onAppear → setupNotificationObservers(), digestFetchTask (1.5s delay), Firestore posts listener
- Hero banner: raw AsyncImage for banner/avatar (no cache layer)
- Tab content: LazyVStack+ForEach for posts/replies/saves (bounded by pagination)

### 6. Tab Switch
- keepMountedTab pattern: all tabs already mounted, switch is opacity-only
- No view init/deinit cost on tab switch
- ALL tab onAppear handlers fire at initial mount (MessagesView.onAppear at line 387 fires even when tab is not active)

### 7. Search
- AMENDiscoveryView → Algolia full-text search on keypress
- PostSearchView → AlgoliaSearchService.searchUsers/searchPosts

---

## DATA PATHS

### Firestore Reads
| Collection | Bounded? | Call site |
|---|---|---|
| `posts` (openTable listener) | YES — limit(to: 50) via FirebasePostService.startListening | FirebasePostService.swift:1458 |
| `posts` (preloadCacheSync) | YES — limit(to: 50) | FirebasePostService.swift:1092 |
| `posts` (loadMorePosts pagination) | YES — limit(to: pageSize) | FirebasePostService.swift:1667 |
| `posts` (fetchFilteredPosts) | YES — limit(to: 50) | FirebasePostService.swift:1193 |
| `users/{uid}` (fetchCurrentUserForWelcome) | YES — single doc | AMENAPPApp.swift:610 |
| `users/{uid}` (checkOnboardingStatus) | YES — single doc | AuthenticationViewModel.swift |
| `users` (FollowService following/followers) | YES — bounded by following set; batched in-10 | PostsManager.swift:1482 |
| `notifications` | Unbounded listener — no limit observed | NotificationService |
| `messages/{convId}/messages` | Bounded — paginated with load-more cursor | UnifiedChatView |
| `featured` (DiscoverView) | YES — small collection | DiscoverView/DiscoverViewModel |

### Cloud Functions / Cloud Run
| Callable | Trigger |
|---|---|
| `FeedAPIService.rankPosts` (Cloud Run HTTP) | On every openTablePosts.count change (debounced 500ms) |
| `DailyVerseGenkitService.generatePersonalizedDailyVerse` | On every app foreground (.active) |
| `saveBereanInsight`, `updateBereanMemory` | Berean conversation actions |
| `createMediaReflection` | Media reflection sheet |
| `getAmenDailyDigest` | ProfileView digestBrain (1.5s after appear) |
| `resolveBannerRail`, `logAmenSpaceBannerEvent` | Spaces banner |

### Algolia
| Index | Trigger |
|---|---|
| Users index | `@mention` in CreatePostView, RepostQuoteComponents |
| Posts index | PostSearchView full-text |
| Users + Posts | AMENDiscoveryView search |

### Image / Video Loads
- Profile images: `CachedAsyncImage` in most feed rows — good
- Profile hero banner: raw `AsyncImage` (ProfileView.swift:1819, 1832) — bypasses ImageCache
- Notification actor avatars: raw `AsyncImage` (AMENNotificationsView.swift:219, 282, 297) — bypasses ImageCache
- PostCard profile image: `CachedAsyncImage` — good
- Blurred hero (ProfileView): raw `AsyncImage` + `.blur(radius: 22)` on full-res image — expensive

---

## EXISTING PERF INFRA

- `PerformanceLog` / `PerfBegin` / `PerfEnd` — `os_signpost` via OSLog in `PerformanceHUD.swift`; wired in AMENAPPApp.init() around the whole init block
- `ImageCache` — NSCache 150 images / 75MB + URLCache-backed session in `ImageCache.swift`
- `CachedAsyncImage` — used throughout feed and profile; wraps ImageCache
- `URLCache` — resized to AppConfig values (memoryCapacity, diskCapacity) in AMENAPPApp.init()
- Firestore disk cache — 150MB cap, configured in AppDelegate
- Realtime DB cache — 50MB, configured in AppDelegate
- Firestore snapshot debounce — 300ms for server snapshots in FirebasePostService
- Cloud Run rankPosts — 500ms debounce in OpenTableView.onChange
