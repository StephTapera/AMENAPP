# Agent D — @Tool Mentions — HANDOFF

Branch: `feature/connected-intelligence-20260609`
Scope (strict ownership): create-only under `src/features/berean/composer/**` + ONE backend module `functions/connectedIntelligence/composerFunctions.js`. No shared files or Berean core were edited.

---

## 1. What this layer does

The composer @mention layer wraps the existing `useBerean().sendMessage(input, domain)`
call. It detects `@`, shows a grant-aware picker, parses the chosen mention, routes the
turn via the FROZEN `MENTION_ROUTING`, gathers ONLY scoped `ContextItem`s, and calls
`sendMessage(enrichedInput, routedDomain)`. Mentions are the only way connector context
enters a Berean turn — there is no ambient connector context anywhere in this layer.

---

## 2. EXACT attach point (existing Berean composer)

File: `src/berean/BereanApp.tsx` → function `ChatScreen()`.

Replace the input-row block (currently the `<div>` with the `<input>` + Send `<button>`,
roughly lines 116–142) with `<MentionComposer/>`. Everything else in `ChatScreen`
(the transcript map, the empty state, the "Berean is thinking…" bubble) stays as-is.

```tsx
import { MentionComposer } from '../features/berean/composer';
import { useBerean } from './core/BereanCore';

function ChatScreen() {
  const { sendMessage, context } = useBerean();
  const [messages, setMessages] = useState< /* unchanged */ >([]);
  const [loading, setLoading] = useState(false);

  // ...transcript rendering unchanged...

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ flex: 1, overflowY: 'auto', padding: '16px 16px 0' }}>
        {/* existing transcript + empty state + loading bubble unchanged */}
      </div>

      {/* ⬇ replaces the old <input> + Send <button> row */}
      <MentionComposer
        userId={context.userId}
        minorScoped={context.minorScoped}
        sendMessage={sendMessage}
        onUserSubmit={(raw) => {
          setMessages((prev) => [...prev, { role: 'user', text: raw }]);
          setLoading(true);
        }}
        onResolved={(outcome) => {
          setLoading(false);
          // append the assistant turn from your own sendMessage result handling,
          // OR keep ChatScreen's existing result wiring — MentionComposer only owns
          // the INPUT. For a 'draft' outcome, no assistant bubble is appended; the
          // CalendarDraftCard renders inline until the user confirms/cancels.
        }}
      />
    </div>
  );
}
```

Notes:
- `context.userId` and `context.minorScoped` come straight off `useBerean().context`.
- `MentionComposer` owns the input, picker, degraded chip, and the calendar draft card.
  The transcript stays the parent's responsibility.
- If you want the assistant's reply text in the transcript, capture it where you already
  call `sendMessage` — `MentionComposer` calls `sendMessage` for you and surfaces the
  outcome via `onResolved`; to also read the assistant text, wrap `sendMessage` in a
  thin closure that appends `result.text` before returning it.

---

## 3. Cloud Functions to export

Add to `functions/index.js` (exports object / re-export block):

```js
const {
  composerCalendarDraft,
  composerCalendarCommit,
} = require("./connectedIntelligence/composerFunctions");
exports.composerCalendarDraft  = composerCalendarDraft;
exports.composerCalendarCommit = composerCalendarCommit;
```

- `composerCalendarDraft({ text })` → `{ ok, draft, error? }`. Claude parses NL → draft;
  writes `berean/{uid}/calendarDrafts/{draftId}` status `pending`. NO external write.
  Secret: `ANTHROPIC_API_KEY` (already defined project-wide).
- `composerCalendarCommit({ draftId })` → `{ ok, pointer, error? }`. The ConfirmationGate
  server side: verifies an active, berean-scoped, `write_commit` calendar grant + minor
  block, then event_create (transactional, idempotent). Marks draft `committed`.

A separate `connectorFetch({ connectorId, surface, query })` callable is expected for
read-side @calendar/@music/@church context (Agent A/B owns it). If absent, the gatherer
DEGRADES gracefully (visible chip), never fabricates. Endpoint name is injectable via
`makeContextGatherer(fetchFn)` if Agent A names it differently.

---

## 4. Grant seam for Agent A

`grantsReader.ts` reads `berean/{uid}/connectorGrants/{connectorId}` for `calendar` and
`music`. When Agent A's canonical `grantsService` lands, wire its loader in with one line:

```ts
import { makeGrantsReader } from './grantsReader';
export const grantsReader = makeGrantsReader(agentAGrantLoader); // GrantLoader signature
```

A mention is available iff `grant.status==='active'` AND not expired AND
`grant.surfaces.includes('berean')`. Minor sessions ⇒ zero connector mentions (enforced
in `grantsReader.resolve` before any read).

---

## 5. Config flags

- No new client flags introduced. `connectedIntelligence.config.ts` `connectors.calendar`
  / `connectors.music` `enabled` gates are honored upstream by Agent A's availability
  service; this layer additionally requires a live berean-scoped grant per mention.
- `scheduledActions.enabled` is OFF in config and is NOT used by this layer (the calendar
  draft path is a synchronous, user-initiated `drafts_for_approval` write, not a schedule).
- Server: `composerCalendarCommit` requires the `write_commit` scope on the grant; ship the
  calendar connector grant UI to request `write_commit` before this path can succeed.

---

## 6. Files

| File | Lines | Role |
|------|-------|------|
| `grantsReader.ts` | 168 | Resolve active/berean-scoped/unexpired connector grants; minor ⇒ none |
| `mentionConfig.ts` | 158 | UI metadata per ToolMention, bound to MENTION_ROUTING |
| `mentionParser.ts` | 186 | `@` trigger detect, parse, route, @calendar write-intent |
| `contextGatherer.ts` | 219 | Scoped ContextItem build; degrade-gracefully; enriched input |
| `calendarDraftService.ts` | 150 | Draft + commit CF client (ConfirmationGate) |
| `useMentionComposer.ts` | 377 | Orchestration hook over sendMessage |
| `MentionPicker.tsx` | 222 | Picker (loading/empty/partial/full/error/offline) |
| `DegradedChip.tsx` | 64 | Degraded-connector chip (distinct from error) |
| `CalendarDraftCard.tsx` | 157 | Draft event card + ConfirmationGate UI |
| `MentionComposer.tsx` | 159 | Drop-in composer wiring it all together |
| `index.ts` | 79 | Public barrel exports |
| `functions/connectedIntelligence/composerFunctions.js` | 299 | Draft + commit CFs |

Verification: `tsc --noEmit` (src/tsconfig.json, strict + noUnusedLocals) → 0 errors in
`composer/**`. `node --check` on the CF → OK. All pre-existing errors elsewhere are
unrelated (firebase.ts import.meta.env, other agents' feature folders).
