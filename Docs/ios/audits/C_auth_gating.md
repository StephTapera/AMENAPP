# Audit C — Auth & Face ID Gating
Date: 2026-05-29
Auditor: Audit Agent C (Read-First Report)

---

## Summary

The AMEN app has two conceptually separate locking mechanisms:

1. **Auth gate** — Firebase-backed sign-in wall. Implemented correctly in `AppNavigationRouter.resolve()` via `requiresAuth`. Every sensitive destination declared in `AppDestination.requiresAuth` is held in `authPendingDestination` until `authDidBecomeReady()` fires.

2. **Biometric / app-lock gate** — Face ID / Touch ID "app lock" toggled via `BiometricAuthService`. This is where the critical gap lives:

   - `AppNavigationRouter.isDestinationBlocked` defaults to `{ _ in false }`.
   - **No code anywhere in the codebase ever reassigns this closure** to check `BiometricAuthService.isBiometricEnabled`.
   - Result: When app lock is enabled, **every external entry point** (Quick Actions, Siri, Spotlight, URL schemes, Controls) bypasses Face ID entirely and opens sensitive screens without prompting.

Additionally:

- `BiometricAuthService` is described in `AccountSettingsView` as "Enabled for quick sign-in" — it was built as a **login convenience**, not an **app-lock**. But the `AMENQuickActionManager` "Require Face ID" quick action and the comment in `AppNavigationRouter` ("Shabbat / app-lock gate") both treat `isDestinationBlocked` as the intended Face ID lock enforcement point.
- `SelahAppLockGateView` is the only component that actually calls `LAContext.evaluatePolicy` as a content gate, but it only protects the Selah private reflections journal — it is not wired to the router.
- The Shabbat/Sunday Church Focus gate (`isDestinationBlocked`) is **also never wired** — the router's `selectedTabView` in ContentView does a view-layer Shabbat check, but this fires only for tab navigation, not for deep links / Siri / Spotlight / Quick Actions that route through `AppNavigationRouter.navigate(to:)`.

---

## Gating Matrix

| Destination | Quick Action | Siri | URL scheme | Spotlight | In-app tap | Auth Gate | Face ID Gate |
|-------------|-------------|------|------------|-----------|------------|-----------|--------------|
| `.messages` | Yes (installed) | Via amenDeepLink | `amen://messages` | No | Tab tap | BLOCKED (requiresAuth=true) | **MISSING** |
| `.conversation(id)` | No | Via amenDeepLink | `amen://conversation/{id}` | No | Push tap | BLOCKED (requiresAuth=true) | **MISSING** |
| `.askBerean` | Yes (bereanAI action) | Via amenDeepLink | `amen://berean` | Via Spotlight | Tab + button | BLOCKED (requiresAuth=true) | **MISSING** |
| `.newPost` | Yes | Via amenDeepLink | `amen://post` | No | Compose button | BLOCKED (requiresAuth=true) | **MISSING** |
| `.continueDraft` | Yes (when draft exists) | No | No | No | Compose button | BLOCKED (requiresAuth=true) | **MISSING** |
| `.activity` | Yes | Via amenDeepLink | `amen://notifications` | No | Tab tap | BLOCKED (requiresAuth=true) | **MISSING** |
| `.profile` | Yes (myProfile) | Via amenDeepLink | `amen://profile` | No | Tab tap | BLOCKED (requiresAuth=true) | **MISSING** |
| `.prayer(id)` | Partial (via resources) | Via amenDeepLink | `amen://prayer/{id}` | No | Resources tab | BLOCKED (requiresAuth=true) | **MISSING** |
| `.prayerNew` | No | Via amenDeepLink | `amen://prayer/new` | No | Resources tab | BLOCKED (requiresAuth=true) | **MISSING** |
| `.userProfile(id)` | No | Via amenDeepLink | `amen://user/{id}` | Via Spotlight | Push tap | BLOCKED (requiresAuth=true) | **MISSING** |
| `.post(id)` | No | Via amenDeepLink | `amen://post/{id}` | Via Spotlight | Feed tap | BLOCKED (requiresAuth=true) | **MISSING** |
| `.churchNotes` | No | Via amenDeepLink | `amen://church-notes` | No | Resources tab | BLOCKED (requiresAuth=true) | **MISSING** |
| `.churchNote(id)` | No | Via amenDeepLink | `amen://church-note/{id}` | No | Push tap | BLOCKED (requiresAuth=true) | **MISSING** |
| `.groupJoinLink(token)` | No | No | `amen://group/join?token=X` | No | Shared link | BLOCKED (requiresAuth=true) | **MISSING** |
| `.bereanWithVerse` | No | Via amenDeepLink | `amen://berean?verse=X` | Via Spotlight | No | BLOCKED (requiresAuth=true) | **MISSING** |
| `.bereanWithSession` | No | Via amenDeepLink | `amen://berean?session=X` | No | No | BLOCKED (requiresAuth=true) | **MISSING** |
| `.reflection` | No | Via amenDeepLink | `amen://reflection` | No | Resources tab | BLOCKED (requiresAuth=true) | **MISSING** |
| `.home` | No | No | `amen://home` | No | Tab tap | NOT REQUIRED | N/A |
| `.discovery` | No | No | `amen://discover` | No | Tab tap | NOT REQUIRED | N/A |
| `.search` | Yes | Via amenDeepLink | `amen://search` | No | Search bar | NOT REQUIRED | N/A |
| `.verseOfDay` | No | Via amenDeepLink | `amen://verse` | No | Banner | NOT REQUIRED | N/A |
| `.settings` | No | Via amenDeepLink | `amen://settings` | No | Profile tab | NOT REQUIRED | N/A |
| Shabbat block any dest | Quick Action | Siri | URL scheme | Spotlight | Tab tap (only) | — | **MISSING** |

