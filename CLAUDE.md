# AMEN — Claude Code Session Rules

These rules override default Claude Code behavior for this repository. Read them before acting.

## Firebase Deploy Rules

**FORBIDDEN for agents:**
- `firebase deploy` (bare — deploys everything)
- `firebase deploy --only functions` (untargeted — triggers orphan deletion prompts)
- Running any `firebase` command from a subdirectory (`cd functions && firebase deploy`)
- `firebase deploy --only functions:creator --force` without human approval (deletes ~120 orphaned Cloud Run services)

**REQUIRED for agents:**
- Always deploy from repo root
- Always use targeted codebase: `firebase deploy --only functions:default` or `firebase deploy --only functions:creator`
- For single functions: `firebase deploy --only functions:creator:functionName`
- **Region rule:** Deploy new functions to `us-central1` if `gcloud run services list --region us-central1 | wc -l` < 950. Otherwise deploy to `us-east1`. NEVER deploy to a region without adding an entry to the **Interim Region Table** in `docs/FUNCTION_INVENTORY.md`. Silent region choices are forbidden.
- Log all deploy output to `deploy-logs/`

See `docs/deploy-topology.md` for full topology, codebase map, and KnownDrift list.
See `docs/FUNCTION_INVENTORY.md` for Interim Region Table and deletion candidate list.

## us-central1 Quota Warning

As of 2026-06-13, us-central1 is at **999/1000** Cloud Run services. Creating new us-central1 functions will fail with HTTP 429. Deploy to us-east1 instead and add to Interim Region Table. Quota reclamation plan: 522 DEAD services identified in `docs/FUNCTION_INVENTORY.md` — requires human approval before deletion. See `docs/deploy-topology.md §us-central1 Quota Warning` for resolution steps.

## cloud-functions/ is QUARANTINED

`cloud-functions/` has its own `firebase.json` (codebase `quarantine-legacy`). It is NOT wired into root `firebase.json`. Never deploy from or to this directory. See `cloud-functions/README.md`.

## Repo Build Protocol

**Canonical build command:**

```sh
xcodebuild -scheme AMENAPP -destination 'generic/platform=iOS' build \
  -clonedSourcePackagesDirPath ./SourcePackages.nosync \
  -derivedDataPath ./DerivedData.nosync
```

**One build at a time, repo-wide:** before any agent starts a build, it must acquire `./.build-lock` with its session identifier and timestamp. A stale lock older than 30 minutes may be cleared only with a log note. Concurrent builds corrupt the shared SwiftPM caches.

**Human build broker:** when an agent shell cannot produce the build because of sandboxing, package services, or other local tool limits, the gate state is `HUMAN-PENDING at SHA <hash>`. The human runs the canonical command on the quiet tree and reports `SUCCEEDED` or `FAILED` with the SHA. A wave is not complete at `HUMAN-PENDING`, but agents may continue non-build work while that gate is pending.

**Per-worktree builds:** use per-worktree cache paths. Do not use the repo-root `.nosync` directories from secondary worktrees.

## Code Style

- PascalCase types, camelCase properties/methods
- `@State private var` for SwiftUI state, `let` for constants
- 4-space indentation
- Import: SwiftUI, Foundation at top
- No force unwrapping
- Prefer Swift async/await over Combine
- Comments only for non-obvious WHY, not WHAT

## Backend Architecture

Three Firebase codebases:
1. `default` → `functions/` — main platform functions
2. `v2triggers` → `functions/v2triggers/` — isolated Gen-2 triggers
3. `creator` → `Backend/functions/` — social graph + globalResilience

See `docs/deploy-topology.md` for full details.
