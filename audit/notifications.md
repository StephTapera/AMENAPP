# Notifications Audit (Push + Live Activities)

Audit date: 2026-05-28  
Auditor: Claude Code (automated)  
Scope: APNs/FCM registration, permission flow, deep-link routing, notification categories/actions, Live Activity lifecycle, settings gating.

---

## Findings Table

| File:Line | Severity | Category | Description |
|-----------|----------|----------|-------------|
| `AMENAPP.entitlements:6` | Blocker | APNs Config | `aps-environment` is `development` in the default entitlements file. The release entitlements file (`AMENAPP.release.entitlements`) correctly says `production`. If the wrong entitlements are signed into an App Store build, push delivery will silently fail in production. Must verify the Xcode build scheme uses the release entitlements for Archive. |
| `AppDelegate.swift:191,194,197` + `AppDelegate+Messaging.swift:23,26,29` | Blocker | Duplicate Registration | `CompositeNotificationDelegate`, `Messaging.messaging().delegate`, and `setupFCMToken()` are set up twice: once in `AppDelegate.setupPushNotifications()` (called from `didFinishLaunching`) and again in the parallel `AppDelegate+Messaging.setupMessaging()` extension method. `setupMessaging()` is never called from `didFinishLaunching`, so the duplicate is dead code right now — but the code comment says "Add these to your AppDelegate," making it a latent Blocker if `setupMessaging()` is ever wired in. The duplicate `setupFCMToken()` call would bypass the `hasSetupFCM` guard because the guard is on `PushNotificationManager` but `setupMessaging()` calls it a second time from a second call site. **Fix:** Delete `AppDelegate+Messaging.swift` entirely or convert it to a pure extension that does NOT duplicate delegate assignment. |
| `PushNotificationManager.swift:192-214` + `PushNotificationHandler.swift:75-101` | High | Dual Token Storage | Two singletons write the FCM token to Firestore at slightly different paths. `PushNotificationManager.saveFCMTokenToFirestore` writes only to `users/{uid}` (flat field). `PushNotificationHandler.saveFCMToken` writes both the flat field AND `users/{uid}/deviceTokens/{sanitisedToken}` subcollection. The `MessagingDelegate` callback fires on both objects (`PushNotificationManager` is set as `Messaging.messaging().delegate`; `PushNotificationHandler` has its own `MessagingDelegate` extension that also saves). On a real device this produces two Firestore writes on every FCM token refresh and a race condition on the flat field. `PushNotificationHandler` is also never set as the FCM delegate (only `PushNotificationManager` is), so `PushNotificationHandler.messaging(_:didReceiveRegistrationToken:)` never fires — meaning the subcollection entry is never written. |
| `PushNotificationManager.swift:689-701` + `PushNotificationHandler.swift:194-211` | High | Dead Delegate | `PushNotificationHandler` conforms to both `UNUserNotificationCenterDelegate` and `MessagingDelegate` but is never assigned as either delegate in `AppDelegate.swift`. All delegate traffic goes to `CompositeNotificationDelegate` (for UNUserNotificationCenter) and `PushNotificationManager` (for Messaging). The conformances in `PushNotificationHandler` are unreachable dead code and create confusion. |
| `NotificationDeepLinkHandler.swift:1-10` | High | Dead Code — Silent Drop | The file explicitly documents itself as deprecated. Its `setupNotificationHandlers()` observer listens for `NSNotification.Name("didReceiveNotificationResponse")` which is **never posted** by any active code path. Any call sites that somehow call `NotificationDeepLinkHandler.shared` get a no-op observer that never fires. The static method `handleLaunch(withUserInfo:)` in the `AppDelegate Integration` extension at line 207 is also unreachable. File should be deleted. |
| `PushNotificationManager.swift:267-293` | High | Incomplete Tap Router | `PushNotificationManager.handleNotificationAction(type:data:)` only handles `"message"` and `"messageRequest"` types. All other types fall into `default:` which posts a bare `NSNotification.Name("pushNotificationTapped")`. This NSNotification path is also never consumed by active routing code (`NotificationDeepLinkRouter` and `NotificationOpenCoordinator` are the active routers but neither observes this NSNotification). Effective result: tapping any non-message push from background when `PushNotificationManager.handleNotificationTap` is the active path drops the notification entirely. |
| `ChurchNotificationManager.swift:80` + `NotificationManager.swift:475` + `BreakTimeNotificationManager.swift:239` | High | Category Registration Race | Three services call `UNUserNotificationCenter.current().setNotificationCategories([...])` directly, bypassing `NotificationCategoryRegistrar`. The Registrar was introduced precisely to fix this "last caller wins" bug, but `ChurchNotificationManager`, `NotificationManager`, and `BreakTimeNotificationManager` still call the raw API. Any of these firing after `NotificationCategoryRegistrar.shared.register(...)` will silently wipe the accumulated category set. **Fix:** Route all three callers through `NotificationCategoryRegistrar.shared.register(...)`. |
| `LiveActivityBridge.swift:174` | High | Unrouted Deep Link | The Worship Music Live Activity stores `deepLinkURL = URL(string: "amen://worship")`. Neither `DeepLinkRouter.parse(url:)` nor `NotificationDeepLinkRouter.handleURL(_:)` handles the `worship` host. Tapping the Dynamic Island or Lock Screen widget for worship music opens the app but routes to `.notifications` fallback (or does nothing). |
| `BereanLiveActivityManager.swift:18` | High | Live Activity Disabled | The entire real `BereanLiveActivityManager` and `BereanLiveActivityBridge` implementation is wrapped in `#if false`. The Berean Dynamic Island is completely non-functional at runtime. All call sites in `BereanIslandViewModel+LiveActivity.swift` and `BereanLiveActivityService.swift` will resolve to the no-op stubs silently. `NSSupportsLiveActivities = YES` in Info.plist implies the feature is active to reviewers. |
| `Info.plist:41` | Med | Usage Description Mismatch | `NSUserNotificationsUsageDescription` (line 41) describes only church reminders: "We'll send you reminders about church service times and when you're near your saved churches." This is shown to the user when the system permission dialog appears. The actual permission scope is much broader (prayers, messages, follows, comments, daily verses). App Review may flag this as misleading. |
| `PushNotificationManager.swift:460-494` | Med | Unregistered Notification Category | `scheduleDailyReminder` sets `categoryIdentifier = "DAILY_REMINDER"` and `scheduleVerseOfTheDayNotification` sets `categoryIdentifier = "VERSE_OF_THE_DAY"`. Neither category is registered with `UNUserNotificationCenter`. Categories with action buttons are fine to omit registration for, but unregistered categories can prevent proper routing if action identifiers are checked. More critically, there is no tap-routing for `type = "daily_reminder"` or `type = "verse_of_the_day"` in any active router (`NotificationDeepLinkRouter`, `NotificationOpenCoordinator`, `NotificationRouteResolver`). Tapping these local notifications opens the app to the fallback notifications tab at best. |
| `LiveActivityManager.swift:382-393` | Med | Unrouted Local Notification Type | The prayer snooze path fires a local notification with `type = "prayer_snooze"`. This type is not handled by `NotificationRouteResolver.resolve(_:)` or `NotificationDeepLinkRouter.routeFromPushPayload(_:)`. Tapping the prayer snooze reminder falls through to the default case (`.notifications` inbox) instead of reopening the prayer. |
| `NotificationSettingsView.swift:603-624` | Med | Settings Stored on User Root — Not Gated Server-Side | `followNotifications`, `amenNotifications`, `commentNotifications`, and `messageNotifications` are saved to `users/{uid}` (the root user document), not to `users/{uid}/settings/notifications`. The Cloud Function in `functionssrcnotifications.ts` correctly reads these fields from the root document, so the toggle does gate server-side delivery. However, `NotificationSettingsService` reads from `users/{uid}/settings/notifications` — a **separate path**. The two systems are not in sync: CalmControl and SpiritualRhythm OS read from the sub-document while the main settings view writes to the root. A user who uses the main settings view and one who uses the CalmControl settings view will have their preferences stored in different places, leading to stale UI and potential missed gating. |
| `AppDelegate.swift:213` | Med | Cold-Launch Permission Registration Without Prior Grant | `UIApplication.shared.registerForRemoteNotifications()` is called unconditionally at every cold launch inside `setupPushNotifications()`, regardless of whether the user has granted notification permission. On iOS this is acceptable (the system ignores it if permission is not granted), but the APNs token callbacks will still be triggered and `retryFCMTokenIfNeeded()` will run. This wastes a round-trip and can cause confusing "No APNS token" warnings in prod logs for users who denied permission. |
| `ContentView.swift:985-990` | Med | Redundant Permission Request + FCM Setup | `ContentView` calls `pushManager.requestNotificationPermissions()` and then `pushManager.setupFCMToken()` when the user grants permission during the onboarding flow. This is correct in isolation, but `setupFCMToken()` is guarded by `hasSetupFCM` (a boolean set at first call). If `NotificationPermissionView`, `NotificationPrePromptView`, or `NotificationPermissionOnboarding` also call `setupFCMToken()` (they do), the guard prevents re-entry. The concern is that on first grant, `requestNotificationPermissions()` itself already calls `registerForRemoteNotifications()` (line 58-59 of PushNotificationManager) which will eventually trigger the FCM token callback. The extra `setupFCMToken()` call in ContentView and all three permission views is safely guarded, but the code pattern causes maintenance confusion. |
| `NotificationSettingsView.swift:22` | Low | `messageNotifications` Toggle Not Plumbed to Messages Badge | The settings toggle `messageNotifications` gates push delivery via Cloud Function but does NOT update `BadgeCountManager`. If a user turns off message notifications, they will still see message badge increments from Firestore listeners, creating a confusing mismatch. |
| `PushNotificationManager.swift:536` | Low | `areDailyRemindersScheduled` Uses Half-Threshold | The method returns `true` if at least half of 8 reminder identifiers are scheduled. This means the method returns `true` even if the user has 4 of 8 reminders, which can suppress re-scheduling attempts that should have happened. |
| `NotificationDeepLinkRouter.swift:558-560` | Low | `prayer` + `churchNote` Tap Route Only Goes to Tab 3 | When a push notification deep-links to `.prayer` or `.churchNote`, `NotificationNavigationHandler` switches to `selectedTab = 3` (Resources) but then sets `pendingAction = nil`. This means no `NotificationCenter.post` fires to tell the Resources tab which prayer/note to open. The user lands on the Resources tab root rather than the specific prayer or note. |
| `LiveActivityAttributes.swift:230-235` | Low | ActivityAttributes Conformances Compile-Only | The `#if canImport(ActivityKit)` conformance block at the bottom of `LiveActivityAttributes.swift` is in the main AMENAPP target. Live Activities require a Widget Extension target for their UI. There is no Widget Extension target visible. Without a Widget Extension, the Dynamic Island/Lock Screen UI will not render — the activity will start (when not `#if false`) but show a blank pill. |
| `AMENAPP.entitlements:25` | Low | `com.apple.developer.usernotifications.communication` Entitlement Without INSendMessageIntent | The communication notifications entitlement is present and `INSendMessageIntent` is listed in `NSUserActivityTypes`, but no code path uses `UNNotificationContent.userInfo` to upgrade a notification to a communication notification. This entitlement has no effect currently and may confuse App Review. |

