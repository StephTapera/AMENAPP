# cloud-functions — QUARANTINED

This directory is an orphaned Cloud Functions deploy context that was never wired into the root `firebase.json`.

**Status:** Quarantined 2026-06-12. Its `firebase.json` codebase name has been changed to `quarantine-legacy` to prevent accidental deployment masquerading as the real `default` codebase.

**Functions exported here** (`moderatePost`, `moderateComment`, `checkContent`, `detectCrisis`) are NOT deployed anywhere. The production equivalents live in `functions/` (default codebase).

**Do not deploy from this directory.** If you need to permanently retire it, run:
```
git mv cloud-functions cloud-functions.RETIRED
```
and verify with `firebase functions:list` that none of these names are live before removing the directory.
