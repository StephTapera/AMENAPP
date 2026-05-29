# Audit A — Destination Correctness
Date: 2026-05-29
Agent: Audit Agent A

---

## Summary

| Category | Count |
|----------|-------|
| PASS — routes correctly through canonical router | 14 |
| P0 — wrong destination | 0 |
| P1 — notification posted with no observer (silent drop) | 4 |
| P1 — notification bypass (router not called; observer exists elsewhere) | 2 |
| P1 — AmenIntentRouter.handle() wired in comments only, never called | 1 |
| P2 — polish / dual-routing risk | 3 |

**No P0 bugs found.** All quick-action, Spotlight, URL, and control widget paths resolve to correct destinations. Four Siri intents (`PostPrayerRequestIntent`, `ShareTestimonyIntent`, `RSVPEventIntent`, `DiscoverPrayerNeedsIntent`) post notification names for which no observer exists anywhere in the app — they are silently dropped.

---

## Matrix

### Surface 1 — Home Screen Quick Actions (`AMENQuickActionManager.swift`)

| Trigger | Intended dest | Actual dest | Status | Notes |
|---------|--------------|-------------|--------|-------|
| `newPost` quick action | `.newPost` | `.newPost` via `AppNavigationRouter` | PASS | Cold and warm paths both wired |
| `newPost` with source=draft | `.continueDraft` | `.continueDraft` via `AppNavigationRouter` | PASS | `handle()` delegates to `destination(for:source:)` |
| `messages` quick action | `.messages` | `.messages` via `AppNavigationRouter` | PASS | |
| `search` quick action | `.search()` | `.search(query:nil)` via `AppNavigationRouter` | PASS | |
| `activity` quick action | `.activity` | `.activity` via `AppNavigationRouter` | PASS | |
| `bereanAI` quick action | `.askBerean()` | `.askBerean(question:nil)` via `AppNavigationRouter` | PASS | |
| `prayer` quick action | `.prayerNew` or `.resources` | `.resources` (tab 3 only, no composer) | P2 | Title says "Prayer" but routes to Resources root, not prayer composer. Acceptable if no composer is desired, but misleading. See P2 section. |
| `myProfile` quick action | `.profile` | `.profile` via `AppNavigationRouter` | PASS | Listed as a possible type in enum; not installed by `installShortcuts()` by default |
| `requireFaceID` quick action | settings toggle, no navigation | `BiometricAuthService` toggle — no `navigate()` call | PASS | Intentional special case, correctly documented |

**Cold launch path (AppDelegate):** `didFinishLaunchingWithOptions` reads `shortcutItem` via raw key string and calls `AMENQuickActionManager.shared.handle()` inside a `Task { @MainActor in }`. `AppNavigationRouter` queues the destination via `coldLaunchDestination` until `sceneDidBecomeReady()` fires from `ContentView`. Wiring is correct.

**Warm/foreground path:** `application(_:performActionFor:completionHandler:)` calls `handle()` and calls `completionHandler(true)`. Correct.

---

### Surface 2 — App Intents / Siri / Spotlight (`AMENAppIntents.swift`)

