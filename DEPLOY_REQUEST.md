# Spiritual OS Deploy Request

Date: 2026-06-20
Branch at last refresh: `feature/volunteer-board-wave0`
Current observed SHA at last refresh: `9989d33602c8980b0a43aec8b851214cfcaf11e1`
Xcode-visible copy: `AMENAPP/Docs/Readiness/SPIRITUAL_OS_DEPLOY_REQUEST.md`

Note: the current worktree still contains unrelated dirty changes from other lanes. Treat this request as the Spiritual OS deploy plan and re-check `git status` plus the exact diff before any production deploy.

## Scope Decision

Product decision: Spiritual OS is in v1 scope. It must ship with real backend/rules support, not dark-only.

## Collision Decision

Current iOS callers use existing callable names:

- `getHubItems`
- `pinHubItem`
- `getAssistantResponse`
- `updateContextState`
- `cleanupContextOnLogout`
- Existing contract helpers: `getSpiritualDigest`, `getPlannerEvents`, `getPlannerSuggestions`, `dismissSuggestion`

These are already exported from the **default** codebase via `functions/index.js` and implemented in `functions/spiritualOSFunctions.js`. Do **not** deploy the renamed creator-codebase duplicates (`spiritualOSAssistant`, `spiritualOSGetHubItems`, etc.) for v1.

Region decision: these existing deployed functions are `us-central1`. Updating them in place preserves current iOS default-region callers. Moving them to `us-east1` would require an iOS region migration and duplicate function lifecycle; do not do that in this release cut.

## Code Diff

Changed file:

- `functions/spiritualOSFunctions.js`

Compatibility repair:

- `getHubItems` accepts both `lastItemId` and Swift's current `cursor`.
- `getHubItems` returns both `id` and `itemId`.
- `getHubItems` converts Firestore `createdAt` to client millisecond epoch.
- `pinHubItem` accepts both `isPinned` and Swift's current `pinned`.

Rules diff:

- `firestore.rules` now includes explicit owner-scoped Spiritual OS blocks before catch-all:
  - `spiritualOS_digest/{userId}/items/{itemId}`
  - `spiritualOS_hub/{userId}/items/{itemId}`
  - `spiritualOS_planner/{userId}/events/{eventId}`
  - `spiritualOS_context/{userId}`
  - `spiritualOS_suggestions/{userId}/items/{itemId}`
  - `spiritualOS_spaceCreateDrafts/{userId}/drafts/{draftId}`
  - `spiritualOS_commandCenter/{userId}/aggregates/{aggregateId}`
- The same rules commit also contains pre-existing report-safety edits that were already in the worktree:
  - `userReports` owner read key changed from `reporterUid` to `reporterId`.
  - Explicit server-only locks were added for `moderationCases`, `trustSafetyEvents`, `evidenceVault`, and `ncmecReadiness`.
  - Human reviewer must treat the rules deploy as a combined SpiritualOS + report-safety rules diff.

## Local Verification

Passed:

```sh
cd functions && node --check spiritualOSFunctions.js
cd functions && npm run build:sanctuary
cd functions && npm run build:berean
cd functions && npm run build:context
```

Blocked / requires human-machine verification:

```sh
FIREBASE_CLI_DISABLE_UPDATE_CHECK=true firebase emulators:exec --only firestore "echo firestore-rules-syntax-ok"
```

Result: Firestore emulator could not start because port `8080` is already occupied. Rules syntax and denial tests are **not green** yet.

Predeploy caveat resolved on 2026-06-20: `build:context` now runs through `functions/scripts/build-context.js` instead of a fragile inline `node -e` command.

## Required Human Review Before Deploy

1. Review `git diff -- functions/spiritualOSFunctions.js`.
2. Review `git diff -- firestore.rules`.
3. Run Firestore rules emulator syntax and denial tests on an open Firestore emulator port.
4. Confirm `ANTHROPIC_API_KEY` is rotated/dead-in-repo before production deploy.
5. Confirm App Check enforcement remains on for each callable.

## Targeted Deploy Commands

Run from repo root only. Do not run broad deploys.

Rules first, after denial tests pass:

```sh
firebase deploy --only firestore:rules | tee deploy-logs/spiritual-os-firestore-rules-$(date +%Y%m%d-%H%M%S).log
```

Functions after rules pass:

```sh
firebase deploy --only functions:default:getSpiritualDigest | tee deploy-logs/getSpiritualDigest-$(date +%Y%m%d-%H%M%S).log
firebase deploy --only functions:default:getHubItems | tee deploy-logs/getHubItems-$(date +%Y%m%d-%H%M%S).log
firebase deploy --only functions:default:getPlannerEvents | tee deploy-logs/getPlannerEvents-$(date +%Y%m%d-%H%M%S).log
firebase deploy --only functions:default:getPlannerSuggestions | tee deploy-logs/getPlannerSuggestions-$(date +%Y%m%d-%H%M%S).log
firebase deploy --only functions:default:getAssistantResponse | tee deploy-logs/getAssistantResponse-$(date +%Y%m%d-%H%M%S).log
firebase deploy --only functions:default:updateContextState | tee deploy-logs/updateContextState-$(date +%Y%m%d-%H%M%S).log
firebase deploy --only functions:default:dismissSuggestion | tee deploy-logs/dismissSuggestion-$(date +%Y%m%d-%H%M%S).log
firebase deploy --only functions:default:pinHubItem | tee deploy-logs/pinHubItem-$(date +%Y%m%d-%H%M%S).log
firebase deploy --only functions:default:cleanupContextOnLogout | tee deploy-logs/cleanupContextOnLogout-$(date +%Y%m%d-%H%M%S).log
```

## Flag Flip Order

All flags stay OFF until rules and function deploys are verified with real data.

1. `spiritualOS_context_engine_enabled`
2. `spiritualOS_assistant_bar_enabled`
3. `spiritualOS_daily_enabled`
4. `spiritualOS_hub_enabled`
5. `spiritualOS_planner_enabled`
6. `spiritualOS_spaces_dashboard_enabled`
7. `spiritualOS_create_space_enhanced_enabled`
8. `spiritualOS_command_center_enabled`
9. `spiritualOS_community_os_enabled`
10. `spiritualOS_enabled` last

## Still Required Before "Ship All"

- Quiet/clean single-writer branch.
- Human Xcode build at final SHA.
- Firestore rules syntax + denial tests.
- Real data round trips for each surface.
- Screenshot matrix: light/dark/Dynamic Type XL/reduce-motion.
- Faith-formation review per surface.
- Hard launch gates: child safety, App Check, secret rotation, privacy labels, permission strings, account deletion, UGC report/block/contact, donation/IAP decision.
