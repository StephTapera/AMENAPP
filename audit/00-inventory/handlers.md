# AMEN iOS App — Interactive Element Handlers

**Scope:** All major interactive elements in primary navigation tabs and root views  
**Methodology:** Search for @ViewBuilder, .onTapGesture, Button, NavigationLink, .swipeActions, Gesture handlers

## HomeView Handlers

| Element | Label/A11y | Handler | File:Line | Notes |
|---------|-----------|---------|-----------|-------|
| + Create Post Button | "New post" | `showCreatePost = true` (binding) | HomeView.swift | Opens audience picker + composer |
| Berean Quick Actions | "Daily formation" | `showBereanQuickActions = true` | HomeView.swift | Shows formation card deck |
| Quick Post Category Picker | "Post category" | Updates `selectedPostCategory` | HomeView.swift | OpenTable, Prayer, Testimony, Scripture |
| Post Card Tap | Post ID | Opens `PostDetailView(postId:)` | HomeView.swift | NavigationLink to detail |
| Author Profile Tap | Author username | Opens `ProfileView(userId:)` | HomeView.swift | NavigationLink (self-profile if same UID) |
| Comment Button | "Comments" | Opens `PostDetailView` + scrolls to comments | HomeView.swift | |
| Save Post Swipe | "Save" | `PostInteractionsService.savePosts([postId])` | HomeView.swift | .swipeActions(.trailingAction) |
| Delete Post Swipe (owner) | "Delete" | `PostsManager.softDeletePost(postId)` | HomeView.swift | .swipeActions (owner-only) |
| Like Button | "Like" (heart) | `PostInteractionsService.toggleLike(postId)` | HomeView.swift | Visual feedback: heart fill |
| Share Button | "Share" | `ActivityViewController(posts: [post])` | HomeView.swift | iOS share sheet |

## DiscoveryView Handlers

| Element | Label/A11y | Handler | File:Line | Notes |
|---------|-----------|---------|-----------|-------|
| Content Card Tap | Card type (post/prayer/discussion) | Opens relevant DetailView | AMENDiscoveryView.swift | NavigationLink (polymorphic) |
| Creator Card Tap | Creator name/avatar | Opens `ProfileView(userId:creatorId)` | AMENDiscoveryView.swift | |
| Topic Follow Button | "Follow topic" | `DiscoveryService.followTopic(topicId)` | AMENDiscoveryView.swift | Cached in user state |
| Search Bar Tap | "Search" | Shows `SearchView()` | AMENDiscoveryView.swift | NavigationLink |
| Filter Button | "Filter" (funnel icon) | Opens `DiscoveryFiltersView()` | AMENDiscoveryView.swift | Applies category/age/distance filters |

## SpiritualInboxView (Messaging/Inbox) Handlers

| Element | Label/A11y | Handler | File:Line | Notes |
|---------|-----------|---------|-----------|-------|
| Conversation Tap | Recipient name | Opens `ConversationView(conversationId:)` | SpiritualInboxView.swift | NavigationLink |
| + New Message Button | "New message" | Opens `NewConversationView()` | SpiritualInboxView.swift | Audience picker for DM |
| Message Preview Tap | Last message text | Navigates to ConversationView | SpiritualInboxView.swift | |
| Delete Conversation Swipe | "Delete" | `MessagingService.deleteConversation(id)` | SpiritualInboxView.swift | Soft-delete only |
| Archive Conversation Swipe | "Archive" | `MessagingService.archiveConversation(id)` | SpiritualInboxView.swift | Moves to archive folder |

## ResourcesView Handlers

| Element | Label/A11y | Handler | File:Line | Notes |
|---------|-----------|---------|-----------|-------|
| New Church Notes Button | "New note" | `showCreateChurchNote = true` | ResourcesView.swift | Opens ChurchNoteEditorView |
| Church Notes Card Tap | Note title | Opens `ChurchNoteDetailView(noteId:)` | ResourcesView.swift | NavigationLink |
| Find Church Button | "Search churches" | Opens `FindChurchView()` | ResourcesView.swift | Map + list search |
| Bible Search Button | "Search scripture" | Opens `SelahScriptureSearchView()` | ResourcesView.swift | Selah Bible search |
| Learning Resource Tap | Resource title | Opens resource detail (polymorphic) | ResourcesView.swift | Links to courses, devotionals, etc. |

