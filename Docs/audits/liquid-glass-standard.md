# AMEN Liquid Glass Design Standard — Audit & Specification

**Document Version:** 1.0  
**Date:** May 28, 2026  
**Scope:** iOS 17.0+ (app deployment target); iOS 26.0+ for native `glassEffect()` API  
**Status:** Canonical reference for all Phase 1–9 Liquid Glass implementation

---

## § 1: Implementation Split — Native vs. Custom Materials

### Overview
The AMEN app uses a **hybrid approach** to achieve Liquid Glass effects across all iOS versions:

- **iOS 26.0+**: Native `glassEffect()` API with `Glass.regular` and `Glass.interactive()` instances
- **iOS 17.0–25.9**: Custom Material system (`.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`) with hand-crafted overlays
- **Accessibility fallback**: High-contrast and reduce-transparency environments fall back to solid fills

### File Count Summary

| Category | Count | Primary Files |
|----------|-------|---|
| **Native iOS 26 glass** (`glassEffect`) | 16 files | `AMENTabBar.swift`, `LiquidGlassMotion.swift`, `GlassEffectModifiers.swift`, `AmenGlassKit.swift` |
| **Custom material system** (`ultraThinMaterial` et al.) | 250+ files | Core design tokens in `LiquidGlassTokens.swift`, buttons in `LiquidGlassButtons.swift`, modal in `LiquidGlassAlert.swift` |
| **LiquidGlass custom components** | 140+ files | All `LiquidGlass*`, `AmenLiquidGlass*`, `Berean*`, `Amen*` prefixed views |
| **Both mixed** | ~16 files | Tab bar, motion system, glass kits |

### Key Observation
Most of the codebase uses the **custom material + overlay approach** because the app targets iOS 17.0 as its deployment minimum. The native `glassEffect()` is used in forward-facing components (tab bar, expandable cards, sheets) where iOS 26 availability is explicitly guarded with `#available(iOS 26.0, *)`.

---

## § 2: Reference Component A — Active Tab Capsule (Pill Nav)

**File:** `/AMENAPP/AMENTabBar.swift`  
**Component:** `LiquidGlassActiveTabCapsule`  
**Pattern:** Light frosted glass pill behind the active center tab, expands to show icon + label on selection.

### Exact Specifications

#### Shape & Geometry
- **Type:** `Capsule(style: .continuous)`
- **Corner radius:** Implicit in capsule (mathematically infinite on ends, continuous curve)
- **Padding inside center rail:** 6pt horizontal, with inter-tab spacing of 2pt

#### Material Stack (iOS 26+)
```swift
.fill(Color.clear)
.glassEffect(Glass.regular, in: Capsule(style: .continuous))
```

#### Material Stack (iOS 17–25.9)
```swift
.fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.06))
.overlay {
    Capsule(style: .continuous)
        .strokeBorder(
            colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.05),
            lineWidth: colorSchemeContrast == .increased ? 1.0 : 0.6
        )
}
```

#### Inner Sheen (iOS 26+)
**Not explicitly rendered** — baked into `Glass.regular` material. For iOS 17 fallback, the `Color.white.opacity(0.16 dark / 0.06 light)` fill serves as the sheen.

#### Refraction Stroke (Border Gradient)
```swift
LinearGradient(
    colors: [
        Color.white.opacity(0.72),  // top-left corner
        Color.white.opacity(0.30),  // center edge
        Color.white.opacity(0.55)   // bottom-right corner
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
lineWidth: 0.9  // or 1.2 if colorSchemeContrast == .increased
```

#### Shadow
```swift
.shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
```

#### Selection Animation (Spring)
**Trigger:** When `selectedTab` changes to this tab  
**Duration:** `response: 0.34, dampingFraction: 0.84`  
**Type:** `.spring(response: 0.34, dampingFraction: 0.84)`

