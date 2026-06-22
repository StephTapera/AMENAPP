# AMEN Social V2 Handoff

## Current Verdict

Status: **9/10 build checkpoint go, not 10/10 release go**.

The Social V2 work is implemented, isolated, committed, merged, imported into the active workspace, focused-typechecked, and the active Xcode project builds. It is **not** release-certified because simulator install/launch verification is still blocked.

## Integration Branch

| Item | Value |
| --- | --- |
| Integration worktree | `/private/tmp/amen-v2-integration` |
| Branch | `integration-v2-social` |
| Latest commit | `3fa42892` |
| Base | `main` at `115b48c9` |
| Project edits | No `.pbxproj` edits |

## Active Workspace Import

| Item | Value |
| --- | --- |
| Imported path | `AMENAPP/Features/SocialV2/` |
| Import type | Additive synchronized-folder files only |
| Additional fix | Renamed Messaging helper `FlowLayout` to `SocialV2MessagingActionRow` to avoid collision with an existing app `FlowLayout` |
| Active build | Passed via Xcode `BuildProject` on 2026-06-22 |

## What Passed

| Area | Status |
| --- | --- |
| Foundation module | Passed focused Swift typecheck |
| Spaces | Passed focused Swift typecheck |
| Feeds | Passed focused Swift typecheck |
| Search | Passed focused Swift typecheck |
| Messaging | Passed focused Swift typecheck |
| Identity | Passed focused Swift typecheck |
| Privacy/Safety | Passed focused Swift typecheck |
| Vault/Notes | Passed focused Swift typecheck |
| Settings | Passed focused Swift typecheck |
| All Social V2 modules together | Passed combined focused Swift typecheck |

## Feature Commits

| Feature | Branch | Commit |
| --- | --- | --- |
| Foundation | `feature-v2-foundation` | `205e766` |
| Spaces | `feature/v2-spaces` | `54a2ee3c` |
| Feeds | `feature/v2-feeds` | `3858820e` |
| Search | `feature/v2-search` | `b8ded2d3` |
| Messaging | `feature/v2-messaging` | `88adfdb9` |
| Identity | `feature/v2-identity` | `552f7e68` |
| Privacy/Safety | `feature/v2-privacy-safety` | `e863db6e` |
| Vault/Notes | `feature/v2-vault-notes` | `babec3fe` |
| Settings | `feature/v2-settings` | `939bf143` |

## Still Blocking 10/10

| Gate | Status |
| --- | --- |
| Full active Xcode build | Passed |
| Device/simulator launch | Blocked - `DeviceInteractionInstallAndRun` could not acquire launch session; `RunProject` rebuild fails with unparsed `Command SwiftCompile failed with a nonzero exit code` while `BuildProject` succeeds |
| Flag-on smoke test | Not run |
| Real app shell wiring | Module contracts exist; app router/DI/flag aggregation still need real-shell integration |

## Build Command To Run Outside Sandbox

Run this from `/private/tmp/amen-v2-integration` in a normal Terminal/Xcode environment:

```sh
xcodebuild \
  -project AMENAPP.xcodeproj \
  -scheme AMENAPP \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/amen-v2-derived \
  -clonedSourcePackagesDirPath /tmp/amen-v2-packages \
  -packageCachePath /tmp/amen-v2-package-cache \
  CODE_SIGNING_ALLOWED=NO \
  build
```

After that passes, run the app on simulator/device and smoke-test each Social V2 surface with flags ON.
