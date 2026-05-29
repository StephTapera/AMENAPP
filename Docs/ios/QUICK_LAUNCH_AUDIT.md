# AMEN Quick-Launch Surface Inventory
Date: 2026-05-29

---

## Summary

**9 distinct quick-launch surfaces** identified across Home Screen shortcuts, Siri/App Intents, URL schemes, Widgets, CarPlay, and Spotlight.

**Routing architecture:**
- **1 primary router** for notification deep links: `NotificationDeepLinkRouter` (warm/background push taps, URL-scheme routing).
- **1 production-grade routing coordinator** layered on top: `NotificationOpenCoordinator` (version-aware, guarded, with analytics — new v3 system).
- **1 dedicated quick-action bridge**: `AMENQuickActionManager` (UIApplicationShortcutItem → `AMENAppRoute` → `ContentView`).
- **1 URL-scheme router** for `DeepLinkRouter` (handles `amen://` scheme with Shabbat gating).
- **1 church-specific router**: `ChurchDeepLinkHandler` (handles `amen://church/*` sub-routes).
- **1 Siri/Spotlight router**: `AmenIntentRouter` (translates AppIntent notifications → NotificationCenter → `amenDeepLink` notification).
- **1 access-pass router**: `AmenAccessPassDeepLinkRouter` (handles `amen://access/` and universal links for invites).

**Hot spots:** Multiple `onOpenURL` handlers are chained inline in `AMENAPPApp.onOpenURL` without a unified dispatch table. Several surfaces navigate via raw `NotificationCenter.post` instead of through any router. The `NotificationDeepLinkHandler` class is marked `@available(*, deprecated)` but is still instantiated as a singleton.

---

## Tab Index Reference

| Index | Tab |
|-------|-----|
| 0 | Home (Feed) |
| 1 | Discovery / People |
| 2 | Messages |
| 3 | Resources (Church Notes, Find Church, Prayer) |
| 4 | Notifications |
| 5 | Profile |
| 6 | Gatherings / Spaces / Community Notes (extended) |

---

## Surface Matrix

