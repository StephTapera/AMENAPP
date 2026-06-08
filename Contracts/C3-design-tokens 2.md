# Contract C3 — White Liquid Glass Design Token Specification
**Phase 0 | FROZEN 2026-06-05**

Status: LOCKED. Design direction is white Liquid Glass (Apple Photos / Mail aesthetic).
Amendments require a RUNLOG entry and explicit approval.

---

## 1. Surfaces

| Token | Value | Notes |
|---|---|---|
| Page background | `Color(uiColor: .systemGroupedBackground)` (~`#F2F2F7` light) | Never use a custom hex |
| Card / sheet | `Color.white` (`#FFFFFF`) in light; `Color(uiColor: .secondarySystemGroupedBackground)` in dark | Cards must be white, not tinted |
| Grouped list row | `Color(uiColor: .secondarySystemGroupedBackground)` | iOS standard grouped row |

**Rule: No card-on-card glass stacking.** A glass card may contain plain content or a photo. It must not contain another glassEffect surface.

---

## 2. Typography

| Role | Token | Notes |
|---|---|---|
| Font family | `.system` (SF Pro) — Dynamic Type only | **No custom display face** |
| Primary text | `Color(uiColor: .label)` (`#000000` light) | Highest emphasis |
| Secondary text | `Color(uiColor: .secondaryLabel)` | Supporting content, metadata |
| Tertiary text | `Color(uiColor: .tertiaryLabel)` | Timestamps, captions |
| Placeholder | `Color(uiColor: .placeholderText)` | Input fields |
| Emphasis | Weight carries emphasis — `.regular` body, `.semibold` or `.bold` key phrase | No color emphasis on non-interactive text |
| Text styles | iOS Dynamic Type only: `.largeTitle`, `.title`, `.title2`, `.title3`, `.headline`, `.subheadline`, `.body`, `.callout`, `.footnote`, `.caption`, `.caption2` | |

### PURGE: Cormorant Garamond

Every occurrence of Cormorant must be removed and replaced with `.system` (SF Pro) at an appropriate Dynamic Type size.

| File | Line | Legacy token | Replacement |
|---|---|---|---|
| `AMENAPP/AMENAPP/Notifications/Views/AmenNotificationCard.swift` | 93 | `Font.custom("CormorantGaramond-SemiBold", size: 22)` | `.system(.title2, design: .default).weight(.semibold)` |

---

## 3. Color

### Canonical palette

| Token | Value | Use |
|---|---|---|
| Primary text / icon | `Color(uiColor: .label)` | Body text, primary icons |
| Secondary text / icon | `Color(uiColor: .secondaryLabel)` | Supporting text |
| Tertiary | `Color(uiColor: .tertiaryLabel)` | Captions, metadata |
| Interactive accent | `Color.accentColor` (iOS system tint, `.blue` default) | Links, toggles, selection rings, progress |
| Separator | `Color(uiColor: .separator)` | Dividers |
| Page background | `Color(uiColor: .systemGroupedBackground)` | Root background |
| Card background | `Color.white` | Cards, sheets |

### Principles

- **Monochrome-first.** Black, white, and neutral system grays carry the UI.
- **Single restrained accent.** iOS system accent only — for interactive affordances (links, toggles, selection states). Not for decoration.
- **No brand color palette.**
- **No gradients as brand surfaces.** Gradient use is limited to: (a) bottom scrim for hero text legibility, (b) specular edge highlight on glass.

### PURGE: Gold tokens

Replace all with system semantic colors or the interactive accent where applicable.

**`#C9A84C` / `amenGold` / `amenGoldText` / `amenGoldGradient`** — appears in 101 files. Key files (non-exhaustive sample):

