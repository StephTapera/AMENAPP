# Post System Audit

Date: 2026-05-24
Verdict: GO

## Summary

This pass audited and fixed the active AMEN post creation, rendering, visibility, media, share, and rules paths around `CreatePostView`, `PostCard`, `PostDetailView`, `AmenMediaDetailView`, `FirebasePostService`, `PostsManager`, Storage rules, and Firestore rules.

Repo-caused gaps fixed:
- Firestore rules now allow only the safe pending media-post envelope created by `CreatePostView` and still block final moderation outcomes from client writes.
- `CreatePostView` writes pending media posts as `status = moderating`, `moderationStatus = pending`, and `publicationVisibility = private_pending` until server moderation finalizes them.
- Algolia indexing now runs only for public, feed-eligible posts and records the actual visibility value.
- `Post` and `FirestorePost` propagate `moderationStatus`, `publicationVisibility`, and `status` so feeds, media grids, and search indexing can filter pending/removed states.
- `Post.isEligibleForFeedDisplay` and `Post.isMediaFeedEligible` now exclude pending, removed, flagged, non-public, and sensitive media states.
- `PostShareOptionsSheet` quick actions no longer swallow backend failures with `try?`; failures surface through sheet state and analytics.
- Storage `post_media/{authorUserId}/{postId}/{fileName=**}` now supports nested witness media and gates reads by owner or matching public/approved Firestore post state.
- Storage post media client mutation is blocked once the matching post is no longer raw/pending; approved media replacement and cleanup are server-owned.
- Legacy `posts/{userId}/{fileName}` reads are owner-only because the path has no post ID for visibility checks.
- Legacy flat `posts/images/{fileName}` client access is fully denied because ownership and visibility cannot be proven.
- Firestore post list reads now use the same `callerCanReadPost()` gate as direct gets, preventing draft, pending, removed, and blocked post leakage through queries.
- Firestore post, comment, and child-read helpers now share a `postPublicationReady` gate and match Swift's capitalized visibility raw values (`Everyone`, `Followers`).
- Community/private visibility states no longer pass through a public-account fallback when no membership rule can prove access.

## File Map

| Area | Active Files Reviewed | Status |
|---|---|---|
| Composer | `CreatePostView.swift`, `CreatePostCameraCoordinator.swift`, `CreatePostMediaViews.swift`, `CreatePostMediaMetadataViews.swift`, `CreatePostDraftViewModel.swift` | GO |
| Feed model/service | `PostsManager.swift`, `FirebasePostService.swift`, `PostsManager+RealtimeListeners.swift` | GO |
| Rendering | `PostCard.swift`, `PostDetailView.swift`, `PostCardRenderModel.swift`, `PostCardModerationBanner.swift` | GO |
| Media detail/feed | `AmenMediaDetailView.swift`, `MediaFeedViewModel.swift`, `PostMediaModels.swift` | GO |
| Share/save/report | `PostShareOptionsSheet.swift`, `PostCardReportSheet.swift`, `SavedPostsService.swift`, `RealtimeSavedPostsService.swift` | GO |
| Rules | `firestore 18.rules`, `firestore.deploy.rules`, `storage.rules` | GO |

## Flow Map

| Flow | Current Path | Status |
|---|---|---|
| Text post | `CreatePostView` -> Firestore `posts/{postId}` -> feed listeners -> `PostCard` | GO |
| Image post | `CreatePostView.uploadImages()` -> `post_media/{uid}/{postId}` -> Firestore pending post -> server finalization | GO |
| Witness/video media | `uploadWitnessAttachment()` -> nested `post_media/{uid}/{postId}/witness/...` -> media metadata on post | GO |
| Media grid | `MediaFeedViewModel` -> `Post.isMediaFeedEligible` | GO |
| Search indexing | `CreatePostView.syncPostToAlgolia` | GO |
| Report | `PostCardReportSheet` -> `ModerationService.reportPost` | GO |
| Share quick actions | `PostShareOptionsSheet` -> `SmartShareBackendService` | GO |

## Visibility Matrix

| Post State | Feed | Profile | Discover | Media Detail | Search | Share | Rules | Status |
|---|---|---|---|---|---|---|---|---|
| public / approved | Visible | Visible | Eligible | Eligible | Indexed | Shareable | Allowed | GO |
| followers | Public feed excluded | Relationship-gated | Not public discover | Public media grid excluded | Not indexed | Only if surfaced to caller | `callerCanReadPost()` follow index | GO |
| community/private/draft | Not eligible | Owner/moderator unless dedicated membership rule proves access | Not eligible | Owner-only media | Not indexed | Not public-share eligible | Draft/status constrained | GO |
| pending moderation | Filtered | Owner/moderator only | Not eligible | Owner-only media | Not indexed | Not public-share eligible | Pending envelope only | GO |
| removed/flagged | Filtered | Filtered | Not eligible | Not eligible | Not indexed | Not public-share eligible | Server-owned flags | GO |
| blocked author | Filtered where surfaced | Block-gated | Block-gated | Block-gated through post state | Not indexed | Not public-share eligible | `callerIsBlockedByAuthor` | GO |

## Button Wiring Matrix

| Button / Action | File | Backend / Service | Loading/Error | A11y | Status |
|---|---|---|---|---|---|
| Publish post | `CreatePostView.swift` | Firestore posts + media upload + moderation services | Yes | Present | GO |
| Media picker/camera | `CreatePostView.swift` | Photos/camera coordinator | Yes | Present | GO |
| Retry/cancel upload | `CreatePostView.swift` | Upload capsule state + cleanup paths | Yes | Accessibility announcements | GO |
| Report post | `PostCardReportSheet.swift` | `ModerationService.reportPost` | Yes | Labels/hints present | GO |
| Save/bookmark | `SavedPostsService.swift`, `RealtimeSavedPostsService.swift`, `PostCard.swift` | Saved post services | Yes | Present | GO |
| Share quick save/note/reminder/reflection/discussion | `PostShareOptionsSheet.swift` | `SmartShareBackendService` | Yes | Existing controls | GO |
| Open media/profile/comments | `PostCard.swift`, `PostDetailView.swift` | Navigation/sheets | Yes | Present | GO |

## Backend Callable Matrix

| Capability | Path / Service | Auth/App Check | Status |
|---|---|---|---|
| Post create | Direct Firestore write plus moderation functions | Auth + rules | GO |
| Media metadata | `mediaMeta` subcollections | Server-only rules | GO |
| Reports | `ModerationService.reportPost` | Auth required by service/rules | GO |
| Smart share actions | `SmartShareBackendService` | Service-backed | GO |
| AI captions/moments/transcripts | `posts/{postId}/mediaMeta/*` | Server-only rules | GO |

## Firestore / Storage Rules Matrix

| Rules Area | Finding | Fix / Status |
|---|---|---|
| `posts/{postId}` create | Composer media posts use pending moderation/publication fields | Safe pending envelope allowed; final outcomes blocked |
| `posts/{postId}` list | Broad authenticated list could leak documents through under-scoped queries | List now requires `callerCanReadPost()` |
| Post server-owned fields | Clients must not set final moderation/generated fields | Blocked |
| `mediaMeta`, `captionTracks`, `keyMoments` | Generated AI/media metadata must be server-owned | Server-only writes |
| `post_media/{uid}/{postId}/{fileName=**}` | Needed nested witness support, visibility-aware reads, and immutable approved media | Owner or public/approved matching post read; client mutation only while raw/pending |
| `posts/{userId}/{fileName}` | No post ID for visibility validation | Owner-only read/write/delete |
| `posts/images/{fileName}` | Flat legacy path cannot prove ownership | All client access denied |

## Media Upload Matrix

| Item | Status |
|---|---|
| Image upload path | `post_media/{uid}/{postId}/image_N.jpg`, owner write |
| Witness upload path | Nested `post_media/{uid}/{postId}/witness/...`, owner write |
| Content type | Explicit image/video allowlists |
| Size limits | Storage rules enforce post media size limits |
| Moderation | Image moderation before upload; media posts create as pending/moderating |
| Cleanup | Pending cleanup paths tracked and cleared on success/failure |
| Metadata consistency | Post stores URLs, storage paths, media count, and pending envelope |
| Read authorization | Owner until public/approved post state; legacy unsafe paths denied |
| Approved media immutability | Client create/update/delete blocked after post leaves raw/pending state |

## AI Post Intelligence Matrix

| Feature | Status |
|---|---|
| AI usage disclosure | `PostAIUsage` carried by post model |
| Captions/key moments/transcripts | Server-owned subcollections; client read only |
| Explain video | Server-owned media metadata path |
| Search indexing | Skips non-public/pending posts |
| User approval | Generated media metadata models require approved status before public display |

## Dead / Duplicate Code Matrix

| Item | Files | Risk | Fix | Removed/Kept |
|---|---|---|---|---|
| Duplicate post services | `FirebasePostService`, `RealtimePostService`, `ServicesPostService` | Managed by active routing | Active shared filters tightened | Kept |
| Duplicate media detail/render models | `AmenMediaDetailView`, `PostMediaModels`, legacy image arrays | Managed by shared eligibility | `Post.isMediaFeedEligible` tightened | Kept |
| Backup controller | `PostViewController_BACKUP.swift` | Not active in SwiftUI post path | No active route found in this pass | Kept |
| Firestore source vs deploy rules | `firestore 18.rules`, `firestore.deploy.rules` | Drift risk | Patched both for post list/create gates | Kept |

## Liquid Glass Matrix

| Surface | Status |
|---|---|
| Composer controls | Control chrome/capsules only |
| Share sheet | Behavior fixed; no content-card glass added |
| Post body cards | No new glass body card added |
| Media overlays | Readable overlays preserved |
| Accessibility | Upload capsule announcements and share errors visible |

## Tests / Validation

Run in this pass:
- Xcode live diagnostics passed for `CreatePostView.swift`, `FirebasePostService.swift`, `PostsManager.swift`, `PostShareOptionsSheet.swift`, and `AmenCommunitySpaceTabs.swift`.
- Rule diffs verified in `storage.rules`, `firestore 18.rules`, and `firestore.deploy.rules` for pending media read gating, approved-media immutability, capitalized visibility values, post list gating, and comment/child-read publication gates.

Environment-limited validation:
- The MCP Xcode build wrapper timed out before a useful compile log.
- Direct `xcodebuild` could not resolve packages inside this assistant sandbox because SwiftPM diagnostic writes to `~/Library/Caches/org.swift.swiftpm/...` were denied by OS permissions before app compilation began.
- The default shell still does not expose `npm` or a Firebase CLI binary, so backend lint/test/tsc and Firebase dry-run could not execute in this assistant environment.

## Exact Deploy Commands

```sh
npm --prefix functions run lint -- --quiet
npm --prefix functions run test
npm exec --prefix functions -- tsc --noEmit
firebase deploy --only functions,firestore:rules,firestore:indexes,storage --dry-run
xcodebuild -project AMENAPP.xcodeproj -scheme AMENAPP -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build test
```

## Rollout Recommendation

GO for the repo-caused post/CreatePostView gaps addressed in this pass. Deploy the updated Firestore and Storage rules with the functions build after running the commands above in a normal developer shell with Xcode, CoreSimulator, SwiftPM cache, npm, and Firebase CLI access.
