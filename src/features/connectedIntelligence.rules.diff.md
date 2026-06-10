# Connected Intelligence v1 — Firestore Rules Diff (FOR HUMAN DEPLOY REVIEW)

> DO NOT auto-apply. This document describes additive rules + one P0 fix for
> `firestore.rules`. Phase 2 / human reviewer pastes these blocks at the noted
> insertion points and deploys. `firestore.rules` is NOT edited by this agent.
>
> Helpers already present (verified): `isSignedIn()` (L54), `isOwner(uid)` (L59),
> `isAdminSDK()` (L65), `isUnderMinimum()` (L91), `isSpaceMember(spaceId)` (L113).
> Timestamp/soft-delete convention follows existing collections (e.g. selahNotes L2135).

---

## PART A — P0 FIX: `discernmentChecks` shared-read leak

### Current rule (firestore.rules:2153–2166) — VERBATIM

```
    // discernmentChecks: created-by read/write; shared checks readable by creator only
    // (sharing to thread participants is enforced server-side via Cloud Function)
    match /discernmentChecks/{checkId} {
      allow read: if request.auth != null &&
        (resource.data.createdBy == request.auth.uid ||
         (resource.data.visibility == 'shared' && resource.data.sourceRef != null));
      allow create: if request.auth != null &&
        request.resource.data.createdBy == request.auth.uid &&
        request.resource.data.visibility == 'private' &&
        request.resource.data.deletedAt == null;
      allow update: if request.auth != null &&
        resource.data.createdBy == request.auth.uid;
      allow delete: if false;  // soft-delete only; no hard delete
    }
```

**Finding (P0):** the second read clause
`(resource.data.visibility == 'shared' && resource.data.sourceRef != null)`
lets **ANY signed-in user** read **ANY** `shared` discernment check, because
`sourceRef != null` is true for essentially every shared check and there is no
participant / membership gate. This exposes private pastoral discernment content
(scripture-grounded counsel on potentially sensitive questions) across the entire
user base.

### Corrected rule — gate the shared branch on participant membership

The comment itself states sharing is *enforced server-side via Cloud Function*.
Reads of a shared check must therefore be restricted to: (a) the creator, OR
(b) a user the CF recorded on the doc as a participant. The CF stamps a
`participants` array (list of uids) and/or a `spaceId` on shared checks; gate on
those. If neither is present, fall closed (CF-admin read only).

```
    // discernmentChecks: created-by read/write; shared checks readable ONLY by
    // creator + CF-recorded participants (or space members). Server (CF) stamps
    // resource.data.participants (list<uid>) and/or resource.data.spaceId at share time.
    match /discernmentChecks/{checkId} {
      allow read: if request.auth != null &&
        (
          resource.data.createdBy == request.auth.uid ||
          (
            resource.data.visibility == 'shared' && (
              request.auth.uid in resource.data.get('participants', []) ||
              isSpaceMember(resource.data.get('spaceId', '__none__'))
            )
          )
        );
      allow create: if request.auth != null &&
        request.resource.data.createdBy == request.auth.uid &&
        request.resource.data.visibility == 'private' &&
        request.resource.data.deletedAt == null;
      allow update: if request.auth != null &&
        resource.data.createdBy == request.auth.uid;
      allow delete: if false;  // soft-delete only; no hard delete
    }
```

> If the CF does NOT currently stamp `participants`/`spaceId`, the safe interim is
> to drop the shared branch entirely (`allow read: if … createdBy == request.auth.uid`)
> and serve shared reads through a CF only. Either way, the unbounded
> `sourceRef != null` clause MUST be removed before deploy.

---

## PART B — NEW COLLECTIONS (Connected Intelligence v1)

Insertion point: inside the top-level `match /databases/{database}/documents { … }`
block, after the AMEN Action Intelligence section (after firestore.rules:2243,
before the closing brace). All collections are owner-scoped, soft-delete only,
and minor-guarded where noted.

