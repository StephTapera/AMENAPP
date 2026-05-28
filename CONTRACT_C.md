# CONTRACT_C — Spaces v2 Shared Components + Navigation Shell

> Agent C owns:
> - `AMENAPP/Spaces/SharedComponents/` — the "import, never re-implement" kit
> - `AMENAPP/Spaces/Shell/` — navigation shell, detail view, community switcher

---

## 1. Shared Component APIs

### `LinkedGlyph`

**File:** `AMENAPP/Spaces/SharedComponents/LinkedGlyph.swift`

```swift
LinkedGlyph(size: Size, isInteractive: Bool = false, action: (() -> Void)? = nil)
```

| Size | Point size |
|------|-----------|
| `.small` | 14 pt |
| `.medium` | 20 pt |
| `.large` | 28 pt |

- Renders SF Symbol `"link"` in `AmenTheme.Colors.amenPurple` over a `LiquidGlassTokens.blurThin` capsule.
- `isInteractive: true` adds a press-scale animation (`Motion.liquidSpring`) and gesture.
- Accessibility: interactive → label "External member indicator", hint "Double-tap to view community."; non-interactive → label "Cross-community member".
- Reduce-transparency fallback: `AmenTheme.Colors.surfaceChip` fill.
- **Never re-implement this glyph elsewhere.**

---

### `LinkedCommunityGlyph`

**File:** `AMENAPP/Spaces/SharedComponents/LinkedCommunityGlyph.swift`

```swift
LinkedCommunityGlyph(size: CGFloat, communityName: String, onTap: (() -> Void)? = nil)
```

- Extended variant: accepts a free-form `CGFloat` point size and a `communityName` for the popover label.
- When `onTap` is provided, tapping shows a popover: "Shared with [communityName]."
- Used by `SharedCommunityBannerHero`, `SpaceAvatarView`, and section headers.

---

### `SpaceAvatarView`

**File:** `AMENAPP/Spaces/SharedComponents/SpaceAvatarView.swift`

```swift
SpaceAvatarView(
    avatarURL: String?,
    title: String,
    size: CGFloat,
    isShared: Bool,
    sharedCommunityName: String = ""
)
```

- Circular avatar: `AsyncImage` from `avatarURL` with initials fallback.
- `isShared: true` → renders `LinkedCommunityGlyph` badge at bottom-right.
- `sharedCommunityName` feeds the glyph's popover label.
- Reduce-transparency: solid `AmenTheme.Colors.surfaceChip` backing.

---

### `SharedCommunityBanner`

**File:** `AMENAPP/Spaces/SharedComponents/SharedCommunityBanner.swift`

```swift
SharedCommunityBanner(mode: Mode)
```

| Mode | Copy produced |
|------|---------------|
| `.sharedWith(communityName: String)` | "Shared with [Community]." |
| `.membersFrom(count: Int, communityName: String)` | "N members are from [Community]." |

- Glass pill (`LiquidGlassTokens.blurThin` capsule, white 0.28 stroke, 8pt shadow).
- Contains `LinkedGlyph(.small)` + text label.
- **No Firestore reads inside.** Caller passes pre-resolved community names.
- `SharedCommunityBannerHero` is the expanded hero variant for `SpaceDetailView` headers.

---

### `MemberRosterSheet`

**File:** `AMENAPP/Spaces/SharedComponents/MemberRosterSheet.swift`

```swift
MemberRosterSheet(
    members: [SpaceCommunityMember],
    localCommunityId: String,
    isPresented: Binding<Bool>,
    communityNames: [String: String] = [:]
)
```

- Section 1 "Members": `homeCommunityId == nil || homeCommunityId == localCommunityId`.
- Section 2+: one section per external `homeCommunityId`; header shows `LinkedGlyph(.small)` + resolved community name.
- Wrapped in `AmenLiquidGlassBottomSheet`; `.medium` / `.large` detents.
- `communityNames` resolves `homeCommunityId` → display name. Pass `[:]` when names are unavailable; section header falls back to the raw ID.
- **No Firestore reads inside.** Caller loads the `members` array from `spaces/{spaceId}/members`.
- **Canonical API. Do not use `ExternalMemberRoster` (deleted).**

---

### `LockedPreviewShell`

**File:** `AMENAPP/Spaces/SharedComponents/LockedPreviewShell.swift`

```swift
LockedPreviewShell(space: AmenSpaceExtended, onUnlock: () -> Void)
```

- Full-screen paywall teaser: blurred `avatarURL` background (or `amenPurple`→`amenBlack` gradient), `lock.fill` in `amenGold`, title, optional description, price chip, "Unlock Space" CTA.
- Price chip: formatted from `space.priceConfig.amountCents / 100`, e.g. "$9.99 / month".
- `onUnlock` is called when the CTA is tapped — **Agent E wires this to `SpacesPurchaseSheet`.**
- Accessibility label: `"Locked Space: [title]. Double-tap to unlock."`.
- Accessibility action named `"Unlock"` also triggers `onUnlock`.

