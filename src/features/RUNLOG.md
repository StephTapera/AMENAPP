# Connected Intelligence — RUNLOG

## 2026-06-09 — Agent 1 (Contract Author) — Phase 1 Contract Freeze

Branch: `feature/connected-intelligence-20260609`. Additive only.

### Files written
- `src/features/connectedIntelligence.contracts.ts` — FROZEN ❄ contract. Imports
  canonical `Provenance, SourceRef, TruthLevel, Plan, CapabilityTier, Domain` from
  `src/berean/contracts.ts`. New enums + core interfaces + `MENTION_ROUTING` +
  `CONNECTOR_ALIASES`.
- `src/features/connectedIntelligence.config.ts` — canonical TS config block (spec §7).
- `src/features/connectedIntelligence.rules.diff.md` — Firestore rules diff for human deploy.
- `src/features/RUNLOG.md` — this file.

### Contract is FROZEN
Phase 2 agents bind to `connectedIntelligence.contracts.ts` and MUST NOT modify it.

### Decisions encoded

1. **TrustProfile — DROPPED from v1.**
   Reason: absent from the TS Berean contract; not required by any of the 6 Phase 2
   surfaces (connectors, brief, notebooks, scheduled actions, mention routing,
   action sheet). Not defined or referenced anywhere in the contract. Revisit only
   if a future surface needs cross-surface trust state.

2. **Drive + Canva connectors — DROPPED.**
   Reason: non-faith-native (violates the faith-native connector charter, already
   enforced in `connectorsService.ts`); no `Domain` value maps to them; the frozen
   `Domain` union may not be extended. `ConnectorId` = { calendar, music, bible,
   church_mgmt } only. `ToolMention` = { bible, prayer, calendar, notes, sermon,
   music, church } only. No drive/canva token, enum value, alias, or config flag
   exists anywhere.

3. **@mention → Domain foldings (7, no enum extension):**
   | mention   | Domain        | taskKey (real)   | provider tier        |
   |-----------|---------------|------------------|----------------------|
   | bible     | scripture     | berean_answer    | claude-exclusive     |
   | prayer    | prayer        | prayer_generate  | claude-exclusive     |
   | notes     | church_notes  | berean_explain   | rag-grounded         |
   | calendar  | church_notes  | daily_brief      | tool-orchestration   |
   | sermon    | study         | berean_explain   | rag-grounded         |
   | music     | general       | berean_explain   | tool-orchestration   |
   | church    | admin         | berean_explain   | tool-orchestration   |

   All taskKeys verified present in `functions/router/amenRouting.config.js`.
   scripture/pastoral path = fail_closed Claude-only; notes/sermon = pinecone
   retrieval (refuse-if-no-index); calendar/music = degrade-gracefully orchestration.

### Reconciliation decisions
- **Memory store:** EXTEND existing `berean/{uid}/memory/{memoryId}` (service
  `src/berean/core/memory.ts`). Did NOT create a parallel `users/{uid}/memories`
  store. `MemoryItem` is a superset *view*; the `users/{uid}/memories` rules block
  in the diff ships UNWIRED, reserved for a future migration.
- **Connector aliases:** `bible` → existing `BibleProvider` (ConnectorType 'bible');
  `church_mgmt` → existing `church_calendar` + `sermon_library` types. Zero new code
  paths for aliased connectors. `calendar` + `music` are the only NEW providers.
- **Timestamp convention:** matched Berean contract — `unknown` (Firestore Timestamp).

### Queued for HUMAN DEPLOY (not auto-applied)
- **P0 SECURITY FIX** — `firestore.rules:2153–2166` `discernmentChecks` shared-read
  leak: current rule lets any signed-in user read any `shared` check via the
  unbounded `sourceRef != null` clause. Corrected rule (gate on CF-stamped
  `participants`/`spaceId`) documented in `connectedIntelligence.rules.diff.md` Part A.
- New owner-scoped collections (connectorGrants, notebooks, scheduledActions,
  briefCache, checkpoints) + CF-admin-only OAuth token docs — Part B of the diff.
- Server flags mirroring `connectedIntelligence.config.ts` → Phase 2 Agent A wires
  them into `functions/router/amenRouting.config.js`.

### Residual gaps for Phase 2
- `calendar` + `music` CF callables + provider adapters do not yet exist (Agents C/E).
- `scheduledActions.enabled = false` until Aegis review id assigned.
- `ResponseAction` deferred values ship UI-absent (gated false in config).
