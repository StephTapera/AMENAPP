# C6 — Navigation Contract + Deep-Link Scheme
**Phase 0 | Contracts-only — stubs and route map, no implementations**
**Frozen:** 2026-06-05

---

## 1. Root Tab Bar

The app uses a custom `AMENTabBar` floating capsule (not `UITabBar`). Tab indices are
assigned at `ContentView` and persisted in `ContentViewModel.selectedTab: Int`.

| Index | Surface | SwiftUI view | Icon | Badge source |
|-------|---------|--------------|------|--------------|
| 0 | **Home / Feed** | `HomeView` | house | none |
| 1 | **Discover** | `AMENDiscoveryView` | magnifyingglass | none |
| 2 | **Messages / Hub** | `SpiritualInboxView` | message | unread count |
| 3 | **Resources** | `ResourcesView` | books.vertical | none |
| 4 | **Notifications** | `AMENNotificationsView` | bell | unread count |
| 5 | **Profile** | `ProfileView` | person.circle | none |
| 6 | **Spaces** | `AmenConnectSpacesHubView` | square.grid.2x2 | none |

**Action Pill (Compose):** A `+` / compose pill overlaid on the tab bar (not its own tab).
Tapping calls `AMENTabBar.onCompose` → sets `showCreatePost = true` in `ContentView`.

> OPEN: Tab 6 (Spaces) is currently wired but not always visible in the tab bar item list.
> Confirm whether Spaces remains a permanent 7th tab or collapses into tab 3 (Resources).

---

## 2. ONE Private Social OS — Sub-Navigation

`ONENavigationShell` (iOS 26+) sits inside Spaces / Profile (exact tab assignment TBD)
and provides its own three-zone glass dock. It is **not** a root tab.

| Zone | View | iOS 26 Availability |
|------|------|---------------------|
| People | `ONEThreadListView` → `ONEThreadView` | Required |
| Moments | `ONELiquidCameraView` | Required |
| World | `ONEWorldFeedView` | Required |

---

## 3. Surface Map

All deep links use the `amen://` custom scheme. Universal links use `https://amenapp.com/`.
Where the surface already exists in the codebase the Swift file path is noted.
Surfaces marked **(NEW - Phase N)** require new construction.

---

### 3.1 Authentication / Onboarding

#### SplashView
- Route: `/splash` (internal — never deep-linked)
- Deep link: none
- Entry points: app cold start, unauthenticated user
- Parameters: none
- Navigation type: fullscreen (replaces ContentView root)
- Back behavior: n/a (unidirectional)
- Phase: 1
- Status: **exists** — `AMENAPP/SplashView.swift` / `AutoLoginSplashView`

#### OnboardingView
- Route: `/onboarding`
- Deep link: none
- Entry points: new account creation (`authViewModel.needsOnboarding == true`)
- Parameters: none
- Navigation type: fullscreen replace
- Back behavior: n/a
- Phase: 1
- Status: **exists** — `AMENAPP/OnboardingView.swift`

#### OnboardingFlowView
- Route: `/onboarding/flow`
- Deep link: none
- Entry points: `AMENAPPApp.fullScreenCover` when `!hasCompletedOnboarding`
- Parameters: none
- Navigation type: fullScreenCover
- Back behavior: n/a (completes to main app)
- Phase: 1
- Status: **exists** — `AMENAPP/OnboardingFlowView.swift`

#### EmailVerificationGateView
- Route: `/auth/verify-email`
- Deep link: handled via Firebase email link (`Auth.auth().isSignIn(withEmailLink:`)
- Entry points: post-onboarding, `authViewModel.needsEmailVerification == true`
- Parameters: none
- Navigation type: fullscreen replace
- Back behavior: n/a
- Phase: 1
- Status: **exists** — `AMENAPP/EmailVerificationGateView.swift`

#### TwoFactorVerificationGateView
- Route: `/auth/2fa`
- Deep link: none
- Entry points: `authViewModel.needs2FAVerification == true`
- Parameters: none
- Navigation type: fullscreen replace
- Back behavior: n/a
- Phase: 1
- Status: **exists** — `AMENAPP/TwoFactorVerificationGateView.swift`

#### UsernameSelectionView
- Route: `/onboarding/username`
- Deep link: none
- Entry points: social sign-in (Google / Apple) first login
- Parameters: none
- Navigation type: fullscreen replace
- Back behavior: n/a
- Phase: 1
- Status: **exists**

