# Sanctuary Design Tokens

Frozen: 2026-06-12  
Version: `2026-06-12-wave0-v1`  
Rule: Wave 3+ SwiftUI uses approved GlassKit/Liquid Glass primitives only. These values describe depth, timing, luminance, and tint contracts.

## Glass Pane Elevation

| Level | Surface | Depth | Opacity | Blur | Notes |
| --- | --- | --- | --- | --- | --- |
| Back Plane | Video | `z = 0` | `1.00` | `0` | Edge-to-edge AVPlayer. No decorative frame. |
| L1 | Scripture Thread | `z = 12` | `0.82` | `18` | Edge-mounted, always non-counting. |
| L2 | Sacred Reactions | `z = 24` | `0.76` | `22` | Particle field and warmth scrubber. |
| L3 | Creator Notes | `z = 36` | `0.72` | `26` | Fan-forward layer content. |
| L4 | AI Context | `z = 48` | `0.68` | `30` | Ask-the-Moment and citations. |
| L5 | Group Private | `z = 60` | `0.64` | `34` | Highest privacy prominence; membership-scoped. |

## Scripture Thread Luminance

| Token | Value | Use |
| --- | --- | --- |
| `threadBaseLuminance` | `0.34` | Idle edge rail. |
| `threadAnchorLuminance` | `0.72` | Verse mark at timestamp. |
| `threadActiveLuminance` | `0.92` | Current verse region. |
| `threadBloomLuminance` | `1.00` | Tap-bloom verse card rim. |

## Reaction Particle Palette

| Reaction | Color | Secondary | Motion |
| --- | --- | --- | --- |
| `amen` | `#F8D66D` | `#FFF3B0` | Soft upward drift. |
| `convicted` | `#B86BFF` | `#E1C4FF` | Slow inward pulse. |
| `encouraged` | `#64DFA3` | `#C8F7DE` | Gentle rise and fade. |
| `needPrayer` | `#6FA8FF` | `#D6E7FF` | Gather toward prayer point. |
| `studyingThis` | `#55D6E8` | `#C7F6FC` | Short shimmer along thread. |
| `saved` | `#FFFFFF` | `#D8DEE8` | Brief star pin then fade. |

No token represents a public count. Warmth is rendered only as normalized density.

## Selah Transition Timing

| Phase | Duration | Curve | Reduced Motion |
| --- | --- | --- | --- |
| Video blur out | `420ms` | `cubic-bezier(0.22, 1, 0.36, 1)` | Crossfade to still frame. |
| Verse/prompt card settle | `520ms` | `cubic-bezier(0.16, 1, 0.3, 1)` | Opacity fade only. |
| Quiet hold | `2000ms` | Linear | Static card. |
| Next-video reveal | `480ms` | `cubic-bezier(0.22, 1, 0.36, 1)` | Crossfade; no scale or parallax. |

## Liturgical Tint Table

| Season | Primary Tint | Accent Tint | Scrim |
| --- | --- | --- | --- |
| Ordinary | `#2F8F5B` | `#D6EAD8` | `rgba(8, 20, 14, 0.22)` |
| Advent | `#5B3FA3` | `#D9C7FF` | `rgba(18, 12, 34, 0.28)` |
| Lent | `#6D4C7D` | `#E0CEE7` | `rgba(20, 12, 24, 0.30)` |
| Easter | `#F7F2D2` | `#FFFFFF` | `rgba(42, 38, 20, 0.16)` |
| Pentecost | `#B93A32` | `#FFD6C7` | `rgba(38, 8, 6, 0.26)` |

## Motion Contract

Every Sanctuary animation must route through `Motion.adaptive` or the local equivalent. Reduced-motion fallbacks use opacity and static state changes only; no parallax, particle drift, zoom, or fan transforms.
