# CONTRACT_F.md — Agent F Public Interface
# Cross-Community Links: Send / Accept / Revoke / Evident Signal

**Status: AGENT_F_COMPLETE**

---

## §1 Files Delivered

| File | Type | Diagnostics |
|------|------|-------------|
| `AMENAPP/Spaces/CrossCommunity/CrossCommunityModels.swift` | New | 0 errors, 0 warnings |
| `AMENAPP/Spaces/CrossCommunity/CrossCommunityLinkService.swift` | New | 0 errors, 0 warnings |
| `AMENAPP/Spaces/CrossCommunity/CrossCommunityViewModel.swift` | New | 0 errors, 0 warnings |
| `AMENAPP/Spaces/CrossCommunity/LinkInviteSheet.swift` | New | 0 errors, 0 warnings |
| `AMENAPP/Spaces/CrossCommunity/LinkInviteInboxView.swift` | New | 0 errors, 0 warnings |
| `AMENAPP/Spaces/CrossCommunity/ExternalJoinPrompt.swift` | New | 0 errors, 0 warnings |
| `AMENAPP/Spaces/CrossCommunity/LinkRevokedBanner.swift` | New | 0 errors, 0 warnings |
| `functions/src/spaces/notifyCommunityLinkInvite.ts` | New | — |
| `functions/src/spaces/index.ts` | Modified | — |
| `functions/index.js` | Modified | — |
| `AMENAPP/Spaces/Shell/SpaceDetailView.swift` | Modified (additive only) | 0 errors, 0 warnings |
| `spaces-spec/AUDIT_F.md` | New | — |
| `spaces-spec/CONTRACT_F.md` | New | — |

---

## §2 Cross-Community Link Service API

**File:** `AMENAPP/Spaces/CrossCommunity/CrossCommunityLinkService.swift`  
**Singleton:** `CrossCommunityLinkService.shared`  
**Isolation:** `@MainActor` class — all method calls are main-actor-safe.

