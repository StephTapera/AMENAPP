# Berean Design System Audit

**Audited by:** Agent B (Design System Audit)
**Date:** 2026-05-27
**Files reviewed:** BereanDesignSystem.swift, BereanComposerBar.swift, BereanChatView.swift (lines 1–300), BereanGlassComposer.swift, BereanEnhancedComponents.swift, BereanLayoutMetrics.swift, BereanAnimationCoordinator.swift, BereanStructuredCardView.swift, BereanFollowUpChips.swift, BereanSmartPillSystem.swift

---

## Overall Health: 4 / 10

The token infrastructure (BereanColor, BereanType, BereanLayoutMetrics, BereanAnimationCoordinator) is solid and well-architected. The design system files that were written first — BereanDesignSystem.swift, BereanComposerBar.swift — largely follow the rules. However, two major problem clusters drag the score down heavily:

1. **BereanEnhancedComponents.swift** is a wholesale typography and animation violation zone: nearly every font call is `.font(.system(size:weight:))` and non-spring animations appear throughout.
2. **BereanStructuredCardView.swift** hard-codes all 7 accent colors with raw RGB values, completely bypassing the token system.
3. **BereanAnimationCoordinator.swift** ships named `fade`, `slowFade`, `microFade`, and `pulseAnimation` helpers that are `.easeOut`/`.easeInOut` — these get used by call sites that expect "spring or nothing."

---

## Hardcoded Colors (violations)

| File | Line | Value | Recommended Token |
|------|------|-------|-------------------|
| BereanChatView.swift | 15 | `Color(red: 0.956, green: 0.956, blue: 0.936)` — background fill | `BereanColor.background` |
| BereanChatView.swift | 19 | `Color(red: 0.94, green: 0.95, blue: 0.93)` — gradient stop | `BereanColor.background` (or named warm-white token) |
| BereanChatView.swift | 20 | `Color(red: 0.98, green: 0.965, blue: 0.94)` — gradient stop | `BereanColor.background` |
| BereanStructuredCardView.swift | 26 | `Color(red: 0.48, green: 0.36, blue: 0.75)` — .prayer accent | `Color.amenPurple` |
| BereanStructuredCardView.swift | 27 | `Color(red: 0.22, green: 0.65, blue: 0.87)` — .decision accent | `Color.amenBlue` |
| BereanStructuredCardView.swift | 28 | `Color(red: 0.30, green: 0.72, blue: 0.45)` — .meal accent | needs a named `Color.amenGreen` token |
| BereanStructuredCardView.swift | 29 | `Color(red: 0.92, green: 0.53, blue: 0.23)` — .debate accent | needs a named `Color.amenAmber` token |
| BereanStructuredCardView.swift | 30 | `Color(red: 0.85, green: 0.30, blue: 0.25)` — .factCheck accent | needs a named `Color.amenCoral` token |
| BereanStructuredCardView.swift | 31 | `Color(red: 0.55, green: 0.20, blue: 0.20)` — .crisis accent | needs a named `Color.amenCrisis` token |
| BereanStructuredCardView.swift | 32 | `Color(red: 0.45, green: 0.45, blue: 0.52)` — .generic accent | needs a named `Color.amenSlate` token |
| BereanStructuredCardView.swift | 202 | `Color(white: 0.13)` — dark mode card background | `AmenTheme.Colors.surfaceCard` (or `BereanColor.aiBubbleBg`) |
| BereanStructuredCardView.swift | 268 (preview) | `Color(red: 0.97, green: 0.97, blue: 0.97)` — preview bg | `BereanColor.background` |
| BereanSmartPillSystem.swift | 341 | `Color(red: 0.85, green: 0.25, blue: 0.30)` — safety pill fill | needs a named `Color.amenCrisis` / `Color.amenDanger` token |
| BereanComposerBar.swift | 814–820 | `Color(red: 0.95, green: 0.78, blue: 0.38)` — voice pulse radial | `Color.amenGold` |
| BereanDesignSystem.swift | 249 | `Color(uiColor: .secondarySystemBackground)` — AI bubble fill | acceptable system adaptive color; not a strict violation but not a named BereanColor token |
| BereanDesignSystem.swift | 343 | `Color.black.opacity(0.78)` on AMEN badge text | `BereanColor.textPrimary` or `Color.amenBlack` |
| BereanGlassComposer.swift | 161 | `Color(hex: "DC3232")` — streaming stop button fill | needs a named `Color.amenDanger` / `Color.amenCrisis` token |

