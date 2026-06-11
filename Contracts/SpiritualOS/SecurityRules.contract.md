# FROZEN - Security Rules Contract - Spiritual OS
> Version 1.1 - 2026-06-11 - Lead Orchestrator
> FROZEN. Additive rules only - never weaken existing rules.
> Deploy ONLY with explicit Lead approval after diff review:
>   firebase deploy --only firestore:rules

---

## Principle
All new collections follow least-privilege, owner-scoped access.
Context data is single-user, CF-written — never world-readable, never in analytics pipelines.

---

## Rules to ADD inside `match /databases/{database}/documents` block

```firestore
// ─── Spiritual OS ──────────────────────────────────────────────────────────────

// Daily Digest — CF writes, owner reads, only isRead client-writable
match /spiritualOS_digest/{userId}/items/{itemId} {
  allow read: if request.auth != null && request.auth.uid == userId;
  allow create: if false;
  allow update: if request.auth != null
    && request.auth.uid == userId
    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isRead'])
    && request.resource.data.isRead is bool;
  allow delete: if false;
}

// Unified Hub Inbox — CF writes, owner reads
// Client writes: isPinned, isRead, isArchived only
match /spiritualOS_hub/{userId}/items/{itemId} {
  allow read: if request.auth != null && request.auth.uid == userId;
  allow create: if false;
  allow update: if request.auth != null
    && request.auth.uid == userId
    && request.resource.data.diff(resource.data).affectedKeys()
        .hasOnly(['isPinned', 'isRead', 'isArchived']);
  allow delete: if false;
}

// Life Planner Events — owner full control EXCEPT bereanNote/isBereanNote (CF-only)
match /spiritualOS_planner/{userId}/events/{eventId} {
  allow read: if request.auth != null && request.auth.uid == userId;
  allow create: if request.auth != null
    && request.auth.uid == userId
    && !('isBereanNote' in request.resource.data)
    && !('bereanNote' in request.resource.data);
  allow update: if request.auth != null
    && request.auth.uid == userId
    && request.resource.data.diff(resource.data).affectedKeys()
        .hasOnly(['isCompleted', 'isDismissed', 'title', 'description',
                  'startDate', 'endDate', 'isAllDay', 'color']);
  allow delete: if request.auth != null && request.auth.uid == userId;
}

// Context State — single doc, owner read/delete only, CF writes
match /spiritualOS_context/{userId} {
  allow read, delete: if request.auth != null && request.auth.uid == userId;
  allow create, update: if false; // updateContextState CF only
}

// Berean Suggestions — CF writes, owner reads, client may dismiss
match /spiritualOS_suggestions/{userId}/items/{itemId} {
  allow read: if request.auth != null && request.auth.uid == userId;
  allow create: if false;
  allow update: if request.auth != null
    && request.auth.uid == userId
    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isDismissed']);
  allow delete: if false;
}

// Create Space Drafts - owner can manage drafts; submitted payload is validated by CF
match /spiritualOS_spaceCreateDrafts/{userId}/drafts/{draftId} {
  allow read: if request.auth != null && request.auth.uid == userId;
  allow create: if request.auth != null
    && request.auth.uid == userId
    && request.resource.data.userId == userId
    && request.resource.data.status in ['draft', 'submitted'];
  allow update: if request.auth != null
    && request.auth.uid == userId
    && request.resource.data.userId == userId
    && request.resource.data.status in ['draft', 'submitted', 'discarded']
    && request.resource.data.diff(resource.data).affectedKeys()
        .hasOnly(['name', 'description', 'coverImageURL', 'privacy', 'memberRoles',
                  'featureToggles', 'moderation', 'encryptedPrayer', 'bereanMember',
                  'status', 'updatedAt', 'aegisFlags']);
  allow delete: if request.auth != null
    && request.auth.uid == userId
    && resource.data.status in ['draft', 'discarded'];
}

// Command Center Aggregates - CF writes, owner reads, client may dismiss cards
match /spiritualOS_commandCenter/{userId}/aggregates/{aggregateId} {
  allow read: if request.auth != null && request.auth.uid == userId;
  allow create: if false;
  allow update: if request.auth != null
    && request.auth.uid == userId
    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isDismissed']);
  allow delete: if false;
}

// Spaces Dashboard Extension fields
// No new client write permissions for heroCardEnabled, activePrayerCount,
// currentStudySeries, dashboardUpdatedAt, bereanMemberId, encryptedPrayerWall.
// These are CF-written and readable to existing space members under existing rules.
// Existing spaces rules are NOT replaced — only the above note applies.
```

---

## Aegis Integration Note
Documents with non-empty `aegisFlags` are application-layer protected via `AmenConnectSpacesAegisService`.
Firestore rules do not enforce Aegis semantics directly, but no Aegis-flagged field is client-writable.

---

## Context Data Privacy Rationale
`spiritualOS_context` is CF-write-only because:
- Location-derived state (isNearChurch, mode) must be validated server-side to prevent spoofing
- Prevents compromised client from injecting false context to manipulate AI outputs
- Audit trail in Aegis, not embedded in the document

---

## Pre-Deploy Checklist (Lead must verify before running deploy)
- [ ] Full rules file syntax-checked in Firebase emulator
- [ ] No existing rules weakened or removed
- [ ] Each new collection block tested with emulator rules unit tests
- [ ] Context collection verified as non-exportable in privacy manifest
- [ ] Diff reviewed and explicitly approved by Lead before running deploy command
