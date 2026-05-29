# Audit D — Cross-Surface Parity
Date: 2026-05-29
Auditor: Audit Agent D

---

## Summary

Five entry surfaces were audited against four canonical actions:
**New Post**, **Ask Berean**, **Messages**, **Activity/Notifications**, **Prayer**, and **Testimony/Share**.

Key findings:

- **Ask Berean** and **Messages**: fully consistent across all surfaces — all resolve to the same `AppDestination` via `AppNavigationRouter`. ✅
- **New Post**: parity failure — `CreatePostIntent` (App Intent) bypasses the router and posts a raw `NotificationCenter` notification instead of calling `AppNavigationRouter.shared.navigate(to: .newPost)`. All other surfaces use the router. **1-line fix applied.**
- **Prayer (open Resources)**: consistent across Quick Action, `OpenPrayerIntent`, URL, and Control Center (no CC button — P2 gap). The router path is canonical.
- **Post Prayer Request**: parity failure — `PostPrayerRequestIntent` posts `.amenOpenPrayerComposer` (name `"amen.openPrayerComposer"`), but **no observer for that exact name exists anywhere in the app**. The router correctly resolves `.prayerNew` via URL `amen://prayer-composer`, but the intent bypasses the router entirely. **prayerText data stranding: fix is recommended but not implemented (requires AppDestination associated value).**
- **Testimony**: same pattern — `ShareTestimonyIntent` posts `.amenOpenTestimonyComposer` (`"amen.openTestimonyComposer"`) with no observer. The `AppDestination.testimony` case and URL `amen://testimony` both exist. `testimonyText` data is written to `UserDefaults("siri_pending_testimony")` but never consumed. **Fix recommended, not implemented.**
- `siri_pending_prayer` and `siri_pending_testimony` UserDefaults keys are written but never read — dead code.
- **Duplicate composer notification name mismatch**: `SiriIntents/AmenAppIntents.swift` posts `"openPrayerComposer"` (no `amen.` prefix), which `AmenIntentRouter` catches and re-routes via `amen://prayer-composer` → `.prayerNew` → router. The newer `AMENAppIntents.swift` posts `"amen.openPrayerComposer"` which has **no handler anywhere**.
- **Activity / Notifications**: consistent on Quick Action and URL. No App Intent or Control Center button exists (P2 gap).

---

## Parity Matrix

| Action | Quick Action | App Intent | Siri phrase | Control Center | URL | Canonical dest | Status |
|--------|-------------|-----------|-------------|----------------|-----|----------------|--------|
| New Post | `→ .newPost` via router | `CreatePostIntent` → `NC(.openCreatePost)` — bypasses router | "Create Post" → `CreatePostIntent` → same bypass | `OpenNewPostAppIntent` → AppGroup `"newPost"` → router `→ .newPost` | `amen://home` → `.home` (no composer!) | `.newPost` | **FAIL — intent bypasses router; URL maps to wrong dest** |
| Ask Berean | `→ .askBerean()` via router | `OpenBereanIntent` → router `→ .askBerean(question:)` + NC broadcast | "Ask Berean in AMEN" → `OpenBereanIntent` → router | `ControlOpenBereanAppIntent` → AppGroup `"askBerean"` → router `→ .askBerean(nil)` | `amen://berean?q=…` → `.askBerean(question:)` | `.askBerean(question:)` | **PASS** (note: CC carries no question, URL and Intent carry question — acceptable) |
| Messages | `→ .messages` via router | None | None | `OpenMessagesAppIntent` → AppGroup `"messages"` → router `→ .messages` | `amen://messages` → `.messages` | `.messages` | **PASS** (missing App Intent — P2) |
| Activity / Notifications | `→ .activity` via router | None | None | None | `amen://notifications` → `.activity` | `.activity` | **PASS** (missing App Intent + CC button — P2) |
| Prayer (open tab) | `→ .resources` via router | `OpenPrayerIntent` → router `→ .resources` | "Open prayer in AMEN" → `OpenPrayerIntent` → router | None | `amen://prayer` → `.resources` | `.resources` | **PASS** (missing CC button — P2) |
| Post Prayer Request | None | `PostPrayerRequestIntent` → `NC("amen.openPrayerComposer")` — **no observer** | "Post a prayer request on AMEN" → `PostPrayerRequestIntent` → same | None | `amen://prayer/new` → `.prayerNew` via router | `.prayerNew` | **FAIL — Intent posts dead notification; prayerText lost** |
| Testimony | None | `ShareTestimonyIntent` → `NC("amen.openTestimonyComposer")` — **no observer** | "Share a testimony on AMEN" → `ShareTestimonyIntent` → same | None | `amen://testimony` → `.testimony` via router | `.testimony` | **FAIL — Intent posts dead notification; testimonyText lost** |
| Prayer (old-style Siri) | — | `SendPrayerRequestIntent` (SiriIntents/) → `NC("openPrayerComposer")` → `AmenIntentRouter` → `amen://prayer-composer` → router `→ .prayerNew` | — | — | — | `.prayerNew` | Functional but indirect 3-hop path |
| Search | `→ .search()` via router | None | None | None | `amen://search?q=…` → `.search(query:)` | `.search(query:)` | **PASS** (missing App Intent + CC — P2) |
| Profile | `→ .profile` via router | None | None | None | `amen://profile` → `.profile` (via user/:id) | `.profile` | **PASS** (missing App Intent + CC — P2) |

