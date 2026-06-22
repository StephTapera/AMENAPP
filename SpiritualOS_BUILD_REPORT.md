# Spiritual OS Build Report

Date: 2026-06-18
Branch: `qa/auto-sweep-2026-06-17`
Latest SpiritualOS report SHA: `1b63bba9`
Xcode build: passed via BuildProject, log `BuildProject-Log-20260618-073907.txt`

## Shipped In Code

| Area | Status | Proof |
|---|---|---|
| Daily | Built, mounted, gated | `AmenDailyDigestView` in `HomeView`; uses Pulse-backed presentation. |
| Hub | Built, mounted, gated | `AmenHubSectionView` in `MessagesView`; callable compatibility fixed. |
| Planner | Built, mounted, gated | `AmenLifePlannerSectionView` in `EventsView` and `ResourcesView`. |
| Spaces Hero Cards | Built, mounted, gated | `AmenSpacesHeroCardSection` in Space detail/ministry surfaces. |
| Create Space | Built, mounted, gated | `AmenCreateSpaceEnhancedSheet` in Connect create flows. |
| Command Center | Built, mounted, gated | `AmenCommandCenterSection` in `ProfileView`. |
| Assistant Bar | Built, mounted, gated | `AmenAssistantBarOverlay` in `ContentView`. |
| Context Engine | Built, mounted, gated | `SpiritualOSContextManager` in `ContentView`; legacy orchestrator remains compatibility-only. |
| Community OS | Built, gated | `AmenCommunityOSView` and view model use SpiritualOS flags. |

## Backend / Rules

Default-codebase callable path is the v1 path because current iOS callers use the existing live callable names.

| Callable | Codebase | Region | Status |
|---|---|---|---|
| `getSpiritualDigest` | `default` | `us-central1` existing | Deploy-request-ready |
| `getHubItems` | `default` | `us-central1` existing | Compatibility fix committed in `7ad7a9c5` |
| `getPlannerEvents` | `default` | `us-central1` existing | Deploy-request-ready |
| `getPlannerSuggestions` | `default` | `us-central1` existing | Deploy-request-ready |
| `getAssistantResponse` | `default` | `us-central1` existing | Deploy-request-ready |
| `updateContextState` | `default` | `us-central1` existing | Deploy-request-ready |
| `dismissSuggestion` | `default` | `us-central1` existing | Deploy-request-ready |
| `pinHubItem` | `default` | `us-central1` existing | Compatibility fix committed in `7ad7a9c5` |
| `cleanupContextOnLogout` | `default` | `us-central1` existing | Deploy-request-ready |

Rules:

- SpiritualOS owner-scoped rules committed in `e27d5b16`.
- That same rules commit also includes report-safety locks already present in the worktree; see `DEPLOY_REQUEST.md`.
- Rules deploy is not green until emulator syntax and denial tests pass.

## Verification Run

Passed:

```sh
cd functions && node --check spiritualOSFunctions.js
cd functions && npm run build:sanctuary
cd functions && npm run build:berean
```

Xcode:

```text
BuildProject passed, log BuildProject-Log-20260618-073907.txt
```

Blocked / not complete:

- `npm run build:context` failed because the package script is quote-broken under this shell before project code runs.
- Firestore emulator rules check could not start because port `8080` was already occupied.
- Screenshot matrix has not been captured.
- Real production Firestore round trips have not been verified.
- No Firebase deploy has been run by this agent.

## Faith-Formation Review

| Surface | Rule check |
|---|---|
| Daily | Bounded Pulse presentation; no infinite scroll. |
| Hub | Unified inbox; pin/read/archive actions, no engagement-bait badging. |
| Planner | Calendar-bounded; suggestions are dismissible. |
| Spaces Hero Cards | Prayer/community data presented as context, not public comparison. |
| Create Space | Privacy, moderation, encrypted prayer controls remain explicit. |
| Command Center | Private formation overview; no leaderboard. |
| Assistant Bar | Server-side AI callable with disclosure label; no client model key. |
| Context Engine | Single approved context projection; no active parallel CoreLocation/CoreMotion sensing pipeline. |
| Community OS | Flag-gated and formation-oriented. |

## Launch Gate Status

| Gate | Status |
|---|---|
| Clean single-writer branch | BLOCKED: broad unrelated worktree churn remains. |
| Xcode build | GREEN at current tree via BuildProject. |
| Backend default functions syntax/build | PARTIAL GREEN: direct touched file and Berean/Sanctuary compile passed; context predeploy script blocked. |
| Firestore rules | BLOCKED: emulator port conflict; denial tests not run. |
| Function deploys | HUMAN-PENDING via `DEPLOY_REQUEST.md`. |
| Rules deploy | HUMAN-PENDING via `DEPLOY_REQUEST.md`. |
| Remote Config flag flips | HUMAN-PENDING after deploys and round trips. |
| Screenshot matrix | PENDING. |
| Child-safety gate | HUMAN/LEGAL-PENDING. |
| Secret rotation | HUMAN-PENDING. |
| Privacy labels/permission strings | HUMAN-PENDING final review. |
| Internal TestFlight | PENDING after deploys, flags, screenshots, and gates. |

## Bottom Line

SpiritualOS is now code- and deploy-request-ready for a human-gated production path, but not yet actually shipped. The remaining work is deploy execution, rules verification, real data round trips, screenshots, Remote Config rollout, and the hard launch gates.

