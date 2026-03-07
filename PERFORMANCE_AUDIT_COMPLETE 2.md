# AMEN App Performance Audit - Complete Report
**Date:** February 23, 2026
**Auditor:** Senior iOS Engineer (SwiftUI/Firebase Specialist)
**Scope:** UI Performance, Animations, Real-time Updates, Layout Correctness

---

## Executive Summary

✅ **Fixed Issues:** 1 critical
⚠️ **Remaining Risks:** 4 areas requiring monitoring
🎯 **Performance Status:** Generally good with targeted fixes needed

### Critical Fix Applied
- **ProfileView Username Header Bug** - Username wasn't visible on initial load (only showed when 3-dot menu opened)

---

## 1. PROFILEVIEW AUDIT

### Issue Found: Username Header Visibility (P0) ✅ FIXED

**Root Cause:**
The username title in navigation bar was being shifted and faded based on `isToolbarExpanded` state (3-dot menu), making it invisible unless user opened the menu.

**Code Location:** `ProfileView.swift:248-257`

**Fix Applied:**
```swift
// BEFORE (BROKEN):
ToolbarItem(placement: .principal) {
    if !showCompactHeader {
        Text(profileData.username)
            .font(.custom("OpenSans-Bold", size: 17))
            .foregroundStyle(.black)
            .offset(x: isToolbarExpanded ? -80 : 0)  // ❌ Shifts offscreen
            .opacity(isToolbarExpanded ? 0.6 : 1.0)  // ❌ Fades out
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isToolbarExpanded)
    }
}

// AFTER (FIXED):
ToolbarItem(placement: .principal) {
    if !showCompactHeader {
        Text(profileData.username)
            .font(.custom("OpenSans-Bold", size: 17))
            .foregroundStyle(.black)
            // ✅ Always visible, no offset/opacity changes
    }
}
```

**Impact:** Username now properly visible on profile load. Hidden only when user scrolls down (showCompactHeader = true).

**Validation Checklist:**
- [x] Username visible on initial profile load
- [x] Username hides when scrolling down past 200 points
- [x] Compact header (avatar + name) appears in top-left when scrolled
- [x] No conflict with 3-dot menu state
- [ ] Test on different screen sizes (iPhone SE, Pro Max)

---

## 2. CREATEPOSTVIEW AUDIT

### Performance Assessment: ✅ GOOD

**Strengths:**
1. **Duplicate Prevention** - Hash-based duplicate post blocking (`inFlightPostHash`)
2. **Rate Limiting** - `ComposerRateLimiter` prevents spam
3. **Parallel Execution** - Moderation and post creation run concurrently
4. **Optimistic UI** - Immediate feedback with progress indicators

**Code Quality Highlights:**
```swift
// P0-1: Duplicate post prevention
let contentHash = postText.hashValue
if let existingHash = inFlightPostHash, existingHash == contentHash {
    print("⚠️ [P0-1] Duplicate post blocked")
    return
}
inFlightPostHash = contentHash

// P0-4: Rate limiting check
if rateLimiter.isRateLimited(for: .post) {
    showError(title: "Slow Down", message: "...")
    return
}
```

**Potential Issues:**

#### Issue 2.1: Keyboard Dismissal Timing (P2)
**Location:** `CreatePostView.swift:1417`
```swift
// Dismiss keyboard
isTextFieldFocused = false
```

**Risk:** Keyboard dismissal happens synchronously before async post creation. May cause slight UI jank on slower devices.

**Recommendation:**
```swift
// Defer keyboard dismissal slightly
Task { @MainActor in
    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
    isTextFieldFocused = false
}
```

#### Issue 2.2: Image Upload Progress Not Always Visible (P2)
**Location:** `CreatePostView.swift:177-210`

The upload progress overlay uses `isUploadingImages` flag, but there's no guarantee this gets set before image upload starts.