---

## Parity Failures (P1)

### P1-A: `CreatePostIntent` bypasses `AppNavigationRouter`

**File:** `AMENAPP/AMENAppIntents.swift`, `CreatePostIntent.perform()`

**Current behavior:**
```swift
// CreatePostIntent.perform() — line 76
NotificationCenter.default.post(name: .openCreatePost, object: nil)
```

`NotificationCenter.default.publisher(for: .openCreatePost)` is observed in `ContentView.swift` line 937 and sets `showCreatePost = true`, which does work. However:

1. This path skips the cold-launch queue in `AppNavigationRouter`. If Siri fires the intent before `sceneDidBecomeReady()`, the notification lands with no observer mounted yet, and is **silently dropped**.
2. It skips the auth gate — an unauthenticated user in a mid-launch state could land on the composer before auth completes.
3. All other "New Post" surfaces (Quick Action, Control Center) use the router. This intent is inconsistent.

**Canonical destination:** `.newPost`

**Fix applied** (1-line change, no data to pass):
```swift
// BEFORE:
NotificationCenter.default.post(name: .openCreatePost, object: nil)
// AFTER:
AppNavigationRouter.shared.navigate(to: .newPost)
```

---

### P1-B: `PostPrayerRequestIntent` posts a notification name with no observer

**File:** `AMENAPP/AMENAppIntents.swift`, `PostPrayerRequestIntent.perform()`

**Current behavior:**
```swift
NotificationCenter.default.post(name: .amenOpenPrayerComposer, object: prayerText)
// name = "amen.openPrayerComposer"
```

No file in the main app target observes `"amen.openPrayerComposer"`. The intent silently no-ops — the prayer composer never opens.

The *older* `SiriIntents/AmenAppIntents.swift` uses `"openPrayerComposer"` (no prefix), which `AmenIntentRouter` does handle → routes via `amen://prayer-composer` → `.prayerNew`. The newer file drifted to a different name that was never wired up.

Additionally, `prayerText` is written to `UserDefaults("siri_pending_prayer")` but that key is never read anywhere; the pre-filled text is lost.

**Canonical destination:** `.prayerNew`

**Cannot be fixed in 1 line** because `prayerText` needs to be passed. See Recommended Fixes.

---

### P1-C: `ShareTestimonyIntent` posts a notification name with no observer

**File:** `AMENAPP/AMENAppIntents.swift`, `ShareTestimonyIntent.perform()`

**Current behavior:**
```swift
NotificationCenter.default.post(name: .amenOpenTestimonyComposer, object: testimonyText)
// name = "amen.openTestimonyComposer"
```

No file in the main app target observes `"amen.openTestimonyComposer"`. The intent silently no-ops.

`testimonyText` is written to `UserDefaults("siri_pending_testimony")` but never read.

