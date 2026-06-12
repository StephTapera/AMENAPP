# Sanctuary Function Signatures

Frozen: 2026-06-12  
Version: `2026-06-12-wave0-v1`  
Rule: all functions require Auth and App Check. All AI calls run through Firebase callable or HTTP proxies; no client API keys.

| Function | Transport | Request | Response | Notes |
| --- | --- | --- | --- | --- |
| `sanctuaryTranscribe` | Callable | `{ videoId: string }` | `{ videoId: string, transcriptDocPath: string, status: "pending" | "processing" | "ready" | "failed" }` | Starts or resumes transcript generation. Status events write to `livingVideos/{id}` and transcript chunk docs. |
| `sanctuaryAnchorScripture` | Callable | `{ videoId: string }` | `{ videoId: string, anchors: ScriptureAnchor[] }` | Uses explicit references plus Berean semantic detection. `verseRef` must be canonical OSIS. |
| `sanctuaryAskMoment` | HTTP SSE | `{ videoId: string, timestampMs: number, question: string }` | `text/event-stream` with citation-bearing chunks | Berean RAG over transcript, anchors, and visible layer context. Moderation middleware is mandatory. |
| `sanctuaryReact` | Callable | `{ videoId: string, reaction: SacredReaction }` | `{ accepted: true, bucketIndex: number }` | Writes raw reaction only. No aggregate counts returned. Rate limited per user/video. |
| `sanctuaryReactionField` | Callable | `{ videoId: string }` | `{ videoId: string, buckets: number[], bucketDurationMs: number, updatedAt: string }` | Server-computed density field only. Values normalized `0...1`; raw counts never leave server. |
| `sanctuaryRoomSync` | Callable | `{ roomId: string, op: WatchRoomSyncOp }` | `{ room: WatchRoom, serverTimeMs: number, correctionMs?: number }` | Firestore-backed playhead sync with drift correction. |
| `sanctuarySearch` | Callable | `{ query: string, scope: SanctuarySearchScope }` | `{ results: SanctuarySearchResult[] }` | Cross-video semantic and keyword search. Results deep-link to timestamps. |
| `sanctuaryWeeklyDigest` | Scheduled | `{ creatorId?: string }` internal payload | `{ digestsWritten: number }` log summary | Server-only scheduled digest. No client callable surface. |

## Support Types

```ts
export type WatchRoomSyncOp =
  | { type: "join"; member: SanctuaryUserRef }
  | { type: "leave"; uid: string }
  | { type: "play"; playheadMs: number }
  | { type: "pause"; playheadMs: number }
  | { type: "prayer"; playheadMs: number }
  | { type: "seek"; playheadMs: number };

export type SanctuarySearchScope = {
  visibility: "mine" | "community" | "public";
  contentTypes?: LivingVideoContentType[];
  verseRefs?: string[];
  creatorIds?: string[];
};

export type SanctuarySearchResult = {
  videoId: string;
  timestampMs: number;
  title?: string;
  snippet: string;
  verseRefs: string[];
  score: number;
};
```

## Acceptance Checklist

| Function | Wave 2 Owner | Emulator Test | Demo Command | Status |
| --- | --- | --- | --- | --- |
| `sanctuaryTranscribe` | B1 | Pending | Pending | Pending |
| `sanctuaryAnchorScripture` | B2 | Pending | Pending | Pending |
| `sanctuaryAskMoment` | B4 | Pending | Pending | Pending |
| `sanctuaryReact` | B3 | Pending | Pending | Pending |
| `sanctuaryReactionField` | B3 | Pending | Pending | Pending |
| `sanctuaryRoomSync` | B3 | Pending | Pending | Pending |
| `sanctuarySearch` | B1 | Pending | Pending | Pending |
| `sanctuaryWeeklyDigest` | B3 | Pending | Pending | Pending |
