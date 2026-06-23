# Governance Hardening — Ops Status & Handoff

Live status of merge / deploy / backup for the gap-closure work. Updated 2026-06-22.

## Commits (local, verified)

| SHA | What |
|-----|------|
| `18eee8cf` | G-1/G-2/G-3 closed end-to-end (genkit governed, SafetyPlan AES-GCM, prayerStreak verdict) |
| `1580495c` | Readiness gate reconciled to live code (5→4 NO-GO; P10-Y1 resolved) |

Both sit on `feature/governance-hardening` (worktree `/Users/stephtapera/Desktop/AMEN/governance-wt`).

## Backup (done — not on GitHub)

GitHub **rejects** a push of this branch: its *history* contains pre-existing large
binaries (e.g. `SourcePackages.nosync/...firebase-ios-sdk...pack` = 225 MB > GitHub's
100 MB limit). This is a pre-existing repo-hygiene issue, unrelated to the gap-closure
commits (which are a few KB of source).

Portable backups of the actual work live in `/Users/stephtapera/Desktop/AMEN/governance-backup/`:
- `0001-feat-governance-close-G-1-G-2-G-3-end-to-end.patch`
- `0002-chore-governance-reconcile-readiness-gate-with-live-.patch`
- `governance-gap-closures.bundle`

To restore elsewhere: `git am 0001-*.patch 0002-*.patch` onto the target branch.

**To enable a real GitHub backup** (separate task, quiet tree): either migrate the
`*.nosync` / SourcePackages blobs to Git LFS, or ensure `*.nosync` is gitignored and the
blobs are removed from history (`git filter-repo`), then push.

## Merge to `main` — HELD (not fast-forwardable)

`main` has diverged from this branch (was 0-behind earlier; now ~37 ahead / 11). A
concurrent `git push origin main` from another agent was observed. `--ff-only` will
refuse, and a non-ff merge during active multi-agent work risks conflicts. Do on a quiet
tree:

```sh
# Only if it reports a fast-forward; otherwise rebase/cherry-pick onto main deliberately.
git -C "<repo>" checkout main
git -C "<repo>" merge --ff-only feature/governance-hardening
```

## Deploy — HELD (preconditions unmet)

Firebase CLI is authenticated, but: (1) the changes are not in `main` or the primary
working dir, only in the worktree; (2) the worktree has no `node_modules` for the function
codebases, so the predeploy build cannot run; (3) the branch is 400+ commits divergent, so
deploying its function bundles risks regressing unrelated code.

**Corrected targeted commands** (the `default` codebase was wrong for `bereanPipeline`).
Run from repo root, on a quiet tree, AFTER the change is merged into the deploy source and
deps are installed:

```sh
# exportAmenFile lives in functions/  -> codebase "default"
firebase deploy --only functions:default:exportAmenFile

# bereanPipeline lives in Backend/functions/ -> codebase "creator" (NOT default)
firebase deploy --only functions:creator:bereanPipeline
```

Region rule + quota (us-central1 at 999/1000) per `CLAUDE.md` still apply; these are
updates to existing functions, so no new Cloud Run service is created.

## Build / Swift suite — HUMAN-PENDING

Add to the AMENAPPTests target, then run the Swift suite on the quiet tree:
- `GovernanceRedLineTests.swift`
- `CrisisSafetyPlanEncryptionTests.swift` (cipher tests need a test HOST app — Keychain)

Green run flips NO-GO blocker `FR-3`.

## NO-GO blockers remaining (4)

| ID | Owner | Status |
|----|-------|--------|
| FR-3 | engineering | code-complete; needs Swift suite green |
| P10-R1 | legal/DPO | analytics privacy-questionnaire classification |
| P5-Y2 | legal/federal | ESP + NCMEC registration (red-line gated) |
| P5-R1 | legal | CSAM hash-provider contract + non-engineer sign-off (red-line `csam`; never DIY) |

P5-Y2 / P5-R1 cannot be closed in code — by design (invariants 4, 6, 8).
