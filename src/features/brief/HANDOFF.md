# Daily Brief — HANDOFF (Agent B, Connected Intelligence v1)

Branch: `feature/connected-intelligence-20260609`

Pull-based home card. Generated on open, cached one-per-day at
`users/{uid}/briefCache/{date}`. **NEVER** a push notification
(`config.brief.pushEnabled === false` — no scheduled/push trigger exists in this
module).

## Files (strict ownership)

| File | Role |
| --- | --- |
| `src/features/brief/DailyBriefCard.tsx` | Home card, all SIX UI states |
| `src/features/brief/briefService.ts` | Client data layer (callable wrapper) |
| `src/features/brief/index.ts` | Barrel export — mount `<DailyBriefCard/>` |
| `functions/connectedIntelligence/briefFunctions.js` | `generateDailyBrief` callable |
| `src/features/brief/HANDOFF.md` | This file |

No shared files were edited. Contracts/config (`connectedIntelligence.contracts.ts`,
`connectedIntelligence.config.ts`) are imported read-only.

## 1. CF export to register (index.js)

Add to `functions/index.js` (or the v2 aggregation file that re-exports callables):

```js
exports.generateDailyBrief =
  require("./connectedIntelligence/briefFunctions").generateDailyBrief;
```

- Region `us-central1`, `timeoutSeconds: 60`.
- Secrets used: `GEMINI_API_KEY`, `OPENAI_API_KEY`, `NVIDIA_API_KEY`
  (the `daily_brief` route chain is gemini→openai with `outputGuard`). All already
  defined for other Berean callables — no new secrets.
- Rate limit: `generateDailyBrief` 30/hour/user (via `enforceRateLimit`).

## 2. briefCache Firestore rules

Add under `match /users/{uid}` (owner-only; the CF writes via admin and bypasses
rules, so client access is read-only):

```
match /briefCache/{date} {
  allow read:  if request.auth != null && request.auth.uid == uid;
  allow write: if false;   // written only by generateDailyBrief (admin SDK)
}
```

The callable also READS (admin SDK, rules-exempt) these first-party collections —
no new rules needed, but they must exist for items to populate:
`users/{uid}/connectorGrants` (grant docs with `surfaces[]` incl. `daily_brief`),
`users/{uid}/connectorEvents` (calendar summary mirror — summaries+pointers only),
`users/{uid}/savedVerses`, `users/{uid}/groupActivity`,
`users/{uid}/prayerUpdates`, `users/{uid}/threads`, `users/{uid}/followUps`,
`users/{uid}/safetySurfaces` (crisis), `spaces/{id}/events`, `spaces/{id}/members`.
Missing collections degrade gracefully (section ABSENT, never a teaser).

## 3. Config flags (already in connectedIntelligence.config.ts)

- `brief.maxItems = 9` — hard cap, mirrored server-side as `MAX_ITEMS_TOTAL`.
- `brief.generateAfterLocalHour = 5` — before 5am local with no cache, the callable
  returns yesterday's card rather than generating early.
- `brief.pushEnabled = false` — enforced by ABSENCE of any push/scheduled trigger.

## 4. Mount point

Home surface (e.g. `HomeScreen` / feed top). Example:

```tsx
import { DailyBriefCard } from './features/brief';

<DailyBriefCard
  userId={uid}
  minorScoped={isMinor}
  onOpenPointer={(pointer) => router.openDeepLink(pointer)}
  onOpenSafety={() => router.openSafetyHub()}
/>
```

Both handlers are REQUIRED (no stubs). Pointers are `amen://…` deep links.

## Behavior guarantees enforced

- **Grants:** connector sections render only when an active grant includes the
  `daily_brief` surface; otherwise ABSENT (no locked teaser). Server is authority.
- **Minor mode:** Amen-native ONLY (space events, saved verse, group/prayer
  activity). Zero connector data. No weather/maps. Banner shown client-side.
- **Sabbath:** card replaced by a rest-framing card; only crisis/safety surfaces
  remain reachable (`onOpenSafety`).
- **Crisis:** safety surface BYPASSES Sabbath suppression AND the 9-item cap.
- **9-cap:** enforced server-side by `SECTION_ORDER` fill; client re-clamps as
  defense-in-depth; cap-degraded state shows a calm non-blocking note.
- **Tone:** banned strings (`you missed`, `streak`, `X days since`) stripped
  server-side (`stripGuiltFraming`) AND absent from all client copy.

## Six UI states (DailyBriefCard.tsx)

1. `loading` — skeleton + aria-busy
2. `ready` — sections + items, each tappable to its pointer
3. `empty` — "You're all caught up." (calm, no guilt) + Refresh
4. `sabbath` — distinct rest card + reachable safety button
5. `error` — message + wired "Try again"
6. minor — Amen-native content + banner (within `ready`)
   plus **cap-degraded** note rendered inside `ready` when `capped === true`.
