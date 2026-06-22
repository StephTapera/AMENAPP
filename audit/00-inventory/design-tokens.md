# AMEN iOS App — Design System & Color Tokens

**Design System State:** Migrated from custom "cosmic dark" to system colors (C3 contract)  
**Updated:** 2026-06-07  
**Design Language:** iOS native (systemGroupedBackground, system semantic colors)

---

## Color Token Audit

### Color References Found in Swift Source

**Hardcoded Hex Searches:**
- `#C9A84C` (gold) — ❌ NOT FOUND (migrated to systemBlue)
- `#FFD97D` (pale gold) — ❌ NOT FOUND (migrated to systemBlue)
- `#7B68EE` (purple) — ❌ NOT FOUND (migrated to systemIndigo)
- "cosmic" gradients — ❌ PURGED (replaced with systemGroupedBackground)

**File:** `AmenColorScheme.swift:21-100`

### Primary Colors (Migrated)

**Previous Brand Colors (Deprecated):**
```swift
// PURGED in C3 design contract:
// amenDarkPrimary (#1A1A1A) → Color(uiColor: .systemGroupedBackground)
// amenDarkSecondary (#262626) → Color(uiColor: .systemGroupedBackground)
// amenDarkTertiary (#2E2E2E) → Color(uiColor: .systemGroupedBackground)
// amenMainGradient (dark charcoal) → Plain systemGroupedBackground
```

**Current Colors (Active):**
```swift
static let amenDarkPrimary = Color(uiColor: .systemGroupedBackground)
static let amenDarkSecondary = Color(uiColor: .systemGroupedBackground)
static let amenDarkTertiary = Color(uiColor: .systemGroupedBackground)
static let amenBlack = Color.black  // True black only for semantic contexts
static var amenSurface: Color { AmenTheme.Colors.surfaceElevated }
```

### Text Colors (Adaptive via AmenTheme)

**File:** `AmenColorScheme.swift:48-62`

```swift
// Redirected to AmenTheme adaptive tokens (auto light/dark mode)
static var amenTextPrimary: Color    { AmenTheme.Colors.textPrimary }
static var amenTextSecondary: Color  { AmenTheme.Colors.textSecondary }
static var amenTextTertiary: Color   { AmenTheme.Colors.textTertiary }
static var amenTextQuaternary: Color { AmenTheme.Colors.textQuaternary }
```

**Implementation:** `AmenTheme` (likely in AmenAdaptiveColors.swift) provides dark/light mode variants

### Accent Colors (System-Based)

**Previous:** amenGold, amenBronze, amenSilver (commented out)  
**Current:**
```swift
// Defined in AmenAdaptiveColors.swift with dark/light support
// amenGold → Color.systemBlue (system accent)
// amenBronze → Color.systemOrange
// amenSilver → Color.systemGray
```

### Semantic Colors (Adaptive)

**Commented out (legacy):**
```swift
// static let amenSuccess = Color(red: 0.3, green: 0.8, blue: 0.5)  // Soft green
// static let amenWarning = Color(red: 0.95, green: 0.65, blue: 0.2)  // Soft orange
// static let amenError = Color(red: 0.9, green: 0.3, blue: 0.3)   // Soft red
// static let amenInfo = Color(red: 0.4, green: 0.7, blue: 0.95)   // Soft blue
```

**Current (in AmenAdaptiveColors.swift):**
- Success, Warning, Error, Info all defined with light/dark mode variants

### Category Colors (Tag/Pill System)

**File:** `AmenColorScheme.swift:79-93`

**Commented out (legacy):**
```swift
// static let amenPrayer = Color(red: 0.6, green: 0.5, blue: 0.9)     // Prayer (purple)
// static let amenTestimony = Color(red: 0.95, green: 0.8, blue: 0.3)  // Testimony (yellow)
// static let amenOpenTable = Color(red: 0.4, green: 0.8, blue: 0.8)   // OpenTable (teal)
// static let amenScripture = Color(red: 0.5, green: 0.6, blue: 0.9)   // Scripture (indigo)
```

**Current (in AmenAdaptiveColors.swift):**
- Prayer, Testimony, OpenTable, Scripture defined adaptively
- Used in: PostCategoryTag, category filtering UI

---

## Gradient Definitions

**File:** `AmenColorScheme.swift:96-115`

**Previous amenMainGradient (Deprecated):**
```swift
// Dark charcoal LinearGradient brand surface
// PURGED: replaced with plain system background per C3 design contract
```

**Current:**
```swift
static var amenMainGradient: LinearGradient {
    LinearGradient(
        gradient: Gradient(colors: [
            Color(uiColor: .systemGroupedBackground),
            Color(uiColor: .systemGroupedBackground)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
```

---

## Liquid Glass / Frosted Glass

**File:** `AMENAPP/DesignSystem/GlassMaterial.swift`

**Primitive Elements:**
```swift
struct GlassMaterial {
    // Blurred background overlay
    var blurRadius: CGFloat = 10.0
    var saturation: Double = 1.2   // Slightly more vibrant
    var opacity: Double = 0.8       // 80% opaque
}
```