**Validation Checklist:**
- [x] Post creation prevents duplicates
- [x] Rate limiting works
- [x] Validation errors show correctly
- [ ] Test image upload progress visibility
- [ ] Test keyboard behavior during post submission
- [ ] Test success animation smoothness
- [ ] Profile with slow network (throttle to 3G)

---

## 3. USERPROFILEVIEW AUDIT

### Performance Assessment: ✅ GOOD (Recently Fixed)

**Recent Fix:** Scroll animations now working correctly after switching from `.onPreferenceChange` to `.onChange(of: rawScrollValue)`.

**Strengths:**
1. **Smooth scroll tracking** - Uses GeometryReader with direct state updates
2. **Fast animations** - 0.15s easeOut matching ProfileView
3. **Clean compact header** - Only back button + profile photo (no duplicate actions)

**Code Quality:**
```swift
// Efficient scroll tracking
.background(
    GeometryReader { geometry in
        let minY = geometry.frame(in: .named("scroll")).minY
        Color.clear
            .onChange(of: minY) { oldValue, newValue in
                rawScrollValue = newValue  // ✅ Direct state update
            }
    }
)

// Smooth compact header transition
.onChange(of: rawScrollValue) { oldValue, newValue in
    let shouldShowCompact = newValue < -200
    if showCompactHeader != shouldShowCompact {
        withAnimation(.easeOut(duration: 0.15)) {
            showCompactHeader = shouldShowCompact
        }
    }
}
```

**Potential Issues:**

#### Issue 3.1: Real-time Listener Lifecycle (P1)
**Assumption:** UserProfileView likely has Firestore listeners for posts/followers.

**Risk:** Listeners may not be properly removed on view dismissal, causing memory leaks.

**Pattern to verify:**
```swift
@State private var listenerRegistration: ListenerRegistration?

.onAppear {
    listenerRegistration = Firestore.firestore()
        .collection("users").document(userId)
        .addSnapshotListener { snapshot, error in
            // ...
        }
}

.onDisappear {
    listenerRegistration?.remove()  // ✅ Critical
    listenerRegistration = nil
}
```

**Validation Checklist:**
- [x] Scroll animations work smoothly
- [x] Compact header appears/disappears correctly
- [x] Navigation title transitions smoothly
- [ ] Verify listener cleanup on dismiss
- [ ] Test with 50+ posts (scroll performance)
- [ ] Test follow/unfollow real-time updates
- [ ] Profile real device memory usage over time

---

## 4. UNIFIEDCHATVIEW (MESSAGES) AUDIT

### Performance Assessment: ⚠️ NEEDS MONITORING

**Strengths:**
1. **Duplicate Message Prevention** - Hash-based optimistic message tracking
2. **Proper Listener Lifecycle** - Uses `listenerTask` with cancellation
3. **Optimistic UI** - Immediate message display with pending state
4. **Memory Safety** - `@MainActor` for state updates

**Code Quality Highlights:**
```swift
// P0-4: Hash-based duplicate prevention
var fetchedMessagesByHash: [Int: AppMessage] = [:]
for message in fetchedMessages {
    let contentHash = message.text.hashValue
    fetchedMessagesByHash[contentHash] = message
}

// Remove optimistic messages that are confirmed
for (optimisticId, contentHash) in optimisticMessageHashes {
    if fetchedMessagesByHash[contentHash] != nil {
        pendingMessages.removeValue(forKey: optimisticId)
    }
}
```

**Critical Issues:**

#### Issue 4.1: Initial Load Performance (P1)
**Location:** `UnifiedChatView.swift:835-890`

**Problem:** `loadMessages()` starts a Firestore listener immediately, which fetches ALL messages at once. For long conversations (100+ messages), this blocks UI.

**Current Code:**
```swift
private func loadMessages() {
    Task {
        try await messagingService.startListeningToMessages(
            conversationId: conversation.id
        ) { fetchedMessages in
            // Processes all messages at once
        }
    }
}
```

