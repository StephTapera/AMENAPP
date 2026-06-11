# B-03: Minor Discoverability in Search and People Index
**Group:** BEFORE-LAUNCH
**Decision:** Should users under the minimum age floor appear in people search, Algolia index, or directory features?

---

## Recommended Answer
Minors are not discoverable by strangers. Only linked guardians and verified church admins of the minor's registered church can find them. Audit all Algolia sync paths to ensure `shouldExcludeFromPeopleIndex()` is called on every incremental sync.

## Rationale
A minor appearing in a public people search allows any adult to find and follow them, bypassing the mutual-follow gate in `canDM()`. The `shouldExcludeFromPeopleIndex()` function exists and is correctly implemented in `AlgoliaSyncService.swift`, but not all incremental sync paths call it. If a sync path is missed, a minor profile can appear in Algolia results at the moment of update. This is a COPPA violation risk (personal data of minors indexed in an external search system).

## What the code already does (file:line)
- `AMENAPP/AlgoliaSyncService.swift:98` — main sync path calls `shouldExcludeFromPeopleIndex()` correctly
- `AMENAPP/AlgoliaSyncService.swift:255` — incremental path also has the check
- `AMENAPP/AlgoliaSyncService.swift:351–355` — `shouldExcludeFromPeopleIndex()`: returns true if `isMinor == true` OR `ageTier` resolves to minor OR `ageTier` is missing
- Gap: Audit confirmed not ALL incremental sync paths call this function — the gap count is unconfirmed

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Not discoverable (recommended) | Audit and fix all incremental sync paths; add test assertion | Correct COPPA posture |
| Discoverable with restrictions | Define the restrictions precisely; enforce in Algolia query layer | Complex; Algolia filters can be bypassed by direct API calls |
| Fully discoverable | Remove `shouldExcludeFromPeopleIndex()` | COPPA violation; minors exposed to strangers |

## Legal consultation required?
NO — COPPA makes this straightforward: minors' personal data should not be indexed in external systems without parental consent.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead
