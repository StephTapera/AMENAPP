# Agent A — Data, Security Rules & Entitlements (FOUNDATION, MERGES FIRST)

> Read `00_MASTER_CONTRACT.md` fully before starting. You define the schema everyone else
> builds on. Get this right; everyone is blocked on you. Project root:
> `~/Desktop/AMEN/AMENAPP copy/`, workspace `AMENAPP.xcworkspace`. Backend is Firebase
> (Firestore, RTDB, Cloud Functions, Storage, Auth), Stripe via Connect.

## Your mandate

### Step 1 — AUDIT FIRST (produce a gap report before changing anything)

Inventory what already exists:
- **Firestore models**: look in `AMENAPP/`, `AMENAPP/AMENAPP/`, `functions/` for any
  existing `community`, `space`, `channel`, `group`, `entitlement`, `membership` models.
  Check Swift files (`*Models.swift`, `*Service.swift`) and Cloud Function index files.
- **Security rules**: read `firestore.rules` in the project root. Map every collection
  that already exists vs. the Master Contract schema.
- **Stripe integration**: find the existing Stripe Connect wiring, fee math, and any
  subscription webhook handler.
- **Cloud Functions**: scan `functions/` for any `grantAccess`, entitlement, or
  subscription-lifecycle functions.

Produce a gap report listing: what exists and can be reused, what needs to be added,
what conflicts with the Master Contract and must be reconciled.

### Step 2 — Implement the schema

Implement or extend the following Firestore collections per the Master Contract §2:

```
communities/{communityId}
  name: string
  handle: string
  avatarURL: string?
  ownerUserId: string
  stripeConnectAccountId: string?
  createdAt: Timestamp

  members/{userId}
    role: "owner" | "admin" | "member"
    joinedAt: Timestamp

  links/{linkId}
    otherCommunityId: string
    status: "pending" | "active" | "revoked"
    scope: string          // description of what is shared
    createdBy: string      // userId
    createdAt: Timestamp
    updatedAt: Timestamp

spaces/{spaceId}
  communityId: string      // denormalized parent
  type: "chat" | "bibleStudy" | "group" | "announcement"
  title: string
  description: string?
  avatarURL: string?
  createdBy: string
  createdAt: Timestamp
  accessPolicy: "free" | "oneTime" | "recurring"
  priceConfig: { amountCents: number, currency: string, interval?: string } | null
  sharedWith: [string]     // communityIds — denormalized for badge/banner render

  members/{userId}
    role: "owner" | "admin" | "member"
    homeCommunityId: string   // "" means same community as Space
    access: "granted" | "none"
    joinedAt: Timestamp

  threads/{threadId}
    title: string?
    createdBy: string
    createdAt: Timestamp
    lastMessageAt: Timestamp

    messages/{messageId}
      authorId: string
      body: string
      createdAt: Timestamp
      editedAt: Timestamp?
      reactions: map<string, [string]>   // emoji → [userId]
      attachments: [{ type, url, metadata }]
      status: "active" | "deleted"       // NEVER hard-delete

  studies/{studyId}
    title: string
    passageRefs: [string]
    cadence: string?
    createdBy: string
    createdAt: Timestamp

    blocks/{blockId}       // reuse Smart Church Notes block model exactly

entitlements/{userId}_{spaceId}    // FLAT TOP-LEVEL — one get() for the gate
  userId: string
  spaceId: string
  status: "active" | "grace" | "expired"
  source: "purchase" | "grant"
  stripeSubId: string?
  expiresAt: Timestamp?    // null = lifetime
  updatedAt: Timestamp
```

**Critical**: entitlements MUST be the flat top-level collection. Do not nest them.

### Step 3 — Security rules

Write `firestore.rules` additions that enforce:

1. **Free Space**: any authenticated user can read threads/messages in a free Space
   (`accessPolicy == "free"`).
