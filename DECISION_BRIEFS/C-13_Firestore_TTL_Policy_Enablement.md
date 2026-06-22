# C-13: Firestore TTL Policy Enablement
**Group:** LATER (post-launch, within 90 days)
**Decision:** Have Firestore TTL policies for `moderationQueue.expireAt` and `moderationDeadLetter` been enabled in the Firebase Console?

---

## Recommended Answer
Enable Firestore TTL policies in the Firebase Console for `moderationQueue` (field: `expireAt`) and `moderationDeadLetter` (field: `expireAt`) within 30 days of launch. This is a manual console step that cannot be done from code.

## Rationale
Firestore TTL policies automatically delete documents when the `expireAt` timestamp passes. Without enabling the TTL policy in the Console, `expireAt` fields are ignored — documents never expire and the `moderationQueue` and `moderationDeadLetter` collections grow indefinitely. This creates storage cost growth and may create a compliance risk if retained documents include PII that should have been purged. The TTL policy must be enabled via the Firebase Console under Firestore > Indexes > TTL.

## What the code already does (file:line)
- `functions/moderateUGC.js` (implied) — `expireAt` fields written to `moderationQueue` documents
- Gap: Firebase Console TTL policy status for `moderationQueue` not confirmed enabled
- Gap: Firebase Console TTL policy status for `moderationDeadLetter` not confirmed enabled

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Enable TTL in Console (recommended) | No code change; Console configuration step only | Correct; reduces storage cost and compliance risk |
| Write a cleanup CF | Add scheduled CF that deletes old documents | More complex; duplicates TTL functionality |
| No TTL | Collections grow indefinitely | Storage cost; potential PII retention beyond policy |

## Legal consultation required?
NO — technical infrastructure decision. Retention periods were decided in B-06.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Engineering Lead
