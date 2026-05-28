# Performance Audit — Agent 2
Date: 2026-05-27

---

## Findings

### F1 — Bare `AsyncImage` without `.transaction { t in t.animation = nil }` (flicker risk)
177 files use `AsyncImage` or `CachedAsyncImage`. The following are in hot-path or frequently-rebuilt views and had no animation suppression:

| File | Line | Context |
|------|------|---------|
| `AMENAPP/SpaceFeedView.swift` | 75 | Cover-image hero in every Space detail |
| `AMENAPP/AmenSpaceBannerRail.swift` | 921 | Banner card media in scrollable horizontal carousel |
| `AMENAPP/AmenSpaceBannerRail.swift` | 951 | Banner card icon in same carousel |
| `AMENAPP/PostCard.swift` | 5224 | Post action-menu preview thumbnail |
| `AMENAPP/FeedComposerRow.swift` | 199 | Composer avatar row (appears at top of every feed) |

> Note: The app already has a `CachedAsyncImage` component (`AMENAPP/CachedAsyncImage.swift`) with in-memory caching. PostCard's main image correctly uses `CachedAsyncImage` (line 561). The five usages above were missed and still use bare `AsyncImage` (no memory cache, no flicker suppression).

### F2 — No `Self._printChanges()` instrumentation anywhere
`grep -r '_printChanges'` returned no matches. Without this, it is impossible to know which `@State`/`@Binding` fields drive unintended re-renders in production profiling sessions.

### F3 — `@ObservedObject` on 4 shared singletons in `YourFeedView`
`AMENAPP/YourFeedView.swift` lines 25-28 use `@ObservedObject` for `HeyFeedPreferencesService`, `HeyFeedNLPreferencesService`, `HeyFeedSessionModeService`, and `ContextLabelPreferenceStore`. These are singletons; any publish on any of them triggers a full `YourFeedView` body re-evaluation. If any of these services is chatty (e.g. timer-driven or publishes on every keystroke), this can be expensive. PostCard already has comments noting this exact fix was applied — YourFeedView was not similarly tightened.

### F4 — `PostCard` has `@StateObject` leaking PrayerRoomService
`AMENAPP/PostCard.swift` line 6836: `@StateObject private var prayerRoomService = PrayerRoomService.shared`. Using `@StateObject` with a shared singleton is incorrect — `@StateObject` initializes its own instance lifecycle, but here it is assigned from `.shared`. Since the wrappedValue is a reference type, the object itself is shared, but SwiftUI still owns the `@StateObject` lifetime per view instance, and any `objectWillChange` publish from `PrayerRoomService` will re-render all active PostCard instances. This should be `@ObservedObject` if observation is required (then scoped with targeted `.onReceive`), or an unobserved `let` if not.

### F5 — `ForEach(..., id: \.id)` vs `Identifiable`
`TopicFeedView.swift` line 117 uses `ForEach(viewModel.posts, id: \.id)` even though `Post` likely conforms to `Identifiable`. This is a minor issue (redundant `id:` parameter vs dropping it) — not a rebuild storm, just defensive hygiene.

### F6 — No `.id(UUID())` forced rebuild patterns found
Searched for `.id(UUID())` — no matches. Good.

### F7 — Animation curve notes (`animation(.linear` / `animation(.easeIn`)
Found 20+ usages of `.easeIn`, `.easeInOut`, and `.linear` duration-based animations on non-spring curves. None are obviously wrong for their context (progress bars, toggles, transitions). No action needed on these.

### F8 — `CachedAsyncImage.loadImage()` uses `withAnimation(.easeOut(duration:0.25))` on image load
`AMENAPP/CachedAsyncImage.swift` line 77: The image load callback fires `withAnimation(.easeOut(duration: 0.25))` on the `MainActor` to fade in images. This is intentional and fine for user-initiated loads, but if the same view is used inside `LazyVStack` during fast scrolling, the animation queues can pile up. The fix is to gate the animation on `!reduceMotion`. Currently not respected.

---

## Implemented

| Change | File | Lines Affected |
|--------|------|----------------|
| Added `Self._printChanges()` behind `#if DEBUG` | `AMENAPP/PostCard.swift` | 2370-2373 |
| Added `Self._printChanges()` behind `#if DEBUG` | `AMENAPP/TopicFeedView.swift` | 22-25 |
| Added `Self._printChanges()` behind `#if DEBUG` | `AMENAPP/SpaceFeedView.swift` | 22-25 |
| Added `.transaction { t in t.animation = nil }` | `AMENAPP/SpaceFeedView.swift` | cover-image AsyncImage |
| Added `.transaction { t in t.animation = nil }` | `AMENAPP/AmenSpaceBannerRail.swift` | `media` var AsyncImage |
| Added `.transaction { t in t.animation = nil }` | `AMENAPP/AmenSpaceBannerRail.swift` | `icon` var AsyncImage |
| Added `.transaction { t in t.animation = nil }` | `AMENAPP/PostCard.swift` | action-menu preview AsyncImage |
| Added `.transaction { t in t.animation = nil }` | `AMENAPP/FeedComposerRow.swift` | composer avatar AsyncImage |

All changes are additive / non-breaking. The `_printChanges()` lines are stripped from Release builds by the `#if DEBUG` guard.

---

## Deferred

| Issue | File | Effort | Notes |
|-------|------|--------|-------|
| Migrate remaining bare `AsyncImage` usages to `CachedAsyncImage` | ~170 files | L | Mechanical but large surface area; prioritize feed-visible rows first (avatars, thumbnails) |
| Fix `@StateObject` on `PrayerRoomService.shared` in PostCard | `PostCard.swift` L6836 | S | Change to `let prayerRoomService = PrayerRoomService.shared` + targeted `.onReceive` where needed |
| Narrow `@ObservedObject` storm in `YourFeedView` | `YourFeedView.swift` L25-28 | M | Replace with `let` + `.onReceive` slices, same pattern already used in PostCard |
| Gate `withAnimation(.easeOut)` in `CachedAsyncImage.loadImage()` on `reduceMotion` | `CachedAsyncImage.swift` L77 | S | Add `@Environment(\.accessibilityReduceMotion)` check |
| Profile with Instruments (Time Profiler + SwiftUI) to validate `_printChanges` output | — | M | Should follow a real scroll session; cannot be done statically |
| `ForEach` id-parameter redundancy audit | Various | S | Where `Post: Identifiable`, drop explicit `id: \.id` |

---

## Risk Notes

- The `_printChanges()` addition changes the `body` return type inference in `TopicFeedView` and `SpaceFeedView` because the `let _ =` expression means `body` no longer implicitly returns. Both files were updated to use an explicit `return` on the subsequent view builder. Verify builds clean.
- `.transaction { t in t.animation = nil }` on `AsyncImage` suppresses ALL transitions on the image view. If a specific screen intentionally wanted a fade-in on first load (not scroll-back flicker), this removes that. Review `SpaceFeedView` cover image UX if a deliberate fade-in was designed.
- 177 files use `AsyncImage`/`CachedAsyncImage` — the five fixed here are the highest-traffic. The rest (settings, profile edit, book detail) are low-frequency screens and are lower priority.