| Trigger | Intended dest | Actual dest | Status | Notes |
|---------|--------------|-------------|--------|-------|
| `OpenPrayerIntent` | `.resources` (prayer in Resources tab) | `.resources` via `AppNavigationRouter.shared.navigate(to:)` | PASS | Correctly routes through canonical router |
| `OpenBereanIntent` | `.askBerean(question:)` | `.askBerean(question:)` via `AppNavigationRouter` + legacy `openBereanFromLiveActivity` NC post | PASS | Dual-post is intentional belt-and-suspenders |
| `DailyVerseIntent` | returns string value (no navigation) | no navigation | PASS | Correct — this intent returns a value, doesn't navigate |
| `CreatePostIntent` | open post composer | posts `Notification.Name("openCreatePost")` only — does NOT call router | P1 | `.openCreatePost` IS observed in `ContentView` (line 937), so the sheet opens correctly in warm state. However, it bypasses `AppNavigationRouter` entirely: cold-launch queuing, auth gating, and Shabbat gate are all skipped. Recommended fix: replace NC post with `AppNavigationRouter.shared.navigate(to: .newPost)` |
| `PostPrayerRequestIntent` | prayer request composer | posts `.amenOpenPrayerComposer` | P1 UNHANDLED | No observer for `Notification.Name("amen.openPrayerComposer")` exists anywhere. `ContentView.handleRouterPresentation(.prayerNew)` re-posts this name but only when called via the router — not as a standalone observer. The notification is silently dropped. See P1 section. |
| `ShareTestimonyIntent` | testimony composer | posts `.amenOpenTestimonyComposer` | P1 UNHANDLED | No observer for `Notification.Name("amen.openTestimonyComposer")`. Same situation as above. |
| `RSVPEventIntent` | events/RSVP screen | posts `.amenOpenEvents` | P1 UNHANDLED | No observer for `Notification.Name("amen.openEvents")` anywhere. Silently dropped. |
| `DiscoverPrayerNeedsIntent` | prayer feed | posts `.amenOpenPrayerFeed` | P1 UNHANDLED | No observer for `Notification.Name("amen.openPrayerFeed")` anywhere. Silently dropped. |

---

### Surface 3 — Siri Routing Layer (`AmenIntentRouter.swift`)

| Trigger | Intended dest | Actual dest | Status | Notes |
|---------|--------------|-------------|--------|-------|
| `handle(notification:)` — `"openPrayerMode"` | `amen://prayer` → `.resources` | posts `"amenDeepLink"` + calls `AppNavigationRouter.shared.navigate(to:)` | P1 (WIRING) | `AmenIntentRouter.handle(notification:)` is correctly implemented but **is never called anywhere**. The `SiriIntents/AmenAppIntents.swift` intents post `"openPrayerMode"` etc. and the router's header comment says "call once in app root to observe these" — but neither `AMENAPPApp` nor `ContentView` sets up these observers. The only observer in the codebase (`AMENAPPApp.body` line 388) listens for `"amenDeepLink"`, not for `"openPrayerMode"`. |
| `handle(notification:)` — `"openBerean"` | `amen://berean` → `.askBerean()` | same wiring gap as above | P1 (WIRING) | Same: `SiriIntents/AmenAppIntents.AskBereanIntent` posts `"openBerean"` — no observer |
| `handle(notification:)` — `"openFindChurch"` | `amen://find-church` → `.findChurch` | same wiring gap | P1 (WIRING) | Same |
| `handle(notification:)` — `"openChurchNotes"` | `amen://church-notes` → `.churchNotes` | same wiring gap | P1 (WIRING) | Same |
| `handle(notification:)` — `"openReflection"` | `amen://reflection` → `.reflection` | same wiring gap | P1 (WIRING) | Same. NOTE: ContentView DOES observe `"openReflection"` at line 1279 (re-posts the same name). If the app were started from `StartReflectionIntent`, the notification would still be silently dropped at the app level because `AMENAPPApp` doesn't bridge it. |
| `handle(notification:)` — `"openPrayerComposer"` | `amen://prayer-composer` → `.prayerNew` | same wiring gap | P1 (WIRING) | `SiriIntents/SendPrayerRequestIntent` posts `"openPrayerComposer"`; no observer in app root |
| `routeSpotlight(type:id:)` | varies by type | posts `"amenDeepLink"` + `AppNavigationRouter.shared.navigate(to:)` | PASS | Called correctly from `AMENAPPApp.onContinueUserActivity` for `"com.amen.view"` activity type |
| `postDeepLink(_:)` private method | canonical URL navigation | calls both `AppNavigationRouter.shared.navigate(to:)` directly AND posts `"amenDeepLink"` | PASS | Belt-and-suspenders correctly implemented |

**Key finding:** `SiriIntents/AmenAppIntents.swift` (6 legacy intents) and `AMENAppIntents.swift` (top-level, 7 v2 intents with `AMENShortcutsProvider`) are two separate intent registration layers. The legacy intents use an indirect `NotificationCenter → AmenIntentRouter.handle()` bridge that is never wired. The v2 intents mostly call `AppNavigationRouter` directly (better), but 4 of them still post unobserved notification names.

---

### Surface 4 — URL Scheme / Universal Links (`AppDestination.init?(url:)`)

