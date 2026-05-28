# Agent 1 — Liquid Glass Animation Audit & Implementation

**Branch:** berean/ui-rebuild-liquid-glass-v1  
**Date:** 2026-05-28  
**Agent:** Animation Implementer

---

## Findings

### Existing Animation State (pre-audit)

The codebase already has a mature animation infrastructure:
- `Motion.swift` — centralized spring presets (`springPress`, `popToggle`, `tabGlide`, `liquidSpring`)
- `LiquidGlassMotion.swift` — `AmenMotion` card/sheet springs + `GlassExpandableCard`, `GlassPressModifier`
- `LiquidGlassEffects.swift` — scroll-responsive glass, success chips, sticky header soften
- `AMENTabBar.swift` — matched geometry pill (`amen_selected_pill`), scroll-hide bridge, `sensoryFeedback`
- `AmenLiquidGlassTabBar.swift` — separate Berean-context tab bar with matched geometry (`amen_liquid_glass_active_tab`)
- `FeaturedHeroCarousel.swift` — Apple TV-style hero with parallax, pull-down stretch, auto-advance

### Key Gaps Found

1. **Spring inconsistency** — Most press/expand/tab animations used `spring(response: 0.3, dampingFraction: 0.86)` or `easeIn/easeOut(0.1)` instead of the canonical `.bouncy(duration: 0.4, extraBounce: 0.1)`.
2. **Press scale inconsistency** — Several button styles used 0.94–0.97; target is unified 0.96.
3. **ComposeButtonStyle** used `.easeOut(duration: 0.15)` — not spring-based at all.
4. **FeedCardViews.swift** used `easeIn(0.1)` / `easeOut(0.1)` for all press gestures.
5. **Page indicator** in `FeaturedHeroCarousel` used `.amenSnappy` — not the canonical bouncy spring.
6. **No scroll-driven material reveal modifier** — existed as `ScrollResponsiveGlassModifier` (opacity/scale only) but not as a standalone `scrollMaterialReveal` for nav bars / docks.
7. **`AmenSheetModifier`** had no `presentationDetents` or `presentationDragIndicator`.
8. **SF Symbol badge-arrival bounce** not wired to badge count changes (only fired on selection).
9. **Specular top-edge highlight** missing from `LiquidGlassActiveTabCapsule` and hero Play button.

---

## Implemented

### 1. `Motion.swift`

- **Added `Motion.liquidSpringAdaptive`** — reduce-motion-aware wrapper around `Motion.liquidSpring`; returns `easeOut(0.18)` when Reduce Motion is active. Used throughout as the single decision point.

### 2. `AMENTabBar.swift` (7 changes)

- **`ComposeButtonStyle`** — upgraded from `easeOut(0.15)` → `Motion.liquidSpring`; scale from 0.95 → 0.96 (Pattern 7)
- **`LiquidGlassTabButtonStyle`** — upgraded from `spring(response:0.20, dampingFraction:0.70)` → `Motion.liquidSpring`; scale from 0.94 → 0.96 (Pattern 7)
- **`handleTap`** — upgraded from `spring(response:0.34, dampingFraction:0.84)` → `Motion.liquidSpring` (Pattern 2)
- **`AMENTabBarScrollBridge.minimize/expand`** — upgraded from `easeOut(0.18)` / `spring(response:0.28)` → `Motion.liquidSpringAdaptive` (Pattern 2)
- **`AMENTabBar.body`** — `.animation(value: isMinimized)` upgraded → `Motion.liquidSpring` (Pattern 2)
- **`iconView(for:isSelected:)`** — added `.symbolEffect(.bounce, value: badgeCount)` so icons bounce when new badge arrives (Pattern 8)
- **`LiquidGlassActiveTabCapsule`** — added specular top-edge highlight (1.5pt white capsule, `blendMode(.plusLighter)`) for iOS 26+ and fallback path (Pattern 10)

### 3. `AmenLiquidGlassTabBar.swift` (3 changes)

- **`selectedTabAnimation`** — upgraded fallback spring to `.bouncy(duration: 0.4, extraBounce: 0.1)` on iOS 17+ (Pattern 2)
- **`body` compress animation** — `spring(response:0.34)` → `Motion.liquidSpring` (Pattern 2)
- **`AmenLiquidGlassTabPressStyle`** — scale 0.94 → 0.96, animation → `Motion.liquidSpring` (Pattern 7)

