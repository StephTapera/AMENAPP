# RULES_PLAN_CONNECT.md — Firestore rules plan for Connect V1 (Phase 0 deliverable #5)

**Date:** 2026-06-18 · **Spec:** `AMEN_CONNECT_V1_SPEC.md` §6 · **Canonical rules file:** `firestore.rules` (repo root, also copied to `AMENAPP/firestore.deploy.rules`).
**Deploy (human-gated):** `firebase deploy --only firestore:rules --project amen-5e359`.
**Test harness:** `Backend/rules-tests/` (Jest + `@firebase/rules-unit-testing`), pattern in `amen-connect.rules.test.ts`.

These rules are **planned, not written** in Phase 0. They land in Wave 1 / Phase 3 with two-sided emulator proof. The default posture for every Connect collection is **deny**; every allow is justified below. Reuse existing helpers — do not duplicate `isSignedIn()`, `isOwner()`, `isAdminSDK()`, `hasAnyClaimRole()`, `validSoftDelete()`, the `diff().affectedKeys().hasOnly()` field-guard pattern, or the `isMinor()` claim helper (`firestore.rules:90-93`).

---

## New helper functions (add once, near `firestore.rules:120`)

```
// Active, verified guardian link from the requester to a specific child.
function hasVerifiedGuardianLink(childId) {
  return isSignedIn() &&
    exists(/databases/$(database)/documents/guardianLinks/$(request.auth.uid + '_' + childId)) &&
    get(/databases/$(database)/documents/guardianLinks/$(request.auth.uid + '_' + childId))
      .data.get('status', '') == 'verified';
}
```

`guardianLinks` doc id is the composite `{guardianUid}_{childId}` (mirrors the existing `follows_index` / `blockedUsers` composite-key convention, `firestore.rules:129`).

---

## Collection-by-collection plan

| Collection | read | create | update | delete | Notes |
|---|---|---|---|---|---|
| `churches/{cid}` (+ `serviceTimes\|events\|ministries\|smallGroups\|sermons`) | member or public | staff roles, same church | staff roles, server fields guarded | `false` (soft-delete) | EXTENDS existing `firestore.rules:1149-1188`. Do not duplicate. |
| `churches/{cid}/resources/{id}` | member, **but media fields only when `moderation == 'approved'`** | staff | staff | `false` | MEDIA-GATE fail-closed mirrors `creatorProfiles` pattern. |
| `churches/{cid}/volunteerNeeds/{id}` | member | staff | staff | `false` | V2 surface, schema only at V1. |
| `members/{cid}_{uid}` | self, or staff of that church, or `isAdminSDK()` | **CF only** (`false`) | **CF only** — `roles` is server-only | `false` (soft-delete `isActive:false`) | `roles` never client-writable. |
| `guardianLinks/{guardianUid}_{childId}` | the guardian (`request.auth.uid == guardianUid`) only | **CF only** (`requestGuardianLink`) | **CF only** — `status`/`verifiedAt` server-only | **CF only** | Self-asserted links forbidden; verification is server-side. |
| `children/{cid}_{childId}` | **`hasVerifiedGuardianLink(childId)` only** (else deny) | **CF only** | **CF only** | **CF only** | Minor PII. Never broadly readable. No analytics path. |
| `checkIns/{cid}/{sessionId}/{childId}` | **`hasVerifiedGuardianLink(childId)` or operating-staff need-to-know** | **CF only** (QR/pickup-code) | **CF only** | **CF only** | `pickupCode`/`authorizedPickup` access-control-grade. |
| `users/{uid}/connectPrefs` (singleton) | owner | owner | owner, no server fields | owner | EXTENDS `users/{uid}` private pattern (`firestore.rules:604-618`). |
| `prayerRequests/{id}` | per `scope` (private→owner, group→group member, church→church member) | **CF only** | **CF only** — `answered`/`answeredAt` server-only | **CF only** | EXTENDS existing `firestore.rules:933-950`. Minor-authored: author PII never exposed. |
| `prayerFollows/{uid}_{requestId}` | owner | owner (own uid only) | owner | owner | Composite-key, self-scoped. |
| `connectReports/{id}` | moderators only (`hasAnyClaimRole([...])`) | signed-in, strict field allow-list | moderators | owner/exec-admin (CF + audit) | Mirrors `moderationQueue` (`firestore.rules:1606-1638`); `child_safety_concern` → absolute-stop escalation, not normal queue. |

**Server-only fields (client `update` must not touch):** `guardianLinks.status`, `guardianLinks.verifiedAt`, `members.roles`, `prayerRequests.answered`, `prayerRequests.answeredAt`, any `*_state`. Enforce with the existing `diff(resource.data).affectedKeys().hasOnly([...])` guard.

---

## Two-sided emulator matrix (Phase 3 — no PASS without both sides green)

Each row needs an explicit ALLOW test and an explicit DENY test, reported with `path:line`.

| # | Invariant | ALLOW (must succeed) | DENY (must fail) |
|---|---|---|---|
| R1 | Guardian gate on child reads | verified guardian reads `children/{cid}_{childId}` | non-guardian (and pending-link guardian) reads it |
| R2 | Check-in guardian gate | verified guardian reads `checkIns/.../{childId}` | unrelated member reads it |
| R3 | Link is server-verified | CF sets `status:'verified'` | client writes `status:'verified'` or `verifiedAt` directly |
| R4 | Roles server-only | CF sets `members.roles` | client writes `members.roles` |
| R5 | Prayer answered server-only | CF sets `answered:true` | client writes `answered:true` |
| R6 | Prayer scope | church-scope request read by same-church member | private-scope request read by non-owner |
| R7 | Minor PII not in analytics | (n/a allow) | any client read of `children/**` via a non-guardian path; any minor doc surfaced in an aggregate/analytics collection |
| R8 | MEDIA-GATE | approved resource media readable | `moderation != 'approved'` media field readable |
| R9 | Reports moderator-only | moderator reads `connectReports` | normal member reads `connectReports` |
| R10 | Concierge data-scope (enforced in-function, asserted here) | requester reads own + guardian-linked child records | requester reads another member's record |

Emulator is two-sided per `Backend/rules-tests/amen-connect.rules.test.ts` (`assertSucceeds`/`assertFails`). Add `connect.rules.test.ts` covering R1–R10.