---

### 3.2 Feed / Home (Tab 0)

#### Home / Feed
- Route: `/home`
- Deep link: `amen://home` | `amen://category/opentable`
- Entry points: Tab 0, cold start (authenticated)
- Parameters: `category?: string` (OpenTable, Testimonies, Prayer, etc.)
- Navigation type: tab root
- Back behavior: tab-root (scroll to top on double-tap)
- Phase: 1
- Status: **exists** — `AMENAPP/HomeView.swift`

> OPEN: Confirm whether `HomeView` shows a single scrollable feed or a category switcher.
> `DeepLinkRouter` routes both `.category` and `.post` to `selectedTab = 0`.

#### Post Detail
- Route: `/post/{postId}`
- Deep link: `amen://post/{postId}` | `amen://post/{postId}?comment={commentId}`
- Entry points: feed row tap, share link, notification tap
- Parameters: `postId: String` (required), `commentId?: String` (scroll + highlight target)
- Navigation type: push (NavigationStack within HomeView)
- Back behavior: pop
- Phase: 1
- Status: **exists** — `AMENAPP/PostDetailView.swift`

#### Comment Thread (with highlight)
- Route: `/post/{postId}/comment/{commentId}`
- Deep link: `amen://comment?postId={postId}&commentId={commentId}&prefill={text}`
- Entry points: notification tap (comment, reply, mention), Reply Assist Live Activity
- Parameters: `postId: String`, `commentId?: String`, `prefill?: String`
- Navigation type: push → CommentsView scroll anchor
- Back behavior: pop
- Phase: 1
- Status: **exists** — `AMENAPP/CommentsView.swift` + `CommentFocusCoordinator`

#### Open Table View
- Route: `/home/open-table`
- Deep link: `amen://category/opentable`
- Entry points: Home tab category switcher
- Parameters: none
- Navigation type: tab root scroll position
- Back behavior: tab-root
- Phase: 1
- Status: **exists** — `AMENAPP/AMENAPP/OpenTableView.swift`

#### Media Detail
- Route: `/media/{mediaId}`
- Deep link: `amen://media/{mediaId}` **(NEW - Phase 2)**
- Entry points: feed post media tap, MediaOnlyFeedView
- Parameters: `mediaId: String`
- Navigation type: fullscreen
- Back behavior: dismiss
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/MediaDetailView.swift`

---

### 3.3 Discover / Search (Tab 1)

#### Discover / Search
- Route: `/discover`
- Deep link: `amen://search?q={query}`
- Entry points: Tab 1, search quick action, notification
- Parameters: `q?: String` (pre-filled query)
- Navigation type: tab root
- Back behavior: tab-root
- Phase: 1
- Status: **exists** — `AMENAPP/AMENAPP/AmenDiscoverView.swift`

#### Discovery Rails
- Route: `/discover/rails`
- Deep link: `amen://discover/rails` **(NEW - Phase 2)**
- Entry points: Discover tab sub-section
- Parameters: `section?: string` (rail type)
- Navigation type: push
- Back behavior: pop
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/SpiritualOS/Discovery/AmenDiscoveryRailsView.swift`

#### Discovery Detail
- Route: `/discover/{objectId}`
- Deep link: `amen://discover/{objectId}` **(NEW - Phase 2)**
- Entry points: discovery rail item tap
- Parameters: `objectId: String`
- Navigation type: push
- Back behavior: pop
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/AmenDiscoverDetailView.swift`

---

### 3.4 Profiles

#### Own Profile
- Route: `/profile`
- Deep link: `amen://profile` (own)
- Entry points: Tab 5, notification for own content
- Parameters: none (uses `Auth.auth().currentUser?.uid`)
- Navigation type: tab root
- Back behavior: tab-root
- Phase: 1
- Status: **exists** — `AMENAPP/ProfileView.swift`

#### Other User Profile
- Route: `/user/{userId}`
- Deep link: `amen://user/{userId}` | `amen://profile/{userId}`
- Entry points: feed author tap, followers list, search result, notification
- Parameters: `userId: String`
- Navigation type: sheet (from `NavigationHelpers.swift`)
- Back behavior: dismiss
- Phase: 1
- Status: **exists** — `AMENAPP/UserProfileView.swift`