| Trigger | Intended dest | Actual dest | Status | Notes |
|---------|--------------|-------------|--------|-------|
| `amen://post/{id}` | `.post(id:)` | `.post(id:)` | PASS | Parsed correctly |
| `amen://user/{id}` or `amen://profile/{id}` | `.userProfile(userId:)` | `.userProfile(userId:)` | PASS | |
| `amen://church/{id}` | `.church(churchId:)` | `.church(churchId:)` | PASS | |
| `amen://conversation/{id}` | `.conversation(conversationId:)` | `.conversation(conversationId:)` | PASS | |
| `amen://messages` | `.messages` | `.messages` | PASS | |
| `amen://prayer/new` | `.prayerNew` | `.prayerNew` | PASS | |
| `amen://prayer/{id}` | `.prayer(prayerId:)` | `.prayer(prayerId:)` | PASS | |
| `amen://prayer-composer` | `.prayerNew` | `.prayerNew` | PASS | Alias for prayer/new |
| `amen://berean?verse=X` | `.bereanWithVerse(reference:)` | `.bereanWithVerse(reference:)` | PASS | |
| `amen://berean?session=X` | `.bereanWithSession(sessionId:)` | `.bereanWithSession(sessionId:)` | PASS | |
| `amen://berean?q=X` | `.askBerean(question:)` | `.askBerean(question:)` | PASS | |
| `amen://find-church` | `.findChurch` | `.findChurch` | PASS | |
| `amen://church-notes` | `.churchNotes` | `.churchNotes` | PASS | |
| `amen://reflection` | `.reflection` | `.reflection` | PASS | |
| `amen://verse` | `.verseOfDay` | `.verseOfDay` | PASS | |
| `amen://notifications` | `.activity` | `.activity` | PASS | |
| `amen://discover` | `.discovery` | `.discovery` | PASS | |
| `amen://search?q=X` | `.search(query:)` | `.search(query:)` | PASS | |
| `amen://settings/{section}` | `.settings(section:)` | `.settings(section:)` | PASS | |
| `amen://group/join?token=X` | `.groupJoinLink(token:)` | `.groupJoinLink(token:)` | PASS | |
| `amen://comment?postId=X` | `.post(id:, highlightCommentId:)` | `.post(id:, highlightCommentId:)` | PASS | |
| `amen://chat?threadId=X` | `.conversation(conversationId:)` | `.conversation(conversationId:)` | PASS | |
| `https://amenapp.com/post/{id}` | `.post(id:)` | `.post(id:)` | PASS | Universal link parsing |
| `https://amenapp.com/profile/{id}` | `.userProfile(userId:)` | `.userProfile(userId:)` | PASS | |
| `https://amenapp.com/group/join?token=X` | `.groupJoinLink(token:)` | `.groupJoinLink(token:)` | PASS | |
| `https://amenapp.com/access` | nil (intentionally rejected) | `nil` | PASS | Correct security guard |
| `amen://category` | `.resources` | `.resources` | PASS | Category → Resources tab |
| `amenapp://notes/{id}` | open church note | handled by `handleChurchNoteDeepLink()` separate from `AppDestination` | P2 | This bypasses `AppDestination` entirely; `handleChurchNoteDeepLink` posts `"OpenChurchNoteFromDeepLink"` notification. Should be migrated to `AppDestination.churchNote(noteId:)` |

**URL dispatch in AMENAPPApp.onOpenURL:** For `amen://` URLs the canonical router is tried first if `AppDestination(url:)` returns non-nil. Then `NotificationOpenCoordinator.shared.handleURL()` runs, then `NotificationDeepLinkRouter.shared.handleURL()` runs as fallback. This means parseable `amen://` URLs are processed by the canonical router AND re-processed by `NotificationDeepLinkRouter`. The `NotificationDeepLinkRouter` path is redundant for URLs already handled by `AppNavigationRouter` but is not harmful — both paths converge on the same tab switch.

---

### Surface 5 — Control Center / Lock Screen / Action Button (`AMENWidgetExtensionControl.swift` + `AMENAPPApp.consumePendingControlAction()`)