---

## Not Fully Wired

### Notification Types With No Working Tap Destination

| Type String | Registered By | Active Router Handles It? | Result on Tap |
|-------------|--------------|---------------------------|---------------|
| `"daily_reminder"` | `PushNotificationManager.scheduleDailyReminder` | No | Falls to `.notifications` inbox (default case in `routeFromPushPayload`) |
| `"verse_of_the_day"` | `PushNotificationManager.scheduleVerseOfTheDayNotification` | No | Falls to `.notifications` inbox |
| `"prayer_snooze"` | `LiveActivityManager.scheduleSnoozeNotification` | No | Falls to `.notifications` inbox instead of reopening prayer |
| `"repost"` (push variant) | Cloud Function, type string `"repost"` | Yes via `NotificationDeepLinkRouter` ("amen" / "repost" case maps to `.post`) | Works but only if `postId` is in payload |

### Live Activity Lifecycle Gaps

| Activity | Start | Update | End | Deep-Link URL Handled? |
|----------|-------|--------|-----|------------------------|
| **BereanLiveActivity** | Stub only (`#if false` disables real code) | Stub | Stub | N/A — activity never starts |
| **ChurchService** | Implemented (real when ActivityKit linked) | Every 60s via timer task | After service + 2h | `amen://church?id=<id>` — `DeepLinkRouter` handles `"church"` host; route works |
| **PrayerReminder** | Implemented | On amen count change | On mark-answered or snooze | `amen://prayer?id=<id>` — `DeepLinkRouter` handles `"prayer"` host; route works |
| **WorshipMusic** | Implemented | On elapsed/pause events | Not called from any music player code path (no call site for `LiveActivityManager.endMusicActivity()` found in active players) | `amen://worship` — **NOT HANDLED** in DeepLinkRouter or NotificationDeepLinkRouter |
| **ReplyAssist** | Implemented with 2s debounce | On suggestion arrival | On user dismiss or 15-min timeout | N/A (not a deep-link activity) |

