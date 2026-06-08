# AMEN iOS App — Route Graph

**Navigation Root:** `ContentView.swift`  
**Tab Count:** 8 (keep-mounted pattern for performance)  
**Auth Gates:** SplashView → UsernameSelection → Onboarding → EmailVerification → AccountStatus → Main  

## Tab Navigation (AllTabsZStack)

### Tab 0: Home (HomeView)
- **Inbound:** ContentView tab selection (default on launch)
- **Outbound:** 
  - Create post (via quick actions)
  - View post details (tap post card)
  - Profile navigation (tap user avatar)
  - Berean quick actions (formations, assistant)
  - Prayer creation
  - Discussion join
- **Service Listeners:** NotificationAggregationService.updateCurrentScreen(.home)

### Tab 1: Discovery (AMENDiscoveryView)
- **Inbound:** Tab bar tap, ContentView selection
- **Outbound:**
  - Content cards (posts, prayers, discussions)
  - Creator profiles
  - Topic follow
  - Search results
- **ID:** "discovery"

### Tab 2: Inbox (SpiritualInboxView)
- **Inbound:** Tab bar tap, conversation notifications
- **Outbound:**
  - Open conversation (tap thread)
  - Create new message
  - View message details
- **Screen Tracking:** .messages
- **Badge Clear:** BadgeCountManager.clearMessages()

### Tab 3: Resources (ResourcesView)
- **Inbound:** Tab bar tap, SabbathMode gate allows during focus
- **Outbound:**
  - Church Notes (creation, editing)
  - Find Church
  - Bible search (Selah)
  - Learning resources
- **ID:** "resources"

### Tab 4: Notifications (AMENNotificationsView)
- **Inbound:** Tab bar tap, notification badge taps
- **Outbound:**
  - Navigate to content (post, prayer, discussion)
  - User profile (from notification actor)
  - Conversation (from DM notification)
- **ID:** "notifications"
- **Screen Tracking:** .notifications

### Tab 5: Profile (ProfileView)
- **Inbound:** Tab bar tap, user avatar taps (own profile)
- **Outbound:**
  - Edit profile (settings)
  - View followers/following
  - Saved posts/prayers
  - Posted content feed
  - Subscription management
  - Account deactivation
- **ID:** "profile"
- **Screen Tracking:** .profile(userId)

### Tab 6: Spaces (AmenConnectSpacesHubView)
- **Inbound:** Tab bar tap
- **Outbound:**
  - Space details (tap space card)
  - Create space
  - Space members list
  - Space events
  - Space chat
- **ID:** "spaces"

### Tab 7: Intelligence Brief (WhatNeedsAttentionView)
- **Inbound:** Tab bar tap, SabbathMode gate allows during focus
- **Outbound:**
  - Prayer needs (tap card)
  - Community requests
  - Opportunities (volunteer, mentorship)
  - World response (global intelligence)
  - Formation cards
- **ID:** "intelligence"

---

## Auth/Onboarding Flow (Synchronous Gates)

### Gate 1: Splash Screen (SplashView)
- **Condition:** `!authViewModel.isAuthenticated && showSplash == true`
- **Outbound:** Dismiss → proceeds to next gate
- **Z-Index:** 1 (topmost)

### Gate 2: Username Selection (UsernameSelectionView)
- **Condition:** `authViewModel.needsUsernameSelection == true`
- **Trigger:** Social sign-in (Google, Apple) creates account without username
- **Outbound:** Complete → sets `completeUsernameSelection()`, proceeds to onboarding gate
- **Transition:** .asymmetric (insertion: .trailing, removal: .opacity)

### Gate 3: Onboarding (OnboardingView)
- **Condition:** `authViewModel.needsOnboarding == true`
- **Trigger:** New user after account creation
- **Behavior:** 
  - Completes before email verification
  - Sets `showFirstPostPromptPending` flag (fires after mainContent appears)
  - Calls `authViewModel.completeOnboarding()` on finish
- **Transition:** .opacity + .move(edge: .trailing)
- **Signal:** Calls `AppReadyStateManager.shared.signalReady()` on appear

### Gate 4: Email Verification (EmailVerificationGateView)
- **Condition:** `authViewModel.needsEmailVerification == true`
- **Trigger:** After onboarding completes (or for existing users with unverified email)
- **Outbound:** Verify email → dismisses gate, checks in background
- **Transition:** .opacity + .move(edge: .trailing)

### Gate 5: Account Status (AccountStatusGateView)
- **Condition:** Authenticated, all gates above passed
- **Behavior:** 
  - Checks for suspended/deactivated status
  - Wraps mainContent
  - Starts core service initialization

### Alternate Gates (Mutually Exclusive)

#### Simple Mode (AmenSimpleModeView)
- **Condition:** `AmenSimpleModeService.shared.isSimpleModeActive == true`
- **Behavior:** Full-screen accessibility mode, bypasses tab bar + feed complexity
- **Bypass:** Overrides all other navigation

#### Account Deactivated (ReactivationPromptView)
- **Condition:** `authViewModel.isDeactivated == true`
- **Behavior:** User is authenticated but profile is hidden; must reactivate
- **Transition:** .opacity + .move(edge: .trailing)

#### Reactivation Needed (for email/phone verification retry)
- Shown before mainContent, no tab navigation available

---

## Modal/Sheet Navigation

### Sheet Presentations (activeModal)