---

## 2. SpaceDetailView Wiring

**File:** `AMENAPP/Spaces/Shell/SpaceDetailView.swift`

- Accepts `space: AmenSpaceExtended` and `communityId: String`.
- Hero header: blurred avatar band → fade → 80 pt type-icon circle (offset +40 pt).
- **SharedCommunityBanner pills**: one per entry in `space.sharedWith`. Names resolved via `sharedCommunityNames: [String: String]` state. Agent F writes `sharedWith` on the space doc; SpaceDetailView re-renders via the Firestore listener owned by `SpacesShellViewModel` in the parent.
- **Entitlement check** (`checkEntitlement()`): calls `EntitlementService.shared.fetchEntitlement(userId:spaceId:)`. If not `.active` or `.grace`, sets `isLocked = true`.
- **LockedPreviewShell overlay**: shown when `isLocked && !isCheckingEntitlement`. `onUnlock` sets `showPurchaseSheet = true`.
- **Agent E purchase sheet**: `.sheet(isPresented: $showPurchaseSheet)` renders `SpacesPurchaseSheet(space:userId:isPresented:)`.
- **MemberRosterSheet**: members loaded once from `spaces/{spaceId}/members` on `.task`. Presented via `showMemberRoster` state.
- **Type-driven body**:
  - `.chat` / `.group` → `ThreadListView(spaceId:space:)` from Agent B.
  - `.bibleStudy` → stub `Text("Study coming from Agent D")` until Agent D wires `StudyBlocksView`.
  - `.announcement` → stub `Text("Announcements")` until Agent D wires `AnnouncementFeedView`.

```swift
// Agent E purchase sheet hook — in SpaceDetailView:
.sheet(isPresented: $showPurchaseSheet) {
    if let userId = Auth.auth().currentUser?.uid {
        SpacesPurchaseSheet(space: space, userId: userId, isPresented: $showPurchaseSheet)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}
// LockedPreviewShell calls onUnlock which sets showPurchaseSheet = true
```

---

## 3. Navigation Shell

### `SpacesRootView`

**File:** `AMENAPP/Spaces/Shell/SpacesRootView.swift`

- iPhone: `NavigationStack` with leading toolbar button that opens `CommunitySwitcherView` sheet.
- iPad: `NavigationSplitView` — `CommunitySwitcherView` in the 64 pt left column.
- Loads communities via `SpacesService.shared.fetchMyCommunities()`.
- Switches between communities by re-mounting `SpacesListView` with `.id(selectedCommunityId)`.
- "Create a Community" FAB → `SpaceCreationWizardPlaceholder` until Agent D wires.
- `SpaceCreationWizardPlaceholder`, `SpacesChatViewPlaceholder`, `SpaceLockedPlaceholder` stubs defined in `SpacesListView.swift`.

### `CommunitySwitcherView`

**File:** `AMENAPP/Spaces/Shell/CommunitySwitcherView.swift`

- Vertical 56 pt sidebar column: circular avatars + `amenPurple` ring for selected community + unread dot.
- Long-press → popover with community name.
- "+" button → `CommunityCreateSheet`.
- Binds `selectedCommunityId: Binding<String>` to parent state.

### `SpacesListView`

**File:** `AMENAPP/Spaces/Shell/SpacesListView.swift`

- Wraps `SpacesShellViewModel` (real-time Firestore listener).
- Filter pills: `SpaceListFilter` — `.all` / `.vip` / `.unreads` / `.external`.
- Each tile: `SpaceListTile` (struct, `AmenSpaceExtended` input).
- Tap: free → direct navigation; paid → `EntitlementService.shared.fetchEntitlement` → locked if not active/grace.
- Context menu: toggle VIP via `viewModel.toggleVip(spaceId:)`.
- FAB: calls `onStartSomething?()` — Agent D wires creation wizard.
- `AmenSpaceExtended` Hashable conformance added here for `navigationDestination(item:)`.

### `SpacesShellViewModel`

**File:** `AMENAPP/Spaces/Shell/SpacesShellViewModel.swift`

```swift
@MainActor final class SpacesShellViewModel: ObservableObject
```

| Published | Type | Description |
|-----------|------|-------------|
| `spaces` | `[AmenSpaceExtended]` | Raw Firestore result |
| `filteredSpaces` | `[AmenSpaceExtended]` | Post-filter |
| `currentFilter` | `SpaceListFilter` | Active pill |
| `unreadCounts` | `[String: Int]` | keyed by spaceId — callers update |
| `isLoading` | `Bool` | Loading state |
| `error` | `Error?` | Last Firestore error |