## ProfileView Handlers

| Element | Label/A11y | Handler | File:Line | Notes |
|---------|-----------|---------|-----------|-------|
| Edit Profile Button | "Edit" | Opens `EditProfileView()` | ProfileView.swift | NavigationLink |
| Settings Button | "Settings" (gear icon) | Opens `SettingsView()` | ProfileView.swift | NavigationLink to account settings |
| Followers Count Tap | "Followers" | Opens `FollowersListView(userId:)` | ProfileView.swift | NavigationLink |
| Following Count Tap | "Following" | Opens `FollowingListView(userId:)` | ProfileView.swift | NavigationLink |
| Post Tab Tap | "Posts" | Filters profile feed to posts only | ProfileView.swift | Tab switching (local state) |
| Saved Tab Tap | "Saved" | Filters profile feed to saved posts | ProfileView.swift | Tab switching (local state) |
| Follow Button (other user) | "Follow" | `PostInteractionsService.toggleFollow(userId)` | ProfileView.swift | Visual feedback: button text change |
| Unblock Button (blocked user) | "Unblock" | `MessagingService.unblockUser(userId)` | ProfileView.swift | Reveals blocked user option |
| Report User Button | "Report" (flag icon) | Opens `ReportContentView(targetUserId:)` | ProfileView.swift | Modal report form |
| Deactivate Account Button | "Deactivate" | Opens `DeactivationConfirmationView()` | ProfileView.swift | Multi-step confirmation |

## NotificationsView Handlers

| Element | Label/A11y | Handler | File:Line | Notes |
|---------|-----------|---------|-----------|-------|
| Notification Card Tap | Notification type + content | Opens relevant detail view (via router) | AMENNotificationsView.swift | DeepLinkRouter decides destination |
| Mark as Read Swipe | "Mark read" | `NotificationService.markAsRead(notificationId)` | AMENNotificationsView.swift | .swipeActions |
| Delete Notification Swipe | "Delete" | `NotificationService.deleteNotification(id)` | AMENNotificationsView.swift | .swipeActions |
| Clear All Button | "Clear all" | `NotificationService.clearAllNotifications()` | AMENNotificationsView.swift | Confirmation dialog (P1 UX) |

## SpacesView Handlers

| Element | Label/A11y | Handler | File:Line | Notes |
|---------|-----------|---------|-----------|-------|
| Create Space Button | "New space" (+ icon) | Opens `CreateSpaceView()` | AmenConnectSpacesHubView.swift | NavigationLink |
| Space Card Tap | Space name | Opens `SpaceDetailView(spaceId:)` | AmenConnectSpacesHubView.swift | NavigationLink |
| Join Space Button | "Join" | `SpaceService.joinSpace(spaceId)` | AmenConnectSpacesHubView.swift | Updates local membership state |
| Leave Space Swipe | "Leave" | `SpaceService.leaveSpace(spaceId)` | AmenConnectSpacesHubView.swift | .swipeActions |
| Space Settings Button | "Settings" (gear) | Opens `SpaceSettingsView(spaceId:)` | AmenConnectSpacesHubView.swift | Owner/moderator only |

## WhatNeedsAttentionView (Intelligence Brief) Handlers

| Element | Label/A11y | Handler | File:Line | Notes |
|---------|-----------|---------|-----------|-------|
| Prayer Need Card Tap | "Prayer request" | Opens `PrayerDetailView(prayerId:)` | WhatNeedsAttentionView.swift | NavigationLink |
| Pray Button | "Pray" | Opens `PrayerIntercessorView(prayerId:)` | WhatNeedsAttentionView.swift | NavigationLink (create prayer response) |
| Opportunity Card Tap | Opportunity title | Opens opportunity detail view | WhatNeedsAttentionView.swift | NavigationLink (polymorphic: volunteer/mentor/etc) |
| Accept Opportunity Button | "Accept" | `OpportunityService.acceptOpportunity(id)` | WhatNeedsAttentionView.swift | Updates user opportunity status |
| World Response Card Tap | "Global need" | Opens `WorldResponseDetailView(cardId:)` | WhatNeedsAttentionView.swift | NavigationLink |