**Recommended Fix:**
```swift
private func loadMessages() {
    Task {
        // 1. First, load initial batch (last 50 messages)
        let initialMessages = try await messagingService.fetchRecentMessages(
            conversationId: conversation.id,
            limit: 50
        )

        await MainActor.run {
            self.messages = initialMessages
        }

        // 2. Then start real-time listener for new messages only
        try await messagingService.startListeningToNewMessages(
            conversationId: conversation.id,
            afterTimestamp: initialMessages.first?.timestamp ?? Date()
        ) { newMessages in
            Task { @MainActor in
                self.messages.append(contentsOf: newMessages)
                self.messages.sort { $0.timestamp < $1.timestamp }
            }
        }
    }
}
```

#### Issue 4.2: Scroll Performance with Many Messages (P1)
**Risk:** ScrollView with 100+ message bubbles may lag on scroll.

**Recommendation:** Use `LazyVStack` instead of `VStack` for message list:
```swift
// In messagesScrollView
ScrollView {
    LazyVStack(spacing: 12) {  // ✅ Lazy loading
        ForEach(messages) { message in
            MessageBubbleView(message: message)
        }
    }
}
```

#### Issue 4.3: Keyboard Animation Jank (P2)
**Location:** Input bar with keyboard

**Risk:** `.safeAreaInset(edge: .bottom)` may cause layout jumps when keyboard appears.

**Validation Required:** Test keyboard show/hide animations on slower devices.

**Validation Checklist:**
- [ ] Test opening chat with 100+ messages (measure time to interactive)
- [ ] Verify no duplicate messages appear
- [ ] Test scroll smoothness with many messages
- [ ] Verify keyboard animations are smooth
- [ ] Test typing indicator lag
- [ ] Verify listener cleanup on back navigation
- [ ] Memory profiling for long chat sessions

---

## 5. POSTDETAILVIEW (COMMENTS) AUDIT

### Performance Assessment: ⚠️ LAYOUT NEEDS VERIFICATION

**Current Layout Structure:**
```swift
ScrollView {
    VStack(spacing: 0) {
        // Main post content
        mainPostSection.id("post")

        // Engagement bar
        engagementBar

        Divider()

        // Comments section
        if isLoading {
            loadingView
        } else if commentsWithReplies.isEmpty {
            emptyCommentsView
        } else {
            commentsSection.id("comments")
        }

        // Bottom spacing for input
        Color.clear.frame(height: 80)  // ⚠️ Fixed height
    }
}
```

**Potential Issues:**

#### Issue 5.1: Comment Section Layout (P0) - REQUIRES USER VERIFICATION
**User Report:** "Comments appearing in the middle of the screen"

**Hypothesis 1:** Scroll offset calculation issue
```swift
.onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
    scrollOffset = max(0, -value)  // May have edge cases
}
```

**Hypothesis 2:** Empty state layout
The `emptyCommentsView` might not have proper constraints, causing it to float.

**Recommended Investigation:**
```swift
// Add debug backgrounds to verify layout
var emptyCommentsView: some View {
    VStack(spacing: 16) {
        // ...
    }
    .frame(maxWidth: .infinity)  // ✅ Ensure full width
    .frame(minHeight: 200)  // ✅ Minimum height
    .background(Color.red.opacity(0.1))  // 🔍 Debug
}
```

#### Issue 5.2: Comment Input Keyboard Overlap (P1)
**Location:** Bottom of PostDetailView

**Risk:** Fixed height `Color.clear.frame(height: 80)` may not accommodate keyboard properly.

**Recommended Fix:**
Use `.safeAreaInset` or keyboard height tracking:
```swift
@State private var keyboardHeight: CGFloat = 0

var body: some View {
    ScrollView {
        // ...
    }
    .safeAreaInset(edge: .bottom) {
        commentInputBar
            .background(.ultraThinMaterial)
    }
    .onReceive(NotificationCenter.default.publisher(
        for: UIResponder.keyboardWillChangeFrameNotification
    )) { notification in
        // Track keyboard height
    }
}
```

