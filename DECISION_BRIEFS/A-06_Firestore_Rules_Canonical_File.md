# A-06: Which Firestore Rules File Is Deployed to Production
**Group:** ANSWER-NOW (HARD BLOCKER)
**Decision:** Which of the two Firestore rules files — `firestore.rules` (repo root) or `AMENAPP/AMENAPP/firestore.deploy.rules` — is the canonical source of truth that `firebase.json` points to for production deploys?

---

## Recommended Answer
Run `firebase deploy --only firestore:rules --dry-run` to confirm which file is live. Reconcile both files into a single canonical file (recommend the repo-root `firestore.rules` since it is the most recently modified). Verify the reconciled file includes `safetyAuditLog`, `guardianLinkRequests`, and `guardianApprovedContacts` rules. Update `firebase.json` to point to the canonical file and delete the stale copy.

## Rationale
The safety-hardening branch has modified both files but they have diverged. The coverage gap for `safetyAuditLog`/`guardianLinkRequests` exists in one file but not the other. If the wrong file is live, child safety data written to those collections may be accessible to any authenticated user or completely blocked, neither of which is correct. The `firebase.json` comment says to change the `'firestore.rules'` field before deploying, which suggests it may be pointing to the wrong file today.

## What the code already does (file:line)
- `firestore.rules` (root) — lines 2776–2833: contains `legalHolds` and related safety rules
- `firebase.json` — `"firestore": { "rules": "firestore.rules" }` — points to root file (confirm current value)
- `AMENAPP/AMENAPP/firestore.deploy.rules` — exists as secondary copy; divergence from root
- Gap: No dry-run has been performed to confirm which file is actually deployed

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Root `firestore.rules` as canonical (recommended) | Delete `firestore.deploy.rules`; verify `firebase.json` already points to root | Clean; one file to maintain |
| `firestore.deploy.rules` as canonical | Update `firebase.json`; reconcile missing rules from root into this file | More work; root file is larger and more complete |
| Leave both files, no reconciliation | No change | Ongoing drift risk; deploy confusion; safety gap persists |

## Legal consultation required?
NO — technical decision. Engineering lead can resolve with a dry-run and diff.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead
