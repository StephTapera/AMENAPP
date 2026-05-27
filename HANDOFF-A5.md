# HANDOFF-A5 — Navigation Agent (A5)
<!-- DATE: 2026-05-26 -->

## Summary

Navigation Agent A5 implemented three deliverables:

1. **`AmenContentRouter.swift`** — added `ReplyActionsTarget` struct and wired `openReplies` / `showReplyActions` with real service calls.
2. **`AMENAPP/AMENAPP/ReplyActionsMenuView.swift`** — new file with 5 real actions (Reply, Amen, Share, Report, Follow Author).
3. **`AMENAPP/PostCard.swift`** — wired `onLongPress` into `LiquidReplyPreviewRotator` and attached `.sheet(item:)` for `ReplyActionsMenuView`.

---

## Files Modified

| File | Change |
|------|--------|
| `AMENAPP/AmenContentRouter.swift` | Added `ReplyActionsTarget` struct; added `@Published var replyActionsTarget: ReplyActionsTarget?`; rewrote `openReplies` to fetch Post + stage `CommentFocusCoordinator`; rewrote `showReplyActions` to set `replyActionsTarget`; added private `resolvePost(postId:)` helper. |
| `AMENAPP/PostCard.swift` | Added `@State private var localReplyActionsTarget: ReplyActionsTarget?`; added `onLongPress` closure to `LiquidReplyPreviewRotator`; added `.sheet(item: $localReplyActionsTarget)` + `.onReceive(AmenUniversalContentRouter.shared.$replyActionsTarget)` to `dynamicReplyPreviewSection`. |

## Files Created

| File | Purpose |
|------|---------|
| `AMENAPP/AMENAPP/ReplyActionsMenuView.swift` | Contextual action menu for long-pressed reply preview chips. |

---

## Implementation Details

### AmenContentRouter.swift

**`ReplyActionsTarget`** (new type):
```swift
struct ReplyActionsTarget: Identifiable {
    let id: UUID       // fresh UUID per activation — ensures .sheet re-presents even for same post/reply
    let postId: String
    let replyId: String
}
```

**`openReplies(postId:highlightedReplyId:)`** now:
- Tracks analytics `.replyPreviewTapped` immediately (type: `"openReplies"`)
- Pre-stages `CommentFocusCoordinator.shared` so `CommentsView` / `PostDetailView` land on the highlighted reply
- Resolves the `Post` asynchronously (in-memory cache → Firestore fetch)
- Posts `.amenOpenRepliesRequested` notification with `"post"` key so listening host views can push `PostDetailView` / `CommentsView` without a second fetch

**`showReplyActions(postId:replyId:)`** now:
- Sets `replyActionsTarget` (drives `.sheet(item:)` in `PostCard`)
- Also fires `.amenReplyActionsRequested` notification (for future coordinator-based listeners)

**`resolvePost(postId:)`** (private):
- Searches `PostsManager.shared.allPosts` by `firestoreId` and `id.uuidString`
- Falls back to `FirebasePostService.shared.fetchPostById(postId:)`

### PostCard.swift — dynamicReplyPreviewSection changes

```swift
LiquidReplyPreviewRotator(
    candidates: candidates,
    onOpenReplies: { preview in openReplyPreview(preview, for: post) },
    onLongPress: { preview in
        AmenUniversalContentRouter.shared.showReplyActions(
            postId: preview.postId,
            replyId: preview.replyId ?? ""
        )
    }
)
.sheet(item: $localReplyActionsTarget) { target in
    ReplyActionsMenuView(target: target)
        .onDisappear { AmenUniversalContentRouter.shared.replyActionsTarget = nil }
}
.onReceive(AmenUniversalContentRouter.shared.$replyActionsTarget) { target in
    if let target, target.postId == post.firestoreId {
        localReplyActionsTarget = target
    } else if target == nil {
        localReplyActionsTarget = nil
    }
}
```

Using `.onReceive` (not `@ObservedObject`) to avoid triggering a full `PostCard` body re-evaluation on every router publish cycle — consistent with PostCard's existing "targeted onReceive" pattern.

### ReplyActionsMenuView.swift — 5 actions

