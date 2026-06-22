# Agent F — Response Action Sheet — HANDOFF

Branch: `feature/connected-intelligence-20260609`
Connected Intelligence v1, Phase 2.

Floating Liquid Glass action pill + full grouped sheet under every Berean response.
Strict ownership respected: new files only under `src/features/actionSheet/**` and the
single backend module `functions/connectedIntelligence/transformFunctions.js`. No shared
files were edited — wiring steps below are deltas for the integrating agent/human.

---

## 1. Files created (this agent's only writes)

### Frontend — `src/features/actionSheet/`
| File | Lines | Purpose |
|---|---|---|
| `types.ts` | 110 | View-model glue. Binds FROZEN `Provenance`/`SourceRef`/`ResponseAction`. `ActionSheetResponse`, `ProvenanceStamp`, `ConversationState`, `ActionResult`, six `ActionUiState`. |
| `taxonomy.ts` | 118 | Full action taxonomy → grouped descriptors. Deferred-off actions filtered ABSENT (not disabled). `VISIBLE_ACTIONS`, `PILL_ACTIONS`, `groupedActions()`. |
| `actionService.ts` | 379 | Real logic for every action. Provenance stamping, memory via existing `memoryService`, moderation fail-closed, checkpoints. `runAction()`, `resumeCheckpoint()`. |
| `ResponseActionSheet.tsx` | 437 | Pill + sheet UI. Long-press AND ••• open the sheet. All six UI states; blocked distinct from error. |
| `index.ts` | 22 | Public barrel. Exports `<ResponseActionSheet response={...}/>`. |
| `HANDOFF.md` | this file | — |

### Backend — `functions/connectedIntelligence/`
| File | Lines | Purpose |
|---|---|---|
| `transformFunctions.js` | 281 | `bereanTransform` onCallV2. Maps the 6 transforms to real task keys; typed `{blocked, refusal}` outcomes (never HttpsError for moderation/refusal). |

---

## 2. Cloud Function exports — WIRING NEEDED (human/integrator)

`bereanTransform` is exported from `functions/connectedIntelligence/transformFunctions.js`
but is NOT yet re-exported from the Firebase entry point. Add to `functions/v2entry.js`
(alongside the existing `// Berean v1 callables` block), as a delta this agent could not make:

```js
// ── Connected Intelligence — Response Action Sheet transforms ─────────────────
const ciTransforms = require("./connectedIntelligence/transformFunctions");
exports.bereanTransform = ciTransforms.bereanTransform;
```

Then deploy: `firebase deploy --only functions:bereanTransform`.

Secrets used (already defined elsewhere, no new secrets): `ANTHROPIC_API_KEY`,
`NVIDIA_API_KEY`, `PINECONE_API_KEY`, `PINECONE_HOST`.

### Transform → real task-key mapping (verified against amenRouting.config.js)
- `simplify`  → scripture-domain ? `berean_explain` : `quick_summary`
- `deep_dive` → scripture-domain ? `berean_explain` : `deep_analysis`
- `challenge_this` → `berean_perspective` (Acts 17:11; labeled+cited traditions; no manufactured controversy)
- `generate_questions` → `family_questions`
- `verify_scripture` / `show_sources` → `berean_answer` (ALWAYS Claude-exclusive; `requireCitations` ⇒ cite-or-refuse)

Scripture-grounded domains (`scripture, theology, pastoral, study, devotional`) force
Claude-exclusive routes. Domain is INHERITED from `sourceDomain`. `crisis` is rejected
(returns typed `{blocked, refusal:'crisis_handoff'}`). Citations-required failure surfaces
as `{blocked:true, refusal:'citations_required'}` — the sheet renders the distinct blocked state.

---

## 3. Firestore security rules — NEEDED

Add to `firestore.rules`. All paths are per-user, owner-only.

```
// Connected Intelligence — checkpoints (continue_later / resume)
match /users/{uid}/checkpoints/{checkpointId} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}

// Action-sheet created objects (all carry provenance)
match /users/{uid}/{coll}/{docId} {
  allow read, write: if request.auth != null && request.auth.uid == uid
    && coll in ['notes','notebookEntries','prayerJournal','shareDrafts',
                'tasks','calendarDrafts','plans','polls','posts'];
}
```

