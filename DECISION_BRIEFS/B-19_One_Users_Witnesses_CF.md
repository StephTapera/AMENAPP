# B-19: `one_users/witnesses` Enforcement CF
**Group:** BEFORE-LAUNCH
**Decision:** Which CF enforces the both-party acceptance constraint on the `one_users/witnesses` subcollection? A comment says "CF validates both-party acceptance" but no CF callable was confirmed.

---

## Recommended Answer
Identify or implement the CF. Restrict client write to `allow create: if request.auth.uid == uid`. Move all other writes to CF-only. Both-party acceptance must be enforced before the document is written, not after.

## Rationale
The `one_users/witnesses` subcollection represents a trust relationship ("ONE" social graph). If both-party acceptance is only checked in code comments and not enforced by an actual CF or Firestore rule, a client can unilaterally create a witness relationship without the other party's consent. In a faith community context, falsified trust relationships could be used to gain access to private spaces or gain social credibility with minor accounts.

## What the code already does (file:line)
- `firestore.rules` — `one_users/witnesses` subcollection: comment says "CF validates both-party acceptance" but no rule enforces this
- Gap: No CF callable confirmed for `/one_users/{uid}/witnesses/{witnessId}` document creation
- Gap: Rule may only restrict `allow create: if request.auth.uid == uid` (one-party constraint), not both-party

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Implement both-party CF (recommended) | Build `createWitnessRelationship` CF callable; deny direct client write; CF checks both parties | Correct enforcement |
| Accept one-party creation + CF post-validation | Allow client write; CF trigger validates and reverts if invalid | Race condition; bad write may be read before CF fires |
| Disable witnesses feature | Block all writes to `one_users/witnesses` | Feature disabled; appropriate if not part of v1 |

## Legal consultation required?
NO — technical security decision.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead
