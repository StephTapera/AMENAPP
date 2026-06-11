# B-24: RBAC Firestore Path Consistency
**Group:** BEFORE-LAUNCH
**Decision:** Is the RBAC Firestore path used by iOS `AmenRBACService.resolveRole` consistent with the paths used by Cloud Functions for role lookups?

---

## Recommended Answer
Document the canonical RBAC Firestore path. Confirm that all CFs reading roles use the same path as the iOS client. Fix any divergence before launch.

## Rationale
`AmenRBACService.resolveRole` reads from `roles/{contextType}/{contextId}/members/{userId}/membership` with a fallback to `roles/{contextType}/{contextId}/members/{userId}`. If Cloud Functions use a different schema (e.g., `churchMembers/{churchId}/roles/{userId}` or a flat `userRoles/{uid}` document), RBAC checks on the server disagree with client-side checks. An attacker could exploit this by having a role in the CF schema that iOS does not recognize, or vice versa, gaining unauthorized access to moderation, channel creation, or admin actions.

## What the code already does (file:line)
- `AMENAPP/AMENAPP/CommunityOS/Identity/AmenRBACService.swift:255–283` — `resolveRole()` reads `roles/{contextType}/{contextId}/members/{userId}/membership`; fallback to `roles/{contextType}/{contextId}/members/{userId}`
- Gap: No CF file confirmed to read from the same `roles/{contextType}/{contextId}/members/` path
- Gap: `covenantFunctions.js` and `spacesLivekitFunctions.js` — server-side RBAC read path unconfirmed (Q-31)

## What changes per alternative answer
| Alternative | Code change needed | Risk |
|---|---|---|
| Document canonical path + fix divergence | Grep all CF role reads; reconcile to one path | Correct; prevents privilege escalation |
| Accept divergence and document it | No code change | Privilege escalation risk if paths differ in meaningful ways |
| Centralize RBAC to a single CF | Build `resolveRoleCF` callable; iOS and all CFs call it | Cleanest architecture; requires refactor |

## Legal consultation required?
NO — technical security decision.

---
**Status:** ☐ OPEN
**Owner:** Engineering Lead
