# Agent A — Audit Report (AUDIT_A.md)
Generated: 2026-05-28

---

## 1. Existing Schema vs. Master Contract

### 1.1 `spaces/{spaceId}` — PARTIALLY EXISTS (conflict/extension needed)

**What exists:**
The `spaces` collection is already used by the `spacesIntelligence` module (callable.ts, semanticPinningEngine.ts, etc.). The existing `spaces` documents have sub-collections:
- `members/{uid}` (role, used in `assertSpaceMember`)
- `rooms/{roomId}/messages/{messageId}` (Covenant OS Phase 0)
- `smartThreads/{threadId}/messages|insights|entities|studySessions`
- `ambientSignals`, `knowledgeGraph`, `semanticIndex`, `prayerRequests`, `events`, `presence`, `roles`, `intelligence`, `safetyEvents`, `relationshipGraph`, `banners`, `knowledgeNodes`, `theologyDoc`

**What the Master Contract adds:**
Fields: `communityId`, `type`, `title`, `description`, `avatarURL`, `createdBy`, `createdAt`, `accessPolicy`, `priceConfig`, `sharedWith` — **none of these are written by existing code** (intelligence modules only care about `spaceId` as a key, not the document fields).

Sub-collections added by Spaces: `threads/{threadId}/messages/{messageId}` (typed differently from `rooms`), `studies/{studyId}/blocks/{blockId}`.

**Resolution:** The existing `spaces` rules block client writes (`allow create, update, delete: if false`). The new Spaces rules layer ADDS admin-gated creation and member-scoped reads with the entitlement gate. No conflict with existing field set.

### 1.2 `communities/{communityId}` — EXISTS BUT IS THE LEGACY "ARK" COLLECTION

**What exists:**
`/communities/{communityId}` rules exist (line 929–979 of firestore.rules) but use fields `adminUids`, `memberCount`, `postCount`, `rankingScore`, `safetyStatus`, `moderationStatus`, `isOfficial`, `isArchived`, `isDeleted`, `creatorId`, `createdAt`, `visibility`. This is the **legacy Ark communities** schema.

**Master Contract schema:** `name`, `handle`, `avatarURL`, `ownerUserId`, `stripeConnectAccountId`, `createdAt` plus `members/{userId}` and `links/{linkId}` sub-collections.

**Resolution:** The Master Contract says "do not rename existing production collections — add alongside." The Ark `communities` collection is production. We cannot reuse the same Firestore collection path with conflicting schemas.

**DECISION:** Use a new top-level collection `amenCommunities/{communityId}` for the Spaces hierarchy. This avoids colliding with the Ark community schema. All Spaces documents will use `communityId` that references `amenCommunities`, not legacy `communities`. (This is noted as a reconciliation assumption in CONTRACT_A.md.)

### 1.3 `entitlements/{userId}_{spaceId}` — DOES NOT EXIST

No existing entitlement collection. `covenantSubscriptions/{uid}` and `covenantMemberships/{docId}` exist for the Covenant/Patreon path but are completely separate. No conflict.

### 1.4 Stripe / Webhook handler — EXISTS (Covenant path only)

- `AmenCovenantCheckoutService.swift` calls `createCovenantCheckoutSession` Cloud Function.
- `covenantMemberships` is written server-side after payment.
- **No existing `stripeWebhook` handler** in `functions/src/` (not present in any of the 6 modules scanned).
- The new `stripeWebhookEntitlement.ts` is net-new.

**Fee math reuse:** Existing fee calculation is inside the Cloud Function `createCovenantCheckoutSession` (not in client code). The new `grantSpaceAccess` and `stripeWebhookEntitlement` can invoke the same Stripe SDK setup.

### 1.5 Cloud Functions — GAPS

| Function | Exists? | Notes |
|---|---|---|
| `grantSpaceAccess` | NO | Net-new |
| `stripeWebhookEntitlement` | NO | Net-new; existing webhook is Covenant-specific and not exposed |
| `revokeSpaceLinkAccess` | NO | Net-new |
| `createCovenantCheckoutSession` | YES | Covenant path; reuse Stripe SDK setup |
| `assertSpaceMember` | YES (local helper) | Already in `spacesIntelligence/callable.ts`; will mirror in new functions |

### 1.6 `isSpaceMember` / `isSpaceAdmin` — ALREADY IN FIRESTORE RULES

Lines 61–86 of `firestore.rules` define `isSpaceMember(spaceId)` and `isSpaceAdmin(spaceId)`. These check `spaces/{spaceId}/members/{uid}`. The new entitlement gate is additive on top of this.

### 1.7 `CommunicationOSModels.swift` — NO CONFLICT

`CommunicationOSModels.swift` contains intelligence/AI models (`ThreadDecision`, `ThreadQuestion`, `ThreadAction`, `GroupPulseData`, `SmartPresenceStatus`). No `Community`, `Space`, `Thread`, or `Message` structs — no naming collision.

### 1.8 `CovenantModels.swift` — ADJACENT, NOT CONFLICTING

Uses `Covenant`, `CovenantRoom`, `CovenantMessage`, `CovenantMembership`. These are the Patreon-like creator layer. No `Space` or `Community` struct. No collision with `SpacesModels.swift`.

### 1.9 `CSPhase1Models.swift` — NO CONFLICT

Creator Spaces Phase 1 — media provenance models, no Firestore hierarchy overlap.

---

## 2. Gap Summary

| Gap | Action |
|---|---|
| `amenCommunities` collection | Create new (legacy `communities` kept intact) |
| `entitlements` flat top-level | Create new — does not exist |
| `spaces` field extensions | Additive only — existing sub-collections kept |
| Stripe webhook for entitlements | New function `stripeWebhookEntitlement.ts` |
| `grantSpaceAccess` callable | New function |
| `revokeSpaceLinkAccess` callable | New function |
| Firestore security rules | Additive — entitlement gate + community/link rules |
| Composite indexes | 4 new indexes needed |
| `SpacesModels.swift` | Net-new file |
| `SpacesService.swift` | Net-new file |

---

## 3. Conflicts / Reconciliation Notes

1. **`communities` vs. `amenCommunities`:** Legacy `communities` (Ark) has a different schema. New Spaces uses `amenCommunities` to avoid schema collision. All Spaces `communityId` fields point to `amenCommunities`.

2. **`spaces/members/{uid}.role` field:** Existing intelligence code (assertSpaceMember) reads `role` from `spaces/{spaceId}/members/{uid}`. New Spaces schema adds `homeCommunityId` and `access` fields alongside `role` — strictly additive.

3. **`covenantSubscriptions` vs. `entitlements`:** Two separate billing paths. `covenantSubscriptions` is the Patreon-tier creator sub; `entitlements` is the Space access gate. Do not merge.

4. **`studies` top-level collection:** Exists as a read-only catch-all (line 1912 of rules). New Spaces uses `spaces/{spaceId}/studies/{studyId}` — a subcollection, not the top-level collection. No conflict.

---

## 4. Existing Infrastructure Reused

- Firebase Admin SDK setup in `functions/src/spacesIntelligence/callable.ts`
- `assertSpaceMember` / `assertSpaceAdmin` helper pattern (mirrored in new functions)
- `isSpaceMember` / `isSpaceAdmin` functions in `firestore.rules`
- Stripe SDK will be imported from the same npm package used in Covenant functions
- SCN block model from `ChurchNotes` (blocks sub-collection) — reused in `studies/{studyId}/blocks`

AUDIT_A_COMPLETE