**Canonical destination:** `.testimony`

**Cannot be fixed in 1 line** because `testimonyText` needs to be passed. See Recommended Fixes.

---

### P1-D: URL `amen://home` does not open the post composer; `amen://home` → `.home` (tab switch only)

There is no URL that directly maps to `.newPost` (the post composer). `amen://home` only switches to the home tab. This means the URL surface is missing a "create new post" entry point entirely.

**Canonical destination:** `.newPost`

**Fix:** Add a URL mapping for `amen://post/new` → `.newPost` in `AppDestination.init?(url:)`. No immediate code impact on existing routes.

---

## Missing Surfaces (P2)

| Action | Missing surfaces |
|--------|-----------------|
| Messages | App Intent (no `MessagesIntent`), Siri phrase |
| Activity / Notifications | App Intent, Siri phrase, Control Center button |
| Prayer (open tab) | Control Center button |
| Search | App Intent, Siri phrase, Control Center button |
| Profile | App Intent, Siri phrase, Control Center button |
| New Post (URL) | `amen://post/new` URL not mapped (see P1-D) |

The highest-priority gap: **Activity/Notifications** has no App Intent or Siri phrase despite having a Quick Action. A user cannot say "Show me my notifications in AMEN" to Siri.

The **Control Center** only exposes three actions: New Post, Ask Berean, Messages. Adding Activity and Prayer buttons would improve parity, but iOS 18 limits users to a small number of custom controls so these are acceptable P2 omissions.

---

## Fixes Applied

### Fix 1 — `CreatePostIntent`: route through `AppNavigationRouter`

**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAppIntents.swift`

Changed `CreatePostIntent.perform()` to call `AppNavigationRouter.shared.navigate(to: .newPost)` instead of posting `.openCreatePost` directly.

The `NotificationCenter` path remains functional for in-app callers that directly post `.openCreatePost` (e.g. `EmptyFeedView`, `SpatialHomeView`). Only the App Intent path is changed, so no regression for those callers.

---

## Recommended Fixes (not yet implemented)

### Rec-1: Add `.prayerNew(prefill: String?)` and `.testimony(prefill: String?)` associated values to `AppDestination`

`PostPrayerRequestIntent` and `ShareTestimonyIntent` both accept optional text from Siri. The only way to pass that text through the canonical router is to add associated values to the relevant `AppDestination` cases:

```swift
// AppDestination.swift
case prayerNew(prefill: String? = nil)
case testimony(prefill: String? = nil)
```

Then both intents become 1-line router calls:

```swift
// PostPrayerRequestIntent
AppNavigationRouter.shared.navigate(to: .prayerNew(prefill: prayerText))

// ShareTestimonyIntent
AppNavigationRouter.shared.navigate(to: .testimony(prefill: testimonyText))
```

The prayer/testimony composer views read the prefill from the router's `pendingPresentation` value (via `ContentView.handlePendingPresentation`). Remove the `UserDefaults("siri_pending_prayer")` and `UserDefaults("siri_pending_testimony")` dead code once the router path is wired up.

**Impact:** Requires updating `AppDestination` `==` and `hash(into:)`, `targetTab`, `requiresAuth`, `analyticsLabel`, and `AppNavigationRouter.resolve()`. Moderate but clean change.

---

### Rec-2: Add `amen://post/new` URL mapping (P1-D)

In `AppDestination.init?(url:)`, add:

```swift
case "post" where path.first == "new":
    self = .newPost
```

Place this before the existing `case "post":` ID-based handler.

---

### Rec-3: Wire `NotificationsIntent` / Siri phrase for Activity tab (P2)

Add an `OpenActivityIntent` parallel to `OpenPrayerIntent`:

```swift
struct OpenActivityIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Notifications"
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        await MainActor.run { AppNavigationRouter.shared.navigate(to: .activity) }
        return .result()
    }
}
```

Register in `AMENShortcutsProvider` with phrases `"Show my notifications in \(.applicationName)"`, `"Open activity in \(.applicationName)"`.

---

### Rec-4: Retire dead `siri_pending_*` UserDefaults keys