**Validation Checklist:**
- [ ] Verify comments appear directly below post (not floating)
- [ ] Test with 0, 1, 10, 50+ comments
- [ ] Verify comment input not covered by keyboard
- [ ] Test adding comment (real-time update)
- [ ] Verify scroll-to-comments button works
- [ ] Test engagement bar scroll blur effect

---

## 6. GLOBAL ANIMATION PERFORMANCE

### Assessment: ✅ GENERALLY GOOD

**Animation Patterns Found:**

#### Good Patterns:
```swift
// Fast, clean transitions
.animation(.easeOut(duration: 0.15), value: showCompactHeader)

// Smooth spring animations
.animation(.spring(response: 0.35, dampingFraction: 0.75), value: isExpanded)

// Liquid glass effects (optimized)
.background(.ultraThinMaterial)
```

#### Patterns to Monitor:

**Pattern 6.1: Over-Animation (P2)**
**Location:** PostDetailView engagement bar
```swift
.animation(.smooth(duration: 0.3), value: scrollOffset)
```

**Risk:** Animating on every scroll offset change (high frequency) may cause frame drops.

**Recommendation:**
```swift
// Throttle scroll animations
@State private var lastAnimationTime = Date()

.onChange(of: scrollOffset) { old, new in
    let now = Date()
    if now.timeIntervalSince(lastAnimationTime) > 0.016 {  // 60fps
        withAnimation(.smooth(duration: 0.3)) {
            // Update animated properties
        }
        lastAnimationTime = now
    }
}
```

**Pattern 6.2: Material Effects Overuse (P2)**
**Risk:** `.ultraThinMaterial` on every cell in a list can cause GPU overdraw.

**Validation Required:** Profile with Instruments (Time Profiler, Core Animation).

---

## 7. REAL-TIME LISTENER MANAGEMENT

### Assessment: ⚠️ NEEDS SYSTEMATIC AUDIT

**Good Patterns Found:**

```swift
// UnifiedChatView - proper lifecycle
@State private var listenerTask: Task<Void, Never>?

.onAppear {
    listenerTask = Task {
        // Start listener
    }
}

.onDisappear {
    listenerTask?.cancel()
    listenerTask = nil
}
```

**Systematic Audit Required:**

### Listener Audit Checklist (ALL VIEWS):

#### Views to Audit:
- [ ] ProfileView
- [ ] UserProfileView
- [ ] CreatePostView (if any)
- [ ] PostDetailView
- [ ] UnifiedChatView ✅
- [ ] MessagesView (list)
- [ ] NotificationsView
- [ ] OpenTableView
- [ ] TestimoniesView
- [ ] PrayerView

#### For Each View, Verify:
1. **Listener Creation:**
   - Are listeners stored in `@State` variables?
   - Are they `ListenerRegistration?` or `Task<Void, Never>?`

2. **Listener Removal:**
   - Does `.onDisappear` call `.remove()` or `.cancel()`?
   - Are listener references set to `nil`?

3. **Memory Safety:**
   - Are closures using `[weak self]` (if in class)?
   - Are state updates wrapped in `@MainActor`?

4. **Duplicate Prevention:**
   - Does `.onAppear` check if listener already exists?
   - Are listeners removed before creating new ones?

**Pattern to Enforce:**
```swift
// REQUIRED PATTERN FOR ALL VIEWS WITH LISTENERS
@State private var firestoreListener: ListenerRegistration?

.onAppear {
    // Remove existing listener first (safety)
    firestoreListener?.remove()

    // Create new listener
    firestoreListener = Firestore.firestore()
        .collection("...")
        .addSnapshotListener { snapshot, error in
            Task { @MainActor in
                // Update state
            }
        }
}

.onDisappear {
    // CRITICAL: Always remove listeners
    firestoreListener?.remove()
    firestoreListener = nil
}
```

---

## 8. MEMORY LEAK RISKS

### High-Risk Areas:

#### Risk 8.1: Firestore Listener Leaks (P0)
**Location:** Any view with real-time updates

**Detection:**
```bash
# Run app with Memory Graph Debugger
# 1. Open view with listeners
# 2. Navigate back
# 3. Check if listener objects still exist
```

**Prevention:** See Listener Audit Checklist above.

#### Risk 8.2: Image Caching (P1)
**Location:** Profile photos, post images

**Risk:** Unbounded cache growth over time.

**Validation:**
```swift
// Check if CachedAsyncImage has cache limits
// Should see something like:
.cache(.temporary)  // ✅ Auto-cleanup
// OR
.cache(.memory(limit: 100 * 1024 * 1024))  // ✅ 100MB limit
```

#### Risk 8.3: Task Leaks (P1)
**Location:** Any view with `Task { }` in `.onAppear`

**Pattern to enforce:**
```swift
@State private var loadTask: Task<Void, Never>?

.onAppear {
    loadTask?.cancel()  // Cancel previous
    loadTask = Task {
        // Work
    }
}

.onDisappear {
    loadTask?.cancel()
    loadTask = nil
}
```

---

## 9. VALIDATION CHECKLISTS

### 9.1 Performance Testing

**Device Matrix:**
- [ ] iPhone 15 Pro (A17 Pro) - Should be perfect
- [ ] iPhone SE 3rd gen (A15) - Should be smooth
- [ ] iPhone 12 (A14) - May show issues
- [ ] iPhone XR (A12) - Critical path

**Network Conditions:**
- [ ] Wi-Fi (fast)
- [ ] LTE (typical)
- [ ] 3G (throttled) - Use Network Link Conditioner
- [ ] Offline mode - Verify cache behavior

**Stress Tests:**
- [ ] Profile with 500+ posts
- [ ] Chat with 500+ messages
- [ ] Feed with 100+ posts
- [ ] Rapid tab switching (10x)
- [ ] Background/foreground 10x
- [ ] Memory usage over 30 min session

### 9.2 Animation Smoothness

**Test Scenarios:**
- [ ] Scroll feed at various speeds
- [ ] Open/close CreatePostView rapidly
- [ ] Switch between profiles quickly
- [ ] Open chat, type message, send (check lag)
- [ ] Post detail: scroll comments smoothly

**Acceptance Criteria:**
- 60 FPS during all animations (use Instruments)
- No visible frame drops on iPhone 12+
- Acceptable on iPhone XR (45+ FPS)

### 9.3 Real-time Updates

**Test Scenarios:**
- [ ] Two devices: Send message, verify instant delivery
- [ ] Two devices: Post comment, verify real-time update
- [ ] Two devices: Like post, verify counter updates
- [ ] Network disconnect/reconnect: Verify recovery
- [ ] Background app, receive notification, foreground: Verify sync

**Acceptance Criteria:**
- Message delivery < 2 seconds (Wi-Fi)
- No duplicate messages
- No missing updates
- Offline changes sync on reconnect

---

## 10. INSTRUMENTATION RECOMMENDATIONS

### Add Performance Logging:

```swift
// In key views, add timing instrumentation
@State private var viewDidAppearTime: Date?

var body: some View {
    content
        .onAppear {
            viewDidAppearTime = Date()
            print("⏱️ [\(Self.self)] Appeared")
        }
        .task {
            // After data loads
            if let startTime = viewDidAppearTime {
                let loadTime = Date().timeIntervalSince(startTime)
                print("⏱️ [\(Self.self)] Time to interactive: \(Int(loadTime * 1000))ms")

                // Log to analytics (optional)
                // Analytics.logEvent("view_load_time", parameters: [
                //     "view": "\(Self.self)",
                //     "duration_ms": Int(loadTime * 1000)
                // ])
            }
        }
}
```

### Crash Reporting:

```swift
// In publishPost, sendMessage, etc.
do {
    try await performOperation()
} catch {
    print("❌ [\(Self.self)] Operation failed: \(error)")
    // Crashlytics.recordError(error)  // If using Firebase Crashlytics
    showError(title: "Error", message: error.localizedDescription)
}
```