### Notification Settings Toggles That Are Local Only (No Server Gating)

The following toggles in `NotificationSettingsView` are saved to Firestore but are **not read by any server-side Cloud Function** to gate delivery. They are stored as preferences only:

- `allowNotifications` (master toggle) — no CF checks this field
- `prayerReminderNotifications` — stored on root user doc; no CF seen checking it (distinct from `NotificationSettingsService.preference("prayerInsights")`)
- `savedSearchAlertNotifications` — no CF gating found
- `soundEnabled`, `badgeEnabled` — client-only; server has no concept of these

The following toggles **are** server-gated (checked in `functionssrcnotifications.ts`):
- `followNotifications`, `amenNotifications`, `commentNotifications`, `messageNotifications`

Prayer notification prefs in `NotificationSettingsService` (`prayerAnswered`, `prayerIntercessors`, etc.) are checked by `PrayerAnsweredNotificationService` client-side before scheduling, but are **not** checked by Cloud Functions, so a push could still arrive from the server.

---

## Fix Recommendations

### Blocker Fixes

**B1 — Entitlements mismatch (highest urgency before any production build)**  
In Xcode → Project settings → Targets → AMENAPP → Build Settings, verify `CODE_SIGN_ENTITLEMENTS` for the Archive / Release scheme points to `AMENAPP.release.entitlements` (which has `aps-environment = production`). Do not ship with the debug entitlements file.

