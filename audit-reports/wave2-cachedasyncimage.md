# Wave 2 — CachedAsyncImage Rollout

**Date:** 2026-05-27
**Branch:** berean/ui-rebuild-liquid-glass-v1
**Build result:** PASS (0 errors)

---

## Summary

Migrated 30 bare `AsyncImage(` call sites to `CachedAsyncImage` across 14 files.
Also fixed 1 pre-existing unrelated build error (Unicode curly quotes in
`AmenLiquidGlassSpiritualReactionSimulation.swift`).

### Before / After call counts

| Metric | Count |
|---|---|
| `AsyncImage(` before this session | ~173 files (170+ calls) |
| Previously fixed (prior session) | 5 |
| Fixed this session | 30 |
| Remaining bare `AsyncImage(` | ~135+ (lower-priority / safe-to-defer) |

---

## CachedAsyncImage API

File: `AMENAPP/CachedAsyncImage.swift`

```swift
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    init(
        url: URL?,
        size: CGSize = CGSize(width: 600, height: 600),
        showsFailureIcon: Bool = true,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    )
}
// Convenience: placeholder defaults to Color(.systemGray6)
extension CachedAsyncImage where Placeholder == Color {
    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content)
}
```

Backend: `ImageCache.shared.loadImage(url:size:)` — in-memory + disk cache.

---

## Files Migrated

### Batch 1 — Profile / post detail hot paths (6 calls)

**`AMENAPP/ProfileView.swift`** — 3 calls
- `avatarWithCameraButton`: edit-profile avatar (100×100) — was bare `AsyncImage`
- `FullscreenAvatarOverlay`: large 300×300 fullscreen avatar — was bare `AsyncImage`
- `ProfilePhotoEditView`: current photo preview (200×200) — was bare `AsyncImage`

**`AMENAPP/PostDetailView.swift`** — 3 calls
- `authorAvatar`: post author header avatar (48pt circle) — was bare `AsyncImage`
- `mediaCarousel`: ForEach image carousel (full-width, 420pt height) — was bare `AsyncImage` with complex phase switch; simplified to CachedAsyncImage
- `commentAvatar(imageURL:initials:size:)`: comment thread avatar helper — was bare `AsyncImage`

### Batch 2 — Notifications, following list, search suggestions (5 calls)

**`AMENAPP/AMENNotificationsView.swift`** — 3 calls
- `avatarView(_:size:)`: notification actor avatar (variable size) — was bare `AsyncImage`
- `ActivityPreviewThumbnail .postImage(url)`: post thumbnail preview (46×46 rounded rect) — was bare `AsyncImage`
- `ActivityPreviewThumbnail .churchLogo(url)`: church logo preview (46×46 rounded rect) — was bare `AsyncImage`

**`AMENAPP/FollowingListView.swift`** — 1 call
- `FollowingUserRow` body avatar (48×48 circle) — was bare `AsyncImage`

**`AMENAPP/SearchSuggestionsView.swift`** — 1 call
- Suggestion avatar in ZStack (40×40 circle) — was bare `AsyncImage` with `.failure` / `.empty` fallback

### Batch 3 — Mutual followers, group avatar, feed card (3 calls)

**`AMENAPP/MutualFollowersView.swift`** — 1 call
- `MutualSingleAvatar.body`: avatar stack component (variable size) — was bare `AsyncImage`; size computed as `size * 2` to pass correct pixel size

**`AMENAPP/GroupView.swift`** — 1 call
- `avatar(for:)`: group cover image avatar (92×92 circle) — was bare `AsyncImage`

**`AMENAPP/PostCard.swift`** — 1 call
- `postActionMenuPreview`: long-press action menu image preview (600pt) — was bare `AsyncImage`; `.transaction { t in t.animation = nil }` modifier preserved

### Batch 4 — Church detail, space feed (6 calls)

**`AMENAPP/ChurchDetailExperience.swift`** — 3 calls
- `churchHeroBackground` (parallax header, full bleed) — was bare `AsyncImage`
- `ChurchCollapsibleHeader` logo badge (76×76) — was bare `AsyncImage`
- `ChurchMediaRail` media cells (132pt height ForEach) — was bare `AsyncImage`

**`AMENAPP/SpaceFeedView.swift`** — 3 calls
- `coverHeader`: space cover image (220pt height) — was bare `AsyncImage` with `.transaction { t in t.animation = nil }` preserved
- `SpacePostRow` author avatar (36×36) — was bare `AsyncImage` with `if case .success` idiom
- `MediaCellView`: media thumbnail in grid (GeometryReader cell) — was bare `AsyncImage`

### Batch 5 — Media card, book covers (3 calls)

**`AMENAPP/MediaCard.swift`** — 1 call
- `thumbnailLayer`: card thumbnail (full-bleed) — was bare `AsyncImage` with 4-case switch

