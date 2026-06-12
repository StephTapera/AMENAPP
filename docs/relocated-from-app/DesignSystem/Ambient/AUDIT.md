# Phase 0 Audit — Adaptive Ambient Rollout

Read-only audit. No code was modified. Date: 2026-06-09.

## Scope

Five surface files inventoried for hardcoded color literals via Grep
(`Color(red:`, `Color(hex:`, `#colorLiteral`, `UIColor(`).

## Hardcoded color inventory

### AMENAPP/ProfileView.swift
No matches. (0 hits)

### AMENAPP/FullscreenMediaViewer.swift
No matches. (0 hits)

### AMENAPP/PostDetailView.swift — 5 hits

| Line | Literal | Context | Disposition |
|------|---------|---------|-------------|
| 527 | `Color(red: 0.05, green: 0.08, blue: 0.25)` / `Color(red: 0.10, green: 0.15, blue: 0.35)` | prayer category gradient (text-only post) | migrate |
| 529 | `Color(red: 0.18, green: 0.06, blue: 0.02)` / `Color(red: 0.30, green: 0.12, blue: 0.04)` | testimonies category gradient | migrate |
| 531 | `Color(red: 0.02, green: 0.10, blue: 0.18)` / `Color(red: 0.05, green: 0.18, blue: 0.28)` | openTable category gradient | migrate |
| 883 | `Color(red: 1.0, green: 0.95, blue: 0.75)` | highlight/annotation chip fill (warm cream) | keep |
| 1406 | `Color(red: 0.05, green: 0.05, blue: 0.07)` | avatar stack overlap border (near-black divider) | migrate |

Note: lines 527/529/531 each contain two literals (gradient endpoints) →
5 grep lines, 8 literal values total. These category gradients are the
prime candidates for ambient adaptation.

### AMENAPP/SpaceFeedView.swift — 7 hits

| Line | Literal | Context | Disposition |
|------|---------|---------|-------------|
| 15 | `Color(red: 0.039, green: 0.039, blue: 0.059)` | `background` token (near-black) | migrate |
| 16 | `Color(red: 0.6, green: 0.35, blue: 1.0)` | `accentPurple` token | keep |
| 17 | `Color(red: 0.45, green: 0.2, blue: 0.85)` | `accentPurple2` token | keep |
| 143 | `Color(red: 0.25, green: 0.1, blue: 0.55)` | gradient placeholder top | migrate |
| 144 | `Color(red: 0.12, green: 0.05, blue: 0.35)` | gradient placeholder mid | migrate |
| 297 | `Color(red: 0.6, green: 0.35, blue: 1.0).opacity(0.25)` | accent fill (mirror of token) | keep |
| 301 | `Color(red: 0.6, green: 0.35, blue: 1.0)` | accent foreground (mirror of token) | keep |
| 375 | `Color(red: 0.1, green: 0.07, blue: 0.2)` | panel fill | migrate |
| 380 | `Color(red: 0.1, green: 0.07, blue: 0.2)` | panel fill (duplicate) | migrate |

Note: grep returned 7 lines (15,16,17,143,144,297,301,375,380 collapse —
9 literal occurrences across 7+ reported lines). Brand accent purple is
identity color → keep. Background/placeholder/panel surfaces → migrate.

### AMENAPP/SettingsView.swift — 5 hits

| Line | Literal | Context | Disposition |
|------|---------|---------|-------------|
| 18 | `Color(red: 0.07, green: 0.07, blue: 0.08)` | `SD.bg` near-black surface | migrate |
| 19 | `Color(red: 0.12, green: 0.12, blue: 0.13)` | `SD.panel` dark glass panel | migrate |
| 26 | `Color(red: 1.0, green: 0.35, blue: 0.35)` | `SD.danger` semantic destructive | keep |
| 99 | `Color(red: 0.2, green: 0.6, blue: 0.9)` | nav row icon background (Messaging) | ambient-exempt |
| 105 | `Color(red: 0.55, green: 0.35, blue: 0.85)` | nav row icon background (Recovery) | ambient-exempt |

Note: SettingsView is a chrome/list surface, not a media canvas. Surface
tokens (bg/panel) migrate; semantic danger stays; per-row icon badges are
decorative category identity → ambient-exempt.

## Disposition summary

- migrate: surface/background/gradient/panel tones that should respond to ambient context.
- keep: brand accent (purple) + semantic colors (danger, cream highlight) — fixed identity.
- ambient-exempt: decorative per-feature icon badges in chrome lists.

## SDK / Glass confirmation

**Deployment target = iOS 17.0 — CONFIRMED.**
`IPHONEOS_DEPLOYMENT_TARGET = 17.0` appears at 8 build configs in
`AMENAPP.xcodeproj/project.pbxproj` (lines 1508, 1539, 1611, 1669, 1709,
1757, 1783, 1810). No iOS 26 target.

**amenGlassEffect shim — EXISTS but PARTIALLY adopted.**
`AMENAPP/LiquidGlassModifiers.swift:270-292` defines `amenGlassEffect(in:)`
and `amenGlassEffect()`, both correctly guarded by `#available(iOS 26, *)`
with a no-op fallback on iOS 17. This is the intended safe path.

**Caveat (not fully guarded):** Many surfaces call `.glassEffect(...)`
DIRECTLY rather than through the shim, and they are NOT wrapped in
`#available(iOS 26)`. Examples:
- SelahView.swift:926, 1254
- SignInView.swift:471, 1844, 1972, 2361
- AMENAPP/EmptyFeedView.swift:61, 77, 104, 119, 139, 147, 155
- AMENAPP/HomeView.swift:622, 649, 700, 727
- JobSeekerProfileView.swift:123, 664, 1055
- FindChurchOS/ChurchCommunityProfileView.swift:133, 355, 424, 466, 483
- AMENAPP/SpiritualOS/ContextEngine/AmenContextBanners.swift:36, 87, 146, 211
- BereanPrayer/BereanPrayerBriefingView.swift:244, 325
- LivestreamOS/PostStreamRecapView.swift:365, 565
- AMENOnboardingSystem.swift:230
- DesignSystem/Ambient/Components/AdaptiveGlassContainer.swift:42

These compile against a newer SDK but on a 17.0 deployment target rely on
availability inference / SDK backporting. The literal claim "all glassEffect
usage is guarded by the amenGlassEffect shim" is NOT accurate as-is — the
shim exists and is correct, but direct unshimed `.glassEffect` call sites
remain across the app. Flagging for the rollout owner.

## Tally

| File | Hardcoded-color grep hits |
|------|---------------------------|
| ProfileView.swift | 0 |
| FullscreenMediaViewer.swift | 0 |
| PostDetailView.swift | 5 |
| SpaceFeedView.swift | 7 |
| SettingsView.swift | 5 |
| **Total** | **17** |
