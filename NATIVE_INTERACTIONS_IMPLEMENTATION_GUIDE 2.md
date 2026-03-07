# AMEN Native Interactions Implementation Guide

## Overview
This guide provides a complete implementation of Instagram/Threads-style native interactions for AMEN, focusing on polish, speed, and accessibility without changing the core visual design.

---

## ✅ Components Implemented

### 1. **DeepLinkRouter.swift** - Central Navigation System
**Purpose**: Handle deep links, push notifications, and in-app navigation

**Features**:
- Parse custom URLs (`amen://post/{id}`, `amen://user/{userId}`, etc.)
- Navigate to exact entities with context (highlighted comments, messages)
- Generate shareable deep links
- Maintain navigation stack state

**Integration**:
```swift
// In AMENAPPApp.swift or ContentView.swift
import SwiftUI

struct AMENAPPApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .handleDeepLinks()  // Add this modifier
        }
    }
}
```

**Usage Examples**:
```swift
// Navigate programmatically
DeepLinkRouter.shared.navigate(to: .post(id: postId, highlightCommentId: commentId))

// Generate share link
let url = DeepLinkRouter.shared.generateURL(for: .userProfile(userId: userId))

// Handle push notification
if let route = DeepLinkRouter.shared.parse(url: notificationURL) {
    DeepLinkRouter.shared.navigate(to: route)
}
```

---

### 2. **InteractionHelpers.swift** - Reusable UI Components

#### A. Haptic Feedback System
**Use sparingly** - only for key interactions:
```swift
HapticHelper.light()     // Swipe actions, minor interactions
HapticHelper.medium()    // Button taps, selections
HapticHelper.heavy()     // Delete, major actions
HapticHelper.success()   // Successful operations
HapticHelper.selection() // Picker/segment changes
```

#### B. Toast Manager
**Purpose**: Show temporary feedback messages with undo support

**Usage**:
```swift
// Simple success toast
ToastManager.shared.success("Post saved")

// Toast with undo action
ToastManager.shared.showWithUndo("Post deleted") {
    // Undo handler
    await postsManager.restorePost(postId)
}

// Add to view hierarchy (once, at root level)
ContentView()
    .withToasts()
```

#### C. Highlight Manager
**Purpose**: Highlight entities from deep links (e.g., specific comment)

**Usage**:
```swift
// In Comment view
CommentRow(comment: comment)
    .highlightable(id: comment.id)

// Trigger highlight when navigating from notification
HighlightManager.shared.highlight(commentId)
```

#### D. Skeleton Loading
**Purpose**: Show loading state without empty screens

**Usage**:
```swift
if isLoading && posts.isEmpty {
    SkeletonLoadingView()
} else {
    // Real content
}
```

---

### 3. **EnhancedPostCard.swift** - Feed Interactions

**Features Implemented**:
✅ **Double-tap to react** - Instagram-style like animation
✅ **Long-press context menu** - Save, Share, Copy Link, Mute, Report
✅ **Swipe actions**:
  - Swipe right: Save/Unsave
  - Swipe left: Hide post
✅ **Haptic feedback** on all interactions
✅ **Toast notifications** with undo support
✅ **Deep link generation** for sharing

**Integration**:
Replace existing PostCard with EnhancedPostCard:
```swift
// Before
PostCard(post: post) {
    // Navigate to detail
}

// After
EnhancedPostCard(post: post) {
    // Navigate to detail
}
```

**Gesture Behaviors**:
- **Single tap**: Opens post detail (with 300ms delay to detect double-tap)
- **Double-tap**: Toggles primary reaction (lightbulb) with animation
- **Long-press**: Shows context menu
- **Swipe right**: Quick save
- **Swipe left**: Hide post

---

### 4. **EnhancedCommentRow.swift** - Comment Interactions

**Features Implemented**:
✅ **Swipe left to reply** - Threads-style quick reply
✅ **Swipe right to delete/report** - Context-aware (own vs others)
✅ **Long-press context menu** - Copy, Restrict, Block, Report
✅ **Real-time comment insertion** - Smooth animation for new comments
✅ **Highlight support** - Deep-linked comments pulse briefly