2. **Paid Space — no entitlement**: deny read of threads/messages/studies.
3. **Paid Space — active entitlement**: `get(/entitlements/$(uid)_$(spaceId)).data.status == "active"` → allow.
4. **Paid Space — grace entitlement**: allow read (grace = still paying, brief window).
5. **Paid Space — expired entitlement**: deny read.
6. **External member via active link**: a user whose `homeCommunityId` is in `space.sharedWith`
   AND whose home community has an `active` link to the Space's owning community → allow.
7. **External member via revoked link**: deny.
8. **Admin/owner bypass**: community owners and admins can always read/write their own
   community's Spaces.
9. **Entitlement writes**: only Cloud Functions (admin SDK) or authenticated user writing
   their own entitlement as a purchase. Prevent arbitrary client entitlement writes.

### Step 4 — Cloud Functions

Add to `functions/` (TypeScript, reuse existing Firebase Admin + Stripe setup):

#### `grantSpaceAccess`
```typescript
// Callable: { userId, spaceId, source: "grant", expiresAt?: Timestamp }
// Sets entitlements/{userId}_{spaceId} with status: "active", source: "grant"
// Admin/owner only — validate caller role from communities.members
```

#### `handleStripeWebhook` (extend existing or create)
```typescript
// On customer.subscription.deleted or invoice.payment_failed:
//   active → grace (give 3-day window)
// On invoice.payment_failed after grace period:
//   grace → expired
// On invoice.payment_succeeded:
//   any status → active
// NEVER delete the entitlement row.
```

#### `revokeSpaceLinkAccess`
```typescript
// Called when a community link is revoked.
// For each user with homeCommunityId == revokedCommunityId in the Space's members:
//   set their space member access: "none"
// Do NOT delete member rows.
```

### Step 5 — Firestore indexes

Add any composite indexes needed for:
- `spaces` where `communityId == X` ordered by `createdAt`
- `spaces/members` where `homeCommunityId == X`
- `entitlements` where `userId == X` and `status == active`
- `communities/links` where `otherCommunityId == X` and `status == active`

### Step 6 — Rules tests

Write rules tests (`.test` files or the existing test framework in the project) covering
all 7 scenarios in Step 3 above. They must be green before you publish CONTRACT_A.md.

---

## Hard constraints

- Entitlements are flat/top-level and Space-scoped (whole Space). One row per `{user,space}`.
- No hard-deletes of data a client may render. Status flips only.
- Reuse existing Stripe fee math and existing Connect account fields — do not invent a
  parallel billing model. Money never crosses a community Link (v1).
- Keep `spaces.sharedWith` and `member.homeCommunityId` denormalized so badges/banners/
  roster render with no joins.
- Do not rename existing Firestore collections that are in production. Add alongside.

---

## Deliverables

1. Swift model files:
   - `AMENAPP/AMENAPP/Spaces/SpacesModels.swift` — Community, Space, Thread, Message, Study, Block, Entitlement structs
   - `AMENAPP/AMENAPP/Spaces/SpacesService.swift` — Firestore CRUD + listeners (async/await, no Combine)
2. Updated `firestore.rules` — additive only, do not break existing rules
3. Updated `firestore.indexes.json` — new composite indexes
4. `functions/src/spaces/grantSpaceAccess.ts`
5. `functions/src/spaces/stripeWebhookEntitlement.ts` (extend existing webhook if present)
6. `functions/src/spaces/revokeSpaceLinkAccess.ts`
7. **`spaces-spec/CONTRACT_A.md`** — exact collection paths, field types, function
   signatures, and the security rule pattern. This is what B–F code against.

---

## Done when

- `SpacesModels.swift` and `SpacesService.swift` build with zero diagnostics in Xcode.
- `firestore.rules` is valid and rules tests for all 7 scenarios are green.
- `CONTRACT_A.md` is published in `spaces-spec/`.
- Signal: write "AGENT_A_COMPLETE" as the last line of `CONTRACT_A.md`.