### 4. `FeedCardViews.swift` (4 changes)

- **`CategoryPill` press gesture** — `easeIn(0.1)` / `easeOut(0.1)` → `Motion.liquidSpring` (Pattern 7)
- **`CommunityCard` press gesture** — same upgrade (Pattern 7)
- **`SmartCommunityCard` long-press** — `.smooth(duration: 0.2)` → `Motion.liquidSpring` (Pattern 7)
- **`TrendingCard` press gesture** — upgraded + added `.presentationDetents([.large])`, `.presentationDragIndicator(.visible)`, `.presentationCornerRadius(24)` to its detail sheet (Pattern 7, 9)

### 5. `ToastNotificationView.swift` (4 changes)

- **`ToastManager.show`** — `Motion.adaptive(spring(0.4, 0.8))` → `Motion.liquidSpringAdaptive` (Pattern 5)
- **`ToastManager.dismiss`** — same upgrade (Pattern 5)
- **`ToastManager.showCopyLinkHUD`** — `spring(0.32, 0.72)` → `Motion.liquidSpringAdaptive` (Pattern 5)
- **`LiquidGlassCopyHUD.onAppear`** — `spring(0.30, 0.70)` → `Motion.liquidSpring` (Pattern 5)

### 6. `AmenLiquidGlassComponents.swift` (3 changes)

- **`AmenLiquidGlassCapsuleSurface`** — scale target 0.97 → 0.96 (Pattern 7)
- **`AmenLiquidGlassPillButton` button body** — added `#available(iOS 17)` branch with `.symbolEffect(.bounce, value: isPressed)` on the icon (Pattern 8)
- **`AmenLiquidGlassPillButton` press animation** — `spring(0.24, 0.84)` → `Motion.liquidSpring` (Pattern 7)

### 7. `LiquidGlassMaterial.swift` (1 change)

- **`AmenSheetModifier`** — added `.presentationDragIndicator(.visible)` and `.presentationDetents([.medium, .large])` so all `amenSheet()` callers get sheet detents and a drag handle (Pattern 9). Affects: ProfileView (10 sheet types), BereanPulseView (5 sheets), and every other call site of `.amenSheet()`.

### 8. `LiquidGlassMotion.swift` (1 change)

- **`AmenMotion.cardSpring` and `.sheetSpring`** — converted from static `let` constants to computed `var` returning `.bouncy(duration: 0.4, extraBounce: 0.1)` on iOS 17+, fallback `spring(0.4, 0.72)` for older OS (Pattern 2). Affects `GlassExpandableCard`, `GlassSheetContainer`, `BackgroundRefocusModifier`.

### 9. `LiquidGlassEffects.swift` (1 addition)

- **Added `ScrollMaterialRevealModifier` + `scrollMaterialReveal()` extension** — applies `ultraThinMaterial` that fades in as scroll offset increases downward. `revealRange` defaults to 60pt. Reduces motion-safe (returns full opacity when `accessibilityReduceTransparency` is ON). (Pattern 1)
- Applied to `BereanPulseView.topBar` via `.scrollMaterialReveal(scrollOffset: scrollOffset, revealRange: 48)`.

### 10. `BereanPulseView.swift` (2 changes)

- **Dock animation** — `spring(0.3, 0.82)` → `Motion.liquidSpring` (Pattern 2)
- **`topBar`** — added `.scrollMaterialReveal(scrollOffset: scrollOffset, revealRange: 48)` (Pattern 1)

### 11. `BereanPulseCardView.swift` (1 change)

- **Card expand animation** — `spring(0.3, 0.86)` → `Motion.liquidSpring` (Pattern 2)

### 12. `ProfileView.swift` (3 changes)

- **Compact header show/hide** — `easeOut(0.15)` → `Motion.liquidSpringAdaptive` (Pattern 1)
- **Profile header pull-down stretch** — added `.scaleEffect(1.0 + scrollOffset * 0.0012, anchor: .top)` when `scrollOffset > 0`, with `.animation(.none)` during stretch and `Motion.liquidSpring` on snap-back (Pattern 4)
- **`stickyTabBar` switch** — `Motion.adaptive(spring(0.32, 0.78))` → `Motion.liquidSpringAdaptive` (Pattern 2)

### 13. `FeaturedHeroCarousel.swift` (4 changes)