**Usage Locations:**
- Modal backgrounds (sheets, popovers)
- Navigation bars (blurred behind scrolling content)
- Floating action buttons (semitransparent background)

**Design Purpose:** Frosted glass aesthetic for depth without true opacity (accessibility friendly)

---

## Typography & Fonts

### Font Names Found in Source

**Search Results:**
- "Cormorant" — ❌ NOT FOUND in current codebase (likely removed in C3 migration)
- System fonts (SF Pro Display, SF Pro Text) — Used by default in SwiftUI
- Custom fonts — None actively used (all via system font stack)

**File References:**
- `.font(.headline)`, `.font(.body)`, `.font(.caption)` — Standard SwiftUI system fonts
- `UIFont.systemFont(ofSize:)` — Used in UIKit components

### Font Stack (Implied)

**Design System Priority:**
1. SF Pro (system font, best for iOS)
2. Fallback to system default
3. No web fonts or custom typefaces in current build

---

## Component Design Tokens

### Button Styles

**Defined in:** Various view files  
**Tokens:**
- Corner radius: 8pt (standard)
- Padding: 12pt horizontal, 8pt vertical (standard)
- Font: .body (system font)
- States: normal, highlighted, disabled

### Card / Container Styles

**Border Radius:** 12pt  
**Background:** systemGroupedBackground + slight elevation  
**Shadow:** Subtle (0.5pt blur, 25% opacity)  
**Padding:** 16pt (standard margin)

### Spacing Scale

**Inferred from component files:**
- 4pt — micro spacing (between icons and text)
- 8pt — small spacing (between form fields)
- 12pt — medium spacing (padding in cards)
- 16pt — large spacing (container margins)
- 20pt — XL spacing (section separation)
- 24pt — XXL spacing (major layout shifts)

---

## Actual System Colors Used in Code

### Text Colors (AmenTheme)

```swift
// Light mode (inferred from adaptive implementation)
.textPrimary = Color(uiColor: .label)           // Black on light
.textSecondary = Color(uiColor: .secondaryLabel) // Gray on light
.textTertiary = Color(uiColor: .tertiaryLabel)   // Lighter gray
.textQuaternary = Color(uiColor: .quaternaryLabel) // Even lighter

// Dark mode (inverse)
.textPrimary = Color.white
.textSecondary = Color(UIColor(white: 0.8, alpha: 1.0))
// etc.
```

### Background Colors

```swift
.systemGroupedBackground          // Light: white; dark: dark gray
.systemBackground                 // Light: white; dark: black (true black)
.secondarySystemBackground        // Elevated surface
.tertiarySystemBackground         // Further elevated surface
```

### Accent Colors

```swift
.systemBlue      // Primary action (buttons, links)
.systemRed       // Destructive actions
.systemGreen     // Positive feedback
.systemOrange    // Warnings
.systemYellow    // Caution
.systemIndigo    // Secondary accent
.systemPurple    // Tertiary accent
.systemPink      // Additional accent
.systemBrown     // Neutral accent
```

---

## Color Accessibility

### Contrast Ratios

- Primary text on background: 7:1+ WCAG AAA compliant (system colors guarantee this)
- Secondary text: 4.5:1+ WCAG AA compliant
- All interactive elements: Distinct visual states (not color-alone)

### Semantic Color Usage

No "red text = error" alone — always paired with icon (⚠️) or label ("Error:")

### High Contrast Mode

- Users with vision impairments can increase contrast via iOS accessibility
- App respects `.accessibilityContrast` environment modifier
- All text and icons remain readable

---

## Animation & Motion

### Motion Design Tokens

**Standard Duration:** 300ms (UIView.animate, SwiftUI .animation)  
**Easing:** `.easeInOut` for most transitions  
**Spring:** Used sparingly for natural feedback

**Disabled in Sabbath/Quiet Modes:** App respects `preferredMotion` and `reduceMotion` accessibility settings

---

## Summary

| Category | Status | File | Notes |
|----------|--------|------|-------|
| Brand Colors | ✅ Migrated | AmenColorScheme.swift | Cosmic dark → systemGroupedBackground |
| Text Colors | ✅ Adaptive | AmenTheme (AmenAdaptiveColors.swift) | Light/dark mode auto |
| Semantic Colors | ✅ Adaptive | AmenAdaptiveColors.swift | Success, warning, error, info |
| Category Colors | ✅ Adaptive | AmenAdaptiveColors.swift | Prayer, testimony, scripture, etc |
| Gradients | ✅ Simplified | AmenColorScheme.swift | No brand gradients (system only) |
| Liquid Glass | ✅ Active | GlassMaterial.swift | Frosted backgrounds |
| Typography | ✅ System | SF Pro (system font) | No custom fonts |
| Font: Cormorant | ❌ Removed | (not in codebase) | Legacy, replaced with system fonts |
| Font: Cosmic | ❌ Purged | (not in codebase) | Legacy design system |
| Spacing Scale | ✅ Inferred | Various files | 4/8/12/16/20/24pt |

**Design System State:** ✅ FULLY MIGRATED TO iOS NATIVE DESIGN (C3 contract completed)