**B2 — Delete or disable `AppDelegate+Messaging.swift`**  
The `setupMessaging()` method duplicates the delegate and FCM setup already done in `AppDelegate.setupPushNotifications()`. Delete the file or replace it with a no-op comment block. Keep only the `didRegisterForRemoteNotificationsWithDeviceToken` and `didFailToRegisterForRemoteNotificationsWithError` method implementations (these are legitimate AppDelegate callbacks not defined elsewhere).

### High-Priority Fixes

**H1 — Consolidate FCM token saving to one path**  
Choose one class to own token storage. `PushNotificationHandler.saveFCMToken` has the better design (subcollection for multi-device support + legacy flat field for backward compat). Make `PushNotificationManager` call `PushNotificationHandler.saveFCMToken` rather than its own Firestore write. Remove the duplicate `MessagingDelegate` conformance from `PushNotificationHandler` since it is never wired as the FCM delegate.

**H2 — Delete `NotificationDeepLinkHandler.swift`**  
The file is already marked `@available(*, deprecated)`. Its observer fires on an NSNotification that no code ever posts. Remove it to eliminate confusion about which routing system is active.

**H3 — Fix notification category registration**  
Replace direct `setNotificationCategories` calls in `ChurchNotificationManager.swift:80`, `NotificationManager.swift:475`, and `BreakTimeNotificationManager.swift:239` with `NotificationCategoryRegistrar.shared.register([...])`.

**H4 — Add `amen://worship` handler to `DeepLinkRouter`**  
Add a `case "worship":` branch in `DeepLinkRouter.parse(url:)` that returns a `.category("worship")` route or a dedicated `.worship` case, and navigate to the Church Notes / music screen. Update `LiveActivityBridge.startMusic` to use a more specific URL like `amen://church-note?id=<churchNoteId>` when a `churchNoteId` is available.

**H5 — Enable BereanLiveActivity**  
Change `#if false` to `#if canImport(ActivityKit)` in `BereanLiveActivityManager.swift`. Verify the Widget Extension target exists (or create one). Link `ActivityKit.framework` to the main target and the extension. Without this the Berean Dynamic Island is permanently broken.

### Medium-Priority Fixes

**M1 — Add tap routing for `daily_reminder`, `verse_of_the_day`, `prayer_snooze`**  
In `NotificationDeepLinkRouter.routeFromPushPayload`:
```swift
case "daily_reminder", "verse_of_the_day":
    destination = .notifications  // or a dedicated scripture/devotional screen

case "prayer_snooze":
    if let prayerId = userInfo["prayerId"] as? String {
        destination = .prayer(prayerId: prayerId)
    } else {
        destination = .notifications
    }
```
Also add these cases to `NotificationRouteResolver.legacyRoute` in `ProductionNotificationRouting.swift`.