| Surface | Trigger | Intended Destination | Current Handler | Current Destination | States Handled | Auth-Gated? | Notes |
|---------|---------|---------------------|-----------------|---------------------|----------------|-------------|-------|
| **Home Screen Quick Action — New Post** | Long-press app icon → "New Post" | Create-post composer | `AppDelegate.application(_:performActionFor:)` → `AMENQuickActionManager.handle(_:)` → `ContentView.handleQuickActionRoute(.newPost)` | selectedTab=0, then `showCreatePost=true` | Cold launch (stored in `pendingRoute`) + warm launch (fires immediately) | Yes — `installShortcuts` clears shortcuts when user is signed out; `handleQuickActionRoute` is only reachable from `mainContent` which is behind auth | Item type: `com.amen.app.quickaction.newpost` |
| **Home Screen Quick Action — Messages** | Long-press app icon → "Messages" | Messages tab | Same chain as above → `handleQuickActionRoute(.messages)` | selectedTab=2 | Cold + warm; contextual subtitle shows unread count | Yes | Item type: `com.amen.app.quickaction.messages`; subtitle shows unread count when >0 |
| **Home Screen Quick Action — Activity** | Long-press app icon → "Activity" | Notifications tab | Same chain → `handleQuickActionRoute(.activity)` | selectedTab=4 | Cold + warm | Yes | Item type: `com.amen.app.quickaction.activity` |
| **Home Screen Quick Action — Ask Berean** | Long-press app icon → "Ask Berean" | Berean AI sheet | Same chain → `handleQuickActionRoute(.bereanAI)` | selectedTab=0, then `showBereanAssistantFromMenu=true` | Cold + warm | Yes | Item type: `com.amen.app.quickaction.berean`; differentiating AMEN feature |
| **Home Screen Quick Action — Search** | Long-press app icon → "Search" (dynamic, not always shown) | Discovery tab | Same chain → `handleQuickActionRoute(.search)` | selectedTab=1 | Cold + warm | Yes | Item type: `com.amen.app.quickaction.search`; not always in the 4-slot rotation |
| **Home Screen Quick Action — Prayer** | Long-press app icon → "Prayer" (dynamic) | Home/Feed tab | Same chain → `handleQuickActionRoute(.prayer)` | selectedTab=0 (no specific prayer deep-nav within tab) | Cold + warm | Yes | Bug: prayer lives in Resources (tab 3) but routes to tab 0. Type: `com.amen.app.quickaction.prayer` |
| **Home Screen Quick Action — My Profile** | Long-press app icon → "My Profile" (dynamic) | Profile tab | Same chain → `handleQuickActionRoute(.myProfile)` | selectedTab=5 | Cold + warm | Yes | Type: `com.amen.app.quickaction.profile` |
| **Home Screen Quick Action — Continue Draft** | Long-press app icon → "Continue Draft" (contextual, shown when draft exists) | Create-post composer with draft restored | Same chain → `handleQuickActionRoute(.newPost)` with `userInfo["source"]="draft"` | selectedTab=0, then `showCreatePost=true` — but draft source is NOT checked in `handleQuickActionRoute` | Cold + warm | Yes | Bug: `userInfo["source"]="draft"` is set in `installShortcuts` but `handleQuickActionRoute` ignores it — draft is never restored automatically |
| **Siri / App Shortcuts — Start Prayer Mode** | "Start prayer mode in AMEN" | Prayer/Resources | `StartPrayerModeIntent.perform()` → `NotificationCenter.post("openPrayerMode")` → `AmenIntentRouter.handle(notification:)` → posts `"amenDeepLink"` notification with `"amen://prayer"` | Relies on `AMENAPPApp` observing `"amenDeepLink"` — **but this observer is not wired in the current `AMENAPPApp.swift`** | openAppWhenRun=true | Yes (app must be open; Shabbat gate applies in DeepLinkRouter) | Gap: `AmenIntentRouter` posts `"amenDeepLink"` but `AMENAPPApp` has no `onReceive` for it; see Gaps section |
| **Siri / App Shortcuts — Ask Berean** | "Ask Berean in AMEN" | Berean AI sheet | `AskBereanIntent.perform()` → writes `pendingBereanQuestion` to UserDefaults → `NotificationCenter.post("openBerean")` → `AmenIntentRouter` → `"amenDeepLink"` | Same gap as above — `"amenDeepLink"` not observed in app root | openAppWhenRun=true | Yes | Question param stored in `UserDefaults("pendingBereanQuestion")`; consumed by `AmenIntentRouter.pendingBereanQuestion()` |
| **Siri / App Shortcuts — Find a Church** | "Find a church in AMEN" | Find Church screen | `FindChurchIntent.perform()` → `NotificationCenter.post("openFindChurch")` → `AmenIntentRouter` → `"amenDeepLink"` with `amen://find-church` | Same gap | openAppWhenRun=true | Yes | |
| **Siri / App Shortcuts — Open Church Notes** | "Open church notes in AMEN" | Church Notes (Resources tab) | `OpenChurchNotesIntent.perform()` → `NotificationCenter.post("openChurchNotes")` → `AmenIntentRouter` → `"amenDeepLink"` with `amen://church-notes` | Same gap | openAppWhenRun=true | Yes | |
| **Siri / App Shortcuts — Start Quiet Reflection** | "Start quiet reflection in AMEN" | Calm/reflection mode | `StartReflectionIntent.perform()` → `NotificationCenter.post("openReflection")` → `AmenIntentRouter` → `"amenDeepLink"` with `amen://reflection` | Same gap | openAppWhenRun=true | Yes | |
| **Siri / App Shortcuts — Send Prayer Request** | "Send a prayer request in AMEN" | Prayer composer | `SendPrayerRequestIntent.perform()` → writes `pendingPrayerMessage` → `NotificationCenter.post("openPrayerComposer")` → `AmenIntentRouter` → `"amenDeepLink"` | Same gap | openAppWhenRun=true | Yes | |
| **Siri / App Shortcuts (AMENAppIntents.swift) — Open Prayer** | Siri / Shortcuts app | Prayer tab/section | `OpenPrayerIntent.perform()` → `NotificationCenter.post(.navigateToTab, userInfo:["tab":2])` | Posts tab index 2 (Messages) — but intent says "Prayer" which should be tab 3 | openAppWhenRun=true | Yes | Bug: `navigateToTab` tab value 2 points to Messages not Prayer/Resources (tab 3). Duplicate intent file: `AMENAppIntents.swift` and `AMENAPP/SiriIntents/AmenAppIntents.swift` define parallel intent sets |
| **Siri / App Shortcuts (AMENAppIntents.swift) — Ask Berean AI** | Siri / Shortcuts app | Berean AI sheet | `OpenBereanIntent.perform()` → `NotificationCenter.post(.openBereanFromLiveActivity)` | Observed in `AMENAPPApp.handleLiveActivityDeepLink` for `host=="berean"` — routes to Berean UI | openAppWhenRun=true | Yes | Also reuses Live Activity notification name |
| **Siri / App Shortcuts (AMENAppIntents.swift) — Get Daily Verse** | Siri / Shortcuts app | Returns verse text (no navigation) | `DailyVerseIntent.perform()` → returns `DailyVerseGenkitService.shared.todayVerse?.text` | No navigation — returns value to Siri | openAppWhenRun=false | No | Benign read-only intent |
| **Siri / App Shortcuts (AMENAppIntents.swift) — Create Post** | Siri / Shortcuts app | Create-post composer | `CreatePostIntent.perform()` → `NotificationCenter.post(.openCreatePost)` | Observed in ContentView | openAppWhenRun=true | Yes | |
| **Siri / App Shortcuts (AMENAppIntents.swift) — Post Prayer Request** | Siri / Shortcuts app | Prayer composer | `PostPrayerRequestIntent.perform()` → `NotificationCenter.post(.amenOpenPrayerComposer)` | Observed in ContentView (gated on `siriIntegrationEnabled`) | openAppWhenRun=true | Yes | |
| **Siri / App Shortcuts (AMENAppIntents.swift) — Share Testimony** | Siri / Shortcuts app | Testimony composer | `ShareTestimonyIntent.perform()` → `NotificationCenter.post(.amenOpenTestimonyComposer)` | Observed in ContentView (gated) | openAppWhenRun=true | Yes | |
| **Siri / App Shortcuts (AMENAppIntents.swift) — RSVP to Event** | Siri / Shortcuts app | Events screen | `RSVPEventIntent.perform()` → `NotificationCenter.post(.amenOpenEvents)` | Observed in ContentView (gated) | openAppWhenRun=true | Yes | |
| **Siri / App Shortcuts (AMENAppIntents.swift) — Discover Prayer Needs** | Siri / Shortcuts app | Prayer feed | `DiscoverPrayerNeedsIntent.perform()` → `NotificationCenter.post(.amenOpenPrayerFeed)` | Observed in ContentView (gated) | openAppWhenRun=true | Yes | |
| **Focus Filter — Prayer Focus** | iOS Focus mode "Prayer Focus" | Silences social; optional prayer-only mode | `PrayerFocusFilter.perform()` → `ShabbatModeService.shared.setEnabled(true)` and/or `UserDefaults("focusFilterPrayerOnly")` | No navigation; modifies app behavior flags | N/A | No explicit auth gate | `SetFocusFilterIntent` — iOS calls this when the focus becomes active/inactive |
| **URL Scheme — Push Notification Tap** | User taps push notification (app in background or cold) | Varies by type (post, profile, conversation, prayer, church note, etc.) | `PushNotificationHandler` → `CompositeNotificationDelegate` → `NotificationOpenCoordinator.handleNotificationResponse(_:)` → `NotificationResolver` → `NotificationTapHandler.execute(_:)` → `NotificationDeepLinkRouter.shared.navigate(to:)` | selectedTab switch + `NotificationCenter.post` for specific screen | All push notification types; debounced; queued until `appReady` and auth resolved | Yes — router queues routes until `Auth.auth().currentUser != nil` | v3 production path via `NotificationOpenCoordinator`; legacy path via `NotificationDeepLinkRouter.routeFromPushPayload` also active in `PushNotificationHandler` |
| **URL Scheme — `amenapp://` / `com.amenapp://`** | External app, share sheet, NFC, QR | Varies by host (post, profile, conversation, prayer, group join, etc.) | `AMENAPPApp.onOpenURL` → `NotificationOpenCoordinator.handleURL(url)` (primary) → fallback to `NotificationDeepLinkRouter.shared.handleURL(url)` | `NotificationDeepLinkRouter` maps to selectedTab + NotificationCenter posts | All hosts defined in `NotificationDeepLinkRouter.handleURL` | Yes (queued until auth) | Info.plist registers schemes `amenapp` and `com.amenapp`. Coordinator only handles `amenapp://` and `com.amenapp://` for its known hosts; `amen://` scheme goes to different routers |
| **URL Scheme — `amen://`** | Live Activity taps, widget CTAs, internal deep links | Varies (post, user, church, conversation, comment, chat, etc.) | `AMENAPPApp.onOpenURL` → `DeepLinkRouter.shared.parse(url:)` + `handleLiveActivityDeepLink(_:)` + `handleChurchNoteDeepLink(_:)` | `DeepLinkRouter.navigate(to:)` sets selectedTab; Live Activity sub-routes post NotificationCenter events | All hosts in `DeepLinkRouter.parse`; Live Activity sub-actions handled inline | Yes — Shabbat gate in `DeepLinkRouter.navigate` | Note: scheme in `amen://` router differs from `amenapp://` router — two parallel parsers for similar destinations |
| **URL Scheme — Access Pass** | QR code, NFC tap, share link, in-app invite | Access pass landing sheet | `AmenAccessPassDeepLinkRouter.canHandle(url:)` → `handle(url:)` → resolves via Cloud Function | Presents `AmenAccessPassLandingView` sheet | Pass ID + raw token required | Stored for post-auth redirect if user is not authenticated | Registered via `.amenAccessPassDeepLinkHandler()` modifier — not yet applied in `AMENAPPApp` (is in separate modifier, needs wiring) |
| **Universal Links — `https://amenapp.com/`** | Web links, email, share cards | Varies (post, profile, conversation, group join, prayer, church note) | `AMENAPPApp.onOpenURL` → `NotificationOpenCoordinator.handleURL` (parses universal links) + `NotificationDeepLinkRouter.handleURL` (handles `amenapp.com` group/join) | Same as `amenapp://` scheme above | Universal link paths: `/post/{id}`, `/profile/{id}`, `/conversation/{id}`, `/prayer/{id}`, `/church-note/{id}`, `/group/join?token=` | Yes | Associated domains entitlement needed; `apple-app-site-association` file required on `amenapp.com` domain |
| **URL Scheme — Church Notes Share Link** | Share link (`amenapp://notes/{id}`) | Church Note detail | `AMENAPPApp.handleChurchNoteDeepLink(_:)` → `NotificationCenter.post("OpenChurchNoteFromDeepLink")` | Observed at call site that handles `"OpenChurchNoteFromDeepLink"` | Share link ID only | Implicit (app must be open) | Separate from main deep link routers; standalone inline handler |
| **Widget — Daily Verse (small/medium/large/lock screen)** | Tap widget | App opens; large widget has explicit CTA button `amen://verse` | `Link(destination: URL("amen://verse"))` in widget CTA | `AMENAPPApp.onOpenURL` receives `amen://verse` — but `DeepLinkRouter` has no `verse` host handler; falls through silently | Widget tap opens app to last active tab; CTA tap fires `amen://verse` which is unhandled | No (widget tap just opens app) | Bug: `amen://verse` is not registered in any router. Widget files are in main app target, not a Widget Extension target — `@main` is commented out; widgets are not actually running yet |
| **Widget — Prayer Count (small/medium/lock screen)** | Tap "Add Prayer" CTA | Prayer composer | `Link(destination: URL("amen://prayer/new"))` | `amen://prayer` host is handled in Live Activity handler (`PrayerLiveActivityService.shared.handleDeepLink`); `/new` sub-path likely not parsed | App opens; prayer deep link partially handled | No | Bug: `amen://prayer/new` — the `/new` action is not explicitly parsed anywhere. Widget target not yet set up. |
| **Spotlight — Prayer, Church Note, Berean, Verse** | User taps Spotlight search result for AMEN content | Respective detail screen | `AMENAPPApp.onContinueUserActivity("com.amen.view")` → `AmenSpotlightService.shared.handleSpotlightResult(activity)` → `AmenIntentRouter.routeSpotlight(type:id:)` → posts `"amenDeepLink"` notification | Same gap as Siri intents: `"amenDeepLink"` notification is **not observed** in `AMENAPPApp` | All four domain types (prayer, churchNote, berean, verse) | Yes | `AmenSpotlightService` indexes content; `AmenSpotlightIndexingService` also in project — two indexing files |
| **CarPlay — Berean Drive** | User connects CarPlay | Berean AI voice assistant | `AmenCarPlaySceneDelegate.templateApplicationScene(_:didConnect:)` → `BereanCarPlayCoordinator.start()` | CarPlay-native CPListTemplate; no shared tab router | Feature-flag gated (`carPlayBereanEnabled`); graceful no-op if flag off | Implicit (requires signed-in user via coordinator) | Requires Apple entitlements `carplay-audio` + `carplay-communication` — not auto-granted |
| **Share Extension → Main App Draft** | User shares content from another app; taps "Post" in extension | Create-post composer with pre-filled draft | `AMENAPPApp.onOpenURL` for scheme `com.amenapp://share` or `amenapp://share` → `handleShareExtensionDraft()` → reads App Group `UserDefaults("pendingShareDraft")` → `NotificationCenter.post(.openCreatePostFromShare)` | Observed somewhere in ContentView / CreatePostView | Draft with text, linkURL, destination | Yes (App Group `group.com.amenapp.shared` must be configured) | Requires Share Extension target to write the draft |

---

## Existing Routing Abstractions

### 1. `DeepLinkRouter` (primary `amen://` URL router)
**File:** `AMENAPP/DeepLinkRouter.swift`

Singleton `@MainActor` class. Parses `amen://` URLs into `DeepLinkRoute` enum cases and calls `navigate(to:)`, which:
- Checks Shabbat gate via `AppAccessController.shared.canAccess(feature)`.
- Sets `selectedTab` (0–4 mapping, differs from actual tab layout — see bug below).
- Sets `activeRoute` for the root view to react to.

**Declared URL routes:** `amen://post/{id}`, `amen://user/{id}`, `amen://church/{id}`, `amen://conversation/{id}`, `amen://category/{name}`, `amen://search?q=`, `amen://settings/{section?}`, `amen://comment?postId=&commentId=&prefill=`, `amen://chat?threadId=&prefill=`.

**Tab mapping in `navigate(to:)`:**
```
post/userProfile/category/church/comment → selectedTab = 0
search                                   → selectedTab = 1
conversation/chat                        → selectedTab = 3  // BUG: should be 2 (Messages)
notification                             → selectedTab = 2  // BUG: should be 4 (Notifications)
settings                                 → selectedTab = 4  // BUG: should be 5 (Profile)
```
The tab mapping was written for an older tab layout. Current layout: 0=Home, 1=Discovery, 2=Messages, 3=Resources, 4=Notifications, 5=Profile.

