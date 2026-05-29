# Audit E — Automated UI Regression Harness

**Date:** 2026-05-29
**Branch:** berean/ui-consolidation-v1
**Status:** Infrastructure wired; 2 tests enabled, 7 tests skipped pending seeded-auth

---

## Files Changed

| File | Change |
|------|--------|
| `AMENAPPUITests/AMENAppRoutingTests.swift` | NEW — 9 routing regression tests |
| `AMENAPP/AMENAPPApp.swift` | Added `UITEST_DEEP_LINK` env-var handler in `.onAppear` |
| `AMENAPP/ModernPrayerWallView.swift` | Added `.accessibilityIdentifier("screen.composer.prayer")` to `NewPrayerSheet` |

---

## Canonical Accessibility Identifiers

### Screen-level identifiers (all confirmed present after this audit)

| Identifier | File | Line (approx.) | Status |
|---|---|---|---|
| `screen.home` | `AMENAPP/ContentView.swift` | ~1909 | Pre-existing |
| `screen.discovery` | `AMENAPP/AMENDiscoveryView.swift` | ~210 | Pre-existing |
| `screen.messages` | `AMENAPP/MessagesView.swift` | ~376 | Pre-existing |
| `screen.resources` | `AMENAPP/ResourcesView.swift` | ~198 | Pre-existing |
| `screen.activity` | `AMENAPP/AMENAPP/AMENNotificationsView.swift` | ~663 | Pre-existing |
| `screen.profile` | `AMENAPP/ProfileView.swift` | ~196 | Pre-existing |
| `screen.berean` | `AMENAPP/BereanChatView.swift` | ~1178 | Pre-existing |
| `screen.composer.post` | `AMENAPP/CreatePostView.swift` | ~1055 | Pre-existing |
| `screen.composer.prayer` | `AMENAPP/ModernPrayerWallView.swift` | `NewPrayerSheet` body | **Added this audit** |

---

## Tests Written

File: `AMENAPPUITests/AMENAppRoutingTests.swift`

### Enabled (run on every build)

| Test | Deep Link | Asserts | Notes |
|---|---|---|---|
| `testHomeURL` | `amen://home` | `screen.home` exists | No auth required; `.home.requiresAuth == false` |
| `testDiscoveryURL` | `amen://discover` | `screen.discovery` exists | No auth required; `.discovery.requiresAuth == false` |
| `testURLSchemeContractDocumentation` | (no launch) | Documentation assertion | Inline contract documentation, always passes |

### Skipped — require seeded-auth wiring

| Test | Skip Reason | What to wire |
|---|---|---|
| `testMessagesURL` | Auth required | `SEEDED_TEST_USER=1` + Firebase emulator test account in this target |
| `testActivityURL` | Auth required | Same as above |
| `testBereanURL` | Auth required | Same as above |
| `testControlCenterNewPost` | Auth required | Same + confirm App Group entitlement is shared between main target and UI test host |
| `testAuthGateBlocksMessages` | `--uitesting-no-auth` not yet wired | Add launch-arg handler in `AuthenticationViewModel.init()` that clears `cachedUser` and forces a signed-out state |
| `testPrayerURLResolvesToResources` | Auth required | Same as seeded-auth above |

---

## Infrastructure Wired

### `UITEST_DEEP_LINK` environment variable (AMENAPPApp.swift)

Added to the `.onAppear` block of the `WindowGroup` body, guarded by `#if DEBUG`:

```swift
#if DEBUG
if let deepLink = ProcessInfo.processInfo.environment["UITEST_DEEP_LINK"],
   let url = URL(string: deepLink) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        AppNavigationRouter.shared.navigate(to: url)
    }
}
#endif
```

The 1.5 s delay matches the existing notification onboarding delay already in `onAppear` and gives `sceneDidBecomeReady()` + `authDidBecomeReady()` time to fire before the router attempts to resolve the destination.

---

## URL Scheme Contract (AppDestination.init?(url:))

| URL | Destination | Tab | requiresAuth |
|---|---|---|---|
| `amen://home` | `.home` | 0 | false |
| `amen://discover` | `.discovery` | 1 | false |
| `amen://messages` | `.messages` | 2 | true |
| `amen://notifications` | `.activity` | 4 | true |
| `amen://prayer` | `.resources` | 3 | true |
| `amen://prayer/new` | `.prayerNew` | 3 (sheet) | true |
| `amen://berean` | `.askBerean(nil)` | 0 (sheet) | true |
| `amen://settings` | `.settings(nil)` | 5 | false |
| `amen://search` | `.search(nil)` | 1 | false |

---

## Next Steps to Enable All Tests

1. **Seeded-auth for UI test target**: Populate Firebase emulator with a test account and expose it via `SEEDED_TEST_USER=1`. The existing `launchReleaseHarness()` in `ReleaseUITestSupport.swift` already sets this flag; the routing tests need to adopt the same harness pattern once the seeded user is confirmed to survive the routing delay.

2. **`--uitesting-no-auth` flag**: Add a guard in `AuthenticationViewModel.init()`:
   ```swift
   #if DEBUG
   if CommandLine.arguments.contains("--uitesting-no-auth") {
       // Clear any cached user so the app starts in signed-out state
       hasCachedUser = false
       cachedUsername = nil
       cachedPhotoURL = nil
   }
   #endif
   ```
   This enables `testAuthGateBlocksMessages` without touching Firebase Auth state.

3. **App Group entitlement in UI test host**: Confirm `group.com.amenapp.shared` is added to the UI test host target's entitlements so `testControlCenterNewPost` can write to shared UserDefaults.

---

## Acceptance Criteria

- [ ] `testHomeURL` passes on simulator without any test account
- [ ] `testDiscoveryURL` passes on simulator without any test account
- [ ] All 7 skipped tests are skipped (not failing) on every build
- [ ] `ModernPrayerWallView.NewPrayerSheet` carries `screen.composer.prayer`
- [ ] `AMENAPPApp.swift` `UITEST_DEEP_LINK` handler is `#if DEBUG` guarded (no production binary impact)
- [ ] Zero new build errors or warnings introduced