- **`pageDots`** — upgraded from `.amenSnappy` → `.spring(.bouncy(duration:0.4, extraBounce:0.1))`, active dot width 22 → 26pt for more visible stretch, added specular 1.5pt top-edge highlight on active dot (Patterns 6, 10)
- **Auto-advance `onReceive`** — `.amenSnappy` → bouncy spring (Pattern 2)
- **Play button** — specular top-edge highlight layer added to white capsule background (Pattern 10)
- **Play + Add buttons** — added `.amenPress()` button style for 0.96 scale + haptic (Pattern 7)

---

## Deferred

| Item | Effort | Why |
|------|--------|-----|
| Pattern 3: Matched geometry hero morph (Feed → PostDetail) | XL | Requires `@Namespace` plumbing through PostCard → FeedView → NavigationStack. The source and destination views are in different files with different lifecycles. High regression risk. |
| Pattern 4: Stretchy parallax on Berean threads header | M | `BereanCommunicationHubView` needs a scroll coordinate space + parallax offset wired through multiple layers. Safe but multi-file. |
| Pattern 4: Stretchy parallax on ARISE detail | M | ARISE detail not found in current codebase — may be in a worktree or planned view. |
| Pattern 1: Scroll material reveal on main nav bars (NavigationStack `.toolbar`) | M | SwiftUI NavigationStack toolbar backgrounds can't be easily overridden per-view with a custom modifier without UINavigationBar appearance hacks. Deferred to avoid UIKit bridging complexity. |
| Pattern 6: Stretching indicator in Berean onboarding flow | S | `BereanOnboardingView` uses a page-style stepper but no `TabView`. A custom page indicator would need to be added alongside it — 1 file, low risk, but out of scope for this pass. |
| Pattern 6: Stretching indicator in `AMENOnboardingSystem` | S | Same as above — onboarding uses step-counter UI not a dots indicator. |
| Pattern 5: Liquid pill morph on AMEN action button (compose orb) | S | `composeOrb` in `AMENTabBar` already has scale press. A color-fill morph on active state would need an `isCreating` state signal piped in from the parent. |
| Pattern 5: Notification toast pill entrance from off-screen | S | Currently uses `.move(edge: .top).combined(with: .opacity)` transition. Upgrading to a scale+spring entrance in `MessagingToastModifier` is low risk but was not touched to preserve the existing tested behavior. |

---

## Risk Notes

1. **`AmenSheetModifier` detents change** is the broadest single change — every call site of `.amenSheet()` will now show a `.medium` detent first. If any view's content is designed to fill the full screen immediately (e.g., `FullScreenAvatarView`, `LoginHistoryView`), callers should override with `.presentationDetents([.large])` directly on those sheets. No crash risk — just a UX choice.

2. **`ProfileView` pull-down stretch** uses `scrollOffset > 0` guard to fire only during overscroll. If `scrollOffset` has sign conventions different from expected (positive = at-top, negative = scrolled-down) the stretch will fire in the wrong direction. The guard should be verified against `ScrollOffsetPreferenceKey.self` actual values. If backwards, change `scrollOffset > 0` to `scrollOffset < 0`.

3. **`Motion.liquidSpring`** is defined as a computed `var` with an `#available(iOS 17, *)` check. All call sites are module-internal and don't need availability annotations. The `Motion.liquidSpringAdaptive` wrapper adds the `UIAccessibility.isReduceMotionEnabled` check synchronously on the main thread — safe since it's always called from `@MainActor` contexts.

4. **`@available(iOS 26, *)` guard in `GlassExpandableCard`** — `AmenMotion.cardSpring` is now a computed var but `GlassExpandableCard` itself is `@available(iOS 26, *)`. The computed spring uses `#available(iOS 17, *)` internally which is always satisfied inside iOS 26 context. No issue.

5. **`FeaturedHeroCarousel` Play button** — `.amenPress()` calls `buttonStyle(AmenPressStyle(...))` but the outer `HStack` already has `.buttonStyle(.plain)`. Adding `.amenPress()` on individual buttons should override correctly since inner button styles win over outer ones in SwiftUI. Low risk.

6. **`scrollMaterialReveal` in `BereanPulseView.topBar`** applies a second background modifier after `.liquidGlassPanel(...)`. The order matters — the scroll material will sit behind the glass panel, which is the desired layering. Verify visually that the material doesn't double-frost the top bar.
