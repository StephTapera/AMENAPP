# Amen Notebooks — HANDOFF (Connected Intelligence v1, Agent C)

Branch: `feature/connected-intelligence-20260609`

## What was built

Per-notebook grounded RAG. Create a notebook by `NotebookKind`, attach sources,
chunk → embed → upsert into a **per-notebook Pinecone namespace** (server-derived
`notebook-{uid}-{notebookId}`, stored as `Notebook.pineconeNamespace`, never
client-supplied). Queries retrieve grounding chunks and **cite-or-REFUSE** — no
index / no grounding ⇒ explicit ungrounded REFUSE, never an ungrounded answer.
Scripture-comparison legs route Claude-exclusive (`berean_answer`) with scripture
citations. Group notebooks share into a Space via `sharedWithSpaceId` (membership
enforced); contributions attributed but **no contribution counts** computed/shown.
Soft delete sets `deletedAt`; a daily `onSchedule` job hard-purges the whole
Pinecone namespace + the Firestore doc after a 7-day retention window.

## Files

| File | Lines | Role |
|---|---|---|
| `functions/connectedIntelligence/notebookFunctions.js` | 521 | 5 CFs (create/ingest/query/softDelete/purgeJob) |
| `src/features/notebooks/notebooksService.ts` | 161 | Client CF wrappers + Firestore list |
| `src/features/notebooks/NotebooksScreen.tsx` | 566 | All 6 UI states + explicit REFUSE state |
| `src/features/notebooks/index.ts` | 29 | Barrel — exports `NotebooksScreen` |

## CF exports (register in `functions/index.js`)

```js
const notebooks = require("./connectedIntelligence/notebookFunctions");
exports.notebookCreate     = notebooks.notebookCreate;     // onCall
exports.notebookIngest     = notebooks.notebookIngest;     // onCall
exports.notebookQuery      = notebooks.notebookQuery;      // onCall
exports.notebookSoftDelete = notebooks.notebookSoftDelete; // onCall
exports.notebookPurgeJob   = notebooks.notebookPurgeJob;   // onSchedule (daily 05:00 UTC)
```

All callables: `onCall` (gen2, us-central1) + auth guard (uid from `request.auth.uid`
only) + `enforceRateLimit`. Caps mirror `connectedIntelligence.config.ts → notebooks`
(`maxNotebooksFree:3`, `maxSourcesFree:10`, `maxSourcesPlus:100`).

## Firestore rules (add to `firestore.rules`, owner-scoped, server-writes-only)

Reuses existing helpers `isOwner(uid)` + `isAdminSDK()`. Place before the catch-all.

```
match /users/{uid}/notebooks/{notebookId} {
  // Owner may read + soft-delete-by-CF only; create/ingest/query mutate via Cloud
  // Functions (admin SDK). pineconeNamespace is server-derived — never client-written.
  allow read:   if isOwner(uid);
  allow create, update, delete: if isAdminSDK();
}
```

> All notebook writes (create, ingest source-ref/count bumps, soft-delete `deletedAt`,
> hard purge) go through the admin SDK in CFs. Clients only READ their own notebooks
> for the list view; every mutation is a callable. This keeps `pineconeNamespace`,
> `chunkCount`, and `sourceCount` un-forgeable.

## Pinecone / config flags

- Namespace pattern: **`notebook-{uid}-{notebookId}`** (derived in CF; in TS as
  `Notebook.pineconeNamespace`). Per-notebook isolation; no cross-notebook/-user reads.
- Embeddings: `openaiEmbedBatch` / `openaiEmbed` (`text-embedding-3-small`, 1536-dim).
- Upsert/query/purge via `functions/mlClients.js` (`pineconeUpsert`, `pineconeQuery`);
  whole-namespace purge uses Pinecone REST `deleteAll:true` (direct fetch in module).
- Secrets (already provisioned project-wide): `OPENAI_API_KEY`, `PINECONE_API_KEY`,
  `PINECONE_HOST`, `ANTHROPIC_API_KEY` (for `berean_answer` scripture legs).
- Server caps in `NOTEBOOK_CONFIG` mirror `connectedIntelligence.config.ts`. No new
  Remote Config flag added — Notebooks ships behind the surface's mount, not a kill switch.
- Retention before hard-purge: `PURGE_RETENTION_DAYS = 7`.

## Grounding / routing decisions (fail-closed)

- **REFUSE gate #1**: notebook `chunkCount === 0` ⇒ `{grounded:false, reason:'ungrounded'}`.
- **REFUSE gate #2**: retrieval returns 0 chunks ⇒ same REFUSE.
- Note/sermon synthesis ⇒ `quick_summary` grounded **only** by injected chunks
  (avoids false scripture-citation refusals on pure-note answers).
- Scripture comparison (book+chapter detected in query) ⇒ `berean_answer`
  (Claude-exclusive, `fail_closed`, `requireCitations`) → scripture citations.
- Any `callModel` block (`retrieval_failed` / `citations_required` / guard) maps to
  the REFUSE state — never a fabricated answer.
- Every grounded answer returns `citations[]` (sourceId, type, pointer deep-link,
  title, chunkIndex, score, snippet, `[n]` marker) → UI "Sources used" panel.

## Mount point

```tsx
import { NotebooksScreen } from 'src/features/notebooks';
<NotebooksScreen userId={uid} />
```

Reachable from the Connected Intelligence hub (`GrantSurface.notebooks`). White/light
Liquid Glass; tokens from `src/berean/contracts.ts`. No cosmic-dark / gold / purple /
Cormorant Garamond.

## UI states (all wired to real CFs, no stubs)

LOADING · EMPTY · LIST · DETAIL · ANSWER(+citations) · ERROR(retry) · **REFUSE**
(calm blue card, distinct from red ERROR, with an inline "add sources" affordance).

## Deltas to shared files (NOT edited by Agent C — for the integrator)

1. `functions/index.js` — add the 5 exports above.
2. `firestore.rules` — add the `users/{uid}/notebooks/{notebookId}` block above.
3. Mount `<NotebooksScreen userId={uid} />` in the Connected Intelligence hub.
