# B-01: Pastor / Leader DMs to Minors
**Group:** BEFORE-LAUNCH
**Decision:** Should verified pastors and church leaders be permitted to send direct messages to minor members? If so, under what conditions?

---

## Recommended Answer
Allow only with a guardian-visible thread — every DM thread between any adult leader and a minor is readable by the minor's linked guardian. Auto-notify the guardian on the first message from any non-family adult.

## Rationale
Without explicit restriction, any adult with a church-leader role can DM any minor in their church. This is a standard vector for grooming. The guardian-visible thread model balances pastoral access (which may be legitimate and important for youth ministry) with the protective oversight that parents expect. The notification-on-first-message rule means guardians are never surprised by a thread they didn't know existed. Completely blocking all adult-to-minor DMs from leaders may harm legitimate pastoral relationships; no restriction is not acceptable.

## What the code already does (file:line)
- `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift:149–184` — `canDM()` requires mutual follow for any minor-involved DM; does not distinguish pastor role
- `functions/safety/minorProtection.js:42` — `dmSafetyMode` field supports `"restricted"` | `"guardian_visible"` | `"disabled"` — the framework for guardian-visible threads exists in the schema
- Gap: No role-aware DM check found — `canDM()` does not check if sender is a pastor/leader
- Gap: No "guardian-visible thread" write path found that copies messages to guardian's view

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Guardian-visible thread (recommended) | Add role check in `canDM()`; implement guardian thread copy logic in `safeMessageGateway.js` | Requires guardian-visible thread architecture |
| Completely blocked | Add `role == "pastor"` check in `canDM()`; return false for adult→minor | Simpler; breaks legitimate youth ministry DM |
| No restriction | No change | Grooming vector; legal and reputational risk |

## Legal consultation required?
NO — product and safety policy decision. Church context may create specific expectations from users that should inform the policy.

---
**Status:** ☐ OPEN
**Owner:** Safety Officer + Product
