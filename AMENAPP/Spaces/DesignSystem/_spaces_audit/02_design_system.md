# 02 — Spaces Design System Audit

**File:** `AMENAPP/Spaces/DesignSystem/SpacesDesignSystem.swift`
**Agent:** Agent 2 — AMEN Design System Architect
**Updated:** 2026-05-29 (iOS 26 native Liquid Glass rewrite)

All components use **native iOS 26 glass APIs exclusively** — `GlassEffectContainer`, `.glassEffect()`, `glassEffectID + @Namespace`, `.buttonStyle(.glass/.glassProminent)`, `.tint()`. No `.ultraThinMaterial`, no `reduceTransparency` fallback branches (the system handles adaptive opacity automatically). All types carry `@available(iOS 26.0, *)`.

Color tokens: `AmenTheme.Colors` only — `amenGold / amenPurple / amenBlue / amenBlack`.
Spacing / radii: `LiquidGlassTokens.*`.
Animation: `Motion.*` — no inline constant redeclarations.

---

## Components

### 1. `SpaceHeroView`

| Prop | Type | Notes |
|---|---|---|
| `space` | `AmenSpaceExtended` | Required. Drives tint color, fallback gradient, action label |
| `verseOverlay` | `String?` | Optional scripture line above title — `.caption.italic()` in `amenGold` |
| `pageIndex` | `Int` | 0-based carousel position. Drives dot indicator |
| `totalPages` | `Int` | Dots hidden when `totalPages <= 1` |
| `onJoin` | `() -> Void` | Called by primary pill button |
| `onSave` | `() -> Void` | Called by circular bookmark button |

**Hero tint logic** (from `space.type`):
- `.bibleStudy` → `amenGold`
- `.chat` / `.group` → `amenPurple`
- `.announcement` → `amenBlue`

**Action row — native iOS 26 glass morphing:**
The join pill + bookmark button sit inside `GlassEffectContainer(spacing: 12)`. Each carries a `glassEffectID` so SwiftUI can morph the glass region between states (e.g. "Join" → "Leave") without any custom geometry math:
- Primary pill: `AMENGlassPillButton` + `.glassEffectID("primaryAction", in: heroNamespace)`
- Bookmark: `.buttonStyle(.glass).tint(heroTint)` + `.glassEffectID("saveAction", in: heroNamespace)`

**Timing constants:**
- Page dot animation: `Motion.popToggle`
- Reduced-motion: `.none` in place of dot animation; no parallax

**Structure:**
- `AsyncImage` fills frame (minHeight 280pt), `.fill` aspect, clipped to `cornerRadiusLarge` (32)
- `scrimGradient`: `amenBlack` at 0 → 0.30 → 0.85 opacity (bottom-up)
- Hero tint bleed layer: `heroTint.opacity(0.07)` over entire card — AMEN brand, not neutral white
- `cornerRadiusLarge` (32) clip + `shadowFloating` drop shadow

**Why this reads as AMEN, not Apple:**
The hero tint layer bleeds the Space's AMEN brand color (gold or purple) into the glass surface. The verse overlay in `amenGold` italic and the faith-native metadata row ("Bible Study · 1 member · KJV") make clear this is a spiritual context — not a video streaming card.

---

### 2. `SpaceFaithMetadataRow`

| Prop | Type | Notes |
|---|---|---|
| `spaceType` | `SpaceV2Type` | Always shown. Drives first chip's icon and label |
| `memberCount` | `Int` | Hidden when 0 |
| `bibleVersion` | `String?` | e.g. "KJV", "NIV" |
| `liturgicalSeason` | `String?` | e.g. "Advent", "Lent" |
| `churchBadge` | `ChurchBadgeChip.Badge?` | Custom badge from caller |

**Glass construction:**
Chips live inside `GlassEffectContainer(spacing: 8)`. Adjacent chips that are packed close together merge their glass shapes into a single fluid surface automatically — no manual corner-radius math.

**Separator:** `" · "` as `Text` in `.caption.bold()` + `amenGold` — not a gray dot.

**Why this reads as AMEN, not Apple:**
The gold `·` separator and faith-specific chip labels ("Bible Study", "Advent", "KJV") make this contextually Christian. A generic streaming UI would show "Drama · 12 episodes" — this shows "Bible Study · 42 members · KJV · Advent".

---

### 3. `ChurchBadgeChip`

| Prop | Type | Notes |
|---|---|---|
| `badge.icon` | `String` | SF Symbol name |
| `badge.label` | `String` | Pill label text |
| `badge.tint` | `Color` | Must be an `AmenTheme.Colors` value. Bleeds directly into glass via `.tint()` |

**Glass construction (iOS 26 native):**
```swift
HStack { Image(systemName:...) ; Text(...) }
    .padding(.vertical, 6).padding(.horizontal, 10)
    .glassEffect(.regular.tint(badge.tint),
                 in: .rect(cornerRadius: LiquidGlassTokens.cornerRadiusMedium))
```
No material layer, no opacity overlay, no manual border — the system tints the glass material directly with the AMEN color.

**Icon color:** Always `amenGold` — consistent gold gleam across all chips regardless of `badge.tint`.

**Why this reads as AMEN, not Apple:**
The tint bleeds an AMEN accent (gold or purple) directly into the glass — it can never be mistaken for a white system chip.

---

### 4. `AMENGlassPillButton`

| Prop | Type | Notes |
|---|---|---|
| `title` | `String` | Button label |
| `icon` | `String?` | SF Symbol, optional |
| `style` | `Style` | `.primary`, `.secondary`, `.prominent` |
| `action` | `() -> Void` | Tap handler |

**Styles (iOS 26 native button styles):**
| Style | Button Style | Tint |
|---|---|---|
| `.primary` | `.glassProminent` | `amenGold` |
| `.secondary` | `.glass` | `amenGold` |
| `.prominent` | `.glassProminent` | `amenPurple` |

Press animation, touch reaction, and reduce-motion scaling are all handled by the system glass button style — no manual `AmenPressStyle` gesture needed.

**Implementation:**
`@ViewBuilder` body switches on `style` and applies `.buttonStyle()` + `.tint()` — can't return `some PrimitiveButtonStyle` across concrete types, so the modifier chain is applied per-case instead.

**Why this reads as AMEN, not Apple:**
`amenGold` on `.glassProminent` produces a gold-filled pill — the inverse of Apple's default blue. `amenPurple` on the prominent style aligns with the Space type and member roster purple used elsewhere in AMEN.

---

### 5. `AMENGlassCard`

| Prop | Type | Notes |
|---|---|---|
| `width` | `CGFloat` | Default 180 |
| `height` | `CGFloat` | Default 120 |
| `tintColor` | `Color` | Default `amenPurple`. Bleeds into glass via `.tint()` |
| `content` | `@ViewBuilder () -> Content` | Card body |

**Glass construction (iOS 26 native):**
```swift
content()
    .frame(width: width, height: height)
    .glassEffect(.regular.tint(tintColor).interactive(),
                 in: .rect(cornerRadius: LiquidGlassTokens.cornerRadiusMedium))
    .clipShape(RoundedRectangle(cornerRadius: ..., style: .continuous))
```
`.interactive()` adds touch-reactive fluid physics identical to a system glass button — no manual press gesture required.

**Why this reads as AMEN, not Apple:**
The `tintColor` bleed (amenPurple or amenGold) gives each card a distinct branded warmth. A plain `.ultraThinMaterial` card would look identical on any app.

---

### 6. `SpaceRailView`

| Prop | Type | Notes |
|---|---|---|
| `title` | `String` | Faith-native: "Continue Studying", "Your Spaces", "Recommended for your walk", "Trending in your church" |
| `items` | `[Item: Identifiable]` | Generic |
| `card` | `@ViewBuilder (Item) -> CardContent` | Card renderer |

**Layout:**
- Section header: `.headline.bold()` in `textPrimary`
- "See All ›": `.buttonStyle(.glass).tint(amenGold)` — never system blue
- `ScrollView(.horizontal)` + `LazyHStack(spacing: 16)`, 20pt leading/trailing inset
- Each card receives `.staggeredReveal(index:baseDelay:0.04 maxDelay:0.20)` from `Motion.swift`

