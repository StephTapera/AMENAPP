# Pulse action routing — handoffs, hygiene incident, test-sweep dispatch (2026-06-10, claude/Pulse)

Owned by the Pulse lane; written here (not inline in the hot manifest) to avoid racing concurrent edits.
Catch-up lane: please land this pointer + `VERIFICATION_SUITE.md` + `AGENT_LANES.md` updates in your next sweep.

## 1. XCTest build blocker — provenance RESOLVED, canonical-lane task (ruling 1)
`AMENAPP/ContextStore/ContextStoreAdversarialTests.swift:31` → `cannot resolve module 'XCTest'`. Root cause: an
XCTest test file inside the app's `PBXFileSystemSynchronizedRootGroup` (`AMENAPP/ContextStore/`) → it gets
**app-target** membership, where XCTest isn't linked. This is the FIRST build error now that the FirebaseAI unlink
landed (FirebaseAI error gone ✅). It is the single fleet-wide build blocker; Pulse runtime screenshots are gated on it.

Provenance: `ContextStore/RUNLOG.md:14` attributes `ContextStoreAdversarialTests` to the **CANONICAL** Context
swarm (`lane/context-system`), NOT the terminated duplicate's quarantine footprint. An active lane ("Fix error in
ContextStoreAdversarialTests.swift on line 31") is already on it. Per ruling 1 (canonical → owner task), I did NOT edit it.

- **→ Canonical Context lane — TASK (30-min window from 2026-06-10):** MOVE
  `AMENAPP/ContextStore/ContextStoreAdversarialTests.swift` → `AMENAPPTests/` (correct home; synchronized roots make
  location = target membership, so the move drops app-target membership and resolves XCTest — no pbxproj surgery).
  Apply the same to any sibling app-rooted `ContextStore*Tests.swift` (e.g. `ContextStoreSecurityTests.swift`).
  Fallback only if the move surfaces a collision: `#if canImport(XCTest)` guard.
  **Window expires with no fix → Pulse lane applies the move, declared here.**

## 2. COMMIT-HYGIENE INCIDENT — self-reported
Commit **`5227689d`** ("feat(pulse): synthesize action deeplinks…") was meant to carry only 3 backend files, but
`git add <paths> && git commit` commits the WHOLE pre-staged index — which already held other lanes' staged files. So
`5227689d` ALSO committed the **canonical Context lane's** staged work:
`ContextStore/{ContextStoreAdversarialTests,ContextStoreModels,ContextStoreService,ContextStoreSecurityTests,
AegisEnforcementService,AmenPassportView,FaithConsentView}.swift` + `ContextStoreRules.txt`. **Nothing is lost** — it's
in history at `5227689d`, not "uncommitted." Context lane: your files are committed there; reconcile/re-attribute as you
wish. **No history rewrite by me** (destructive = human-only). Fix adopted: scoped commits use
`git commit -m … -- <pathspec>` (proven on `544769b7`), never `add + commit`.

## 3. Dormant-test sweep — logger fixed, path-class DISPATCHED (ruling 2; feeds Gap Audit A6)
- **Logger class FIXED centrally** — `544769b7`: `Backend/functions/jest.setup.ts` + `setupFiles`. Mocks the
  firebase-functions logger (preserving all other exports via requireActual). +4 tests (646→650), no regressions, zero
  lane-file edits.
- **Path class DISPATCHED** (cross-lane test files — Pulse will not edit them after the `5227689d` incident). Exact root
  cause: colocated `*.static.test.ts` use `const src = path.join(__dirname, "..")`, written assuming they live in
  `src/__tests__/` (where `..` = `src/`). Colocated at `src/`, `..` overshoots to `Backend/functions/` → ENOENT. **Sources
  EXIST** (`src/twoFactorAuth.ts`; sibling reads like `functions/src/bereanChatProxyStream.ts` also exist) — NOT deletions.
  **Owner fix (choose one):** (a) move the `.static.test.ts` into `src/__tests__/`, or (b) change the base to `__dirname`.
  Affected: `accountLifecycle`, `securityLaunchReadiness`, `securityPosture`, several `berean.*` /
  `aiBackendOwnership` / `remainingReleaseScopes` (the last group reads the sibling `functions/` codebase — fix the base,
  don't re-hardcode).
- **Residual** non-path, non-logger failures (real assertion failures) stay triaged per owner in `VERIFICATION_SUITE.md`
  = authoritative verification-debt list for A6.

Suite totals after both fixes: **58 suites (30 fail / 28 pass), 907 tests (257 fail / 650 pass)** — up from the
pre-sweep 21 suites running. Corrected run command: `cd Backend/functions && npx jest --forceExit`.

## 4. → Catch-up lane (ruling 3)
`VERIFICATION_SUITE.md` and `AGENT_LANES.md` are updated in the WORKING TREE but NOT committed by me (they carry
other lanes' uncommitted edits; co-committing would repeat the `5227689d` mistake). Please land them scoped in the
catch-up sweep, plus a one-line manifest pointer to this file.