| File | Approx. lines | Action |
|---|---|---|
| `AMENAPP/AmenAdaptiveColors.swift` | 133–139 | Remove `amenGold`, `amenGoldText` definitions |
| `AMENAPP/AmenColorScheme.swift` | 100–107, 143, 161, 184, 231, 336 | Remove `amenGoldGradient`, UIColor.amenGold |
| `AMENAPP/AMENAPP/DesignSystem/GlassMaterial.swift` | 101–116 | Remove `NotifGlassTokens.goldPrimary`, `.goldLight`, `.goldGradient`, `.primaryButtonGradient` |
| `AMENAPP/AMENAPP/ONE/Design/ONETokens.swift` | 27, 39 | Remove `decayAmber` (uses amenGold), `witnessGold`, `subscriberGold` |
| `AMENAPP/CreatorOS/CreatorPrivateMetricsDashboard.swift` | 118, 124, 134, 138, 184 | Replace with `Color.accentColor` or `Color(uiColor: .label)` |
| `AMENAPP/CreatorOS/CreatorMonetizationView.swift` | 63, 133, 200 | Replace |
| `AMENAPP/TipSheetView.swift` | 31 | Remove local `amenGold` definition |
| `AMENAPP/CoCreationSummaryView.swift` | 24, 125, 160 | Remove local definition |
| `AMENAPP/VergeCreatorStudioView.swift` | 26, 122, 178, 270, 325 | Remove local definition |
| `AMENAPP/TipView.swift` | 29 | Remove local definition |
| `AMENAPP/VergeCreateRoomSheet.swift` | 30, 198, 201 | Remove |
| `AMENAPP/CreatorTrustBadgeView.swift` | 32, 55–76, 174, 186, 195–203 | Replace with `Color(uiColor: .label)` + system |
| `AMENAPP/SpotlightCard.swift` | 134, 269, 306 | Replace |
| `AMENAPP/Shared/DesignSystem/GlassTabBar.swift` | 87, 93 | Replace selected tab with `Color.accentColor` |
| `AMENAPP/IntegrationOS/ExternalIntegrationView.swift` | 288–608 (multiple) | Replace throughout |
| `AMENAPP/RouterOS/RouteSuggestionsView.swift` | 27, 58, 66 | Replace |
| `AMENAPP/SafetyOS/CrisisInterventionView.swift` | 19, 64, 106 | Replace |
| `AMENAPP/SafetyOS/PrePublishSafetyGate.swift` | 73 | Replace |
| `AMENAPP/MessagingOS/MessagingAttachmentMenu.swift` | 99 | Replace |
| `AMENAPP/MessagingOS/MessageLongPressMenu.swift` | 67 | Replace |
| `AMENAPP/MessagingOS/CatchMeUpBanner.swift` | 27, 93 | Replace |
| `AMENAPP/Shared/DesignSystem/ContentCardView.swift` | 43, 110 | Replace |
| `AMENAPP/ChurchNotesDesignSystem.swift` | 21 (`amenGoldLight`) | Remove |
| `AMENAPP/ChurchNotesOS/BereanHighlightMenu.swift` | 92, 108 | Replace |
| `AMENAPP/ContentFlowOS/DiscussionModePickerView.swift` | 22, 35, 56 | Replace |
| `AMENAPP/ContentFlowOS/ApprovalSheetView.swift` | 93, 148, 157, 172, 207 | Replace |
| `AMENAPP/FindChurchOS/ChurchCommunityProfileView.swift` | 115–298 (multiple) | Replace |
| `AMENAPP/VergeRoomSummaryView.swift` | 24, 213, 238 | Replace |
| *(+ 72 additional files — see `amenGold` grep output)* | | |

**`#FFD97D`** — appears in 29 files. Primary concentration:

| File | Approx. lines | Action |
|---|---|---|
| `AMENAPP/AMENAPP/DesignSystem/GlassMaterial.swift` | 107, 113 | Remove `NotifGlassTokens.goldLight`, gradient |
| `AMENAPP/TestimonyViralSheet.swift` | 137–334 (multiple) | Replace throughout |
| `AMENAPP/PrayerRecapCardView.swift` | 101, 149, 155, 169–173 | Replace |
| `AMENAPP/AMENAPP/Notifications/Views/AmenNotificationCard.swift` | 259, 290 | Replace |
| `AMENAPP/AMENAPP/Settings/NotificationSettingsView.swift` | 122 | Replace |
| `AMENAPP/PostCard.swift` | 3586 | Replace |
| `AMENAPP/BereanPrayer/BereanPrayerJournalView.swift` | — | Replace |
| `AMENAPP/BereanPrayer/BereanPrayerBriefingView.swift` | — | Replace |
| `AMENAPP/Discussion/DiscussionHealthEngine.swift` | — | Replace |
| `AMENAPP/Discussion/DiscussionSummaryView.swift` | — | Replace |
| `AMENAPP/Discussion/DiscussionCommandCenterView.swift` | — | Replace |
| `AMENAPP/BereanMentorship/BereanMentorshipModels.swift` | — | Replace |
| `AMENAPP/OnboardingQuizView.swift` | — | Replace |
| *(+ remaining 16 files in the C9A84C/FFD97D grep result set)* | | |

