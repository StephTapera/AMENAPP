# HANDOFF-A2 — Backend Agent (Dynamic Reply Preview)

**Contract version consumed**: CONTRACT.md 1.0.1 — 2026-05-26
**Completed**: 2026-05-26
**Agent**: A2 (Backend)

---

## Deliverables

### New file
`Backend/functions/src/replyPreview.ts`

CONTRACT.md-authoritative implementation of `onReplyCreate` and `rebuildReplyPreviews`.

### Modified file
`Backend/functions/src/index.ts`

Replaced `export * from "./generateDynamicReplyPreviews"` with an explicit named-export list
(omitting `onReplyCreate` and `rebuildReplyPreviews`) to avoid duplicate-export conflicts, then
added the three canonical exports from `replyPreview.ts`.

---

## Functions implemented in replyPreview.ts

| Export | Type | CONTRACT.md reference |
|--------|------|-----------------------|
| `onReplyCreate` | Firestore `onCreate` trigger — `posts/{postId}/comments/{commentId}` | §12, §16 |
| `rebuildReplyPreviews` | HTTPS callable (`enforceAppCheck: true`) | §12, §13, §15 |
| `rebuildReplyPreviewsOnDirty` | Firestore `onUpdate` trigger — `posts/{postId}` (dirty flag) | §12 |

---

## Implementation notes

### onReplyCreate (§12, §16)
- Fetches live `comments` count via `count()` aggregation query.
- Denormalizes `replyCount` onto `posts/{postId}` on every create.
- Marks `previewDirty = true` only when count hits an exact threshold in `[5, 12, 30, 75]`.
- Immediately enqueues `performRebuild` inline (no Cloud Tasks dependency at this scale).

### rebuildReplyPreviews callable (§12, §13, §15)
- Requires App Check + Firebase Auth; throws `HttpsError` on either missing.
- Loads up to 60 most-recent comments ordered by `createdAt desc`.
- Converts each `RawComment → ReplyCandidate` using the exact scoring components:
  - `relevanceScore`: text-length curve
  - `spiritualUsefulness`: keyword gate
  - `engagementScore`: positive reactions minus 2× reports, clamped to [0,1]
- Passes each through the `rankDynamicReplyCandidate` module for full signal blending.
- Filters to `safetyPassed == true` only (on-write moderation gate).

### Resolver ladder (§13)
```
Step 1 — followedReply:   safeCandidates where authorUID ∈ viewerFollows → argmax compositeScore
Step 2 — bereanInsight:   replyCount ≥ 12 AND communityPulse.confidence ≥ 0.72 AND safetyPassed
Step 3 — communityPulse:  replyCount ≥ 5 → aggregate spiritual themes across last-30 comments
Step 4 — topReply:        safeCandidates sorted by compositeScore desc, exclude followedReply author
Step 5 — nil (empty list)
```

### Scoring formula (§15, verbatim)
```
compositeScore = 0.35 × relevanceScore
              + 0.25 × spiritualUsefulness
              + 0.25 × engagementScore
              + 0.15 × recencyScore

recencyScore = 1.0 - min(1.0, hoursSinceCreated / 168.0)
```

### Firestore writes (§11)
- Writes `DynamicReplyPreview` docs to `posts/{postId}/dynamicReplyPreviews/{id}`.
- Deletes stale docs from previous build not present in new result set.
- Sets `posts/{postId}.dynamicReplyPreviewCandidates` (denormalized, non-viewer-specific types only).
- Sets `posts/{postId}.previewDirty = false` and updates `posts/{postId}.replyCount`.
- Updates `posts/{postId}/dynamicReplyPreviewMeta/state.lastRefreshedAt`.

### rebuildReplyPreviewsOnDirty (§12)
- Guards: only fires when `before.previewDirty !== true && after.previewDirty === true`.
- Calls `performRebuild` with reason `"dirty_flag_rebuild"`.

---

## Relationship to generateDynamicReplyPreviews.ts

`generateDynamicReplyPreviews.ts` is a prior comprehensive implementation that ships many
additional triggers (avatar refresh, post-delete cascade, block-relationship, scheduled refresh).
It remains unchanged and its non-conflicting exports are preserved in `index.ts`.

`replyPreview.ts` is the CONTRACT.md-canonical source for the two named symbols
(`onReplyCreate`, `rebuildReplyPreviews`). The `index.ts` wires:

```ts
// generateDynamicReplyPreviews.ts — all auxiliary functions, minus the two conflicting names
export { onCommentCreatedUpdatePreviews, onCommentDeletedUpdatePreviews, ... } from "./generateDynamicReplyPreviews";

// replyPreview.ts — contract-exact implementations
export { onReplyCreate, rebuildReplyPreviews, rebuildReplyPreviewsOnDirty } from "./replyPreview";
```

---

## TypeScript build status

`tsc --noEmit` exits 0 — no type errors.

---

## Dependencies used

| Module | Path |
|--------|------|
| `moderatePreviewText` | `./moderation/previewModerationProvider` |
| `rankDynamicReplyCandidate` | `./ranking/dynamicReplyPreviewRanking` |
| `logPreviewEvent`, `logPreviewError` | `./utils/previewLogger` |
| `firebase-admin` | admin SDK (Firestore) |
| `firebase-functions/v2/firestore` | `onDocumentCreated`, `onDocumentUpdated` |
| `firebase-functions/v2/https` | `onCall`, `HttpsError` |

---

## What the next agents need

| Agent | Action |
|-------|--------|
| iOS / Navigation Agent | `openReplies(postId:highlightedReplyId:)` and `showReplyActions(postId:replyId:)` on `AmenUniversalContentRouter` (CONTRACT.md §19) |
| iOS / Component Agent | Wire `LiquidReplyPreviewRotator` in `PostCard` at line ~3200 (CONTRACT.md §18) |
| iOS / Feature-Flag Agent | Add `replyPreviewRotationEnabled` to `AMENFeatureFlags` (CONTRACT.md §17) |
| iOS / Analytics Agent | Add `replyPreviewShown`, `replyPreviewTapped`, `replyPreviewType` cases to `AMENAnalyticsEvent` (CONTRACT.md §14) |
| DevOps | Deploy `replyPreview.ts` functions to the `creator` codebase; update Firestore rules to allow subcollection reads on `posts/{postId}/dynamicReplyPreviews` |

---

## Amendments to CONTRACT.md

None. CONTRACT.md version 1.0.1 was consumed as-is. No symbols were changed or added.