**Integration**:
```swift
EnhancedCommentSection(
    postId: post.id,
    replyingTo: $replyingToComment
)
```

**Real-time Updates**:
When a comment is posted, broadcast notification:
```swift
NotificationCenter.default.post(
    name: .commentAdded,
    object: nil,
    userInfo: ["commentId": commentId, "postId": postId]
)
```

---

### 5. **EnhancedNotificationsView.swift** - Notifications

**Features Implemented**:
✅ **Category filters** - All, Mentions, Replies, Reactions, Follows, Prayers
✅ **Pull to refresh** - Fast, native iOS refresh
✅ **Swipe actions**:
  - Swipe right: Clear notification
  - Swipe left: Mute category
✅ **Grouped by date** - Today, Yesterday, This Week, etc.
✅ **Clear all with undo** - Bulk actions with safety
✅ **Deep link navigation** - Tap notification → exact destination

**Integration**:
Replace existing NotificationsView:
```swift
// In ContentView tabs
EnhancedNotificationsView()
    .tabItem {
        Label("Notifications", systemImage: "bell")
    }
```

**Notification Model**:
```swift
struct NotificationItem: Identifiable {
    let id: String
    let type: NotificationType  // mention, reply, reaction, follow, etc.
    let fromUserId: String?
    let fromUsername: String
    let title: String
    let message: String?
    let entityId: String?        // postId, userId, etc.
    let commentId: String?       // For comment mentions/replies
    let timestamp: Date
    var isRead: Bool
}
```

---

## 📱 Integration Checklist

### Step 1: Add Components to Project
- [x] DeepLinkRouter.swift
- [x] InteractionHelpers.swift
- [x] EnhancedPostCard.swift
- [x] EnhancedCommentRow.swift
- [x] EnhancedNotificationsView.swift

### Step 2: Enable Deep Links
```swift
// AMENAPPApp.swift
import SwiftUI

@main
struct AMENAPPApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .handleDeepLinks()
                .withToasts()
        }
    }
}
```

### Step 3: Update ContentView Navigation
```swift
@ObservedObject private var deepLinkRouter = DeepLinkRouter.shared

var body: some View {
    TabView(selection: $deepLinkRouter.selectedTab) {
        // Tab 0: Home/Feed
        NavigationStack(path: $deepLinkRouter.navigationPath) {
            FeedView()
                .navigationDestination(for: DeepLinkRouter.DeepLinkDestination.self) { destination in
                    destinationView(for: destination)
                }
        }
        .tabItem { Label("Home", systemImage: "house") }
        .tag(0)
        
        // ... other tabs
    }
    .onChange(of: deepLinkRouter.activeRoute) { _, newRoute in
        if let route = newRoute {
            handleDeepLink(route)
        }
    }
}

@ViewBuilder
func destinationView(for destination: DeepLinkRouter.DeepLinkDestination) -> some View {
    switch destination {
    case .post(let id):
        PostDetailView(postId: id)
    case .userProfile(let userId):
        UserProfileView(userId: userId)
    case .church(let churchId):
        ChurchProfileView(churchId: churchId)
    case .conversation(let conversationId):
        ConversationView(conversationId: conversationId)
    case .settings:
        SettingsView()
    }
}
```

### Step 4: Integrate Enhanced Components

#### Replace PostCard
```swift
// In FeedView/HomeView
ForEach(posts) { post in
    EnhancedPostCard(post: post) {
        // Navigate to detail
        deepLinkRouter.push(.post(id: post.id))
    }
}
```

#### Replace Comment Views
```swift
// In PostDetailView
EnhancedCommentSection(
    postId: post.id,
    replyingTo: $replyingToComment
)
```

#### Replace NotificationsView
```swift
// In ContentView tabs
EnhancedNotificationsView()
```

### Step 5: Configure Push Notifications

#### Update Notification Payload
```json
{
  "aps": {
    "alert": {
      "title": "Jordan mentioned you",
      "body": "\"Check out this verse...\""
    },
    "badge": 1,
    "sound": "default",
    "category": "MENTION"
  },
  "deepLink": "amen://post/abc123?comment=def456",
  "entityId": "abc123",
  "commentId": "def456",
  "type": "mention"
}
```

