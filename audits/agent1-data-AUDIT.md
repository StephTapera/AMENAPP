# Agent 1 — Comments Data Layer Audit
**Date:** 2026-05-27  
**Auditor:** Agent 1 (Data Layer)  
**Scope:** End-to-end comments system — model, schema, security rules, listeners, threading, pagination, aggregations

---

## Q1 — Surfaces That Have Comments

The `CommentsView` (backed by `CommentService` / RTDB) is the primary surface and is used across:

| Surface | File | Notes |
|---|---|---|
| Regular Posts (all categories) | `AMENAPP/PostDetailView.swift:493` | `CommentsView(post: post)` |
| Post Cards (feed) | `AMENAPP/PostCard.swift:6124–6130` | Sheet presentation |
| Prayer Requests | `AMENAPP/PrayerView.swift:1467` | Same `CommentsView` |
| User Profile (own posts) | `AMENAPP/ProfileView.swift:2707` | |
| Other User Profile | `AMENAPP/UserProfileView.swift:589, 3284` | |
| Church Notes | `AMENAPP/ChurchNotesView.swift:4759` | `threadCategoryOverride: "church_note"` |
| ARISE/Outpour Media detail | `AMENAPP/AMENAPP/AmenMediaDetailView.swift:370` | `CommentsView(post: post)` |
| Post Attachment System | `AMENAPP/AMENAPP/PostAttachmentSystem.swift:1354` | |
| Voice Prayer (subcollection) | `AMENAPP/AMENAPP/VoicePrayer/VoicePrayerCommentsSection.swift` | Separate Firestore subcollection `posts/{postId}/voiceComments` |
| Church Notes (semantic editor) | `AMENAPP/AMENAPP/ChurchNotes/Views/ChurchNoteSemanticEditorView.swift:475` | `ChurchNoteCommentsView` → Firestore subcollection `churchNotes/{noteId}/comments` |

**Summary:** There are **three distinct comment subsystems** in production:
1. **Primary (RTDB):** `CommentService` → `postInteractions/{postId}/comments/{commentId}` (main social feed)
2. **Church Notes (Firestore subcollection):** `ChurchNotesCommentsService` → `churchNotes/{noteId}/comments/{commentId}`
3. **Voice Prayer (Firestore subcollection):** `VoicePrayerCommentsSectionViewModel` → `posts/{postId}/voiceComments/{commentId}`

There are also two **zombie services** with zero active callers: `NestedCommentService` (Firestore `comments/{commentId}` top-level) and `RealtimeCommentsService.observeComments()` (RTDB `comments/{postId}`).

---

## Q2 — The `Comment` Model

**Canonical model:** `AMENAPP/PostInteractionModels.swift:15–127`

```swift
struct Comment: Identifiable, Codable, Equatable {
    var id: String?                         // optional — nil for optimistic comments
    var postId: String
    var authorId: String
    var authorName: String
    var authorUsername: String
    var authorInitials: String
    var authorProfileImageURL: String?
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isEdited: Bool
    var amenCount: Int
    var lightbulbCount: Int
    var replyCount: Int
    var amenUserIds: [String]
    var parentCommentId: String?            // nil = top-level; non-nil = reply
    var mentionedUserIds: [String]?
    var momentAnchor: MediaMomentAnchor?
    var approvalStatus: String?             // raw String enum ("approved"/"pending"/"rejected")
}
```

**Missing required fields (per audit spec):**
- `authorDisplayName` — uses `authorName` instead (different field name)
- `authorAvatarURL` — uses `authorProfileImageURL` instead (different field name)
- `deletedAt: Date?` — not present
- `deletedBy: String?` — not present
- `editedAt: Date?` — not present (uses `updatedAt` generically)
- `reactionCounts: [String: Int]` — not present (uses flat `amenCount`, `lightbulbCount`)
- `moderationState: ModerationState` — uses raw `approvalStatus: String?` instead of typed enum

**Separate model `PostComment`** (`AMENAPP/PostComment.swift:13`) — a lightweight struct used nowhere visibly (appears orphaned; uses `UUID` not `String` for IDs).

---

## Q3 — Reply Model

**No separate Reply model.** A reply is a `Comment` with `parentCommentId != nil`. The `isReply` computed property (`PostInteractionModels.swift:117`) makes this explicit. `CommentWithReplies` (`PostInteractionModels.swift:220`) is a display wrapper — not a Firestore model.

`NestedCommentService.NestedComment` (`NestedCommentService.swift:24`) is an identical parallel model inside the zombie service; it should be considered vestigial.

---

## Q4 — Firestore / RTDB Schema

