# Wave 0 — Firestore Rules Skeleton (§4.3)

> **PENDING HUMAN FREEZE — not yet written into `firestore.rules`.** Each block is
> anchored to an existing pattern + line number in the canonical root
> `firestore.rules`. Prayer-journal and the encrypted memory blocks are 🔒 BLOCKED
> on the E2EE / PRIV-005 decisions and must not ship before they land.

## Collections → rule blocks

| Collection (final name) | Rec | Anchor pattern (existing) | ACL shape |
|---|---|---|---|
| `users/{uid}/voiceSessions/{sessionId}` | BUILD-NEW | `users/{uid}/mediaSessions` (~line 638) | owner-read; CF admin-write only |
| `users/{uid}/voicePrayerJournal/{entryId}` 🔒 | BUILD-NEW ⚠️ | existing `prayerJournal` (lines 2476/2806) — **collision, renamed** | owner-read; **CF-write-only**; `ownerUidEncrypted` (I-6); encrypted-at-rest |
| `users/{uid}/formationMemory/{docId}` | BUILD-NEW | `berean/{uid}/memory` (~line 2554) + `memoryGraph` (~2047) | owner-read; CF admin-write; user-exportable + deletable |
| `users/{uid}/bereanStudyProjects/{projectId}` | EXTEND | global `/bereanProjects` (~1908) — user-scope is new | owner read/write own studies |
| `users/{uid}/sermonCaptures/{captureId}` | EXTEND | `users/{uid}/sermonSessions` (~3307) + `churchNotes` (~1364) | CF-job-owned transcripts/OCR; soft-delete only (I-1); owner + church-member read |
| `users/{uid}/groupSessions/{sessionId}` | BUILD-NEW | org/space member ACL (~1060/1143) | owner + space/org-member read; CF admin-write; honor minor/guardian gating (OPEN-2) |
| `orgs/{orgId}/organizationalMemory/{docId}` | BUILD-NEW | org member ACL (~1060) | org-member read; leadership+ CF write |

## ⚠️ `prayerJournal` naming collision (must resolve before any rule lands)

`users/{uid}/prayerJournal` **already exists** in two senses:
- a **consent permission key** (line ~2476), and
- an **owner read/write** action-sheet object collection (line ~2806, GAP A4-P1).

The proposed encrypted, CF-write-only, `ownerUidEncrypted` journal **contradicts**
the existing owner-writable rule. Overloading the path breaks the existing
collection. **Decision required:** adopt `voicePrayerJournal` (recommended) or
reconcile the two ACL models. Also: `config/voice` (line ~2598) currently allows
any signed-in read — if it starts holding per-user voice settings, tighten to
owner-only or move to `users/{uid}/voiceSettings`.

## Proposed `match` blocks (illustrative — not final)

```
// reuse mediaSessions shape
match /users/{userId}/voiceSessions/{sessionId} {
  allow read: if isOwner(userId);
  allow write: if false;            // CF admin SDK only
}

// RENAMED to avoid collision; 🔒 BLOCKED on E2EE-account-recovery decision
match /users/{userId}/voicePrayerJournal/{entryId} {
  allow read: if isOwner(userId);   // ciphertext only; ownerUidEncrypted never client-readable (I-6)
  allow create, update, delete: if false;  // CF-write-only; honor full delete server-side
}

match /users/{userId}/formationMemory/{docId} {
  allow read: if isOwner(userId);   // user-exportable + deletable
  allow write: if false;            // CF admin SDK
}

match /users/{userId}/bereanStudyProjects/{projectId} {
  allow read, write: if isOwner(userId);
}

match /users/{userId}/sermonCaptures/{captureId} {
  allow read: if isOwner(userId) || isChurchMemberOf(userId);
  allow write: if false;            // CF transcription/OCR job; soft-delete only (I-1)
}

match /users/{userId}/groupSessions/{sessionId} {
  allow read: if isOwner(userId) || isSpaceOrOrgMember(resource.data.scopeId);
  allow write: if false;            // honor isMinorSafeDM / guardian gating (OPEN-2)
}

match /orgs/{orgId}/organizationalMemory/{docId} {
  allow read: if isOrgMember(orgId);
  allow write: if false;            // leadership+ via CF callable
}
```

> Helper names (`isOwner`, `isChurchMemberOf`, `isSpaceOrOrgMember`, `isOrgMember`,
> `isMinorSafeDM`) are placeholders — Wave 1 must bind them to the **real** helpers
> in `firestore.rules` (e.g. `sameOrg()`, `hasRole()`, `allAttachmentsPrayerSafe()`).

## Cross-cutting rule risks (from recon)

- `allAttachmentsPrayerSafe()` (~line 386) only covers post attachments today — if
  voice records allow attachments, replicate the anonymous-author-leak guard.
- Public prayer reads (§2c, ~line 816) vs encrypted owner-only journal: keep the
  two collections cleanly separated to avoid a parity gap.
- OPEN-3 (anonymous prayer shielding): if voice prayer carries audio blobs, the CF
  must mask speaker identity before any privileged read.
