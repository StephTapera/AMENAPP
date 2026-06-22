# B-02: Paid Orgs and Moderation Bypass
**Group:** BEFORE-LAUNCH
**Decision:** Should paying church or organization accounts receive any bypass, reduction, or exemption from content moderation?

---

## Recommended Answer
NO. Paid status never grants moderation bypass. Moderation rules apply identically to free and paid accounts. A paying account that posts CSAM is handled identically to a free account — immediate content removal, NCMEC pipeline triggered, account actioned.

## Rationale
Moderation bypass for paying accounts creates a two-tiered safety system where bad actors could purchase their way out of content enforcement. In the faith-community context, a paying church with a trusted role could be exploited if paying granted any moderation leniency. This decision also simplifies the legal posture: there is no "premium safety" tier and no argument that a victim was harmed because their abuser paid for a church account.

## What the code already does (file:line)
- `functions/moderation/escalation.js` — CSAM escalation pipeline runs regardless of account tier (no tier check found)
- `AMENAPP/AMENAPP/Monetization/AmenAccountTier.swift` — account tier model; no moderation-bypass logic found
- The code appears correct already — no bypass exists in the current moderation path
- Confirm: search for any `isPaid || isChurchPro` conditions in moderation CF before deploying

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| No bypass for paid (recommended) | No code change needed; document policy explicitly | Correct |
| Paid accounts get expedited appeals | Add priority queue for paid-account appeals only — NOT bypass | Acceptable if appeals only, not moderation thresholds |
| Paid accounts get reduced moderation sensitivity | Change NeMo Guard thresholds based on account tier | Legal liability; creates de-facto immunity for paying bad actors |

## Legal consultation required?
NO — product policy decision. Document the decision in the sign-off table.

---
**Status:** ☐ OPEN
**Owner:** Founder + Safety Officer