### A. Primary comments (RTDB — active, main system)
```
/postInteractions/{postId}/comments/{commentId}
  authorId: String
  authorName: String
  authorUsername: String
  authorInitials: String
  authorProfileImageURL: String
  content: String
  timestamp: Int64 (ms since epoch)
  likes: Int
  likedBy: {[userId]: true}
  parentCommentId?: String
  clientRequestId?: String
  isEdited?: Bool
  updatedAt?: Int64
  momentAnchor?: {...}
```
Counter lives at: `/postInteractions/{postId}/commentCount`

### B. Legacy RTDB path (also written — dual-write risk)
`CommentService.addReply` does a multi-path write to BOTH:
- `/postInteractions/{postId}/comments/{commentId}/parentCommentId`
- `/comments/{postId}/{commentId}/parentCommentId`  ← legacy path (`CommentService.swift:755–758`)

`RealtimeCommentsService` still observes `comments/{postId}` (the legacy path) and `PostInteractionsService` also observes `comments/{postId}` for the `_commentsData` feed handle (`PostInteractionsService.swift:1207`).

### C. Church Notes comments (Firestore subcollection — active)
```
/churchNotes/{noteId}/comments/{commentId}
  id, noteId, anchorText, anchorStart?, anchorEnd?, body,
  authorUid, authorName, parentCommentId?, resolved, createdAt, updatedAt
```

### D. Voice Prayer comments (Firestore subcollection — active, flag-gated)
```
/posts/{postId}/voiceComments/{commentId}
  (VoiceComment model, status: VoiceCommentStatus)
```

### E. Zombie Firestore top-level collection (no Firestore rules, no active callers)
```
/comments/{commentId}   ← written by NestedCommentService only
```
**CRITICAL:** This collection has **no Firestore security rules** other than the catch-all deny (`match /{document=**} { allow read, write: if false; }`). Since NestedCommentService has **zero active callers** (only `static let shared` self-reference), it is currently harmless, but the collection would be silently blocked if ever called. The existing safety rule is `comments/{commentId}/safety/{docId}` which covers subcollections only, not the root document.

---

## Q5 — Security Rules Analysis

### Primary comments (RTDB `postInteractions/{postId}/comments`)
RTDB rules live in `AMENAPP.xcodeproj/firestore_permissions.rules` (not the Firestore rules). These were NOT audited in detail here — a separate RTDB rules audit is needed.

**Client-side enforcement** exists in `CommentService`:
- `editComment` fetches the document and verifies `authorId == userId` (line 1056) before writing.
- `deleteComment` verifies `authorId == userId` via transaction (line 1182).
- `toggleAmen` does NOT verify ownership (by design — anyone can amen).

**Risk:** If RTDB rules are permissive, a user can craft a direct RTDB write to spoof `authorId`. This bypasses client-side checks. → `DEFERRED_FIXES.md` (RTDB rules audit needed).

### Church Notes comments (Firestore `churchNotes/{noteId}/comments`)
Rules at `firestore.rules:1307–1328`:
- `create`: requires `request.resource.data.authorUid == request.auth.uid` ✅ (prevents author spoofing)
- `update`: only the author can update (`resource.data.authorUid == request.auth.uid`) and only whitelisted fields ✅
- `delete`: only the author can delete ✅

**No loophole found** in Church Notes comment rules.

### Voice Prayer comments (Firestore `posts/{postId}/voiceComments`)
No explicit rule found for this path in `firestore.rules`. Falls through to the catch-all deny → all writes must go through Cloud Functions or are blocked. Appears correct if backed by a callable.

### Zombie top-level `comments/{commentId}` collection (Firestore)
**No CRUD rules** at this path (only `comments/{commentId}/safety/{docId}` at line 1461). Catch-all deny covers writes/reads. The `NestedCommentService` writes would **silently fail** at Firestore layer — which is currently acceptable since the service has no active callers.

---

## Q6 — Snapshot Listener Hygiene

### CommentService (RTDB) — ✅ CLEAN
- `startListening(to:)` → stores `DatabaseHandle` in `listenerPaths[postId]`
- `stopListening(to:)` → removes observer + removes from dict
- `stopListening()` → clears all
- Called correctly in `CommentsView.swift:1360` (`.task { startRealtimeListener() }`) and `CommentsView.swift:1372` (`.onDisappear { stopRealtimeListener() }`)
- `deinit` logs a warning if cleanup was missed but cannot call Firebase safely

**Minor issue:** `deinit` comment says "don't call Firebase methods from deinit" but the `_rootRef` cached reference is never used in deinit for cleanup. The warning approach is correct; the comment-only approach is adequate.

### VoicePrayerCommentsSectionViewModel (Firestore) — ✅ CLEAN
- `startListening()` → stores `ListenerRegistration?` in `listener`
- `stopListening()` → calls `listener?.remove(); listener = nil`
- Wired: `.task { await viewModel.startListening() }` / `.onDisappear { viewModel.stopListening() }` at `VoicePrayerCommentsSection.swift:66–67`

### ChurchNotesCommentsService (Firestore) — ✅ CLEAN
- `start(noteId:)` → stores `ListenerRegistration?` in `listener`
- `stop()` → calls `listener?.remove(); listener = nil`
- Wired via `start()`/`stop()` in `ChurchNoteCommentsView`

### RealtimeCommentsService.observeComments (RTDB) — ⚠️ POTENTIAL LEAK
- `observeComments()` stores handle in `commentListeners[postId]`
- `removeCommentsListener(postId:)` and `removeAllListeners()` exist
- `deinit` uses a `Task { @MainActor ... }` detached cleanup — **this is a race condition**: if the object deallocates before the Task runs, the captured `database` reference may be released. However, this is a `static let shared` singleton so it never deallocates in practice.
- **Active concern:** `observeComments()` has **no known caller** in the codebase. If ever called, the callers would need to call `removeCommentsListener()` — there is no automatic cleanup tied to a View lifecycle.

### PostInteractionsService (RTDB) — ✅ CLEAN
- `observePost(postId:)` stores handles in `observers` dict
- `stopObservingPost(postId:)` and `stopAllObservers()` exist
- `stopAllObservers()` is called from `AppLifecycleManager` on sign-out

**No confirmed unbounded listener leaks found** in the active comment code paths.

---

## Q7 — `@MainActor` / Threading

### CommentService — ✅ CORRECT
- Class is `@MainActor` (line 36)
- RTDB callback extracts data synchronously on Firebase thread, then dispatches to `@MainActor` via `Task { @MainActor [weak self] in ... }` pattern (line 1358)
- `Task.detached(priority: .utility)` for post-write moderation correctly avoids main-actor (line 540)

### RealtimeCommentsService — ✅ CORRECT (for singleton)
- Class is `@MainActor` (line 20)
- `observeComments` extracts snapshot data synchronously before dispatching to MainActor (line 473+)

### NestedCommentService — ✅ CORRECT (but orphaned)
- Class is `@MainActor` (line 16)
- All methods are `async`

### VoicePrayerCommentsSectionViewModel — ✅ CORRECT
- `@MainActor final class` (line 207)
- Listener callback dispatches to main via Swift concurrency

**No `@MainActor` violations found** in active comment-handling code.

---

## Q8 — Pagination

### Primary CommentService (RTDB) — ✅ PAGINATED
- `static let commentPageSize = 20` (line 50)
- Live listener uses `.queryLimited(toLast: UInt(Self.commentPageSize))` (line 1331)
- `loadMoreComments(postId:)` implements cursor-based older-page loading (line 1588)
- Per-post `hasMoreComments` and `loadMoreInFlight` guards prevent duplicate fetches

### NestedCommentService (Firestore) — ⚠️ HARD LIMIT ONLY
- `fetchComments`: `.limit(to: 100)` (line 143) — bounded but large
- `fetchReplies`: `.limit(to: 50)` (line 178) — bounded

### RealtimeCommentsService (RTDB, orphaned) — ⚠️ UNBOUNDED
- `fetchComments` does `.getData()` on entire `comments/{postId}` node with no limit (line 156)
- No pagination implemented

### ChurchNotesCommentsService — ⚠️ UNBOUNDED
- `start(noteId:)` listener has no `.limit()` (line 29)
- Risk is low for church note comments (expected to be sparse), but should be bounded

### fetchUserComments (CommentService) — ✅ BOUNDED
- `.limit(to: limit)` with default 50 (line 950)

---

## Q9 — Aggregations & Counters

| Counter | Location | Strategy | Transactional? |
|---|---|---|---|
| `commentCount` on post | RTDB `postInteractions/{postId}/commentCount` | Denormalized | ✅ Transaction in `deleteComment` (line 1231); increment via `PostInteractionsService` |
| `amenCount` (likes) on comment | RTDB `postInteractions/{postId}/comments/{commentId}/likes` | Denormalized | ✅ Full transaction in `toggleAmen` (line 1271) |
| `replyCount` on comment | Not stored in RTDB; computed from `commentReplies[commentId].count` in listener | Live-computed | N/A |
| `replyCount` in NestedCommentService | Firestore `comments/{commentId}` | `FieldValue.increment(1)` (line 232) | ✅ |
| `commentCount` on post in NestedCommentService | Firestore `posts/{postId}` | `FieldValue.increment(1)` (line 238) | ✅ |
| `likeCount` in NestedCommentService | Firestore `comments/{commentId}` | `FieldValue.increment(±1)` (lines 341, 347) | ✅ |

**Counter issue found:** In `RealtimeCommentsService.toggleCommentAmen()` (line 427–450), the RTDB amen count is updated via transaction on a separate `comment_stats/{commentId}/amenCount` path, but the interaction presence is set in a separate (non-transactional) write to `comment_interactions/{commentId}/amen/{userId}`. This is a two-step write without atomicity. However, this service has **no active callers** so the risk is currently theoretical.

---

## PHASE 2 — SAFE FIXES APPLIED

### Fix 1: Add `ModerationState` enum + `CommentFlags` struct + missing model fields to `PostInteractionModels.swift`

Added:
- `ModerationState` enum: `.pending`, `.approved`, `.hidden`, `.removed`
- `CommentFlags` struct: `containsLink`, `containsMention`, `containsScripture`
- `deletedAt: Date?`
- `deletedBy: String?`
- `editedAt: Date?` (alongside existing `updatedAt`)
- `reactionCounts: [String: Int]`
- `moderationState: ModerationState` (typed, replaces raw `approvalStatus` string — kept `approvalStatus` for backward compat)

### Fix 2: Add `.limit(25)` to ChurchNotesCommentsService unbounded listener

Added `.limit(to: 25)` to the Firestore listener in `ChurchNotesCommentsService.start(noteId:)`.

### Fix 3: `RealtimeCommentsService.deinit` — remove racy Task-based cleanup, log instead

The `deinit` Task is a race condition (object may be released before Task executes). Since this is a singleton, risk is theoretical — but changed to a safer pattern matching `CommentService`'s approach.

---

## VERIFICATION

### Files Changed

| File | Change |
|---|---|
| `AMENAPP/PostInteractionModels.swift` | Added `ModerationState` enum, `CommentFlags` struct, `deletedAt`, `deletedBy`, `editedAt`, `reactionCounts`, `moderationState` fields to `Comment` |
| `AMENAPP/AMENAPP/ChurchNotes/Services/ChurchNotesCommentsService.swift` | Added `.limit(to: 25)` to the Firestore snapshot listener |
| `AMENAPP/RealtimeCommentsService.swift` | Replaced racy `Task`-based deinit cleanup with a debug-only warning log matching `CommentService` pattern |

### Tests That Exist
- `AMENAPPTests/VoicePrayerCommentTests.swift` — covers voice comment feature flags, duration limits, model decoding, safety, reactions, analytics
- No unit tests exist for `CommentService`, `NestedCommentService`, or `ChurchNotesCommentsService`

### Test Gaps
- No tests for `Comment` model encoding/decoding (Firestore round-trip)
- No tests for `CommentService.addComment` permission checks
- No tests for `CommentService.deleteComment` ownership enforcement
- No tests for `CommentService.toggleAmen` transaction behavior
- No tests for `ModerationState` enum or `CommentFlags` struct
- No contract tests for listener start/stop lifecycle
- No tests for `ChurchNotesCommentsService` CRUD operations

---

## DEFERRED ITEMS (written to DEFERRED_FIXES.md)

1. **RTDB security rules audit** — RTDB rules at `AMENAPP.xcodeproj/firestore_permissions.rules` were not audited. If they are permissive on `postInteractions/{postId}/comments`, a user can craft a direct write with a spoofed `authorId`.

2. **Dual-write to legacy RTDB path** — `CommentService.addReply` writes `parentCommentId` to both `/postInteractions/{postId}/comments/` AND `/comments/{postId}/` (line 755–758). The legacy path should be removed after all readers migrate.

3. **`NestedCommentService` zombie** — Writes to Firestore `comments/{commentId}` with no active callers and no Firestore security rules for CRUD on that path. Should be deleted or wired in properly with rules.

4. **`RealtimeCommentsService.observeComments` orphan** — has no callers; the service is only referenced in `AppLifecycleManager.removeAllListeners()`. Should be deleted.

5. **`PostComment.swift` orphan** — Uses `UUID` instead of `String` for IDs, not used anywhere. Should be deleted.

6. **`approvalStatus: String?`** field should be migrated to `moderationState: ModerationState` — requires a migration plan.

7. **ChurchNotesCommentsService has no auth on body/authorName** — Firestore rules enforce `authorUid == request.auth.uid` on create, but `authorName` comes from `Auth.auth().currentUser?.displayName` at write time (line 136), not from a server-verified claim. Could be spoofed via display name manipulation.