#### Badge (if count > 0)
- **Background:** `Color(red: 0.937, green: 0.267, blue: 0.267)` (bright red #EF4444)
- **Shape:** `Capsule()`
- **Size:** min 17pt × 17pt, expands horizontally if count ≥ 10
- **Border:** `Color(.systemBackground).opacity(0.9)`, lineWidth 1.5
- **Scale on new badge:** `.spring(response: 0.25, dampingFraction: 0.5)`

---

## § 3: Reference Component B — Centered Blurred-Glass Modal Alert

**File:** `/AMENAPP/AMENAPP/LiquidGlass/LiquidGlassAlert.swift`  
**Component:** `LiquidGlassAlertCard` (internal) + `.amenAlert()` modifier (public)  
**Pattern:** Centered modal card with blurred dimmed background, two capsule action buttons.

### Status: FULLY IMPLEMENTED ✓

This component **exists and is production-ready**. It is the canonical modal alert pattern for AMEN.

### Exact Specifications

#### Container
- **Backdrop:** `Color.black.opacity(0.35)` full-screen scrim
- **Card max-width:** 320pt
- **Card corner radius:** `LiquidGlassTokens.cornerRadiusLarge` (32pt)
- **Corner style:** `.continuous`

#### Card Background (iOS 26+)
```swift
ZStack {
    RoundedRectangle(cornerRadius: 32, style: .continuous)
        .fill(LiquidGlassTokens.blurElevated)  // .regularMaterial
    RoundedRectangle(cornerRadius: 32, style: .continuous)
        .fill(
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.13 : 0.58),  // top: bright in light, dim in dark
                    Color.white.opacity(0.02)  // bottom: nearly transparent
                ],
                startPoint: .top,
                endPoint: .center
            )
        )
        .blendMode(.screen)
}
```

#### Card Background (iOS 17–25.9, Reduce Transparency On)
```swift
RoundedRectangle(cornerRadius: 32, style: .continuous)
    .fill(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.96))
```

#### Card Shadow
```swift
.shadow(
    color: LiquidGlassTokens.shadowFloating.color,  // .black.opacity(0.12)
    radius: LiquidGlassTokens.shadowFloating.radius,  // 24
    y: LiquidGlassTokens.shadowFloating.y  // 10
)
```

#### Title & Message
- **Title font:** `.title3.weight(.semibold)`, multiline center-aligned
- **Message font:** `.body`, multiline center-aligned (if present)
- **Icon (optional):** `.system(size: 28, weight: .medium)`, `.secondary` color

#### Action Buttons
**Layout:** Vertical stack, buttons full-width minus padding  
**Height:** 46pt  
**Corner:** `Capsule(style: .continuous)`  
**Font:** `.body.weight(.semibold)`

**Button Tones:**
1. **Primary** (`.primary`): `AmenTheme.Colors.amenGold`
2. **Spiritual** (`.spiritual`): `Color(red: 0.42, green: 0.28, blue: 1.0)` (purple)
3. **Destructive** (`.destructive`): `Color.red.opacity(pressed ? 0.72 : 0.88)`
4. **Dismiss** (`.dismiss`): 
   - Reduce transparency ON: `Color(white: 0.82 light / 0.28 dark)`
   - Reduce transparency OFF: `.ultraThinMaterial` with white border

**Button Press State:** scale 0.97 with spring animation  
**Foreground color:** 
- Primary/Spiritual/Destructive: `.white`
- Dismiss: `.primary` (system label)

#### Transition Animation
- **Insertion:** `.scale(scale: 0.88).combined(with: .opacity)`
- **Removal:** `.scale(scale: 0.96).combined(with: .opacity)`
- **Overall animation:** `.spring(response: 0.34, dampingFraction: 0.84)` (or `.easeOut(duration: 0.18)` if reduce motion)

#### Spacing (Padding)
- **Card padding:** 24pt all sides
- **Button spacing:** 10pt between buttons
- **Icon to title:** 10pt
- **Title to message:** 8pt
- **Message to buttons:** 22pt

#### Usage
```swift
.amenAlert(
    isPresented: $showAlert,
    config: LiquidGlassAlertConfig(
        title: "Confirm Action",
        message: "Are you sure?",
        icon: "exclamationmark.triangle",
        primaryButton: LiquidGlassAlertButton("Confirm", tone: .primary) { /* action */ },
        secondaryButton: LiquidGlassAlertButton.cancel { /* action */ }
    )
)
```

---

## § 4: Color Tokens — Complete Definition

All color definitions are in `/AMENAPP/AMENAPP/AmenTheme.swift` under the `AmenTheme.Colors` namespace.

### Brand Colors (Invariant)

| Token | RGB Value | Usage |
|-------|-----------|-------|
| `amenGold` | `(0.83, 0.69, 0.22)` | Primary action buttons, highlight accents |
| `amenBronze` | `(0.80, 0.50, 0.20)` | Secondary/warm accents |
| `amenSilver` | `(0.75, 0.75, 0.75)` | Neutral accent, disabled states |

### Tab Bar Accent

| Token | RGB Value | Usage |
|-------|-----------|-------|
| `amenTabAccent` (in `AMENTabBar.swift`) | `(0.04, 0.52, 1.0)` | Active tab icon + label tint, profile circle stroke |

### Alert Button Colors

| Button Tone | Color | RGB Value |
|-------------|-------|-----------|
| Primary | `AmenTheme.Colors.amenGold` | `(0.83, 0.69, 0.22)` |
| Spiritual | Hardcoded purple | `(0.42, 0.28, 1.0)` |
| Destructive | System red | `.red.opacity(0.88 normal / 0.72 pressed)` |
| Dismiss | Material fallback | `.ultraThinMaterial` or system gray |

### Glass Material Tokens

| Token | Definition | Opacity (Light / Dark) |
|-------|-----------|----------|
| `blurThin` | `.ultraThinMaterial` | — |
| `blurRegular` | `.thinMaterial` | — |
| `blurElevated` | `.regularMaterial` | — |
| `glassFill` | Adaptive white highlight | 0.70 light / 0.06 dark |
| `glassStroke` | Adaptive white border | 0.55 light / 0.16 dark |
| `glassHighlightTop` | Gradient top | 0.55 light / 0.10 dark |
| `glassHighlightBottom` | Gradient bottom | 0.18 light / 0.03 dark |
| `glassDepth` | Darkening pool | 0.06 light / 0.25 dark |

### Shadow Tokens

| Token | Color Opacity | Radius | Y Offset |
|-------|---|---|---|
| `shadowSoft` | `0.08` | 14 | 6 |
| `shadowFloating` | `0.12` | 24 | 10 |

### Motion Tokens

| Token | Duration (seconds) | Usage |
|-------|---|---|
| `motionFast` | 0.18 | Quick dismissals, collapse |
| `motionNormal` | 0.32 | Standard spring base |
| `motionSlow` | 0.55 | Content reveals, onboarding |

---

## § 5: Canonical Source of Truth — Reusable Components

### Primary Library Files

1. **`/AMENAPP/AMENAPP/LiquidGlass/LiquidGlassTokens.swift`** ← **MASTER TOKENS**
   - All corner radii, materials, shadows, motion constants
   - Single source for entire design system

2. **`/AMENAPP/AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift`** ← **PRIMARY COMPONENTS**
   - `AmenLiquidGlassPillButton` (reusable capsule button)
   - `AmenLiquidGlassControlDock` (horizontal action strip)
   - `AmenLiquidGlassBottomSheet` (footer sheet container)
   - `AmenGlassSmartSheet` (intent-aware sheet modifier)
   - `AmenGlassContextMenu` (haptic menu wrapper)
   - `AmenGlassMediaChrome` (inactivity-fading media controls)
   - `AmenGlassLoadingSkeleton` (shimmer placeholder)
   - `AmenGlassExpandableCard` (backward-compatible expand/collapse)
   - `AmenGlassComposerBar` (pill ↔ panel composer morph)
   - `AmenFloatingGlassBackButton` (floating pill back button)
   - `AmenGlassActionRail` (icon-only action strip)

3. **`/AMENAPP/AMENAPP/LiquidGlass/LiquidGlassAlert.swift`** ← **MODAL ALERT PATTERN**
   - `LiquidGlassAlertConfig` (alert configuration)
   - `LiquidGlassAlertButton` (button with tone enum)
   - `.amenAlert()` modifier (public API)

4. **`/AMENAPP/LiquidGlassMotion.swift`** ← **ADVANCED MORPHING (iOS 26+)**
   - `GlassExpandableCard` (iOS 26+ native glass expand)
   - `GlassContextualSheet` (iOS 26+ contextual sheet)
   - `BackgroundRefocusModifier` (depth separation)
   - `AmenMotion` (animation constants)

5. **`/AMENAPP/AMENTabBar.swift`** ← **NAVIGATION REFERENCE**
   - `LiquidGlassTabBarBackground` (capsule container material)
   - `LiquidGlassOrbBackground` (side circle material)
   - `LiquidGlassActiveTabCapsule` (active pill)
   - `AMENTabBar` (full tab bar implementation)

### Component Status

| Component | Exists? | Type | Notes |
|-----------|---------|------|-------|
| Glass button | ✓ | `AmenLiquidGlassPillButton` | Capsule-shaped, icon+label |
| Glass icon button | ✓ | `AmenLiquidGlassButton` | Circle/capsule/roundedRect shape variant |
| Glass modal/alert | ✓ | `.amenAlert()` modifier | **CANONICAL** — use this everywhere |
| Glass sheet | ✓ | `.amenSmartSheet()` modifier | Falls back gracefully on iOS 17 |
| Glass expandable card | ✓ | `GlassExpandableCard` (iOS 26) | iOS 26+ only; backward compat version exists |
| Glass action rail | ✓ | `AmenGlassActionRail` | Horizontal/vertical icon buttons |
| Glass loading skeleton | ✓ | `AmenGlassLoadingSkeleton` | Shimmer placeholder with adaptive material |
| Glass composer | ✓ | `AmenGlassComposerBar` | Pill ↔ panel morph |
| Glass back button | ✓ | `AmenFloatingGlassBackButton` | Floating pill for sheets |

**Recommendation:** No new glass components need to be created. All Phase 1–9 work should **use the existing library** and add new variations via parameters (e.g., `.tone`, `.size`, `.shape`) rather than creating duplicate components.

---

## § 6: Design Constants — Copy-Paste Reference Block

**Use this block in all Phase 1–9 implementation docs, feature briefs, and code reviews.**

```swift
// AMEN Liquid Glass Design Constants
// Canonical values extracted from AMENTabBar.swift, LiquidGlassTokens.swift, LiquidGlassAlert.swift
// All Phase 1–9 agents should reference these values verbatim.

// MARK: - Corner Radii
let cornerRadiusSmall: CGFloat = 14      // Small pills, badges
let cornerRadiusMedium: CGFloat = 22     // Standard cards, buttons
let cornerRadiusLarge: CGFloat = 32      // Modal cards, sheets
let capsuleRadius: CGFloat = 999         // Capsule (infinite, continuous curve)

// MARK: - Material Tiers (iOS 17 Fallback)
let blurThin: Material = .ultraThinMaterial      // Lightest, most transparent
let blurRegular: Material = .thinMaterial        // Standard glass
let blurElevated: Material = .regularMaterial    // Dense, modal-grade

// MARK: - Shadows
struct GlassShadow {
    static let soft = (color: Color.black.opacity(0.08), radius: 14.0, y: 6.0)
    static let floating = (color: Color.black.opacity(0.12), radius: 24.0, y: 10.0)
}

// MARK: - Tab Bar (AMENTabBar.swift exact values)
struct TabBarGlass {
    // Capsule (center rail)
    static let capsuleInnerSheen = (
        darkMode: Color.white.opacity(0.06),
        lightMode: Color.white.opacity(0.14)
    )
    static let capsuleRefractionStroke = LinearGradient(
        colors: [
            Color.white.opacity(0.8),    // top-left
            Color.cyan.opacity(0.16),    // center (cyan tint)
            Color.pink.opacity(0.14),    // center (pink tint)
            Color.white.opacity(0.6)     // bottom-right
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let capsuleShadow = (color: Color.black.opacity(0.16), radius: 20.0, y: 11.0)
    
    // Active pill (selection background)
    static let pillStroke = LinearGradient(
        colors: [
            Color.white.opacity(0.72),   // top-left
            Color.white.opacity(0.30),   // center
            Color.white.opacity(0.55)    // bottom-right
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let pillShadow = (color: Color.black.opacity(0.10), radius: 6.0, y: 3.0)
    static let pillStrokeWidth: CGFloat = 0.9  // standard; 1.2 if .increased contrast
    
    // Orb (side circles)
    static let orbShadowExpanded = (color: Color.black.opacity(0.16), radius: 14.0, y: 7.0)
    static let orbShadowCompressed = (color: Color.black.opacity(0.16), radius: 9.0, y: 3.0)
    
    // Selection animation
    static let selectSpring = Animation.spring(response: 0.34, dampingFraction: 0.84)
    
    // Badge (notification count)
    static let badgeColor = Color(red: 0.937, green: 0.267, blue: 0.267)  // #EF4444
    static let badgeBorder = Color(.systemBackground).opacity(0.9)
    static let badgePulseSpring = Animation.spring(response: 0.25, dampingFraction: 0.5)
}

// MARK: - Alert Modal (LiquidGlassAlert.swift exact values)
struct AlertGlass {
    static let maxWidth: CGFloat = 320
    static let cornerRadius: CGFloat = 32
    static let padding: CGFloat = 24
    
    // Background gradient (top of card)
    static let gradientTopOpacity = (lightMode: 0.58, darkMode: 0.13)
    static let gradientBottomOpacity = 0.02
    
    // Button heights and spacing
    static let buttonHeight: CGFloat = 46
    static let buttonSpacing: CGFloat = 10
    
    // Backdrop scrim
    static let backdropOpacity: CGFloat = 0.35
    
    // Button colors
    static let primaryButtonColor = Color(red: 0.83, green: 0.69, blue: 0.22)  // amenGold
    static let spiritualButtonColor = Color(red: 0.42, green: 0.28, blue: 1.0)
    static let destructiveButtonColor = Color.red
    
    // Button press states
    static let buttonPressOpacity: CGFloat = 0.80
    static let destroyPressOpacity: CGFloat = 0.72
    static let normalOpacity: CGFloat = 1.0
    
    // Animation
    static let dismissSpring = Animation.spring(response: 0.24, dampingFraction: 0.88)
    static let scaleInsert: CGFloat = 0.88
    static let scaleRemove: CGFloat = 0.96
}

// MARK: - Motion (LiquidGlassMotion.swift exact values)
struct GlassMotion {
    static let cardSpringResponse: CGFloat = 0.42
    static let cardDamping: CGFloat = 0.82
    static let sheetSpringResponse: CGFloat = 0.38
    static let sheetDamping: CGFloat = 0.85
    static let microSpringResponse: CGFloat = 0.22
    static let microDamping: CGFloat = 0.9
    static let refocusDuration: Double = 0.28
}

// MARK: - Tab Accent Color
let amenTabAccent = Color(red: 0.04, green: 0.52, blue: 1.0)  // Bright blue for active tab

// MARK: - Accessibility Fallback Fills
struct AccessibilityFallback {
    static let darkModeBackgroundFill = Color(white: 0.14)     // #242424
    static let lightModeBackgroundFill = Color(white: 0.97)    // #F7F7F7
    static let darkModeOpaque = Color(white: 0.18)             // Alert dark fallback
    static let lightModeOpaque = Color(white: 0.96)            // Alert light fallback
}
```

---

## Summary & Recommendations

### For Phase 1–9 Agents

1. **All modal/alert patterns** → Use `.amenAlert()` from `LiquidGlassAlert.swift`
2. **All glass buttons** → Use `AmenLiquidGlassPillButton` or `AmenLiquidGlassButton` with shape/intensity parameters
3. **All glass sheets** → Use `.amenSmartSheet()` from `AmenLiquidGlassComponents.swift`
4. **All expandable cards** → Use `GlassExpandableCard` (iOS 26+) or backward-compatible `AmenGlassExpandableCard`
5. **All design constant** → Reference the block in § 6; do NOT invent new opacities, radii, or spring values
6. **iOS 26 features** → Guard with `#available(iOS 26.0, *)` and provide iOS 17 fallback using materials + overlays

### Known Gaps (Do NOT Create)

- Glass button component: ✓ exists
- Glass alert/modal: ✓ exists
- Glass action rail: ✓ exists
- Glass loading skeleton: ✓ exists

**All necessary components are production-ready.** Phase 1–9 work is **integration and refinement**, not new creation.

---

**End of Audit Document**
