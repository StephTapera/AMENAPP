# AMEN Catch-Up Report — 2026-06-10

PROJECT_ROOT: `/Users/stephtapera/Desktop/AMEN/AMENAPP copy` · xcodeproj: `AMENAPP.xcodeproj`
Integration line ("main" for this purpose): `feature/connected-intelligence-20260609-r2` @ `5225e38c`
Author lane: claude (catch-up). Read-only map + reporting; **no out-of-lane mutations** (see "Why" below).

## Execution constraint (binding)
The order's own RULES — *"conflicts resolved by owners never guesswork; destructive git
human-only; no deploys"* — and `AGENT_LANES.md` (no out-of-lane deletes; pbxproj is a
HUMAN-ONLY hotspot, agent edits blocked by the Xcode-open crash-safety hook; don't edit
active lanes' files) **gate almost every STEP-2..5 mutation.** 5+ lanes are live in this
tree right now (Pulse, FirebaseAI-removal, migration/context, Berean, ambient-UI, a sibling
claude running this same order → `audit/BUILD_CURRENCY_AUDIT_2026-06-10.md`). The sole build
blocker is owned by an active lane. So this pass completes every **read-only / reporting /
coordination** step and **posts blockers to owners** rather than guess-merging or
out-of-lane-deleting — which is the exact pattern `AGENT_LANES.md:7,83,85` says destroyed
work twice.

---

## STEP 1 — Drift (item → type → owner → disposition)

### Build blocker (single, decisive)
`xcodebuild build … -clonedSourcePackagesDirPath ./SourcePackages` → **BUILD FAILED, 80 errors,
all identical class:** `Missing package product '<X>' (in target 'AMENAPP')` for the ENTIRE
Firebase / Algolia / LiveKit / GoogleSignIn / GoogleGenerativeAI stack. `-resolvePackageDependencies`
printed `resolved source packages:` (EMPTY). The build dies at package resolution; **no Swift
source compiles → zero source-level compile errors exist to fix.**
- Verbatim first error: `AMENAPP.xcodeproj: error: Missing package product 'LiveKit' (in target 'AMENAPP' from project 'AMENAPP')`
- **Owner:** Codex — "Resolve Missing Package Products" (active; owns `project.pbxproj`,
  `SourcePackages`, `DerivedData`, `PackageCache`). pbxproj = human-only.
- **Disposition:** posted to owner. NOT touched — those four paths are an active lane's owned
  set; pbxproj edits are physically blocked for agents.

### Branches (`git branch --no-merged` vs HEAD)
| Branch | behind/ahead HEAD | Carries | Owner | Disposition |
|---|---|---|---|---|
| `feature/ail` | 11 / 10 | AIL — **already landed** path-scoped (HEAD `4b40d006…5225e38c`) | AIL lane | Functionally home; owner tags+archives. Raw merge would reintroduce divergent pbxproj/history — do NOT. |
| `ci/contract-faithful` | 6 / 2 | Connected-Intelligence corrected-contract (React/TS Gen-2 CFs) | CI lane | Owner merges; SUPERSEDES duplicate-swarm on conflict; then export callables from `index.ts` + add app flag. Blocked on green build. |
| `feature/ci-native-bridge-20260609` | 6 / 2 | Same tip as ci/contract-faithful (`5c382372`) | CI lane | Folds in with above. |
| `integration/recover-features-20260609` | 13 / 263 | 2,574-file recovery worktree | human/integration | NEVER wholesale. Diff → cherry-pick proven-missing delta → tag+archive. Destructive archive = human-only. |
| `audit/overnight-20260530/0531/0601`, `restore/feb18`, `berean/ui-*`, `feature/master-run-20260531`, `audit/2026-05-*`, `claude/*` | stale (May–early Jun) | superseded audit/restore history | human | tag + archive (documented). Destructive = human-only. |

### Worktrees
Main + 3 lane worktrees (`_integration-recover-20260609`, `ail-land`, `ail-wt`, `ci-bridge-wt`)
+ ~17 `.claude/worktrees/agent-*` (mostly `locked`, live agents). None orphaned/removable by an
agent (destructive = human-only; locked = in use).