### PURGE: Purple accent

**`#7B68EE` / `accentPurple`** — Replace with `Color.accentColor` (iOS system blue) for interactive affordances, or `Color(uiColor: .secondaryLabel)` for decorative.

| File | Line | Action |
|---|---|---|
| `AMENAPP/AMENAPP/DesignSystem/GlassMaterial.swift` | 103 | Remove `NotifGlassTokens.accentPurple` definition |
| `AMENAPP/AMENAPP/Settings/NotificationSettingsView.swift` | 122 | Replace gradient using #7B68EE |
| `AMENAPP/AMENAPP/Notifications/Views/AmenNotificationCard.swift` | 259, 290 | Replace `toneColors` tuples |
| `AMENAPP/PostCard.swift` | 3586 | Replace `toneColors` tuple |

### PURGE: Dark brand colors

**`amenDarkPrimary` / `amenDarkSecondary` / `amenDarkTertiary` / `amenBlack` / `amenMainGradient`** — dark-theme backgrounds must not appear in the white Liquid Glass system. All 26 files in the dark-bg grep set need audit.

Key definition files:
- `AMENAPP/AmenColorScheme.swift` lines 17–96 — dark bg definitions; migrate callers to `Color(uiColor: .systemBackground)` or `Color(uiColor: .systemGroupedBackground)`.

### PURGE: `cosmicDark` (`#0D0D1A`)

| File | Line | Action |
|---|---|---|
| `AMENAPP/AMENAPP/DesignSystem/GlassMaterial.swift` | 104 | Remove `NotifGlassTokens.cosmicDark` definition |
| `GlassMaterial.swift` preview section | 123–125 | Update preview background |

### PURGE: `amenCream` (`#F8F4EC`) and `amenSlate` (`#4A4A55`)

| File | Line | Action |
|---|---|---|
| `AMENAPP/AMENAPP/SpiritualOS/SOColors.swift` | 6–7 | Migrate to `Color(uiColor: .systemGroupedBackground)` and `Color(uiColor: .secondaryLabel)` |

### Gold-tinted ONE tokens to purge

| File | Token | Action |
|---|---|---|
| `AMENAPP/AMENAPP/ONE/Design/ONETokens.swift` | `ONE.Colors.glassWarm` (amber tint) | Replace with neutral/white glass tint |
| `AMENAPP/AMENAPP/ONE/Design/ONETokens.swift` | `ONE.Colors.decayAmber` (uses amenGold) | Replace with `Color.orange.opacity(0.6)` |
| `AMENAPP/AMENAPP/ONE/Design/ONETokens.swift` | `ONE.Colors.witnessGold`, `subscriberGold` | Replace with `Color.accentColor` or system badge colors |
| `AMENAPP/AMENAPP/ONE/Design/ONETokens.swift` | `ONE.Colors.privateIndigo` (custom purple) | Replace with `Color.accentColor` |

---

## 4. Corner Radius

| Context | Value | Style |
|---|---|---|
| Card / bottom sheet | 28–32pt | `.continuous` (squircle, not circular) |
| Photo hero within card | 20–24pt | `.continuous` |
| Pill / capsule | Fully rounded (`Capsule()`) | — |
| Circular single-glyph button | Equal width/height, `.clipShape(Circle())` | — |
| Input field | 14–18pt | `.continuous` |
| Chip | Fully rounded | — |

**Reference:** `LiquidGlassTokens` already has `cornerRadiusLarge: 32`, `cornerRadiusMedium: 22` — these are the correct values for C3.

---

## 5. Elevation

One ambient shadow token only. No hard, colored, or multi-layer shadows.

| Token | Color | Opacity | Radius | Offset |
|---|---|---|---|---|
| `AmenShadow.card` | `.black` | 6–8% | 20–28pt blur | `x: 0, y: 4–6` |
| `AmenShadow.floating` | `.black` | 10–12% | 28–36pt blur | `x: 0, y: 8–12` |

No colored shadows. No shadows derived from brand colors (e.g., no `amenGold` glow).

---

## 6. Materials / Glass

| Use case | Material / API |
|---|---|
| Standard glass panel | `.regularMaterial` (SwiftUI) |
| Subtle glass (toolbar overlaid on content) | `.thinMaterial` |
| Ultra-subtle glass (sheet peek) | `.ultraThinMaterial` |
| iOS 26 adaptive glass | `.glassEffect()` + `GlassEffectContainer` |
| Over-photo dark pill (Directions pattern) | Dark translucent glass: `.ultraThinMaterial` + `.colorScheme(.dark)` forced, or `Material` + dark tint |
| Hero text scrim | `LinearGradient(.black.opacity(0), .black.opacity(0.35))` bottom-anchored on photo |