**SwiftUI modifier:** `.handleDeepLinks()` (`DeepLinkHandler` struct) — installed via `onOpenURL` but does NOT appear to be applied in `AMENAPPApp.swift` or `ContentView.swift`. This router is only reached via the fallback path in `AMENAPPApp.onOpenURL`.

---

### 2. `NotificationDeepLinkRouter` (push notification + `amenapp://` scheme router)
**File:** `AMENAPP/NotificationDeepLinkRouter.swift`

Singleton `@MainActor` class. Handles:
- `route(_:AppNotification)` — routes in-app notification taps.
- `routeFromPushPayload(_:)` — routes push notification tap payloads.
- `handleURL(_:)` — routes `amenapp://` URL scheme and `https://amenapp.com/` universal links.

Navigation is dispatched via `NotificationNavigationHandler` ViewModifier applied at `.handleNotificationNavigation(selectedTab:)` in `ContentView.swift` (line ~684). Uses correct tab indices (0=Home, 2=Messages, 4=Notifications, 5=Profile).

Has debounce (0.6s), auth-readiness queuing, and `verifyAndNavigate` content-existence check via Firestore.

**Tab mapping in `NotificationNavigationHandler`:**
```
.post          → selectedTab = 0
.profile       → selectedTab = 5
.conversation  → selectedTab = 2
.messages      → selectedTab = 2
.notifications → selectedTab = 4
.prayer/.churchNote/.job/.event/.studioProfile → selectedTab = 3
.groupDetail   → selectedTab = 1
.groupJoinLink → selectedTab = 2
```

