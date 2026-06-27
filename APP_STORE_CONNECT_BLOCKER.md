# App Store Connect Blocker

**Generated:** 2026-06-27  
**Status:** HUMAN BLOCKED / NO-GO

## Current Evidence

- `AMENAPP/Config.xcconfig:46` still contains:

```text
APP_STORE_APP_ID = 0000000000
```

- The config comments state the Rate AMEN row stays hidden while this value is `0000000000` or unset.
- No real numeric App Store Connect app ID was provided in this workspace or environment during this pass.

## Required Human Action

Steph must create the App Store Connect app record and replace `APP_STORE_APP_ID` in `AMENAPP/Config.xcconfig` with the real numeric Apple ID from App Store Connect.

## Release Impact

- Do not attempt App Store upload.
- Do not mark App Store validation passed.
- Do not mark release GO.

## Acceptance Evidence Required

- Real numeric App Store Connect Apple ID in `AMENAPP/Config.xcconfig`.
- Archive validation or upload evidence that uses the real app record.
