# Profile Header v2 — Cloud Functions

Four Gen2 onCall callables (plus one scheduled function) that power the Profile Header v2 feature on AMEN.

All callables require the caller to be authenticated (`request.auth` non-null).

---

## 1. `getProfileHeaderPayload`

**Purpose:** Returns the full Profile Header v2 payload for a given user. Public callable — any signed-in user may fetch any other user's profile.

### Request

```typescript
{
  userId: string,   // required, non-empty — the profile owner's UID
  viewerId: string  // the calling user's UID (informational; auth uid is used for security)
}
```

### Response

```typescript
{
  userId: string,
  links: Array<{
    id: string,
    type: string,     // e.g. "instagram", "website", "youtube"
    url: string,
    label: string,
    order: number
  }>,
  pinSlotIds: string[],    // max 3 post IDs
  roleFlags: {
    isMentor: boolean,
    isCreator: boolean,
    isMinistryLeader: boolean,
    isChurchAccount: boolean,
    churchId: string | null
  },
  profileMetrics: {
    peopleDiscipled: number,
    versesShared: number,
    yearsWalkingWithChrist: number | null,
    testimoniesGiven: number,
    prayersOffered: number
  },
  bereanAboutOptIn: boolean,
  hasGivingEnabled: boolean,        // true if Stripe Connect payoutsEnabled OR church has giving link
  hasSubscriptionEnabled: boolean,  // true if isCreator === true AND postsCount > 0
  visitChurchURL: string | null     // websiteUrl from churches/{churchId} if set
}
```

### Error Codes

| Code | Meaning |
|------|---------|
| `unauthenticated` | Caller is not signed in |
| `invalid-argument` | `userId` is missing or empty |
| `not-found` | User document does not exist |
| `internal` | Unexpected Firestore failure |

---

## 2. `updatePinSlots`

**Purpose:** Sets the calling user's pinned post slots. Owner-only — the caller may only pin their own posts.

### Request

```typescript
{
  postIds: string[]  // array of post IDs to pin; max length 3; pass [] to clear all pins
}
```

### Response

```typescript
{
  success: true,
  pinSlotIds: string[]  // the saved pin slot IDs (echo of request.postIds)
}
```

### Validation

- `postIds` must be an array of non-empty strings.
- Maximum 3 elements. Providing 4+ returns `invalid-argument`.
- Each post must exist in the `posts` collection.
- Each post's `authorId` must equal `request.auth.uid`. Any mismatch returns `permission-denied`.

### Error Codes

| Code | Meaning |
|------|---------|
| `unauthenticated` | Caller is not signed in |
| `invalid-argument` | `postIds` missing, not an array, too long, or contains invalid IDs |
| `permission-denied` | A post does not belong to the calling user |
| `not-found` | A post ID does not exist in `posts` |
| `internal` | Unexpected Firestore failure |

---

## 3. `inferUserRoles`

**Purpose:** Computes `profile.roleFlags` for a user by reading server-authoritative signals and writes the result to `users/{userId}`. Admin or owner only.

### Request

```typescript
{
  userId: string  // required, non-empty
}
```

### Response

```typescript
{
  success: true,
  roleFlags: {
    isMentor: boolean,
    isCreator: boolean,
    isMinistryLeader: boolean,
    isChurchAccount: boolean,
    churchId: string | null
  }
}
```

### Role Inference Logic

| Flag | Source |
|------|--------|
| `isMentor` | `mentorVerifications/{userId}.verified === true` |
| `isCreator` | `users/{userId}.postsCount > 0` |
| `isChurchAccount` | `churches` collection has a doc where `adminId === userId` |
| `isMinistryLeader` | `isChurchAccount === true` OR `users/{userId}.isMinistryLeader === true` |
| `churchId` | ID of the matching church document (or `null`) |

### Error Codes

| Code | Meaning |
|------|---------|
| `unauthenticated` | Caller is not signed in |
| `permission-denied` | Non-admin caller tried to infer a different user's roles |
| `invalid-argument` | `userId` is missing or empty |
| `not-found` | User document does not exist |
| `internal` | Unexpected Firestore failure |

### Scheduled Variant: `scheduledInferRoles`

Runs on a `"every 24 hours"` schedule. Pages through all users in batches of 100 and applies the same role inference logic. Failures on individual users are logged and skipped; the sweep continues.

---

## 4. `assembleBereanAboutContext`

**Purpose:** Assembles a structured context payload for Berean AI to answer questions about a user's public spiritual identity. Only available if the user has opted in (`profile.bereanAboutOptIn === true`).

### Privacy Contract

- Only fetches posts where `privacy === "public"` and `authorId === userId`.
- Pinned posts are filtered to public-only before inclusion.
- Never includes: DMs, private prayer requests, draft content, or any PII.
- Hard-blocks if `profile.bereanAboutOptIn` is not `true`.

### Request

```typescript
{
  userId: string,   // required, non-empty — the profile to assemble context for
  viewerId: string  // the requesting user's UID (informational)
}
```

### Response

```typescript
{
  displayName: string,
  bio: string | null,
  roleFlags: object,
  recentPublicPosts: Array<{
    id: string,
    content: string,
    type: string,
    createdAt: string   // ISO 8601
  }>,                   // last 10 public posts, newest first
  pinnedPosts: Array<{
    id: string,
    content: string,
    type: string
  }>,                   // up to 3, public-only
  churchInfo: {
    name: string,
    location: string
  } | null
}
```

### Error Codes

| Code | Meaning |
|------|---------|
| `unauthenticated` | Caller is not signed in |
| `invalid-argument` | `userId` is missing or empty |
| `not-found` | User document does not exist |
| `permission-denied` | `berean-opt-in-required` — user has not opted in to Berean About |
| `internal` | Unexpected Firestore failure |

---

## Firestore Fields

All new fields live under the `profile` map key in `users/{uid}`:

| Field | Type | Default | Client-writable |
|-------|------|---------|----------------|
| `profile.links` | `ProfileLink[]` | `[]` | Yes (owner) |
| `profile.pinSlots` | `string[]` | `[]` | Via `updatePinSlots` CF only |
| `profile.roleFlags` | `RoleFlags` | see defaults | No — CF only (`profile.roleFlags` is blocked in Firestore rules) |
| `profile.profileMetrics` | `ProfileMetrics` | see defaults | Yes (owner) |
| `profile.bereanAboutOptIn` | `boolean` | `false` | Yes (owner) |

---

## Migration

To backfill existing users with default values for all new fields:

```bash
# Dry run — preview which documents would be updated
node Backend/functions/scripts/migrate-profile-v2.js --dry-run

# Live run — write defaults to all users missing any profile.* field
GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json \
  node Backend/functions/scripts/migrate-profile-v2.js
```

The script is idempotent — it only writes fields that are absent, never overwrites existing data, and uses cursor-based pagination in pages of 500.
