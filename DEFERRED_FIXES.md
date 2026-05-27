# DEFERRED_FIXES.md
> Fixes identified during the comments system 6-agent audit (2026-05-27) that are too risky to apply automatically. Each entry must be reviewed, coordinated, and tested before merging.

---

## [AGENT-1] RTDB Security Rules Audit for Comments
Risk: 🔴
File: `AMENAPP.xcodeproj/firestore_permissions.rules`
Description: The Firebase Realtime Database rules were not audited in this pass. The primary comment store (`postInteractions/{postId}/comments/{commentId}`) relies entirely on client-side ownership checks in `CommentService.editComment` and `CommentService.deleteComment`. If RTDB rules allow any authenticated user to write to any `postInteractions/{postId}/comments/{commentId}` node, a user can craft a direct RTDB write with a spoofed `authorId`, bypassing all client-side protections. The rules must be audited to ensure: (1) only the comment `authorId == request.auth.uid` can update/delete their own comment, (2) `authorId` cannot be changed after creation, (3) writes to `likedBy/{uid}` are restricted to `uid == request.auth.uid`.
Effort: M

---

## [AGENT-1] Remove Dual-Write to Legacy RTDB Path
Risk: 🟡
File: `AMENAPP/CommentService.swift:755–758`
Description: `CommentService.addReply()` writes `parentCommentId` to BOTH the canonical path (`/postInteractions/{postId}/comments/{commentId}/parentCommentId`) AND a legacy path (`/comments/{postId}/{commentId}/parentCommentId`). The legacy path `comments/{postId}` is also observed by `RealtimeCommentsService.observeComments()` and `PostInteractionsService` (the `_commentsData` handle at line 1207). This dual-write creates two sources of truth. The legacy path should be removed once all readers (`RealtimeCommentsService`, `PostInteractionsService._commentsData`) are confirmed migrated to `postInteractions/{postId}/comments`. Requires a coordinated migration: remove writes → remove readers → clean up orphan data.
Effort: L

---

## [AGENT-1] Delete NestedCommentService (Zombie Firestore Service)
Risk: 🟡
File: `AMENAPP/NestedCommentService.swift`
Description: `NestedCommentService` writes to the Firestore top-level `comments/{commentId}` collection but has zero active callers in the app. This collection has no Firestore security rules for CRUD (only `/comments/{commentId}/safety/{docId}` is covered). If this service is ever called, writes will silently fail at the Firestore layer (caught by the catch-all deny rule). The service should be deleted after confirming no downstream system (Cloud Functions, analytics pipelines) reads from `comments/{commentId}`. Also requires adding explicit deny rules to the Firestore ruleset to make the intent explicit.
Effort: S

---

## [AGENT-1] Delete RealtimeCommentsService.observeComments (Orphaned Listener)
Risk: 🟡
File: `AMENAPP/RealtimeCommentsService.swift:464`
Description: `RealtimeCommentsService.observeComments(postId:completion:)` has no callers in the current codebase. The only reference to `RealtimeCommentsService.shared` is in `AppLifecycleManager.removeAllListeners()` (calling `removeAllListeners()` on signout). If `observeComments` is ever called without a matching `removeCommentsListener()` call tied to a View lifecycle, the RTDB listener will leak for the session lifetime. The method (and potentially the entire service) should be deleted after confirming it is not used by any background extension or Cloud Function trigger.
Effort: S

---

## [AGENT-1] Delete PostComment.swift (Orphaned Model)
Risk: 🟢
File: `AMENAPP/PostComment.swift`
Description: `PostComment` struct uses `UUID` (not `String`) for its `id` and `postId` fields, making it incompatible with both RTDB and Firestore IDs. It has no callers and no references other than its own definition. The `Date.timeAgoDisplay()` extension it defines is already defined elsewhere (referenced in `Comment.timeAgo`). Should be deleted after confirming no test target or extension references it.
Effort: S

---

## [AGENT-1] Migrate approvalStatus (String?) to moderationState (ModerationState)
Risk: 🟡
File: `AMENAPP/PostInteractionModels.swift`
Description: `Comment.approvalStatus: String?` is a raw string enum ("approved"/"pending"/"rejected"). It has been superseded by the new `moderationState: ModerationState` typed enum added in Phase 2. A migration plan is needed: (1) update all write sites to write `moderationState` instead of/alongside `approvalStatus`, (2) update all read sites to prefer `moderationState`, (3) run a Cloud Function migration to backfill existing RTDB/Firestore documents, (4) remove `approvalStatus` from the model. The custom `init(from decoder:)` added in Phase 2 bridges the two for now.
Effort: M

---

## [AGENT-1] ChurchNotesCommentsService authorName Spoof Risk
Risk: 🟡
File: `AMENAPP/AMENAPP/ChurchNotes/Services/ChurchNotesCommentsService.swift:136`
Description: When writing a church note comment, `authorName` is sourced from `Auth.auth().currentUser?.displayName` (client-controlled). The Firestore security rule enforces `authorUid == request.auth.uid` but does NOT restrict `authorName` to match the server-verified display name. A malicious user could change their Firebase Auth display name to impersonate another user's name in comments. Fix: server-resolve `authorName` in a Cloud Function, or add a Firestore rule that validates `authorName` matches the user's profile document.
Effort: M

---

## [AGENT-1] Firestore top-level comments collection needs explicit security rules
Risk: 🟡
File: `firestore.rules`
Description: The top-level Firestore `comments/{commentId}` collection (written only by the zombie `NestedCommentService`) has no explicit CRUD rules — only the catch-all deny covers it. This is currently safe because `NestedCommentService` is unused, but the ruleset should have an explicit `allow read, write: if false;` at `match /comments/{commentId}` to make the intent clear and prevent any future accidental reads/writes from succeeding if rules are reordered.
Effort: S

