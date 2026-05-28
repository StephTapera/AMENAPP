# CONTRACT_C — Spaces v2 Shared Components & Navigation Shell
**Agent C | AMENAPP Spaces v2 | Status: AGENT_C_COMPLETE**

---

## §1 Shared Component API (Agents B, D, E, F: import these — never re-implement)

All components live in `AMENAPP/Spaces/SharedComponents/`.
Use `AmenTheme.Colors` for all tokens. Use `LiquidGlassTokens` for radii and blur surfaces.

---

### LinkedCommunityGlyph

**File:** `AMENAPP/AMENAPP/Spaces/SharedComponents/LinkedCommunityGlyph.swift`

Interlocking-link SF Symbol badge indicating cross-community sharing. `amenPurple` glyph over `ultraThinMaterial`. Tappable with optional popover.

```swift
LinkedCommunityGlyph(
    size: CGFloat,           // 14 (small) | 20 (medium) | 28 (large)
    communityName: String,   // shown in popover label
    onTap: (() -> Void)? = nil
)
```

- When `onTap` is nil: badge is non-interactive, no popover shown.
- When `onTap` is provided: tappable, shows "Shared with [communityName]" popover.
- Accessibility: `accessibilityLabel("Shared community")`, button trait when `onTap` provided.
- `reduceTransparency`: falls back to `surfaceChip` fill.
- `reduceMotion`: disables press scale animation.

---

### SpaceAvatarView

**File:** `AMENAPP/AMENAPP/Spaces/SharedComponents/SpaceAvatarView.swift`

Circular avatar for Space and Community tiles. AsyncImage with initials fallback. Optional `LinkedCommunityGlyph` badge at bottom-trailing when `isShared == true`.

```swift
SpaceAvatarView(
    avatarURL: String?,        // nil or empty → shows initials
    title: String,             // used to derive 1–2 letter initials
    size: CGFloat,             // diameter in points
    isShared: Bool,            // shows LinkedCommunityGlyph badge when true
    sharedCommunityName: String = ""   // passed to LinkedCommunityGlyph popover
)
```

- `reduceTransparency`: initials background uses `surfaceChip` fill instead of blur.
- Accessibility: combined element with label `"\(title) avatar[, shared community]"`.

---

### ExternalMemberRoster

**File:** `AMENAPP/AMENAPP/Spaces/SharedComponents/ExternalMemberRoster.swift`

Member sheet that sections external members under their home community. Renders own-community members first ("Members"), then one section per external community with `LinkedCommunityGlyph` in the section header.

```swift
ExternalMemberRoster(
    members: [SpaceMember],
    communityNames: [String: String]   // communityId → display name
)
```

- Uses `SpaceMember` from `AMENAPP/AMENAPP/Spaces/SpacesModels.swift` (canonical Agent A type).
- `member.homeCommunityId == ""` → local member.
- `member.homeCommunityId != ""` → external; keyed to `communityNames` for section label.
- Sheet: `presentationDetents([.medium, .large])`, drag indicator visible.
- Accessibility: section headers have `.isHeader` trait; rows use `.combine` + role label.

---

### SharedCommunityBanner + SharedCommunityBannerHero

**File:** `AMENAPP/AMENAPP/Spaces/SharedComponents/SharedCommunityBanner.swift`

Two distinct styles of cross-community banner.

**Pill style** (compact — use in tile rows and composer):
```swift
SharedCommunityBanner(mode: .sharedWith(communityName: String))
SharedCommunityBanner(mode: .membersFrom(count: Int, communityName: String))
```

**Hero style** (expanded — use at top of SpaceDetailView header):
```swift
SharedCommunityBannerHero(
    communityName: String,
    communityAvatarURL: String?,      // nil → initials fallback via SpaceAvatarView
    externalMemberCount: Int,
    spaceType: AmenSpace.SpaceType
)
```

- Both styles use `LinkedGlyph(size: .small)` / `LinkedCommunityGlyph(size: 16, ...)`.
- `reduceTransparency`: uses `surfaceChip` / `surfaceCard` fill.
- Accessibility: `.combine` element with full label text.

---

## §2 Navigation Shell API (Agents B, D, E, F: entry points below)

All Shell files live in `AMENAPP/Spaces/Shell/`.

---

### SpacesRootView

**File:** `AMENAPP/AMENAPP/Spaces/Shell/SpacesRootView.swift`

Top-level Spaces tab view. Mounted in `ContentView` at tab index 7, gated on `SpacesFeatureFlags.shared.spacesLiquidGlassEnabled` (default OFF).

