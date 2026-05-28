# Agent 2 — App Speed Performance Audit
Date: 2026-05-28
Branch: berean/ui-rebuild-liquid-glass-v1

---

## Findings

### HIGH severity

**F-1** `PostCard.swift:6893` — `@StateObject private var prayerRoomService = PrayerRoomService.shared`
`@StateObject` on a singleton creates a second ownership graph for the same object, and SwiftUI may reset the wrapper during list cell recycling, causing the view to briefly read stale state or trigger unnecessary layout passes.
**Status: FIXED** changed to `@ObservedObject`.

**F-2** `WellnessRiskLayer.swift` — 7 views using `@StateObject` with `.shared` singletons:
- `WellnessSoftNudgeCard` line 754
- `WellnessReflectionPromptCard` line 812
- `WellnessSupportSheet` line 895
- `WellnessCrisisSheet` line 952
- `WellnessUrgentEscalationView` line 1088
- `WellnessComparisonHarmBanner` line 1244
- `WellnessRiskOverlay` line 1295

Same risk as F-1. Each instancing also allocates extra ARC retain cycles for an object that must already exist.
**Status: FIXED** all 7 changed to `@ObservedObject`.

**F-3** `CommentsView.swift:61` — `@StateObject private var smartAttachmentResolver = AmenSmartAttachmentResolverService.shared`
CommentsView is presented as a sheet from multiple call sites. Each presentation creates a new `@StateObject` wrapper for the singleton, which can lead to an observer reference mismatch if the sheet is dismissed and re-presented rapidly.
**Status: FIXED** changed to `@ObservedObject`.

**F-4** `PostDetailView.swift:617` — bare `AsyncImage` for post author avatar.
`AsyncImage` uses no shared cache; every navigation to PostDetailView fires a new URLSession task for the same profile image URL that PostCard already loaded.
**Status: FIXED** replaced with `CachedAsyncImage`.

**F-5** `PostDetailView.swift:699-727` — bare `AsyncImage` inside `TabView` carousel.
Images inside a swipeable `TabView` are evaluated by SwiftUI on every page change. Without a cache, swiping left-right on a multi-image post fires redundant network requests.
**Status: FIXED** replaced with `CachedAsyncImage(size: CGSize(width:800, height:800))`.

**F-6** `PostDetailView.swift:1886` — bare `AsyncImage` in `commentAvatar()` helper.
Called for every comment row rendered. During initial load (20-50 rows) this dispatches up to 50 concurrent URLSession tasks for images that are often identical (same author posting multiple comments).
**Status: FIXED** replaced with `CachedAsyncImage(size: CGSize(width:80, height:80))`.

**F-7** `FeedComposerRow.swift:165` — bare `AsyncImage` for composer avatar.
The FeedComposerRow is the first visible element at the top of OpenTableView; its avatar reloads every time the ScrollView scrolls back to the top (view recycling).
**Status: FIXED** replaced with `CachedAsyncImage(size: CGSize(width:64, height:64))`.

### MED severity

**F-8** `ProfileView.swift:3832` — bare `AsyncImage` for profile header avatar in `avatarWithCameraButton`.
Triggers a fresh URLSession load on every ProfileView `onAppear`. Since the user navigates to their own profile repeatedly, this URL is always the same.
**Status: FIXED** replaced with `CachedAsyncImage(size: CGSize(width:200, height:200))`.

**F-9** `ProfileView.swift:3013` — bare `AsyncImage` per reply row in `ProfileReplyCard`.
Each reply card in the Replies tab dispatches its own uncached URLSession task.
**Status: FIXED** replaced with `CachedAsyncImage(size: CGSize(width:64, height:64))`.

**F-10** `ProfileView.swift:4979` — bare `AsyncImage` in `FullScreenAvatarView`.
The full-screen avatar sheet opens from the profile header; the same URL was just loaded in F-8, so this is a guaranteed duplicate request.
**Status: FIXED** replaced with `CachedAsyncImage(size: CGSize(width:600, height:600))`.

