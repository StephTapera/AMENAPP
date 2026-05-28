# CONTRACT_A.md — Agent A Public Interface

> Agents B–F: build against this document. Do NOT read Agent A's source files directly.
> If you discover a gap, raise it — do not invent a parallel schema.

---

## 1. Firestore Collection Paths

### 1.1 Communities

```
amenCommunities/{communityId}
  name: String
  handle: String
  avatarURL: String?
  ownerUserId: String           ← SERVER-OWNED
  stripeConnectAccountId: String?  ← SERVER-OWNED
  createdAt: Timestamp          ← SERVER-OWNED

  members/{userId}
    role: "owner" | "admin" | "member"
    joinedAt: Timestamp

  links/{linkId}
    otherCommunityId: String
    status: "pending" | "active" | "revoked"
    scope: String
    createdBy: String
    createdAt: Timestamp        ← SERVER-OWNED
    updatedAt: Timestamp        ← SERVER-OWNED
```

**IMPORTANT:** `amenCommunities` is a NEW top-level collection. The legacy `/communities` (Ark)
collection exists separately and is NOT the same schema. Never use `/communities` for Spaces data.
Always use `amenCommunities`.

### 1.2 Spaces

```
spaces/{spaceId}
  communityId: String           → amenCommunities/{communityId}
  type: "chat" | "bibleStudy" | "group" | "announcement"
  title: String
  description: String?
  avatarURL: String?
  createdBy: String             ← SERVER-OWNED
  createdAt: Timestamp          ← SERVER-OWNED
  accessPolicy: "free" | "oneTime" | "recurring"
  priceConfig: { amountCents: Int, currency: String, interval: String? }?
  sharedWith: [String]          // communityIds — denormalized, never join

  members/{userId}
    role: "owner" | "admin" | "member"
    homeCommunityId: String     // "" = same community; non-empty = external member
    access: "granted" | "none"
    joinedAt: Timestamp

  threads/{threadId}            // chat/group types
    spaceId: String
    title: String?
    createdBy: String
    createdAt: Timestamp
    lastMessageAt: Timestamp

    messages/{messageId}
      authorId: String
      body: String
      createdAt: Timestamp
      editedAt: Timestamp?
      reactions: { [emoji: String]: [userId: String] }
      attachments: [{ type: String, url: String, metadata: [String: String] }]
      status: "active" | "deleted"   ← NEVER hard-delete; use status flip

  studies/{studyId}             // bibleStudy type
    spaceId: String
    title: String
    passageRefs: [String]
    cadence: String?
    createdBy: String
    createdAt: Timestamp

    blocks/{blockId}            // reuses SCN block editor model
      type: "text"|"scripture"|"question"|"reflection"|"prayer"|"image"|"audio"|"heading"|"divider"
      content: String
      sortOrder: Int
      createdBy: String
      createdAt: Timestamp
      updatedAt: Timestamp
      scriptureRef: String?
      renderMode: String?
      metadata: [String: String]?
```

### 1.3 Entitlements (flat top-level — NEVER nested)

```
entitlements/{userId}_{spaceId}
  userId: String
  spaceId: String
  status: "active" | "grace" | "expired"
  source: "purchase" | "grant"
  stripeSubId: String?          ← SERVER-OWNED
  expiresAt: Timestamp?         // null = lifetime; set on grace/expiry
  updatedAt: Timestamp          ← SERVER-OWNED
```

**Key invariant:** Document ID is always `{userId}_{spaceId}` (underscore separator).
One row per `{user, space}` pair. Never delete — flip status only.

---

## 2. Swift Types (SpacesModels.swift)

| Type | Collection |
|---|---|
| `SpacesCommunity` | `amenCommunities/{communityId}` |
| `CommunityMember` | `amenCommunities/{communityId}/members/{userId}` |
| `CommunityLink` | `amenCommunities/{communityId}/links/{linkId}` |
| `AmenSpace` | `spaces/{spaceId}` |
| `SpaceMember` | `spaces/{spaceId}/members/{userId}` |
| `SpaceThread` | `spaces/{spaceId}/threads/{threadId}` |
| `SpaceMessage` | `spaces/{spaceId}/threads/{threadId}/messages/{messageId}` |
| `SpaceMessageAttachment` | embedded in `SpaceMessage` |
| `SpaceStudy` | `spaces/{spaceId}/studies/{studyId}` |
| `StudyBlock` | `spaces/{spaceId}/studies/{studyId}/blocks/{blockId}` |
| `SpaceEntitlement` | `entitlements/{userId}_{spaceId}` |
| `SpacePriceConfig` | embedded in `AmenSpace` |

