# us-central1 Reclamation — Vetting Result (2026-06-10)

## Headline
The canonical `deploy-logs/2026-06-12/dead_central1_functions.txt` (522 "DEAD")
is **56% wrong**. Its definition — "name not in any `exports.` line under `functions/`" —
ignores TWO live sources:
  1. the `Backend/functions` (creator) TypeScript codebase
  2. iOS `httpsCallable("<name>")` call sites

Re-vetting all 522 (case-normalized: service names are lowercase, callers camelCase):

| Bucket | Count |
|---|---|
| Total "DEAD" list | 522 |
| **Has a live caller (iOS OR Backend export) — DELETING = OUTAGE** | **293** |
| Verified-safe (no functions/ export, no Backend export, no iOS caller) | **229** |

False positives include `persistrealtimetranscriptchunk`, `resolvescripturereferences`
(already outaged+restored this session), `matchprayersupport`, `validatethinkfirstcheck`
(a safety gate), `getamendiscoverfeed`, `resolveorcreateconversation`.

## Artifacts
- `verified_safe_to_delete_229.txt` — triple-checked safe set
- `DEAD_list_FALSE_POSITIVES_293.txt` — names that have a live caller; DO NOT DELETE

## Correct methodology (use this, not the old one)
A service is safe to delete ONLY if its name (case-insensitive) appears in NONE of:
  - `exports.` lines under `functions/` (default codebase)
  - `export const` / `export {` under `Backend/functions/src` (creator codebase)
  - `httpsCallable("...")` under `AMENAPP/` (iOS client)

## Status: NOT EXECUTED. Verified-safe list prepared; awaiting human go on deletion.