```
    // =========================================================================
    // CONNECTED INTELLIGENCE v1 — owner-scoped, soft-delete, minor-guarded
    // Added: 2026-06-09 (Connected Intelligence contract freeze)
    //
    // Invariants:
    //   CI-1: Owner-only read/write unless a server-only field is involved.
    //   CI-2: Minors (isUnderMinimum) cannot create connector grants.
    //   CI-3: No hard deletes — soft delete via softDeleted/revokedAt.
    //   CI-4: OAuth token docs are CF-admin only (allow read,write: if false),
    //         mirroring liveActivityTokens (firestore.rules:536).
    //   CI-5: Scheduled-action execution fields are server-only.
    // =========================================================================

    // Connector grants — owner r/w; minors BLOCKED from granting.
    match /users/{uid}/connectorGrants/{connectorId} {
      allow read: if isOwner(uid);
      allow create, update: if isOwner(uid) &&
        !isUnderMinimum() &&                                  // CI-2 minor guard
        request.resource.data.minorBlocked == false;          // minorBlocked assertion
      allow delete: if false;                                 // CI-3 soft revoke only

      // OAuth token sub-doc — CF-admin only (CI-4), mirrors liveActivityTokens.
      match /tokens/{tokenId} {
        allow read, write: if false;
      }
    }

    // Memories — owner-only; soft delete.
    // NOTE: v1 EXTENDS the existing berean/{uid}/memory store (see reconciliation
    // note below). This block is the canonical mirror IF/when memories migrate to
    // users/{uid}/memories. Until migration, the existing berean/{uid}/memory rule
    // governs writes and THIS block stays unwired. (Decision recorded in RUNLOG.)
    match /users/{uid}/memories/{memoryId} {
      allow read: if isOwner(uid);
      allow create, update: if isOwner(uid);
      allow delete: if false;                                 // soft delete via softDeleted
    }

    // Notebooks — owner r/w; optional Space share via existing membership.
    match /users/{uid}/notebooks/{notebookId} {
      allow read: if isOwner(uid) ||
        (resource.data.sharedSpaceId is string &&
         isSpaceMember(resource.data.sharedSpaceId));
      allow create, update: if isOwner(uid);
      allow delete: if false;                                 // soft delete via softDeleted
    }

    // Scheduled actions — owner r/w on config fields; execution fields server-only.
    match /users/{uid}/scheduledActions/{actionId} {
      allow read: if isOwner(uid);
      allow create, update: if isOwner(uid) &&
        // CI-5: clients may never write server-only execution fields.
        !request.resource.data.diff(resource.data).affectedKeys()
          .hasAny(['lastRunAt', 'nextRunAt', 'dryRunsRemaining', 'aegisReviewId']);
      allow delete: if false;
    }

    // Brief cache — owner read; server (CF) write only.
    match /users/{uid}/briefCache/{date} {
      allow read: if isOwner(uid);
      allow write: if false;                                  // CF admin SDK only
    }

    // Checkpoints — owner r/w.
    match /users/{uid}/checkpoints/{checkpointId} {
      allow read: if isOwner(uid);
      allow create, update: if isOwner(uid);
      allow delete: if false;
    }
```

> The `create`/`update` guard on `scheduledActions` assumes Firestore's
> `diff().affectedKeys()` is available (it is, in v2 rules). On `create`,
> `resource.data` is null, so reviewers should split create (no diff) from update
> if their linter complains; functionally clients still cannot set execution fields
> because the CF seeds them and clients can only update non-execution keys.

---

## RECONCILIATION NOTE — memories path (REQUIRED human decision)

Two candidate paths exist:
- **EXISTING:** `berean/{uid}/memory/{memoryId}` (shape `BereanMemoryDoc`,
  service `src/berean/core/memory.ts`) — already governs memory writes.
- **SPEC:** `users/{uid}/memories/{memoryId}`.

**Chosen:** EXTEND the existing `berean/{uid}/memory` store (do NOT fork a parallel
store). The `MemoryItem` contract is a superset *view*; persistence stays in
`memory.ts` against `berean/{uid}/memory`. The `users/{uid}/memories` rule block
above is provided ONLY for a future migration and ships UNWIRED in v1. Phase 2
agents read/write memory exclusively through the existing path + service.
