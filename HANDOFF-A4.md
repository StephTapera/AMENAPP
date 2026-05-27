# HANDOFF-A4 — Navigation Agent (reply-preview-navigation)

**Agent**: A4 — reply-preview-navigation
**Date**: 2026-05-26
**Contract version read**: 1.0.1

---

## Summary

This agent verified and completed the two contract-frozen navigation methods (`openReplies` and `showReplyActions`) on `AmenUniversalContentRouter`, then corrected the `ReplyActionsMenuView` report action to call `reportComment` with `.spam` per the contract spec (it was previously calling `reportPost` with `.inappropriateContent`). All five action buttons in `ReplyActionsMenuView` now call real service methods with no empty closures and no TODOs.

---

## Methods Added / Verified

### File: `AMENAPP/AmenContentRouter.swift`

Both methods exist on `AmenUniversalContentRouter` and were confirmed complete. No edits were required to the router file itself.

| Method | Line range | Status |
|--------|-----------|--------|
| `openReplies(postId:highlightedReplyId:)` | 144–195 | Pre-existing, fully implemented |
| `showReplyActions(postId:replyId:)` | 199–214 | Pre-existing, fully implemented |

---

## `openReplies` — How It Works

**Signature** (contract-frozen, `@MainActor` class method on `AmenUniversalContentRouter`):
```swift
func openReplies(postId: String, highlightedReplyId: String?)
```

**Post resolution order** (`resolvePost(postId:)` private helper, lines 219–233):
1. In-memory cache: `PostsManager.shared.allPosts.first(where: { $0.firestoreId == postId || $0.id.uuidString == postId })`
2. Firestore fetch: `FirebasePostService.shared.fetchPostById(postId: postId)` — returns `Post?`, throws on network error (caught and returns `nil`)

**Navigation path** (lines 165–194):
- Spawns an unstructured `Task {}` so the synchronous call site is not blocked.
- If a `Post` is resolved: fires `NotificationCenter.default.post(name: .amenOpenRepliesRequested, …)` with `userInfo["post"]` included so host views (HomeFeedView, ProfileView, etc.) can present `CommentsView` or `PostDetailView` directly.
- If post cannot be fetched: fires the same notification without `userInfo["post"]`, allowing host views to display an error state or attempt their own fetch. The failure is silent (no crash, no modal error); the notification itself serves as the non-fatal log path.
- Before the async resolution, if `highlightedReplyId` is non-nil, `CommentFocusCoordinator.shared.set(scrollTarget:highlight:expandThread:)` is called so `PostDetailView` / `CommentsView` scrolls and highlights the target comment on appearance.

**Equivalent PostCard path** this mirrors:
`PostCardSheet.commentsHighlighted(post: post, replyId: highlightedReplyId, highlightedCommentIds: [highlightedReplyId])`
presented as a sheet from `PostCardSheetsModifier` (`PostCard.swift:6045–6047`).

---

## `showReplyActions` — How It Works

**Signature** (contract-frozen):
```swift
func showReplyActions(postId: String, replyId: String)
```

**Mechanism** (lines 199–214):
1. Creates an `AmenReplyRouteRequest` with `.showReplyActions(replyId:)` and publishes it to `pendingReplyRoute`.
2. Sets `replyActionsTarget = ReplyActionsTarget(postId: postId, replyId: replyId)`.
3. Fires `NotificationCenter.default.post(name: .amenReplyActionsRequested, …)`.

**Presentation path in PostCard** (`PostCard.swift:3243–3259`):
- Each `PostCard` has a `.sheet(item: $localReplyActionsTarget)` that presents `ReplyActionsMenuView(target:)`.
- `localReplyActionsTarget` is populated via `.onReceive(AmenUniversalContentRouter.shared.$replyActionsTarget)` — only accepts targets where `target.postId == post.firestoreId`, so only the owning card responds.
- On sheet dismiss, the card clears `AmenUniversalContentRouter.shared.replyActionsTarget = nil`.

---

## `ReplyActionsMenuView` — Five Real Actions

**File**: `AMENAPP/AMENAPP/ReplyActionsMenuView.swift`

The view is a `NavigationStack`-wrapped `List` with `.presentationDetents([.medium])`. It resolves its own `Post` via the same two-step cache+Firestore lookup used in the router. All five rows call real service methods:

| # | Label | Service call |
|---|-------|-------------|
| 1 | Reply | `CommentFocusCoordinator.shared.set(...)` + `NotificationCenter.post(.amenOpenRepliesRequested)` |
| 2 | Like / Amen | `PostInteractionsService.shared.toggleAmen(postId: post.firestoreId)` — optimistic UI with revert on error |
| 3 | Share | `ShareLink(item: URL("https://amenapp.page.link/post/\(target.postId)"))` |
| 4 | Report | `ModerationService.shared.reportComment(commentId: target.replyId, commentAuthorId: "", postId: target.postId, reason: .spam, additionalDetails: nil)` |
| 5 | Follow / Unfollow Author | `FollowService.shared.followUser(userId:)` / `FollowService.shared.unfollowUser(userId:)` — toggle based on `FollowService.shared.following.contains(post.authorId)` |