All types are in `AMENAPP/AMENAPP/Spaces/SpacesModels.swift`.

### Key enum values

```swift
AmenSpace.SpaceType:  .chat | .bibleStudy | .group | .announcement
AmenSpace.AccessPolicy: .free | .oneTime | .recurring
SpaceMember.role:     .owner | .admin | .member
SpaceMember.access:   .granted | .none
CommunityRole:        .owner | .admin | .member
CommunityLink.LinkStatus: .pending | .active | .revoked
SpaceMessage.MessageStatus: .active | .deleted
SpaceEntitlement.EntitlementStatus: .active | .grace | .expired
SpaceEntitlement.EntitlementSource: .purchase | .grant
```

---

## 3. SpacesService API (SpacesService.swift)

File: `AMENAPP/AMENAPP/Spaces/SpacesService.swift`
Singleton: `SpacesService.shared`
All public methods are `async throws`. All UI mutation is `@MainActor`.

### Communities

```swift
func fetchCommunity(communityId: String) async throws -> SpacesCommunity
func fetchMyCommunities() async throws -> [SpacesCommunity]
func fetchCommunityMember(communityId: String, userId: String) async throws -> CommunityMember
func fetchCommunityMembers(communityId: String) async throws -> [CommunityMember]
func fetchActiveLinks(communityId: String) async throws -> [CommunityLink]
```

### Spaces

```swift
func fetchSpaces(communityId: String) async throws -> [AmenSpace]
func fetchSpace(spaceId: String) async throws -> AmenSpace
func spaceListener(spaceId:onUpdate:onError:) -> ListenerRegistration
func fetchMySpaceMembership(spaceId: String) async throws -> SpaceMember?
func fetchSpaceMembers(spaceId: String) async throws -> [SpaceMember]
func fetchExternalMembers(spaceId: String) async throws -> [SpaceMember]
```

### Threads

```swift
func fetchThreads(spaceId: String) async throws -> [SpaceThread]
func createThread(spaceId: String, title: String?) async throws -> String  // returns threadId
func threadsListener(spaceId:onUpdate:onError:) -> ListenerRegistration
```

### Messages

```swift
func fetchMessages(spaceId: String, threadId: String, limit: Int = 50) async throws -> [SpaceMessage]
func sendMessage(spaceId: String, threadId: String, body: String, attachments: [SpaceMessageAttachment]) async throws -> String
func deleteMessage(spaceId: String, threadId: String, messageId: String) async throws   // status flip only
func toggleReaction(spaceId: String, threadId: String, messageId: String, emoji: String) async throws
func messagesListener(spaceId:threadId:onUpdate:onError:) -> ListenerRegistration
```

### Studies

```swift
func fetchStudies(spaceId: String) async throws -> [SpaceStudy]
func createStudy(spaceId: String, title: String, passageRefs: [String], cadence: String?) async throws -> String
func fetchBlocks(spaceId: String, studyId: String) async throws -> [StudyBlock]
func upsertBlock(_ block: StudyBlock, spaceId: String, studyId: String) async throws
```

### Entitlements

```swift
func fetchEntitlement(spaceId: String) async throws -> SpaceEntitlement?
func entitlementListener(userId:spaceId:onUpdate:onError:) -> ListenerRegistration
func hasAccess(to space: AmenSpace) async throws -> Bool
func fetchMyActiveEntitlements() async throws -> [SpaceEntitlement]
```

---

## 4. Cloud Functions

### `grantSpaceAccess` (HTTPS Callable)
File: `functions/src/spaces/grantSpaceAccess.ts`

```typescript
// Request payload:
{
  userId: string,           // target user
  spaceId: string,          // which space
  source: "grant",          // must be literal "grant"
  expiresAt?: Timestamp | null  // null = lifetime
}

// Response:
{
  success: boolean,
  entitlementId: string,    // "{userId}_{spaceId}"
  userId: string,
  spaceId: string,
  status: "active"
}

// Authorization: caller must be amenCommunity admin/owner OR have admin custom claim
// Error: "permission-denied" if not authorized
// Error: "not-found" if space or user does not exist
// Error: "invalid-argument" if fields missing or source != "grant"
```

### `handleStripeSpaceWebhook` (HTTPS Endpoint)
File: `functions/src/spaces/stripeWebhookEntitlement.ts`