**`AMENAPP/WisdomLibraryView.swift`** — 2 calls
- `WLFeaturedBookCard` blurred banner background (blur: 28, full-bleed) — was bare `AsyncImage`
- `WLBookCoverView` cover image (variable width/height/corner) — was bare `AsyncImage` with 3-case switch; size uses `width * 2, height * 2` for @2x

### Batch 6 — Gatherings, space card (3 calls)

**`AMENAPP/Gatherings/AmenGatheringCard.swift`** — 1 call
- `heroBackground`: gathering card cover hero — was bare `AsyncImage`

**`AMENAPP/Gatherings/AmenGatheringDetailView.swift`** — 1 call
- `heroCover`: gathering detail full-bleed cover — was bare `AsyncImage` using `phase.image` idiom

**`AMENAPP/SpaceCardView.swift`** — 1 call
- `avatarStack` ForEach (22×22 per avatar, up to 3) — was bare `AsyncImage`

### Batch 7 — Creator / Covenant discovery (4 calls)

**`AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantDiscoveryView.swift`** — 4 calls
- `FeatureCreatorCard` banner background (120pt height, full-width) — was bare `AsyncImage`
- `FeatureCreatorCard` avatar overlay (44×44 circle at bottom-left) — was bare `AsyncImage` (same source URL re-used; both now cached from first load)
- `CompactCreatorRow` avatar (46×46 circle) — was bare `AsyncImage`
- `PopularCreatorCard` avatar (52×52 circle) — was bare `AsyncImage`

### Batch 8 — Covenant home (3 calls)

**`AMENAPP/AMENAPP/Covenant/AmenCovenantHomeView.swift`** — 3 calls
- `CovenantPillCard` avatar (56×56 circle) — was bare `AsyncImage`
- `NewPaidPostCard` creator avatar (28×28 circle) — was bare `AsyncImage`
- `SuggestedCreatorCard` creator avatar (60×60 circle) — was bare `AsyncImage`

---

## Files Skipped (and why)

| File | Reason |
|---|---|
| `CommentsView.swift` | Already fully migrated — all 4 call sites use CachedAsyncImage |
| `ProfileView.swift` (other calls) | Already used CachedAsyncImage at the 3 primary avatar locations |
| `UserProfileView.swift` | Already fully migrated — 5 existing CachedAsyncImage usages |
| `AMENDiscoveryView.swift` | Already fully migrated — 5 CachedAsyncImage usages |
| `DiscoverContentCards.swift` | Already fully migrated |
| `DiscoverUIEnhancements.swift` | Already fully migrated |
| `DiscoverSearchComponents.swift` | Already fully migrated |
| `MessagesView.swift` | Already fully migrated (5 CachedAsyncImage usages) |
| `UnifiedChatView.swift` | Already fully migrated (5 CachedAsyncImage usages) |
| `ModernPrayerWallView.swift` | Already fully migrated |
| `PrayerView.swift` | Already fully migrated |
| `NotificationsView.swift` | Already fully migrated |
| `FollowersListView.swift` | Already fully migrated |
| `FollowRequestsView.swift` | Already fully migrated |
| `FindFriendsView.swift` | Already fully migrated |
| `SuggestedUserRow.swift` | Already fully migrated |
| `PeopleDiscoveryView.swift` | Already fully migrated |
| `SafeConversationView.swift` | Already fully migrated |
| `GroupChatLiquidHeader.swift` | Feed item — deferred (complex layout, not a hot path per session) |
| ~100 remaining files | Lower-priority: non-feed contexts (settings sheets, one-off modals, dev/debug previews, print/share contexts) |

---

## Pre-existing Bug Fixed

**`AMENAPP/AMENAPP/AMENAPP/AmenLiquidGlassSpiritualReactionSimulation.swift`** — line 980, 987

Unicode "curly" (`"` `"`) smart quotes embedded in Swift string literals caused compiler errors.
Replaced with escaped straight-quote sequences (`\"...\"`). Build was failing before this fix.
This was not related to the CachedAsyncImage migration.

---

## Migration Pattern Used

```swift
// Before
AsyncImage(url: url) { phase in
    switch phase {
    case .success(let image):
        image.resizable().scaledToFill()
    default:
        placeholder
    }
}

// After
CachedAsyncImage(url: url, size: CGSize(width: W, height: H)) { image in
    image.resizable().scaledToFill()
} placeholder: {
    placeholder
}
```

Size guidelines applied:
- Avatars: `2× display size` (e.g. 96×96 for a 48pt avatar) for @2x clarity
- Hero / full-bleed covers: 1200×800 or 1200×440
- Media carousels: 1200×1200
- Small thumbnails: 92×92 or 80×80

`.transaction { t in t.animation = nil }` was preserved at call sites where it previously existed (SpaceFeedView cover header, PostCard action menu preview).