> OPEN: The codebase uses sheet for UserProfileView but push navigation for some paths.
> Confirm canonical navigation type for other-user profile (sheet vs push).

#### Church Profile
- Route: `/church/{churchId}`
- Deep link: `amen://church/{churchId}`
- Entry points: discovery, search, notification, post tag
- Parameters: `churchId: String`
- Navigation type: push | sheet
- Back behavior: pop | dismiss
- Phase: 2
- Status: **exists** — router at `AMENAPP/AMENAPP/ChurchJourneyRouter.swift`; view TBD

#### Organization / Nonprofit Profile
- Route: `/org/{orgId}`
- Deep link: `amen://org/{orgId}` **(NEW - Phase 3)**
- Entry points: discovery, search, job post tag
- Parameters: `orgId: String`
- Navigation type: push
- Back behavior: pop
- Phase: 3
- Status: **(NEW - Phase 3)**

#### Creator / Studio Profile
- Route: `/creator/{creatorId}`
- Deep link: `amen://creator/{creatorId}`
- Entry points: notification (`studioProfile`), discovery, Spaces host tap
- Parameters: `creatorId: String`
- Navigation type: push
- Back behavior: pop
- Phase: 3
- Status: **exists** — `NotificationDeepLinkRouter.NavigationDestination.studioProfile`

---

### 3.5 Spaces + Connect (Tab 6)

#### Spaces Hub
- Route: `/spaces`
- Deep link: `amen://spaces`
- Entry points: Tab 6, notification
- Parameters: none
- Navigation type: tab root
- Back behavior: tab-root
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/ConnectSpaces/AmenConnectSpacesHubView.swift`

#### Space Detail
- Route: `/space/{spaceId}`
- Deep link: `amen://space/{spaceId}`
- Entry points: Spaces Hub tap, discovery, notification
- Parameters: `spaceId: String`
- Navigation type: push
- Back behavior: pop
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/ConnectSpaces/AmenSpaceDetailView.swift`

#### Space Discovery
- Route: `/spaces/discover`
- Deep link: `amen://spaces/discover` **(NEW - Phase 2)**
- Entry points: Spaces Hub "Explore" action
- Parameters: none
- Navigation type: push | sheet
- Back behavior: pop | dismiss
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/ConnectSpaces/AmenSpaceDiscoveryView.swift`

#### Event Detail
- Route: `/event/{eventId}`
- Deep link: `amen://event/{eventId}`
- Entry points: Space Detail event card, notification, calendar
- Parameters: `eventId: String`
- Navigation type: push | sheet
- Back behavior: pop | dismiss
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/ConnectSpaces/Events/AmenSpaceEventDetailView.swift`

#### Ministry Room (Study Room)
- Route: `/space/{spaceId}/room/{roomId}`
- Deep link: `amen://space/{spaceId}/room/{roomId}` **(NEW - Phase 2)**
- Entry points: Space Detail "Open Room" pill
- Parameters: `spaceId: String`, `roomId: String`
- Navigation type: fullscreen
- Back behavior: dismiss
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/ConnectSpaces/Spaces/AmenMinistryRoomShellView.swift`

#### Live Room
- Route: `/space/{spaceId}/live`
- Deep link: `amen://space/{spaceId}/live` **(NEW - Phase 2)**
- Entry points: Space event "Go Live" tap
- Parameters: `spaceId: String`
- Navigation type: fullscreen
- Back behavior: dismiss
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/ConnectSpaces/Live/AmenLiveRoomShellView.swift`

#### Creator Hub
- Route: `/creator/hub`
- Deep link: `amen://creator/hub` **(NEW - Phase 3)**
- Entry points: Profile → Creator Hub tab
- Parameters: none
- Navigation type: push | sheet
- Back behavior: pop | dismiss
- Phase: 3
- Status: **exists** — `AMENAPP/AMENAPP/ConnectSpaces/AmenCreatorHubTabView.swift`

---

### 3.6 Messages / Hub (Tab 2)

#### Spiritual Inbox / Messages Hub
- Route: `/messages`
- Deep link: `amen://messages`
- Entry points: Tab 2, notification routing (`.messages`)
- Parameters: none
- Navigation type: tab root
- Back behavior: tab-root
- Phase: 1
- Status: **exists** — `AMENAPP/AMENAPP/SpiritualOS/SpiritualInboxView.swift`

