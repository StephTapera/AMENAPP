# Security Rules Contract — Spiritual OS
## STATUS: FROZEN · Do not edit without Lead Orchestrator sign-off

These Firestore rules additions cover every new collection introduced by
the Spiritual OS build. They follow least-privilege: default DENY, explicit
ALLOW for owner/member scoped reads and writes. Space-role-aware for
Space collections.

Deploy ONLY via:
  `firebase deploy --only firestore:rules`
after Lead Orchestrator reviews the diff and gives explicit approval.

---

## Authoring Conventions

- `isSignedIn()` — `request.auth != null`
- `isOwner(uid)` — `request.auth.uid == uid`
- `isSpaceMember(spaceId)` — member doc exists in `spaces/{spaceId}/members/{request.auth.uid}`
- `isSpaceLeaderOrModerator(spaceId)` — member doc exists with role in `["leader", "moderator", "pastor"]`
- All new rules are ADDITIVE — existing rules remain unchanged.

---

## Rules to Add

```javascript
// ─── Spiritual OS Rules ───────────────────────────────────────────────────

// Helper functions (add to rules functions block)
function isSignedIn() {
  return request.auth != null;
}
function isOwner(uid) {
  return isSignedIn() && request.auth.uid == uid;
}
function isSpaceMember(spaceId) {
  return isSignedIn() &&
    exists(/databases/$(database)/documents/spaces/$(spaceId)/members/$(request.auth.uid));
}
function isSpaceLeaderOrModerator(spaceId) {
  return isSignedIn() &&
    get(/databases/$(database)/documents/spaces/$(spaceId)/members/$(request.auth.uid)).data.role
      in ["leader", "moderator", "pastor"];
}

// ── Daily Digest ─────────────────────────────────────────────────────────
match /users/{uid}/dailyDigest/{date} {
  // Owner-only: read and server-write (CF writes via admin SDK, bypasses rules)
  allow read: if isOwner(uid);
  allow write: if false;  // CF admin SDK only
}

// ── Hub Items ─────────────────────────────────────────────────────────────
match /users/{uid}/hubItems/{itemId} {
  allow read: if isOwner(uid);
  // Client may mark read/archive/pin via CF only
  // Direct writes allowed only for read/pin state fields
  allow update: if isOwner(uid) &&
    request.resource.data.diff(resource.data).affectedKeys()
      .hasOnly(["readAt", "archivedAt", "pinnedAt"]);
  allow create, delete: if false;  // CF fan-out only
}

// ── Life Planner Events ───────────────────────────────────────────────────
match /users/{uid}/lifePlannerEvents/{eventId} {
  allow read: if isOwner(uid);
  // User can create/update personal events; mirrored events are CF-written
  allow create: if isOwner(uid) &&
    request.resource.data.source == "personal" &&
    request.resource.data.uid == uid;
  allow update: if isOwner(uid) &&
    // Cannot change source-of-truth fields for mirrored events
    (resource.data.source == "personal" ||
     request.resource.data.diff(resource.data).affectedKeys()
       .hasOnly(["isCompleted", "completedAt", "bereanSuggestionDismissed", "notes"]));
  allow delete: if isOwner(uid) && resource.data.source == "personal";
}

// ── Context State ─────────────────────────────────────────────────────────
match /users/{uid}/contextState {
  allow read: if isOwner(uid);
  // Context Engine CF writes via admin SDK. Client may update consent flags only.
  allow update: if isOwner(uid) &&
    request.resource.data.diff(resource.data).affectedKeys()
      .hasOnly(["locationConsentGranted", "motionConsentGranted", "calendarConsentGranted"]);
  allow create, delete: if false;
}

// ── Command Center ────────────────────────────────────────────────────────
match /users/{uid}/commandCenter {
  allow read: if isOwner(uid);
  // User may toggle streak opt-in only
  allow update: if isOwner(uid) &&
    request.resource.data.diff(resource.data).affectedKeys()
      .hasOnly(["streakOptIn"]);
  allow create, delete: if false;  // Scheduled CF only
}

// ── Suggestions ───────────────────────────────────────────────────────────
match /suggestions/{uid} {
  allow read: if isOwner(uid);
  allow write: if false;  // CF only
}

// ── Spaces ────────────────────────────────────────────────────────────────
match /spaces/{spaceId} {
  // Public spaces readable by anyone signed in
  allow read: if isSignedIn() &&
    (resource.data.privacy == "public" || isSpaceMember(spaceId));
  // Secret spaces: member-only read
  // (privacy == "secret" is implied by the read guard above)

  // Only CF createSpace callable creates Space docs
  allow create: if false;

  // Leader/moderator/pastor may update Space metadata
  allow update: if isSpaceLeaderOrModerator(spaceId) &&
    // Cannot change ownership or encryption settings post-create
    !request.resource.data.diff(resource.data).affectedKeys()
      .hasAny(["ownerId", "encryptionEnabled", "createdAt"]);

  allow delete: if false;  // Soft-delete via CF only
}

match /spaces/{spaceId}/members/{uid} {
  // Members can read the member list (for avatars, counts)
  allow read: if isSpaceMember(spaceId);

  // Writes via CF only (invite, remove, role change)
  allow create, update, delete: if false;
}

match /spaces/{spaceId}/events/{eventId} {
  allow read: if isSignedIn() &&
    (get(/databases/$(database)/documents/spaces/$(spaceId)).data.privacy == "public"
     || isSpaceMember(spaceId));

  // Leaders/moderators create events; members RSVP via CF
  allow create: if isSpaceLeaderOrModerator(spaceId);
  allow update: if isSpaceLeaderOrModerator(spaceId) ||
    // Members may only add themselves to rsvpUids
    (isSpaceMember(spaceId) &&
     request.resource.data.diff(resource.data).affectedKeys().hasOnly(["rsvpUids", "rsvpCount"]));
  allow delete: if isSpaceLeaderOrModerator(spaceId);
}

match /spaces/{spaceId}/prayerRequests/{requestId} {
  // Members can read; anonymous requests hide authorUid client-side
  // (CF strips authorUid before returning to non-leaders when isAnonymous == true)
  allow read: if isSpaceMember(spaceId);

  // Members post prayer requests; Aegis CF validates
  allow create: if isSpaceMember(spaceId) &&
    request.resource.data.authorUid == request.auth.uid &&
    request.resource.data.text.size() <= 2000;

  // Author may update their own; leaders may close/flag
  allow update: if
    (isOwner(resource.data.authorUid) &&
     request.resource.data.diff(resource.data).affectedKeys()
       .hasOnly(["text", "updatedAt"])) ||
    (isSpaceLeaderOrModerator(spaceId) &&
     request.resource.data.diff(resource.data).affectedKeys()
       .hasOnly(["isClosed", "closedAt", "aegisFlags"]));

  allow delete: if false;  // Soft-close only
}

match /spaces/{spaceId}/studySeries/{seriesId} {
  allow read: if isSpaceMember(spaceId);
  allow write: if isSpaceLeaderOrModerator(spaceId);
}
```

---

## Privacy Invariants to Verify Post-Deploy

| Invariant | Verification |
|---|---|
| `dailyDigest` never readable by other users | Read as user B for user A's UID → `permission-denied` |
| `contextState` contains no raw coordinates | Schema inspection + CF code review |
| Anonymous prayer requests: `authorUid` hidden from non-leaders | Read as non-leader member, verify CF strips field |
| `commandCenter.streakDays` never in public API responses | Read as another user → `permission-denied` |
| `hubItems` fan-out only writes allowed | Attempt direct client `create` → `permission-denied` |
| Encrypted Space members cannot be listed by non-members | Read member subcollection as non-member → `permission-denied` |
