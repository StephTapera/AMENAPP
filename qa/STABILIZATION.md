# STABILIZATION — getting the AMEN line backed up, pushable, and converged

**Status:** active plan. **Doc-only** — this file describes the sequence; it does
not perform it. The destructive step (Step 5) is **human-only**.

## Why this exists

The local AMEN line is **494 commits ahead of `origin/main`** and **cannot push
to GitHub**: a 225 MB Firebase SPM pack (`SourcePackages.nosync/.../firebase-ios-sdk
.../pack-*.pack`) is baked into history, and GitHub's pre-receive hook hard-rejects
any push whose history contains a blob > 100 MB. Because the line can't push, those
494 commits + 10 stashes exist in **exactly one physical place** until backed up.

This was compacted out of a working session once already. It lives here so the
sequence survives session resets and hand-offs to agents who weren't present.

## The single rule that governs everything below

**Order is load-bearing.** Each step is a precondition for the next. Do not
reorder. In particular: **back up before anything destructive**, and **triage
stashes before the history rewrite** (a rewrite orphans stashes).

---

## Step 0 — Off-machine backup  *(precondition for all destructive work)*

The complete safety net. Built 2026-06-17 at
`/Users/stephtapera/Desktop/AMEN-backup-2026-06-17/` (verified):

| Artifact | Role |
|----------|------|
| `amen-dotgit-2026-06-17.tar.gz` (1.0 GB) | **Authoritative** — full `.git`: all 494 commits + **all 10 stashes** (reflog), full fidelity |
| `amen-complete-history-2026-06-17.bundle` (504 MB) | Portable cross-check. **NOT source of truth** — `git bundle --all` silently drops 8/10 stashes (stash commits aren't reachable from branch refs) |
| `amen-uncommitted-worktree-2026-06-17.tar.gz` (260 KB) | 73 uncommitted working files |

**⚠️ Not a real backup until it is OFF this laptop.** On one SSD it defends
against every agent-caused mistake (`git clean`, `rm`, soft-reset) and **zero**
against disk failure. **→ Drag the folder to an external drive and/or cloud.**
This is the single highest-value action in the whole sequence.

## Step 1 — Quiesce the writers

Stop spawning agents. Let in-flight commits land. The tree must be calm before
any commit-discipline or rewrite work — the recurring bare-`git commit` /
shared-dirty-index problem comes from concurrent writers on one working tree.

## Step 2 — Owners commit their groups to durable branches

Each owner commits their own work, **path-scoped**, to a durable branch — using
temp-index discipline (build a temp index from HEAD, add only the intended paths,
verify *1 expected file set / 0 foreign hunks* before committing). See
`qa/UNCOMMITTED_INVENTORY.md` for the file→owner map. This clears the shared
staged pile without one agent sweeping another's work into a bare commit.

## Step 3 — Triage the 10 stashes  *(must precede Step 5)*

On the now-calm tree, review all 10 stashes: confirm keepers (e.g. `@{0}`, `@{3}`)
vs. superseded giants. **Apply none until decided.** This has to happen *before*
the history rewrite, because a rewrite orphans stash entries — resolve them while
they're still attached.

## Step 4 — *(reserved — folded into Step 3 triage outcome)*

## Step 5 — Strip the large blobs  *(HUMAN-ONLY · backup in hand · tree quiet)*

`git-filter-repo` to remove the >100 MB (and >50 MB) blobs from history. This is
the single most destructive git operation: it **rewrites every commit SHA and
force-pushes**, orphaning every worktree/agent on the old history. Hard
preconditions: **Step 0 backup confirmed off-machine**, and **tree quiesced
(Steps 1–3 done)**. This is what finally makes the line sub-100 MB and pushable.
**An agent must not run this.**

## Step 6 — Converge onto `cert/clean-launch`

Merge the durable branches (Step 2) onto the cert/clean-launch line. **Watch the
safety-code conflicts** — COPPA age gate, crisis/NCMEC paths, MinorSafetyGate,
moderation — that's where controls get silently clobbered during merges. Review
those hunks by hand.

## Step 7 — Build `cert/clean-launch` in isolation  *(the v1 ship gate)*

Clean compile in a fresh worktree, away from the hot tree. **This is the real ship
criterion** — green build on the converged, reconciled line, not a green build on
the live tree mid-edit.

## Step 8 — Push

Now that the line is sub-100 MB and history is reconciled, push to origin and open
PRs for review. This is the first time the line has a pushable, backed-up,
integrated origin — the foundation v1 is assembled and submitted from.

---

### Invariants for any agent touching this repo
- **Never** run destructive/history git (`reset`, `rebase`, `filter-repo`,
  force-push, `git clean`) — human-only. Step 5 especially.
- **Never** `git commit` without a path scope; **never** `git add -A` on the
  shared tree. Use temp-index discipline.
- Safety-adjacent files (age gate, crisis, CSAM/NCMEC, moderation, minor safety)
  get extra scrutiny on every commit and merge — content over green badge.