**Additional `.background(Color.black)` / `.background(Color.white)` hardcoded instances:**

| File | Line | Value | Note |
|------|------|-------|------|
| BereanDesignSystem.swift | 243 | `.fill(Color.black)` — user bubble | Use `Color.amenBlack` or `AmenTheme.Colors.textPrimary` |
| BereanComposerBar.swift | 427 | `.fill(Color.black.opacity(0.82))` — stop button | Use `Color.amenBlack` with opacity modifier |
| BereanComposerBar.swift (preview) | 883 | `.background(Color.white)` | Use `BereanColor.background` |
| BereanComposerBar.swift | 296–297 | `Color.white.opacity(0.13)` / `Color.black.opacity(0.055)` — utility button | Could use `BereanColor.glassFill` / `BereanColor.glassBorder` |
| BereanEnhancedComponents.swift | 303 | `.fill(Color.white)` — selected mode tab bg | `BereanColor.background` or `AmenTheme.Colors.surfaceCard` |

---

## Non-Spring Animations (violations)

| File | Line | Current Animation | Recommended Spring |
|------|------|-------------------|--------------------|
| BereanDesignSystem.swift | 219 | `.linear(duration: 0)` used as reduce-motion fallback | Acceptable (0-duration, invisible); not a user-facing violation |
| BereanDesignSystem.swift | 276 | `.easeInOut(duration: 0.55).repeatForever()` — thinking dots | Use spring pulse (or retain as nil when reduceMotion; document it's a repeating loop where linear/ease is conventional) |
| BereanAnimationCoordinator.swift | 38 | `static var fade: Animation { .easeOut(duration: 0.18) }` | Rename to `staticFade`; callers should use spring for motion, fade only for pure opacity |
| BereanAnimationCoordinator.swift | 42 | `static var slowFade: Animation { .easeOut(duration: 0.30) }` | Same — document as opacity-only helper |
| BereanAnimationCoordinator.swift | 46 | `static var microFade: Animation { .easeOut(duration: 0.12) }` | Same |
| BereanAnimationCoordinator.swift | 55 | `adaptive(_:reduceMotion:)` returns `.easeOut(duration: 0.18)` for reduced-motion path | Acceptable for accessibility fallback only |
| BereanAnimationCoordinator.swift | 60 | `adaptiveSoftSpring` returns `.easeOut(duration: 0.22)` for reduced-motion path | Acceptable for accessibility fallback only |
| BereanAnimationCoordinator.swift | 65 | `adaptiveStudySpring` returns `.easeOut(duration: 0.25)` for reduced-motion path | Acceptable for accessibility fallback only |
| BereanAnimationCoordinator.swift | 73 | `pulseAnimation` returns `.easeInOut(duration: 1.6).repeatForever()` | Acceptable for a pulse loop; spring doesn't repeat well; document exemption |
| BereanEnhancedComponents.swift | 370 | `.linear(duration: 2.0).repeatForever(autoreverses: false)` — loading spinner phase | Acceptable for a spinner rotation loop (spring doesn't repeat); document exemption |
| BereanEnhancedComponents.swift | 176 | `.easeInOut(duration: 0.2)` — cursor blink | Replace with `BereanAnimationCoordinator.microFade` (or `.linear(duration:)` — cursor blink is conventional) |
| BereanFollowUpChips.swift | 211 | `.linear(duration: 0.90).repeatForever(autoreverses: false)` — thinking ring spinner | Acceptable for spinner loop; document exemption |
| BereanFollowUpChips.swift | 223 | `.easeInOut(duration: 0.28)` — phrase transition | Replace with `BereanAnimationCoordinator.compactSpring` or `.spring(response: 0.28, dampingFraction: 0.82)` |
| BereanFollowUpChips.swift | 242 | `.easeInOut(duration: 0.32)` — phrase index rotation | Replace with `BereanAnimationCoordinator.compactSpring` |
| BereanComposerBar.swift | 458 | `.easeOut(duration: 0.18)` — ghost draft dismiss | Replace with `BereanAnimationCoordinator.microFade` / `.spring(response: 0.22, dampingFraction: 0.88)` |
| BereanComposerBar.swift | 850 | `.easeInOut(duration: 1.8).repeatForever()` — voice orb breathe | Acceptable repeating loop; document exemption |
| BereanComposerBar.swift | 854 | `.easeOut(duration: 0.24)` — voice orb deactivate | Replace with `.spring(response: 0.28, dampingFraction: 0.88)` |
| BereanGlassComposer.swift | 152 | `.amenEaseQuick` — fill opacity change | Inspect `Animation.amenEaseQuick`; if it resolves to an ease curve, replace with `BereanAnimationCoordinator.compactSpring` |

---

## Typography Violations

All violations below are raw `.font(.system(size:weight:))` calls that bypass `AMENFont.*` / `BereanType.*` tokens.

| File | Line | Current | Recommended |
|------|------|---------|-------------|
| BereanDesignSystem.swift | 341 | `.font(.system(size: fontSize, weight: .semibold))` in `BereanBrandBadge` | `.font(AMENFont.semiBold(fontSize))` |
| BereanEnhancedComponents.swift | 49 | `.font(.system(size: 13, weight: .medium))` — SuggestionPill | `BereanType.caption()` |
| BereanEnhancedComponents.swift | 128–129 | `.font(.system(size: 11, weight: .medium))` × 2 — ResponseActionChip | `BereanType.micro()` |
| BereanEnhancedComponents.swift | 157, 161 | `.font(.system(size: 15))` / `.font(.system(size: 15, weight: .light))` — BereanStreamingText | `BereanType.subheadline()` |
| BereanEnhancedComponents.swift | 239 | `.font(.system(size: 16, weight: .medium))` — ToolbarButton | `BereanType.body()` or `AMENFont.medium(16)` |
| BereanEnhancedComponents.swift | 292, 295 | `.font(.system(size: 12, weight: .medium))` / `.font(.system(size: 13, weight: .semibold/.regular))` — BereanModeButton | `BereanType.micro()` / `BereanType.caption()` |
| BereanEnhancedComponents.swift | 334 | `.font(.system(size: 16, weight: .medium))` — BereanLiquidLoadingState sparkles icon | `AMENFont.medium(16)` |
| BereanEnhancedComponents.swift | 341, 344 | `.font(.system(size: 14, weight: .medium))` / (font on dots) — loading text | `BereanType.subheadline()` |
| BereanEnhancedComponents.swift | 394–396 | `.font(.system(size: 14, weight: .medium))` / `.font(.system(size: 13, weight: .semibold))` — BereanScriptureReferenceCard | `BereanType.subheadline()` / `BereanType.caption()` |
| BereanEnhancedComponents.swift | 407 | `.font(.system(size: 14))` — verse text | `BereanType.subheadline()` |
| BereanEnhancedComponents.swift | 448, 458, 462 | `.font(.system(size: 18, weight: .medium))` / `.font(.system(size: 11, weight: .semibold))` / `.font(.system(size: 15, weight: .medium))` — BereanDailyTrainingPromptCard | `AMENFont.medium(18)` / `BereanType.micro()` / `BereanType.subheadline()` |
| BereanEnhancedComponents.swift | 469 | `.font(.system(size: 24))` — checkmark button | `AMENFont.regular(24)` |
| BereanEnhancedComponents.swift | 519, 524, 528 | `.font(.system(size: 14, weight: .medium))` × 3 — BereanLongPressContextMenu | `BereanType.subheadline()` / `BereanType.body()` |
| BereanComposerBar.swift | 290 | `.font(.system(size: 17, weight: .semibold))` — utility + button | `AMENFont.semiBold(17)` |
| BereanComposerBar.swift | 338 | `.font(.system(size: 14, weight: .semibold))` — mode slider icon | `AMENFont.semiBold(14)` |
| BereanComposerBar.swift | 372 | `.font(.system(size: 16, weight: .medium))` — mic icon | `AMENFont.medium(16)` |
| BereanComposerBar.swift | 410 | `.font(.system(size: 14, weight: .bold))` — send arrow | `AMENFont.bold(14)` |
| BereanComposerBar.swift | 432 | `.font(.system(size: 12, weight: .semibold))` — stop icon | `AMENFont.semiBold(12)` |
| BereanComposerBar.swift | 463 | `.font(.system(size: 17, weight: .medium))` — xmark.circle in voice panel | `AMENFont.medium(17)` |
| BereanComposerBar.swift | 496 | `.font(.system(size: 12, weight: .semibold))` — status pill icon | `AMENFont.semiBold(12)` |
| BereanComposerBar.swift | 521 | `.font(.system(size: 12, weight: .semibold))` — ghost draft icon | `AMENFont.semiBold(12)` |
| BereanComposerBar.swift | 669 | `.font(.system(size: 15, weight: .semibold))` — tool sheet icon | `AMENFont.semiBold(15)` |
| BereanComposerBar.swift | 750 | `.font(.system(size: 16, weight: .semibold))` — mode picker icon | `AMENFont.semiBold(16)` |
| BereanComposerBar.swift | 762 | `.font(.system(size: 13, weight: .semibold))` — checkmark | `AMENFont.semiBold(13)` |

> Note: `BereanGlassComposer.swift` uses `.font(.systemScaled(16))` which resolves via a custom extension — this is likely acceptable if `systemScaled` wraps `AMENFont`. Verify the `systemScaled` extension source maps to a dynamic-type-aware font.

---

## Magic Number Padding/Spacing

The following are raw numeric literals in padding/spacing contexts. Numbers from `BereanLayoutMetrics` or `AmenSpacing` are exempt. The ones flagged below are unexplained inline literals:

| File | Line | Value | Context |
|------|------|-------|---------|
| BereanDesignSystem.swift | 234 | `52` | `Spacer(minLength: 52)` — bubble alignment spacer |
| BereanDesignSystem.swift | 214 | `52` | Same spacer in user-side |
| BereanDesignSystem.swift | 235 | `14`, `10` | `.padding(.horizontal, 14)` / `.padding(.vertical, 10)` — bubble padding |
| BereanDesignSystem.swift | 268, 283 | `16`, `14` | `.padding(.horizontal, 16)` / `.padding(.vertical, 14)` — thinking indicator |
| BereanEnhancedComponents.swift | 32 | `20` | `.padding(.horizontal, 20)` — suggestion pills row |
| BereanEnhancedComponents.swift | 54 | `14`, `8` | `.padding(.horizontal, 14)` / `.padding(.vertical, 8)` — SuggestionPill |
| BereanEnhancedComponents.swift | 204, 205 | `20`, `12` | `.padding(.horizontal, 20)` / `.padding(.vertical, 12)` — BereanContextToolbar |
| BereanEnhancedComponents.swift | 299, 300 | `14`, `8` | mode button padding |
| BereanEnhancedComponents.swift | 355, 356 | `16`, `14` | loading state padding |
| BereanEnhancedComponents.swift | 413 | `14` | BereanScriptureReferenceCard padding |
| BereanEnhancedComponents.swift | 441–442 | `44` | icon circle frame (acceptable — WCAG tap target constant; should still be a named constant) |
| BereanEnhancedComponents.swift | 474 | `16` | BereanDailyTrainingPromptCard padding |
| BereanEnhancedComponents.swift | 528, 529 | `16`, `12` | context menu row padding |
| BereanStructuredCardView.swift | 125, 126 | `16`, `14` | header H/V padding |
| BereanStructuredCardView.swift | 145, 146 | `16`, `16` | content body H/bottom padding |
| BereanStructuredCardView.swift | 34 | `9` | rounded corner badge radius |
| BereanFollowUpChips.swift | 140, 141 | `13`, `8` | chip H/V padding |
| BereanFollowUpChips.swift | 116, 117 | `16`, `4` | scroll content H/V padding |
| BereanSmartPillSystem.swift | 348, 349 | `11`, `7` | smart pill H/V padding |
| BereanComposerBar.swift | 70–72 | `30`, `8`, `620` | cornerRadius / innerSpacing / shellWidth — at least `30` and `8` should be named |
| BereanComposerBar.swift | 113 | `56` | `.frame(minHeight: 56)` — input bar shell height |
| BereanComposerBar.swift | 448, 449 | `28` | voice panel pulse size |
| BereanComposerBar.swift | 487 | `0.82` | voice panel width multiplier |

**High-priority magic numbers** (most likely to cause inconsistency):
- Bubble spacers (`52`) — should be `BereanLayoutMetrics.bubbleMinSpacerWidth` or similar
- Chip H/V paddings scattered across 5 files with near-identical values (13–14 H, 7–8 V) — a single `BereanLayoutMetrics.chipPaddingH/V` would unify them
- Corner radii: `14`, `16`, `18`, `24`, `30` appear across multiple files with no shared constant

---

## Spring Constant Catalog

All spring configurations found across the audited files:

| Config | Response | Damping | File / Context |
|--------|----------|---------|----------------|
| A | 0.28 | 0.88 | BereanComposerBar — focus ring & text changes |
| B | 0.28 | 0.75 | BereanStructuredCard — press scale |
| C | 0.28 | 0.82 | BereanAnimationCoordinator.compactSpring |
| D | 0.28 | 0.78 | BereanFollowUpChips — copy feedback |
| E | 0.30 | 0.70 | BereanEnhancedComponents — response card actions toggle |
| F | 0.30 | 0.72 | BereanEnhancedComponents — toolbar scrolling/focus hide |
| G | 0.30 | 0.72 | BereanGlassComposer — focus lift |
| H | 0.30 | 0.80 | BereanComposerBar — voice panel dismiss |
| I | 0.32 | 0.90 | BereanAnimationCoordinator.inputBarSpring |
| J | 0.34 | 0.86 | BereanAnimationCoordinator.softSpring |
| K | 0.35 | 0.68 | BereanEnhancedComponents — mode selector morphing |
| L | 0.35 | 0.70 | BereanEnhancedComponents — long-press context menu appear |
| M | 0.38 | 0.72 | BereanFollowUpChips — chip row stagger |
| N | 0.40 | 0.64 | BereanGlassComposer — chip stagger entrance |
| O | 0.40 | 0.68 | BereanEnhancedComponents — suggestion pills entrance |
| P | 0.40 | 0.72 | BereanDesignSystem — message bubble entrance |
| Q | 0.42 | 0.84 | BereanAnimationCoordinator.studySurfaceSpring |
| R | 0.50 | 0.68 | BereanEnhancedComponents — scripture card appear |
| S | 0.30 | 0.70 | BereanStructuredCard — save button feedback |

**Inconsistency observations:**

1. **Damping at response=0.28 varies from 0.75 to 0.88** — configs A, B, C, D all share `response: 0.28` but damping spans 13 points. This makes micro-interactions feel inconsistent. Recommend consolidating to `BereanAnimationCoordinator.compactSpring` (0.28/0.82) for all small UI changes.

2. **response=0.30 with varying damping (0.70–0.80)** — configs E, F, G, H are effectively the same interaction speed but with 4 different damping values. `BereanAnimationCoordinator.softSpring` (0.34/0.86) should be the canonical "standard UI" spring; the 0.30-family should be merged into it.

3. **Two near-identical chip stagger springs** — config M (0.38/0.72, BereanFollowUpChips) and config P (0.40/0.72, BereanDesignSystem) differ by only 0.02 in response. Both should use the same constant.

4. **BereanAnimationCoordinator defines 4 named springs** (softSpring, compactSpring, inputBarSpring, studySurfaceSpring) but files define 15+ ad-hoc inline springs — the catalog exists but is not being used consistently.

---

## Glass-on-Glass Violations

Glass-on-glass layering (`.fill(.ultraThinMaterial)` nested under another material) appears in:

| File | Location | Pattern | Verdict |
|------|----------|---------|---------|
| BereanDesignSystem.swift | `BereanThinkingIndicator.thinkingBackground` (line 303–305) | `Color.white.opacity(0.88)` + `.background(.ultraThinMaterial)` | **Violation** — `.fill(Color.white.opacity(...))` clipped over `.fill(.ultraThinMaterial)` is redundant layering. The material should be the sole background; the white tint should be an `.overlay`. |
| BereanEnhancedComponents.swift | `SuggestionPill` (line 56–57) | `Color.white.opacity(0.82)` fill + `.background(Capsule().fill(.ultraThinMaterial))` | **Violation** — same pattern. Material should be the base; white tint as overlay. |
| BereanEnhancedComponents.swift | `BereanContextToolbar` (line 207–209) | `Color.white.opacity(0.88)` fill + `.background(Capsule().fill(.ultraThinMaterial))` | **Violation** |
| BereanEnhancedComponents.swift | `BereanLiquidLoadingState` (line 328–330) | `Color.white.opacity(0.88)` + `.background(…fill(.ultraThinMaterial))` | **Violation** |
| BereanEnhancedComponents.swift | `BereanDailyTrainingPromptCard` (line 478–480) | `Color.white.opacity(0.88)` + `.background(…fill(.ultraThinMaterial))` | **Violation** |
| BereanEnhancedComponents.swift | `BereanLongPressContextMenu` (line 554–557) | `Color.white.opacity(0.95)` + `.background(…fill(.ultraThinMaterial))` | **Violation** |
| BereanGlassComposer.swift | `composerBody` background (line 133–139) | `Color.white.opacity(fillOpacity)` fill + inner `.background(.ultraThinMaterial)` | **Violation** — the `BereanGlassComposer` replicates the LiquidGlassCard pattern but does it manually in the wrong nesting order |
| BereanDesignSystem.swift | `BereanBrandBadge` (line 328–335) | `.fill(.ultraThinMaterial)` + `.fill(Color.white.opacity(0.74))` overlay | **Acceptable** — this is the correct pattern (material base, white tint as overlay via `.fill` on a second shape) |
| BereanDesignSystem.swift | `LiquidGlassCard` (line 79–84) | `ZStack { .fill(.ultraThinMaterial); .fill(AmenTheme.Colors.glassFill) }` | **Acceptable** — ZStack pattern, not nested `.background()` |

**Root cause:** The correct AMEN pattern is:
```
.fill(.ultraThinMaterial)          ← base layer
.overlay(shape.fill(glassFill))    ← color tint on top
```
Several files use the reverse — a solid fill with a material as its background — which can cause the material to show through at edges or clip incorrectly.

---

## What's Working Well

1. **BereanDesignSystem.swift** — The token file itself is excellent. `BereanColor` correctly maps to `AmenTheme.Colors`, `BereanType` wraps `AMENFont`, and the `LiquidGlassCard` / `LiquidGlassInputBarModifier` modifiers implement the correct material-first layering order.

2. **BereanLayoutMetrics.swift** — A model implementation of named constants. Size-class-aware computed properties, safe area inset handling, and scroll thresholds are all properly named. Zero magic numbers in this file.

3. **BereanAnimationCoordinator.swift** — The named spring catalog (`softSpring`, `compactSpring`, `inputBarSpring`, `studySurfaceSpring`) is the right approach; the problem is that call sites don't use it consistently.

4. **BereanComposerBar.swift** — The main composer shell correctly uses `LiquidGlassCapsuleBackground`, `BereanColor.*` tokens, `AMENFont.*` typography, and named spring values for its two primary animations (focus ring, streaming state). The feature logic (ghost drafts, tone nudge, scripture paste detect) is well-separated from styling.

5. **BereanFollowUpChips.swift / BereanSmartPillSystem.swift** — Chip row animations correctly gate on `accessibilityReduceMotion` and use `BereanAnimationCoordinator`-range spring values. Pill sizing is consistent chip-to-chip.

6. **Accessibility** — `accessibilityLabel`, `accessibilityHint`, `accessibilityReduceMotion`, and `accessibilityReduceTransparency` guards appear consistently throughout all audited files. This is the strongest area of the codebase relative to industry baseline.

7. **`BereanAnimationCoordinator.adaptive(_:reduceMotion:)`** — The reduce-motion fallback pattern is correctly delegated to a central helper and used by multiple call sites, not duplicated inline.

---

## Priority Fix Queue (for Agent C / rebuild PRs)

| Priority | Issue | Files |
|----------|-------|-------|
| P0 | All 7 `BereanCardType.accentColor` RGB values — replace with named tokens | BereanStructuredCardView.swift |
| P0 | `BereanChatCleanBackground` raw RGB gradient — use `BereanColor.background` | BereanChatView.swift lines 15–20 |
| P0 | All `.font(.system(size:weight:))` in BereanEnhancedComponents.swift — ~15 instances | BereanEnhancedComponents.swift |
| P1 | Glass-on-glass layering in 6 components (material as `.background` of solid fill) | BereanEnhancedComponents.swift, BereanGlassComposer.swift |
| P1 | `.easeInOut`/`.easeOut` animations not in reduce-motion paths | BereanFollowUpChips.swift, BereanComposerBar.swift voice orb |
| P1 | `Color(hex: "DC3232")` stop button in BereanGlassComposer | BereanGlassComposer.swift |
| P1 | `Color(red: 0.85, green: 0.25, blue: 0.30)` safety pill — needs `Color.amenDanger` token | BereanSmartPillSystem.swift |
| P2 | Consolidate ad-hoc inline spring configs to named `BereanAnimationCoordinator` constants | All files |
| P2 | Chip H/V padding values (13–14/7–8) — add `BereanLayoutMetrics.chipPaddingH/V` | BereanFollowUpChips.swift, BereanSmartPillSystem.swift |
| P2 | Bubble min-spacer (`52`) — add named constant | BereanDesignSystem.swift |
| P3 | `.font(.system(size:weight:))` in BereanComposerBar.swift — ~10 instances in button icons | BereanComposerBar.swift |
| P3 | Verify `Animation.amenEaseQuick` resolves to a spring, not an ease curve | BereanGlassComposer.swift |