---

## Edit Made in This Session

**File**: `AMENAPP/AMENAPP/ReplyActionsMenuView.swift` — `submitReport()` (lines 309–328)

**Before**: Called `ModerationService.shared.reportPost(postId:postAuthorId:reason:additionalDetails:)` with `.inappropriateContent` and a freeform `additionalDetails` string.

**After**: Calls `ModerationService.shared.reportComment(commentId: target.replyId, commentAuthorId: "", postId: target.postId, reason: .spam, additionalDetails: nil)` per contract spec.

The doc comment on `reportRow(post:)` was also updated to accurately describe the current implementation.

---

## Known Limitations

### 1. `commentAuthorId: ""` in Report

**Gap**: `reportComment` requires a `commentAuthorId`. `ReplyActionsTarget` carries only `postId` and `replyId` — the reply author's UID is not available at call time.

**Mitigation**: `ModerationService.submitReport` accepts an empty string for `reportedUserId`; the Firestore document contains the full comment record including `authorId`, which the review team uses to resolve ownership. The `.spam` default reason is set per contract spec.

**Resolution path**: Pass `DynamicReplyPreview.authorId` through `ReplyActionsTarget` in a future iteration so `reportComment` receives the real `commentAuthorId`. This would require adding `authorId: String?` to `ReplyActionsTarget` and updating the call site in `PostCard.swift:3227–3230`.

### 2. Reply action uses parent post's `authorUsername` for prefill

The "Reply" button prefills the composer with `"@\(post.authorUsername) "` where `post` is the parent post resolved from Firestore. If the highlighted `replyId` belongs to a different commenter (not the original post author), the mention prefix will be wrong. The reply author UID is available in `DynamicReplyPreview.authorId` but not carried into `ReplyActionsMenuView` via `ReplyActionsTarget`.

### 3. `reportRow(post:)` receives unused `post` parameter

After the report implementation was changed to use `target.postId`/`target.replyId` directly, the `post:` parameter to `reportRow(post:)` is unused. The parameter is retained for structural consistency with the other action rows (all take `post:`) and to avoid changing `actionsContent(post:)`.

---

## Stub in PostCard.swift This Resolves (from A3)

The A3 agent's HANDOFF-A3.md (Resolver Agent) listed this as an open item:

> "Implement `openReplies(postId:highlightedReplyId:)` and `showReplyActions(postId:replyId:)` on router — Navigation agent"

The stub in `PostCard.swift` at lines 3226–3230 calls `AmenUniversalContentRouter.shared.showReplyActions(postId:replyId:)` from the `onLongPress` closure of `LiquidReplyPreviewRotator`. This now resolves to a real implementation that:

1. Sets `replyActionsTarget` on the router.
2. The owning `PostCard` picks up the target via `.onReceive`.
3. Presents `ReplyActionsMenuView` as a sheet with five real service-backed actions.

---

## Files Read (Reference Map)

| File | Purpose |
|------|---------|
| `AMENAPP/AmenContentRouter.swift` | Router class — both methods live here |
| `AMENAPP/PostCard.swift` | `PostCardSheet` enum, `openReplyPreview`, `dynamicReplyPreviewSection`, `PostCardSheetsModifier` |
| `AMENAPP/PostDetailView.swift` | Confirmed `init(post:highlightedCommentId:initialBereanPostContext:autoOpenBereanOnAppear:)` |
| `AMENAPP/PostsManager.swift` | Confirmed `PostsManager.shared.allPosts: [Post]` |
| `AMENAPP/FirebasePostService.swift` | Confirmed `FirebasePostService.shared.fetchPostById(postId:) async throws -> Post?` |
| `AMENAPP/PostInteractionsService.swift` | Confirmed `toggleAmen(postId:) async throws` |
| `AMENAPP/ModerationService.swift` | Confirmed `reportComment(commentId:commentAuthorId:postId:reason:additionalDetails:) async throws` and `.spam` case |
| `AMENAPP/FollowService.swift` | Confirmed `followUser(userId:) async throws`, `unfollowUser(userId:) async throws`, `FollowService.shared.following: Set<String>` |
| `AMENAPP/AMENAPP/ReplyActionsMenuView.swift` | Action sheet view — edited `submitReport()` |
| `AMENAPP/NotificationRoute.swift` | Confirmed `CommentFocusCoordinator.shared` and `.set(scrollTarget:highlight:expandThread:)` |

---

## No Outstanding TODOs, fatalErrors, or Empty Shipped Closures.