#### Direct Message Thread
- Route: `/conversation/{conversationId}`
- Deep link: `amen://conversation/{conversationId}?message={messageId}` | `amenapp://conversation/{conversationId}`
- Entry points: Inbox row tap, notification tap, group join link
- Parameters: `conversationId: String`, `messageId?: String` (scroll anchor)
- Navigation type: push
- Back behavior: pop
- Phase: 1
- Status: **exists** — `AMENAPP/ConversationView.swift` (inferred from `NotificationDeepLinkRouter`)

#### ONE Thread (E2EE Private)
- Route: `/one/thread/{threadId}`
- Deep link: `amen://one/thread/{threadId}` **(NEW - Phase 2)**
- Entry points: ONE People zone thread row
- Parameters: `threadId: String`
- Navigation type: push (within `ONENavigationShell` NavigationStack)
- Back behavior: pop
- Phase: 2
- Status: **exists** — `ONEThreadView` via `ONEThreadListView.navigationDestination`

#### Group Join Link
- Route: `/group/join`
- Deep link: `amenapp://group/join?token={token}` | `https://amenapp.com/group/join?token={token}`
- Entry points: share link from outside app
- Parameters: `token: String`
- Navigation type: sheet
- Back behavior: dismiss
- Phase: 2
- Status: **exists** — `NotificationDeepLinkRouter.NavigationDestination.groupJoinLink`

---

### 3.7 Prayer + Church Notes (Tab 3 — Resources)

#### Prayer Room / Prayer Detail
- Route: `/prayer/{prayerId}`
- Deep link: `amen://prayer/{prayerId}` | `amenapp://prayer/{prayerId}`
- Entry points: notification (prayerReminder, prayerAnswered, prayerSupported), Resources tab
- Parameters: `prayerId: String`
- Navigation type: push | sheet
- Back behavior: pop | dismiss
- Phase: 1
- Status: **exists** — `NotificationDeepLinkRouter.NavigationDestination.prayer`

#### Voice Prayer Recorder
- Route: `/prayer/record`
- Deep link: none (internal)
- Entry points: Prayer Room action, Create menu
- Parameters: none
- Navigation type: sheet
- Back behavior: dismiss
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/VoicePrayer/VoicePrayerRecorderView.swift`

#### Church Notes Session
- Route: `/church-notes`
- Deep link: `amen://church-notes` | `amenapp://notes/{shareLinkId}`
- Entry points: Resources tab, notification (`churchNoteShared`), share link
- Parameters: `shareLinkId?: String`
- Navigation type: push | sheet
- Back behavior: pop | dismiss
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/ChurchNotesSessionView.swift`

#### Church Note Detail
- Route: `/church-note/{noteId}`
- Deep link: `amen://church-note/{noteId}` | `amenapp://notes/{noteId}`
- Entry points: notification, Church Notes list, share link
- Parameters: `noteId: String`
- Navigation type: push
- Back behavior: pop
- Phase: 2
- Status: **exists** — `NotificationDeepLinkRouter.NavigationDestination.churchNote`

#### Find a Church
- Route: `/church`
- Deep link: `amen://church`
- Entry points: Resources tab, notification, Discover section
- Parameters: `query?: String`
- Navigation type: push
- Back behavior: pop
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/SpiritualOS/Churches/AmenChurchHubView.swift`

#### Church Journey — Prep / Plan / Reflection
- Route: `/church-journey/{churchId}` | `/church-journey/plan/{churchId}` | `/church-journey/notes/{sessionId}` | `/church-journey/reflection/{journeyId}`
- Deep link: `amen://church-journey/church/{churchId}` | `amen://church-journey/plan/{churchId}` | `amen://church-journey/notes/{sessionId}` | `amen://church-journey/reflection/{journeyId}`
- Entry points: Church Profile, Sunday prompt, notification
- Parameters: see `ChurchJourneyRoute` enum
- Navigation type: push
- Back behavior: pop
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/ChurchJourneyRouter.swift`, `ChurchMorningPrepView`, `ChurchJourneyPlanView`, `ChurchReflectionView`

#### Study Plans / Berean Study
- Route: `/study`
- Deep link: `amen://study` **(NEW - Phase 2)**
- Entry points: Resources tab, Berean quick action
- Parameters: none
- Navigation type: push
- Back behavior: pop
- Phase: 2
- Status: **exists** — `AMENAPP/AMENAPP/BereanStudyHomeView.swift`, `AmenMyStudyPlansView`