- **iPhone**: `NavigationStack` + community avatar button in toolbar → sheet with community switcher list.
- **iPad**: `NavigationSplitView` with `CommunitySwitcherView` in sidebar (64pt column).
- Loads communities via `SpacesService.shared.fetchMyCommunities()` on `.task`.
- Selects first community by default; spring-animates community switch.
- Hosts `SpaceCreationWizardPlaceholder` (replace: `SpaceCreationWizard(communityId:)` when Agent D is ready).

**Agent D wiring point:**
```swift
// In SpacesRootView.body → .sheet(isPresented: $showCreationWizard)
// Replace: SpaceCreationWizardPlaceholder()
// With:    SpaceCreationWizard(communityId: selectedCommunityId)
```

---

### CommunitySwitcherView

**File:** `AMENAPP/AMENAPP/Spaces/Shell/CommunitySwitcherView.swift`

Vertical column of community avatar circles. Active: `amenPurple` ring + 1.05 scale. Long-press: community name tooltip via `.popover`. Bottom "+" button → `CommunityCreateSheet`.

```swift
CommunitySwitcherView(
    selectedCommunityId: Binding<String>,
    communities: [SpacesCommunity],
    unreadByCommunity: [String: Int]   // communityId → unread count for badge dot
)
```

---

### SpacesListView

**File:** `AMENAPP/AMENAPP/Spaces/Shell/SpacesListView.swift`

Filter pill list for a community's Spaces. Uses `SpacesShellViewModel` for state.

```swift
SpacesListView(
    communityId: String,
    onStartSomething: (() -> Void)? = nil   // Agent D wires creation wizard here
)
```

- Filter pills: `All | VIP | Unreads | External` via `SpaceListFilter.allCases`.
- `SpaceListTile`: `SpaceAvatarView` + lock badge (paid, no entitlement) + type icon + `LinkedGlyph`.
- Tapping a free Space → `navigationDestination` to `SpaceDetailView`.
- Tapping a paid Space without entitlement → `LockedPreviewShell` sheet.
- FAB: gold circle with plus → `onStartSomething?()`.
- Pull-to-refresh supported via `.refreshable`.
- **Placeholder structs** (delete when wired):
  - `SpaceCreationWizardPlaceholder` — replaced by Agent D
  - `SpacesChatViewPlaceholder` — replaced by Agent B
  - `SpaceLockedPlaceholder` — replaced by Agent E
- **Agent D wiring point**: pass `onStartSomething` callback from `SpacesRootView`.
- **Agent E wiring point**: replace `lockedSpaceTarget` sheet content with purchase UI.

**`AmenSpace.SpaceType` display helpers** (extensions defined in this file):
- `.displayName: String` — "Chat" | "Bible Study" | "Group" | "Announcements"
- `.systemImageName: String` — SF Symbol name for each type

---

### SpaceDetailView

**File:** `AMENAPP/Spaces/Shell/SpaceDetailView.swift` (pre-existing — Agent C did not modify)

Agent C's `SpaceDetailView` entry point signature for reference:
```swift
SpaceDetailView(space: AmenSpace, communityId: String)
```

Uses `SharedCommunityBannerHero` for the cross-community banner in the hero header.
Uses `ExternalMemberRoster` (via `MemberRosterSheet`) for the member list.
Uses `LockedPreviewShell` for the paywall gate.

---

### CommunityCreateSheet

**File:** `AMENAPP/AMENAPP/Spaces/Shell/CommunityCreateSheet.swift`

Minimal community creation: name, handle (auto-slug), avatar `PhotosPicker`. Spring dismiss.

```swift
CommunityCreateSheet(
    isPresented: Binding<Bool>,
    onCreated: ((String) -> Void)? = nil   // called with new communityId on success
)
```

- Writes `amenCommunities/{communityId}` + `members/{userId}` with role "owner".
- Tries `SpacesCallable.createCommunity` Firebase callable first.
- Falls back to direct Firestore write if callable not yet deployed (pre-deploy testing only — **remove fallback after callable deployment**).
- Does NOT configure Stripe Connect — Agent E handles that post-creation.

---

## §3 Tab Bar Integration

**AMENTabBar.swift** additions:
- `AMENTab.spaces` (rawValue 7): `activeIcon: "house.and.flag.fill"`, label: "Spaces"
- `AMENBadgeCounts.spaces: Int = 0`
- `centerTabs`: appends `.spaces` only when `spacesFlags.spacesLiquidGlassEnabled == true`

**ContentView.swift** addition:
```swift
// Tab 7: Spaces
keepMountedTab(isActive: viewModel.selectedTab == AMENTab.spaces.rawValue) {
    SpacesRootView()
        .id("spaces")
        .task { NotificationAggregationService.shared.updateCurrentScreen(.none) }
}
```

