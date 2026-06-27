# Context System — fail-close patch record

**Orphan record branch.** This branch exists only to carry a reviewable, remote copy of the
Context System fail-close fix, because the working branch `feature/liquid-glass-hero` cannot be
pushed (large-history / SourcePackages blob blocker, human-owned).

## Contents
- `context-flags-fail-closed.patch` — `git format-patch` of commit `3fef620c`, applyable to the
  feature branch with `git am` / `git apply`. Sets `context_universal_import_enabled` and
  `context_berean_interview_enabled` to **false** in both the stored-property defaults and the
  `buildDefaults` fallback (fail-closed), per `CONTEXT_SYSTEM_RELEASE_GATE.md`.
- `CONTEXT_SYSTEM_CERTIFICATION_PROOF.md` — the BLOCKED proof-chain record.

## Status
Context System is **safe-surface live, NOT release-certified**. The two untrusted-LLM flags
stay **OFF** until quiet-tree archive + ASC privacy questionnaire + on-device App-Check-valid
live bait test all pass with real artifacts. This branch certifies nothing; it preserves the fix.

The canonical fix lives on `feature/liquid-glass-hero` at commit `3fef620c`
(local tag `context-flags-fail-closed`).