Key:
- "Auth Gate" = BLOCKED means `requiresAuth=true` and the router queues correctly.
- "Face ID Gate" = MISSING means `isDestinationBlocked` is never set; Face ID is not prompted.
- The Shabbat gate works only for **manual tab taps** inside ContentView's `selectedTabView`. It does not intercept deep links routed through `AppNavigationRouter`.

---

## P0 Security Gaps

### P0-1: `AppNavigationRouter.isDestinationBlocked` is never set — Face ID gating is a complete no-op

**Severity:** P0 — User-visible security contract violated

**File:** `AMENAPP/AMENAPP/Navigation/AppNavigationRouter.swift` line 75

```swift
/// Returns true when the app policy blocks this destination (e.g. Shabbat gate).
var isDestinationBlocked: (AppDestination) -> Bool = { _ in false }
```

**Root cause:** No code anywhere calls `AppNavigationRouter.shared.isDestinationBlocked = { ... }`. The closure was designed as an injection point but was never wired.

**Impact:**
- User enables "Require Face ID" via quick action or `AccountSettingsView` toggle.
- `BiometricAuthService.shared.isBiometricEnabled` becomes `true`.
- User (or attacker with physical device access) triggers a Quick Action, Siri shortcut, URL scheme, or Spotlight tap for `.messages`, `.askBerean`, `.newPost`, `.activity`, `.profile`, `.conversation(id)`, `.userProfile(id)`, `.post(id)`, or any other auth-required destination.
- The router's `resolve()` method calls `isDestinationBlocked(destination)` → returns `false` → **screen opens without any Face ID prompt.**
- Sensitive content (DMs, prayer journal, activity feed, profile) is visible without authentication.

**What does work:**
- `SelahAppLockGateView` blocks the private reflections journal when app lock is enabled, but only within the Selah journal flow, not for router-routed deep links.
- `BiometricAuthService.authenticate()` is called on the login screen for "Sign in with Face ID" — but this is a login convenience, not an app-lock.

### P0-2: Shabbat gate bypassed for all router-routed navigation

**Severity:** P0 — Feature behavior contract violated for deep-link surfaces

**Files:** `ContentView.swift` line 500; `AppNavigationRouter.swift` line 161

**Root cause:** The Shabbat gate in `ContentView.selectedTabView` fires only when `viewModel.selectedTab` changes from a tab tap. `AppNavigationRouter.resolve()` calls `isDestinationBlocked(destination)` which is also `{ _ in false }` — so Quick Actions, Siri shortcuts, and URL schemes that trigger `.messages`, `.newPost`, `.askBerean`, etc. on a Sunday bypass the Shabbat restriction entirely.

**Impact:** A user with Shabbat mode ON can still receive a push notification, tap it, and have the router navigate to a restricted destination — arriving there without hitting the `SundayChurchFocusGateView`.

---

## P1 Issues

### P1-1: Auth-gate UX is silent (no screen shown while waiting for sign-in)

**File:** `AppNavigationRouter.swift` line 154–158

When a destination requiring auth arrives before the user is signed in, the router queues it in `authPendingDestination` silently. The user sees no loading indicator, no "sign in to continue" prompt, and no feedback that their destination was queued. If sign-in never completes (e.g., cold launch unauthenticated), the destination may be silently dropped.

The UX contract is undefined: does the sign-in screen appear? Does the app just sit at the splash? This is not a security gap but a UX gap.

### P1-2: `BiometricAuthService` semantic mismatch — "quick sign-in" vs "app lock"

**Files:** `AccountSettingsView.swift` line 38; `AMENQuickActionManager.swift` lines 32–34; `AppNavigationRouter.swift` line 74 (comment)

`BiometricAuthService` is built and labeled as "quick sign-in" (convenience login), but it is referenced as "app lock" in `AMENQuickActionManager` and `AppNavigationRouter`. These are two different security models:

- **Login convenience**: Face ID completes a Firebase sign-in. Does not protect an already-authenticated session.
- **App lock**: Face ID gates access to content after the app is already authenticated. Used by banking apps, 1Password, etc.

The codebase conflates both. Currently, `isBiometricEnabled` only gates the Sign In screen button. An app-lock system needs a separate `isAppLocked: Bool` state that is set to `true` on background entry and cleared only after a successful biometric challenge.

### P1-3: `handleScenePhaseChange` does not set an app-lock flag on background entry

**File:** `ContentView.swift` line 1304–1348

When the app enters `.background`, no lock flag is set. When it returns to `.active`, no biometric check is performed. The correct pattern (used by banking / notes apps) is:

1. On `.background` → `isAppLocked = isBiometricEnabled`
2. On `.active` → if `isAppLocked`, present fullscreen gate, call `BiometricAuthService.authenticate()`, on success set `isAppLocked = false`.

Neither step exists.

### P1-4: `isDestinationBlocked` on the router redirects to tab 3 (Resources) as the Shabbat block response

**File:** `AppNavigationRouter.swift` line 163

```swift
selectedTab = 3
```

When a destination is blocked, the router silently switches to the Resources tab. There is no toast, no sheet, no gate view explaining to the user why their destination was blocked. The `shabbatDeepLinkBlocked` notification is posted, but the ContentView receiver (`line 863`) only repeats the same `viewModel.selectedTab = 3` redirect — it does not surface any user-visible explanation. `SundayChurchFocusGateView` is never shown for deep-link-triggered routes.

---

## Fixes Applied

None. All gaps require UX decisions about:
- What screen to show while app is locked (fullscreen cover vs. overlay)
- Whether Face ID failure should fall back to passcode
- Whether Shabbat-blocked deep links should show the `SundayChurchFocusGateView` or a different banner

---

## Recommended Fixes (not yet implemented)

### Fix 1 — Wire `isDestinationBlocked` to Shabbat gate (unambiguous, small)

In `ContentView.mainContent.onAppear` (around line 334 where `sceneDidBecomeReady()` is called), add:

```swift
AppNavigationRouter.shared.isDestinationBlocked = { destination in
    guard SundayChurchFocusManager.shared.shouldGateFeature() else { return false }
    // Map AppDestination → AppFeature
    let feature: AppFeature? = {
        switch destination {
        case .messages, .conversation:       return .messages
        case .newPost, .continueDraft:       return .postCreate
        case .testimony:                     return .testimonies
        case .prayerNew, .prayer:            return .prayer
        case .askBerean, .bereanWithVerse,
             .bereanWithSession:             return .bereanAI
        case .activity:                      return .notifications
        case .userProfile:                   return .profileBrowse
        case .discovery, .search:            return .peopleDiscovery
        case .post:                          return .feed
        case .reflection:                    return .createActivity
        case .findChurch, .churchNotes,
             .churchNote, .resources,
             .church, .settings,
             .home, .verseOfDay, .profile,
             .groupJoinLink:                 return nil  // allowed
        }
    }()
    guard let feature else { return false }
    return AppAccessController.shared.canAccess(feature) == .blocked(reason: ShabbatBlockReason(feature: feature)) ? true : false
    // Simplification: use the canAccess check
}
```