**Rule: glass must be white/clear, not gold-tinted or cosmically dark.** The `glassWarm` amber tint in `ONETokens` violates this contract and is in the purge list.

---

## 7. Icons

- Monochrome only: SF Symbols line-weight glyphs
- Consistent stroke weight: `.regular` weight SF Symbol unless hierarchy demands `.bold` (primary action only)
- Color: `Color(uiColor: .label)` on white backgrounds; white on dark overlay pills
- No filled color-tinted icons except for system status colors (red destructive, etc.)

---

## 8. Controls

### Segmented Selector (For You / Library pattern)

The canonical "For You / Library" style:
- Track: `Color(uiColor: .secondarySystemFill)` (light gray)
- Selected pill: `Color.white` + `AmenShadow.card`
- Selected label: `Color(uiColor: .label)` — black, `.semibold`
- Unselected label: `Color(uiColor: .secondaryLabel)` — gray, `.regular`
- Track corner radius: fully rounded (`Capsule`)

Component: `AmenSegmentedSelector`

### Toolbar / Action Pill (Mail toolbar / Action Pill pattern — A18)

This is the universal Action Pill:
- Primary action: circular button, white fill + `AmenShadow.floating`, `.bold` SF Symbol
- Secondary actions: horizontal capsule of line icons, white fill + `AmenShadow.card`
- Separator between icon groups: `Color(uiColor: .separator)` hairline
- Background container: `Color.clear` — pill floats above content

Component: `AmenActionPill` / `AmenToolbar` (same underlying component, different binding site)

---

## 9. Accessibility Tokens

| Requirement | Implementation |
|---|---|
| Dynamic Type | All font sizes via Dynamic Type text styles only — never fixed `size:` |
| Reduced Motion | Gate all spring/bounce animations behind `@Environment(\.accessibilityReduceMotion)` |
| Reduced Transparency | Swap glass materials to solid `Color(uiColor: .systemBackground)` when `reduceTransparency == true` |
| Color semantic names | Always use semantic system color names — never hardcoded hex for UI-critical colors |
| Minimum touch target | 44×44pt for all interactive controls |
| Contrast | Text on white card: `Color(uiColor: .label)` guarantees system-managed contrast |

---

## 10. Component API Surface

Signatures only — no implementations in Phase 0.

```swift
// AmenCard
struct AmenCard<Content: View>: View {
    var content: () -> Content
    var elevation: AmenShadow.Level          // .card | .floating
    var cornerRadius: CGFloat                // defaults to AmenRadius.card
}

// AmenHeroCard
struct AmenHeroCard: View {
    var image: Image
    var title: String
    var subtitle: String?
    var actionPill: AmenActionPill?
}

// AmenSegmentedSelector
struct AmenSegmentedSelector: View {
    var segments: [String]
    @Binding var selection: Int
}

// AmenActionPill
struct AmenActionPill: View {
    var actions: [AmenPillAction]
    @Binding var isExpanded: Bool
    var onExpand: (() -> Void)?
}

// AmenGlassOverlayPill  — for over-photo use (Directions button pattern)
struct AmenGlassOverlayPill: View {
    var label: String
    var icon: String                         // SF Symbol name
}

// AmenToolbar
struct AmenToolbar: View {
    var leadingActions: [AmenPillAction]
    var primaryAction: AmenPillAction
    var trailingActions: [AmenPillAction]
}
```

---

## 11. PURGE Manifest — Complete Summary

The following tokens, colors, fonts, and named values must be removed or replaced before any
white Liquid Glass component goes into code review.

### Font

| Token | Files | Replacement |
|---|---|---|
| `Font.custom("CormorantGaramond-…", size:)` | `AmenNotificationCard.swift:93` | `.system` Dynamic Type |

### Gold Color Family