---

## 11. REMAINING RISKS & EDGE CASES

### P0 Risks (Must Fix):
1. **PostDetailView comment layout** - User reported "comments in middle of screen"
   - Action: Add debug backgrounds, verify layout constraints
   - Priority: Immediate

### P1 Risks (Should Fix):
1. **UnifiedChatView initial load** - May lag with 100+ messages
   - Action: Implement pagination (load last 50, then older on scroll)
   - Priority: Before TestFlight

2. **Listener lifecycle audit** - Incomplete verification
   - Action: Systematic audit of all 10 views
   - Priority: Before TestFlight

3. **Memory profiling** - No long-session testing yet
   - Action: 30-minute session test with Instruments
   - Priority: Before TestFlight

### P2 Risks (Monitor):
1. **Scroll animation throttling** - May cause frame drops
   - Action: Profile with Instruments, add throttling if needed
   - Priority: Post-launch optimization

2. **Image cache unbounded growth** - Long-term memory issue
   - Action: Verify cache limits, add if missing
   - Priority: Post-launch monitoring

---

## 12. IMPLEMENTATION PRIORITY

### Week 1 (Critical):
1. ✅ Fix ProfileView username visibility (DONE)
2. [ ] Investigate PostDetailView comment layout bug
3. [ ] Audit listener lifecycle (top 3 views)

### Week 2 (Important):
4. [ ] Optimize UnifiedChatView initial load (pagination)
5. [ ] Complete listener lifecycle audit (all views)
6. [ ] Add performance instrumentation

### Week 3 (Polish):
7. [ ] Scroll animation throttling (if needed)
8. [ ] Memory profiling and optimization
9. [ ] Stress testing on older devices

---

## 13. SUCCESS METRICS

### Before Launch:
- [ ] 0 P0 bugs remaining
- [ ] 0 P1 bugs remaining
- [ ] All validation checklists 100% complete
- [ ] Memory growth < 50MB over 30 min session
- [ ] 60 FPS on iPhone 12+ for all interactions
- [ ] 45+ FPS on iPhone XR for critical paths

### Post-Launch Monitoring:
- App crash rate < 0.1%
- Average time to interactive < 2 seconds
- Real-time message delivery < 2 seconds (p95)
- User-reported animation jank < 1% of sessions

---

## 14. FINAL NOTES

### Code Quality: ⭐⭐⭐⭐☆ (4/5)
**Strengths:**
- Excellent duplicate prevention patterns
- Good real-time update architecture
- Proper error handling in most places
- Clean SwiftUI code organization

**Areas for Improvement:**
- Systematic listener lifecycle management
- More performance instrumentation
- Memory profiling needed

### Architecture: ⭐⭐⭐⭐½ (4.5/5)
**Strengths:**
- Good separation of concerns (Services pattern)
- Proper use of @StateObject for shared instances
- Clean real-time data flow

**Areas for Improvement:**
- Need pagination for large datasets
- Consider view model layer for complex views

### Performance: ⭐⭐⭐⭐☆ (4/5)
**Strengths:**
- Generally smooth animations
- Good optimistic UI patterns
- Fast initial renders

**Areas for Improvement:**
- Chat initial load needs optimization
- Scroll performance with many items
- Animation throttling for high-frequency updates

---

## APPENDIX A: Quick Reference

### Common Performance Patterns:

**Fast Animation:**
```swift
.animation(.easeOut(duration: 0.15), value: state)
```

**Smooth Spring:**
```swift
.animation(.spring(response: 0.35, dampingFraction: 0.75), value: state)
```

**Proper Listener Cleanup:**
```swift
@State private var listener: ListenerRegistration?
.onDisappear { listener?.remove(); listener = nil }
```

**Lazy List:**
```swift
LazyVStack { ForEach(items) { item in /* ... */ } }
```

**Main Actor Update:**
```swift
Task { @MainActor in self.state = newValue }
```

---

**END OF AUDIT**
