# Spiritual OS Deploy Plan

Date: 2026-06-12
Current SHA: `f91f424c9d4ac6e8003739cc65d75e946e12f1ac`
Xcode gate: `HUMAN-PENDING` at current SHA.
Backend gate: `npm run build` in `Backend/functions` passed at current SHA after callable rename.

## Human Xcode Build Request

Run from repo root on a quiet tree after acquiring `./.build-lock`:

```sh
xcodebuild -scheme AMENAPP -destination 'generic/platform=iOS' build \
  -clonedSourcePackagesDirPath ./SourcePackages.nosync \
  -derivedDataPath ./DerivedData.nosync
```

Report `SUCCEEDED` or `FAILED` with SHA `f91f424c9d4ac6e8003739cc65d75e946e12f1ac`.

## Callable Collision Resolution

Collision check:

```sh
grep -rn "getAssistantResponse" functions Backend/functions/src --include="*.ts" --include="*.js" -l | grep -v node_modules | grep -v "/lib/"
```

Result: the live callable names already exist in `functions/spiritualOSFunctions.js`, `functions/index.js`, and `functions/spiritualOSFunctions 2.js`. `firebase functions:list` also shows these deployed callable IDs in `us-central1`: `getAssistantResponse`, `getHubItems`, `pinHubItem`, `updateContextState`, `cleanupContextOnLogout`.

Decision: this lane must not deploy the same callable IDs from the `creator` codebase. The creator-codebase additions were renamed in commit `f91f424c`:

| Contract role | Existing live/default callable | Creator lane callable after repair | Deploy decision |
|---|---|---|---|
| Assistant response | `getAssistantResponse` | `spiritualOSAssistant` | Deploy only after iOS migration or explicit consolidation decision. |
| Hub page fetch | `getHubItems` | `spiritualOSGetHubItems` | Deploy only after iOS migration or explicit consolidation decision. |
| Hub pin toggle | `pinHubItem` | `spiritualOSPinHubItem` | Deploy only after iOS migration or explicit consolidation decision. |
| Context sync | `updateContextState` | `spiritualOSUpdateContextState` | Deploy only after iOS migration or explicit consolidation decision. |
| Logout cleanup | `cleanupContextOnLogout` | `spiritualOSCleanupContextOnLogout` | Deploy only after iOS migration or explicit consolidation decision. |

Compatibility: current iOS callers still use the existing live/default callable IDs. This repair avoids breaking old binaries and prevents a cross-codebase same-name deploy.

## Quota Dependency

BLOCKED: `us-central1` has approximately 1007 Cloud Run services, above/near the default 1000 service quota. New `us-central1` functions are blocked until either:

1. Function inventory cleanup deletes verified orphan services, or
2. A quota grant is approved.

No deploy command may run until this path clears and the human approves this plan.

## Targeted Deploy Commands

Run from repo root only, after quota clears and human approval:

```sh
firebase deploy --only functions:creator:spiritualOSAssistant | tee deploy-logs/spiritualOSAssistant-$(date +%Y%m%d-%H%M%S).log
firebase deploy --only functions:creator:spiritualOSGetHubItems | tee deploy-logs/spiritualOSGetHubItems-$(date +%Y%m%d-%H%M%S).log
firebase deploy --only functions:creator:spiritualOSPinHubItem | tee deploy-logs/spiritualOSPinHubItem-$(date +%Y%m%d-%H%M%S).log
firebase deploy --only functions:creator:spiritualOSUpdateContextState | tee deploy-logs/spiritualOSUpdateContextState-$(date +%Y%m%d-%H%M%S).log
firebase deploy --only functions:creator:spiritualOSCleanupContextOnLogout | tee deploy-logs/spiritualOSCleanupContextOnLogout-$(date +%Y%m%d-%H%M%S).log
```

Do not deploy the old names from `creator`; those collide with existing deployed default-codebase functions.

## Rules Review Package

Rules are ready for review from `Contracts/SpiritualOS/SecurityRules.contract.md`; they were not deployed in this run.

Additive Firestore blocks:

| Collection path | Access model | Deploy state |
|---|---|---|
| `spiritualOS_digest/{userId}/items/{itemId}` | Owner read; CF create; owner `isRead` update only. | REVIEW-READY, NOT DEPLOYED |
| `spiritualOS_hub/{userId}/items/{itemId}` | Owner read; CF create; owner `isPinned`, `isRead`, `isArchived` update only. | REVIEW-READY, NOT DEPLOYED |
| `spiritualOS_planner/{userId}/events/{eventId}` | Owner control; Berean note fields CF-only. | REVIEW-READY, NOT DEPLOYED |
| `spiritualOS_context/{userId}` | Owner read/delete; CF create/update only. | REVIEW-READY, NOT DEPLOYED |
| `spiritualOS_suggestions/{userId}/items/{itemId}` | Owner read; owner dismiss update only. | REVIEW-READY, NOT DEPLOYED |
| `spiritualOS_spaceCreateDrafts/{userId}/drafts/{draftId}` | Owner draft management. | REVIEW-READY, NOT DEPLOYED |
| `spiritualOS_commandCenter/{userId}/aggregates/{aggregateId}` | Owner read; owner dismiss update only. | REVIEW-READY, NOT DEPLOYED |

## Remote Config Flags

Local app defaults are OFF. The checked `remoteconfig.template.json` does not yet include these Spiritual OS flags, so Remote Config versioning is a human flag-package task.

