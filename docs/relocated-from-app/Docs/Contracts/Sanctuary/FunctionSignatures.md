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
| `sanctuaryTranscribe` | B1 | ✅ `B1 sanctuaryTranscribe rejects non-gs media and records failed status` | `XDG_CONFIG_HOME=/private/tmp/firebase-config FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 firebase --config firebase.sanctuary-emulator.json emulators:exec --only firestore,auth,functions "npm --prefix functions test -- --runTestsByPath src/sanctuary/sanctuary.test.ts"` | ✅ Emulator green |
| `sanctuaryAnchorScripture` | B2 | ✅ `B2 sanctuaryAnchorScripture writes explicit OSIS anchors from transcript chunks` | `XDG_CONFIG_HOME=/private/tmp/firebase-config FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 firebase --config firebase.sanctuary-emulator.json emulators:exec --only firestore,auth,functions "npm --prefix functions test -- --runTestsByPath src/sanctuary/sanctuary.test.ts"` | ✅ Emulator green |
| `sanctuaryAskMoment` | B4 | ✅ `B4 sanctuaryAskMoment streams citation and answer events over SSE` | `XDG_CONFIG_HOME=/private/tmp/firebase-config FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 firebase --config firebase.sanctuary-emulator.json emulators:exec --only firestore,auth,functions "npm --prefix functions test -- --runTestsByPath src/sanctuary/sanctuary.test.ts"` | ✅ Emulator green |
| `sanctuaryReact` | B3 | ✅ `B3 sanctuaryReact accepts text-free reactions and sanctuaryReactionField returns density only` | `XDG_CONFIG_HOME=/private/tmp/firebase-config FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 firebase --config firebase.sanctuary-emulator.json emulators:exec --only firestore,auth,functions "npm --prefix functions test -- --runTestsByPath src/sanctuary/sanctuary.test.ts"` | ✅ Emulator green |
| `sanctuaryReactionField` | B3 | ✅ `B3 sanctuaryReact accepts text-free reactions and sanctuaryReactionField returns density only` | `XDG_CONFIG_HOME=/private/tmp/firebase-config FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 firebase --config firebase.sanctuary-emulator.json emulators:exec --only firestore,auth,functions "npm --prefix functions test -- --runTestsByPath src/sanctuary/sanctuary.test.ts"` | ✅ Emulator green |
| `sanctuaryRoomSync` | B3 | ✅ `B3 sanctuaryRoomSync persists room presence and prayer state` | `XDG_CONFIG_HOME=/private/tmp/firebase-config FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 firebase --config firebase.sanctuary-emulator.json emulators:exec --only firestore,auth,functions "npm --prefix functions test -- --runTestsByPath src/sanctuary/sanctuary.test.ts"` | ✅ Emulator green |
| `sanctuarySearch` | B1 | ✅ `B1 sanctuarySearch returns timestamped keyword results and writes journey interaction` | `XDG_CONFIG_HOME=/private/tmp/firebase-config FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 firebase --config firebase.sanctuary-emulator.json emulators:exec --only firestore,auth,functions "npm --prefix functions test -- --runTestsByPath src/sanctuary/sanctuary.test.ts"` | ✅ Emulator green |
| `sanctuaryWeeklyDigest` | B3 | ✅ `B3 sanctuaryWeeklyDigest writes server-only creator digest documents` | `XDG_CONFIG_HOME=/private/tmp/firebase-config FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 firebase --config firebase.sanctuary-emulator.json emulators:exec --only firestore,auth,functions "npm --prefix functions test -- --runTestsByPath src/sanctuary/sanctuary.test.ts"` | ✅ Emulator green |