| Modal | Trigger | Content | Detents |
|-------|---------|---------|---------|
| .sundayPrompt | Sunday focus start | SundayShabbatPromptView | .medium |
| .authSuccess | Sign-in completion | AuthSuccessCheckmarkView | fullScreen |
| .welcomeToAMEN | First onboarding complete | WelcomeToAMENView | fullScreen |
| .compulsiveReopenRedirect(count) | Session re-open limit | CompulsiveReopenRedirectView | fullScreen |

### Deep Modal Coordination

- **Audience Picker:** `showAudiencePicker` (true/false) for post creation
- **Camera OS:** `showCameraOS` (true/false) for media capture
- **Create Post:** `showCreatePost` (true/false) + post category state
- **Quick Actions:** `showCreateQuickActions`, `showBereanQuickActions`
- **Berean Assistant:** `showBereanAssistantFromMenu` + `assistantCoordinator` coordination

### NavigationLink Usage (in Post/Profile/Details Views)

- Post author profile link (embedded in HomeView, DiscoveryView)
- Comment author profile link (in PostDetailView)
- Prayer responder profile link (in PrayerDetailView)
- Discussion participants (in DiscussionDetailView)
- Conversation participant profile (in ConversationView)
- Mentioned users (in text parsing)

---

## Sabbath/Focus Mode Navigation

### Sabbath Gate (SabbathWindowView)
- **Condition:** `sabbathService.currentState == .active`
- **Behavior:** Full-screen gate with surface selection (Prayer, Scripture, Reflection)
- **Outbound:** Each surface is a `.fullScreenCover(item:content:)` that updates `sabbathCurrentDest`
- **Override:** Takes precedence over all other navigation, including SundayChurchFocus

### Stepped Out Banner (SabbathBanner)
- **Condition:** `sabbathService.currentState == .steppedOut`
- **Behavior:** Persistent banner at top, allows normal tab navigation
- **Restoration:** Shows countdown to Sabbath end

### Sunday/Church Focus Gate (SundayChurchFocusGateView)
- **Condition:** `SundayChurchFocusManager.shared.shouldGateFeature() && !isAllowedDuringChurchFocus(tab)`
- **Allowed Tabs During Focus:** 3 (Resources), 5 (Profile), 7 (Intelligence Brief)
- **Blocked Tabs:** 0 (Home), 1 (Discovery), 2 (Inbox), 6 (Spaces)
- **Behavior:** Shows focus mode banner, redirects to allowed tabs

---

## Deep Link Entry Points (NotificationDeepLinkRouter)

Routes push notifications to specific content:
- Post ID → PostDetailView (via HomeView or DiscoveryView)
- Prayer ID → PrayerDetailView
- Discussion ID → DiscussionDetailView
- User ID → ProfileView (tab 5)
- Conversation ID → ConversationView (tab 2)
- Church ID → FindChurchView (tab 3)
- Space ID → SpaceDetailsView (tab 6)
- Notification ID → NotificationsView (tab 4)

**Bootstrapper:** `NotificationTapBootstrapper.shared.appDidBecomeReady()` signals app ready to router

---

## Screen Tracking (NotificationAggregationService)

Used to suppress duplicate notifications while user is viewing that screen:

| Screen | Tab(s) | updateCurrentScreen() |
|--------|--------|----------------------|
| .home | 0 | In HomeView.onAppear |
| .discover | 1 | In AMENDiscoveryView.task |
| .messages | 2 | In SpiritualInboxView.task |
| .notifications | 4 | In AMENNotificationsView.task |
| .profile(userId) | 5 | In ProfileView.task |
| .none | (default) | Other tabs, blocks some notifications |

---

## Orphan Views (No Direct Inbound from MainNav)

- **AuthenticationViews:** SplashView, UsernameSelectionView, OnboardingView, EmailVerificationGateView, ReactivationPromptView, AccountStatusGateView
- **Fallback Sheets:** CompulsiveReopenRedirectView (only via excessive re-open)
- **Detail Views (Deep Links Only):** PostDetailView, PrayerDetailView, DiscussionDetailView, ProfileDetailView (non-owner), ConversationDetailView, SpaceDetailView
- **Settings/Account Views:** Only reachable from ProfileView settings

---

## Dead Ends (No Outbound Navigation)

- **Splash View** (closes to proceed)
- **Email Verification Gate** (must verify or skip)
- **Username Selection** (must choose to proceed)
- **Simple Mode View** (accessibility-only, no nav)
- **Reactivation Prompt** (no bypass)
- **Settings Screen** (saves in place)
- **About/Legal Views** (dismiss to return)

---

## TabView Implementation Details

**Performance:** All 8 tabs are kept mounted simultaneously (not destroyed on tab switch)
```swift
keepMountedTab(isActive: viewModel.selectedTab == 0) {
    HomeView(...)
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(isActive)
        .accessibilityHidden(!isActive)
}
```

**Benefits:**
- Scroll position preserved across tab switches
- Feed continues loading in background
- No re-initialization on return to tab

**Animation:** `.animation(nil, value: viewModel.selectedTab)` — explicit no-animation for tab switches

---

## Route Count Summary

- **Primary Navigation:** 8 tabs
- **Auth/Onboarding Gates:** 5 sequential gates
- **Modal Presentations:** 4 named modals + numerous ephemeral sheets
- **Deep Link Targets:** 7 content types
- **Orphan Entry Points:** 10+ (auth, details, admin)
- **Dead Ends:** 6 (gates, settings, modals)