---

### 3. `NotificationOpenCoordinator` (v3 production notification coordinator)
**File:** `AMENAPP/AMENAPP/ProductionNotificationRouting.swift`

The newest layer, intended to be the single entry point for all notification-triggered routing. Wraps `NotificationResolver` (Firestore existence check + guard logic) and `NotificationTapHandler`. Accepts push taps via `handleNotificationResponse(_:)`, URL schemes via `handleURL(_:)`, and is called first in `AMENAPPApp.onOpenURL`. Uses `PendingRouteStore` (UserDefaults-persisted) for cold-launch queueing.

`AMENAPPApp.onOpenURL` calls this coordinator first; only falls through to `NotificationDeepLinkRouter.handleURL` if coordinator returns `false`.

---

### 4. `AMENQuickActionManager` (Home Screen quick actions bridge)
**File:** `AMENAPP/AMENQuickActionManager.swift`

Singleton `@MainActor` class. Stores pending `AMENAppRoute` for cold-launch delivery. `ContentView` observes `$pendingRoute` via `.onReceive` and calls `handleQuickActionRoute(_:)`. Installs/removes `UIApplicationShortcutItem` array on sign-in/sign-out and on every app foreground transition.

---

### 5. `ChurchDeepLinkHandler` (church-specific sub-router)
**File:** `AMENAPP/ChurchDeepLinkHandler.swift`

