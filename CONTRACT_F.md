# CONTRACT_F.md — Spaces v2 Cross-Community Links

> Agent F deliverables. All downstream callers (Agent C's SpaceDetailView, community admin nav) build against these entry points.
> Do not redefine any type listed here.

---

## File Ownership

Agent F owns exclusively: `AMENAPP/Spaces/Links/` (new directory).

Agent F reads (never edits): all other Spaces files, including Agent C's SharedComponents.

---

## 1. Entry Points

### `LinkSpaceSheet`

**File:** `AMENAPP/Spaces/Links/LinkSpaceSheet.swift`

```swift
LinkSpaceSheet(
    space: AmenSpaceExtended,   // The existing Space to share — create-first/link-second
    communityId: String,         // Owning community
    isPresented: Binding<Bool>
)
```

**Trigger:** SpaceDetailView presents this sheet when an admin taps "Link a community."
Agent C calls `onManageLinks` from `LinkedSpaceDetailSection` which sets `showLinkSheet = true` → `.sheet { LinkSpaceSheet(...) }`.

**Flow:**
1. Search step — @handle text field, 500ms debounce, calls `SpacesLinksService.searchCommunity(handle:)`.
2. Confirm step — hero invite card (your community → `LinkedGlyph` → target community), pre-send copy.
3. Pending state — after invite sent; "Cancel invite" calls `revokeLink`.
4. Error — inline display.

---

### `PendingInvitationsSheet`

**File:** `AMENAPP/Spaces/Links/PendingInvitationsSheet.swift`

```swift
PendingInvitationsSheet(
    communityId: String,
    isPresented: Binding<Bool>
)
```

**Trigger:** Community admin nav (or `PendingInvitationsBanner.onTap`) presents this sheet.

**Behaviour:**
- Loads `pendingInvitations` on appear via `SpacesLinksService.loadPendingInvitations(forCommunityId:)`.
- Each card: hero-profile style (48pt avatar, community name, Space title, timestamp).
- Accept → `service.acceptLink(linkId:communityId:)` → card disappears via Firestore listener update (no client-side array mutation).
- Decline → `service.revokeLink(linkId:communityId:)` → status flips to revoked; card disappears via listener.
- **No hard-deletes anywhere.**

---

### `PendingInvitationsBanner`

**File:** `AMENAPP/Spaces/Links/PendingInvitationsBanner.swift`

```swift
PendingInvitationsBanner(
    invitations: [PendingLinkInvitation],
    onTap: () -> Void
)
```

Non-intrusive pill banner for community admin surfaces.
- Hidden when `invitations.isEmpty`.
- Renders `LinkedGlyph(.small)` + "N pending community link invitation(s)".
- `onTap` opens `PendingInvitationsSheet`.

---

### `LinkedSpaceDetailSection`

**File:** `AMENAPP/Spaces/Links/LinkedSpaceDetailSection.swift`

```swift
LinkedSpaceDetailSection(
    space: AmenSpaceExtended,
    communityId: String,         // Owning community
    onManageLinks: () -> Void    // Opens LinkSpaceSheet
)
```

**Usage:** Agent C drops this below the hero header in `SpaceDetailView`.

**Data source:** `space.sharedWith` (denormalized array) — **no per-frame Firestore fetches**.
Community name resolution is done once on appear via a single batch `getDocument()` per communityId.

**Renders:**
- Section header: `LinkedGlyph(.small)` + "Linked communities"
- One `SharedCommunityBanner(.sharedWith(communityName:))` per `sharedWith` entry.
- "Link a community" button (`onManageLinks`) for admins.

**Hidden** when `space.sharedWith.isEmpty` and no admin button is needed.

---

## 2. `SpacesLinksService` Public Method Signatures

**File:** `AMENAPP/Spaces/Links/SpacesLinksService.swift`

```swift
@MainActor final class SpacesLinksService: ObservableObject {

    @Published var pendingInvitations: [PendingLinkInvitation] = []
    @Published var activeLinks: [CommunityLink] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    // Attaches a live Firestore listener on amenCommunities/{communityId}/links.
    // Populates activeLinks (status .active). Listener cancelled in deinit.
    func loadLinks(communityId: String) async

    // Queries amenCommunities where handle == handle.
    // Returns nil when not found. Query is authenticated.
    // Strips leading "@" from input automatically.
    func searchCommunity(handle: String) async throws -> AmenCommunity?

    // Calls SpacesCallable.linkCommunity. Returns new linkId on success.
    // Money never crosses the link — this call creates only the link record.
    func inviteToLink(
        fromCommunityId: String,
        targetCommunityId: String,
        spaceId: String
    ) async throws -> String

    // Calls SpacesCallable.acceptCommunityLink.
    // Backend fan-outs sharedWith on the Space doc.
    // activeLinks updates automatically via listener.
    func acceptLink(linkId: String, communityId: String) async throws

    // Calls SpacesCallable.revokeCommunityLink.
    // Status flips to revoked on backend. External members' access drops via CF.
    // NEVER calls .delete() on any Firestore document.
    func revokeLink(linkId: String, communityId: String) async throws

    // Attaches a live listener on amenCommunities/{communityId}/links
    // where status == "pending" and toCommunityId == communityId.
    // Resolves from-community name + avatar and Space title on each update.
    // Listener cancelled in deinit.
    func loadPendingInvitations(forCommunityId: String) async
}
```

---

## 3. View-Layer Model Types (SpacesLinksModels.swift)

```swift
/// Invite flow state for LinkSpaceSheet's attach UX.
enum LinkInviteState: Equatable {
    case idle
    case searching
    case found(community: AmenCommunity)
    case pendingAcceptance(linkId: String)
    case active
    case error(String)
}

/// Pending link invitation surfaced to target community admins.
struct PendingLinkInvitation: Identifiable {
    let id: String               // linkId (Firestore document ID)
    let spaceId: String
    let spaceTitle: String       // resolved on load
    let fromCommunityId: String
    let fromCommunityName: String
    let fromCommunityAvatarURL: String?
    let createdAt: Date
}
```

These extend Agent A's canonical types. `CommunityLink` and its `LinkStatus` live in `SpacesModels.swift` and are NOT redefined here.

---

## 4. Fields That Agent C and Agent E Rely On

| Field | Location | Used by |
|---|---|---|
| `sharedWith` | `spaces/{spaceId}` | Agent C (SharedCommunityBanner pills in SpaceDetailView); Agent F's LinkedSpaceDetailSection reads it. |
| `homeCommunityId` | `spaces/{spaceId}/members/{userId}` | Agent C (MemberRosterSheet sections external members by this field). Agent F does NOT write this — owned by backend CF. |
| `status` | `amenCommunities/{id}/links/{linkId}` | Agent F listens to this for activeLinks and pendingInvitations. Agent C reacts to sharedWith changes that the CF makes on status flip. |

**sharedWith maintenance:** Agent F calls `acceptCommunityLink` / `revokeCommunityLink` callables. The Cloud Function (Agent A) fans out `sharedWith` updates on the Space doc. Agent F's client does NOT write `sharedWith` directly.

**homeCommunityId maintenance:** Owned entirely by Agent A's Cloud Functions. Agent F surfaces this field only via Agent C's `MemberRosterSheet` and `LinkedGlyph` components — never writes it.

---

## 5. The No-Money-Crossing Guarantee (Explicit)

**Money never crosses a community link in v1.**

- `SpacesLinksService` manages only link status (`pending → active → revoked`).
- `SpacesLinksService` does NOT read, write, or reference `entitlements/` documents.
- `SpacesLinksService` does NOT call `grantAccess`, `purchaseSpaceAccess`, or `revokeAccess` callables.
- External members who need paid access to a Space must go through Agent E's `SpacesPurchaseSheet` / `grantAccess` path.
- `LinkedSpaceDetailSection` and `PendingInvitationsSheet` surface **zero pricing UI** — no price chips, no "Unlock" CTAs, no fee math.
- The owning community's Stripe Connect account collects all revenue. Cross-link revenue split is a fast-follow item outside v1 scope.

This boundary is enforced by file ownership: `AMENAPP/Spaces/Links/` contains no imports of `SpacesFeeCalculator`, `AmenCovenantCheckoutService`, `AmenSubscriptionService`, or `GivingInAppSheet`.

---

## 6. Imported Agent C Components (Never Re-implemented)

| Component | Used in | Purpose |
|---|---|---|
| `LinkedGlyph` | `PendingInvitationsBanner`, `LinkedSpaceDetailSection`, `PendingInvitationsSheet` | Cross-community signal glyph |
| `SharedCommunityBanner` | `LinkedSpaceDetailSection`, `LinkSpaceSheet` (active state) | "Shared with [Community]" pill |
| `SpaceAvatarView` | `LinkSpaceSheet`, `PendingInvitationsSheet` (InvitationCard) | Community avatar + linked badge |
| `AmenLiquidGlassBottomSheet` | `LinkSpaceSheet`, `PendingInvitationsSheet` | Sheet chrome |
| `AmenLiquidGlassPillButton` | `LinkSpaceSheet`, `PendingInvitationsSheet` (InvitationCard) | Primary CTA buttons |

---

## 7. Callables Used

| Callable | `SpacesCallable` case | Description |
|---|---|---|
| `linkCommunity` | `.linkCommunity` | Creates pending link in both communities |
| `acceptCommunityLink` | `.acceptCommunityLink` | Activates link; CF fans out `sharedWith` |
| `revokeCommunityLink` | `.revokeCommunityLink` | Revokes link; CF removes from `sharedWith`, sets external members' access="none" |

---

## 8. Hard Constraints Summary

- Status flips only — `revokeLink` never calls `.delete()` on any Firestore document.
- No "church" in any field, string, comment, or label.
- Tokens only: `AmenTheme.Colors.*`, `LiquidGlassTokens.blurThin`, `LiquidGlassTokens.cornerRadius*`.
- `@MainActor` on `SpacesLinksService`.
- No force-unwrap anywhere in `AMENAPP/Spaces/Links/`.
- Create-first / link-second only — `LinkSpaceSheet` requires an existing `AmenSpaceExtended`.

---

## 9. Three-Line Handoff

**What changed:** Agent F delivered 6 files in `AMENAPP/Spaces/Links/` — `SpacesLinksModels.swift` (view-layer models), `SpacesLinksService.swift` (@MainActor service wrapping the 3 link callables with live Firestore listeners), `LinkSpaceSheet.swift` (search → confirm → pending flow), `PendingInvitationsBanner.swift` (pill banner for admin nav), `PendingInvitationsSheet.swift` (accept/decline sheet), and `LinkedSpaceDetailSection.swift` (drop-in section for SpaceDetailView). All 6 files have 0 diagnostics.

**Contract exposed:** `LinkSpaceSheet(space:communityId:isPresented:)` is the entry point from SpaceDetailView; `PendingInvitationsSheet(communityId:isPresented:)` for community admin nav; `LinkedSpaceDetailSection(space:communityId:onManageLinks:)` drops into SpaceDetailView below the hero header. `SpacesLinksService` is `@StateObject`-scoped (one per sheet), not a singleton — no shared mutable state across surfaces.

**Assumptions made:** (1) `amenCommunities` is the Firestore collection name used by both CrossCommunity and Links services per the pattern established in `CrossCommunityLinkService.swift`. (2) `CommunityLink.LinkStatus` (from `SpacesModels.swift`) is the canonical status enum — `CrossLinkStatus` in `CrossCommunityModels.swift` is a parallel type owned by the earlier CrossCommunity work and is not imported into Links. (3) `SpacesCallable.revokeCommunityLink` handles both invite-decline (from pending state) and active-link revocation — the backend discriminates by current status.