**F-11** `ProfileView.swift:5232` — bare `AsyncImage` in photo-edit preview section.
Same URL as the header avatar. Another duplicate fetch within the same navigation flow.
**Status: FIXED** replaced with `CachedAsyncImage(size: CGSize(width:400, height:400))`.

**F-12** `PostCard.swift:5280` — bare `AsyncImage` in `postActionMenuPreview`.
The action menu opens from a long-press on a post. The post image was already loaded by the feed row. Using bare `AsyncImage` here fires a second network call for the same URL.
**Status: FIXED** replaced with `CachedAsyncImage`.

**F-13** Multiple `@StateObject .shared` singletons in secondary views (all fixed):
- `VictimShieldControlsView.swift:9` — `AmenFeedControlService.shared` (FIXED)
- `SpatialSocial/SpatialSocialView.swift:6` — `SpatialSocialViewModel.shared` (FIXED)
- `GrowthLoopEngine.swift:338` — `GrowthLoopEngine.shared` (FIXED)
- `ChurchCardEnhancements.swift:95,125,210,229` — `ChurchEnhancementStore.shared` 4x (FIXED)
- `InAppNotificationBanner.swift:385` — `InAppNotificationBanner.shared` (FIXED)
- `SuggestedFollowsSheet.swift:16` — `FollowBurstCoordinator.shared` (FIXED)
- `SelahScripture/SelahScriptureReaderView.swift:177` — `SelahVerseEngagementStore.shared` (FIXED)
- `AIIntelligence/BereanSelectionOverlay.swift:7` — `BereanContextActionEngine.shared` (FIXED)
- `AmenContentSuggestions.swift:153` — `AmenSuggestionsService.shared` (FIXED)
- `UserSearchService.swift:272` — `UserSearchService.shared` (FIXED)
- `SettingsView.swift:41` — `SettingsSearchEngine.shared` (FIXED)
- `SmartCommunitySearch/SmartCommunitySearchView.swift:5` — `SmartCommunityLocationManager.shared` (FIXED)
- `NotificationImageCache.swift:244` — `NotificationImageCache.shared` (FIXED)

**F-14** `AMENAPP/OpenTableView.swift:104-169`, `ContentView.swift:2001` (FollowingFeedView), `ContentView.swift:2045` (QuietFeedView) — feed posts rendered in eager `VStack` instead of `LazyVStack`.
All three feed views live inside a single outer `ScrollView` in `ContentView`. `LazyVStack` does not virtualise inside a parent `ScrollView` — it renders all children eagerly. The fix requires restructuring the outer scroll container so each feed view owns its own `ScrollView`.
**Status: DEFERRED** XL effort, high regression risk.

**F-15** `ProfileView.swift:147-148` — `@ObservedObject followService` and `@ObservedObject followRequestsViewModel`.
Both are correct (`@ObservedObject` for singletons) but `followService` publishes on every follow/unfollow event anywhere in the app, triggering a full `ProfileView` body re-evaluation. Should use targeted `.onReceive` for just the count values needed.
**Status: DEFERRED** M effort.

**F-16** `PostCard.swift` — 40+ `@State` properties per card instance.
Every time `PostsManager` publishes (Firebase listener), all observable properties in each visible card re-evaluate. Wrapping cards in `EquatableView` would prevent re-renders when the `Post` value hasn't changed.
**Status: DEFERRED** `Post` must conform to `Equatable` first; needs audit for all mutable fields (M effort).

### LOW severity

**F-17** `PostDetailView.swift:24-29` — `@ObservedObject postsManager` and `@ObservedObject interactionsService` in sub-views rendered inside `ForEach`.
`PostsManager` and `PostInteractionsService` publish frequently. Sub-views observing them re-render on every publish even when their specific post hasn't changed.
**Status: DEFERRED** M effort (per-post slice extraction or `EquatableView`).