Handles `amen://church/{id}`, `amen://church/{id}/reflect`, `amen://church/{id}/journey`. Applied via `.handleChurchDeepLinks()` modifier in `AMENAPPApp.swift` (line ~208). Presents `ChurchProfileView` as a sheet. Runs in parallel with `DeepLinkRouter` which also handles `amen://church/{id}` — potential double-navigation.

---

### 6. `AmenIntentRouter` (Siri intent → deep link translator)
**File:** `AMENAPP/AMENAPP/SiriIntents/AmenIntentRouter.swift`

Translates `NotificationCenter` notifications from `AppIntent.perform()` calls into deep-link URL strings, then posts them as `Notification.Name("amenDeepLink")` with `userInfo["url"]`. **Critical gap: `AMENAPPApp.swift` does not observe `"amenDeepLink"`**, so all Siri/Spotlight routes via this router are silently dropped.

---

### 7. `AmenAccessPassDeepLinkRouter`
**File:** `AMENAPP/AccessPasses/AmenAccessPassDeepLinkRouter.swift`

Handles `amen://access/{passId}?t={token}` and `https://amen.app/access/{passId}?t={token}`. Applied via `.amenAccessPassDeepLinkHandler()` view modifier. This modifier adds its own `onOpenURL` — it must be applied at the root level to intercept URLs before other handlers. Current status: modifier exists but is not visibly applied in `AMENAPPApp.swift`.

---

### 8. `AmenSpotlightService`
**File:** `AMENAPP/AMENAPP/AmenSpotlightService.swift`

Indexes prayers, church notes, Berean sessions, and verses into Core Spotlight. Results are handled in `AMENAPPApp.onContinueUserActivity("com.amen.view")` which calls `AmenIntentRouter.routeSpotlight`. Same gap as Siri: the resulting `"amenDeepLink"` notification is not observed anywhere.

---

## Navigation Hot Spots (Bug Sources)

### Hot Spot 1 — `"amenDeepLink"` notification is never observed
**Severity: P0 — All Siri shortcuts and all Spotlight results are silently dropped.**

`AmenIntentRouter` (both in `AmenAppIntents.swift` and `SiriIntents/AmenIntentRouter.swift`) posts `Notification.Name("amenDeepLink")` after translating an intent into an `amen://` URL. However, neither `AMENAPPApp.swift` nor `ContentView.swift` has an `.onReceive` or `NotificationCenter.addObserver` for `"amenDeepLink"`. Every Siri shortcut and Spotlight tap ends with a `dlog` and no navigation.

**Fix:** In `AMENAPPApp.body` (WindowGroup), add:
```swift
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("amenDeepLink"))) { notification in
    if let urlString = notification.userInfo?["url"] as? String,
       let url = URL(string: urlString) {
        NotificationDeepLinkRouter.shared.handleURL(url)
    }
}
```

---

### Hot Spot 2 — `DeepLinkRouter.navigate(to:)` uses stale tab indices
**Severity: P1 — Tapping `amen://conversation/...`, `amen://notification/...`, or `amen://settings` lands on the wrong tab.**

`DeepLinkRouter.navigate(to:)` (line ~173–191) maps:
- `.conversation/.chat` → `selectedTab = 3` (opens Resources, should be 2 Messages)
- `.notification` → `selectedTab = 2` (opens Messages, should be 4 Notifications)
- `.settings` → `selectedTab = 4` (opens Notifications, should be 5 Profile)

**Fix:** Update `DeepLinkRouter.navigate(to:)` tab mapping to match current layout.

---

### Hot Spot 3 — "Prayer" quick action routes to Home, not Resources
**Severity: P1 — User expects to see Prayer content; lands on the social feed instead.**

`ContentView.handleQuickActionRoute(.prayer)` sets `selectedTab = 0` (Home). Prayer features live in the Resources tab (index 3).

**Fix:** Change `case .prayer: viewModel.selectedTab = 3` (or whichever tab hosts Prayer in the current Resources hierarchy).

---

### Hot Spot 4 — "Continue Draft" quick action does not restore the draft
**Severity: P1 — User taps "Continue Draft" shortcut; composer opens but is empty.**

`AMENQuickActionManager.installShortcuts` creates a `UIApplicationShortcutItem` with `userInfo["source"] = "draft" as NSSecureCoding`, but `handleQuickActionRoute` handles `.newPost` without checking the `source` key. The draft is never loaded.

**Fix:** Pass `source` through `AMENAppRoute` (e.g. `case newPost(source: String?)`) and in `handleQuickActionRoute(.newPost)`, check for `source == "draft"` before opening the composer, then call `DraftsManager.shared` to restore the latest draft into the composer.

