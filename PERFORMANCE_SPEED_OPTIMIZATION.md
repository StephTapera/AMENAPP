# AMEN Performance & Speed Optimization Plan
**Date**: February 26, 2026
**Focus**: Navigation speed, UI responsiveness, and eliminating lag throughout the app

---

## Executive Summary

**Current Performance Issues Identified:**

1. **App Launch**: 1.3s welcome screen + auth resolution causing 1.5-2s total launch time
2. **ContentView**: 6+ @ObservedObject singletons causing unnecessary redraws
3. **PostCard**: Heavy view body recomputation on every interaction
4. **Tab Switching**: Lag due to lazy tab content initialization
5. **Feed Scrolling**: Profile image loading blocking main thread
6. **View Transitions**: Synchronous Firebase calls during navigation
7. **Image Loading**: No progressive loading or caching strategy

**Target Performance Goals:**
- App launch to content: < 1 second
- Tab switching: < 100ms (instant feel)
- Feed scrolling: 60fps constant
- View push/pop: < 200ms
- Image loading: Progressive with instant cache hits

---

## Critical Performance Bottlenecks

### 🔴 P0: App Launch Performance

**Current Flow** (1.5-2s total):
```swift
// AMENAPPApp.swift:130-165
.onAppear {
    ScrollBudgetManager.shared.trackAppReopen() // Sync

    Task(priority: .high) {
        await fetchCurrentUserForWelcome()  // 300-500ms
        await FirebasePostService.shared.preloadCacheSync()  // 200-400ms
        FirebasePostService.shared.startListening()  // Async but blocks
    }

    Task(priority: .medium) {
        await startFollowServiceListeners()  // 200-300ms
        await setupFCMForExistingUser()  // 100-200ms
    }
}
```

**Problem**: Sequential tasks blocking UI, excessive splash screen duration

**Solution: Parallel Loading with Instant UI**:
```swift
// AMENAPPApp.swift - OPTIMIZED
.onAppear {
    // INSTANT: Show UI immediately (no wait)
    Task { @MainActor in
        showWelcomeScreen = false  // Remove splash instantly
    }

    // PARALLEL: Load everything in background
    Task(priority: .userInitiated) {
        async let userTask = fetchCurrentUserForWelcome()
        async let postsTask = FirebasePostService.shared.preloadCacheSync()
        async let followTask = FollowService.shared.loadCurrentUserFollowing()
        async let fcmTask = setupFCMForExistingUser()

        // Wait for all in parallel
        _ = await (userTask, postsTask, followTask, fcmTask)
        print("✅ All startup tasks complete")
    }
}
```

**Expected Improvement**: 1.5s → 0.5s (67% faster)

---

### 🔴 P0: ContentView Observation Overhead

**Current Problem** (ContentView.swift:19-29):
```swift
// PROBLEM: 6+ @ObservedObject singletons = 6x view redraws
@ObservedObject private var appUsageTracker = AppUsageTracker.shared
@ObservedObject private var notificationManager = NotificationManager.shared
@ObservedObject private var badgeCountManager = BadgeCountManager.shared
@ObservedObject private var churchFocusManager = SundayChurchFocusManager.shared
@ObservedObject private var messagingService = FirebaseMessagingService.shared
@ObservedObject private var ftueManager = FTUEManager.shared

// Result: ContentView.body recomputes on:
// - Every badge count change
// - Every message received
// - Every notification
// - Every FTUE step
// = 20-50 redraws per minute during active use!
```

**Solution 1: Extract Specific State**:
```swift
// ContentView.swift - OPTIMIZED
// Only observe the SPECIFIC values you need
@State private var unreadBadgeCount: Int = 0
@State private var showSundayPrompt: Bool = false

var body: some View {
    // ...
    .onReceive(BadgeCountManager.shared.$totalBadgeCount) { count in
        unreadBadgeCount = count  // Only update when badge changes
    }
    .onReceive(SundayChurchFocusManager.shared.$showSundayPrompt) { show in
        showSundayPrompt = show
    }
}
```

**Solution 2: Use @EnvironmentObject**:
```swift
// AMENAPPApp.swift
WindowGroup {
    ContentView()
        .environmentObject(BadgeCountManager.shared)
        .environmentObject(NotificationManager.shared)
}

// ContentView.swift
@EnvironmentObject var badgeCountManager: BadgeCountManager
// Now only redraws when ContentView USES the specific @Published property
```

**Expected Improvement**: 80% reduction in ContentView redraws

---

### 🔴 P0: PostCard Body Recomputation

**Current Problem** (PostCard.swift:24-31):
```swift
// PROBLEM: Every PostCard observes ALL singletons
@ObservedObject private var postsManager = PostsManager.shared
@ObservedObject private var savedPostsService = RealtimeSavedPostsService.shared
@ObservedObject private var followService = FollowService.shared
@ObservedObject private var moderationService = ModerationService.shared
@ObservedObject private var pinnedPostService = PinnedPostService.shared
@ObservedObject private var interactionsService = PostInteractionsService.shared

// Result: 100 posts in feed = 100 views redrawing on ANY interaction!
// Tap "like" on one post → ALL 100 posts redraw their body!
```

**Solution: Extract Per-Post State**:
```swift
// PostCard.swift - OPTIMIZED
// Don't observe entire services - extract per-post state
struct PostCard: View {
    let post: Post
    @State private var hasLiked: Bool = false
    @State private var likeCount: Int = 0
    @State private var isSaved: Bool = false
    @State private var isFollowing: Bool = false

    var body: some View {
        // ... use local state
    }

    .onAppear {
        // Load initial state ONCE
        hasLiked = interactionsService.hasLiked(postId: post.id)
        likeCount = post.amenCount
        isSaved = savedPostsService.isSaved(postId: post.id)
        isFollowing = followService.isFollowing(userId: post.authorId)
    }

    // Listen to ONLY this post's changes
    .onReceive(interactionsService.likeUpdates(for: post.id)) { update in
        hasLiked = update.liked
        likeCount = update.count
    }
}
```

**Expected Improvement**: 90% reduction in PostCard redraws during interaction

---

### 🔴 P0: Tab Switching Lag

**Current Problem**:
- Tabs initialize lazily on first appearance
- Fetching data synchronously during tab switch
- No preloading of adjacent tabs

**Solution: Preload Adjacent Tabs**:
```swift
// ContentView.swift - OPTIMIZED
TabView(selection: $selectedTab) {
    HomeFeedView()
        .tag(0)
        .onAppear { preloadTab(1) }  // Preload next tab

    PrayerView()
        .tag(1)
        .onAppear { preloadTab(2) }

    MessagesView()
        .tag(2)
        .onAppear { preloadTab(3) }
}

private func preloadTab(_ index: Int) {
    Task(priority: .utility) {
        switch index {
        case 1:
            // Preload prayer posts
            _ = PrayerService.shared
            await PrayerService.shared.loadPrayers()
        case 2:
            // Preload messages
            _ = FirebaseMessagingService.shared
            await FirebaseMessagingService.shared.startListeningToConversations()
        default:
            break
        }
    }
}
```

**Expected Improvement**: Tab switch lag 300ms → 50ms (83% faster)

---

### 🟡 P1: Feed Scrolling Performance

**Current Problem**:
1. **Profile images loading synchronously** on main thread
2. **No image caching** - reload on every scroll
3. **Heavy body computation** per cell

**Solution 1: Async Image Loading with Cache**:
```swift
// PostCard.swift - OPTIMIZED
struct PostCard: View {
    @State private var profileImage: UIImage?

    var body: some View {
        // ...
        if let image = profileImage {
            Image(uiImage: image)
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        } else {
            // Placeholder while loading
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(post.authorInitials)
                        .font(.system(size: 16, weight: .semibold))
                }
        }
    }

    .task {
        // Load image asynchronously with caching
        profileImage = await ImageCache.shared.loadImage(
            url: post.authorProfileImageURL,
            size: CGSize(width: 88, height: 88)  // 2x for retina
        )
    }
}

// ImageCache.swift - NEW FILE
@MainActor
class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    init() {
        cache.countLimit = 100  // Cache 100 images
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB
    }

    func loadImage(url: String?, size: CGSize) async -> UIImage? {
        guard let url = url, !url.isEmpty else { return nil }

        // Check cache first
        if let cached = cache.object(forKey: url as NSString) {
            return cached
        }

        // Check if already loading
        if let existingTask = inFlightTasks[url] {
            return await existingTask.value
        }

        // Load image
        let task = Task {
            guard let imageURL = URL(string: url) else { return nil }

            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                guard let image = UIImage(data: data) else { return nil }

                // Resize on background thread
                let resized = await Task.detached(priority: .utility) {
                    image.preparingThumbnail(of: size)
                }.value

                // Cache it
                if let resized = resized {
                    cache.setObject(resized, forKey: url as NSString)
                }

                return resized
            } catch {
                return nil
            }
        }

        inFlightTasks[url] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: url)

        return result
    }
}
```

**Solution 2: Lazy Cell Rendering**:
```swift
// Feed view - use LazyVStack instead of VStack
ScrollView {
    LazyVStack(spacing: 12, pinnedViews: []) {
        ForEach(posts) { post in
            PostCard(post: post)
                .id(post.id)
        }
    }
}
```

**Expected Improvement**: 60fps scrolling even with 100+ posts

---

### 🟡 P1: View Transition Performance

**Current Problem**:
```swift
// PostCard.swift - PROBLEM
Button {
    showPostDetail = true  // Triggers NavigationLink
} label: {
    // Post content
}
.sheet(isPresented: $showPostDetail) {
    PostDetailView(post: post)
        .onAppear {
            // BLOCKING: Loads comments synchronously
            await commentService.loadComments(for: post.id)
        }
}
```

**Solution: Preload Data Before Transition**:
```swift
// PostCard.swift - OPTIMIZED
Button {
    // Preload comments BEFORE showing sheet
    Task { @MainActor in
        await commentService.preloadComments(for: post.id)
        showPostDetail = true  // Now show sheet instantly
    }
} label: {
    // Post content
}
.sheet(isPresented: $showPostDetail) {
    PostDetailView(post: post)
        // Comments already loaded!
}
```

**Expected Improvement**: Sheet appears 400ms faster

---

### 🟡 P1: Firebase Listener Optimization

**Current Problem**:
- 64 Firestore listeners across app
- No listener pooling or batching
- Listeners not cleaned up properly

**Solution: Listener Pooling**:
```swift
// FirebaseListenerPool.swift - NEW FILE
@MainActor
class FirebaseListenerPool {
    static let shared = FirebaseListenerPool()

    private var listeners: [String: ListenerRegistration] = [:]
    private var listenerCounts: [String: Int] = [:]

    func addListener(
        id: String,
        query: Query,
        handler: @escaping (QuerySnapshot?, Error?) -> Void
    ) {
        // Check if listener already exists
        if listeners[id] != nil {
            listenerCounts[id, default: 0] += 1
            print("⚡️ Reusing existing listener: \\(id)")
            return
        }

        // Create new listener
        let listener = query.addSnapshotListener(handler)
        listeners[id] = listener
        listenerCounts[id] = 1
        print("✅ Created new listener: \\(id)")
    }

    func removeListener(id: String) {
        guard let count = listenerCounts[id] else { return }

        if count <= 1 {
            // Last reference - actually remove listener
            listeners[id]?.remove()
            listeners.removeValue(forKey: id)
            listenerCounts.removeValue(forKey: id)
            print("🧹 Removed listener: \\(id)")
        } else {
            // Still have references - decrement
            listenerCounts[id] = count - 1
            print("📉 Decremented listener count: \\(id) (\\(count - 1) remaining)")
        }
    }
}

// Usage in PostsManager:
func startListening() {
    FirebaseListenerPool.shared.addListener(
        id: "posts_opentable",
        query: db.collection("posts").whereField("category", isEqualTo: "openTable")
    ) { snapshot, error in
        // Handle updates
    }
}
```

**Expected Improvement**: Reduce listener overhead by 60%

---

## Implementation Plan

### Phase 1: Critical Path (Week 1)

