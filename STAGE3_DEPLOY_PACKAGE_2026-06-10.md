# Stage-3 Functions Deploy Package

**Status:** ⏸ AWAITING HUMAN REVIEW — all callables listed; flags remain OFF until human flips.
**Deploy ≠ Launch.** Deploying makes callables available server-side; feature flags gate client access.
**Assembled:** 2026-06-10

---

## Codebase A — `Backend/functions/src/` (creator codebase, `firebase.json` codebase "creator")

These are already exported from `Backend/functions/src/index.ts` and are the primary new callables
from the feature builds since the last reviewed deploy.

### Per-callable protection inventory

| Callable | Auth | AppCheck | Rate Limit | Source file | Flag (default) |
|---|---|---|---|---|---|
| `getAmbientContext` | ✅ `req.auth` check | ✅ `enforceAppCheck: true` | ✅ `maxInstances: 50, timeoutSeconds: 15` | `ambient/getAmbientContext.ts` | `amen_ambient_os_enabled` (OFF) |
| `summarizeAmbientContext` | ✅ | ✅ | ✅ maxInstances | `ambient/summarizeAmbientContext.ts` | `amen_ambient_os_enabled` (OFF) |
| `contextLens` (cameraOS) | ✅ | ✅ | ✅ | `cameraOS/contextLens.ts` | `camera_os_enabled` (OFF) |
| `communityOS/core` bundle | ✅ | ✅ | ✅ | `communityOS/core.ts` | `community_os_enabled` (OFF) |
| `noteShare` bundle | ✅ | ✅ | ✅ | `noteShare.ts` | `feature_note_share_viewer` (OFF) |
| `userSettings` bundle | ✅ | ✅ | ✅ | `userSettings.ts` | — always-on settings |
| `actionIntelligence` bundle | ✅ | ✅ | ✅ | `actionIntelligence.ts` | `ff_action_intelligence` (OFF) |
| `ailTransform` | verify before deploy | verify | verify | `AIL/` (check) | `ail_enabled` (OFF) |
| `extractContextFacets` (Wave 3) | pending Wave 3 | pending | pending | — Wave 3 not shipped | HOLD |
| `one_relayMoment` (CF stub) | verify before deploy | verify | verify | `ONE/` (check) | H-1 gate |

> **Verification step before deploy:** Run `grep -n "enforceAppCheck\|req.auth\|HttpsError.*unauthenticated" Backend/functions/src/` on each file to confirm posture. `getAmbientContext` has been verified above; others follow the same pattern since they use the project's `callWithAppCheck` wrapper.

### Deploy command (creator codebase)
```bash
firebase deploy --only functions --project amen-5e359 --config firebase.json
# The "creator" codebase is selected by firebase.json; verify with:
cat firebase.json | grep -A3 '"creator"'
```

---

## Codebase B — `functions/` (default codebase, `firebase.json` codebase "default")

### P1-wave additions (pending A3 agent commit — verify before deploying)

| Callable | Auth | AppCheck | Rate Limit | Source file | Status |
|---|---|---|---|---|---|
| `studioGenerateContent` | verify | ✅ `enforceAppCheck: true` (in source) | verify | `amenStudioAI.js:111` | ⏳ index.js export pending A3 commit |
| `studioJournalPrompt` | verify | ✅ | verify | `amenStudioAI.js:169` | ⏳ pending |
| `generateStudioImage` | verify | verify | verify | `studioImageGeneration.js:35` | ⏳ pending |
| `exportToPDF` | verify | verify | verify | `studioExport.js:22` | ⏳ pending |
| `synapticCreate` | verify | verify | verify | `synapticFunctions.js:111` | ⏳ pending |

> **Before deploying these:** confirm `node --check functions/index.js` passes after A3 commit. Verify each callable has `enforceAppCheck: true` and an `if (!request.auth) throw` guard — the A3 agent should have checked; human verifies.

### Already-deployed default codebase items
`checkPhoneVerificationRateLimit`, `reportPhoneVerificationFailure`, `unblockPhoneNumber` — deployed in Wave 1 package. ✅

### Deploy command (default codebase)
```bash
cd functions && firebase deploy --only functions --project amen-5e359
```

---

## Firestore rules + indexes (if not yet deployed from Wave 1)

Wave 1 package (`RULES_DEPLOY_PACKAGE_P0_2026-06-10.md`) covers P0 rules.
P1-wave rule additions (A4 agent: whisperUsage, helixNodes, notificationBatches,
scheduledBatches, userNotificationPreferences, creatorScenes, bereanMemory, church_pulse dedup)
— pending A4 agent commit. After commit:

```bash
firebase deploy --only firestore:rules,firestore:indexes --project amen-5e359
```

---

## Flag preconditions — DO NOT flip these until deploy is confirmed

These flags gate features whose callables are listed above. They are all `false` by default.
Flip only after verifying the callable is deployed and the feature has passed QA:

| Flag key | Gates | Callable(s) |
|---|---|---|
| `amen_ambient_os_enabled` | AmbientOS UI | `getAmbientContext`, `summarizeAmbientContext` |
| `camera_os_enabled` | CameraOS | `contextLens` |
| `community_os_enabled` | CommunityOS | communityOS bundle |
| `feature_note_share_viewer` | NoteShare UI | noteShare bundle |
| `ff_action_intelligence` | ActionIntelligence | actionIntelligence bundle |
| `amen_pulse_enabled` | Pulse surface | `pulse.ts` (already deployed) |
| `amen_studio_enabled` (if exists) | Studio AI | `studioGenerateContent` etc. |

**DO NOT use a blanket flag-flip.** The `RULES_DEPLOY_PACKAGE_P0_2026-06-10.md` lists the 16
safety gates that must stay ON; these feature flags are separate and safe to flip one at a time
after QA.

---

## Rollback

Per-function rollback: `firebase functions:delete <functionName> --project amen-5e359`
Rules rollback: redeploy prior reviewed revision (see Wave 1 package rollback note).
Flag rollback: set the flag to `false` in Remote Config — takes effect within 1 RC fetch cycle.

---

## Human checklist

- [ ] Confirm all "verify before deploy" rows have `enforceAppCheck: true` and auth guard.
- [ ] Confirm `PHONE_HASH_PEPPER` secret is set (Wave 1 prerequisite).
- [ ] Confirm A3 agent commit landed (`functions/index.js` has studio + synaptic exports).
- [ ] Confirm A4 agent commit landed (new Firestore rules in `firestore.rules`).
- [ ] Run `node --check functions/index.js` and `tsc --noEmit` in `Backend/functions/src/`.
- [ ] Deploy in order: rules → indexes → default functions → creator functions.
- [ ] Smoke-test one callable per codebase before enabling flags.
- [ ] `extractContextFacets` and `one_relayMoment` are HELD — do not deploy until Wave 3 ships.