- VIP set persisted in `UserDefaults` under key `"vipSpaceIds"`.
- Call `applyFilter(_:)` to update `filteredSpaces` without re-fetching.
- Call `loadSpaces(communityId:)` to attach/replace the Firestore listener.

### `CommunityCreateSheet`

**File:** `AMENAPP/Spaces/Shell/CommunityCreateSheet.swift`

- Creates `amenCommunities/{id}` + `members/{userId}` (role: owner).
- Tries `createCommunity` Firebase callable first; falls back to direct Firestore write if callable is not yet deployed.
- Accepts `onCreated: ((String) -> Void)?` — called with the new `communityId`.
- **Deploy note**: the `createCommunity` callable must be deployed before the CF path functions. Direct-write fallback is intentional for pre-deploy testing.

---

## 4. Filter tabs (cross-agent contract)

Agent B exposes `ThreadFilter` enum (`all/vip/unreads/external`) in `Chat/SpacesChatModels.swift` for the per-thread level. Agent C's `SpaceListFilter` (same four cases) operates at the Space level in `SpacesShellViewModel`. Both are analogous but separate enums.

### How Agent B wires `ThreadListView`

`SpaceDetailView` for `.chat` and `.group` types renders:
```swift
ThreadListView(spaceId: space.id ?? "", space: space)
```
B's `ThreadListView` takes `(spaceId: String, space: AmenSpaceExtended)`. Until B's file is present the stub `Text("Chat — Agent B")` can be used.

---

## 5. How Agent E wires the purchase sheet

1. `LockedPreviewShell` calls `onUnlock()` when the CTA is tapped.
2. `SpaceDetailView.onUnlock` sets `showPurchaseSheet = true`.
3. `.sheet(isPresented: $showPurchaseSheet)` renders `SpacesPurchaseSheet(space:userId:isPresented:)`.
4. E also gets `SpacesPurchaseSheet` called from `SpacesNavigationView` and `SpacesListView` (via `lockedSpaceTarget` → `LockedPreviewShell` → `onUnlock`).

---

## 6. How Agent F updates the view

F writes the `sharedWith` field on the `spaces/{spaceId}` document via `acceptCommunityLink` / `revokeCommunityLink` callables. `SpacesShellViewModel`'s Firestore snapshot listener automatically picks up the change and re-renders `SpaceDetailView`'s `SharedCommunityBanner` pills. **F does NOT call any method on Agent C directly.**

---

## 7. Duplicate / deleted files

| File | Decision |
|------|----------|
| `ExternalMemberRoster.swift` | **Deleted.** Unreferenced. `MemberRosterSheet` is the canonical roster API. |
| `LinkedCommunityGlyph.swift` | **Kept.** Not a duplicate — referenced by `SharedCommunityBannerHero`, `SpaceAvatarView`, and external section headers. Provides free-form `CGFloat` size + popover that `LinkedGlyph`'s `Size` enum does not cover. |

---

## 8. Motion tokens

`Motion.liquidSpring` is defined in `AMENAPP/Motion.swift` (line 336). All Agent C files use it directly — no substitution needed.

---

## 9. Three-line handoff

**What changed:** Agent C delivered 13 files — 6 shared components (LinkedGlyph, LinkedCommunityGlyph, SpaceAvatarView, SharedCommunityBanner, MemberRosterSheet, LockedPreviewShell) and 7 shell files (SpacesRootView, CommunitySwitcherView, SpacesListView, SpacesNavigationView, SpacesShellViewModel, SpaceDetailView, CommunityCreateSheet). `ExternalMemberRoster.swift` was deleted (unreferenced duplicate); `SpacesListView` was fixed to use `AmenSpaceExtended` throughout with a `Hashable` conformance extension; `SpacesNavigationView.SpaceListRow.body` was decomposed to fix a type-checker timeout.

**Contract exposed:** `LinkedGlyph`, `LinkedCommunityGlyph`, `SpaceAvatarView`, `SharedCommunityBanner` / `SharedCommunityBannerHero`, `MemberRosterSheet`, `LockedPreviewShell` are the canonical shared-component kit — import these, never re-implement. `SpaceDetailView` exposes `showPurchaseSheet` state for Agent E, responds to Firestore `sharedWith` changes for Agent F, and renders `ThreadListView` seam for Agent B.

**Assumptions:** `AmenSpaceExtended` is the v2 Space model from Agent A; `SpaceCommunityMember` (in `SpacesCommunityModels.swift`) is the correct member type for `MemberRosterSheet`; `Motion.liquidSpring` is defined project-wide in `Motion.swift` and requires no substitution; the `createCommunity` callable may not yet be deployed (direct-write fallback is intentional).
