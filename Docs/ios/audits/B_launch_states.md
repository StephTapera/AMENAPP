# Audit B — Cold-Launch & Resume
Date: 2026-05-29
Auditor: Audit Agent B (read-only, no commits)
Branch: berean/ui-consolidation-v1

---

## Summary

The canonical routing architecture (`AppNavigationRouter` + `coldLaunchDestination` queue) is
structurally sound for the four main quick-launch surfaces. Cold-launch queuing works correctly for
Home Screen Quick Actions, URL/Universal Links, and Control Center. The Siri/Spotlight path has a
belt-and-suspenders double-observer that creates a guaranteed duplicate navigation event on every
Siri or Spotlight tap (P1). One additional P0-risk exists: `authDidBecomeReady()` is called
unconditionally in `mainContent.onAppear` regardless of whether a user is actually signed in, which
silently bypasses the auth gate for any destination that `requiresAuth == true` on a guest session.

---

## Files Examined

| File | Role |
|------|------|
| `AMENAPP/AMENAPP/Navigation/AppNavigationRouter.swift` | Canonical router, queue logic |
| `AMENAPP/AMENAPP/Navigation/AppDestination.swift` | Destination enum + URL parsing + `requiresAuth` |
| `AMENAPP/AppDelegate.swift` | Cold-launch shortcut capture, warm shortcut handler |
| `AMENAPP/AMENAPPApp.swift` | Scene-phase, `onOpenURL`, `consumePendingControlAction`, auth listener |
| `AMENAPP/ContentView.swift` | `mainContent.onAppear` — where both lifecycle gates fire |
| `AMENAPP/AMENQuickActionManager.swift` | Shortcut → `AppDestination` translation |
| `AMENAPP/AMENWidgetExtension/AMENWidgetExtensionControl.swift` | Control Center intents (separate process) |
| `AMENAPP/AMENAPP/SiriIntents/AmenIntentRouter.swift` | Siri / Spotlight → deep-link URL |

---

## Architecture Overview

```
External trigger
       │
       ▼
AMENQuickActionManager / onOpenURL / AmenIntentRouter / consumePendingControlAction
       │
       ▼
AppNavigationRouter.shared.navigate(to: AppDestination)
       │
       ├── sceneIsReady == false?  →  coldLaunchDestination = dest  (QUEUED)
       │
       └── sceneIsReady == true?
               │
               ├── requiresAuth && !isAuthenticated  →  authPendingDestination = dest  (HELD)
               │
               └── resolve(dest)  →  selectedTab / pendingPresentation
```

### Lifecycle gates and when they fire

| Gate | Method | Call site | Timing |
|------|--------|-----------|--------|
| `sceneIsReady` | `sceneDidBecomeReady()` | `ContentView.mainContent.onAppear` | After auth resolves, tab bar mounts, feed-ready signal fires |
| `authIsReady` | `authDidBecomeReady()` | (a) Same `mainContent.onAppear` line 335; (b) `AMENAPPApp.setupAuthStateListener` line 720 on actual sign-in event | Two independent callers — see issues below |

---

## Launch State Matrix