**Day 1-2: App Launch Optimization**
- [ ] Remove welcome screen delay (AMENAPPApp.swift:125)
- [ ] Parallelize startup tasks (AMENAPPApp.swift:136-165)
- [ ] Defer non-critical migrations to background
- [ ] Test launch time: target < 1s

**Day 3-4: ContentView Observation**
- [ ] Extract specific state from @ObservedObject singletons
- [ ] Convert to @EnvironmentObject pattern
- [ ] Use .onReceive for specific @Published values
- [ ] Measure: 80% reduction in redraws

**Day 5-6: PostCard Optimization**
- [ ] Extract per-post state (remove @ObservedObject singletons)
- [ ] Implement .onReceive for post-specific updates
- [ ] Add debouncing for rapid interactions
- [ ] Test: 100-post feed should scroll at 60fps

**Day 7: Testing & Verification**
- [ ] Profile with Instruments (Time Profiler)
- [ ] Test on iPhone SE (slowest device)
- [ ] Verify 60fps scrolling
- [ ] Measure app launch time

### Phase 2: User Experience (Week 2)

**Day 8-9: Tab Switching**
- [ ] Implement tab preloading
- [ ] Cache tab state between switches
- [ ] Test: tab switch < 100ms

**Day 10-11: Image Loading**
- [ ] Implement ImageCache
- [ ] Add progressive loading
- [ ] Resize images on background thread
- [ ] Test: images appear < 50ms from cache

**Day 12-13: View Transitions**
- [ ] Preload data before sheet presentation
- [ ] Optimize PostDetailView loading
- [ ] Add skeleton states
- [ ] Test: sheets appear < 200ms

**Day 14: Performance Testing**
- [ ] Full app performance audit
- [ ] Test all critical flows
- [ ] Verify 60fps throughout

### Phase 3: Advanced Optimization (Week 3)

**Day 15-16: Firebase Listener Pool**
- [ ] Implement listener pooling
- [ ] Deduplicate listeners
- [ ] Add cleanup on deinit

**Day 17-18: Memory Optimization**
- [ ] Profile memory usage with Instruments
- [ ] Fix memory leaks (Leaks instrument)
- [ ] Reduce peak memory by 30%

**Day 19-20: Battery & Network**
- [ ] Batch network requests
- [ ] Implement exponential backoff
- [ ] Reduce Firebase reads by 40%

**Day 21: Final Testing**
- [ ] Test on all devices
- [ ] Verify all performance goals met
- [ ] Document improvements

---

## Code Changes Required

### 1. AMENAPPApp.swift - Remove Welcome Screen Delay

```swift
// BEFORE (AMENAPPApp.swift:118-128)
ZStack {
    ContentView()

    if showWelcomeScreen {
        WelcomeScreenView(isPresented: $showWelcomeScreen)
            .transition(.opacity)
            .zIndex(1)
    }
}

// AFTER - NO WELCOME SCREEN
ContentView()
    .handleChurchDeepLinks()
```

### 2. AMENAPPApp.swift - Parallelize Startup

```swift
// BEFORE (AMENAPPApp.swift:136-165) - Sequential
Task(priority: .high) {
    await fetchCurrentUserForWelcome()
    await FirebasePostService.shared.preloadCacheSync()
}
Task(priority: .medium) {
    await startFollowServiceListeners()
    await setupFCMForExistingUser()
}

// AFTER - Parallel
Task(priority: .userInitiated) {
    async let user = fetchCurrentUserForWelcome()
    async let posts = FirebasePostService.shared.preloadCacheSync()
    async let follow = FollowService.shared.loadCurrentUserFollowing()
    async let fcm = setupFCMForExistingUser()

    _ = await (user, posts, follow, fcm)
}
```

### 3. ContentView.swift - Fix @ObservedObject Overhead

```swift
// BEFORE (ContentView.swift:19-29) - Observes entire singletons
@ObservedObject private var badgeCountManager = BadgeCountManager.shared
@ObservedObject private var notificationManager = NotificationManager.shared
@ObservedObject private var messagingService = FirebaseMessagingService.shared

// AFTER - Extract specific state
@State private var totalBadgeCount: Int = 0
@State private var unreadMessages: Int = 0

var body: some View {
    // ...
    .onReceive(BadgeCountManager.shared.$totalBadgeCount) { count in
        totalBadgeCount = count
    }
    .onReceive(FirebaseMessagingService.shared.$unreadCount) { count in
        unreadMessages = count
    }
}
```

