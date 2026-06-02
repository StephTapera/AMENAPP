# FROZEN — Design Tokens Contract · Spiritual OS
> Version 1.0 · 2026-06-02 · Lead Orchestrator
> ⚠️ FROZEN. Agents read only. Propose changes by escalating to Lead; Lead re-freezes and re-broadcasts.

---

## 1. Brand Colors

| Swift Token | Hex | Dark-mode Hex | Primary Usage |
|---|---|---|---|
| `amenGold` | `#D4AF37` | `#E8C84A` | CTAs, active state, candlelight accent, streaks (private only) |
| `amenPurple` | `#6B5BFF` | `#8B7FFF` | Berean AI surface, scripture highlights, study |
| `amenBlue` | `#4A90D9` | `#5BA8E8` | Prayer, community, trust indicators |
| `amenBlack` | `#1A1A2E` | `#0D0D1A` | Deep background, primary text on light |
| `amenCream` | `#FFF8F0` | — | Matte reading surface, light-mode card background |
| `amenCharcoal` | `#2C2C3E` | `#1E1E2E` | Dark-mode matte card background |
| `amenWarm` | `#F5E6C8` | `#3D2E1A` | Warm section tint, candlelight atmosphere |

All tokens live in `SpiritualOSComponents.swift` as `extension Color`. Agents do NOT define new colors.

---

## 2. The Glass Rule (ABSOLUTE — zero exceptions)

> **Content is matte. Chrome is glass.**

| Surface | Treatment | Reason |
|---|---|---|
| Scripture text, prayer body, article copy | **Matte** (`amenCream` / `amenCharcoal`) | Readability + reverence |
| Navigation bars, tab bar, floating bars | **Glass** (`.ultraThinMaterial`) | Chrome |
| Navigational/action cards (Space HeroCard, event tile) | **Glass** | Chrome that links to content |
| Content cards (devotional, testimony, church note excerpt) | **Matte** with glass action strip at bottom | Content matte, controls glass |
| Modal sheets | Glass header/handle bar + matte body | Hybrid |
| Tags, chips, role badges | **Glass** (`.ultraThinMaterial`) | Control affordances |

**Test:** If removing glass would make spiritual content harder to read, it is on the wrong surface.

---

## 3. Canonical Glass Treatments

### GlassBar
- Usage: tab bar, navigation bar, floating AssistantBar, sticky section headers
- Material: `.ultraThinMaterial`
- Border: LiquidGlassAdaptiveBorder (white-top 0.38, black-bottom 0.15)
- Corner: capsule when floating; 0pt when pinned full-width

### GlassCard
- Usage: navigational cards that open deeper content (Space card, Hub item, event tile)
- Material: `.ultraThinMaterial`
- Corner radius: 20pt
- Rule: Never place scripture/prayer body text directly on this surface.

### GlassSheet
- Usage: modal bottom sheets (Create Space, Tier Setup, permissions)
- Material: `.thinMaterial`
- Top corners: 28pt; bottom corners: 0pt (full-screen) or 20pt (card modal)
- Handle: 4x28pt rounded rect, opacity 0.3
- Body: Matte (amenCream / amenCharcoal)

### GlassChip
- Usage: faith-native tags, filter pills, pastoral role badges
- Material: `.ultraThinMaterial`
- Heights: small=28pt / default=32pt / large=40pt
- Corner: Capsule
- Selected state: amenGold tint fill, white label

### HeroCard
- Usage: Space/community featured card on dashboard
- Cover region: image with matte gradient scrim
- Content region: Matte (title, subtitle, avatars, next event) — NOT glass
- Action row: GlassBar across bottom (Pray Together / Schedule / Notes / Ask Berean)
- Corner: 24pt

---

## 4. Mood Reference
Warm candlelight. Parchment. Evening study lamp. Never clinical or cold.
- Light mode: amenCream backgrounds, gold accents, warm amber shadows
- Dark mode: amenBlack/amenCharcoal backgrounds, gold edge highlights, candlelight glow on glass

---

## 5. Typography Scale

| Token | Size | Weight | Usage |
|---|---|---|---|
| `digestGreeting` | 28pt | .light | "Good morning, {name}..." |
| `sectionHeader` | 17pt | .semibold | Section headings |
| `cardTitle` | 15pt | .medium | Card primary label |
| `cardBody` | 14pt | .regular | Card secondary / preview text |
| `chipLabel` | 12pt | .medium | Tags, chips |
| `timestamp` | 12pt | .regular | Timestamps, metadata |
| `verseText` | 16pt | .regular | Scripture body (always on matte) |

---

## 6. Motion System

All animations pass through `Motion.adaptive` (see `AnimationTokens.swift`).

| Animation type | Normal | Reduce Motion |
|---|---|---|
| Glass morph / layout | Spring: 0.28s response, 0.82 damping | Fade 0.2s |
| Page / tab | ease-in-out 0.22s | Fade 0.15s |
| Sheet present/dismiss | Spring: 0.35s, 0.85 | Cross-fade 0.25s |
| Low power mode | Disable specular, simplify materials | Same as reduce-motion |

---

## 7. Spacing

```
cornerRadiusSmall    = 10
cornerRadiusMedium   = 16
cornerRadiusLarge    = 24   // HeroCard
pillHeightSmall      = 32
pillHeightDefault    = 40
insetStandard        = 16
insetTight           = 8
insetLoose           = 24
```