---

### Hot Spot 5 — `OpenPrayerIntent` (in `AMENAppIntents.swift`) posts wrong tab index
**Severity: P1 — "Open prayer in AMEN" Siri command lands on Messages tab.**

`OpenPrayerIntent.perform()` posts `.navigateToTab` with `["tab": 2]`, which is Messages. Prayer/Resources is tab 3.

**Fix:** Change `["tab": 2]` to `["tab": 3]` in `OpenPrayerIntent.perform()`.

---

### Hot Spot 6 — Two parallel `AppShortcutsProvider` / intent sets
**Severity: P2 — Intent registration is split across two files; iOS may surface duplicate or conflicting shortcuts.**

`AMENAPP/AMENAppIntents.swift` defines `AMENShortcutsProvider` with 7 shortcuts, and `AMENAPP/AMENAPP/SiriIntents/AmenAppIntents.swift` defines `AmenAppShortcutsProvider` with 6 different shortcuts. Both files have `static var appShortcuts` and would both be registered if both types appear in the compiled binary. iOS allows only one `AppShortcutsProvider` per app target.

**Fix:** Consolidate all shortcuts into a single provider in one file; delete the other.

---

### Hot Spot 7 — `amen://verse` widget CTA is unhandled
**Severity: P2 — Tapping "Open AMEN" in the large Daily Verse widget opens the app but navigates nowhere.**

`AmenDailyVerseWidget` has `Link(destination: URL(string: "amen://verse")!)`. No router parses `host == "verse"`. Falls through all `onOpenURL` handlers silently.

**Fix:** Add `case "verse": return .category("verse")` (or a dedicated route) in `DeepLinkRouter.parse(url:)` to navigate to the Daily Verse section.

---

### Hot Spot 8 — `amen://prayer/new` (Prayer widget CTA) path not parsed
**Severity: P2 — "Add Prayer" CTA in the Prayer widget opens the app but does not open the prayer composer.**

`AmenPrayerWidget` uses `Link(destination: URL(string: "amen://prayer/new")!)`. The `handleLiveActivityDeepLink` handles `host == "prayer"` by calling `PrayerLiveActivityService.shared.handleDeepLink(url:)`. That handler's behavior for the `/new` sub-path is unknown without reading `PrayerLiveActivityService`.

**Fix:** Audit `PrayerLiveActivityService.handleDeepLink(url:)` to ensure it opens the prayer composer when `action == "new"` or `pathComponents[0] == "new"`.

---

### Hot Spot 9 — `ChurchDeepLinkHandler` and `DeepLinkRouter` both handle `amen://church/`
**Severity: P2 — Potential double sheet presentation for church deep links.**

`AMENAPPApp` applies `.handleChurchDeepLinks()` which installs an `onOpenURL` observer via `ChurchDeepLinkHandler`. `AMENAPPApp.onOpenURL` also calls `NotificationDeepLinkRouter.shared.handleURL(url)` which routes `amenapp://` church links, and `DeepLinkRouter` handles `amen://church/{id}`. Multiple handlers may respond to the same URL type, potentially showing duplicate sheets.

**Fix:** Centralize church routing through one router. Have `ChurchDeepLinkHandler` remain the authoritative handler but remove the `church` case from `DeepLinkRouter.navigate` and/or add a guard so `ChurchDeepLinkHandler.handleURL` returns `true` to prevent further processing.

---

### Hot Spot 10 — `NotificationDeepLinkHandler` (deprecated) is still a live singleton
**Severity: P2 — Dead code adds confusion; its `NSNotification` observer on `"didReceiveNotificationResponse"` is never fired.**

`NotificationDeepLinkHandler` is marked `@available(*, deprecated, renamed: "NotificationDeepLinkRouter")` but its `init` calls `setupNotificationHandlers()` which registers a `NotificationCenter` observer. No active code path posts `"didReceiveNotificationResponse"`. It should be removed to avoid maintenance confusion.

---

### Hot Spot 11 — Widget files are in the main app target, not a Widget Extension
**Severity: P2 — Widgets are not visible to users; the `@main` entry point is commented out.**

`AmenWidgetBundle.swift`, `AmenDailyVerseWidget.swift`, `AmenPrayerWidget.swift` are in `AMENAPP/AMENAPP/Widgets/` and are built into the main app target. The `@main` struct comment says "Remove @main when the target is created." Without a separate Widget Extension target, WidgetKit never registers these widgets and they do not appear on the Home Screen or Lock Screen.

