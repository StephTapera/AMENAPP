# CONTRACT_A.md — Spaces v2 Data Layer
> Agent A deliverables. All downstream agents (B, C, D, E, F) build against this contract.
> Do not redefine any type listed here.

---

## Swift Type Locations

| Type | File | Notes |
|------|------|-------|
| `CommunityRole` | `AMENAPP/Spaces/SpacesCommunityModels.swift` | enum: owner, admin, member |
| `CommunityLinkStatus` | `AMENAPP/Spaces/SpacesCommunityModels.swift` | enum: pending, active, revoked |
| `CommunityLink` | `AMENAPP/Spaces/SpacesCommunityModels.swift` | Codable, Identifiable |
| `AmenCommunity` | `AMENAPP/Spaces/SpacesCommunityModels.swift` | Codable, Identifiable, @DocumentID |
| `AmenCommunityMember` | `AMENAPP/Spaces/SpacesCommunityModels.swift` | Codable |
| `SpaceV2Type` | `AMENAPP/Spaces/SpacesCommunityModels.swift` | enum: chat, bibleStudy, group, announcement |
| `AccessPolicy` | `AMENAPP/Spaces/SpacesCommunityModels.swift` | enum: free, oneTime, recurring |
| `PriceConfig` | `AMENAPP/Spaces/SpacesCommunityModels.swift` | Codable |
| `AmenSpaceExtended` | `AMENAPP/Spaces/SpacesCommunityModels.swift` | Codable, Identifiable — NEW canonical Space model for v2 |
| `SpaceMemberAccess` | `AMENAPP/Spaces/SpacesCommunityModels.swift` | enum: granted, none |
| `SpaceMember` | `AMENAPP/Spaces/SpacesCommunityModels.swift` | Codable, Identifiable |
| `EntitlementStatus` | `AMENAPP/Spaces/SpacesEntitlementModels.swift` | enum: active, grace, expired |
| `EntitlementSource` | `AMENAPP/Spaces/SpacesEntitlementModels.swift` | enum: purchase, grant |
| `SpaceEntitlement` | `AMENAPP/Spaces/SpacesEntitlementModels.swift` | Codable, Identifiable |
| `EntitlementService` | `AMENAPP/Spaces/SpacesEntitlementModels.swift` | @MainActor, ObservableObject, singleton |
| `SpaceBodyRenderer` | `AMENAPP/Spaces/SpacesCore.swift` | protocol — `static var renderedType: SpaceV2Type` |

---

## IMPORTANT: SpaceType naming

`SpaceV2Type` (not `SpaceType`) is the v2 enum. `SpaceType` in SpacesCore.swift is a
typealias for `AmenSpaceType` (Phase 0 multi-purpose type). Use `SpaceV2Type` everywhere
in Spaces v2 surfaces. `SpaceBodyRenderer.renderedType` is of type `SpaceV2Type`.

---

## EntitlementService Method Signatures

```swift
// Agents B, C, D, E, F call these — do not redefine or wrap.

// Single fetch (use for initial load or one-time gate checks):
func fetchEntitlement(userId: String, spaceId: String) async throws -> SpaceEntitlement?

// Live stream (use for paid-space lock/unlock UI):
func observeEntitlement(userId: String, spaceId: String) -> AsyncStream<SpaceEntitlement?>
```

Both are on `EntitlementService.shared` (singleton, `@MainActor`).

---

## Cloud Function Callable Names

All match their `SpacesCallable` enum raw values in `AMENAPP/Spaces/SpacesCore.swift`.

| Callable Name | SpacesCallable case | Owner | Description |
|---|---|---|---|
| `createCommunity` | `.createCommunity` | Agent A | Creates community + seeds owner member |
| `linkCommunity` | `.linkCommunity` | Agent F | Creates pending link in both communities |
| `acceptCommunityLink` | `.acceptCommunityLink` | Agent F | Activates link, fan-outs sharedWith |
| `revokeCommunityLink` | `.revokeCommunityLink` | Agent F | Revokes link, removes from sharedWith, sets external access="none" |
| `grantAccess` | `.grantAccess` | Agent E | Admin comp/grant — writes entitlement with source:"grant" |
| `revokeAccess` | `.revokeAccess` | Agent E | Sets entitlement status="expired" |
| `stripeWebhookEntitlementHandler` | `.stripeWebhookEntitlement` | Backend only | onRequest Stripe webhook, verifies Stripe-Signature |
| `purchaseSpaceAccess` | `.purchaseSpaceAccess` | Agent E | Not implemented by A — Agent E owns this CF |

TypeScript source: `Backend/functions/src/spaces/`

---

## Firestore Paths