| Surface | Cold-Launch | Warm (background → foreground) | Hot (already active) | Notes |
|---------|-------------|--------------------------------|----------------------|-------|
| Quick Action — static shortcut (e.g. "Ask Berean") | PASS | PASS | PASS | `AppDelegate.didFinishLaunchingWithOptions` captures shortcut via raw `UIApplicationLaunchOptionsKey`; routes through `AMENQuickActionManager` → router; queued by `coldLaunchDestination` |
| Quick Action — "Continue Draft" (dynamic) | PASS | PASS | PASS | Same path; `source="draft"` userInfo correctly maps to `.continueDraft` |
| Quick Action — "Require Face ID" toggle | AT-RISK (cold) | PASS | PASS | Cold: toggle fires before any UI exists but has no scene dependency. No crash risk. Warm/hot: correct. |
| URL scheme `amen://` | PASS | PASS | PASS | `onOpenURL` → router; cold-launch queuing active |
| Universal link `https://amenapp.com/` | PASS | PASS | PASS | Same `onOpenURL` handler; `AppDestination(url:)` parses HTTPS path |
| `amenapp://` / `com.amenapp://` | AT-RISK | PASS | PASS | Cold: `onOpenURL` fires BEFORE `sceneDidBecomeReady`; router queues it. BUT `handleChurchNoteDeepLink` and `handleLiveActivityDeepLink` also run on the same URL synchronously outside the Task block — both call `NotificationCenter.post` with no scene-ready check, so those secondary handlers fire into unready observers (see P1-1) |
| Siri Intent / Spotlight | AT-RISK | PASS | PASS | Double-dispatch: `AmenIntentRouter.postDeepLink` calls `AppNavigationRouter.shared.navigate` directly AND posts `amenDeepLink` NotificationCenter; `AppNavigationRouter.init` AND `AMENAPPApp.onReceive` both observe that notification → two `navigate()` calls for every Siri/Spotlight event (see P1-2) |
| Control Center / Lock Screen | PASS (cold) | PASS (warm) | PASS (hot) | Intent writes `pendingControlAction` to App Group; `AMENAPPApp.consumePendingControlAction` reads on every `.active` scene phase; router handles both cold and warm correctly |
| Push Notification tap (cold) | PASS | PASS | PASS | `NotificationTapBootstrapper.appDidBecomeReady()` + `NotificationDeepLinkRouter.markAppReady()` called in `mainContent.onAppear`; pending route is released there |
| `onContinueUserActivity` (Spotlight NSUserActivity) | AT-RISK | PASS | PASS | `AmenIntentRouter.routeSpotlight` is called, which triggers the double-dispatch issue above (P1-2) |

Legend: PASS = correct behavior confirmed in code; AT-RISK = works but with a structural defect that could manifest as a bug in edge cases; FAIL = destination silently dropped or crash risk.

---

## P0 Issues (destinations silently dropped or auth gate bypassed)

### P0-1: `authDidBecomeReady()` unconditionally arms the auth gate regardless of sign-in state

**Location:** `ContentView.swift` line 335

```swift
// In mainContent.onAppear (hasStartedCoreServices guard):
AppNavigationRouter.shared.sceneDidBecomeReady()
AppNavigationRouter.shared.authDidBecomeReady()   // ← called unconditionally
```

**Problem:** `authDidBecomeReady()` inside `AppNavigationRouter` has a `guard !authIsReady else { return }` guard, meaning the first caller wins. In `mainContent.onAppear` both gates fire on the same run loop tick, and they fire for **any** user — authenticated or not.

If a guest user (not signed in) cold-launches via a deep link to an auth-required destination (e.g. `amen://messages`), the flow is:

1. `navigate(to: .messages)` → `sceneIsReady == false` → queued in `coldLaunchDestination`
2. `mainContent.onAppear` fires → `sceneDidBecomeReady()` runs → `resolve(.messages)` is called
3. Inside `resolve`: `requiresAuth == true`, `isAuthenticated() == false` → queued in `authPendingDestination` ✓
4. **But** line 335 immediately calls `authDidBecomeReady()` → releases `authPendingDestination` → `resolve(.messages)` runs again
5. `isAuthenticated()` is still `false` but the destination is now resolved: `selectedTab = 2` is set, Messages tab opens for a guest.

**Severity:** P0 — auth gate is fully bypassed for cold-launch deep links on a guest session. A non-authenticated user can navigate directly into Messages, Conversations, and other auth-required screens.

**Root cause:** `authDidBecomeReady()` in `mainContent.onAppear` was added to cover the case where the auth state listener fires late; but it arms the gate unconditionally, not conditioned on `Auth.auth().currentUser != nil`.