### Working tree (294 entries)
| Class | Count | Owner / disposition |
|---|---|---|
| Modified (unstaged) | ~168 | spans all active lanes — leave to owners |
| Deleted (unstaged) | ~51 | root scripts/logs/JSX prototypes (`deploy-berean*.sh`, `*.py`, `church_notes_*.txt`, `Berean*.jsx`) — deliberate declutter by owning lanes |
| Untracked | ~32 | ContextStore/* (migration lane), AIL settings (AIL lane), Ambient (ambient lane), CI configs — owners commit |
| Staged (index) | 7 | **NOT mine** (AIL + build-info + ambient lanes) — a naive commit would sweep them; must not |
| `* 2/3/4.*` junk dups | ~20 regenerated | a process is still spawning them post-dedup (`8ebbc140`/`91af1a44`) — **deletion is out-of-lane + non-converged**; report, don't delete |

---

## STEP 2 — Compile status
- **No Swift compile errors exist** — the build never reaches compilation (package-resolution failure).
- **`* 2` duplicates:** prior dedup of 13 source dups + 330 SourcePackages dups already done by the
  ambient-UI lane (`AGENT_LANES.md:142-186`). Remaining ` 2/3/4` files belong to ACTIVE lanes
  (`actionIntelligence 2.ts`, `noteShare 2.ts`, `userSettings 2.ts`, `agentIdentity 2.ts`, …) and a
  process is **still regenerating them** → deleting now is both forbidden (out-of-lane) and futile.
  Reported to owners, none deleted.
- **Reachable-scope fixes:** none — every dirty file is owned by an active lane; the only blocker is
  the active package lane + human-only pbxproj.

## STEP 3 — Flag hygiene (the named hazards are already corrected)
| Flag | Default now | Verdict |
|---|---|---|
| `cameraOSEnabled` | **`false`** (line 345) | "Missing CameraOS flag" — **already present + OFF**. No add needed. |
| `communityOSEnabled` / `communityHubsEnabled` | `false` / `false` | Corrected — OFF. |
| `presenceIntelligenceEnabled` / `smartPresenceEnabled` | `false` / `false` | Corrected — OFF. |
| `accessibilityIntelligenceEnabled` (AIL) | `false` | Corrected — OFF. |
| `amenPulseEnabled` | `false` | Correct — pre-deploy. |
| `onboardingV2Enabled`, `noteShareViewerEnabled`, `bereanHelperModelEnabled`, all `*KillSwitch` | `false` | Correct. |

The three previously "caught defaulting ON" (CommunityOS/presence/AIL) are **all OFF now** and the
CameraOS flag exists — STEP 3's specific asks are satisfied in-tree. Safety gates intentionally `true`
(`moderation*`, `safetyOSEnabled`, `aegisPrePostReviewEnabled`, `socialSafetyOS*`, minor-safety) are
**correctly ON** — a blanket "flip all true→OFF" would disable safety and is NOT done.
`AMENFeatureFlags.swift` is an append-only HOTSPOT currently dirty with another lane's edits → **no
flip performed** (can't isolate; would entangle their work). If a human wants any specific
non-safety `true` flag flipped pre-launch, name it and a single owner appends it.

## STEP 4 — Stranded branches
Cannot execute now: every merge is **owner-driven + requires a green build between each** (order's own
rule), and the build is **red at package resolution (active lane)**. AIL is already functionally home
(path-scoped land). CI + integration merges + all archive/tag (destructive) are **owner/human-only**.
Posted readiness above; no guess-merge performed.

## STEP 5 — Currency proof
- Branch **0 behind / 9 ahead of `main`** → current with main (no rebase). ✅
- Clean git status: **NO** — ~250 multi-lane uncommitted files (active work, not mine to commit). ❌ (owner-gated)
- Zero unmerged branches: **NO** — owner/human-gated merges+archives pending. ❌ (owner-gated)
- Green build from clean HEAD: **NO** — blocked at package resolution by the active Codex lane +
  human-only pbxproj. ❌ (blocked)
- Stamp screenshot (SHA on screen == HEAD): **NOT possible** — app cannot build, so cannot launch. ❌ (blocked)

## Owner action queue (unblocks the rest)
1. **Codex / package lane:** re-resolve `./SourcePackages` (clean-scope re-clone is the documented fix,
   `AGENT_LANES.md:186`) so the 80 missing products resolve → build reaches source. Owns this exclusively.
2. **Human:** the 6-site FirebaseAI/FirebaseAILogic pbxproj unlink (exact edits posted to chat
   2026-06-10; agent pbxproj edits hook-blocked).
3. **Active lanes:** commit your compiling hunks now (wipe-risk window open, `AGENT_LANES.md:162`).
4. **AIL / CI / integration owners:** STEP-4 merges + archives, green build between each, once (1)+(2) land.