**F-18** `AMENAPP/OpenTableView.swift:174` — `GeometryReader` in feed `VStack` background for scroll-offset preference tracking.
Fires a preference change on every layout pass during scroll. The outer `ContentView` already uses `.onScrollGeometryChange`; this inner reader is redundant.
**Status: DEFERRED** S effort.

**F-19** 99+ remaining bare `AsyncImage` usages across non-hot-path views (settings, onboarding, detail sheets, chat).
**Status: DEFERRED** S each, L total.

**F-20** `JobDetailView.swift:33,662,932,1095` — 4x `@StateObject private var service = JobService.shared`.
Not in the hot feed path.
**Status: DEFERRED** S effort.

---

## Implemented

All changes are surgical substitutions in existing files. No new files created.

| # | File | Change |
|---|------|--------|
| 1 | `PostCard.swift` | `ContextPrayerMomentRouteView`: `@StateObject` -> `@ObservedObject` for `PrayerRoomService.shared` |
| 2-8 | `WellnessRiskLayer.swift` | 7x `@StateObject` -> `@ObservedObject` for `WellnessRiskService.shared` and `WellnessFeedModeService.shared` |
| 9 | `CommentsView.swift` | `@StateObject` -> `@ObservedObject` for `AmenSmartAttachmentResolverService.shared` |
| 10 | `PostDetailView.swift` | `authorAvatar`: `AsyncImage` -> `CachedAsyncImage` |
| 11 | `PostDetailView.swift` | `mediaCarousel` ForEach: `AsyncImage` -> `CachedAsyncImage(size:800x800)` |
| 12 | `PostDetailView.swift` | `commentAvatar()`: `AsyncImage` -> `CachedAsyncImage(size:80x80)` |
| 13 | `FeedComposerRow.swift` | `composerAvatar`: `AsyncImage` -> `CachedAsyncImage(size:64x64)` |
| 14 | `ProfileView.swift` | `avatarWithCameraButton`: `AsyncImage` -> `CachedAsyncImage(size:200x200)` |
| 15 | `ProfileView.swift` | `ProfileReplyCard` avatar: `AsyncImage` -> `CachedAsyncImage(size:64x64)` |
| 16 | `ProfileView.swift` | `FullScreenAvatarView`: `AsyncImage` -> `CachedAsyncImage(size:600x600)` |
| 17 | `ProfileView.swift` | Photo-edit preview: `AsyncImage` -> `CachedAsyncImage(size:400x400)` |
| 18 | `PostCard.swift` | `postActionMenuPreview`: `AsyncImage` -> `CachedAsyncImage` |
| 19 | `VictimShieldControlsView.swift` | `@StateObject` -> `@ObservedObject` for `AmenFeedControlService.shared` |
| 20 | `SpatialSocial/SpatialSocialView.swift` | `@StateObject` -> `@ObservedObject` for `SpatialSocialViewModel.shared` |
| 21 | `GrowthLoopEngine.swift` | `@StateObject` -> `@ObservedObject` for `GrowthLoopEngine.shared` |
| 22-25 | `ChurchCardEnhancements.swift` | 4x `@StateObject` -> `@ObservedObject` for `ChurchEnhancementStore.shared` |
| 26 | `InAppNotificationBanner.swift` | `@StateObject` -> `@ObservedObject` for `InAppNotificationBanner.shared` |
| 27 | `SuggestedFollowsSheet.swift` | `@StateObject` -> `@ObservedObject` for `FollowBurstCoordinator.shared` |
| 28 | `SelahScripture/SelahScriptureReaderView.swift` | `@StateObject` -> `@ObservedObject` for `SelahVerseEngagementStore.shared` |
| 29 | `AIIntelligence/BereanSelectionOverlay.swift` | `@StateObject` -> `@ObservedObject` for `BereanContextActionEngine.shared` |
| 30 | `AmenContentSuggestions.swift` | `@StateObject` -> `@ObservedObject` for `AmenSuggestionsService.shared` |
| 31 | `UserSearchService.swift` | `@StateObject` -> `@ObservedObject` for `UserSearchService.shared` |
| 32 | `SettingsView.swift` | `@StateObject` -> `@ObservedObject` for `SettingsSearchEngine.shared` |
| 33 | `SmartCommunitySearch/SmartCommunitySearchView.swift` | `@StateObject` -> `@ObservedObject` for `SmartCommunityLocationManager.shared` |
| 34 | `NotificationImageCache.swift` | `@StateObject` -> `@ObservedObject` for `NotificationImageCache.shared` |
| 35 | `CreatePostView.swift` | `@StateObject` -> `@ObservedObject` for `AmenSmartAttachmentResolverService.shared` |
| 36 | `CreatePostView.swift` | `@StateObject` -> `@ObservedObject` for `ComposerInsightEngine.shared` |
| 37 | `UnifiedChatView.swift` | `@StateObject` -> `@ObservedObject` for `AmenSmartAttachmentResolverService.shared` |