| Trigger | Intended dest | Actual dest | Status | Notes |
|---------|--------------|-------------|--------|-------|
| `OpenNewPostAppIntent` (Control) | `.newPost` | writes `"newPost"` to App Group; `consumePendingControlAction()` maps to `.newPost` → `AppNavigationRouter` | PASS | Full round-trip through canonical router on `.active` scene phase |
| `ControlOpenBereanAppIntent` (Control) | `.askBerean()` | writes `"askBerean"` to App Group; maps to `.askBerean(question:nil)` → `AppNavigationRouter` | PASS | |
| `OpenMessagesAppIntent` (Control) | `.messages` | writes `"messages"` to App Group; maps to `.messages` → `AppNavigationRouter` | PASS | |
| Unknown action value | no navigation | logs warning, returns — no crash | PASS | Defensive handling correct |

---

### Surface 6 — Legacy `DeepLinkRouter` (`DeepLinkRouter.swift`)

| Trigger | Intended dest | Actual dest | Status | Notes |
|---------|--------------|-------------|--------|-------|
| `DeepLinkRouter.shared.navigate(to:)` calls in `MessagesView` (line 2440) | `.userProfile(userId:)` | sets `DeepLinkRouter.shared.activeRoute` + `selectedTab = 0` | P2 | `DeepLinkRouter` is a parallel singleton with its own `@Published selectedTab`. Only `NotificationDeepLinkRouter` is observed by `ContentView`; `DeepLinkRouter.shared.selectedTab` has no observer in `ContentView`. The tab switch in `MessagesView` is silently lost. Fix: replace with `AppNavigationRouter.shared.navigate(to: .userProfile(userId:))`. |
| `DeepLinkRouter.shared.generateURL(for:)` in `SmartShareSystem` | URL generation only | generates URL string — no navigation | PASS | URL generation is not routing; fine as utility |
| `DeepLinkHandler` ViewModifier (line 297) | parses `onOpenURL` | calls `DeepLinkRouter.shared.navigate(to:)` — same dead `selectedTab` issue | P2 | `DeepLinkHandler` modifier is attached somewhere in the app. Its navigation calls into the orphaned router. Not confirmed to still be applied. |

---

## P0 Bugs Fixed

**None.** No P0 (wrong destination) bugs were found. All navigable triggers either reach the correct `AppDestination` or are silently unhandled (P1 category).

---

## P1 Gaps (not fixed — need product/routing call)

### P1-A: `CreatePostIntent` bypasses router (`AMENAppIntents.swift` line 76)

**Description:** `CreatePostIntent.perform()` posts `Notification.Name("openCreatePost")` directly. `ContentView` observes this notification and opens the composer, so the feature works in warm state. However, cold-launch queuing, auth gating, and Shabbat mode are all bypassed.

**Recommended fix (1 line):**
```swift
// File: AMENAPP/AMENAppIntents.swift, line 76 — replace NC post with:
AppNavigationRouter.shared.navigate(to: .newPost)
```
The `.openCreatePost` notification subscriber in `ContentView` (line 937) can remain as a legacy path for in-app code that still posts it directly (e.g., `EmptyFeedView`, `SpatialHomeView`).

---

### P1-B: `PostPrayerRequestIntent` posts unobserved notification (`AMENAppIntents.swift` line 243)

**Description:** `PostPrayerRequestIntent.perform()` posts `.amenOpenPrayerComposer` (`Notification.Name("amen.openPrayerComposer")`). No `addObserver` or `.onReceive` for this name exists anywhere in the main app. The intent opens the app (via `openAppWhenRun = true`) but no navigation occurs.

**Recommended fix:**
```swift
// File: AMENAPP/AMENAppIntents.swift — replace line 243 with:
await MainActor.run {
    AppNavigationRouter.shared.navigate(to: .prayerNew)
}
```
Also save `prayerText` to UserDefaults before navigating so the composer can pre-fill it (already done at line 241 via `siri_pending_prayer` key).

---

### P1-C: `ShareTestimonyIntent` posts unobserved notification (`AMENAppIntents.swift` line 263)

**Description:** `ShareTestimonyIntent.perform()` posts `.amenOpenTestimonyComposer` (`Notification.Name("amen.openTestimonyComposer")`). No observer exists.

