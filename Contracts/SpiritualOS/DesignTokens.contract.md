# Design Tokens Contract — Spiritual OS
## STATUS: FROZEN · Do not edit without Lead Orchestrator sign-off

---

## Color Palette (AMEN canonical — no system colors in primary positions)

| Token        | Light mode                  | Dark mode                   | Role |
|--------------|-----------------------------|-----------------------------|------|
| `amenGold`   | `#C9A84C` (warm gold)       | `#D4AF5A` (lifted)          | Primary accent, active states, scripture highlights |
| `amenPurple` | `#6B4FA2` (deep violet)     | `#8E6EC8` (lifted)          | Spiritual depth, Berean AI, prayer surfaces |
| `amenBlue`   | `#2E6DA4` (calm cobalt)     | `#4D90C4` (lifted)          | Community, events, Church Notes |
| `amenBlack`  | `#1A1A1E` (near-black)      | `#0D0D10` (OLED dark)       | Primary text, structural anchors |
| `amenCream`  | `#F8F4EC` (warm off-white)  | `#1E1B14` (warm dark)       | Content backgrounds — NEVER glass |
| `amenSlate`  | `#4A4A55` (warm grey)       | `#9090A0`                   | Secondary text, captions |

**Rule: Primary actions and active states use `amenGold` or `amenPurple` only. Apple system blue (`Color.blue`, `.accentColor`) is FORBIDDEN in new Spiritual OS surfaces.**

---

## The Fundamental Glass Rule

> **Content is matte. Chrome is glass.**

| Layer | Material | Rationale |
|---|---|---|
| Scripture text, prayer prose, post body | `.clear` on `amenCream`/`amenBlack` backgrounds | Reading content must never sit on animated, refractive glass — it triggers motion sensitivity and hurts legibility |
| Cards containing content (non-reading) | `LiquidGlassCard` (existing component) | Brief, glanceable items: event cards, digest bullets, member chips |
| Navigation bars, tab bars, composer bars | `.glassEffect` (iOS 26 native) or `LiquidGlassMaterial(.blurThin)` | Chrome — users expect translucency here |
| Floating sheets, action trays | `GlassSheet` primitive (see SharedComponents) | Elevated glass, `elevated: true` |
| Persistent Assistant Bar | `GlassBar` primitive | Floating chrome |

**Glass-on-glass is FORBIDDEN.** A `GlassCard` inside a `GlassSheet` must use a matte inner background, not another glass layer.

---

## Existing Token References (do NOT re-declare these)

These are already defined in `LiquidGlassTokens.swift` and must be consumed as-is:

```swift
LiquidGlassTokens.cornerRadiusSmall   // 14
LiquidGlassTokens.cornerRadiusMedium  // 22
LiquidGlassTokens.cornerRadiusLarge   // 32
LiquidGlassTokens.capsuleRadius       // 999 (pill shape)

LiquidGlassTokens.blurThin            // .ultraThinMaterial
LiquidGlassTokens.blurRegular         // .thinMaterial
LiquidGlassTokens.blurElevated        // .regularMaterial

LiquidGlassTokens.motionFast          // 0.18s
LiquidGlassTokens.motionNormal        // 0.32s
LiquidGlassTokens.motionSlow          // 0.55s
```

And existing `BereanGlass.Impl` presets (`lensed`, `contextual`, `compressed`) via `BereanGlassSystem.swift`.

---

## Canonical Glass Treatments

### Treatment 1 — `contextual` (default, balanced)
- **Use on:** Home digest cards, Hub inbox rows, Life Planner day rows, Assistant Bar suggestions
- **Material:** `LiquidGlassMaterial(tint: nil, elevated: false)` → `blurThin`
- **Corner radius:** `cornerRadiusMedium` (22)
- **Shadow:** `shadowSoft` (8% black, 14pt radius)
- **Tint:** contextual — pass Space's theme color if available

### Treatment 2 — `lensed` (hero, premium)
- **Use on:** Spaces `HeroCard`, Daily Digest hero area, Worship Mode overlay, full-screen sheets
- **Material:** `LiquidGlassMaterial(tint: spaceColor, elevated: true)` → `blurElevated`
- **Corner radius:** `cornerRadiusLarge` (32)
- **Shadow:** `shadowFloating` (12% black, 24pt radius)
- **Tint:** must bleed the Space's `amenColor` tint (amenGold / amenPurple / amenBlue)

### Treatment 3 — `compressed` (dense, efficient)
- **Use on:** Hub swipe rows, Command Center stats, planner timeline items, chip rails
- **Material:** `LiquidGlassMaterial(tint: nil, elevated: false)` → `blurThin`
- **Corner radius:** `cornerRadiusSmall` (14)
- **Shadow:** none (use separator lines instead)

---

## Motion Rules

All animation must be wrapped in a reduce-motion guard:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

let spring = reduceMotion
    ? Animation.easeOut(duration: LiquidGlassTokens.motionFast)
    : Animation.spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82)
```

This is **`Motion.adaptive`** as referenced in the Phase 2 instructions — agents must implement it exactly this way, not via a custom animation modifier that bypasses the environment.

| Motion class | Spring response | Damping | Use |
|---|---|---|---|
| Fast (micro) | 0.18s | 0.90 | Button presses, chip selection |
| Normal (transition) | 0.32s | 0.82 | Card appear, sheet present |
| Slow (hero) | 0.55s | 0.75 | HeroCard morph, Context Mode switch |

---

## Faith-Formation UI Rules (visual enforcement)

- No numeric engagement metrics on any card visible to others (likes, view counts, streak counts in shared surfaces)
- Formation counts (reading days, prayer count) are shown ONLY in private `CommandCenter`/`AmenLife` surfaces, styled as a warm `GlassChip` — never a bold headline number
- No infinite scroll in new surfaces — use paginated `TimelineRow` lists with "Load more" affordance
- Spiritual counters are never colored red/orange (urgency hue) — use `amenGold` or `amenSlate`
- Berean AI suggestions are styled as invitations (italic, lighter weight) not commands
