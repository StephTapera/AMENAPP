# 02 — Spaces Design System Audit

**File:** `AMENAPP/Spaces/DesignSystem/SpacesDesignSystem.swift`
**Agent:** Agent 2 — AMEN Design System Architect
**Date:** 2026-05-28

All color tokens are sourced from `AmenTheme.Colors`. All corner radii from `LiquidGlassTokens`. All animation constants reference `Motion.*` directly — no redeclarations. No iOS 26 API used.

---

## Components

### 1. `SpaceHeroView`

| Prop | Type | Notes |
|---|---|---|
| `space` | `AmenSpaceExtended` | Required. Drives tint color, fallback gradient, action label |
| `verseOverlay` | `String?` | Optional scripture line above title. `.caption.italic()` in `amenGold` |
| `pageIndex` | `Int` | 0-based carousel position. Drives dot indicator |
| `totalPages` | `Int` | Total dots. Dots hidden when `totalPages <= 1` |
| `onJoin` | `() -> Void` | Called by primary pill button |
| `onSave` | `() -> Void` | Called by circular bookmark button |

**Hero tint logic** (from `space.type`):
- `.bibleStudy` → `amenGold`
- `.chat` / `.group` → `amenPurple`
- `.announcement` → `amenBlue`

**Timing constants:**
- Page dot animation: `Motion.popToggle` (response 0.20, dampingFraction 0.56)
- Hero spring (caller-driven carousel): `Motion.liquidSpring` (iOS 17+: `.bouncy(duration: 0.4, extraBounce: 0.1)`, fallback: `response 0.40, dampingFraction 0.72`)
- Reduced-motion: `Motion.popToggle` gated behind `@Environment(\.accessibilityReduceMotion)`. No parallax, no dot animation.

**Structure:**
- `AsyncImage` fills frame (minHeight 280pt), `.fill` aspect, clipped to `cornerRadiusLarge` (32)
- `scrimGradient`: `amenBlack` at 0 → 0.30 → 0.85 opacity (bottom-up)
- Verse overlay: `.caption.italic()` in `amenGold`, 1-line limit
- Title: `.title2.bold()` in `textPrimary`
- `SpaceFaithMetadataRow` directly beneath title
- `AMENGlassPillButton` (primary) + circular bookmark button
- Hero tint bleed layer: `heroTint.opacity(0.07)` over entire card surface
- `cornerRadiusLarge` (32) clip + `shadowFloating` drop shadow

**Why this reads as AMEN, not Apple:**
The hero tint layer bleeds the Space's AMEN brand color (gold or purple) into the glass surface rather than relying on a neutral white material. The verse overlay in `amenGold` italic and the faith-native metadata row ("Bible Study · 1 member · KJV") make clear this is a spiritual context — not a video streaming card.

---

### 2. `SpaceFaithMetadataRow`

| Prop | Type | Notes |
|---|---|---|
| `spaceType` | `SpaceV2Type` | Always shown. Drives first chip's icon and label |
| `memberCount` | `Int` | Hidden when 0 |
| `bibleVersion` | `String?` | e.g. "KJV", "NIV". Only shown for bibleStudy via hero |
| `liturgicalSeason` | `String?` | e.g. "Advent", "Lent" |
| `churchBadge` | `ChurchBadgeChip.Badge?` | Custom badge from caller |

**Timing constants:** None (static layout). Chips appear via `staggeredReveal` if used inside `SpaceRailView`.

**Separator:** `" · "` rendered as `Text` in `.caption.bold()` + `amenGold` — not a gray dot.

**Why this reads as AMEN, not Apple:**
The gold `·` separator and faith-specific chip labels ("Bible Study", "Advent", "KJV") make this contextually Christian. A generic streaming UI would show "Drama · 12 episodes" — this shows "Bible Study · 42 members · KJV · Advent".

---

### 3. `ChurchBadgeChip`

| Prop | Type | Notes |
|---|---|---|
| `badge.icon` | `String` | SF Symbol name |
| `badge.label` | `String` | Pill label text |
| `badge.tint` | `Color` | Must be an `AmenTheme.Colors` value; used for icon tint and glass bleed |