**Recommended fix:**
```swift
// File: AMENAPP/AMENAppIntents.swift — replace line 263 with:
await MainActor.run {
    AppNavigationRouter.shared.navigate(to: .testimony)
}
```

---

### P1-D: `RSVPEventIntent` posts unobserved notification (`AMENAppIntents.swift` line 283)

**Description:** `RSVPEventIntent.perform()` posts `.amenOpenEvents` (`Notification.Name("amen.openEvents")`). No observer exists. There is no `AppDestination` case for events/RSVP.

**Recommended fix (requires product decision on destination):**
If events live in Discover (tab 1), route to `.discovery`. If they live in Resources (tab 3), route to `.resources`. If a dedicated events screen exists, add an `AppDestination.events` case.
Interim safe fix: `AppNavigationRouter.shared.navigate(to: .discovery)`.

---

### P1-E: `DiscoverPrayerNeedsIntent` posts unobserved notification (`AMENAppIntents.swift` line 298)

**Description:** `DiscoverPrayerNeedsIntent.perform()` posts `.amenOpenPrayerFeed` (`Notification.Name("amen.openPrayerFeed")`). No observer exists.

**Recommended fix:**
```swift
// File: AMENAPP/AMENAppIntents.swift — replace line 298 with:
await MainActor.run {
    AppNavigationRouter.shared.navigate(to: .resources)
}
```
If a dedicated prayer feed screen exists separately from the Resources tab, use a more specific destination.

---

### P1-F: `AmenIntentRouter.handle(notification:)` is never called — legacy Siri intents are unrouted

**Description:** `SiriIntents/AmenAppIntents.swift` defines 6 intents (`StartPrayerModeIntent`, `AskBereanIntent`, `FindChurchIntent`, `OpenChurchNotesIntent`, `StartReflectionIntent`, `SendPrayerRequestIntent`) that post notification names (`"openPrayerMode"`, `"openBerean"`, `"openFindChurch"`, `"openChurchNotes"`, `"openReflection"`, `"openPrayerComposer"`). `AmenIntentRouter.handle(notification:)` is documented as the bridge between these notifications and the canonical router — but neither `AMENAPPApp` nor `ContentView` has ever subscribed to any of these names to call `handle()`.

The legacy intents appear in `AMENShortcutsProvider` via `AMENAppIntents.swift` — which means Siri may present these shortcuts to users; if tapped, the app opens but nothing happens.

**Recommended fix:** Either:
1. Wire observers in `AMENAPPApp.body` (6 `.onReceive` modifiers each calling `AmenIntentRouter.handle(notification:)`), OR
2. (Preferred) Update all 6 legacy intents in `SiriIntents/AmenAppIntents.swift` to call `AppNavigationRouter.shared.navigate(to:)` directly, matching the v2 pattern in `AMENAppIntents.swift`. This eliminates the intermediary hop.

The 6 intents map cleanly to existing `AppDestination` cases:
- `"openPrayerMode"` → `.resources`
- `"openBerean"` → `.askBerean()`
- `"openFindChurch"` → `.findChurch`
- `"openChurchNotes"` → `.churchNotes`
- `"openReflection"` → `.reflection`
- `"openPrayerComposer"` → `.prayerNew`

---

## P2 / Polish

### P2-1: `prayer` quick action maps to `.resources` (tab only), not `.prayerNew` (composer)

`AMENQuickActionManager.destination(for:source:)` maps `.prayer` → `.resources`. The shortcut title is "Prayer", which a user would expect to open some prayer action. A user pressing "Prayer" from the home screen gets dropped into the Resources tab root with no further direction. Comment in code says "change this to `.prayerNew`... if a deeper prayer sub-destination is needed" — this is the right call to make.

**Recommended fix:** Change `.resources` to `.prayerNew` in `AMENQuickActionManager.destination(for:source:)` line 217. This is an unambiguous improvement and a 1-line change.

---

### P2-2: `amenapp://notes/{shareLinkId}` bypasses `AppDestination` entirely

