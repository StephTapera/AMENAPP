# Agent C — Spaces Shell + Shared Design Components

> Read `00_MASTER_CONTRACT.md`, `CONTRACT_A.md`, and `CONTRACT_B.md` first. Do NOT start
> wiring until A is complete. You build the navigation shell that all other agents render
> into, and you OWN the shared cross-community design components. Project root:
> `~/Desktop/AMEN/AMENAPP copy/`, workspace `AMENAPP.xcworkspace`.

## Your mandate

### Step 1 — AUDIT FIRST (gap report before changing anything)

Inventory existing navigation + community shell:
- Look in `AMENAPP/AMENAPP/CommunicationOS/BereanCommunicationHubView.swift` — is this
  the existing hub? What navigation structure does it use?
- Check for any existing `CommunityListView`, `SpacesListView`, or similar.
- Look at `AMENAPP/AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift` — what
  shared glass components already exist? Can any be reused?
- Check how existing tab/filter navigation works (All/Unreads etc.) in the communication
  layer.
- Identify the design token source file (colors, materials). This is the ONE file you
  extend for shared tokens. Do not create a second.

Produce a gap report before changing anything.

### Step 2 — Shared design components (Agent C owns these, nobody else edits them)

**`AMENAPP/AMENAPP/Spaces/SharedComponents/SpacesDesignTokens.swift`**

Add/extend (do not replace) the shared token source:
```swift
// If AmenLiquidGlassComponents.swift is the token source, extend it.
// Otherwise create SpacesDesignTokens.swift.
// Required tokens:
extension Color {
    static let amenGold = Color("AmenGold")       // only if not already defined
    static let amenPurple = Color("AmenPurple")
    static let amenBlue = Color("AmenBlue")
    static let amenBlack = Color("AmenBlack")
}
// Required materials: ultraThinMaterial (system), no custom materials
```

**`AMENAPP/AMENAPP/Spaces/SharedComponents/LinkedCommunityGlyph.swift`**
```swift
// The "evident" cross-community badge — interlocking rings in amenPurple over ultraThinMaterial.
// Used on: shared Space tiles, external member avatars, the banner pill.
// Parameters: size: CGFloat, onTap: (() -> Void)?
// Tapping shows a small popover: "Shared with [Community Name]"
// Accessibility: label "Shared community", hint "Tap to see details"
struct LinkedCommunityGlyph: View { ... }
```

**`AMENAPP/AMENAPP/Spaces/SharedComponents/SharedCommunityBanner.swift`**
```swift
// Glass pill shown at top of shared Spaces and in the composer.
// "This [Space type] is shared with [Community Name]"
// "N members are from [Community Name]"
// Uses hero-profile header style: community avatar + name + glyph.
// Parameters: communityName, communityAvatarURL, externalMemberCount, spaceType
struct SharedCommunityBanner: View { ... }
```

**`AMENAPP/AMENAPP/Spaces/SharedComponents/ExternalMemberRoster.swift`**
```swift
// Member sheet component that sections external members under their home community.
// Parameters: members: [SpaceMember] (from CONTRACT_A schema)
// Renders own-community members first, then one section per external community.
// Each external section header shows that community's name + LinkedCommunityGlyph.
struct ExternalMemberRoster: View { ... }
```

**`AMENAPP/AMENAPP/Spaces/SharedComponents/SpaceAvatarView.swift`**
```swift
// Space avatar: circular image or initials fallback, with optional LinkedCommunityGlyph
// overlay in the bottom-right corner when the Space is shared.
// Parameters: avatarURL: String?, title: String, size: CGFloat, isShared: Bool
struct SpaceAvatarView: View { ... }
```

### Step 3 — Community + Spaces navigation shell

**`AMENAPP/AMENAPP/Spaces/Shell/SpacesRootView.swift`**

Top-level view. Layout:
- Left/leading sidebar (iPad) or bottom tab (iPhone): community switcher — avatar circles
  for each community the user belongs to, + button for "create or join a community."
- Right/main area: `SpacesListView` for the selected community.
- Liquid Glass nav bar, ultraThinMaterial background.
- Spring animation on community switch.

**`AMENAPP/AMENAPP/Spaces/Shell/SpacesListView.swift`**

The Slack-style channel list for a community:
- Filter pill row at top: **All | VIP | Unreads | External**
  - **All**: all Spaces the user is a member of.
  - **VIP**: Spaces with `filterSignals.isVIP == true`.
  - **Unreads**: Spaces with `filterSignals.hasUnread == true`.
  - **External**: Spaces with `filterSignals.hasExternalMembers == true` (shared Spaces).