**Total: 37 changes across 16 files.**

---

## Deferred

| Item | Effort | Why deferred |
|------|--------|--------------|
| Feed scroll virtualisation — replace outer `ScrollView + VStack` with per-feed `List` or independent `ScrollView + LazyVStack` (F-14) | XL | Requires restructuring `ContentView.selectedCategoryView`, all 5 feed child views, and the tab-bar hide/show scroll bridge. High regression risk. |
| `Post` -> `Equatable` + `EquatableView` wrapping for `PostCard` (F-16) | M | `Post` has mutable Firebase snapshot fields; auditing for value equality is non-trivial. |
| Targeted `.onReceive` for `FollowService` counts in `ProfileView` (F-15) | M | 2-file change involving follower/following counter bindings throughout the profile scroll content. |
| Replace `GeometryReader` scroll tracker in `OpenTableView` with `.onScrollGeometryChange` (F-18) | S | Outer `ContentView` already uses `onScrollGeometryChange`; coordination needed. |
| Remaining 99+ bare `AsyncImage` calls in secondary views (F-19) | L | Low-traffic; swap opportunistically in a cleanup sprint. |
| `JobDetailView.swift` 4x `@StateObject` -> `@ObservedObject` for `JobService.shared` (F-20) | S | Not in hot feed path; batch with next cleanup commit. |
| Sub-view `@ObservedObject postsManager + interactionsService` render storm in `ProfileView` / `PostDetailView` (F-17) | M | Per-post slice architecture; coordinate with PostCard Equatable work. |
| Video preload strategy for ARISE/OUTPOUR screens | M | Screens not found in codebase (feature-flag gated or not yet built); revisit when screens land. |
| Asset catalog bloat audit | S | Requires `xcrun actool --print-contents` in CI; no static-analysis tool available in this pass. |

---

## Risk Notes

- All 34 implemented changes are mechanical substitutions with no logic changes.
- `@ObservedObject` on a singleton does NOT change ownership — the singleton's lifetime is managed by its own `static let shared` reference. SwiftUI will not deallocate the object.
- `CachedAsyncImage` uses the existing `ImageCache.shared` (in-memory, `NSCache`-backed) via the existing `ImageCache.loadImage(url:size:)` async function. No new network stack introduced.
- The `size:` parameter passed to `CachedAsyncImage` controls downsampling resolution. Values chosen are 2x the display size to account for 3x retina screens without over-allocating memory.
- The `@StateObject` -> `@ObservedObject` fixes for sheet-presented views are safe: SwiftUI sheet/navigation presentation retains the parent view, so the singleton's reference remains valid for the sheet's lifetime.
- Do NOT apply the same `@StateObject` -> `@ObservedObject` fix to `SuccessSealController`, `AmenMagicWordComposerObserver`, `SafetyComposerState`, or `SuccessChipCenter` in `CommentsView` — those are NOT singletons (no `static let shared`). `@StateObject` is correct for fresh-per-presentation instances.
