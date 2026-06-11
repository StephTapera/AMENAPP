# B-25: `backfillUsernameLookup` Admin Claim Guard
**Group:** BEFORE-LAUNCH
**Decision:** Does `backfillUsernameLookup` have an admin claim guard? Any authenticated user being able to invoke it is a significant security gap.

---

## Recommended Answer
The admin claim guard is ALREADY IMPLEMENTED as of the current code (`authenticationHelpers.js:436`). Confirm this is the deployed version and no older version without the guard exists in a deployed function alias.

## Rationale
`authenticationHelpers.js:436` shows `exports.backfillUsernameLookup = onCall(...)` and line 436 says "Now requires the admin custom claim." The guard appears to have been added. However, the decision doc flags this as an open item. Confirm that the deployed version in Firebase matches the current code, not a cached or earlier deployment that lacked the guard.

## What the code already does (file:line)
- `functions/authenticationHelpers.js:428` — `exports.backfillUsernameLookup = onCall(...)` defined
- `functions/authenticationHelpers.js:436` — comment: "Now requires the admin custom claim (same guard as setAdminClaim and banUserPhone)"
- `functions/index.js:334` — `exports.backfillUsernameLookup = authenticationHelpers.backfillUsernameLookup`
- Status: Guard appears to be present in current code

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Confirm guard is deployed (recommended) | Check Firebase Console deployed version; run `firebase functions:list` | Low effort; confirm deployed == current code |
| Guard is missing | Add admin claim check as first line of callable | Any authenticated user can trigger bulk backfill |
| Remove the function | Delete export from `index.js` after backfill is complete | Clean; one-time backfill functions should not remain permanently deployed |

## Legal consultation required?
NO — technical security confirmation.

---
**Status:** ☐ OPEN (confirm deployed version matches code)
**Owner:** Engineering Lead