**Timing constants:**
- Stagger: `Motion.appearEase` (`.easeOut(duration: 0.24)`) per item
- `baseDelay`: 0.04s; `maxDelay`: 0.20s cap

**Why this reads as AMEN, not Apple:**
Section labels are spiritually-native ("Continue Studying", "Trending in your church"). "See All ›" uses `amenGold` — a secondary AMEN action signal, not a system tint link.

---

### 7. `AMENGlassTabBar`

| Prop | Type | Notes |
|---|---|---|
| `selectedTab` | `@Binding<SpacesTab>` | Drives active state |
| `scrollOffset` | `CGFloat` | 0 = top; positive = scrolled. Drives label collapse at ≥ 60pt |

**Tabs:**
| Case | Icon | Label |
|---|---|---|
| `.feed` | `house.fill` | "Feed" |
| `.study` | `book.fill` | "Study" |
| `.prayer` | `hands.sparkles.fill` | "Prayer" |
| `.spaces` | `rectangle.3.group.fill` | "Spaces" |
| `.search` | `magnifyingglass` | "Search" |

**Glass construction (iOS 26 native):**
```swift
GlassEffectContainer(spacing: 0) {
    HStack(spacing: 0) {
        ForEach(SpacesTab.allCases) { tab in tabItem(tab) }
    }
}
```
`spacing: 0` causes all tab glass shapes to fully merge into one seamless capsule bar. Each tab uses:
```swift
.buttonStyle(.glass(.regular.tint(isActive ? AmenTheme.Colors.amenGold : .clear)))
.glassEffectID(tab.id, in: tabNamespace)
.glassEffectTransition(.matchedGeometry)
```
As selection changes, the gold-tinted glass region morphs between tab positions via `.matchedGeometry` — the AMEN active-state indicator, not system blue.

**Scroll-driven behavior:**
- Labels collapse at `scrollOffset >= 60pt` via `Motion.liquidSpring`
- Reduced-motion: labels always shown; no collapse animation

**Active state:** `amenGold` glass tint + icon scale 1.08. Inactive: neutral glass, scale 1.0.

**Timing constants:**
- Tab switch: `Motion.popToggle`
- Bar contract/expand: `Motion.liquidSpring`
- Reduced-motion: `.none` for all animations

**Why this reads as AMEN, not Apple:**
`hands.sparkles.fill` ("Prayer") and `book.fill` ("Study") are spiritually-native icons with no streaming/social equivalent. The `amenGold` active state replaces system tint blue. The morphing gold region is a distinctly AMEN-branded indicator.

---

### 8. `GlassSheetModifier`

| Prop | Type | Notes |
|---|---|---|
| `tintColor` | `Color` | Default `amenPurple`. Use `amenGold` for Bible Study sheets |

**Extension:**
```swift
@available(iOS 26.0, *)
func amenGlassSheet(tint: Color = AmenTheme.Colors.amenPurple) -> some View
```

**Glass construction (iOS 26 native):**
```swift
content.glassEffect(
    .regular.tint(tintColor),
    in: UnevenRoundedRectangle(
        topLeadingRadius: LiquidGlassTokens.cornerRadiusLarge,
        bottomLeadingRadius: 0, bottomTrailingRadius: 0,
        topTrailingRadius: LiquidGlassTokens.cornerRadiusLarge,
        style: .continuous
    )
)
```
Top corners are `cornerRadiusLarge` (32); bottom corners are 0 so the sheet seats flush against the screen edge.

**Specular sweep:**
A tinted (2pt) horizontal `LinearGradient` band traverses left-to-right over 500ms `.easeOut` on appear. `specularProgress` drives both x-offset and fade-out opacity. Skipped when `reduceMotion` is true.

**Rubber-band dismiss:**
`DragGesture(minimumDistance: 10)` → offset = `sqrt(dragOffset) * 3.5` (stiff logarithmic resistance). `.onEnded`: `withAnimation(Motion.liquidSpring) { dragOffset = 0 }`.

