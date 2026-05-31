# AMEN — Canonical Liquid Glass Design Standard
**Version:** 1.0 — Design Pass 2026-05-30  
**Source of truth for all Phase 2 fixes.**

---

## 1. Material Family

| Role | SwiftUI Material | Adaptive Tint | Use On |
|------|-----------------|---------------|--------|
| Controls (buttons, pills, orbs) | `.ultraThinMaterial` | `Color.white.opacity(0.05–0.10)` overlay | Tab bar, floating buttons, capsule search, filter pills |
| Sheets & menus | `.regularMaterial` | `Color.white.opacity(0.04)` overlay | Action sheets, context menus, option panels |
| Cards | `.thinMaterial` | none | Feed cards, church cards, verse cards |
| Dropdowns | `.ultraThinMaterial` | none | Search suggestions, filter dropdowns |

**Never use:** flat `Color(white: 0.14)` / `Color(.systemGray6)` / hardcoded hex fills as a substitute for material on an overlay, control, or sheet. Those are opaque and non-adaptive.

### Reduce Transparency fallback (REQUIRED on every glass surface)
```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency

// Pattern:
.background(
    reduceTransparency
        ? AmenTheme.Colors.backgroundElevated  // solid fallback
        : AnyShapeStyle(.ultraThinMaterial)
)
```
Any glass surface without this fallback is a **severity MEDIUM** finding.

---

## 2. Palette — Accent-only rule

| Token | Color | Usage |
|-------|-------|-------|
| `AmenTheme.Colors.amenGold` | warm gold | Primary accent, active states, CTA highlights |
| `AmenTheme.Colors.amenPurple` | medium purple | Category accents, Berean AI |
| `AmenTheme.Colors.amenBlue` | AMEN blue | Church Notes, info states |
| `AmenTheme.Colors.amenEmerald` | green | Wellness, success states |
| `AmenTheme.Colors.amenBlack` | deep black | Typography on light, tab icons |

**Rule:** These colors appear as small accents (icon tint, border tint, pill background opacity ≤ 0.15), not as full-screen or full-surface backgrounds. An amenPurple `Color.fill` on a VStack background is a **MEDIUM** finding. An amenGold or amenPurple hero gradient is acceptable only in the ambient hero zone (≤ 50% opacity) with a white/system-background fade.

---

## 3. Corner Radius Scale

| Element | Radius |
|---------|--------|
| Circle controls (orbs, icon buttons) | `Circle()` |
| Pill / capsule controls (search, filter) | `Capsule()` |
| Cards (feed, church, verse) | `18` |
| Sheets & menus | `24` |
| Floating panels | `20` |
| Dropdown panels | `16` |
| Small chips/tags | `10` |

Mixing random radii (12, 14, 15, 28 on the same surface type) is a **LOW** finding.

---

## 4. Hero Header Spec

```
┌──────────────────────────────────────────────────────┐  ← Edge-to-edge, bleeds into status bar
│  ┌──────────────────────────────────────────────────┐│
│  │  [Full-bleed image / ambient gradient]           ││
│  │                                                  ││  ← `.ignoresSafeArea(edges: .top)`
│  │                                                  ││
│  │  ●  [← ] glass back circle    [★ ···] glass pill ││  ← floating glass controls, .top safe area padding
│  │                                                  ││
│  │  Legibility scrim (gradient bottom 30%)          ││  ← black.opacity(0–0.45) gradient
│  │                                                  ││
│  │  Feature Title (32–36pt bold, .white)  [CTA ●]  ││  ← title bottom-left; optional solid CTA bottom-right
│  └──────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────┘
```

**Requirements:**
- `.ignoresSafeArea(edges: .top)` on the hero image/gradient container
- Status bar forced to `.lightContent` over dark imagery: `.preferredColorScheme(.dark)` on the hero overlay, or `UIStatusBarStyle.lightContent` via `statusBarHidden(false)` + a transparent UIStatusBar appearance
- Legibility scrim: `LinearGradient(colors: [.clear, Color.black.opacity(0.45)], startPoint: .center, endPoint: .bottom)` overlaid on the hero
- Glass back circle: 40×40pt, `.ultraThinMaterial` fill, white strokeBorder 0.75pt, shadow `black.opacity(0.10) radius:12`
- Glass secondary pill: `.ultraThinMaterial` fill, white strokeBorder, content = SF Symbol icons
- Title: `AMENFont.bold(32–36)` `.white`, positioned with `.frame(maxWidth: .infinity, alignment: .leading)` at hero bottom
- All elements inside `ZStack(alignment: .bottomLeading)`

---

## 5. Glass Capsule Control Spec (search bars, filter bars, composer rows)

```swift
// Standard glass search capsule
HStack { /* content */ }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .background {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.70), .white.opacity(0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.75
            )
        }
    }
    .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 6)
```

---

## 6. Glass Circle Control Spec (back buttons, action orbs)

```swift
ZStack {
    Circle().fill(.ultraThinMaterial)
    Circle().strokeBorder(
        LinearGradient(colors: [.white.opacity(0.68), .white.opacity(0.20)],
                       startPoint: .topLeading, endPoint: .bottomTrailing),
        lineWidth: 0.75
    )
    Image(systemName: symbol)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color(.label))
}
.frame(width: 40, height: 40)
.shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 5)
```

---

## 7. Sheet / Menu Spec (action sheets, context menus, option panels)

```swift
VStack(spacing: 0) {
    // Drag handle (for bottom sheets)
    RoundedRectangle(cornerRadius: 3).fill(.tertiary)
        .frame(width: 36, height: 4).padding(.top, 10)
    
    // Rows: Label(title, systemImage: icon)
    //   .font(.body)
    //   Destructive: .foregroundStyle(.red)
}
.padding(.horizontal, 6)
.background(.regularMaterial)
.cornerRadius(24)
.shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 10)
// reduce-transparency fallback required
```

---

## 8. Floating Tab Bar Spec

- Outer: `Capsule().fill(.ultraThinMaterial)` — never a flat dark Color
- Border: `Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)`
- Shadow: `black.opacity(colorScheme == .dark ? 0.45 : 0.16) radius: 20`
- Tab icons: `.primary` / `.secondary` for unselected; amenGold for selected
- **Reduce transparency fallback**: solid `Color(.systemBackground).opacity(0.92)` + full-opacity border

---

## 9. List Row Spec

```
[Avatar 40pt] [Title .body.semibold / Subtitle .footnote.secondary]  [Trailing control]
```

- Background: `Color(.systemBackground)` — not `Color.white` (breaks dark mode)
- Divider: `Divider()` at 1pt, not hardcoded `Color.black.opacity(0.06)`
- Trailing control: glass circle or `.bordered` button style — not raw `Button { Text("") }`
- Swipe actions: use `.swipeActions` with `.destructive` tint for delete

---

## 10. Elevation / Shadow Scale

| Level | Shadow |
|-------|--------|
| 0 — flat | none |
| 1 — raised control | `black.opacity(0.07) radius: 8 y: 3` |
| 2 — card | `black.opacity(0.08) radius: 14 y: 5` |
| 3 — floating control | `black.opacity(0.10) radius: 12 y: 5` |
| 4 — sheet | `black.opacity(0.12) radius: 24 y: 10` |
| 5 — modal | `black.opacity(0.18) radius: 32 y: 16` |

---

## 11. Animation / Motion Spec

- **All spring animations:** `Motion.adaptive(.spring(response: R, dampingFraction: D))` — never bare `.spring()`, never `.easeInOut` on interactive elements
- **Ambient/decorative:** `.easeInOut` is OK for looping hero orb pulses
- **Reduce motion:** every animated state change must have `reduceMotion ? .none : animation` fallback
- **Tab bar expand/collapse:** response 0.35, dampingFraction 0.85
- **Sheet present:** response 0.38, dampingFraction 0.82

---

## 12. Reading Surface Rule

**Do not apply glass to:**
- Church Notes body editor text area
- Berean AI conversation message bubbles (text body)
- 242 Hub article body text
- Dense scripture reading areas (Selah reader body)

Glass chrome (headers, toolbars, floating controls) ON THESE SCREENS is fine and encouraged. Glass ON the reading text area itself is not.
