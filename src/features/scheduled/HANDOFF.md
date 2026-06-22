# Scheduled Actions — HANDOFF (Agent E, Connected Intelligence Phase 2)

Branch: `feature/connected-intelligence-20260609`
Owner surface: **Scheduled Actions** (ScheduleKind = reminder | digest | follow_up).

## Files created (strict ownership: only these)

Client — `src/features/scheduled/**`
- `index.ts` — public barrel; exports `ScheduledActionsScreen`, `gateState`, templates.
- `ScheduledActionsScreen.tsx` — the surface. All 6 UI states + disabled + dry-run + run-failed.
- `scheduledService.ts` — Firestore client persistence (controlsService.ts pattern).
- `scheduledTemplates.ts` — NL → preview parser + the 6 templates + `previewToAction`.
- `scheduledStyles.ts` — Liquid Glass white/light styles (tokens from berean/contracts).
- `HANDOFF.md` — this file.

Backend — single module
- `functions/connectedIntelligence/scheduledFunctions.js` — gen2 `onSchedule` runner.

No shared files were edited. (index.js wiring + Firestore rules are human deploy steps, below.)

## CF / scheduler export

```js
// functions/index.js — ADD (human deploy step):
const {executeScheduledActions} = require("./connectedIntelligence/scheduledFunctions");
exports.executeScheduledActions = executeScheduledActions;
```

Runner: `onSchedule("*/5 * * * *", timeZone: UTC, region: us-central1)`.
Mirrors `scheduledPostsFunctions.js`: batch query `.limit(50)`, per-doc try/catch.

## The Aegis gate (SHIP-BLOCKER — DO NOT bypass)

- `connectedIntelligence.config.ts → scheduledActions.enabled === false` and
  `aegisReviewId === null`. **Until an Aegis review id exists, the feature is OFF.**
- Client: `gateState()` returns `enabled:false`; the screen self-renders the
  **"Pending capability review"** state (informative banner + preview cards, NO dead
  buttons, NO fake flow). `createAction/activate/...` THROW `scheduled_actions_pending_review`.
- Server: runner **returns immediately (no-op)** while `SCHEDULED_ACTIONS_ENABLED !== "true"`
  OR `SCHEDULED_ACTIONS_AEGIS_REVIEW_ID` unset. It reads/mutates zero docs.

### To go live (after Aegis review lands)
1. Set `connectedIntelligence.config.ts → scheduledActions.enabled = true` + real `aegisReviewId`.
2. Set CF env: `SCHEDULED_ACTIONS_ENABLED=true`, `SCHEDULED_ACTIONS_AEGIS_REVIEW_ID=<id>`.

## Config flags (mirror of config.ts, read from env server-side)

| Config key | env var | default |
|---|---|---|
| `enabled` | `SCHEDULED_ACTIONS_ENABLED` | false |
| `aegisReviewId` | `SCHEDULED_ACTIONS_AEGIS_REVIEW_ID` | null |
| `dryRunCount` | `SCHEDULED_ACTIONS_DRY_RUN_COUNT` | 3 |
| `maxActiveFree` | `SCHEDULED_ACTIONS_MAX_ACTIVE_FREE` | 2 |
| `maxActivePlus` | `SCHEDULED_ACTIONS_MAX_ACTIVE_PLUS` | 10 |

## Firestore rules (human deploy step — server-only execution fields)

Collection `scheduledActions/{id}`:
- `create`: only if `request.auth.uid == request.resource.data.uid`, and incoming
  `writeRisk in ['read_only','drafts_for_approval']`, and `dryRun == true`,
  `status == 'dry_run'` at creation.
- `update` (client): owner only; **may NOT write** any of:
  `lastRunAt, lastRunStatus, lastRunFailureReason, lastRunPreviewText, dryRunsCompleted, aegisReviewId, createdAt`.
  These are **server-only execution fields** (written exclusively by the CF / admin SDK).
- Client `update` allowed fields: `status` (active|paused|dry_run|deleted), `dryRun`
  (false only via promote), `sabbathSuppressed`, `consentGranted`.
- Subcollection `scheduledActions/{id}/runs/{runId}`: **read-only to owner; writes server-only.**
- Minors: deny create entirely (consistent with ConnectorGrant.minorBlocked).

## Invariants enforced in code

- **Write-risk ceiling**: enum has only `read_only` + `drafts_for_approval`. Service
  (`assertWriteRiskCeiling`) and runner (`ALLOWED_WRITE_RISKS`) both fail closed.
  **No autonomous external write exists in code** — `drafts_for_approval` only writes a
  `runs` draft doc with `approved:false`.
- **Dry-run default**: every action starts `dryRun:true`, `status:'dry_run'`. First
  `dryRunCount` (3) runs are preview-only ("would have done X"). Server NEVER auto-promotes;
  only the user's `promoteToLive` clears `dryRun`.
- **Sabbath suppression**: default true; per-action override allowed EXCEPT digest/care
  templates (`sabbathOverrideLocked`). Suppressed run ⇒ `lastRunStatus:'sabbath_skip'` (deferral).
- **Never silent skip / never fabricate**: every failed run writes
  `lastRunStatus:'failed'` + `lastRunFailureReason`; the UI shows a distinct run-failed strip.
- **Care template** ("surface prayer requests awaiting follow-up") is framed as private
  CARE to a circle leader, gated behind explicit consent, never public, no counts, no shaming.
- **Safety/crisis** are NOT in `ScheduleKind` ⇒ structurally un-schedulable (route to Guardian).

## Mount point

```tsx
import { ScheduledActionsScreen } from 'src/features/scheduled';
<ScheduledActionsScreen userId={uid} plan={plan} />
```
Mount from Connected Intelligence settings. The screen gates itself — callers need no guard.

---

### BROADCAST
Agent E (Scheduled Actions) complete. 6 files, ~1,180 LOC.
- src/features/scheduled/ScheduledActionsScreen.tsx (~560) — 6 states + disabled + dry-run + run-failed
- src/features/scheduled/scheduledService.ts (~230) — Firestore persistence, Aegis + write-risk + cap gates
- src/features/scheduled/scheduledTemplates.ts (~270) — NL parser + 6 templates (incl. care/consent)
- src/features/scheduled/scheduledStyles.ts + index.ts (~280) — Liquid Glass styles + barrel
- functions/connectedIntelligence/scheduledFunctions.js (~290) — gen2 onSchedule, no-op while gated; dry-run/Sabbath/draft-only/never-silent-skip
Pending human: index.js wire + Firestore rules + flip Aegis gate (config + CF env). No shared files touched.
