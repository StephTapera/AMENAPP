# Discussion System — Firestore Schema
# Version: 1.0.0 | Status: FROZEN (Phase 0)
# Amendment requires: RUNLOG entry + orchestrator approval

---

## Design Principles

- Comments are stored in a **flat subcollection** under their thread.
  Nesting is represented by `parentCommentId` + `depth`, not recursive subcollections.
  Max depth: 3 (root comment → reply → reply-to-reply). Client collapses beyond that.
- `watchProgress` uses a composite doc ID (`{uid}_{postId}`) for O(1) lookups.
- `reputationEvents` is a root collection (not per-user) so Cloud Functions can
  run cross-user aggregations in a single query.
- `contextRefs` is a root cache keyed by canonical verse key (e.g. `JHN.3.16`).
  Comments store an array of verseKeys; the client resolves them from this cache.

---

## Collection: `threads`

**Path:** `threads/{threadId}`

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Firestore doc ID |
| `postId` | string | ID of the Amen post this thread is anchored to |
| `postAuthorUID` | string | UID of the post's author |
| `postType` | `"text" \| "video" \| "audio" \| "image"` | Drives consume-nudge logic |
| `transcriptRef` | string \| null | Storage path to text transcript; enables parity path |
| `createdAt` | Timestamp | Server timestamp |
| `updatedAt` | Timestamp | Server timestamp; updated on each new comment |
| `commentCount` | number | Denormalized; incremented by CF, never by client |
| `isLocked` | boolean | Moderation lock; new comments blocked when true |
| `lockedReason` | string \| null | Human-readable reason shown to users |
| `bereanSummaryRef` | string \| null | Doc path of latest Ask Berean result |

**Indexes required:**
- `postId ASC, createdAt DESC` (look up thread for a post)

---

## Collection: `threads/{threadId}/comments`

**Path:** `threads/{threadId}/comments/{commentId}`

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Firestore doc ID |
| `threadId` | string | Denormalized for CF queries |
| `authorUID` | string | |
| `authorDisplayName` | string | Snapshot at write time |
| `authorAvatarURL` | string \| null | Snapshot at write time |
| `parentCommentId` | string \| null | null = root comment |
| `depth` | number | 0 = root, 1 = reply, 2 = reply-to-reply (max) |
| `body` | string | Max 2,000 characters |
| `verseKeys` | string[] | Canonical verse keys, e.g. `["JHN.3.16"]`; may be empty |
| `destination` | `"public" \| "reflection" \| "churchNotes"` | Chosen in Pre-Post Threshold step 3 |
| `helpfulCount` | number | Denormalized; incremented by CF |
| `isAcceptedAnswer` | boolean | Set by thread owner (postAuthorUID) |
| `isDeleted` | boolean | Soft-delete; body replaced with tombstone text server-side |
| `deletedAt` | Timestamp \| null | |
| `createdAt` | Timestamp | Server timestamp |
| `updatedAt` | Timestamp \| null | Set if body is edited |
| `reportedAt` | Timestamp \| null | Set server-side on first report; comment locked |
| `thresholdPassedAt` | Timestamp | When the Pre-Post Threshold completed (for analytics) |
| `embedding` | number[] \| null | 768-d embedding; written by CF after comment creation;
used by `detectDuplicate` |

**Indexes required:**
- `threadId ASC, parentCommentId ASC, createdAt ASC` (thread render)
- `threadId ASC, parentCommentId == null, createdAt ASC` (root comments only)
- `threadId ASC, isAcceptedAnswer ASC, createdAt DESC` (accepted answers first)

---

## Collection: `reputationEvents`

**Path:** `reputationEvents/{eventId}`

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Firestore doc ID |
| `type` | `"helpfulMark" \| "acceptedAnswer" \| "firstComment" \| "bereanCite"` | |
| `fromUID` | string | Who triggered the event (helpful-mark giver, post author, system) |
| `toUID` | string | Who receives the reputation points |
| `commentId` | string | The comment that earned the event |
| `threadId` | string | Denormalized |
| `points` | number | Points awarded; see table below |
| `createdAt` | Timestamp | Server timestamp |

**Points table:**
| Type | Points |
|------|--------|
| `helpfulMark` | +3 |
| `acceptedAnswer` | +10 |
| `firstComment` | +1 |
| `bereanCite` | +2 (comment contains ≥1 verseKey, verified by CF) |

**Indexes required:**
- `toUID ASC, createdAt DESC` (compute total for a user)
- `commentId ASC` (prevent duplicate helpful-marks per user per comment)

---

## Collection: `watchProgress`

**Path:** `watchProgress/{docId}`
**Doc ID pattern:** `{uid}_{postId}` (client constructs; CF validates format)

| Field | Type | Notes |
|-------|------|-------|
| `uid` | string | User who watched |
| `postId` | string | Post being watched |
| `progressFraction` | number | 0.0–1.0; last known playback position / duration |
| `durationSecs` | number | Total media duration in seconds |
| `watchedSecs` | number | Cumulative seconds watched (deduplicated by CF) |
| `transcriptRead` | boolean | True if user opened the transcript parity path |
| `updatedAt` | Timestamp | Server timestamp |

**Indexes required:**
- `uid ASC, postId ASC` (threshold lookup — covered by composite doc ID pattern)

---

## Collection: `contextRefs`

**Path:** `contextRefs/{verseKey}`
**Doc ID:** Canonical OSIS verse key, e.g. `JHN.3.16`, `GEN.1.1`, `PSA.23.1`

| Field | Type | Notes |
|-------|------|-------|
| `verseKey` | string | OSIS key (doc ID) |
| `bookName` | string | Human-readable, e.g. "John" |
| `chapterNumber` | number | |
| `verseNumber` | number | |
| `displayRef` | string | e.g. "John 3:16" |
| `textESV` | string | ESV translation text (≤500 chars) |
| `textKJV` | string | KJV translation text (≤500 chars) |
| `textNIV` | string \| null | NIV translation text |
| `crossRefs` | string[] | Up to 5 related verse keys |
| `cachedAt` | Timestamp | When this entry was written/refreshed |

**Note:** This collection is a pre-populated or lazily-populated cache.
The `detectDuplicate` CF may write new entries when a new verse key appears.
Client reads from this collection directly (no CF needed); security rules allow
unauthenticated reads.

---

## Out-of-scope stubs (not built in V1)

```
// TODO: voiceTranscripts — STT pipeline output per recording
// TODO: heatMapSessions — per-second engagement data for heat map overlay
// TODO: communityMemory — AI-indexed community knowledge across threads
// TODO: mediatorEscalations — elevated conflict resolution queue
// TODO: creatorDashboard — thread analytics, revenue from paid threads
```
