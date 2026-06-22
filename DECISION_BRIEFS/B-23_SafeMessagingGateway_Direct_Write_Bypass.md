# B-23: `safeMessagingGateway.js` Direct Write Bypass
**Group:** BEFORE-LAUNCH
**Decision:** Do Firestore security rules block direct client writes to the DM messages collection, or can a client bypass `safeMessagingGateway.js` entirely?

---

## Recommended Answer
Confirm Firestore rules deny all direct client writes to the DM messages collection (only Admin SDK / CF writes permitted). Update the `senderData.isBanned` check in `safeMessagingGateway.js` to use `admin.auth().getUser(uid).disabled` for real-time ban status rather than a Firestore field that may be stale.

## Rationale
`safeMessagingGateway.js:593` checks `liveData.isBanned` before writing a DM message. This ban check is only meaningful if the gateway is the only path that can write to the messages collection. If Firestore rules allow direct client writes, a banned user can bypass the gateway by writing directly via the Firebase SDK — the gateway ban check is then a no-op. The Admin SDK `getUser()` check is also more reliable than a Firestore field because the `isBanned` Firestore field could be stale if the ban was applied recently.

## What the code already does (file:line)
- `functions/safeMessagingGateway.js:593` — `isBanned` check against Firestore field `liveData.isBanned`
- `functions/index.js:240` — `safeMessageGateway` exported from `safeMessagingGateway.js`
- Gap: Firestore rule for DM messages collection (`conversations/{id}/messages/`) not confirmed to deny direct client writes
- Gap: `isBanned` reads from Firestore field (potentially stale); `admin.auth().getUser(uid).disabled` would be real-time

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Confirm + update rule + real-time ban check (recommended) | Verify `firestore.rules` denies direct writes; update ban check to use `admin.auth()` | Correct |
| Confirm rule only | Verify Firestore rule; leave ban check as-is | Stale ban state; recently-banned user can DM for a few seconds |
| No change | Audit and document current state | Unknown if ban bypass is possible |

## Legal consultation required?
NO — technical security decision.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead
