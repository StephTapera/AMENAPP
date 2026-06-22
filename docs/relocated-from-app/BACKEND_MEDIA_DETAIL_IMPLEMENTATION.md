# Backend: Media-Detail System Implementation

## 1. Architecture Overview

The media-detail system powers the "Photos & Videos" profile tab, the reusable `AmenMediaDetailView`, feed media tiles, and notification deep links — all through a single canonical post model.

### Key design choices

| Concern | Decision |
|---|---|
| Profile media index | Denormalized `users/{uid}/mediaPosts/{postId}` subcollection, backend-only writes |
| Comment threads | One canonical thread per post (`posts/{postId}/comments/{commentId}`) — no duplication |
| Media detail view | Single `AmenMediaDetailView` reused across Feed / Profile / Search / Notifications |
| Moderation | `isHidden` + `moderationState` fields on index doc, set only by Cloud Functions |
| Deep links | `amen://post/{postId}` and `amen://media/{postId}?mediaIndex=0` |
| Profile media load | `MediaPostIndexService` → paginated subcollection reads (30/page) |

---

## 2. Collections and Fields Added

### `users/{authorId}/mediaPosts/{postId}` (new)

Backend-written index document. Firestore rules block all client writes.

| Field | Type | Notes |
|---|---|---|
| `postId` | string | mirrors document ID |
| `authorId` | string | owner UID |
| `visibility` | string | `"everyone"` \| `"followers"` \| `"community"` |
| `mediaItems` | array | lightweight media entries (id, type, url, thumbnailURL, aspectRatio, order, duration) |
| `primaryThumbnailURL` | string | first media item thumbnail or url |
| `primaryMediaType` | string | `"image"` \| `"video"` |
| `mediaCount` | number | total media items |
| `isCarousel` | boolean | mediaCount > 1 |
| `caption` | string | post content, max 280 chars |
| `verseReference` | string? | attached scripture reference |
| `churchNoteId` | string? | attached church note ID |
| `isChurchShare` | boolean | whether post is a church share |
| `sharedChurchId` | string? | church ID if isChurchShare |
| `category` | string | post category |
| `createdAt` | Timestamp | mirrors post createdAt |
| `updatedAt` | Timestamp (server) | updated by CF on each change |
| `isHidden` | boolean | true when moderation removes from grid |
| `moderationState` | string | `"clean"` \| `"flagged"` \| `"removed"` \| `"quarantined"` |
| `status` | string | `"published"` \| `"publishing"` \| `"draft"` |

---

## 3. Cloud Functions Added

### `AMENAPP/Backend/functions/src/mediaPostIndex.ts`

Exported from `index.ts` as three gen2 Firestore triggers:

| Function | Trigger | Behavior |
|---|---|---|
| `onMediaPostCreate` | `posts/{postId}` created | If post has media and is not a draft, writes `users/{authorId}/mediaPosts/{postId}` |
| `onMediaPostUpdate` | `posts/{postId}` updated | Syncs index: removes if media gone/draft; updates visibility, moderation, attachments |
| `onMediaPostDelete` | `posts/{postId}` deleted | Removes index doc |

Media extraction handles both `mediaItems` (modern schema) and `imageURLs` (legacy) transparently.

Moderation fields trusted: `removed`, `quarantined`, `flaggedForReview` (server-set only, clients cannot write these per Firestore rules).

---

## 4. Firestore Rules Added

In `firestore 18.rules`, added block for `users/{userId}/mediaPosts/{postId}`:

- **Owner**: always readable (own private grid)
- **`visibility: "everyone"`**: any authenticated user
- **`visibility: "followers"`**: only confirmed followers (via `callerFollows(userId)`)
- **`isHidden: true`**: non-owners denied regardless of visibility
- **Write**: `if false` — exclusively backend (admin SDK)

---

## 5. Firestore Indexes Added (`firestore.indexes.json`)

Four new composite indexes on `mediaPosts` (COLLECTION scope):

1. `isHidden ASC, createdAt DESC` — main profile grid query
2. `isHidden ASC, primaryMediaType ASC, createdAt DESC` — photo/video filter
3. `visibility ASC, isHidden ASC, createdAt DESC` — future viewer-scoped queries
4. `status ASC, isHidden ASC, createdAt DESC` — status-filtered queries