---

## Face ID / App Lock Mechanism

### How it works today

**1. `BiometricAuthService`** (`AMENAPP/BiometricAuthService.swift`)
- Singleton that checks `LAContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`.
- Preference stored in `UserDefaults("biometricAuthEnabled")`.
- Provides `authenticate(reason:)` (biometrics only) and `authenticateWithPasscodeFallback(reason:)` (biometrics + device passcode).
- Used for sign-in convenience, not as a per-session app lock.

**2. `SelahAppLockGateView`** (`AMENAPP/SelahScripture/SelahAppLockGateView.swift`)
- A full-screen gate specifically protecting the **Selah private journal** (spiritual reflections).
- Uses `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` (biometrics + passcode fallback).
- Shown on `SelahView.onAppear` when the Selah section is entered; calls `onUnlocked()` callback on success.
- Fires automatically on `.onAppear` to prompt immediately.

**3. No app-wide "Require Face ID" toggle exists in the current codebase.**
- `AMENFeatureFlags.swift` does not define an `appLockEnabled` or `requireFaceID` flag.
- There is no session-level lock that gates the entire app behind biometrics on foreground re-entry.
- `BiometricAuthService.isBiometricEnabled` is only used for sign-in convenience flows (referenced in `BiometricOnboardingPage.swift`).

**Which screens check the lock before rendering:**
- `SelahView` / the Selah journal section — gated by `SelahAppLockGateView`.
- No other view in the audited source files calls `LAContext.evaluatePolicy` before rendering.

**Future integration point:** `AMENMessagingPrivacyPill.swift` references `LAContext` for messaging privacy; `SecurityCenterView.swift` likely has a toggle UI. A full app-lock feature was noted in `Info.plist` (`NSFaceIDUsageDescription`: "AMEN uses Face ID to keep your account secure and let you sign in quickly.") but the enforcement logic for whole-app locking is not yet implemented.

---

## Gaps and Questions for Agent 1 (Router Author)

1. **Routing authority:** Should `NotificationOpenCoordinator` become the single entry point for ALL URL-scheme and push-notification routing, superseding `NotificationDeepLinkRouter` and `DeepLinkRouter`? Currently three routers handle overlapping URL schemes.

2. **`"amenDeepLink"` observer:** Where should the observer for `"amenDeepLink"` live — in `AMENAPPApp` body or in `ContentView.mainContent`? It must run only when the user is authenticated. Recommend: `ContentView.mainContent` with an auth guard.

3. **URL scheme consolidation:** The app registers both `amenapp://` (handled by `NotificationDeepLinkRouter`) and `amen://` (handled by `DeepLinkRouter` + Live Activity handler + Church handler). Should these be merged into a single scheme? Which scheme should be canonical?

4. **Tab index source of truth:** `DeepLinkRouter.navigate` uses indices 0–4 matching an older layout. `NotificationDeepLinkRouter.NotificationNavigationHandler` uses the correct current indices (0–5 + extended). Should `DeepLinkRouter` be updated or deprecated in favor of `NotificationDeepLinkRouter`?

5. **Prayer quick-action destination:** Prayer is currently reached via the Resources tab (index 3). Should the quick action switch directly to tab 3 and optionally scroll to the prayer section, or should Prayer eventually get its own tab?

6. **Widget Extension target:** When will the Widget Extension target be created? Until it is, all widget deep-link routing code is dead. Confirm: should `amen://verse` open the daily verse in the main feed, or navigate to a dedicated verse detail view?

7. **`AmenAccessPassDeepLinkRouter` wiring:** The `.amenAccessPassDeepLinkHandler()` modifier exists but is not applied at the root level. Should it be applied in `AMENAPPApp.body` or inside `ContentView` after auth?

8. **`NotificationDeepLinkHandler` removal:** Confirm it is safe to delete `NotificationDeepLinkHandler.swift` entirely. No active code path calls it; retaining it only adds dead-observer overhead.

9. **Cold-launch race for quick actions:** On cold launch, `AMENQuickActionManager.pendingRoute` fires via `.onReceive` in `ContentView`. Is the 0.15s dispatch delay sufficient for all auth paths (2FA gate, onboarding gate, email verification gate)? Should the pending route be held until `NotificationDeepLinkRouter.markAppReady()` is called?

10. **Face ID app-wide lock:** Is "Require Face ID" (mentioned in Info.plist and app-store copy) a planned feature? If so, the lock check should be placed in `ContentView`'s `scenePhase .active` handler, not scattered per-view.