### Send a link invite
```swift
func sendLinkInvite(
    fromCommunityId: String,
    toCommunityId: String,
    spaceId: String,
    scope: String
) async throws
```
- Creates `amenCommunities/{fromCommunityId}/links/{linkId}` with `status: "pending"`.
- Document ID: `{fromCommunityId}_{toCommunityId}` (CONTRACT_A §8 #2 pattern).
- Stores `fromCommunityId`, `toCommunityId`, `spaceId` as extra fields so the `notifyCommunityLinkInvite` CF can resolve the target and space name.
- Throws `CrossLinkError.alreadyLinked` if an active link exists; `CrossLinkError.inviteAlreadyPending` if a pending one exists. Re-invite is allowed after revocation (overwrites the doc).

### Accept an invite
```swift
func acceptLink(
    linkId: String,
    inCommunityId: String,
    spaceId: String
) async throws
```
- Verifies current status is `"pending"`, then runs a Firestore batch:
  - `link.status → "active"`, `link.updatedAt → now`
  - `spaces/{spaceId}.sharedWith → arrayUnion([inCommunityId])` (idempotent)
- Throws `CrossLinkError.invalidLinkState(_)` if status is not pending.

### Decline an invite
```swift
func declineLink(linkId: String, inCommunityId: String) async throws
```
- Flips `link.status → "revoked"`. Never deletes.

### Revoke an active link
```swift
func revokeLink(
    linkId: String,
    inCommunityId: String,
    spaceId: String
) async throws
```
- Flips `link.status → "revoked"`.
- Calls `revokeSpaceLinkAccess` (Agent A CF) with `{ spaceId, revokedCommunityId }`:
  - CF flips all external members' `access: "none"`.
  - CF removes `revokedCommunityId` from `spaces/{spaceId}.sharedWith`.
- Never hard-deletes. Never re-implements CF logic.

### Query methods
```swift
func fetchIncomingInvites(communityId: String) async throws -> [CommunityLinkRecord]
// Collection group query: links where toCommunityId == communityId AND status == "pending"

func fetchOutgoingInvites(communityId: String) async throws -> [CommunityLinkRecord]
// amenCommunities/{communityId}/links where fromCommunityId == communityId, ordered by createdAt DESC

func fetchLinkedCommunities(spaceId: String) async throws -> [LinkedCommunityRecord]
// Reads spaces/{spaceId}.sharedWith, resolves community names + external member counts

nonisolated func streamLinkedCommunities(spaceId: String) -> AsyncStream<[LinkedCommunityRecord]>
// Real-time Firestore listener on spaces/{spaceId}; emits on every sharedWith change
```

### External member join
```swift
func joinAsExternalMember(spaceId: String, homeCommunityId: String) async throws
```
- Writes `spaces/{spaceId}/members/{uid}` with `homeCommunityId`, `role: "member"`, `access: "granted"`.
- Uses `setData(merge: true)` — safe to call multiple times.

### Community search
```swift
func searchCommunities(query: String) async throws -> [SpacesCommunity]
```
- Firestore name prefix range query (`amenCommunities`). Returns up to 20 results.
- **Swap point for Algolia:** replace body with `AlgoliaCommunitiesIndex.search(query: query)` when Algolia is wired.

---

## §3 ViewModel API

**File:** `AMENAPP/Spaces/CrossCommunity/CrossCommunityViewModel.swift`

```swift
@MainActor final class CrossCommunityViewModel: ObservableObject {
    @Published var linkedCommunities: [LinkedCommunityRecord]
    @Published var incomingInvites: [CommunityLinkRecord]
    @Published var outgoingInvites: [CommunityLinkRecord]
    @Published var searchResults: [SpacesCommunity]
    @Published var isLoading: Bool
    @Published var isSending: Bool
    @Published var error: Error?
    @Published var showRevokedBanner: Bool

    func loadForSpace(spaceId: String, communityId: String) async
    func loadIncomingInvites(communityId: String) async
    func sendInvite(toCommunityId: String, fromCommunityId: String, spaceId: String, scope: String) async
    func acceptInvite(link: CommunityLinkRecord, spaceId: String) async
    func declineInvite(link: CommunityLinkRecord) async
    func revokeLink(link: LinkedCommunityRecord, spaceId: String, communityId: String) async
    func search(query: String) async
    func startListening(spaceId: String)   // starts AsyncStream → updates linkedCommunities + showRevokedBanner
    func stopListening()
    func dismissRevokedBanner()
}
```

---

## §4 Revocation Sequence (no crash, no hard-delete)

```
Admin calls revokeLink(link:spaceId:communityId:)
  │
  ├─ 1. link.status → "revoked"   (Firestore write)
  │
  ├─ 2. revokeSpaceLinkAccess CF called → { spaceId, revokedCommunityId }
  │       CF: spaces/{spaceId}/members batch access "granted" → "none"
  │       CF: spaces/{spaceId}.sharedWith arrayRemove revokedCommunityId
  │       CF: NEVER deletes member rows
  │
  ├─ 3. SpaceDetailView.crossCommunityVM.startListening fires
  │       AsyncStream detects sharedWith shrinkage
  │       withAnimation(.liquidSpring) { linkedCommunities updated; showRevokedBanner = true }
  │
  ├─ 4. LinkRevokedBanner appears at top of SpaceDetailView (spring in)
  │       Non-blocking — user can still interact with the Space content
  │       Auto-dismisses after 5 seconds; tap-to-dismiss also wired
  │
  └─ 5. On next navigation away + back:
         Space no longer in external member's list (sharedWith no longer contains their communityId)
         No hard-delete, no EXC_BAD_ACCESS
```

---

## §5 Cloud Function — notifyCommunityLinkInvite

**File:** `functions/src/spaces/notifyCommunityLinkInvite.ts`

- Firestore `onDocumentCreated` on `amenCommunities/{communityId}/links/{linkId}`.
- Skips if `status != "pending"`.
- Resolves: fromCommunity name, space title from `spaces/{spaceId}`.
- Fetches target community (`toCommunityId`) owner + admins via role-based member query.
- Fan-out FCM using the AMEN pattern from `pushNotifications.js`:
  - `users/{userId}/deviceTokens` subcollection (enabled == true) first.
  - Fallback to legacy `users/{userId}.fcmToken`.
  - Stale tokens removed on `messaging/registration-token-not-registered`.
- Notification payload:
  ```
  title: "[fromCommunityName] wants to share a Space with you"
  body:  "[spaceTitle] — tap to review"
  data:  { type: "communityLinkInvite", fromCommunityId, toCommunityId, spaceId, linkId }
  ```
- Exported in `functions/src/spaces/index.ts` and `functions/index.js`.

---

## §6 Shared-File Touches

| File | Type of Change | Why |
|------|---------------|-----|
| `AMENAPP/Spaces/Shell/SpaceDetailView.swift` | Additive | Replaced placeholder toolbar stub with `link.badge.plus` button → `LinkInviteSheet`; added `LinkRevokedBanner` overlay driven by `CrossCommunityViewModel.showRevokedBanner`; added `.onDisappear` to stop listener |
| `functions/src/spaces/index.ts` | Additive | Export `notifyCommunityLinkInvite` |
| `functions/index.js` | Additive | Export `notifyCommunityLinkInvite` from `spacesFns` |

Agent F did NOT touch: `SpacesModels.swift`, `SpacesCommunityModels.swift`, `SpacesService.swift`, any SharedComponent file, or any Agent B/C/D/E file besides `SpaceDetailView.swift`.

---

## §7 Assumptions Made

1. **CommunityLinkRecord vs CommunityLink:** Agent A's `CommunityLink` (in `SpacesModels.swift`) uses `@DocumentID var id: String?` and a flat `otherCommunityId` field. Agent F's view model needs richer typing (`fromCommunityId`, `toCommunityId`, non-optional `id`). Agent F names its type `CommunityLinkRecord` to avoid collision and maps from Firestore at service boundary.

2. **Link document ID:** Uses `{fromCommunityId}_{toCommunityId}` per CONTRACT_A §8 #2. This is a well-known ID pattern — no random UUID is used, which enables idempotent re-invites.

3. **Extra fields on link doc:** Agent F adds `fromCommunityId`, `toCommunityId`, `spaceId` to the link document (beyond the CONTRACT_A minimum). These are essential for the `notifyCommunityLinkInvite` CF and for the collection group query to work. They are additive and do not break CONTRACT_A security rules.

4. **authorHomeCommunityId gap:** `SpaceMessage` in `SpacesModels.swift` does not include an `authorHomeCommunityId` field. The AGENT_F spec instructs Agent F to add it if missing. This field is owned by Agent A's schema and Agent B's message model. Agent F flags the gap here but does NOT add it unilaterally to avoid schema drift:
   - **Action required (Agent A or B):** Add `authorHomeCommunityId: String?` to `SpaceMessage` in `SpacesModels.swift` or to `SpacesChatCoreModels.swift`. The badge logic (LinkedCommunityGlyph on message author avatars) reads this field.

5. **Community search uses Firestore fallback:** Algolia client is not imported by Agent F. The name prefix range query is functional for pre-production. The swap comment is in `CrossCommunityLinkService.searchCommunities`.

6. **ExternalJoinPrompt — spaceId delivery:** `ExternalJoinPrompt` receives `spaceId` and `homeCommunityId` from its call site (the parent view that already has the `AmenSpaceExtended` + the current user's community membership). The join prompt does not perform its own Firestore lookup.

7. **LinkInviteInboxView — spaceId on accept:** The `CommunityLinkRecord` stores `scope` as "Shared: [Title]" not as a `spaceId`. `SpaceDetailView`'s `LinkInviteSheet` has the spaceId in scope and passes it correctly. When `LinkInviteInboxView` is navigated to directly from a notification, the `spaceId` should be passed via deep link data (stored in the link doc's `spaceId` field). **Action required:** the notification tap route must extract `spaceId` from the FCM `data` payload and pass it to `acceptInvite`.

8. **SpaceDetailView type:** Uses `AmenSpaceExtended` (not `AmenSpace` from `SpacesModels.swift`). Agent F matches this — `LinkInviteSheet` takes `spaceId: String` and `spaceTitle: String` (extracted from `AmenSpaceExtended.id` and `.title`) rather than the whole space model.

---

## §8 Deploy Steps Required

| Step | Severity | Owner |
|------|----------|-------|
| Compile TypeScript and deploy `notifyCommunityLinkInvite` to Firebase | P1 | Backend |
| Verify `revokeSpaceLinkAccess` is deployed (Agent A) | P1 | Backend |
| Add Firestore composite index: `amenCommunities/{cid}/links`, fields: `toCommunityId ASC, status ASC` | P1 | Backend/Agent A |
| Add Firestore composite index: collection group `links`, fields: `toCommunityId ASC, status ASC` | P1 | Backend/Agent A |
| Enable `spacesLiquidGlassEnabled` feature flag to surface Spaces tab | P2 | Product |

---

AGENT_F_COMPLETE
