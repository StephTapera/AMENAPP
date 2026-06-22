# C-15: Admin Console `ageTier` Override Protection
**Group:** LATER (post-launch, within 90 days)
**Decision:** Can an admin with Firebase Console access bypass the `allow update: if false` Firestore rule by manually setting `ageTier: 'tierD'` for a minor account?

---

## Recommended Answer
Document an explicit policy prohibiting console `ageTier` overrides for minor accounts. Add an audit log CF (`onWrite` trigger on `ageTier` changes) that records every modification to `ageTier` fields, who made it (via `modifiedBy` metadata), and when.

## Rationale
The `allow update: if false` Firestore rule prevents client SDK writes to `ageTier` but does not restrict the Firebase Console Admin SDK. Any project admin with Console access can manually change a minor's `ageTier` to `"tierD"` (18+), bypassing all minor safety restrictions. The I-8 invariant ("ageTier must not be writable by clients") is satisfied, but the Console bypass is not caught. An audit log CF that fires on any `ageTier` write creates a tamper-evident trail that can detect unauthorized overrides.

## What the code already does (file:line)
- `firestore.rules` — `ageTier` field: `allow update: if false` (client SDK writes blocked)
- `functions/ageTier.js` — canonical ageTier computation; no `onWrite` audit trigger found
- Gap: No `onWrite` trigger on `ageTier` field changes found in `functions/`
- Gap: No documented policy prohibiting console overrides

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Policy + audit log CF (recommended) | Add `onDocumentWritten` trigger on `users/{uid}` that detects `ageTier` changes and logs them | Creates detection capability; does not prevent but deters |
| Restrict Console access | Admin IAM configuration; remove Console access for non-engineers | Operational; appropriate at scale |
| Accept current state | No change | Silent bypass possible; undetectable without audit logs |

## Legal consultation required?
NO — operational policy decision.

---
**Status:** ☐ OPEN (90-day post-launch deadline)
**Owner:** Engineering Lead + Founder (policy)