- Each Space tile: `SpaceAvatarView` + title + type badge + unread dot + latest preview.
  - If `space.sharedWith` is non-empty, show `LinkedCommunityGlyph` on the tile.
  - Paid Space tiles show a lock icon (amenGold) if user lacks entitlement.
- Tap → `SpaceDetailView`.
- Pull to refresh, Firestore real-time listener.
- "Start something" FAB (+ button) → triggers Agent D's creation wizard.

**`AMENAPP/AMENAPP/Spaces/Shell/SpaceDetailView.swift`**

The room view for a selected Space:
- **Hero header**: `SpaceAvatarView` + title + type badge + member count.
  - If shared: `SharedCommunityBanner` below the header.
- **Paywall gate**: if Space is paid and user has no active entitlement, show
  `SpaceLockedView` (implemented by Agent E). `SpaceDetailView` checks entitlement
  state from Agent E's `SpacesEntitlementService` and routes accordingly.
- **Content area**: switches on `space.type`:
  - `chat` / `group` → embed Agent B's chat view (`SpacesChatView` — a view B exposes).
  - `bibleStudy` → embed the study view (B's chat + study blocks from SCN model).
  - `announcement` → read-only message list.
- **Members button**: sheet → `ExternalMemberRoster`.
- **Settings** (owner/admin only): edit title, access policy, link another community.

**`AMENAPP/AMENAPP/Spaces/Shell/CommunitySwitcherView.swift`**

Vertical column of community avatar circles:
- Tap switches active community.
- Long-press shows community name tooltip (glass bubble).
- Bottom: "+" → `CommunityCreateSheet` (minimal: name, handle, avatar upload).
- Active community highlighted with amenPurple ring.
- Notification badge overlay on communities with unread activity.

### Step 4 — Community create sheet

**`AMENAPP/AMENAPP/Spaces/Shell/CommunityCreateSheet.swift`**
```swift
// Minimal community creation: name, handle (auto-slug from name), avatar pick.
// Does NOT include Stripe Connect setup (that's Agent E after creation).
// On create: writes communities/{communityId} + members/{userId} with role "owner".
// Uses existing Firebase Storage for avatar upload.
// Liquid Glass sheet, spring dismiss.
```

### Step 5 — Integrate into existing AMEN navigation

Find where AMEN's main navigation lives (likely `ContentView.swift` or the main tab bar).
Add "Spaces" as a tab (or the primary hub if appropriate) that routes to `SpacesRootView`.
Do NOT reorganize other tabs — additive only. Use the existing navigation pattern.

---

## Hard constraints

- Shared components (glyph, banner, roster) live here. B/D/E/F IMPORT them. Never
  re-implement. If another agent needs to modify them, it must flag it as a shared-file
  conflict and not edit unilaterally.
- Design tokens: extend the existing token source, do not create a competing one.
- No Combine. Async/await only.
- No hard-deletes.
- No "church" in any string, label, or enum.
- `SpaceDetailView` does NOT implement the paywall UI — it imports Agent E's view.
- `SpaceDetailView` does NOT implement the creation wizard — it calls Agent D's entry point.

---

## Deliverables

1. `AMENAPP/AMENAPP/Spaces/SharedComponents/LinkedCommunityGlyph.swift`
2. `AMENAPP/AMENAPP/Spaces/SharedComponents/SharedCommunityBanner.swift`
3. `AMENAPP/AMENAPP/Spaces/SharedComponents/ExternalMemberRoster.swift`
4. `AMENAPP/AMENAPP/Spaces/SharedComponents/SpaceAvatarView.swift`
5. `AMENAPP/AMENAPP/Spaces/SharedComponents/SpacesDesignTokens.swift` (or extension to existing)
6. `AMENAPP/AMENAPP/Spaces/Shell/SpacesRootView.swift`
7. `AMENAPP/AMENAPP/Spaces/Shell/SpacesListView.swift`
8. `AMENAPP/AMENAPP/Spaces/Shell/SpaceDetailView.swift`
9. `AMENAPP/AMENAPP/Spaces/Shell/CommunitySwitcherView.swift`
10. `AMENAPP/AMENAPP/Spaces/Shell/CommunityCreateSheet.swift`
11. Additive change to main navigation to expose Spaces tab.
12. **`spaces-spec/CONTRACT_C.md`** — shared component APIs (parameter lists + usage notes),
    shell navigation entry points D/E/F need to hook into.

---

## Done when

- All Swift files build with zero diagnostics.
- `SpacesListView` shows filter pills, linked glyph on shared tiles, unread indicators.
- `SpaceDetailView` routes correctly on space type and entitlement state.
- `CONTRACT_C.md` published ending with "AGENT_C_COMPLETE".