### Entitlements (primary access gate)
```
entitlements/{userId}_{spaceId}
  userId: String
  spaceId: String
  status: "active" | "grace" | "expired"
  source: "purchase" | "grant"
  stripeSubId: String?        // null for grants
  expiresAt: Timestamp?       // null = lifetime
  updatedAt: Timestamp
```

Document ID format: `"\(userId)_\(spaceId)"` — construct with `SpaceEntitlement.id`.

### Communities
```
communities/{communityId}
  name, handle, avatarURL, ownerUserId, stripeConnectAccountId, createdAt
  members/{userId} → role: "owner"|"admin"|"member", joinedAt
  links/{linkId}   → otherCommunityId, status, scope, createdBy, createdAt, updatedAt
```

### Spaces (v2 fields)
```
spaces/{spaceId}
  communityId: String          // owning community — drives money routing
  type: "chat"|"bibleStudy"|"group"|"announcement"
  title, description, avatarURL, createdBy, createdAt
  accessPolicy: "free"|"oneTime"|"recurring"  // drives access decision
  priceConfig: { amountCents, currency, interval? }?
  sharedWith: [communityId]    // denormalized — never join per-frame
  isDeleted: Bool              // soft-delete only
  members/{userId} → role, homeCommunityId?, access: "granted"|"none", joinedAt
  threads/{threadId}/messages/{messageId}
  studies/{studyId}/blocks/{blockId}
```

---

## Fields That Drive Access Decisions

| Field | Location | Decision |
|---|---|---|
| `accessPolicy` | `spaces/{spaceId}` | "free" → check member.access=="granted"; "oneTime"/"recurring" → check entitlement |
| `status` | `entitlements/{uid}_{spaceId}` | "active" or "grace" = read access; "expired" = locked |
| `access` | `spaces/{spaceId}/members/{userId}` | "granted" = admitted to free space; "none" = revoked (link broken) |
| `homeCommunityId` | `spaces/{spaceId}/members/{userId}` | nil = owning community member; set = external/linked member |
| `isDeleted` | `spaces/{spaceId}` | true = soft-deleted, never hard-delete |

---

## Design Tokens Added

In `AMENAPP/AMENAPP/AmenTheme.swift`:
- `AmenTheme.Colors.amenPurple` = `Color(red: 0.44, green: 0.26, blue: 0.80)` — use for LinkedGlyph (Agent C)
- `AmenTheme.Colors.amenBlack` = `Color(red: 0.06, green: 0.06, blue: 0.07)` — use for deep backgrounds
- `AmenTheme.Colors.amenBlue` was already present (not duplicated)

---

## SpacesCallable Additions (SpacesCore.swift)

Added to the existing `SpacesCallable` enum (Phase 0 cases preserved):
```swift
case createCommunity
case linkCommunity
case acceptCommunityLink
case revokeCommunityLink
case purchaseSpaceAccess
case grantAccess
case revokeAccess
case stripeWebhookEntitlement
```

---

## Firestore Rules Added

Appended to `firestore.rules` (existing rules untouched):
- Helper functions: `isCommunityOwner`, `isCommunityAdmin`, `isSpaceAdminOrOwner`, `hasActiveEntitlement`, `canReadSpaceV2`, `canWriteSpaceV2`
- `communities/{communityId}/members/{userId}` — signed-in read; admin or self write
- `communities/{communityId}/links/{linkId}` — admin-only read; CF-only write
- `entitlements/{entitlementId}` — owner or space admin read; CF-only write
- `spaces/{spaceId}/threads/{threadId}/messages/{messageId}` — entitlement-gated read/write; soft-delete only
- `spaces/{spaceId}/studies/{studyId}/blocks/{blockId}` — entitlement-gated read; admin-only write

---

## Handoff

**What changed:** 2 new Swift model files, 3 TypeScript CF files, 8 new SpacesCallable cases, 1 new protocol, 2 new color tokens (amenPurple + amenBlack), ~70 lines appended to firestore.rules.

**Contract exposed:** `EntitlementService.shared.fetchEntitlement` + `observeEntitlement` are the single access-check seam; `AmenSpaceExtended` is the canonical v2 Space model; `SpaceV2Type` drives `SpaceBodyRenderer`; entitlement doc ID = `"\(userId)_\(spaceId)"`.

**Assumptions made:** (1) `SpaceType` typealias conflict resolved by naming the v2 enum `SpaceV2Type` — `SpaceBodyRenderer.renderedType` uses this. (2) `amenBlue` already existed in AmenTheme with a slightly different value (0.04, 0.52, 1.0) — not duplicated per mandate; only `amenPurple` and `amenBlack` were added. (3) The legacy `/communities/{communityId}` top-level rule block is preserved; Spaces v2 subcollection rules are appended as separate flat `match` blocks targeting the new subcollections directly.