**Sizing:** 6pt vertical / 10pt horizontal padding. `cornerRadiusMedium` (22) corner radius.

**Glass construction:**
- `.ultraThinMaterial` base
- `badge.tint.opacity(0.10)` overlay (tint bleed into glass)
- `glassStroke` 0.75pt border
- `reduceTransparency` path: `surfaceCard` flat fill

**Timing constants:** None (static chip).

**Why this reads as AMEN, not Apple:**
The icon always renders in `amenGold` (not the chip's `tint` color), so every chip has a consistent gold gleam regardless of context — matching the gold accent language used throughout AMEN's prayer, study, and reaction surfaces.

---

### 4. `AMENGlassPillButton`

| Prop | Type | Notes |
|---|---|---|
| `title` | `String` | Button label |
| `icon` | `String?` | SF Symbol, optional |
| `style` | `Style` | `.primary`, `.secondary`, `.prominent` |
| `action` | `() -> Void` | Tap handler |

**Styles:**
| Style | Fill | Text | Stroke |
|---|---|---|---|
| `.primary` | `amenGold` | `amenBlack` | `glassStroke` 0.5pt |
| `.secondary` | `.ultraThinMaterial` + `amenGold.opacity(0.08)` | `amenGold` | `amenGold` 1.0pt |
| `.prominent` | `amenPurple` | `textPrimary` | `amenPurple.opacity(0.40)` 0.5pt |

**Timing constants:**
- Press: `AmenPressStyle` from `Motion.swift` — `Motion.springPress` (response 0.22, dampingFraction 0.88) at 0.96 scale
- Release: `AmenPressStyle` handles snap-back automatically
- Reduced-motion: `AmenPressStyle` respects `@Environment(\.accessibilityReduceMotion)` — no scale, only opacity pulse

**Note:** `AMENGlassPillButton` delegates capsule surface logic to `AmenPressStyle` (from Motion.swift). It is a thin style-aware wrapper, not a duplicate of `AmenLiquidGlassPillButton`. Use `AmenLiquidGlassPillButton` when you need the frosted capsule glass surface with `symbolEffect`; use `AMENGlassPillButton` when you need AMEN branded fill colors.

**Why this reads as AMEN, not Apple:**
The `.primary` style fills with `amenGold` and labels in `amenBlack` — the exact inverse of Apple's default dark-on-white pills. The `.prominent` style uses `amenPurple` fill, the same purple used on the Space type chip and member roster. No system blue anywhere.

---

### 5. `AMENGlassCard`

| Prop | Type | Notes |
|---|---|---|
| `width` | `CGFloat` | Default 180 |
| `height` | `CGFloat` | Default 120 |
| `tintColor` | `Color` | Default `amenPurple`. Bleeds into glass surface |
| `content` | `@ViewBuilder () -> Content` | Card body |

**Glass construction:**
- `.ultraThinMaterial` base
- `tintColor.opacity(0.08)` bleed overlay
- Top-edge `LinearGradient` highlight: `glassHighlightTop` → `glassHighlightBottom`, 40% card height
- `glassStroke` 1.0pt border
- `shadowSoft` (color `.black.opacity(0.08)`, radius 14, y 6)
- `cornerRadiusMedium` (22) on all corners

**Timing constants:**
- Press scale: `Motion.springPress` (response 0.22, dampingFraction 0.88) to 0.96
- Reduced-motion: `.none` animation, no scale

**Why this reads as AMEN, not Apple:**
The `tintColor` bleed (amenPurple or amenGold depending on context) gives each card a distinct branded warmth — a plain `ultraThinMaterial` card would look identical on any app. The gold highlight on Bible Study rails vs. purple on community rails provides spiritual context at a glance.

---

### 6. `SpaceRailView`

| Prop | Type | Notes |
|---|---|---|
| `title` | `String` | Faith-native: "Continue Studying", "Your Spaces", "Recommended for your walk", "Trending in your church" |
| `items` | `[Item: Identifiable]` | Generic |
| `card` | `@ViewBuilder (Item) -> CardContent` | Card renderer |

**Layout:**
- Section header: `.headline.bold()` in `textPrimary` + "See All ›" in `amenGold`
- `ScrollView(.horizontal)` + `LazyHStack(spacing: 16)`, 20pt leading/trailing inset
- Each card receives `.staggeredReveal(index:baseDelay:0.04 maxDelay:0.20)` from `Motion.swift`

**Timing constants:**
- Stagger: `Motion.appearEase` (`.easeOut(duration: 0.24)`) per item via `StaggeredReveal` modifier
- `baseDelay`: 0.04s between items; `maxDelay`: 0.20s cap
- Reduced-motion: `Motion.adaptive()` in `StaggeredReveal` returns `.easeInOut(0.16)` with no offset

**Why this reads as AMEN, not Apple:**
The section labels are spiritually-native ("Continue Studying", "Trending in your church") rather than content-category neutral ("Continue Watching", "Popular on TV+"). The "See All ›" affordance uses `amenGold` — signaling a secondary AMEN action, not a default system tint link.

---

### 7. `AMENGlassTabBar`

| Prop | Type | Notes |
|---|---|---|
| `selectedTab` | `@Binding<SpacesTab>` | Drives active state |
| `scrollOffset` | `CGFloat` | 0 = top; positive = scrolled. Drives blur boost and label collapse |

**Tabs:**
| Case | Icon | Label |
|---|---|---|
| `.feed` | `house.fill` | "Feed" |
| `.study` | `book.fill` | "Study" |
| `.prayer` | `hands.sparkles.fill` | "Prayer" |
| `.spaces` | `rectangle.3.group.fill` | "Spaces" |
| `.search` | `magnifyingglass` | "Search" |

**Scroll-driven behavior:**
- `scrollOffset` 0→100pt maps to a 0→0.15 glass opacity boost
- Labels collapse at `scrollOffset >= 60` pt via `Motion.liquidSpring`
- Reduced-motion: labels always shown; no glass opacity animation; static blur level

**Timing constants:**
- Tab switch: `Motion.popToggle` (response 0.20, dampingFraction 0.56)
- Active dot `matchedGeometryEffect` glides: driven by `Motion.popToggle` on `isActive`
- Bar contract/expand: `Motion.liquidSpring` (iOS 17+: `.bouncy(duration: 0.4, extraBounce: 0.1)`)
- Reduced-motion: `.none` in place of all three

**Active state:** `amenGold` icon + label + 2pt underline dot. Inactive: `textSecondary`.

**Glass:** `Capsule(.ultraThinMaterial)` + `glassFill.opacity(scrollBlurBoost)` overlay + `glassStroke` 0.75pt border + `shadowFloating`.

**Why this reads as AMEN, not Apple:**
`hands.sparkles.fill` ("Prayer") and `book.fill` ("Study") are spiritually-native tab icons that have no equivalent in a streaming or social product. The `amenGold` active state replaces the system tint blue that would appear in a plain iOS tab bar. The bar floats with `shadowFloating` rather than sitting flush against the safe area edge, giving it the premium Liquid Glass feel.

---

### 8. `GlassSheetModifier`

| Prop | Type | Notes |
|---|---|---|
| `tintColor` | `Color` | Default `amenPurple`. Use `amenGold` for Bible Study sheets |

**Extension:**
```swift
func amenGlassSheet(tint: Color = AmenTheme.Colors.amenPurple) -> some View
```

**Glass construction:**
- `.ultraThinMaterial` base + `tintColor.opacity(0.05)` tint bleed
- `glassStroke` 0.75pt border on top two corners only
- `cornerRadiusLarge` (32) top corners, 0 bottom corners (flush to screen edge)
- Drag indicator: 36×4pt pill in `glassStroke`

**Specular sweep:**
- A thin (2pt) horizontal `LinearGradient` band (`tintColor + glassHighlightTop`) traverses left-to-right over 500ms `.easeOut`
- `specularProgress` drives both x-offset and fade-out opacity (1.0 → 0.2)
- Skipped entirely when `reduceMotion` is true

**Rubber-band dismiss:**
- `DragGesture(minimumDistance: 10)` tracks downward drag
- Offset = `sqrt(dragOffset) * 3.5` — stiff logarithmic resistance, matches iOS sheet feel
- `.onEnded`: `withAnimation(Motion.liquidSpring) { dragOffset = 0 }` — canonical bouncy snap-back

**Timing constants:**
- Specular sweep: `.easeOut(duration: 0.50)`
- Rubber-band snap-back: `Motion.liquidSpring` (iOS 17+: `.bouncy(duration: 0.4, extraBounce: 0.1)`)
- Reduced-motion: specular sweep skipped; snap-back still uses `Motion.liquidSpring` (non-visual, safe)

**Why this reads as AMEN, not Apple:**
The tint bleed (purple for community context, gold for study context) means every sheet immediately communicates its spiritual role. The specular sweep is tinted with the context color rather than pure white, so it reads as a faith-brand flourish rather than a generic iOS presentation animation.

---

## Token Reference Summary

| Token | Value | Source |
|---|---|---|
| `LiquidGlassTokens.cornerRadiusMedium` | 22 pt | LiquidGlassTokens.swift |
| `LiquidGlassTokens.cornerRadiusLarge` | 32 pt | LiquidGlassTokens.swift |
| `LiquidGlassTokens.shadowSoft` | black 0.08, radius 14, y 6 | LiquidGlassTokens.swift |
| `LiquidGlassTokens.shadowFloating` | black 0.12, radius 24, y 10 | LiquidGlassTokens.swift |
| `Motion.liquidSpring` | iOS 17: `.bouncy(duration:0.4, extraBounce:0.1)` / fallback `response:0.4, dampingFraction:0.72` | Motion.swift |
| `Motion.springPress` | `response:0.22, dampingFraction:0.88` | Motion.swift |
| `Motion.springRelease` | `response:0.26, dampingFraction:0.72` | Motion.swift |
| `Motion.popToggle` | `response:0.20, dampingFraction:0.56` | Motion.swift |
| `Motion.appearEase` | `.easeOut(duration:0.24)` | Motion.swift |
| `AmenTheme.Colors.amenGold` | `Color(red:0.83, green:0.69, blue:0.22)` | AmenTheme.swift |
| `AmenTheme.Colors.amenPurple` | `Color(red:0.44, green:0.26, blue:0.80)` | AmenTheme.swift |
| `AmenTheme.Colors.amenBlue` | `Color(red:0.04, green:0.52, blue:1.0)` | AmenTheme.swift |
| `AmenTheme.Colors.amenBlack` | `Color(red:0.06, green:0.06, blue:0.07)` | AmenTheme.swift |
| `AmenTheme.Colors.glassStroke` | dark: white 0.16α / light: white 0.55α | AmenTheme.swift |
| `AmenTheme.Colors.glassHighlightTop` | dark: white 0.10α / light: white 0.55α | AmenTheme.swift |

---

## Accessibility checklist

- All interactive elements carry `.accessibilityLabel` and `.accessibilityHint`
- `SpaceFaithMetadataRow` collapses to a single `.accessibilityElement(children:.combine)` label
- `AMENGlassTabBar` tabs carry `.isSelected` trait when active
- Dot indicators, decorative gradients, and tint bleed layers are `.accessibilityHidden(true)` or `.allowsHitTesting(false)`
- Every `@Environment(\.accessibilityReduceMotion)` path tested: springs → `.none`; specular sweep → skipped; label collapse → always shown
- Every `@Environment(\.accessibilityReduceTransparency)` path: materials → opaque `surfaceCard` / `surfaceElevated` fills

---

## Prohibited patterns (confirmed absent)

- `.glassEffect()` — not used
- `GlassEffectContainer` — not used
- `glassEffectID` — not used
- `@Namespace` for hero morph — not used
- Raw `.blue`, `.purple`, `.yellow`, `.green` system colors — not used
- `import CoreMotion` — not imported (light-tracking sheen not implemented)