```
POST /handleStripeSpaceWebhook
Stripe-Signature: <sig>
Content-Type: application/json

Events handled:
  invoice.payment_succeeded    → any status → "active"
  customer.subscription.deleted → "active" → "grace" (3-day window)
  invoice.payment_failed        → "active" → "grace"  (3-day window)
  invoice.payment_failed (again, grace elapsed) → "grace" → "expired"

Stripe subscription/invoice metadata required:
  amenUserId:  Firebase UID
  amenSpaceId: Firestore spaceId

NEVER deletes entitlement row. Always status flip only.
```

### `revokeSpaceLinkAccess` (HTTPS Callable)
File: `functions/src/spaces/revokeSpaceLinkAccess.ts`

```typescript
// Request payload:
{
  spaceId: string,
  revokedCommunityId: string
}

// Response:
{
  success: boolean,
  revokedCount: number,
  spaceId: string,
  revokedCommunityId: string
}

// Side effects:
//   - Sets access="none" on all space members with homeCommunityId == revokedCommunityId
//   - Removes revokedCommunityId from space.sharedWith array
//   - Does NOT delete member rows
// Authorization: amenCommunity admin/owner or platform admin
```

---

## 5. Security Rules Pattern

### Entitlement gate (single get())

```
// In firestore.rules:
function hasActiveEntitlement(spaceId) {
  let ent = get(/databases/$(db)/documents/entitlements/$(request.auth.uid + "_" + spaceId));
  return ent.data.status == "active" || ent.data.status == "grace";
}
```

### 7-scenario read gate for paid content

```
function canReadSpaceContentFull(spaceId) {
  return canReadAmenSpaceContent(spaceId)    // free member access or paid entitlement
    || isExternalMemberWithActiveLink(spaceId)  // external + active link
    || isAmenSpaceAdmin(spaceId);           // admin/owner bypass
}
```

### Applied to:
- `spaces/{spaceId}/threads/{threadId}/messages/{messageId}`
- `spaces/{spaceId}/studies/{studyId}/blocks/{blockId}`

### Entitlement writes: client-blocked
```
match /entitlements/{entitlementId} {
  allow write: if false; // Cloud Function / Admin SDK only
}
```

---

## 6. Composite Indexes Added

| Collection | Fields | Notes |
|---|---|---|
| `spaces` | `communityId ASC, createdAt ASC` | Query spaces by community |
| `members` (collection group) | `homeCommunityId ASC, access ASC` | External member lookup |
| `entitlements` | `userId ASC, status ASC` | Active entitlements for user |
| `links` (collection group) | `otherCommunityId ASC, status ASC` | Cross-community link lookup |
| `threads` | `spaceId ASC, lastMessageAt DESC` | Threads ordered by activity |
| `messages` | `status ASC, createdAt ASC` | Non-deleted messages query |

---

## 7. Hard Boundaries (enforced by this layer)

1. **No hard-deletes of in-render data.** `SpaceMessage.status = .deleted` — never call
   `.delete()` on message docs. `SpaceEntitlement.status` flips to `.expired` — row is kept.
2. **Entitlement is Space-scoped.** One row per `{user, space}`. No per-artifact entitlements.
3. **Money never crosses a community Link (v1).** `sharedWith` grants access, not revenue.
4. **No "church" in field names or enums.** Use "community", "space", "member" everywhere.
5. **`amenCommunities` ≠ `/communities`.** Legacy Ark collection is untouched.
6. **Client cannot write entitlements.** `allow write: if false` — Cloud Function only.

---

## 8. Assumptions Made

1. `amenCommunities` is the new top-level collection for Spaces (avoids collision with legacy `/communities` Ark schema).
2. Cross-link check uses document ID pattern `{homeCommunityId}_{owningCommunityId}` for the link document. Agent F must use this pattern when creating links.
3. Stripe subscription and invoice metadata must include `amenUserId` and `amenSpaceId` for the webhook to route correctly. Agent E must set these when creating Stripe checkout sessions.
4. `SpacesService` uses `@MainActor` but listeners use `nonisolated` — callers are responsible for `Task { @MainActor in ... }` dispatch.
5. The existing `assertSpaceMember` / `assertSpaceAdmin` helpers in `spacesIntelligence/callable.ts` use `spaces/{spaceId}/members/{uid}` — compatible with the new `SpaceMember` schema (additive fields only).

---

AGENT_A_COMPLETE