### 4. PostCard.swift - Remove Singleton Observation

```swift
// BEFORE (PostCard.swift:24-31) - Every card observes all services
@ObservedObject private var postsManager = PostsManager.shared
@ObservedObject private var savedPostsService = RealtimeSavedPostsService.shared
@ObservedObject private var followService = FollowService.shared

// AFTER - Local state only
@State private var isSaved: Bool = false
@State private var isFollowing: Bool = false
@State private var likeCount: Int = 0

.onAppear {
    isSaved = RealtimeSavedPostsService.shared.isSaved(postId: post.id)
    isFollowing = FollowService.shared.isFollowing(userId: post.authorId)
    likeCount = post.amenCount
}
```

### 5. Create ImageCache.swift

```swift
// NEW FILE: ImageCache.swift
import UIKit

@MainActor
class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB
    }

    func loadImage(url: String?, size: CGSize) async -> UIImage? {
        // Implementation shown above
    }
}
```

---

## Performance Metrics & Goals

### Launch Time
- **Current**: 1.5-2.0 seconds
- **Target**: < 1.0 seconds
- **Measurement**: Time from app icon tap to feed visible

### Tab Switching
- **Current**: 200-400ms
- **Target**: < 100ms
- **Measurement**: Time from tap to content visible

### Feed Scrolling
- **Current**: 45-55fps with stutters
- **Target**: 60fps constant
- **Measurement**: Instruments Time Profiler

### View Transitions
- **Current**: 300-500ms
- **Target**: < 200ms
- **Measurement**: Time from button tap to sheet fully visible

### Memory Usage
- **Current**: 180-250MB peak
- **Target**: < 150MB peak
- **Measurement**: Instruments Allocations

### Network Requests
- **Current**: 200-300 Firestore reads/min
- **Target**: < 150 reads/min
- **Measurement**: Firebase Console

---

## Testing Checklist

### Manual Testing
- [ ] App launches in < 1 second on iPhone SE
- [ ] Tab switching feels instant (< 100ms)
- [ ] Feed scrolls at 60fps with 100+ posts
- [ ] Images appear instantly from cache
- [ ] No visual lag when tapping like/comment
- [ ] Sheets open smoothly < 200ms
- [ ] No jank during rapid scrolling
- [ ] No lag when navigating back

### Instruments Testing
- [ ] Time Profiler: No hot paths on main thread
- [ ] Allocations: No memory leaks
- [ ] Leaks: Zero leaks detected
- [ ] Core Animation: 60fps in all scrolls
- [ ] Network: Reduced Firebase reads by 40%

### Device Testing
- [ ] iPhone SE (2020) - Baseline
- [ ] iPhone 13 Pro - Mid-tier
- [ ] iPhone 15 Pro Max - High-end
- [ ] Test on iOS 15, 16, 17

---

## Success Metrics

**Before Optimization:**
- Launch: 1.5-2.0s
- Tab switch: 200-400ms
- Feed scroll: 45-55fps
- View transitions: 300-500ms
- Memory: 180-250MB
- Network: 200-300 reads/min

**After Optimization (Target):**
- Launch: < 1.0s (50% faster)
- Tab switch: < 100ms (75% faster)
- Feed scroll: 60fps (100% smooth)
- View transitions: < 200ms (50% faster)
- Memory: < 150MB (40% reduction)
- Network: < 150 reads/min (40% reduction)

**User-Facing Improvements:**
- App feels 2x faster
- Scrolling is buttery smooth
- No lag or stuttering
- Instant tab switching
- Smooth animations everywhere
- Responsive to every tap

---

## References

- Time Profiler: Xcode → Instruments → Time Profiler
- Memory Profiler: Xcode → Instruments → Allocations
- Leak Detection: Xcode → Instruments → Leaks
- FPS Measurement: Xcode → Debug → View Debugging → Rendering
- Network Profiling: Firebase Console → Usage

---

**END OF PERFORMANCE OPTIMIZATION PLAN**
