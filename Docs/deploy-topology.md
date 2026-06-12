# Deploy Topology — AMEN Firebase Functions

Last updated: 2026-06-12

## The Three Codebases

| Codebase    | Source directory            | Predeploy                               | What lives here |
|-------------|-----------------------------|-----------------------------------------|-----------------|
| `default`   | `functions/`                | `npm run build:context` + `berean/ tsc` | All platform functions: feed, posts, comments, Berean AI, notifications, safety, church, Spaces messaging, discovery, restored functions |
| `v2triggers`| `functions/v2triggers/`     | (none)                                  | Gen-2 Firestore/Eventarc triggers that are isolated from the main bundle |
| `creator`   | `Backend/functions/`        | `npm run build` (TypeScript)            | Social graph (follow/unfollow/block/privacy), counter reconciliation, globalResilience (adaptive media, feed ranking, trust scoring, crisis bulletins, locale packs, messaging) |

## Deployment Rules

**RULE 1 — All new functions must declare `region: "us-central1"` explicitly.**
Never rely on a default or inherited region. Every `onCall`, `onSchedule`, and `onDocumentXxx` must carry an explicit `region` option.

**RULE 2 — Every deploy command must use targeted codebase/function syntax.**
Allowed: `firebase deploy --only functions:default`, `firebase deploy --only functions:creator`, `firebase deploy --only functions:default:myFunction`.
**FORBIDDEN for agents:** bare `firebase deploy` or untargeted `--only functions` — these deploy ALL codebases and can trigger unintended orphan-deletion prompts.

**RULE 3 — All deploys must run from the repo root only.**
Never `cd functions && firebase deploy` or `cd Backend/functions && firebase deploy`. Firebase reads `firebase.json` from the directory you run it from; running from a subdirectory will use the wrong config.

**RULE 4 — `cloud-functions/` is quarantined.**
The `cloud-functions/` directory has its own `firebase.json` (codebase `quarantine-legacy`). It is NOT wired into the root `firebase.json` and must NEVER be deployed. See `cloud-functions/README.md`.

## us-central1 Quota Warning

As of 2026-06-12, the `us-central1` region has ~1007 Cloud Run services deployed, which is at or near the default quota (1000 services per region). Deploying new functions to `us-central1` will fail with HTTP 429 until quota is freed.

**To free quota before adding new functions:**
1. Open [GCP Cloud Run Console](https://console.cloud.google.com/run?project=amen-5e359)
2. Identify and delete Cloud Run services from removed/orphaned functions
3. Or request a quota increase: IAM & Admin → Quotas → Cloud Run → "Maximum number of services per region"

**Orphaned creator functions:** The creator codebase has ~120 Cloud Run services at `us-central1` that no longer have corresponding source code in `Backend/functions/src/`. These are stale from previous deployments. A human should audit and delete them before any new `creator` codebase deploys. **Do not run `firebase deploy --only functions:creator --force`** without first verifying which of these orphans are still receiving traffic (check Cloud Run metrics in GCP Console).

## KnownDrift — Functions Held at us-east1 Pending Coordinated Migration

These functions cannot be migrated to `us-central1` without a simultaneous iOS app release that updates the client region. They must stay at `us-east1` until that coordination happens.

| Function | Source file | iOS call site | Notes |
|----------|-------------|---------------|-------|
| `broadcastSpaceEvent` | `functions/liveActivityFunctions.js` | `AmenSmartEventComposerView.swift:665` | Needs app release to update client |
| `broadcastSpaceAnnouncement` | `functions/connectHubFunctions.js` | `AmenEventBroadcastView.swift:537` | Needs app release to update client |
| ChurchNotes intelligence functions | `Backend/functions/src/churchNotes/` | `ChurchNotesIntelligenceRepository.swift:28` (property-level) | All calls from repository go to us-east1; needs app release |

**Additional drift — follow/privacy functions:**
The follow/privacy functions (`createFollow`, `createUnfollow`, `acceptFollowRequest`, `rejectFollowRequest`, `cancelFollowRequest`, `removeFollower`, `onAccountPrivacyChange`, `reconcileFollowCounts`, `blockRelationshipCleanupTrigger`) are held at `us-east1` because us-central1 quota is exhausted. The source code (globalResilience/* constants) has been updated to `us-central1` in preparation; these functions' source still declares `us-east1` and will need to be updated and redeployed once quota is freed.

## Predeploy Commands Reference

```bash
# Deploy only the default codebase (from repo root):
firebase deploy --only functions:default

# Deploy only the creator codebase (from repo root):
firebase deploy --only functions:creator

# Deploy a specific function from creator (from repo root):
firebase deploy --only functions:creator:createFollow

# List all functions and their regions:
firebase functions:list

# Delete a specific function (DESTRUCTIVE — confirm before running):
firebase functions:delete functionName --region us-east1 --force
```
