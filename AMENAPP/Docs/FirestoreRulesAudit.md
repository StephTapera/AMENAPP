# Firestore Rules Audit

Date: 2026-05-24
Scope: `AMENAPP/COMPLETE_FIRESTORE_RULES.txt`

## Status

GO for Xcode build and local structural rules sanity.

Firebase emulator validation could not be executed in this workspace because `firebase`, `node`, `npm`, and `npx` are not installed. The project builds successfully after the stricter rules and query compatibility changes.

## Implemented Safeguards

- Added rule-level post visibility enforcement through `canReadPost`.
- Public post reads now require `visibility == "everyone"` / `"Everyone"` and approved publication/moderation state.
- Private/pending/removed/test posts are no longer readable just because a user is signed in.
- Followers-only posts are readable only to the author, tagged users, or users with a follow edge/mirror doc.
- `users/{userId}` is no longer public; reads now require sign-in.
- Post creates require verified writer identity, `authorId == request.auth.uid`, valid visibility/category, and no client-supplied moderation/publication fields.
- Post author updates cannot change `authorId`, `createdAt`, or server-owned moderation/publication fields.
- Client-side post count updates are no longer allowed by Firestore rules; counters must be maintained by Cloud Functions/Admin SDK.
- Testimonies, prayers, top-level comments, reposts, and post interactions require matching author/user identity.
- Prayer document reads are restricted to the author or followers.
- Follow edges require `followerId == request.auth.uid`, prevent self-follow, and disallow client updates.
- Top-level block docs are read-only to involved users and write-blocked for clients; Cloud Functions remain authoritative.
- Saved-post documents support legacy `{uid}_{postId}` IDs while requiring user ownership.
- Communities require verified owner/creator/admin identity for create/update/delete.
- Repost creates now require verified author identity, valid visibility, and an existing original post.
- Internal collections for moderation queue, reports, media uploads, analytics, impressions, and drafts now have explicit rules.

## Client Compatibility Fixes

- `FirebasePostService.fetchPostsByIds` now hydrates post IDs with direct document reads so post visibility rules evaluate per post instead of denying broad `whereIn` queries.
- Saved-post hydration now reads each saved post directly and skips unreadable/deleted posts.
- `RepliesModels` now hydrates parent posts with direct document reads instead of a broad `whereIn` query.
- `PostInteractionsService.getPostAuthorId` no longer bypasses post visibility with a list query.
- Discover feed, topic feed, and Firestore search fallback queries now include `visibility == "everyone"`.

## Validation

- Xcode build: PASS.
- Live diagnostics: PASS for `FirebasePostService.swift` and `SearchService.swift`; Xcode could not retrieve live diagnostics for several smaller changed files, but the full build passed.
- Local structural check: PASS (`COMPLETE_FIRESTORE_RULES.txt` brace balance is zero).
- Firebase CLI/emulator: NOT RUN here because the required CLI/runtime tools are not installed in this environment.

## Deployment Gate

Before deploying these rules, run the official Firebase rules validation/emulator in an environment with Firebase CLI installed:

```bash
firebase emulators:exec --only firestore '<your rules test command>'
firebase deploy --only firestore:rules --dry-run
```