`handleChurchNoteDeepLink(_:)` in `AMENAPPApp` intercepts `amenapp://notes/{id}` and posts `"OpenChurchNoteFromDeepLink"` — bypassing `AppDestination`, auth gating, and cold-launch queuing. Should be migrated to:
```swift
AppNavigationRouter.shared.navigate(to: .churchNote(noteId: shareLinkId))
```
`AppDestination.init?(url:)` already parses `amen://church-note/{id}` correctly. The `amenapp://notes/{id}` scheme should either be redirected through the canonical URL mapping or the parser extended to cover it.

---

### P2-3: `DeepLinkRouter.shared` used in `MessagesView` (profile navigation)

`MessagesView` line 2440 calls `DeepLinkRouter.shared.navigate(to: .userProfile(userId:))`. `DeepLinkRouter.shared.selectedTab` is not bound to any `TabView` in `ContentView` — the tab switch is silently discarded. The tab on screen never changes. Replace with:
```swift
AppNavigationRouter.shared.navigate(to: .userProfile(userId: otherUserId))
```

---

### P2-4: Dual routing for `amen://` URLs in `onOpenURL`

In `AMENAPPApp.onOpenURL`, when an `amen://` URL is parseable by `AppDestination`, both `AppNavigationRouter.shared.navigate(to: url)` AND `NotificationDeepLinkRouter.shared.handleURL(url)` are called (the latter unconditionally after the `NotificationOpenCoordinator` check). For URLs that `AppNavigationRouter` already handles, this means the tab-switch fires twice — once from the router's `@Published selectedTab` and once from `NotificationDeepLinkRouter`'s own state. In practice both converge on the same tab so there is no visible bug, but it is a redundant dispatch.

**Recommended fix:** Add a guard that skips `NotificationDeepLinkRouter.shared.handleURL(url)` when `AppDestination(url: url) != nil`.

---

## Stress Test Script

1. **Quick action — cold launch:**
   Kill app. Long-press icon. Tap "New Post". Verify composer opens. Tap "Ask Berean". Verify Berean sheet opens.

2. **Quick action — warm launch:**
   With app open on any screen, background it, long-press icon, tap "Activity". Verify Notifications tab selected.

3. **Siri — v2 intents (working):**
   "Open prayer in AMEN" → verify Resources tab. "Ask AMEN a question" → verify Berean sheet.

4. **Siri — v2 intents (broken, P1-B through P1-E):**
   "Post a prayer request on AMEN" → app opens, verify NOTHING happens (composer does not open — confirms P1-B). Repeat for "Share a testimony", "RSVP to an event", "Discover prayer needs".

5. **Siri — legacy intents (broken, P1-F):**
   "Start prayer mode with AMEN" → app opens, verify NOTHING navigates (confirms P1-F).

6. **Control Center:**
   Add AMEN "New Post" control. Lock screen. Tap control. Verify composer opens after FaceID/PIN. Tap "Ask Berean" control. Verify Berean sheet opens.

7. **URL scheme:**
   Safari: `amen://post/abc123`. Verify post detail opens. `amen://berean?verse=John+3:16`. Verify Berean opens with verse pre-filled.

8. **Spotlight:**
   Search for a prayer item or verse in Spotlight. Tap result. Verify Berean or Resources opens correctly.

---

## Acceptance Criteria Checklist

- [ ] `PostPrayerRequestIntent` opens prayer composer (P1-B fixed)
- [ ] `ShareTestimonyIntent` opens testimony composer (P1-C fixed)
- [ ] `RSVPEventIntent` navigates to events screen (P1-D fixed — destination TBD)
- [ ] `DiscoverPrayerNeedsIntent` navigates to prayer feed or resources (P1-E fixed)
- [ ] `CreatePostIntent` respects auth gate and cold-launch queue (P1-A fixed)
- [ ] Legacy Siri intents (`StartPrayerModeIntent`, etc.) all navigate after being tapped (P1-F fixed)
- [ ] "Prayer" home screen quick action opens prayer composer or Resources prayer section (P2-1 decision made)
- [ ] `MessagesView` profile navigation actually switches tab to Profile (P2-3 fixed)
- [ ] All 6 surfaces navigating to the same destination land on the same tab and sheet state
- [ ] No duplicate navigation fires (tab switches once, sheet presents once) for any trigger