**M2 — Fix `.prayer` and `.churchNote` deep-link navigation**  
In `NotificationNavigationHandler.body` (inside `NotificationDeepLinkRouter.swift`), the `.prayer` and `.churchNote` cases set `selectedTab = 3` and then `pendingAction = nil`. They should post an `NSNotification` so the Resources tab can scroll to the specific item:
```swift
case .prayer(let prayerId):
    selectedTab = 3
    pendingAction = {
        NotificationCenter.default.post(name: .openPrayerFromNotification, object: nil, userInfo: ["prayerId": prayerId])
    }
case .churchNote(let noteId):
    selectedTab = 3
    pendingAction = {
        NotificationCenter.default.post(name: .openChurchNoteFromNotification, object: nil, userInfo: ["noteId": noteId])
    }
```

**M3 — Update `NSUserNotificationsUsageDescription`**  
Broaden the string in `Info.plist` to cover the full notification scope:  
`"AMEN will notify you about prayers, comments, messages, followers, and daily scripture. You can customize this in Settings."`

**M4 — Unify notification settings storage path**  
Migrate `NotificationSettingsView.saveNotificationSettings()` to write to `users/{uid}/settings/notifications` (the same path `NotificationSettingsService` reads from), so the CalmControl/SpiritualRhythm policy engines and the main settings view share the same document.

**M5 — Add server-side gating for `prayerReminderNotifications` and `savedSearchAlertNotifications`**  
Currently these are stored but not checked in Cloud Functions. Add checks in the relevant notification dispatch functions, or document clearly that they are client-side only.

### Low-Priority Fixes

**L1 — Add `endMusicActivity()` call site**  
`LiveActivityManager.endMusicActivity()` has no call site in the Church Notes music player or any playback service. Add a call when the user stops/completes worship music playback.

**L2 — Fix `areDailyRemindersScheduled` threshold**  
Change from `>= count / 2` to `>= 1` (or `== count`) to accurately reflect whether reminders are scheduled.

**L3 — Sync `messageNotifications` toggle to `BadgeCountManager`**  
When the user disables `messageNotifications`, call `BadgeCountManager.shared.clearMessages()` to suppress the badge that would otherwise persist from Firestore listeners.

---

## Stress Test Script

1. Fresh install → cold launch → confirm notification onboarding sheet appears after 1.5s (not immediately on `didFinishLaunching`).
2. Tap "Allow Notifications" → confirm system permission dialog appears → confirm FCM token is written to `users/{uid}/deviceTokens/{token}` AND the root `users/{uid}.fcmToken` field (only one write expected despite multiple call sites due to `lastSavedToken` guard).
3. Background the app → send a push of type `"follow"` → tap the notification → confirm app routes to the follower's profile.
4. Background the app → send a push of type `"comment"` with `commentId` → confirm app routes to the post and scrolls to the comment.
5. Background the app → send a push of type `"prayer_snooze"` with `prayerId` → tap → confirm routes to prayer (will fail until M1 fix is applied).
6. Start a worship music session → confirm Dynamic Island starts → tap the Dynamic Island → confirm app does NOT crash (will fall back to notifications tab until H4 fix is applied).
7. Sign out → sign back in → confirm `fcmToken` is removed from Firestore on sign-out and re-written on sign-in.
8. Go to Settings → Notifications → toggle off "Follow Notifications" → ask another account to follow you → confirm no push is received (server-side gating test).
9. Go to Settings → Notifications → toggle off "Prayer Reminders" → confirm local notifications are not re-scheduled.
10. Kill the app → receive a push for `"daily_reminder"` → relaunch by tapping → confirm no crash and sensible fallback destination (will be notifications inbox until M1 fix).

---

## Acceptance Criteria Checklist

- [ ] Debug entitlements file (`aps-environment = development`) is NOT used in Archive builds
- [ ] FCM token is written exactly once per refresh event (no double Firestore write)
- [ ] `NotificationDeepLinkHandler.swift` is deleted
- [ ] `AppDelegate+Messaging.swift` duplicate setup removed
- [ ] All three rogue `setNotificationCategories` calls migrated to `NotificationCategoryRegistrar`
- [ ] `amen://worship` URL has a working handler in `DeepLinkRouter`
- [ ] `BereanLiveActivityManager` `#if false` guard replaced with `#if canImport(ActivityKit)`
- [ ] Tapping `daily_reminder` / `verse_of_the_day` / `prayer_snooze` notifications routes to a meaningful screen
- [ ] Tapping a `prayer` or `churchNote` deep-link notification opens the specific item, not just the Resources tab root
- [ ] `NSUserNotificationsUsageDescription` describes the full notification scope
- [ ] `NotificationSettingsView` writes to `users/{uid}/settings/notifications` (same path as `NotificationSettingsService`)
- [ ] `LiveActivityManager.endMusicActivity()` is called when worship music stops
