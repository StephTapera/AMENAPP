# Agent F — Cross-Community Links (Generic Attachment + Evident Signal UX)

> Read `00_MASTER_CONTRACT.md`, `CONTRACT_A.md`, and `CONTRACT_C.md` first. Do NOT start
> until A and C are complete (CONTRACT_A.md ends "AGENT_A_COMPLETE", CONTRACT_C.md ends
> "AGENT_C_COMPLETE"). Project root: `~/Desktop/AMEN/AMENAPP copy/`, workspace
> `AMENAPP.xcworkspace`.

## Your mandate

You build the cross-community linking system: how two communities attach to share a
Space, how the link is surfaced as an evident, faith-neutral signal throughout the UI,
and how revocation is handled cleanly.

### Step 1 — AUDIT FIRST (gap report before changing anything)

Inventory existing cross-community or organization linking:
- Check `AMENAPP/AMENAPP/CommunicationOS/` for any multi-community or org-linking
  patterns.
- Check `Organizations/` at the project root for any org relationship models.
- Look at existing invitation/access-request flows (e.g., `AMENAPP/AMENAPP/AccessPasses/`)
  — the link invitation UX can reuse the access-pass accept/decline pattern.
- Check `CONTRACT_C.md` for where Agent C exposed the "Link another community" entry
  point in `SpaceDetailView`'s settings.

Produce a gap report before changing anything.

### Step 2 — Link data layer

All Firestore reads/writes follow the schema in `CONTRACT_A.md`:
```
communities/{communityId}/links/{linkId}
  otherCommunityId: string
  status: "pending" | "active" | "revoked"
  scope: string         // e.g. "Shared: Romans Study"
  createdBy: string     // userId who initiated
  createdAt: Timestamp
  updatedAt: Timestamp

spaces/{spaceId}
  sharedWith: [communityId]   // maintained by Agent F's service
  members/{userId}
    homeCommunityId: string   // set when external member joins
```

**`AMENAPP/AMENAPP/Spaces/CrossCommunity/CrossCommunityLinkService.swift`** (async/await)
```swift
// sendLinkInvite(fromCommunityId: String, toCommunityId: String, spaceId: String, scope: String) async throws
//   → creates communities/{fromCommunityId}/links/{linkId} with status: "pending"
//   → sends notification to toCommunityId's admins/owner

// acceptLink(linkId: String, inCommunityId: String) async throws
//   → sets link.status = "active"
//   → adds spaceId to spaces/{spaceId}.sharedWith (atomic transaction)
//   → does NOT add individual members yet — joining is per-user

// declineLink(linkId: String, inCommunityId: String) async throws
//   → sets link.status = "revoked"
//   → does NOT delete the link row

// revokeLink(linkId: String, inCommunityId: String) async throws
//   → sets link.status = "revoked"
//   → removes communityId from spaces/{spaceId}.sharedWith
//   → calls Cloud Function revokeSpaceLinkAccess (from Agent A) — flips member access, never deletes
//   → does NOT delete the link row

// fetchIncomingLinkInvites(communityId: String) async throws -> [CommunityLink]
// fetchOutgoingLinkInvites(communityId: String) async throws -> [CommunityLink]
// streamLinkedCommunities(spaceId: String) -> AsyncStream<[LinkedCommunity]>
//   → returns the list of communities currently sharing the Space (status: active)
```

**`AMENAPP/AMENAPP/Spaces/CrossCommunity/CrossCommunityModels.swift`**
```swift
struct CommunityLink: Identifiable, Codable {
    let id: String
    let fromCommunityId: String
    let toCommunityId: String
    var status: LinkStatus
    let scope: String
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
}

enum LinkStatus: String, Codable {
    case pending, active, revoked
}

struct LinkedCommunity: Identifiable {
    let id: String           // communityId
    let name: String
    let avatarURL: String?
    let externalMemberCount: Int
    let linkId: String
    let linkStatus: LinkStatus
}
```

### Step 3 — Link invite + accept/decline flow

**`AMENAPP/AMENAPP/Spaces/CrossCommunity/LinkInviteSheet.swift`**

Triggered from Agent C's Space settings (owner/admin only). Glass sheet:
```
"Link another community to this Space"

Search field: "Find a community..." → searches communities by name/handle (Algolia)
Results: community avatar + name + member count

[Invite to share] → sends link invite → shows pending state
"Waiting for [Community Name] to accept..."

Already linked communities: listed with [Revoke] button
```

**`AMENAPP/AMENAPP/Spaces/CrossCommunity/LinkInviteInboxView.swift`**

Where community admins see incoming link invitations:
```
Accessible from: community settings or notification banner.

Each invite card:
  [Community avatar]  [Community name]  "wants to share [Space title] with you"
  [Accept]   [Decline]   — amenGold / amenPurple glass buttons

On accept: calls acceptLink() → Space appears in their linked Spaces list.
On decline: calls declineLink() → invite disappears.
```

Reuse the access-pass accept/decline card style if it exists (check `AmenAccessRequestInboxView`).