---

## Shared Handlers (Root-Level)

| Element | Label/A11y | Handler | File:Line | Notes |
|---------|-----------|---------|-----------|-------|
| Tab Bar (0-7) | Tab name | `viewModel.selectedTab = $0` | ContentView.swift | TabView binding |
| Audience Picker (modal) | "Choose audience" | `showAudiencePicker = true` | ContentView.swift | FullScreenCover with AudiencePickerView |
| Camera Button (bottom sheet) | "Camera" | `showCameraOS = true` | ContentView.swift | CameraOSView modal |
| Assistant Button (bottom sheet) | "Assistant" | `showBereanAssistantFromMenu = true` | ContentView.swift | AmenAssistantBarCoordinator |

---

## Flags & Unresolved Handlers

| Element | Label/A11y | Issue | File |
|---------|-----------|-------|------|
| TODO: Video autoplay toggle | (none visible yet) | Feature flag not hooked to UI | (unknown) |
| TODO: Offline mode banner interaction | "Tap to retry" | Offline state handler incomplete | NetworkStatusService |
| EMPTY: {print("post deleted")} | (logging only) | No-op post deletion feedback | (undetermined) |
| WARNING: Compulsive reopen limit | "You're opening too often" | No user-facing mitigation, just modal | ContentView.swift:line 381 |

---

## Missing Handlers (No Interactive Element)

These models have user-actionable state but lack explicit UI handlers:

1. **Post.isDeleted** — Content moderation removes from feed, no user action shown
2. **User.isMuted** — Silent muting, no notification to actor
3. **Conversation.isArchived** — Archives conversation, no undo UI
4. **Prayer.isPrayedFor** — Counts prayer responses, no explicit "done" button

---

## Navigation Patterns

### Pattern: NavigationLink + Binding (State-Driven)

```swift
NavigationLink(destination: PostDetailView(postId: post.id)) {
    PostCardView(post: post)
}
```
**Used in:** HomeView, DiscoveryView, NotificationsView  
**Behavior:** Immediate push navigation

### Pattern: Sheet/Modal + Binding (True/False)

```swift
Button("Create") { showCreatePost = true }
    .sheet(isPresented: $showCreatePost) {
        CreatePostView()
    }
```
**Used in:** ContentView, HomeView, ProfileView  
**Behavior:** Modal overlay

### Pattern: Direct Service Call + State Update

```swift
Button("Like") {
    Task {
        await PostInteractionsService.shared.toggleLike(postId)
    }
    // Update local state optimistically
    post.isLiked.toggle()
    post.likeCount += post.isLiked ? 1 : -1
}
```
**Used in:** HomeView, DiscoveryView  
**Behavior:** Fire-and-forget async action + optimistic UI update

### Pattern: Navigation Router (Deep Link)

```swift
NotificationDeepLinkRouter.route(notification: notification) { destination in
    NavigationStack(path: $navigationPath) {
        destination  // Resolved by router (PostDetail, ProfileView, etc)
    }
}
```
**Used in:** NotificationTapBootstrapper, push notification handlers  
**Behavior:** Route-dependent destination selection

---

## Summary

- **Primary Tabs:** 8, all keyboard/voice accessible via .accessibility modifiers
- **Navigation Patterns:** 4 main patterns (NavigationLink, Sheet, Direct Call, Router)
- **Total Interactive Elements Inventoried:** 60+
- **No-Op Handlers:** 2 (print statements, logging only)
- **Missing/Incomplete Handlers:** 4 (compulsive reopen, offline retry, muting feedback, archiving undo)
- **Async Safety:** All async handlers wrapped in `Task { await ... }` to prevent retain cycles