| Token | Definition file | All consumer files |
|---|---|---|
| `Color.amenGold` | `AmenAdaptiveColors.swift:134` | 101 Swift files (see grep set) |
| `Color.amenGoldText` | `AmenAdaptiveColors.swift:139` | (subset of above) |
| `UIColor.amenGold` | `AmenColorScheme.swift:143` | — |
| `Color.amenGoldGradient` | `AmenColorScheme.swift:100` | — |
| `NotifGlassTokens.goldPrimary` (#C9A84C) | `GlassMaterial.swift:101` | (see #C9A84C grep) |
| `NotifGlassTokens.goldLight` (#FFD97D) | `GlassMaterial.swift:102` | (see #FFD97D grep) |
| `NotifGlassTokens.goldGradient` | `GlassMaterial.swift:106` | — |
| `NotifGlassTokens.primaryButtonGradient` | `GlassMaterial.swift:112` | — |
| `ONE.Colors.witnessGold` | `ONETokens.swift:31` | — |
| `ONE.Colors.subscriberGold` | `ONETokens.swift:39` | — |
| `ONE.Colors.decayAmber` | `ONETokens.swift:27` | — |
| `ChurchNotesDesignSystem.amenGoldLight` | `ChurchNotesDesignSystem.swift:21` | — |
| `Color(hex: "F59E0B")` (local) | `TipSheetView.swift:31`, `VergeCreatorStudioView.swift:26`, `VergeCreateRoomSheet.swift:30`, `VergeRoomSummaryView.swift:24` | — |
| `Color(red:0.96,green:0.62,blue:0.04)` (local) | `CoCreationSummaryView.swift:24`, `TipView.swift:29`, `CreatorTrustBadgeView.swift:32,186` | — |

### Purple Accent Family

| Token | Definition file | Consumer files |
|---|---|---|
| `NotifGlassTokens.accentPurple` (#7B68EE) | `GlassMaterial.swift:103` | `NotificationSettingsView.swift:122`, `AmenNotificationCard.swift:259,290`, `PostCard.swift:3586` |
| `ONE.Colors.privateIndigo` | `ONETokens.swift:33` | — |

### Dark Brand Backgrounds

| Token | Definition file | Consumer files |
|---|---|---|
| `Color.amenDarkPrimary` | `AmenColorScheme.swift:17` | 26 files (see dark-bg grep set) |
| `Color.amenDarkSecondary` | `AmenColorScheme.swift:21` | — |
| `Color.amenDarkTertiary` | `AmenColorScheme.swift:24` | — |
| `Color.amenBlack` | `AmenColorScheme.swift:27` | — |
| `Color.amenMainGradient` | `AmenColorScheme.swift:87` | — |
| `UIColor.amenDarkPrimary` | `AmenColorScheme.swift:137` | — |
| `UIColor.amenDarkSecondary` | `AmenColorScheme.swift:140` | — |

### Cosmic / Dark Panel

| Token | Definition file | Notes |
|---|---|---|
| `NotifGlassTokens.cosmicDark` (#0D0D1A) | `GlassMaterial.swift:104` | Also in preview background |
| `glassSurface` reduceTransparency fallback `#1A1A2E` | `GlassMaterial.swift:49` | Migrate to `Color(uiColor: .systemBackground)` |

### Warm Cream / Tinted Glass

| Token | Definition file | Notes |
|---|---|---|
| `Color.amenCream` (#F8F4EC) | `SOColors.swift:6` | Migrate to `systemGroupedBackground` |
| `Color.amenSlate` (#4A4A55) | `SOColors.swift:7` | Migrate to `secondaryLabel` |
| `ONE.Colors.glassWarm` (amber tint) | `ONETokens.swift:21` | Replace with neutral glass |
| `ONE.Colors.glassCool` (blue tint) | `ONETokens.swift:24` | Acceptable only if used for accessibility-only zone indicators, not brand decoration |

---

## 12. What is NOT purged

The following existing tokens are **compatible** with C3 and should be retained:

- `LiquidGlassTokens` (`cornerRadiusSmall/Medium/Large`, `blurThin/Regular/Elevated`, `shadowSoft/Floating`) — values align with C3
- `AmenGlassDesignTokens` (`AmenGlassMetrics`, `AmenGlassBehavior`) — behavioral constants, not color tokens; retain
- `AmenTheme.Colors.*` — all semantic wrappers over system colors; fully compatible
- `ChurchNotesDesignTokens` — color-neutral, uses system semantic colors; retain
- `GlassSurfaceModifier` core glass surface behavior — retain; update reduceTransparency fallback only
- `LiquidGlassModifiers.swift` (`LiquidGlassStyle`, `FloatingPillStyle`, etc.) — white-glass pattern; fully compatible

---

*End of Contract C3 — Design Tokens*
