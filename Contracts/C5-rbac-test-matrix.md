# C5 — RBAC Test Assertion Matrix

**Contract ID:** C5 (companion to C5-security-rules.md)  
**Phase:** 0 (CI test skeleton — no passing implementation yet)  
**Owner:** Trust & Safety Lead  
**Purpose:** Every row is an executable test case. CI must run these against the Firestore Rules Emulator before any Phase 4 merge.  
**Test runner:** Firebase Rules Unit Testing (JS SDK with `@firebase/rules-unit-testing`)  
**Minimum count:** 35 test cases (≥ 30 required, 35 delivered)

---

## Test Case Format

```
Actor:    Role + optional context (e.g., churchId, spaceId, ageTier)
Resource: Collection path + document shape relevant to the test
Action:   Firestore operation (get | list | create | update | delete)
Expected: ALLOW or DENY
Notes:    Condition code from C5-security-rules.md §2 that drives the expectation
```

---

## Group 1 — Visitor Tests (5 cases)

| Test ID | Actor | Resource | Action | Expected | Notes |
|---------|-------|----------|--------|----------|-------|
| **C5-V-01** | Visitor (unauthenticated) | `posts/{id}` where `privacyLevel == 'public'` | `get` | ALLOW | Public posts readable without auth (pending OPEN-5 resolution) |
| **C5-V-02** | Visitor (unauthenticated) | `posts/{id}` where `privacyLevel == 'private'` | `get` | DENY | Private content is owner-only |
| **C5-V-03** | Visitor (authenticated, no org membership) | `posts/{id}` | `create` | DENY | Visitors cannot create posts — must be a Member or above |
| **C5-V-04** | Visitor (authenticated, no org membership) | `posts/{id}` where `privacyLevel == 'church'` | `get` | DENY | Church-scoped content requires verified church membership |
| **C5-V-05** | Visitor (authenticated, no org membership) | `conversations/{id}` (DM) | `create` | DENY | Visitors cannot initiate DMs |

---

## Group 2 — Minor Tests (5 cases)

| Test ID | Actor | Resource | Action | Expected | Notes |
|---------|-------|----------|--------|----------|-------|
| **C5-M-01** | Minor (`ageTier == 'teen'`) | `conversations/{id}` (new DM to non-mutual-follow adult) | `create` | DENY | `[MINOR]` C-MINOR-DM: DMs to non-mutual-follows are hard blocked |
| **C5-M-02** | Minor (`ageTier == 'teen'`) | `posts/{id}` create with `privacyLevel == 'public'` without `publicConfirmed == true` | `create` | DENY | `[MINOR]` Default-private invariant I-3: public posting requires explicit confirmation field |
| **C5-M-03** | Minor (`ageTier == 'teen'`) | `posts/{id}` create with `privacyLevel == 'private'` | `create` | ALLOW | `[MINOR]` Private content creation is permitted for Minors |
| **C5-M-04** | Minor (`ageTier == 'teen'`) | `jobs/{id}` | `get` | DENY | `[MINOR]` C-AGE: Job listings are completely blocked for Minors |
| **C5-M-05** | Minor (`ageTier == 'under_minimum'`) | Any resource | `create` | DENY | `[MINOR]` Under-minimum accounts are fully suspended; no writes permitted |

---

## Group 3 — Moderator Tests (5 cases)

| Test ID | Actor | Resource | Action | Expected | Notes |
|---------|-------|----------|--------|----------|-------|
| **C5-MOD-01** | Moderator (same org as post) | `posts/{id}` soft-delete update (set `deletedAt`) | `update` | ALLOW + AUDIT | C-AUDIT + C-MOD: Moderators can soft-delete posts within their org scope |
| **C5-MOD-02** | Moderator | `posts/{id}` hard delete (`delete` operation) | `delete` | DENY | I-1: Hard deletes denied for all client roles; soft-delete only |
| **C5-MOD-03** | Moderator | `moderationQueue/{id}` | `get` | ALLOW | Moderators can read the moderation queue |
| **C5-MOD-04** | Moderator | `adminDashboard/{id}` (full analytics) | `get` | DENY | Moderators have queue-only view; full dashboard requires Owner/ExecutiveAdmin |
| **C5-MOD-05** | Moderator | `users/{uid}/private/age_assurance` | `update` | DENY | I-8: Age profile is unwritable by any client role, including Moderators |

---

## Group 4 — Owner Tests (5 cases)