#### Handle Incoming Notifications
```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
) {
    let userInfo = response.notification.request.content.userInfo
    
    if let deepLinkString = userInfo["deepLink"] as? String {
        DeepLinkRouter.shared.navigate(to: deepLinkString)
    }
    
    completionHandler()
}
```

---

## 🎯 Feature Behaviors

### Feed (OpenTable)
| Gesture | Action | Haptic |
|---------|--------|--------|
| Single tap | Open post detail | None |
| Double tap | Toggle reaction + animation | Medium |
| Long press | Show context menu | Light |
| Swipe right | Save/Unsave | Light |
| Swipe left | Hide post | Light |
| Pull down | Refresh feed | None (native) |

### Comments
| Gesture | Action | Haptic |
|---------|--------|--------|
| Single tap | (none) | None |
| Swipe left | Reply | Light |
| Swipe right (own) | Delete | None (confirmation) |
| Swipe right (other) | Report | None |
| Long press | Context menu | Light |

### Notifications
| Gesture | Action | Haptic |
|---------|--------|--------|
| Tap notification | Navigate + mark read | Light |
| Swipe right | Clear | Light |
| Swipe left | Mute category | Medium |
| Pull down | Refresh | None (native) |

---

## 🧪 Manual QA Checklist

### 1. Deep Links
- [ ] Open `amen://post/{id}` from Safari → lands on post detail
- [ ] Open `amen://post/{id}?comment={commentId}` → highlights comment
- [ ] Tap push notification → navigates to correct screen
- [ ] Share post → copy link → paste in Safari → opens app
- [ ] Back navigation works correctly after deep link

### 2. Feed Interactions
- [ ] Double-tap post → reaction animation plays, reaction toggles
- [ ] Single tap (after double-tap) → opens post detail
- [ ] Long-press → context menu appears
- [ ] Swipe right → "Saved" toast appears with undo
- [ ] Swipe left → "Hidden" toast appears with undo
- [ ] Pull to refresh → shows loading, fetches new posts
- [ ] No duplicate reactions when tapping rapidly

### 3. Comments
- [ ] Swipe left on comment → reply button appears
- [ ] Swipe right on own comment → delete confirmation
- [ ] Swipe right on other's comment → report
- [ ] New comment appears at top with highlight
- [ ] Highlight fades after 2 seconds
- [ ] Long-press → copy works
- [ ] Keyboard dismisses when tapping outside

### 4. Notifications
- [ ] Pull to refresh works
- [ ] Category filters update list correctly
- [ ] Swipe right → notification clears with undo
- [ ] Swipe left → "Muted {category}" toast
- [ ] Clear all → confirmation dialog → undo works
- [ ] Tap notification → navigates to entity → highlights target
- [ ] Unread indicator shows/hides correctly

### 5. Gestures & Performance
- [ ] No scroll jank on feed
- [ ] No gesture conflicts (scroll vs double-tap)
- [ ] Haptics fire correctly (not too frequent)
- [ ] Toasts auto-dismiss after 3 seconds
- [ ] Undo actions work correctly
- [ ] Navigation animations are smooth
- [ ] Lists use stable IDs (no jumping)

### 6. Accessibility
- [ ] VoiceOver reads all interactive elements
- [ ] Reduce Motion respected (no double-tap animation)
- [ ] Dynamic Type scales correctly
- [ ] Hit targets are >= 44x44 points
- [ ] Color contrast meets WCAG standards

### 7. Edge Cases
- [ ] Rapid taps don't cause duplicate actions
- [ ] Background/foreground transitions work
- [ ] Poor network doesn't crash app
- [ ] Empty states show correctly
- [ ] Deep links work when app is terminated
- [ ] Deep links work when app is backgrounded

---

## 🚀 Performance Guidelines

### Avoid These Anti-Patterns
❌ Heavy animations on every cell
❌ Duplicate Firestore listeners
❌ Expensive work in `body`
❌ Force-unwrapping in gesture handlers
❌ Missing loading/error states

### Best Practices
✅ Use `.task` for async loading
✅ Use stable `id` for ForEach
✅ Cancel tasks in `.onDisappear`
✅ Debounce rapid user actions
✅ Show skeleton UI during initial load
✅ Cache computed properties
✅ Use `LazyVStack` for long lists