#### Giving / Donation
- Route: `/giving`
- Deep link: `amen://giving` **(NEW - Phase 3)**
- Entry points: Church Profile → Give, Resources tab
- Parameters: `churchId?: String`, `campaignId?: String`
- Navigation type: push | sheet
- Back behavior: pop | dismiss
- Phase: 3
- Status: **exists** — `AMENAPP/AMENAPP/Giving/Views/GivingHomeView.swift`

#### Job / Opportunity Detail
- Route: `/job/{jobId}`
- Deep link: `amen://job/{jobId}`
- Entry points: notification (`.job`), Resources → AMEN Connect, Discover
- Parameters: `jobId: String`
- Navigation type: push | sheet
- Back behavior: pop | dismiss
- Phase: 3
- Status: `NotificationDeepLinkRouter.NavigationDestination.job` exists; view **(NEW - Phase 3)**

#### Mentorship Profile
- Route: `/mentor/{userId}`
- Deep link: `amen://mentor/{userId}` **(NEW - Phase 3)**
- Entry points: AMEN Connect, discovery, notification
- Parameters: `userId: String`
- Navigation type: push | sheet
- Back behavior: pop | dismiss
- Phase: 3
- Status: **exists** — `AMENAPP/AMENAPP/ConnectSpaces/Community/AmenMentorMatchingView.swift`

---

### 3.8 Berean AI (global overlay)

#### Berean AI Chat
- Route: `/berean`
- Deep link: `amen://berean` | Live Activity `amen://berean?postID={postId}`
- Entry points: Berean quick actions menu, post long-press, Live Activity, `BereanChatRouteView`
- Parameters: `postId?: String`, `query?: String`, `mode?: String`
- Navigation type: sheet | overlay (AmenAssistantBarOverlay)
- Back behavior: dismiss
- Phase: 1
- Status: **exists** — `AMENAPP/AMENAPP/BereanChatRouter.swift` routes to `BereanChatView`

> OPEN: Berean bar overlays all tabs as a persistent bottom overlay (`AmenAssistantBarOverlay`).
> Clarify whether `amen://berean` link pushes a full sheet or expands the persistent bar.

#### Berean Daily Formation
- Route: `/berean/formation`
- Deep link: `amen://berean/formation` **(NEW - Phase 3)**
- Entry points: Berean home, daily push notification
- Parameters: none
- Navigation type: sheet
- Back behavior: dismiss
- Phase: 3
- Status: **exists** — `AMENAPP/AMENAPP/AMENAPP/BereanPulse/BereanPulseView.swift`

---

### 3.9 Settings + Privacy (Tab 5)

#### Settings Root
- Route: `/settings`
- Deep link: `amen://settings` | `amen://settings/{section}`
- Entry points: Profile tab, notification redirect
- Parameters: `section?: String` (e.g., `privacy`, `notifications`, `subscription`)
- Navigation type: push
- Back behavior: pop
- Phase: 1
- Status: **exists** — `AMENAPP/AMENAPP/Settings/SettingsView.swift` (inferred)

#### Manage Subscription
- Route: `/settings/subscription`
- Deep link: `amen://settings/subscription` **(NEW - Phase 3)**
- Entry points: Settings, Profile paywall prompt
- Parameters: none
- Navigation type: push
- Back behavior: pop
- Phase: 3
- Status: **exists** — `AMENAPP/AMENAPP/ManageSubscriptionView.swift`

#### Feed Intelligence Settings
- Route: `/settings/feed-intelligence`
- Deep link: `amen://settings/feed` **(NEW - Phase 3)**
- Entry points: Settings, "Why am I seeing this?" link
- Parameters: none
- Navigation type: push
- Back behavior: pop
- Phase: 3
- Status: **exists** — `AMENAPP/AMENAPP/FeedIntelligenceSettingsView.swift`

---

### 3.10 Notifications (Tab 4)

#### Notification Center
- Route: `/notifications`
- Deep link: `amen://notifications` | `amenapp://notifications`
- Entry points: Tab 4, notification tap fallback
- Parameters: none
- Navigation type: tab root
- Back behavior: tab-root
- Phase: 1
- Status: **exists** — `AMENAPP/AMENAPP/AMENNotificationsView.swift` (inferred)