Flag default is `false` — Spaces tab is invisible until enabled via `SpacesFeatureFlags.shared.spacesLiquidGlassEnabled = true`.

---

## §4 Key Data Types (from SpacesModels.swift — canonical Agent A types)

```swift
struct SpacesCommunity: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var name: String; var handle: String; var avatarURL: String?
    var ownerUserId: String; var stripeConnectAccountId: String?; var createdAt: Timestamp
}

struct AmenSpace: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var communityId: String; var type: SpaceType; var title: String
    var description: String?; var avatarURL: String?; var createdBy: String
    var createdAt: Timestamp; var accessPolicy: AccessPolicy
    var priceConfig: SpacePriceConfig?; var sharedWith: [String]
    enum SpaceType: String, Codable, CaseIterable { case chat, bibleStudy, group, announcement }
    enum AccessPolicy: String, Codable, CaseIterable { case free, oneTime, recurring }
}

struct SpaceMember: Identifiable, Codable {
    @DocumentID var id: String?    // = userId
    var role: SpaceMemberRole; var homeCommunityId: String  // "" = same community
    var access: SpaceAccess; var joinedAt: Timestamp
}
enum SpaceMemberRole: String, Codable, CaseIterable { case owner, admin, member }
enum SpaceAccess: String, Codable, CaseIterable { case granted, none }
```

---

## §5 Known Gaps / Deploy Steps Required

| Gap | Severity | Owner | Notes |
|-----|----------|-------|-------|
| `createCommunity` Cloud Function not deployed | P1 | Backend | `CommunityCreateSheet` has direct-Firestore fallback for pre-deploy. Remove fallback after deploy. |
| `SpacesService.shared.createCommunity()` absent | P2 | Agent A | CommunityCreateSheet calls Firebase callable directly. Agent A should add a service method. |
| `AmenRoute` missing `.spaces` case | P2 | Navigation | `route(for:)` in AMENTabBar has no `.spaces` case — falls through to `default`. Add `.spaces → AmenRoute.spaces` when navigation routing is extended. |
| `SpacesCallable.createCommunity.rawValue` must match deployed function name | P1 | Backend + Agent A | Verify the deployed function name matches `SpacesCore.swift`. |

---

## §6 Design Constraints Honoured

- No Combine — all async/await only.
- No hard-deletes — Spaces tab is additive; existing tab indices 0–6 unchanged.
- No "church" strings — community-centric language throughout.
- All tokens from `AmenTheme.Colors` and `LiquidGlassTokens`.
- `reduceTransparency` and `reduceMotion` respected in all components.
- No paywall UI — `LockedPreviewShell` + placeholder only; Agent E owns purchase flow.
- No creation wizard — `SpaceCreationWizardPlaceholder` only; Agent D owns creation wizard.
- `SpacesCommunityModels.swift` types (`AmenSpaceExtended`, `AmenCommunity`) are untouched — Shell files use `SpacesModels.swift` canonical types.

---

## §7 Files Delivered

| File | Status | Diagnostics |
|------|--------|-------------|
| `spaces-spec/AUDIT_C.md` | Created | N/A |
| `spaces-spec/CONTRACT_C.md` | Created | N/A |
| `AMENAPP/AMENAPP/Spaces/SharedComponents/LinkedCommunityGlyph.swift` | Created | 0 errors, 0 warnings |
| `AMENAPP/AMENAPP/Spaces/SharedComponents/SpaceAvatarView.swift` | Created | 0 errors, 0 warnings |
| `AMENAPP/AMENAPP/Spaces/SharedComponents/ExternalMemberRoster.swift` | Created | 0 errors, 0 warnings |
| `AMENAPP/AMENAPP/Spaces/SharedComponents/SharedCommunityBanner.swift` | Modified (added Hero style) | 0 errors, 0 warnings |
| `AMENAPP/AMENAPP/Spaces/Shell/SpacesRootView.swift` | Created | 0 errors, 0 warnings |
| `AMENAPP/AMENAPP/Spaces/Shell/CommunitySwitcherView.swift` | Created | 0 errors, 0 warnings |
| `AMENAPP/AMENAPP/Spaces/Shell/SpacesListView.swift` | Created | 0 errors, 0 warnings |
| `AMENAPP/AMENAPP/Spaces/Shell/CommunityCreateSheet.swift` | Created | 0 errors, 0 warnings |
| `AMENAPP/AMENTabBar.swift` | Modified (Spaces tab + badge + flag guard) | 0 errors, 0 warnings |
| `AMENAPP/ContentView.swift` | Modified (keepMountedTab for Spaces) | 0 errors, 0 warnings |

---

AGENT_C_COMPLETE