| Flag | Default | Flip order |
|---|---:|---:|
| `spiritualOS_enabled` | `false` | 8 |
| `spiritualOS_context_engine_enabled` | `false` | 1 |
| `spiritualOS_assistant_bar_enabled` | `false` | 2 |
| `spiritualOS_daily_enabled` | `false` | 3 |
| `spiritualOS_hub_enabled` | `false` | 4 |
| `spiritualOS_planner_enabled` | `false` | 5 |
| `spiritualOS_spaces_dashboard_enabled` | `false` | 6 |
| `spiritualOS_create_space_enhanced_enabled` | `false` | 6 |
| `spiritualOS_command_center_enabled` | `false` | 7 |
| `spiritualOS_community_os_enabled` | `false` | 7 |

Flip order: deploy backend/rules, verify server flags, enable per-surface flags in internal cohort, then enable `spiritualOS_enabled` last.

## Owed Verification

Screenshots must be written to `wave-reports/spiritual-os/` by the capture sweep lane:

| Surface | Required captures | Current state |
|---|---|---|
| Daily | light, dark, Dynamic Type XL, reduce motion | PENDING-CAPTURE |
| Hub | light, dark, Dynamic Type XL, reduce motion | PENDING-CAPTURE |
| Planner | light, dark, Dynamic Type XL, reduce motion | PENDING-CAPTURE |
| Hero Cards | light, dark, Dynamic Type XL, reduce motion | PENDING-CAPTURE |
| Create Space | light, dark, Dynamic Type XL, reduce motion | PENDING-CAPTURE |
| Command Center | light, dark, Dynamic Type XL, reduce motion | PENDING-CAPTURE |
| Assistant Bar | light, dark, Dynamic Type XL, reduce motion | PENDING-CAPTURE |

Tests still owed:

| Test name | Purpose | Current state |
|---|---|---|
| `SpiritualOSFlagOffRenderingTests` | Flag-OFF byte-identical assertions per mounted surface. | PENDING-TEST |
| `SpiritualOSContextPrivacyTests` | Assert flag-OFF does not start CoreLocation/CoreMotion legacy pipeline. | PENDING-TEST |
| `SpiritualOSCallableCollisionTests` | Assert creator functions do not export live/default callable names. | PENDING-TEST |

Faith-formation checks:

| Surface | Hard-rules state |
|---|---|
| Daily | PASS-BY-INSPECTION: extends bounded Pulse; no infinite scroll or public metrics. |
| Hub | PASS-BY-INSPECTION: unified inbox actions are read/pin/archive; no engagement-bait badging. |
| Planner | PASS-BY-INSPECTION: suggestions are dismissible and calendar-bounded. |
| Hero Cards | PASS-BY-INSPECTION: prayer count is contextual/private, not comparative. |
| Create Space | PASS-BY-INSPECTION: private prayer/encryption and moderation controls remain explicit. |
| Command Center | PASS-BY-INSPECTION: private formation overview; no public leaderboard. |
| Assistant Bar | PASS-BY-INSPECTION: AI disclosure label required; no client-side model keys. |
| Context Engine | PASS-BY-INSPECTION: consumes approved context projection; no parallel sensing pipeline. |

## Status Table

| Surface | Committed | Builds | Wired entry point | Screenshots | Tests | Deploy | LIVE-ON-RELEASE |
|---|---|---|---|---|---|---|---|
| Daily | `06106379` | `HUMAN-PENDING @ f91f424c`; backend green | `HomeView` top section, Pulse-backed | PENDING-CAPTURE | PENDING-TEST | BLOCKED-QUOTA / NO APPROVAL | NO, flags OFF |
| Hub | `06106379`, backend repair `f91f424c` | `HUMAN-PENDING @ f91f424c`; backend green | `MessagesView` | PENDING-CAPTURE | PENDING-TEST | BLOCKED-QUOTA / COLLISION REPAIRED | NO, flags OFF |
| Planner | `ebc4bf44` | `HUMAN-PENDING @ f91f424c`; backend green | `EventsView`, `ResourcesView` | PENDING-CAPTURE | PENDING-TEST | BLOCKED-QUOTA / NO APPROVAL | NO, flags OFF |
| Hero Cards | `06106379` | `HUMAN-PENDING @ f91f424c`; backend green | Space detail and ministry room surfaces | PENDING-CAPTURE | PENDING-TEST | BLOCKED-QUOTA / NO APPROVAL | NO, flags OFF |
| Create Space | `06106379` | `HUMAN-PENDING @ f91f424c`; backend green | Connect create-space sheets | PENDING-CAPTURE | PENDING-TEST | BLOCKED-QUOTA / NO APPROVAL | NO, flags OFF |
| Command Center | `06106379` | `HUMAN-PENDING @ f91f424c`; backend green | `ProfileView` | PENDING-CAPTURE | PENDING-TEST | BLOCKED-QUOTA / NO APPROVAL | NO, flags OFF |
| Assistant Bar | `06106379`, backend repair `f91f424c` | `HUMAN-PENDING @ f91f424c`; backend green | `ContentView` overlay | PENDING-CAPTURE | PENDING-TEST | BLOCKED-QUOTA / COLLISION REPAIRED | NO, flags OFF |
| Context Engine | `5f3ac874`, backend repair `f91f424c` | `HUMAN-PENDING @ f91f424c`; backend green | `ContentView` `SpiritualOSContextManager` | PENDING-CAPTURE | PENDING-TEST | BLOCKED-QUOTA / COLLISION REPAIRED | NO, flags OFF |
| Community OS | `06106379` | `HUMAN-PENDING @ f91f424c`; backend green | gated `AmenCommunityOSView` | PENDING-CAPTURE | PENDING-TEST | BLOCKED-QUOTA / NO APPROVAL | NO, flags OFF |