(The exact implementation needs the `AppAccessResult` comparison fixed — `.blocked` is not `Equatable` — but the wiring point is clear.)

### Fix 2 — Add a true app-lock state separate from login biometrics

Create a `BiometricAppLockManager` (or extend `BiometricAuthService`) with:
- `@Published var isAppLocked: Bool`
- `func lockIfEnabled()` — called on `.background`
- `func unlockWithBiometrics() async -> Bool` — calls `authenticate()`

Wire in `ContentView.handleScenePhaseChange`:
```swift
case .background:
    BiometricAppLockManager.shared.lockIfEnabled()
case .active:
    // handled by a fullscreen cover on isAppLocked
```

Show a fullscreen cover (not a router navigation) when `isAppLocked` is true, so the lock screen appears above all content including sheets.

### Fix 3 — Wire `isDestinationBlocked` to app-lock check (after Fix 2)

Once `BiometricAppLockManager` exists:

```swift
AppNavigationRouter.shared.isDestinationBlocked = { destination in
    // Shabbat gate
    if /* shabbat check */ { return true }
    // App lock gate — only block sensitive destinations
    if destination.requiresAuth && BiometricAppLockManager.shared.isAppLocked {
        return true  // triggers Face ID prompt before navigation resolves
    }
    return false
}
```

When blocked, the router currently just switches to tab 3 silently. For app lock, the correct response is to **queue the destination** (not drop it) and present the lock screen; once unlocked, re-resolve the queued destination. This is analogous to how `authPendingDestination` works.

### Fix 4 — Show `SundayChurchFocusGateView` for Shabbat-blocked deep links

In the `.shabbatDeepLinkBlocked` NotificationCenter receiver in `ContentView.mainContent` (line 863), present `SundayChurchFocusGateView` as a sheet so the user understands why their destination was blocked:

```swift
.onReceive(NotificationCenter.default.publisher(for: .shabbatDeepLinkBlocked)) { _ in
    viewModel.selectedTab = 3
    activeModal = .sundayPrompt  // or a dedicated shabbatGate modal
}
```

---

## Stress Test Script

1. Enable Face ID lock via Settings → Account → Face ID toggle ON.
2. Background the app completely.
3. From Home Screen, long-press AMEN icon → tap "Messages".
   - Expected: Face ID prompt before Messages opens.
   - Actual: Messages opens directly (P0-1).
4. Re-open app. Ask Siri "Open Berean in AMEN".
   - Expected: Face ID prompt.
   - Actual: Berean opens directly (P0-1).
5. Open Safari, navigate to `amen://conversation/test123`.
   - Expected: Face ID prompt (if already logged in).
   - Actual: Conversation tab opens directly (P0-1).
6. Enable Shabbat mode. Sunday.
7. Background app. Receive a push notification for a new message. Tap it.
   - Expected: Shabbat gate view shown.
   - Actual: Router switches to Messages tab, bypassing gate (P0-2).
8. With Shabbat mode ON on a Sunday, use Spotlight to search for a user and tap.
   - Expected: Shabbat gate view.
   - Actual: Profile opens (P0-2).

---

## Acceptance Criteria Checklist

- [ ] `AppNavigationRouter.isDestinationBlocked` is set during app initialization to check both Shabbat and app-lock state.
- [ ] When Shabbat is active, Quick Actions / Siri / URL schemes / Spotlight for blocked destinations redirect to `SundayChurchFocusGateView` (not a silent tab switch).
- [ ] When app lock is enabled and app is foregrounded, a Face ID / passcode prompt appears before any content is revealed.
- [ ] When Face ID succeeds after a deep-link was queued, the original destination resolves automatically.
- [ ] When Face ID fails or is cancelled, the app shows the lock screen — the queued destination is NOT dropped (user can retry).
- [ ] `BiometricAuthService.isBiometricEnabled` semantics are split: one flag for login convenience, one for app-lock.
- [ ] `AccountSettingsView` toggle label changes from "Enabled for quick sign-in" to a label that reflects whether it is configured as login convenience, app lock, or both.
- [ ] All listed destinations in the gating matrix show "Face ID Gate: GATED" after fixes.
- [ ] `SelahAppLockGateView` is reviewed to determine if it should also check the router-level app lock state, or remain as an independent journal gate.