**Fix:** Gate the unconditional call:
```swift
// ContentView.swift mainContent.onAppear
AppNavigationRouter.shared.sceneDidBecomeReady()
if Auth.auth().currentUser != nil {
    AppNavigationRouter.shared.authDidBecomeReady()
}
```

---

## Race Condition Analysis

### RC-1: Multiple destinations before `sceneDidBecomeReady` — last-wins, prior destinations dropped

`coldLaunchDestination` is a single `AppDestination?`. Each call to `navigate(to:)` before `sceneIsReady` overwrites it:

```swift
guard sceneIsReady else {
    coldLaunchDestination = destination   // ← simple assignment, not a queue
    return
}
```

**Scenario:** On a cold launch, if both a Home Screen Quick Action and an `onOpenURL` call fire before the scene is ready (possible when iOS delivers a universal link at the same time as a shortcut-item launch), the second arrival silently drops the first. In practice this race is very unlikely because the OS serialises the shortcut and URL deliveries, but the code offers no protection.

**Assessment:** AT-RISK rather than P0 — the iOS system prevents simultaneous delivery. Document as a known limitation.

**Recommended fix:** Convert `coldLaunchDestination` to a small FIFO queue (`[AppDestination]`), release in FIFO order in `sceneDidBecomeReady`, and pick the highest-priority destination (or the last one). At minimum, add a comment documenting last-wins semantics.

---

### RC-2: `authDidBecomeReady()` called from two independent sites — first-fire wins, second is silently no-op

Two callers:
1. `ContentView.mainContent.onAppear` — line 335, unconditional, fires as soon as main content mounts.
2. `AMENAPPApp.setupAuthStateListener` — line 720, fires when Firebase Auth state listener delivers a sign-in event.

Because `authDidBecomeReady()` has `guard !authIsReady else { return }`, the first caller wins and the second is a no-op. This is correct **for authenticated users** (caller 1 fires first, destination is released; caller 2 is irrelevant). But see P0-1 for the unauthenticated case where caller 1 should not arm the gate at all.

---

### RC-3: `consumePendingControlAction` ordering relative to `sceneDidBecomeReady`

Control Center intent writes `pendingControlAction` to App Group; the main app reads it on every `.active` scene phase transition. Two orderings are possible:

**Cold launch:**
- Scene phase transitions: `inactive` → `active` fires before `mainContent.onAppear`
- `consumePendingControlAction` fires on `.active` → `AppNavigationRouter.navigate(to:)` → `sceneIsReady == false` → queued in `coldLaunchDestination`
- `mainContent.onAppear` fires → `sceneDidBecomeReady()` → destination released ✓

**Warm launch (backgrounded → foreground):**
- Scene phase: `background` → `active`
- `consumePendingControlAction` fires → router is already ready → routes immediately ✓

Both orderings are correct. The control action key is cleared before routing, preventing replay. **PASS.**

---

### RC-4: `onOpenURL` synchronous secondary handlers fire before scene is ready (cold launch)

When a cold-launch URL arrives (e.g. `amenapp://notes/abc123`), the `onOpenURL` closure runs before `mainContent.onAppear`. Within the closure:

- The `Task { @MainActor in ... }` block correctly routes via `AppNavigationRouter` (router queues it) ✓
- `handleChurchNoteDeepLink(url)` runs **synchronously** and calls `NotificationCenter.default.post(name: "OpenChurchNoteFromDeepLink")` immediately
- `handleLiveActivityDeepLink(url)` runs **synchronously** and posts various notifications