---

### 3.11 Moderation / Admin

#### Moderation Dashboard
- Route: `/admin/moderation`
- Deep link: none (admin-only, no external link)
- Entry points: Admin-flagged user access, Spaces host moderation panel
- Parameters: none
- Navigation type: push | sheet
- Back behavior: pop | dismiss
- Phase: 4
- Status: **exists** — `AMENAPP/AMENAPP/ConnectSpaces/Safety/AmenModerationDashboardView.swift`

#### Crisis Support
- Route: `/crisis`
- Deep link: none (internal trigger only — `CrisisDetectionService`)
- Entry points: Berean crisis detection, content safety flag
- Parameters: none
- Navigation type: fullscreen overlay
- Back behavior: dismiss (explicit user action only)
- Phase: 1
- Status: **exists** — `AMENAPP/AMENAPP/Crisis/CrisisSupportView.swift`

---

### 3.12 Universal Composer

#### Universal Composer (Create Post)
- Route: `/compose`
- Deep link: `amen://compose` | `amenapp://share` (from Share Extension)
- Entry points: Action Pill tap, Berean quick action, Share Extension, first-post prompt
- Parameters: `category?: String`, `prefill?: String` (from share extension draft)
- Navigation type: sheet (`.presentationDetents([.large])`)
- Back behavior: dismiss
- Phase: 1
- Status: **exists** — `AMENAPP/AMENAPP/CreatePostView.swift`

**Action Pill → Composer flow:**
1. User taps `+` pill in `AMENTabBar`
2. `AMENTabBar.onCompose` callback fires → `ContentView` sets `showCreatePost = true`
3. `ContentView` presents `CreatePostView` as a sheet
4. No NavigationStack push — always a sheet from the root level so it floats above all tabs

**Share Extension → Composer flow:**
1. iOS invokes share extension → writes `ShareDraft` to App Group UserDefaults (`group.com.amenapp.shared`)
2. App opens via `amen://share` → `handleShareExtensionDraft()` reads draft, posts `.openCreatePostFromShare`
3. `ContentView` observes notification → opens `CreatePostView` pre-filled

---

### 3.13 Follow-Up / Continuity Navigation

Smart Follow-Up (`SmartNotificationEngine`, `A15`) resurfaces pending items via:

1. **Notification tap** — routes through `NotificationDeepLinkRouter.routeFromPushPayload` → `performNavigation` → updates `selectedTab` and posts `openPostFromNotification` / `openConversation` etc.
2. **Reply Assist Live Activity** — deep link `amen://comment?postId={}&commentId={}&prefill={}` or `amen://chat?threadId={}&prefill={}`; route handled by `DeepLinkRouter.parse` → `.comment` or `.chat`
3. **Church Journey continuation** — `amen://church-journey/reflection/{journeyId}` resurfaces incomplete reflection
4. **Berean follow-up** — `amen://berean?postID={postId}` from Live Activity opens Berean chat with post context

Resurfaced item route: uses the same surface routes listed above; no separate "follow-up" screen.
`SmartNotificationRouter` (`AMENAPP/SmartNotificationRouter.swift`) is the iOS-side routing coordinator.

---

## 4. Complete Deep Link Scheme Reference

### Custom Scheme: `amen://`
Used by `DeepLinkRouter` (parsed in `DeepLinkRouter.parse(url:)`).

```
amen://home
amen://category/{name}              — e.g. amen://category/opentable
amen://post/{postId}
amen://post/{postId}?comment={commentId}
amen://comment?postId={}&commentId={}&prefill={}
amen://user/{userId}
amen://profile/{userId}
amen://church/{churchId}
amen://church-journey/church/{churchId}
amen://church-journey/plan/{churchId}
amen://church-journey/notes/{sessionId}
amen://church-journey/reflection/{journeyId}
amen://conversation/{conversationId}
amen://conversation/{conversationId}?message={messageId}
amen://chat?threadId={}&prefill={}
amen://messages
amen://notifications
amen://search?q={query}
amen://settings
amen://settings/{section}
amen://prayer/{prayerId}
amen://berean
amen://berean?postID={postId}
amen://berean/formation
amen://spaces
amen://space/{spaceId}
amen://space/{spaceId}/room/{roomId}
amen://space/{spaceId}/live
amen://discover/{objectId}
amen://media/{mediaId}
amen://creator/{creatorId}
amen://creator/hub
amen://org/{orgId}
amen://mentor/{userId}
amen://job/{jobId}
amen://event/{eventId}
amen://giving
amen://study
amen://compose
```