`siri_pending_prayer`, `siri_pending_testimony`, and `siri_pending_rsvp_event` are written in `AMENAppIntents.swift` but never read. Once Rec-1 is implemented and the router carries prefill data, remove these writes to avoid stale-data confusion across app restarts.

---

### Rec-5: Consolidate duplicate prayer-composer notification names

Two different name strings are used for the same action:

| Poster | Name string | Handler |
|--------|-------------|---------|
| `SiriIntents/AmenAppIntents.swift` (old) | `"openPrayerComposer"` | `AmenIntentRouter` → `amen://prayer-composer` → router ✅ |
| `AMENAppIntents.swift` (new) | `"amen.openPrayerComposer"` | None ❌ |
| `SpatialHomeView.swift` | `"amen.openPrayerComposer"` | None ❌ |
| `AmenContextualPromptCard.swift` | `"amen.openPrayerComposer"` | None ❌ |
| `ContentView.swift` (router handler for `.prayerNew`) | posts `"amen.openPrayerComposer"` | None ❌ |

After Rec-1 is done, all these callers should be migrated to `AppNavigationRouter.shared.navigate(to: .prayerNew())` and both notification names retired. Until then, `SpatialHomeView`, `AmenContextualPromptCard`, and `ContentView`'s `.prayerNew` handler should switch from `"amen.openPrayerComposer"` to `"openPrayerComposer"` (the one with an active handler) to restore functionality immediately.

---

## Stress Test Script

1. **Cold launch — New Post via Siri:** Say "Create Post on AMEN" immediately after a fresh app kill. Verify composer sheet opens (not silently dropped).
2. **Cold launch — Ask Berean with question:** Say "Ask AMEN a question" with question "What does John 3:16 mean?". Verify Berean opens with question pre-filled.
3. **Control Center — New Post:** Add the AMEN "New Post" control to Control Center (iOS 18). Lock screen → Control Center → tap "New Post". Verify composer opens after authentication.
4. **Control Center — Ask Berean:** Tap "Ask Berean" from Control Center. Verify Berean sheet opens (no question expected from this surface — acceptable).
5. **URL scheme — New Post:** Open `amen://home` from Safari. Verify only the home tab opens (no composer). Then open `amen://post/new` (after Rec-2 fix) — verify composer opens.
6. **Siri — Post Prayer Request:** Say "Post a prayer request on AMEN" with spoken text. Verify prayer composer opens AND text is pre-filled (currently broken — P1-B).
7. **Siri — Share Testimony:** Say "Share a testimony on AMEN" with spoken text. Verify testimony composer opens AND text is pre-filled (currently broken — P1-C).
8. **Quick Action — Prayer:** Long-press app icon → tap "Prayer". Verify Resources tab (tab 3) opens, not the prayer composer.

---

## Acceptance Criteria Checklist

- [ ] `CreatePostIntent.perform()` calls `AppNavigationRouter.shared.navigate(to: .newPost)` — no direct NC post
- [ ] `PostPrayerRequestIntent.perform()` calls router with prefill text (requires Rec-1)
- [ ] `ShareTestimonyIntent.perform()` calls router with prefill text (requires Rec-1)
- [ ] `amen://post/new` URL maps to `.newPost` in `AppDestination.init?(url:)` (requires Rec-2)
- [ ] No `siri_pending_*` UserDefaults writes exist without corresponding reads (requires Rec-4)
- [ ] Only one `AppShortcutsProvider` is registered (`AMENShortcutsProvider`) — confirmed ✅
- [ ] `AmenIntentRouter.postDeepLink` calls `AppNavigationRouter` before NC broadcast — confirmed ✅
- [ ] Control Center consumes `pendingControlAction` on scene-active via `consumePendingControlAction()` — confirmed ✅
- [ ] All three Control Center actions (`"newPost"`, `"askBerean"`, `"messages"`) map to correct `AppDestination` — confirmed ✅
- [ ] Cold-launch queue is exercised: Siri cold-launch delivers to router, which queues until `sceneDidBecomeReady()` — confirmed in router architecture ✅
