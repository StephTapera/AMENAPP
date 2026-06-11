# AMEN Connect — Wave 0 Frozen Contracts

**Status:** FROZEN — 2026-06-10  
**Version:** connect-ui-polish-v1  
**Authority:** Do not modify without Lead Orchestrator sign-off and rebroadcast to every wave agent.

---

## C-1 · Bottom Chrome Inset Contract

**Single source of truth:** `ConnectChromeMetrics` (in `ConnectWave0UIContracts.swift`)

| Layer | Height |
|---|---|
| Tab bar | 49 pt |
| Ask Berean pill | 50 pt |
| Breathing margin | 16 pt |
| **Total `bottomInset`** | **115 pt** |

**Rule:** Every `ScrollView` in the Connect module **must** consume `ConnectChromeMetrics.bottomInset`
via `.safeAreaInset(edge: .bottom)` or `.contentMargins(.bottom, ConnectChromeMetrics.bottomInset)`.  
Hard-coded `.padding(.bottom, 92)` or similar literal offsets are **forbidden** once Wave 1 ships.

**Current violation to fix in Wave 1:** `AmenConnectRootView` (line 50) uses `.padding(.bottom, 92)`.

---

## C-2 · Canonical AI Disclosure String

**Single source of truth:** `ConnectStrings.aiSummaryDisclosure` (in `ConnectWave0UIContracts.swift`)

> "AI summaries include only content you can access. Private, paid, confidential, youth-protected, deleted, and admin-excluded content is never included."

**Rule:** This exact localized string (`connect.ai.disclosure`) is the **only** permitted AI
disclosure text in the Connect module. Delete on sight:

- `AmenConnectView.swift` line 194 — divergent variant ("AI-assisted summaries exclude private…")
- `AmenConnectView.swift` line 678 — divergent variant ("AI-assisted summaries include only content you have access to. Paid, private…")

Both must be replaced with `ConnectStrings.aiSummaryDisclosure`.

---

## C-3 · `ConnectEmptyStateView` GlassKit Component

**Defined in:** `ConnectWave0UIContracts.swift`

**Signature:**
```swift
ConnectEmptyStateView(
    icon: String,                       // SF Symbol name
    title: String,
    message: String,
    primaryCTA: ConnectCTAConfig,
    secondaryCTA: ConnectCTAConfig?,    // optional
    ghostPreview: AnyView?              // optional blurred sample content
)
```

**Rules:**
- CTA buttons use `.amenGlassEffect(in: Capsule())` — never `.regularMaterial` or `.ultraThinMaterial`
- Entrance animation: `AmenMotion.cardAnimation()` with Reduce Motion crossfade fallback
- No glass-on-glass: this component is placed on a content layer, never on a glass surface

---

## C-4 · `SkeletonCard` + `SkeletonRail` GlassKit Components

**Defined in:** `ConnectWave0UIContracts.swift`

- `SkeletonCard(aspectRatio:)` — single card placeholder
- `SkeletonRail(cardCount:)` — horizontal row of N skeleton cards

**Rules:**
- Under `accessibilityReduceMotion == true`: static placeholder with tinted fill, no animation
- Under normal motion: shimmer gradient (leading-to-trailing) at 1.4 s period, infinite repeat
- Both components carry `.accessibilityLabel("Loading")` and `.accessibilityHidden(true)` on the shimmer layer

---

## C-5 · Navigation Ownership Contract

### Decision

**Bottom tab bar** (primary router — 5 fixed tabs):

| Tab | Icon | Owns |
|---|---|---|
| Home | `house` | Feed |
| Search | `magnifyingglass` | Search/Discover |
| Messages | `bubble.left.and.bubble.right` | DMs, group chats, requests |
| Resources | `tray.2` | Amen Connect dashboard |
| Profile | `person` | User profile |

**Connect pill row** (section switcher — view-scoped to Resources/Connect):

| Pill | Maps to |
|---|---|
| Lobby | Dashboard overview |
| Discover | Space/creator discovery |
| Spaces | My spaces list |
| Activity | Notifications/Pulse |

**DMs is removed from the Connect pill row.** DMs is owned exclusively by the Messages bottom tab.
The 14-room switcher in `AmenConnectRoomSwitcher` is trimmed to these 4 sections in Wave 1.
Rooms (Announcements, Discussions, Meetings, Calendar, Boards, Marketplace, Creators, Safety, Admin)
become sub-navigation **within** their parent section, not top-level switcher pills.

### Active Tab Invariant
The highlighted tab must always match the rendered view. Navigating to the Connect dashboard
via the Resources tab highlights Resources. This is enforced by state binding in the root
`ContentView` tab selection — Connect never manages bottom tab highlight state itself.

---

## Glass Surface Rules (applies to all waves)

1. **Native glass only.** Use `.amenGlassEffect()` (shim for `.glassEffect()` on iOS 26) or
   `GlassEffectContainer` + `.glassEffectID()`. Never use `.ultraThinMaterial`, `.thinMaterial`,
   `.regularMaterial`, or blur/opacity stacks to fake glass.
2. **No glass-on-glass.** A glass surface may not sit directly on another glass surface. Flatten
   the lower layer to a tinted `Color` or `Color(.systemBackground)` background.
3. **Detect violations:** search for nested `.amenGlassEffect` or `GlassEffectContainer` ancestry
   in the view tree after each wave.

**Current violations in existing Connect code (fix in Wave 1/2 as part of migration):**
- `AmenConnectLiquidGlassSurface` uses `.ultraThinMaterial`/`.thinMaterial`/`.regularMaterial` — migrate to `.amenGlassEffect()`
- `AmenConnectSpacesHubView` `sectionHeader()` uses `.ultraThinMaterial` — migrate
- `LiveSpaceCardRow` / `SpaceCardRow` / `VideoCardRow` use `.ultraThinMaterial` — migrate
- `AmenConnectSpaceListView` empty-state CTA uses `.regularMaterial` — replace with `ConnectEmptyStateView`

---

*Frozen 2026-06-10. Next revision requires Wave 0 re-run.*