### Step 4 — Joining a shared Space as an external member

When a linked community's member enters the shared Space via Agent C's shell:
- If they don't have a `spaces/{spaceId}/members/{userId}` row yet:
  - Show a "You're joining as a visitor from [Your Community]" glass card.
  - On confirm: write the member row with `homeCommunityId = their community`, `access: "granted"`.
- Their avatar shows `LinkedCommunityGlyph` (Agent C's component) everywhere in the Space.

**`AMENAPP/AMENAPP/Spaces/CrossCommunity/ExternalJoinPrompt.swift`**
```swift
// Glass card shown once when an external member first enters a shared Space.
// "You're joining as a visitor from [Community Name]"
// [Join as visitor] button
// On tap: writes spaces/{spaceId}/members/{userId} with homeCommunityId
struct ExternalJoinPrompt: View { ... }
```

### Step 5 — Notification: link invite received

When a link invite is sent, the owning community admin/owner must be notified.

**`functions/src/spaces/notifyCommunityLinkInvite.ts`**
```typescript
// Triggered by Firestore onCreate on communities/{communityId}/links/{linkId}
//   where status == "pending".
// Sends push notification to the target community's owner + admins:
//   title: "[Community Name] wants to share a Space with you"
//   body: "[Space title] — tap to review"
// Uses existing AMEN FCM notification pattern.
```

### Step 6 — Revocation handling (graceful, no crash)

When `revokeLink` is called:
1. Cloud Function `revokeSpaceLinkAccess` (Agent A) flips external members'
   `access: "none"` — does NOT delete member rows.
2. `spaces/{spaceId}.sharedWith` is updated (atomic remove).
3. The real-time `sharedWith` listener in Agent C's `SpaceDetailView` fires → banner
   disappears, `LinkedCommunityGlyph` disappears from the Space tile.
4. External members who are mid-session get a non-blocking glass banner:
   "This Space is no longer shared with your community."
5. The Space remains visible to them temporarily (for the in-render session) — on
   next navigation away and back, the Space no longer appears in their list.
6. No hard-delete. No crash. No `EXC_BAD_ACCESS`.

**`AMENAPP/AMENAPP/Spaces/CrossCommunity/LinkRevokedBanner.swift`**
```swift
// Non-blocking dismissable banner shown to external members when their link is revoked.
// "This Space is no longer shared with your community."
// Dismisses with spring animation after 5 seconds or on tap.
struct LinkRevokedBanner: View { ... }
```

### Step 7 — Evident signal: external member badge on avatars

When rendering a message author avatar in Agent B's chat (or anywhere in the Space), the
author's `homeCommunityId` must be checked:
- If `homeCommunityId != space.communityId` AND the community is actively linked:
  - Show `LinkedCommunityGlyph` (from Agent C) as a small overlay badge on the avatar.
  - Tapping the badge shows: "From [Community Name]" in a glass tooltip.

**This badge logic must be in the chat view model or author view — Agent B exposes
`homeCommunityId` on the message/author model (per CONTRACT_B), and Agent C renders the
glyph. Agent F does NOT create a competing badge implementation.**

If Agent B's message model does not expose `homeCommunityId` on the author:
1. Flag it in CONTRACT_F.md as a gap.
2. Add `authorHomeCommunityId: String?` to `SpaceMessage` in Agent B's model file.
   Document this as a shared-file touch.

---

## Hard constraints

- Money does not cross the link. Payments are the owning community's affair entirely.
- Revocation: flip status, flip member access, never delete rows.
- Create-first / link-second only. No co-creation wizard step.
- The evident signal (glyph, banner, roster) is implemented in Agent C's components.
  Agent F wires data to them; it does NOT re-implement them.
- No Combine. Async/await only.
- No "church" anywhere.

---

## Deliverables

1. `AMENAPP/AMENAPP/Spaces/CrossCommunity/CrossCommunityModels.swift`
2. `AMENAPP/AMENAPP/Spaces/CrossCommunity/CrossCommunityLinkService.swift`
3. `AMENAPP/AMENAPP/Spaces/CrossCommunity/LinkInviteSheet.swift`
4. `AMENAPP/AMENAPP/Spaces/CrossCommunity/LinkInviteInboxView.swift`
5. `AMENAPP/AMENAPP/Spaces/CrossCommunity/ExternalJoinPrompt.swift`
6. `AMENAPP/AMENAPP/Spaces/CrossCommunity/LinkRevokedBanner.swift`
7. `functions/src/spaces/notifyCommunityLinkInvite.ts`
8. Additive `authorHomeCommunityId` field to Agent B's model if missing (flag in contract).
9. **`spaces-spec/CONTRACT_F.md`** — link service API, any shared-file touches,
   revocation sequence, assumptions made.

---

## Done when

- All Swift files build with zero diagnostics.
- Link invite → accept → external member joins → badge appears → revoke → banner appears,
  all without crash or hard-delete.
- `CONTRACT_F.md` published ending with "AGENT_F_COMPLETE".
