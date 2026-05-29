# PII Migration Plan: email / phoneNumber fields

**Status:** In progress — client writes now blocked by Firestore rules; data migration pending  
**Priority:** P1 (THREAT_MODEL.md Risk #1)  
**Owner:** Engineering  
**Last updated:** 2026-05-29

---

## Current State (Before Migration)

The root `/users/{uid}` document currently stores two PII fields that should not live there:

| Field | Problem | Written by |
|-------|---------|------------|
| `email` | Readable by every signed-in user (the root doc has `allow read: if isSignedIn()`). Every AMEN user can query any other user's email address. | `UserService.updateUserEmail` (iOS) |
| `phoneNumber` | Same broad read exposure. Also queried by `DiscoveryService.loadContactSuggestions` which can leak phone numbers via client-side queries. | `DiscoveryService` (iOS) |

Firestore Security Rules **cannot mask individual fields** on a document read. If a user has
`allow read` to `/users/{uid}`, they receive the entire document, including `email` and
`phoneNumber`. The only fix is to remove these fields from the root document.

---

## Why Client Writes Are Now Blocked

As of the security hardening commit (feat(security): Firestore/Storage rules hardening + deny-test suite),
the Firestore rules on `/users/{uid}` now include two new guards:

```
function hasNoPIIFields() {
  return !request.resource.data.keys().hasAny(['email', 'phoneNumber']);
}

function piuFieldsUnchanged() {
  return !request.resource.data.diff(resource.data).affectedKeys()
    .hasAny(['email', 'phoneNumber']);
}
```

- `allow create` now requires `hasNoPIIFields()` — new user docs cannot include email/phone
- `allow update` now requires `piuFieldsUnchanged()` — existing docs cannot add/change email/phone

These rules do **not** prevent Cloud Functions (Admin SDK) from writing these fields during the
migration phase — Admin SDK bypasses Security Rules entirely. This allows the migration CF to
read the current values, copy them to the locked subcollection, and then strip them from the root doc.

---

## Target State (After Migration)

PII fields live exclusively in `/users/{uid}/private/pii` — a server-only subcollection:

```
/users/{uid}/private/pii
  {
    email: "user@example.com",
    phoneNumber: "+15555550100",
    migratedAt: <timestamp>,
    migratedBy: "piiMigrationV1"
  }
```

The subcollection rule `match /private/{docId} { allow read, write: if false; }` ensures
**no client** (not even the user themselves) can read this document. All access is via Admin SDK
in Cloud Functions only.

---

## Migration Steps

### Step 1: Deploy the piiMigrationV1 Cloud Function

Create a new callable/HTTP function `piiMigrationV1` that:

1. Queries all `/users` documents where `email != null || phoneNumber != null`.
2. For each matching doc:
   a. Read the current `email` and `phoneNumber` values.
   b. Write `{ email, phoneNumber, migratedAt, migratedBy: 'piiMigrationV1' }` to
      `/users/{uid}/private/pii` using Admin SDK `set({ merge: true })`.
   c. Strip `email` and `phoneNumber` from the root doc using `update({ email: FieldValue.delete(), phoneNumber: FieldValue.delete() })`.
3. Log each migration with the uid (no PII in logs) to `migratedUserCount` metric.
4. Run in batches of 250 documents with a 100ms delay between batches to avoid Firestore write quota limits.

### Step 2: Update contactLookupByPhone Cloud Function

The `DiscoveryService.loadContactSuggestions` feature currently queries the root `/users`
collection by `phoneNumber`. After migration:

1. Implement (or enable) the `contactLookupByPhone` Cloud Function stub.
2. The function reads `/users/{uid}/private/pii` docs server-side (Admin SDK), matches hashed
   phone numbers, and returns only the safe public profile fields (uid, displayName, photoURL).
3. Update `DiscoveryService.swift` to call this function instead of querying Firestore directly.
4. Remove the `phoneNumber` index from the Firestore console after migration is verified.

### Step 3: Update UserService.updateUserEmail

1. In `UserService.swift`, change `updateUserEmail` to call a new `updateUserEmail` Cloud Function
   callable instead of writing directly to the root doc.
2. The callable writes the email to `/users/{uid}/private/pii` using Admin SDK.
3. Also updates Firebase Auth's email record (already server-side via Admin SDK).

### Step 4: Verify and Monitor

After the migration CF runs:

1. Query the root `/users` collection for any docs where `email != null` or `phoneNumber != null`.
   The count should be 0.
2. Verify `/users/{uid}/private/pii` exists for all users who previously had email/phone set.
3. Run the Firestore rules test suite (`npm test` in `rules-tests/`) — the deny tests for email/
   phoneNumber writes must continue to pass.
4. Monitor `UserService` and `DiscoveryService` error rates for 48 hours post-migration.

### Step 5: Remove Firestore Indexes (post-migration)

After Step 4 is confirmed clean:
- Remove the `phoneNumber` composite index (if any) from Firestore console.
- Remove the `email` index (if any).

---

## Rollback Plan

If the migration must be rolled back:

1. The rules guards (`hasNoPIIFields` / `piuFieldsUnchanged`) are backward-compatible — they do
   not break existing users who still have email on the root doc (those docs were written before
   the guard was deployed).
2. Restore email/phoneNumber from `/users/{uid}/private/pii` back to the root doc by running the
   inverse migration function.
3. Note: once email is removed from the root doc, any client-side Firestore queries filtering by
   `email` will return empty results. Check for such queries before running the migration.

---

## Acceptance Criteria

- [ ] `piiMigrationV1` CF deployed and run against production
- [ ] Zero `/users` root docs contain `email` or `phoneNumber` fields
- [ ] `/users/{uid}/private/pii` populated for all affected users
- [ ] `contactLookupByPhone` CF live and `DiscoveryService` updated
- [ ] `UserService.updateUserEmail` calls CF instead of direct Firestore write
- [ ] Firestore rules test suite passing (all DENY tests for email/phone hold)
- [ ] No new alerts from `UserService` or `DiscoveryService` for 48 hours post-migration
