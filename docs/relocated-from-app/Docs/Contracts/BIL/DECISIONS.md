# BIL Decisions

## 2026-06-12 - Stub End-State

BIL stub end-state = target-membership exclusion (human-owned); all other workarounds rejected 2026-06-12.

Evidence:
- The project uses `PBXFileSystemSynchronizedRootGroup` for the `AMENAPP` target.
- The app target exception set currently excludes only `AMENBuildInfo.swift` and `Info.plist`.
- There are no `membershipExceptions` for the seven `AMENAPP/BIL/*.swift` placeholder files committed at `eb04a154`.
- Those placeholders remain inert until a human excludes them from target membership in Xcode.