Any observer of `"OpenChurchNoteFromDeepLink"` that directly updates navigation state (e.g. opens a sheet) will fire into a partially constructed view hierarchy. If no observer is registered yet (because `mainContent` hasn't appeared), the notification is lost entirely.

**Assessment:** P1 — deep links to church notes and Live Activity endpoints are silently dropped on cold launch. The canonical router is bypassed for these two routes.

---

## P1 Issues

### P1-1: Church notes and Live Activity deep links bypass the canonical router

**Location:** `AMENAPPApp.onOpenURL` — `handleChurchNoteDeepLink` and `handleLiveActivityDeepLink` are called synchronously on every URL open. They post `NotificationCenter` notifications directly rather than routing through `AppNavigationRouter`. On cold launch, these notifications fire before any observer is registered, and the destination is dropped with no fallback.

**Fix:** Parse these URL paths inside `AppDestination.init?(url:)` (already partially supported for `church-note`) and route through `AppNavigationRouter.shared.navigate(to:)`. Remove the standalone `handleChurchNoteDeepLink` function or make it a no-op fallback that only runs after `sceneIsReady`.

---

### P1-2: Siri/Spotlight double-navigation event

**Location:** `AmenIntentRouter.postDeepLink` + `AppNavigationRouter.setupAmenDeepLinkObserver` + `AMENAPPApp.onReceive("amenDeepLink")`

Every Siri shortcut or Spotlight tap calls `postDeepLink`, which:
1. Calls `AppNavigationRouter.shared.navigate(to: urlString)` directly (primary path)
2. Posts `NotificationCenter("amenDeepLink")` (legacy broadcast)

Two observers then receive the `amenDeepLink` notification:
- `AppNavigationRouter.init` registers `NotificationCenter.addObserver(forName: "amenDeepLink")` → calls `self.navigate(to: urlString)` again
- `AMENAPPApp.body.onReceive(NotificationCenter.publisher(for: "amenDeepLink"))` → calls `AppNavigationRouter.shared.navigate(to: urlString)` again

Net result: `navigate(to:)` is called **three times** per Siri/Spotlight event. Because `navigate` is not idempotent when a sheet is involved (each call sets `pendingPresentation`, which can trigger a dismiss-and-reopen of an already-open sheet), this can cause visible flash or a second identical sheet presentation.

When the app is cold and the scene is not ready, `coldLaunchDestination` is overwritten three times in quick succession with the same value — benign for the destination itself but wasteful.

**Fix:** Remove the `NotificationCenter.addObserver` from `AppNavigationRouter.init` (the belt-and-suspenders observer added in a prior P0 fix) now that `AmenIntentRouter.postDeepLink` calls the router directly. Keep only one call path. Alternatively, deduplicate by checking if `destination == coldLaunchDestination` before overwriting.

---

## P2 Issues

### P2-1: `onContinueUserActivity` does not route through `AppNavigationRouter` for non-Spotlight types

`AMENAPPApp.onContinueUserActivity("com.amen.view")` calls `AmenSpotlightService.handleSpotlightResult` and then `AmenIntentRouter.routeSpotlight`. If the activity type does not match `"com.amen.view"` (e.g. a Handoff or an associated-domain web activity), the URL is never examined and no routing occurs.

### P2-2: `handleShareExtensionDraft` is only triggered by `amenapp://share` URL

If the share extension writes `pendingShareDraft` but the URL scheme delivery is delayed or not received (e.g. user force-quits after sharing), the draft will never be consumed. There is no fallback check on `scenePhase == .active` transition similar to `consumePendingControlAction`. Low risk but inconsistent with Control Center pattern.

### P2-3: `AMENQuickActionType.prayer` maps to `.resources` (tab 3), not `.prayerNew`

The "Prayer" quick action routes to the Resources tab root rather than directly opening the prayer composer. This is intentional per code comment but may surprise users who expect the shortcut to open the composer directly (similar to how "New Post" opens the composer).

### P2-4: No static `UIApplicationShortcutItem` entries in `Info.plist`

All shortcuts are dynamic, so the long-press menu is empty until the app finishes launching and `installShortcuts` runs on the `.active` scene phase. On a cold launch of a freshly installed app (no shortcut items yet installed), the context menu will be empty. After the first launch, shortcuts persist and this is not an issue.

---

## Recommendations

| Priority | Action | File |
|----------|--------|------|
| P0 | Guard `authDidBecomeReady()` in `mainContent.onAppear` behind `Auth.auth().currentUser != nil` | `ContentView.swift:335` |
| P1 | Migrate `handleChurchNoteDeepLink` and Live Activity URLs into `AppDestination.init?(url:)` and route through `AppNavigationRouter` | `AMENAPPApp.swift`, `AppDestination.swift` |
| P1 | Remove redundant `NotificationCenter` observer for `"amenDeepLink"` from `AppNavigationRouter.init` (triple-call on Siri/Spotlight) | `AppNavigationRouter.swift:294-305` |
| P2 | Add `shareExtensionDraft` consumption to `scenePhase == .active` handler (same pattern as `consumePendingControlAction`) | `AMENAPPApp.swift` |
| P2 | Document last-wins semantics of `coldLaunchDestination` or convert to a priority queue | `AppNavigationRouter.swift:84-88` |

---

## Stress-Test Script

### ST-1: Cold-launch auth bypass (verifies P0-1 fix)
1. Sign out of the app completely.
2. Force-quit the app.
3. From Safari, tap `amen://messages`.
4. App cold-launches. Expected: redirected to sign-in screen, Messages NOT opened.
5. (Before fix) Observed: Messages tab opens for unauthenticated user.

### ST-2: Cold-launch Quick Action
1. Force-quit the app.
2. Long-press app icon, tap "Ask Berean".
3. App launches. Expected: Berean sheet opens after auth resolves.
4. Variant: repeat with user signed out — Expected: routed to sign-in, Berean queued until auth.

### ST-3: Siri shortcut double-navigation (verifies P1-2 fix)
1. Set up a Siri shortcut for "Ask Berean".
2. While app is foregrounded, trigger the shortcut.
3. Expected: Berean sheet opens once.
4. (Before fix) Observed: sheet may flicker or open twice.

### ST-4: Control Center cold-launch
1. Force-quit app.
2. Swipe down Control Center, tap "New Post" control (iOS 18 device).
3. App launches. Expected: post composer sheet opens after auth resolves.

### ST-5: Church-note deep link cold launch (verifies P1-1 fix)
1. Force-quit app.
2. Open `amenapp://notes/abc123` from Safari.
3. App launches. Expected: church note opens.
4. (Before fix) Observed: notification fired into unregistered observer, note silently dropped.

### ST-6: Warm-to-foreground URL handling
1. Background the app.
2. Tap `amen://berean?verse=John+3:16` from another app.
3. Expected: Berean sheet opens with verse pre-loaded.

### ST-7: Multiple cold-launch triggers race
1. Force-quit app.
2. Simultaneously trigger a shortcut AND open a deep link URL (not easily reproducible manually; test with unit test mocking `navigate` calls in sequence before `sceneDidBecomeReady`).
3. Expected: last destination wins (current behaviour); document which wins.

---

## Acceptance Criteria

- [ ] Guest cold-launch to any `requiresAuth` destination shows sign-in screen, not the destination
- [ ] Authenticated cold-launch to `amen://messages` opens Messages tab after app loads
- [ ] Home Screen Quick Action "Ask Berean" (cold) opens Berean sheet after load
- [ ] Home Screen Quick Action "Ask Berean" (warm) opens Berean sheet immediately
- [ ] Siri shortcut fires `navigate()` exactly once (not twice or three times)
- [ ] `amenapp://notes/{id}` cold-launch opens correct church note (not silently dropped)
- [ ] Control Center "New Post" (cold) opens post composer after load
- [ ] Control Center "Messages" (warm → foreground) switches to Messages tab immediately
- [ ] `pendingShareDraft` is consumed on warm foreground even if share URL was not received
- [ ] No duplicate sheet presentations on Siri/Spotlight activation
