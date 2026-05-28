# AUDIT_F.md — Agent F Pre-Implementation Gap Report

**Date:** 2026-05-28  
**Agent:** F — Cross-Community Links

---

## 1. AmenAccessRequestInboxView.swift — Card/Button Style Audit

**File:** `AMENAPP/AccessPasses/AmenAccessRequestInboxView.swift`

**Findings:**
- Uses `.insetGrouped` `List` with `listRowBackground(Color.clear)`.
- Each request row is a `VStack(alignment: .leading, spacing: 10)` inside a `List` row.
- Avatar: 40pt `Circle()` with `.ultraThinMaterial` fill and `0.5pt` white stroke.
- Action buttons: SwiftUI `.bordered` (Deny, role: .destructive) and `.borderedProminent` (Approve) at `.small` controlSize.
- Filter pills: `Capsule()` with `.ultraThinMaterial` fill; selected = `.primary` fill with inverse foreground.

**Decision:** LinkInviteInboxView mirrors this structural pattern (card-per-row, avatar + metadata + action buttons) but renders as standalone glass cards (not List rows) to match the Liquid Glass specification. The button style is replaced with `InboxActionButtonStyle` — gold-filled for Accept, purple-tinted glass for Decline — consistent with `AmenTheme.Colors.amenGold` / `amenPurple`.

---

## 2. revokeSpaceLinkAccess.ts — Existence and Spec Match

**File:** `functions/src/spaces/revokeSpaceLinkAccess.ts`

**Findings:**
- **EXISTS.** Exports `revokeSpaceLinkAccess` as an `onCall` function.
- Payload: `{ spaceId: string, revokedCommunityId: string }` — **matches CONTRACT_A §4 exactly**.
- Side effects confirmed:
  - Flips `access: "granted" → "none"` on all `spaces/{spaceId}/members/{userId}` where `homeCommunityId == revokedCommunityId`. Batch-safe (≤400/batch).
  - Atomically removes `revokedCommunityId` from `spaces/{spaceId}.sharedWith` via `arrayRemove`.
  - **Never deletes member rows.** Hard constraint honoured.
- Authorization: `enforceAppCheck: true` + custom `assertCommunityAdminOrOwner` helper.
- Already exported in `functions/src/spaces/index.ts` and `functions/index.js`.
- **No rewrite needed.** Agent F calls it via `Functions.functions().httpsCallable("revokeSpaceLinkAccess")`.

---

## 3. CommunicationOS — Multi-Org/External-Member Patterns

**Directory:** `AMENAPP/AMENAPP/AMENAPP/CommunicationOS/`

**Findings:**
- No multi-community or org-linking models found. CommunicationOS is a messaging/presence layer for single-community threads.
- `AmenSmartCollaborationContracts.swift`, `CommunicationOSModels.swift`, etc. operate on threads/messages within a single community — no cross-community data field anywhere.
- `AmenMinistryOSBridge.swift` bridges to "ministry" concepts but is entirely single-community scoped.
- **No conflict. Agent F's cross-community models are fully additive.**

---

## 4. functions/index.js — Existing Spaces Exports

**Findings:**
- Spaces Cloud Functions are exported at lines ~1456–1465 via `require('./src/spaces/dist')`.
- Pre-existing exports: `grantSpaceAccess`, `handleStripeSpaceWebhook`, `revokeSpaceLinkAccess`.
- Agent E exports: `createSpaceCheckoutSession`, `createStripeConnectAccount`.
- **Gap:** `notifyCommunityLinkInvite` (Agent F's new trigger) was NOT yet exported.
- **Fixed:** Added export in `functions/index.js` and `functions/src/spaces/index.ts`.

---

## 5. Agent C SharedComponents — File Location

**Contract C** specifies paths under `AMENAPP/AMENAPP/Spaces/SharedComponents/`. The **actual** files are at:

```
AMENAPP/Spaces/SharedComponents/LinkedCommunityGlyph.swift   ← used by Agent F
AMENAPP/Spaces/SharedComponents/SpaceAvatarView.swift        ← used by Agent F
AMENAPP/Spaces/SharedComponents/SharedCommunityBanner.swift  ← used by SpaceDetailView
AMENAPP/Spaces/SharedComponents/LinkedGlyph.swift            ← used by SharedCommunityBanner
```

All four confirmed present. Agent F imports them by name — no re-implementation.

---

## 6. SpaceDetailView — State of the Wire Points

**File:** `AMENAPP/Spaces/Shell/SpaceDetailView.swift`

**Findings:**
- Uses `AmenSpaceExtended` (from `SpacesCommunityModels.swift`) — NOT `AmenSpace` from `SpacesModels.swift`. This is Agent C's v2 working type.
- Already uses `SharedCommunityBanner` and `LinkedGlyph` for the sharedWith display.
- Has a gear toolbar item (Manage Space) — Agent F added a second toolbar item (`link.badge.plus`) for the invite sheet.
- No `LinkRevokedBannerPlaceholder` existed; the banner was added as a ZStack overlay.
- `showMemberRoster`, `showPurchaseSheet` state already present; Agent F adds `showLinkInviteSheet`, `crossCommunityVM`.

---

## 7. CrossCommunityModels — Naming Decision

**Gap identified:** CONTRACT_A §2 defines `CommunityLink` (with `@DocumentID var id: String?` and Firestore mapping fields) in `SpacesModels.swift`. The task spec asks Agent F to create a `CommunityLink` struct with a non-optional `let id: String` and richer fields (`fromCommunityId`, `toCommunityId`).

**Resolution:** Agent F's view model type is named `CommunityLinkRecord` to avoid redeclaring `CommunityLink`. The service converts from the Firestore `CommunityLink` shape to `CommunityLinkRecord`. This is a zero-conflict additive strategy.

---

## 8. SpacesCommunity Search

The task calls for Algolia search. Algolia integration requires the AMEN Algolia client (separate module). As a safe Firestore fallback, Agent F implements a name prefix range query (`name >= query, name <= query\u{f8ff}`). This works for pre-production and is clearly commented as the Algolia swap point.

---

## 9. authorHomeCommunityId on SpaceMessage

`SpaceMessage` in `SpacesModels.swift` does NOT include `authorHomeCommunityId`. The AGENT_F_cross_community.md spec says to add it if missing. However, Agent B's `SpacesChatCoreModels.swift` defines its own chat message model; adding to the canonical `SpaceMessage` would require a shared-file touch owned by Agent A.

**Decision:** Flag in CONTRACT_F.md. Not added by Agent F to avoid schema drift — see CONTRACT_F §4.

---

## 10. No AccessPasses Directory Under AMENAPP/AMENAPP

The spec path `AMENAPP/AMENAPP/AccessPasses/AmenAccessRequestInboxView.swift` does not exist. The file is at `AMENAPP/AccessPasses/AmenAccessRequestInboxView.swift` (one level up in the Xcode project hierarchy). Read successfully at that path.

---

*End of AUDIT_F.md*
