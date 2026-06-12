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
- All new functions must declare `region: "us-central1"` explicitly
- Log all deploy output to `deploy-logs/`

See `docs/deploy-topology.md` for full topology, codebase map, and KnownDrift list.

## us-central1 Quota Warning

As of 2026-06-12, us-central1 Cloud Run service quota is exhausted (~1007 services). Creating new us-central1 functions will fail with HTTP 429. Do NOT attempt to deploy new functions to us-central1 without first confirming quota has been freed. See `docs/deploy-topology.md §us-central1 Quota Warning` for resolution steps.

## cloud-functions/ is QUARANTINED

`cloud-functions/` has its own `firebase.json` (codebase `quarantine-legacy`). It is NOT wired into root `firebase.json`. Never deploy from or to this directory. See `cloud-functions/README.md`.

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
