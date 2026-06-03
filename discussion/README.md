# AMEN Discussion System — V1

## What was built

| Feature | Status | Files |
|---|---|---|
| Nested, collapsible thread (depth 0–2) | ✅ Complete | `discussion/index.html`, `discussion/prototypes/thread-view.html` |
| Pre-Post Threshold (3-step gate) | ✅ Complete | `discussion/index.html`, `discussion/prototypes/threshold-composer.html` |
| Consume-nudge (< 80% watched) | ✅ Complete | Step 1 of threshold |
| Transcript parity path + override | ✅ Complete | "Read Transcript" / "Post anyway" |
| Duplicate check (cosine similarity) | ✅ Complete | Step 2 — mock adapter when `EMBEDDING_KEY` absent |
| Destination choice | ✅ Complete | Step 3 — Public / Reflection / Church Notes |
| Ask Berean (thread AI) | ✅ Complete | `discussion/prototypes/thread-view.html`, backend in `discussionFunctions.js` |
| Behavior-based reputation + badge | ✅ Complete | Helpful marks, accepted answers, points math |
| Inline verse context cards | ✅ Complete | `discussion/index.html`, `discussion/prototypes/context-card.html` |
| Cloud Functions (backend) | ✅ Complete | `functions/discussionFunctions.js`, `functions/src/discussion/` (TypeScript) |
| TypeScript types + API contracts | ✅ Complete | `contracts/types.ts`, `contracts/api.ts`, `contracts/schema.md` |
| Unit tests | ✅ Complete | `functions/src/discussion/discussion.test.ts` |

## What's stubbed (out of scope — extension points)

```
// TODO: Voice transcription pipeline
//   Extension point: functions/src/discussion/callable.ts → transcribeVoiceComment()
//   Schema: voiceTranscripts/{commentId} in schema.md

// TODO: Engagement heat map
//   Extension point: watchProgress tracking → aggregate per-second data
//   Schema: heatMapSessions/{sessionId} in schema.md

// TODO: Community memory (AI-indexed knowledge across threads)
//   Extension point: askBerean → store indexed summaries → retrieval at compose time

// TODO: Mediator escalation
//   Extension point: Firestore reportedAt trigger → mediatorEscalations collection

// TODO: Creator dashboard (thread analytics, engagement rates)
//   Extension point: computeReputation → aggregate per-thread for creator

// TODO: Full moderation OS integration
//   Current: isLocked / lockedReason on thread doc
//   Extension: wire into existing AMEN moderation pipeline

// TODO: iOS native port
//   Contracts are at /contracts/*.ts — types map directly to Swift Codable structs
//   See ONE/CONTRACTS.md for Swift type examples
```

## How to run (local prototype — no Firebase needed)

```bash
# Open the integrated prototype directly in a browser
open discussion/index.html

# Or open individual component prototypes
open discussion/prototypes/thread-view.html       # Thread + Ask Berean panel
open discussion/prototypes/threshold-composer.html # Pre-Post Threshold flow
open discussion/prototypes/context-card.html       # Inline verse reference cards
```

All prototypes are self-contained HTML files. No build step. No network required (Google Fonts are optional for typography).

## How to run with Firebase Emulator

```bash
# 1. Install emulator suite (one-time)
npm install -g firebase-tools
firebase login

# 2. Start emulators
cd /path/to/repo
firebase emulators:start --only functions,firestore,auth

# 3. Set environment variables for mock adapters (optional — mock works without keys)
firebase functions:config:set berean.llm_key="your-gemini-key"
firebase functions:config:set embedding.key="your-embedding-key"

# 4. The functions are registered in functions/index.js as:
#    exports.askBerean, exports.detectDuplicate, etc.
```

## How to deploy (🛑 STOP — requires explicit approval)

**Do NOT run this without orchestrator approval.**

```bash
firebase deploy --only functions:askBerean,detectDuplicate,computeReputation,postComment,markHelpful,updateWatchProgress,getWatchProgress --project amen-5e359
```

Before deploying:
1. Set `BEREAN_LLM_KEY` secret in GCP Secret Manager
2. Set `EMBEDDING_KEY` secret in GCP Secret Manager
3. Deploy Firestore rules update (from `contracts/schema.md` indexes)
4. Deploy Firestore indexes for `threads/{threadId}/comments` queries

## Key architecture decisions

- **Flat comments subcollection**: Comments live at `threads/{threadId}/comments/{commentId}`. Nesting is represented by `parentCommentId` + `depth`. The client assembles the tree — Firestore can't query recursively nested subcollections.
- **Mock-first AI**: Both `askBerean` and `detectDuplicate` work without API keys. The mock adapter returns realistic placeholder data. Set keys via env to enable real AI.
- **Embedding is async**: When a comment is posted, the body is queued in `embeddingQueue/{commentId}`. The embedding is written back to the comment doc by a separate worker (not yet built). The `detectDuplicate` function handles `embedding: null` gracefully.
- **Reputation is append-only**: `reputationEvents` is never deleted. `computeReputation` aggregates on read. This gives a full audit trail.
- **Threshold is never a hard lock**: "Post anyway" is always available in Step 1. The threshold is a nudge, not a gate.

## Firestore indexes needed (deploy before using with emulator/prod)

```json
{
  "indexes": [
    {
      "collectionGroup": "comments",
      "queryScope": "COLLECTION",
      "fields": [
        {"fieldPath":"threadId","order":"ASCENDING"},
        {"fieldPath":"isDeleted","order":"ASCENDING"},
        {"fieldPath":"createdAt","order":"ASCENDING"}
      ]
    },
    {
      "collectionGroup": "comments",
      "queryScope": "COLLECTION",
      "fields": [
        {"fieldPath":"isDeleted","order":"ASCENDING"},
        {"fieldPath":"embedding","order":"ASCENDING"}
      ]
    },
    {
      "collectionGroup": "reputationEvents",
      "queryScope": "COLLECTION",
      "fields": [
        {"fieldPath":"toUID","order":"ASCENDING"},
        {"fieldPath":"createdAt","order":"DESCENDING"}
      ]
    },
    {
      "collectionGroup": "reputationEvents",
      "queryScope": "COLLECTION",
      "fields": [
        {"fieldPath":"fromUID","order":"ASCENDING"},
        {"fieldPath":"commentId","order":"ASCENDING"},
        {"fieldPath":"type","order":"ASCENDING"}
      ]
    }
  ]
}
```