| Test ID | Actor | Resource | Action | Expected | Notes |
|---------|-------|----------|--------|----------|-------|
| **C5-OWN-01** | Owner | `organizations/{orgId}` (their own org) | `update` with audit log batch | ALLOW + AUDIT | C-AUDIT: Owner can update their own org when audit log is written atomically |
| **C5-OWN-02** | Owner of Org A | `organizations/{orgId}` for Org B | `update` | DENY | Owners are scoped to their own org; cross-org update is denied |
| **C5-OWN-03** | Owner | `auditLog/{eventId}` | `delete` | DENY | Audit log is append-only — delete is denied even for Owner |
| **C5-OWN-04** | Owner | `posts/{id}` (soft-delete another member's post in own org) | `update` setting `deletedAt` | ALLOW + AUDIT | C-AUDIT: Owner may soft-delete any post in their org scope |
| **C5-OWN-05** | Owner | `users/{uid}/private/age_assurance` | `update` | DENY | I-8: Even Owner cannot update age profiles — Admin SDK only |

---

## Group 5 — Cross-Role Escalation Tests (5 cases)

| Test ID | Actor | Resource | Action | Expected | Notes |
|---------|-------|----------|--------|----------|-------|
| **C5-ESC-01** | Member (no special role) | `moderationQueue/{id}` | `update` (action an item) | DENY | Members cannot action moderation queue items |
| **C5-ESC-02** | Leader (space-scoped) | `moderationQueue/{id}` for a post outside their space | `update` | DENY | C-SPACE: Leader moderation is scoped to their space only |
| **C5-ESC-03** | ContentManager | `users/{uid}` (another member's profile) | `update` | DENY | ContentManager has no member management rights |
| **C5-ESC-04** | EventManager | `posts/{id}` (non-event post) | `create` | ALLOW | EventManager is still a member; can create personal posts |
| **C5-ESC-05** | Pastor (Church A) | `posts/{id}` with `churchId == 'Church-B'` and `privacyLevel == 'church'` | `get` | DENY | C-CHURCH: Cross-church private content is denied (see OPEN-6) |

---

## Group 6 — Edge Cases (10 cases)

| Test ID | Actor | Resource | Action | Expected | Notes |
|---------|-------|----------|--------|----------|-------|
| **C5-EDGE-01** | Any authenticated user | `posts/{id}` with `ownerUidEncrypted` field | `get` (read the field) | Field masked / DENY field read | I-6: `ownerUidEncrypted` must never be readable by any client |
| **C5-EDGE-02** | Any authenticated user | `bereanInsights/{id}` | `create` | DENY | I-7: BereanInsight is CF-write-only; client creates are denied |
| **C5-EDGE-03** | Minor (`ageTier == 'teen'`) | `posts/{id}` with `privacyLevel == 'public'` AND `publicConfirmed == true` | `create` | ALLOW | `[MINOR]` Minors CAN post publicly if they explicitly set `publicConfirmed = true` after the UI confirmation step |
| **C5-EDGE-04** | Minor (`ageTier == 'teen'`) | `conversations/{id}` (DM to mutual follow who is also a Minor) | `create` | ALLOW | `[MINOR]` C-MINOR-DM: Mutual-follow DMs between two Minors are permitted (both must be mutual follows) |
| **C5-EDGE-05** | ExecutiveAdmin | `users/{uid}/private/age_assurance` | `update` | DENY | I-8: Even ExecutiveAdmin cannot update age profile via client — Admin SDK only |
| **C5-EDGE-06** | Member | Anonymous `prayers/{id}` (field `ownerUidEncrypted` exists) | `get` | ALLOW (document), DENY (ownerUidEncrypted field) | I-6: Document is readable; the encrypted owner field is masked |
| **C5-EDGE-07** | Visitor | `volunteerOpportunities/{id}` where `contactPhone` field exists | `get` | DENY (field must not exist per I-5) | I-5: PII fields in opportunity listings are a creation-time validation failure; if a document somehow contains `contactPhone`, get is denied entirely |
| **C5-EDGE-08** | Owner | `auditLog/{eventId}` | `update` | DENY | Audit log is append-only; updates denied for all roles including Owner |
| **C5-EDGE-09** | Unauthenticated visitor | `users/{uid}/private/age_assurance` | `get` | DENY | Age profile is private subcollection; no unauthenticated access |
| **C5-EDGE-10** | Member with `ageTier == 'adult'` who self-edits their `ageTier` field in `/users/{uid}` | `update` (client sets `ageTier: 'adult'` on own profile doc) | `update` | DENY | Age-tier escalation via client write is forbidden; `ageTier` field is server-managed only |

---

## Test Setup Notes (for CI implementation)

```javascript
// Required Firebase Rules Emulator test setup
// File: rules-tests/c5-rbac.test.js

const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');

// Actor helpers
function asVisitor(env)           { return env.unauthenticatedContext(); }
function asMinor(env, uid)        { return env.authenticatedContext(uid, { ageTier: 'teen', role: 'minor' }); }
function asMember(env, uid, org)  { return env.authenticatedContext(uid, { role: 'member', orgId: org }); }
function asModerator(env, uid, org) { return env.authenticatedContext(uid, { role: 'moderator', orgId: org }); }
function asOwner(env, uid, org)   { return env.authenticatedContext(uid, { role: 'owner', orgId: org }); }
function asPastor(env, uid, churchId) { return env.authenticatedContext(uid, { role: 'pastor', churchId }); }
function asExecAdmin(env, uid)    { return env.authenticatedContext(uid, { role: 'executive_admin', admin: true }); }

// Each test case maps 1:1 to a row in the matrix above
// Test IDs must match exactly: C5-V-01, C5-M-01, etc.
// CI fails if any ALLOW test returns DENY or any DENY test returns ALLOW
```

---

## Compliance Checklist

Before Phase 4 merge, the T&S Lead must verify:

- [ ] All 35 test cases pass against the production-ready `firestore.rules`
- [ ] OPEN-1 resolved: minor age threshold confirmed
- [ ] OPEN-2 resolved: guardian tools scope defined
- [ ] OPEN-3 resolved: anonymous shielding level chosen
- [ ] OPEN-4 resolved: NCMEC pipeline SLA + escalation key holder identified
- [ ] OPEN-5 resolved: unauthenticated visitor read access decision documented
- [ ] OPEN-6 resolved: cross-church data access confirmed as denied
- [ ] Audit log write is tested atomically with each C-AUDIT action
- [ ] `ownerUidEncrypted` field mask test (C5-EDGE-01) passes
- [ ] Age profile immutability tests (C5-OWN-05, C5-MOD-05, C5-EDGE-05) all DENY

---

*End of C5 RBAC Test Matrix*
