# HANDOFF-A1 — LiquidReplyPreviewRotation Backend Agent

**CONTRACT.md version read**: 1.0.1 — 2026-05-26
**Completed**: 2026-05-26

---

## Files Changed

| File | Change type | Notes |
|------|-------------|-------|
| `Backend/functions/src/replyPreview.ts` | Modified | Three targeted fixes described below |
| `Backend/functions/src/index.ts` | Pre-existing, no change needed | `onReplyCreate`, `rebuildReplyPreviews`, `rebuildReplyPreviewsOnDirty` were already exported on line 168 |

### Helper files consumed (read-only, not changed)

| File | Role |
|------|------|
| `Backend/functions/src/moderation/previewModerationProvider.ts` | Text safety gate used inside `isSafeRawComment` and `safetyPassedForText` |
| `Backend/functions/src/ranking/dynamicReplyPreviewRanking.ts` | Secondary scoring layer (`rankDynamicReplyCandidate`) applied on top of CONTRACT §15 formula |
| `Backend/functions/src/utils/previewLogger.ts` | Structured logging via `logPreviewEvent` / `logPreviewError` |

---

## Function Signatures Exported

```typescript
// Backend/functions/src/index.ts line 168
export { onReplyCreate, rebuildReplyPreviews, rebuildReplyPreviewsOnDirty } from "./replyPreview";
```

### `onReplyCreate`

```typescript
export const onReplyCreate = onDocumentCreated(
    "posts/{postId}/comments/{commentId}",
    async (event) => { ... }
)
```

Trigger: Firestore `onCreate` on `posts/{postId}/comments/{commentId}`.

Behaviour (after fixes):
- Runs a Firestore transaction that reads the current `replyCount` from the post doc, increments it by 1 (`FieldValue.increment(1)`), and checks whether the transition `previousCount < threshold AND newCount >= threshold` is true for any value in `[5, 12, 30, 75]`.
- If a threshold is crossed: sets `previewDirty = true` inside the same transaction write (no separate call).
- If no threshold is crossed: only increments `replyCount`, logs the skip.
- Does NOT call `performRebuild` directly. The `rebuildReplyPreviewsOnDirty` trigger handles execution.

### `rebuildReplyPreviews`

```typescript
export const rebuildReplyPreviews = onCall(
    { enforceAppCheck: true },
    async (request) => { ... }
): Promise<{ status: "ok"; previewsWritten: number }>
```

Callable invocation (admin / manual):
- Enforces `request.app != undefined` (App Check) and `request.auth` (Firebase Auth). Throws `unauthenticated` for either missing.
- Requires `request.data.postId: string`. Throws `invalid-argument` if absent or empty.
- Calls `performRebuild` and returns `{ status: "ok", previewsWritten: number }`.

### `rebuildReplyPreviewsOnDirty`

```typescript
export const rebuildReplyPreviewsOnDirty = onDocumentUpdated(
    "posts/{postId}",
    async (event) => { ... }
)
```

Trigger: Firestore `onUpdate` on `posts/{postId}`.
- Guards: only runs when `before.previewDirty !== true` AND `after.previewDirty === true` (exact false->true transition).
- Calls `performRebuild` with `reason: "dirty_flag_rebuild"`.

---

## What Was Already Implemented (Pre-existing)

The majority of the implementation already existed in `replyPreview.ts` when this agent read the file:

- All internal types (`RawComment`, `ReplyCandidate`, `DynamicReplyPreviewDoc`, `CommunityPulse`)
- CONTRACT §15 scoring formula (`contractCompositeScore`)
- Safety helpers (`isSafeRawComment`, `safetyPassedForText`)
- Score sub-components (`computeRelevanceScore`, `computeSpiritualUsefulness`, `computeEngagementScore`)
- `toReplyCandidate` mapping
- Community pulse detector (`detectCommunityPulseFromCandidates`, `SPIRITUAL_THEMES`)
- Preview doc builders (`buildSingleReplyDoc`, `buildAggregateDoc`, `buildBereanInsightDoc`)
- Resolver ladder (`runResolverLadder`) implementing all five steps from CONTRACT §13
- Follow-graph loader (`loadViewerFollowsForPost`)
- Core rebuild logic (`performRebuild`) — batch writes subcollection, deletes stale docs, denormalises onto post, sets `previewDirty = false`
- All three exported Cloud Function definitions
- All three exports in `index.ts`

---

## Specific Changes Made

### 1. `performRebuild` return type: `Promise<void>` -> `Promise<number>`

The function now returns the count of preview documents written. Early exits return `0`. The catch block returns `0` for trigger-initiated calls (the callable path re-throws before reaching `return 0`).

### 2. `markDirtyIfThresholdCrossed` — threshold semantics and transaction

**Before**: Read a `.count()` aggregate, checked `DIRTY_THRESHOLDS.includes(replyCount)` (exact equality), then wrote `replyCount` then `previewDirty`, then called `performRebuild` inline.

**After**:
- Uses `db.runTransaction` to atomically read `post.replyCount`, compute `newCount = previousCount + 1`, and check `DIRTY_THRESHOLDS.some(t => previousCount < t && newCount >= t)` (crossing semantics).
- Writes `replyCount: FieldValue.increment(1)` in every case.
- Writes `previewDirty: true` only when a threshold is crossed — same `tx.set` call.
- Does NOT call `performRebuild` inline; the `rebuildReplyPreviewsOnDirty` trigger fires from the dirty flag write.

This is more correct because: (a) exact-equality would miss thresholds if the count jumped by 2+ in quick succession; (b) calling `performRebuild` inline caused the Firestore trigger to also fire, resulting in duplicate rebuilds.

### 3. Callable return value

**Before**: `return { success: true, postId: postId.trim() }`

**After**: `return { status: "ok", previewsWritten }` — matches CONTRACT.md §12 exactly.

---

## Deviations from CONTRACT.md

None. All deviations from the CONTRACT.md specification were pre-existing in the file before this agent made changes. The three changes above bring the implementation into full compliance.

---

## Known Limitations

1. **`replyCount` bootstrap dependency**: The transaction reads `post.replyCount` from the post document to determine the previous count. If the field does not yet exist on the post doc (e.g., the first comment on a brand-new post), `previousCount` defaults to `0`. This means threshold crossing at count=5 requires that all prior comments also went through `onReplyCreate` (so the field is always present after the first comment). A one-time backfill job may be needed for legacy posts.

2. **`spiritualUsefulness` scoring**: The `computeSpiritualUsefulness` function uses keyword/regex heuristics. Full semantic scoring (e.g., embedding-based) is outside scope for this agent per the task specification.

3. **Callable App Check enforcement**: `enforceAppCheck: true` is set, which requires App Check to be configured in the Firebase project. In dev/test environments without App Check registration the callable will reject all requests.

4. **Stale preview doc cleanup**: The batch that deletes stale preview docs reads the entire `dynamicReplyPreviews` subcollection before the write. At very high preview doc counts this could be slow; it is bounded by `MAX_PREVIEW_DOCS = 6` on the write side, so in practice the subcollection remains small.

5. **`rebuildReplyPreviewsOnDirty` re-entrance**: If the trigger fires and `performRebuild` throws before setting `previewDirty = false`, the post doc is left dirty. The function will be re-triggered on the next post doc write (e.g., a reaction), not immediately retried. A Cloud Tasks-based retry is not in scope per the task instructions.