**Timing constants:**
- Specular sweep: `.easeOut(duration: 0.50)`
- Rubber-band snap-back: `Motion.liquidSpring`
- Reduced-motion: specular sweep skipped; snap-back still runs (non-visual, safe)

**Why this reads as AMEN, not Apple:**
The tint bleed (purple for community, gold for study) immediately communicates the sheet's spiritual role. The specular sweep is tinted with the context color — a faith-brand flourish, not a generic iOS presentation shimmer.

---

## Token Reference Summary

| Token | Value | Source |
|---|---|---|
| `LiquidGlassTokens.cornerRadiusMedium` | 22 pt | LiquidGlassTokens.swift |
| `LiquidGlassTokens.cornerRadiusLarge` | 32 pt | LiquidGlassTokens.swift |
| `LiquidGlassTokens.shadowSoft` | black 0.08, radius 14, y 6 | LiquidGlassTokens.swift |
| `LiquidGlassTokens.shadowFloating` | black 0.12, radius 24, y 10 | LiquidGlassTokens.swift |
| `Motion.liquidSpring` | iOS 17+: `.bouncy(duration:0.4, extraBounce:0.1)` | Motion.swift |
| `Motion.springPress` | `response:0.22, dampingFraction:0.88` | Motion.swift |
| `Motion.popToggle` | `response:0.20, dampingFraction:0.56` | Motion.swift |
| `Motion.appearEase` | `.easeOut(duration:0.24)` | Motion.swift |
| `AmenTheme.Colors.amenGold` | `Color(red:0.83, green:0.69, blue:0.22)` | AmenTheme.swift |
| `AmenTheme.Colors.amenPurple` | `Color(red:0.44, green:0.26, blue:0.80)` | AmenTheme.swift |
| `AmenTheme.Colors.amenBlue` | `Color(red:0.04, green:0.52, blue:1.0)` | AmenTheme.swift |
| `AmenTheme.Colors.amenBlack` | `Color(red:0.06, green:0.06, blue:0.07)` | AmenTheme.swift |
| `AmenTheme.Colors.glassStroke` | dark: white 0.16α / light: white 0.55α | AmenTheme.swift |

---

## Accessibility checklist

- All interactive elements carry `.accessibilityLabel` and `.accessibilityHint`
- `SpaceFaithMetadataRow` collapses to a single `.accessibilityElement(children:.combine)` label
- `AMENGlassTabBar` tabs carry `.isSelected` trait when active
- Dot indicators, decorative gradients, and tint bleed layers are `.accessibilityHidden(true)` or `.allowsHitTesting(false)`
- All `@Environment(\.accessibilityReduceMotion)` paths tested: springs → `.none`; specular sweep → skipped; label collapse → always shown
- `reduceTransparency` is **not** manually handled — native `glassEffect` adapts automatically per system setting

---

## Required patterns (iOS 26 native — confirmed present)

- `GlassEffectContainer(spacing:)` — merges glass shapes; `spacing:0` for tab bar capsule, `spacing:8/12` for chip/action rows
- `.glassEffect(.regular.tint(color), in: Shape)` — branded tint bleed on cards, chips, sheets
- `.glassEffect(.regular.tint(color).interactive())` — touch-reactive glass on `AMENGlassCard`
- `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` + `.tint()` — system-managed press animation
- `.buttonStyle(.glass(.regular.tint(isActive ? amenGold : .clear)))` — active-state tab highlight
- `glassEffectID(_:in:)` + `.glassEffectTransition(.matchedGeometry)` — liquid morph between positions
- `@available(iOS 26.0, *)` on every struct and the `amenGlassSheet` extension

## Prohibited patterns (confirmed absent)

- `.ultraThinMaterial` / `.thinMaterial` — replaced by native `glassEffect`
- Manual `@Environment(\.accessibilityReduceTransparency)` branches — system handles this
- Raw `.blue`, `.purple`, `.yellow`, `.green` system colors — not used
- `import CoreMotion` — not imported
- `AmenPressStyle` manual scale gestures inside glass components — system button styles handle press