| # | Action | Real service call |
|---|--------|------------------|
| 1 | **Reply** | `CommentFocusCoordinator.shared.set(scrollTarget:highlight:)` + `NotificationCenter` `.amenOpenRepliesRequested` — triggers CommentsView with text prefilled `"@username "` |
| 2 | **Like / Amen** | `PostInteractionsService.shared.toggleAmen(postId:)` with optimistic flip + revert on error |
| 3 | **Share** | `ShareLink(item: URL("https://amenapp.page.link/post/\(postId)"))` — native iOS share sheet |
| 4 | **Report** | `ModerationService.shared.reportPost(postId:postAuthorId:reason:.inappropriateContent:additionalDetails:)` — Alert confirmation before submit |
| 5 | **Follow Author** | `FollowService.shared.followUser(userId:)` / `unfollowUser(userId:)` toggle + `NotificationCenter.default.post("ReplyPreviewNeedsRefresh", userInfo: ["postId": postId])` |

---

## Known Gaps / HANDOFF Notes

### Gap 1 — Reply action reports to `reportPost`, not `reportComment`

`ModerationService.shared.reportComment(commentId:commentAuthorId:postId:reason:additionalDetails:)` requires a `commentAuthorId`. `ReplyActionsMenuView` receives a `ReplyActionsTarget` which only carries `postId` and `replyId` — it doesn't carry the reply author's UID. `DynamicReplyPreview.authorId` is optional and not surfaced to `ReplyActionsTarget`.

**Current behavior**: falls back to `reportPost` on the parent post with `additionalDetails` noting the replyId.

**Fix path**: extend `ReplyActionsTarget` to also carry `replyAuthorId: String?`, populated in `PostCard.openReplyPreview` from `preview.authorId`, and call `reportComment` when the author ID is available.

### Gap 2 — `openReplies` navigates via NotificationCenter only

`AmenUniversalContentRouter.openReplies` fires `.amenOpenRepliesRequested` notification with the `Post` object. Host views (`HomeView`, `ProfileView`, `UserProfileView`) must add an `.onReceive(.amenOpenRepliesRequested)` listener to intercept this and push/present a `CommentsView` or `PostDetailView`.

At time of writing no host view subscribes to this notification. The `PostCard`-internal `.presentSheet(.commentsHighlighted(...))` path (used by `openReplyPreview`) continues to work correctly for in-feed taps. The router's `openReplies` path is wired and correct but will silently no-op until a host subscribes.

**Fix path**: add `.onReceive(NotificationCenter.default.publisher(for: .amenOpenRepliesRequested))` in `HomeView` / `ProfileView` to push `CommentsView`.

### Gap 3 — `LiquidReplyPreviewRotator.onLongPress` was already present

The `LiquidReplyPreviewRotator` file in the repo already had `var onLongPress: (DynamicReplyPreview) -> Void = { _ in }` (added by a prior agent). A5 wired the closure — no structural change to the rotator was needed.

### Gap 4 — Reply composer pre-fill is NotificationCenter-mediated

The "Reply" action fires a NotificationCenter post. This is the best available approach given `CommentsView` is presented modally by `PostCard` (not owned by `ReplyActionsMenuView`). A future improvement would be to pass a `prefillText` parameter directly, but that requires `PostCard` to coordinate the dismissal of `ReplyActionsMenuView` before presenting `CommentsView`, which introduces ordering complexity.

---

## Testing Checklist

- [ ] Long-press a `LiquidReplyPreviewChip` → `ReplyActionsMenuView` appears (`.medium` detent)
- [ ] Tap **Reply** → sheet dismisses, CommentsView opens anchored to `replyId`, text field pre-filled `"@username "`
- [ ] Tap **Say Amen** → icon flips immediately; Firestore write completes; toggling again un-amens
- [ ] Tap **Say Amen** with no network → icon reverts, toast appears
- [ ] Tap **Share** → iOS share sheet appears with `https://amenapp.page.link/post/<postId>`
- [ ] Tap **Report** → Alert confirms → ModerationService call fires → success Alert dismisses sheet
- [ ] Tap **Follow Author** → FollowService call fires → button label switches to "Unfollow Author"; NotificationCenter posts `"ReplyPreviewNeedsRefresh"`
- [ ] Tap **Follow Author** on own post → toast "You can't follow yourself."
- [ ] Only the card whose `post.firestoreId` matches the router target presents the sheet (multi-card feeds)
- [ ] Dismissing sheet clears `AmenUniversalContentRouter.shared.replyActionsTarget`