Memory writes reuse the EXISTING `berean/{uid}/memory` rules (already in place — soft-delete
only, hard delete denied). `remember_this` writes `origin:'explicit_remember'` + `sourcePointer`
as extra fields on the schemaless memory doc via the existing `upsertMemory` (no parallel store).

---

## 4. Config flags

Read-only consumption of the FROZEN config (`connectedIntelligence.config.ts`):
`actionSheet.deferred` — all five deferred actions are `false` in v1, so
`turn_into_podcast / turn_into_video_script / create_infographic / create_presentation /
create_flyer` are **filtered out of the taxonomy entirely** (absent buttons, never disabled).
Flipping any flag to `true` makes that button appear with no code change required.

No new flags were introduced by this agent.

---

## 5. How the pill attaches to a Berean response (mount point)

Mount under each assistant bubble in `ChatScreen` (`src/berean/BereanApp.tsx`), passing the
Berean result. Delta for the integrating agent (this agent did not edit BereanApp.tsx):

```tsx
import { ResponseActionSheet } from '../features/actionSheet';

// inside the assistant message render branch (msg.role === 'berean'):
<ResponseActionSheet
  response={{
    responseId: msg.id ?? `resp_${i}`,
    domain: 'general',               // the domain passed to sendMessage()
    text: msg.text,
    provenance: msg.provenance ?? { sources: [], truthLevel: 'grounded' },
    threadId: currentThreadId,
    conversationState: {             // optional — full state for continue_later
      threadId: currentThreadId,
      domain: 'general',
      messages,
    },
  }}
/>
```

The component reads `uid`/`plan` from `useBerean()` context (already provided by
`<BereanProvider>`), so no extra props are needed beyond `response`. Long-press the pill OR
tap ••• to open the full grouped sheet. To rehydrate a saved session call
`resumeCheckpoint(uid, checkpointId)` and feed the returned `ConversationState` back into the host.

---

## 6. Invariants enforced
- PROVENANCE: every object-producing action (note, notebook, prayer entry, share draft, task,
  calendar draft, plan, poll, post/carousel, checkpoint) writes the canonical `Provenance` +
  `originResponseId` pointer + source excerpt.
- MEMORY: via existing `memoryService` only; `explicit_remember` origin; one-tap soft-delete +
  undo; `why_remembered` renders origin+sourcePointer verbatim; `show_related` labels results.
  NO passive inference.
- MODERATION: `turn_into_post`/`turn_into_carousel` call `checkContentSafety`, FAIL CLOSED —
  anything but `decision==='allow'`, or any callable error ⇒ BLOCKED, never publishes.
- CONTINUITY: `continue_later` → `users/{uid}/checkpoints/{id}`; `resume` restores full state.
- DEFERRED: five deferred actions ABSENT (filtered), not disabled.
- SIX UI states implemented; moderation-blocked is amber and DISTINCT from error (red).
- DESIGN: white/light Liquid Glass via frozen `tokens`. No cosmic-dark / gold / purple /
  Cormorant Garamond.

---

## BROADCAST

```
Agent F (Response Action Sheet) — COMPLETE. 7 files, ~1347 lines.
FE src/features/actionSheet/: types.ts(110) taxonomy.ts(118) actionService.ts(379) ResponseActionSheet.tsx(437) index.ts(22) HANDOFF.md
BE functions/connectedIntelligence/transformFunctions.js(281) — bereanTransform onCallV2, 6 transforms→real task keys, typed blocked/refusal.
Pill (Save·Discuss·Remember·Post·Continue·•••) + long-press/••• grouped sheet; 6 UI states; blocked≠error; deferred ABSENT.
Provenance on every created object; memory via existing memoryService; post/carousel checkContentSafety FAIL-CLOSED; continue_later→checkpoints + resume.
WIRE: v2entry.js re-export bereanTransform · firestore.rules checkpoints+objects · mount <ResponseActionSheet> in BereanApp ChatScreen.
```