Live Activity / Shabbat helpers (parsed in `AMENAPPApp.handleLiveActivityDeepLink`):
```
amen://prayer?action=prayed
amen://prayer?action=snooze
amen://church?action=end
amen://church?action=notes
amen://church?action=navigate
amen://music?action=stop
amen://berean?postID={}
```

### Legacy Scheme: `amenapp://`
Used by `NotificationDeepLinkRouter.handleURL`. Maps to the same surfaces.

```
amenapp://post/{postId}
amenapp://post/{postId}?commentId={commentId}
amenapp://profile/{userId}
amenapp://conversation/{conversationId}
amenapp://conversation/{conversationId}?messageId={messageId}
amenapp://group/join?token={token}
amenapp://notifications
amenapp://messages
amenapp://prayer/{prayerId}
amenapp://church-note/{noteId}
amenapp://notes/{shareLinkId}        — church notes share link
amenapp://share                      — share extension draft handoff
```

### Universal Links: `https://amenapp.com/`
Handled in `NotificationDeepLinkRouter.handleURL` for `https` scheme.

```
https://amenapp.com/group/join?token={token}
```

> OPEN: Universal link domain association file (`apple-app-site-association`) must be deployed
> at `https://amenapp.com/.well-known/apple-app-site-association`. Confirm which paths are
> registered and whether the amen:// scheme is registered in Info.plist URL Types.

---

## 5. Tab Index Routing Map (DeepLinkRouter)

From `DeepLinkRouter.navigate(to:)` and `NotificationNavigationHandler`:

| Route type | selectedTab |
|-----------|-------------|
| `.post`, `.category`, `.comment`, `.userProfile` (push), `.church` | 0 (Home) |
| `.search` | 1 (Discover) |
| `.conversation`, `.chat`, `.messages` | 2 (Messages) |
| `.prayer`, `.churchNote`, `.job`, `.event`, `.studioProfile` | 3 (Resources) |
| `.notification`, `.notifications` | 4 (Notifications) |
| `.profile` (own or other) | 5 (Profile) |
| Spaces-related | 6 (Spaces) |
| `.settings` | 4 (Profile — `DeepLinkRouter` uses 4; see conflict note below) |

> **ROUTING CONFLICT DETECTED:** `DeepLinkRouter` maps `.settings` to `selectedTab = 4`
> (Notifications), but settings lives under Tab 5 (Profile).
> `NotificationNavigationHandler` uses the comment: "Tab layout: 0=Home, 1=Discovery,
> 2=Messages, 3=Resources, 4=Notifications, 5=Profile" — so settings should target tab 5.
> This is a bug that must be resolved before Phase 1 ships.

---

## 6. Shabbat / Church Focus Gate

When `SundayChurchFocusManager.shared.shouldGateFeature()` is true:
- Tabs 0 (Home), 1 (Discover), 2 (Messages), 4 (Notifications), 6 (Spaces) → show `SundayChurchFocusGateView`
- Tabs 3 (Resources) and 5 (Profile/Settings) remain accessible
- `DeepLinkRouter` redirects blocked routes to `selectedTab = 3` and posts `.shabbatDeepLinkBlocked`

---

## 7. Open Questions (for human sign-off)

1. **Settings tab routing** — `DeepLinkRouter` sends settings to tab 4 (Notifications). Should be tab 5 (Profile). Fix required before Phase 1.
2. **Spaces as permanent tab** — Is Tab 6 (Spaces) always visible, or conditionally shown (e.g., only for Premium or Creator accounts)?
3. **ONE shell entry point** — Which tab hosts `ONENavigationShell`? Current code does not wire it to a ContentView tab.
4. **Profile navigation type** — Other-user profiles currently use sheet. Confirm push vs sheet is the canonical pattern for the Community OS redesign.
5. **Universal link paths** — Which paths beyond `/group/join` should be added to `apple-app-site-association`?
6. **`amen://` vs `amenapp://` unification** — Two parallel schemes exist with different parsing. Phase 1 should consolidate to a single scheme.