---

## 📝 Code Snippets

### Scroll to Top on Tab Reselect
```swift
// In FeedView
@State private var scrollToTopTrigger = 0

var body: some View {
    ScrollViewReader { proxy in
        ScrollView {
            LazyVStack {
                ForEach(posts) { post in
                    EnhancedPostCard(post: post)
                        .id(post.id)
                }
            }
            .id("top")
        }
        .onChange(of: scrollToTopTrigger) { _, _ in
            withAnimation {
                proxy.scrollTo("top", anchor: .top)
            }
        }
    }
    .onReceive(NotificationCenter.default.publisher(for: ScrollToTopHelper.scrollToTopNotification)) { notification in
        if let tab = notification.userInfo?["tab"] as? Int, tab == 0 {
            scrollToTopTrigger += 1
        }
    }
}

// In ContentView - detect tab reselection
.onChange(of: selectedTab) { oldValue, newValue in
    if oldValue == newValue {
        ScrollToTopHelper.scrollToTop(tab: newValue)
    }
}
```

### Hide Tab Bar on Scroll
```swift
// In FeedView
@State private var lastScrollOffset: CGFloat = 0
@State private var showTabBar = true

ScrollView {
    GeometryReader { geometry in
        Color.clear.preference(
            key: ScrollOffsetPreferenceKey.self,
            value: geometry.frame(in: .named("scroll")).minY
        )
    }
    .frame(height: 0)
    
    // Content...
}
.coordinateSpace(name: "scroll")
.onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
    let delta = offset - lastScrollOffset
    lastScrollOffset = offset
    
    // Hide tab bar when scrolling down, show when scrolling up
    withAnimation(.easeInOut(duration: 0.2)) {
        if delta < -10 && showTabBar {
            showTabBar = false
        } else if delta > 10 && !showTabBar {
            showTabBar = true
        }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
```

---

## 🎨 Accessibility Considerations

### Reduce Motion
```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// In double-tap animation
if !reduceMotion {
    withAnimation(.spring()) {
        isDoubleTapAnimating = true
    }
} else {
    // Skip animation, just toggle state
    isDoubleTapAnimating = true
}
```

### VoiceOver Labels
```swift
// Make swipe actions accessible
.swipeActions {
    Button {
        toggleSave()
    } label: {
        Label("Save Post", systemImage: "bookmark")
    }
    .accessibilityLabel("Save this post for later")
}
```

### Dynamic Type
```swift
// Use semantic text styles
Text(post.content)
    .font(.body)  // Scales with user's text size preference

// For custom sizes, use .custom with .relativeTo
Text(headerText)
    .font(.system(size: 24, weight: .bold))
    .minimumScaleFactor(0.5)  // Allow shrinking if needed
```

---

## 🔧 Troubleshooting

### Issue: Double-tap not working
**Solution**: Ensure single-tap has 300ms delay:
```swift
.onTapGesture {
    handleSingleTap()  // Has built-in delay
}
.onTapGesture(count: 2) {
    handleDoubleTap()  // Cancels single tap
}
```

### Issue: Swipe actions conflict with scroll
**Solution**: Use `.swipeActions` instead of custom gestures

### Issue: Deep links not working
**Solution**: Check URL scheme in Info.plist:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>amen</string>
        </array>
    </dict>
</array>
```

### Issue: Haptics not firing
**Solution**: Test on real device (Simulator doesn't support haptics)

### Issue: Toasts stacking
**Solution**: ToastManager auto-dismisses previous toast when showing new one

---

## 📚 Additional Resources

- [HIG: Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures)
- [HIG: Haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- [SwiftUI Navigation](https://developer.apple.com/documentation/swiftui/navigation)
- [Universal Links](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)

---

## ✅ Implementation Complete

All interaction patterns are now implemented and ready for integration. Follow the checklist above to add these enhancements to your existing AMEN app without breaking current functionality.

**Key Wins**:
- Native iOS feel (swipe, long-press, double-tap)
- Fast and smooth (no jank, proper loading states)
- Accessible (VoiceOver, Reduce Motion, Dynamic Type)
- Safe (undo actions, confirmations for destructive operations)
- Consistent (same gestures work the same way everywhere)