---

## 6. iOS Client Files Added / Modified

### New

| File | Purpose |
|---|---|
| `AMENAPP/AMENAPP/MediaPostIndexService.swift` | Async/await paginated reader for `users/{uid}/mediaPosts`. Decodes `MediaPostIndexDoc`, supports `MediaPostIndexFilter` (All / Photos / Videos), provides `toGridItems()` and `toEnrichedGridItem()` converters |
| `AMENAPP/AMENAPP/IndexedMediaGridView.swift` | Drop-in profile media tab view. Owns `MediaPostIndexService`, renders filter strip, delegates grid rendering to `MediaGridView` |

### Modified

| File | Change |
|---|---|
| `AMENAPP/MediaGridView.swift` | Added `init(items: [MediaGridItem], sourceContext: MediaSourceContext)` — direct items initializer for index-backed usage |

---

## 7. Client Wiring Notes for SwiftUI

### Replace profile media grid

In `ProfileView.swift` and `UserProfileView.swift`, replace `MediaGridView(posts: userPosts)` with the index-backed view:

```swift
// Own profile tab
IndexedMediaGridView(userId: currentUserId, viewerOwns: true, sourceContext: .profile)

// Other user's profile
IndexedMediaGridView(userId: targetUserId, viewerOwns: false, sourceContext: .userProfile)
```

The index-backed view handles loading, pagination (30 items/page), pull-to-refresh, and photo/video filtering automatically.

### Media detail view (already implemented)

`AmenMediaDetailView` receives a `Post` and `initialMediaIndex`. Open it from any context:

```swift
AmenMediaDetailLoaderView(
    postID: postId,
    initialMediaIndex: tappedIndex,
    sourceContext: .notification
)
```

### Deep link routing

Notification payloads should include:

```json
{
  "route": "media",
  "postId": "<postId>",
  "mediaIndex": "0"
}
```

Route to:

```swift
AmenMediaDetailLoaderView(
    postID: payload.postId,
    initialMediaIndex: Int(payload.mediaIndex) ?? 0,
    sourceContext: .deepLink
)
```

---

## 8. Migration Notes

### Backfilling existing posts

The `onMediaPostCreate` trigger only fires on new writes. Existing posts with media will not have index docs until they are next updated (or a one-time backfill script is run).

For the backfill, run a script that iterates all `posts` documents where `mediaItems` or `imageURLs` is non-empty and writes the index doc via admin SDK. This can be done in a Cloud Function with a Firestore query + batch write.

Until backfilled, `IndexedMediaGridView` will show fewer items than `MediaGridView(posts: userPosts)`. The existing `MediaGridView` path remains available and can be used as a fallback during migration.

### Deprecation plan

Once backfill is complete and index docs are verified:
1. Remove `feedViewMode == .media` branch from `ProfileView` that calls `MediaGridView(posts: userPosts)`
2. Replace with `IndexedMediaGridView`
3. Remove `mediaFeedVM.ingestPosts()` call

---

## 9. Deployment Steps

```bash
# 1. Deploy Cloud Functions (new triggers)
firebase deploy --only functions:onMediaPostCreate,functions:onMediaPostUpdate,functions:onMediaPostDelete

# 2. Deploy Firestore rules (new mediaPosts subcollection rule)
firebase deploy --only firestore:rules

# 3. Deploy Firestore indexes (new mediaPosts indexes)
firebase deploy --only firestore:indexes

# 4. (After verifying triggers are live) Run backfill script for existing posts
# See backfill notes above.
```

---

## 10. Risks and Follow-ups

| Risk | Mitigation |
|---|---|
| Index lag after post create | `onMediaPostCreate` is near-real-time (gen2 trigger). Profile tab shows the spinner until first page loads. |
| Moderation state drift | `onMediaPostUpdate` syncs `isHidden` and `moderationState` on every post write. CF is the sole writer. |
| Backfill window | Existing posts missing index until backfill. `MediaGridView(posts:)` remains as a fallback. |
| `callerFollows()` cost | Firestore rules `callerFollows()` performs a get(). Called only on follower-visibility reads. Consistent with existing follows-gated post reads. |
| Large carousels in index | `mediaItems` array is stored in full. For carousels > ~20 items, consider storing only first 10 in the index and loading the rest from the canonical post on demand. |
