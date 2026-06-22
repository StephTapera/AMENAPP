# AMEN / Berean - Module 13: Liquid Glass Motion & iOS 27 Animation System

## Multi-Agent Build Orchestration Spec - Contracts-First, Wave-Based, iOS 27-Native, End-to-End

Companion to `AMEN_Settings_Safety_MultiAgent_Build.md`. That spec defines the settings surfaces and their components; this spec defines the motion and Liquid Glass primitives those components sit on, and applies them app-wide across Bible study, prayer journal, creator dashboard, moderation queue, and related surfaces. Same operating model: frozen Wave 0, parallel lanes with strict file ownership, feature flags default off, build-broker protocol, three-strikes stop rule, no false completion, human-only destructive git.

What changed since the original brief: the brief targeted "iOS 27 animation" generically. iOS 27 shipped at WWDC 2026 and materially reshapes this work. This spec builds on the new surface: the system-level Liquid Glass intensity slider, `.glassEffectID` morphing, new toolbar, scroll, confirmation, reorder, and swipe APIs. Where an exact signature differs from the GA SDK, the named API and intent govern; agents resolve the canonical form against Xcode 27 and Apple's exported agent skills.

Local documentation check: Xcode SwiftUI documentation confirms the core Liquid Glass APIs named here, including `glassEffect(_:in:)`, `GlassEffectContainer`, `glassEffectID(_:in:)`, `glassEffectTransition(_:)`, and `swipeActionsContainer()`.

## 0. How To Use This Document

1. Read section 3, Motion invariants, and section 6, Wave 0 contracts, before writing code. These are frozen. No lane edits them.
2. Motion is almost entirely client-side SwiftUI. The demo gate is an Xcode 27 Live Preview gallery, not an HTML demo. HTML cannot render Metal lensing, so a Preview showing every state across Reduce Motion, transparency spectrum, and accent tokens is the correct review artifact.
3. Every motion behavior has an accessibility fallback baked in at the primitive level, not bolted on per screen. A primitive that animates without a Reduce Motion path fails its definition of done.
4. Each lane owns its files and consumes Wave 0 plus lower lanes. Lane M-D composes primitives; it never re-implements them.
5. Use the kickoff prompts in section 15 one lane at a time.

## 1. iOS 27 Ground Truth

- Liquid Glass is system-sliderable. iOS 27 adds a graduated, system-wide Liquid Glass intensity and opacity control from ultraclear to fully tinted. Apps using system glass APIs honor it automatically; custom glass must read and respect the user's system preference.
- Glass adoption is mandatory on the latest SDK. Xcode 27 disables legacy deferral flags.
- Improved background diffusion addresses iOS 26 contrast and legibility failures, but custom implementations still need a contrast audit.
- `.glassEffect()` and `GlassEffectContainer` remain core. `.glassEffectID` drives morphing transitions between glass shapes and is the glass-native source-to-sheet morph primitive.
- New toolbar APIs include `.visibilityPriority(.high)`, `ToolbarOverflowMenu`, `.topBarPinnedTrailing`, and `.toolbarMinimizeBehavior(.onScrollDown, for: .navigationBar)`.
- `.confirmationDialog(_, item:)` and `.alert(_, item:)` item binding replace the Bool plus selected-item dance.
- Swipe actions on any view in a scroll container use `.swipeActions` plus `.swipeActionsContainer()`.
- Reorderable containers use `.reorderable()` and `.reorderContainer(for:)` across `List` and `LazyVGrid`.
- `Tab(role: .prominent)` supports a standout tab in `LiquidGlassTabBar`.
- `@State` is now a macro with lazy init. Do not assign a default in the declaration and reassign in `init`.
- `ContentBuilder` should be used when deeply nested glass hierarchies make compile times unreasonable.
- Resizable iPhone apps and hinge-state layout APIs mean motion cannot assume fixed window sizes.

## 2. Motion Principles

- Every sheet, card, menu, popover, and dialog is spatially connected to the element that opened it.
- Depth comes from blur, translucency, scale, and spring physics, never a flat slide.
- Motion serves clarity, never decoration. No idle loops, no engagement shimmer.
- Accessibility is a first-class path, not a degraded one.

## 3. Motion Invariants - Frozen

- MA1: Reduce-Motion fallback at the primitive level. Every spring, scale, or positional animation has a crossfade or opacity alternate when `accessibilityReduceMotion` is true.
- MA2: Transparency spectrum. Honor the iOS 27 system Liquid Glass intensity preference and `accessibilityReduceTransparency`. Reduced or off means solid adaptive token-backed surfaces, not slightly less blur.
- MA3: WCAG AA on glass. Text and controls over glass meet AA contrast in light, dark, and every accent token. Never place light text over uncontrolled blurred media.
- MA4: Interruptible and non-blocking. Motion never blocks navigation, dismissal, or input.
- MA5: Spatial honesty. Open is the inverse of close. Sheets, popovers, and menus morph from their source and return into it.
- MA6: Motion budget. No looping or idle animation that does not convey state.
- MA7: Haptic restraint. `.sensoryFeedback` fires only on meaningful state changes and honors both the system setting and the app Haptic Feedback toggle.
- MA8: Performance. Group related glass in `GlassEffectContainer`, allow static backgrounds to cache, avoid per-frame GPU recompute, and virtualize glass-heavy lists.

## 4. Agent Operating Protocol

- Seed every lane with Apple's official SwiftUI agent skills exported to `docs/agent-skills/`.
- Demo gate is a Live Preview gallery covering all states, Reduce Motion on/off, transparency spectrum, at least three accent tokens including `amenWineRed` and `amenTan`, and light/dark.
- Build broker applies. Code-complete lanes write `BUILD_REQUEST.md` with changed files and Preview verification, then stop for the human build.
- No false completion, three-strikes stop, contracts frozen, file ownership is law, destructive git is human-only.
- No backend in this module unless motion needs an existing value. No new Cloud Functions.

## 5. Wave Plan

| Wave | Name | Who | Gate |
|---|---|---|---|
| 0 | Motion contracts and tokens | M0 coordinator plus human ratify | Contracts frozen; adaptive layer and token set compile |
| 1 | Glass primitives and materials | M-A | Primitives green in Preview gallery; MA1-MA3 asserted |
| 2 | Containers and chrome | M-B | Sheet, popover, nav, and tab morphs green; MA5 proven |
| 3 | Controls | M-C | Toggle, picker, segmented, confirmation green; haptics gated |
| 4 | Per-surface choreography | M-D | Every required animation wired on its screen |
| 5 | Accessibility and final audit | M-E plus all | Section 13 audit clean; acceptance matrix 100% |

M-A to M-B to M-C are a dependency chain. M-D depends on all three. M-E runs the cross-cutting audit last but supplies the adaptive test harness from Wave 1.

## 6. Wave 0 - Motion Contracts And Tokens

### 6.1 Motion Token Set

`DesignSystem/LiquidGlass/Tokens/MotionTokens.swift`

- `spring.standard = .spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)`
- `spring.snappy = .spring(response: 0.30, dampingFraction: 0.88)`
- `spring.gentle = .spring(response: 0.55, dampingFraction: 0.90)`
- `spring.destructive = .spring(response: 0.62, dampingFraction: 0.92)`
- `scale.cardEntry = 0.96 -> 1.0`
- `opacity.scrim = 0.0 -> 0.32`
- `duration.crossfade = 0.22`

Call sites use tokens, never raw numbers.

### 6.2 Adaptive Motion Layer

`DesignSystem/LiquidGlass/Environment/MotionEnvironment.swift`

```swift
@Observable final class MotionEnvironment {
    var reduceMotion: Bool
    var glassIntensity: Double
    var transparencyReduced: Bool
    var hapticsEnabled: Bool
}
```

`glassIntensity` is composed, not app-only: `effective = min(systemLiquidGlassPreference, appIntensitySlider)`. The app may reduce, never amplify beyond the user's system choice.

Required helpers:

- `animation(_ token:) -> Animation?` returns the spring token, or crossfade when `reduceMotion` is enabled.
- `surface(for:)` returns glass material or solid token-backed fill when `transparencyReduced` is true.
- `@State` stored instances follow the iOS 27 lazy-init rule: declare without default, assign in `init`.

### 6.3 Glass Morph Namespace Registry

`DesignSystem/LiquidGlass/Environment/GlassNamespaces.swift`

Stable IDs for `glassEffectID` and `matchedGeometryEffect`. Examples:

- `settingsRow(id)`
- `reportIssueFAB`
- `accentDot(color)`
- `aiPill(mode)`
- `sessionRow(id)`

One registry. Lanes reference it and do not invent inline IDs.

### 6.4 Component API Contracts

Freeze public signatures for these primitives:

- `LiquidGlassBackground`
- `LiquidGlassCard`
- `LiquidGlassSheet`
- `LiquidGlassPopover`
- `LiquidGlassButton`
- `LiquidGlassToggle`
- `LiquidGlassPicker`
- `LiquidGlassSegmentedControl`
- `LiquidGlassNavBar`
- `LiquidGlassTabBar`
- `LiquidGlassConfirmationDialog`
- `LiquidGlassProgressBar`

Each primitive takes `MotionEnvironment` from the environment, exposes accessibility label and hint parameters, and documents Reduce Motion plus reduced-transparency behavior.

### 6.5 Haptic Catalog

`DesignSystem/LiquidGlass/Environment/Haptics.swift`

Semantic mappings:

- `toggleCommit -> .selection`
- `destructiveConfirm -> .warning`
- `lockdownArm -> .warning`
- `flowComplete -> .success`
- `removeItem -> .impact(.rigid)`

All haptics route through `MotionEnvironment.hapticsEnabled`.

### 6.6 File Ownership

```text
DesignSystem/LiquidGlass/Tokens/**        -> Wave 0, read-only after freeze
DesignSystem/LiquidGlass/Environment/**   -> Wave 0
DesignSystem/LiquidGlass/Primitives/**    -> Lane M-A
DesignSystem/LiquidGlass/Containers/**    -> Lane M-B
DesignSystem/LiquidGlass/Controls/**      -> Lane M-C
Features/**/Motion/**                     -> Lane M-D
DesignSystem/LiquidGlass/Accessibility/** -> Lane M-E
```

Boundary with the settings spec: settings components consume these primitives. If a name collides, the settings component wraps the module primitive. Single implementation, no duplicate glass logic.

## 7. Lanes

### Lane M0 - Coordinator

Produce only section 6: tokens, `MotionEnvironment` with composed `glassIntensity`, namespace registry, component API contracts, haptic catalog, and ownership map. End with a compiling stub. Respect section 3 and the iOS 27 `@State` lazy-init rule. Finish with `BUILD_REQUEST.md`.

### Lane M-A - Glass Primitives And Materials

Own `Primitives/**`.

Build `LiquidGlassBackground`, `LiquidGlassCard`, `LiquidGlassButton`, `LiquidGlassProgressBar`, the material/intensity engine, and depth layering. Honor MA1, MA2, MA3, and MA8. Ship a Preview gallery covering the full matrix. Finish with `BUILD_REQUEST.md`.

### Lane M-B - Containers And Chrome

Own `Containers/**`.

Build `LiquidGlassSheet`, `LiquidGlassPopover`, `LiquidGlassNavBar`, and `LiquidGlassTabBar`. Sheet open/close uses `glassEffectID` plus `GlassEffectContainer`, and close is the inverse morph. Every sheet has working X, drag, and back dismissal. Finish with `BUILD_REQUEST.md`.

### Lane M-C - Controls

Own `Controls/**`.

Build `LiquidGlassToggle`, `LiquidGlassPicker`, `LiquidGlassSegmentedControl`, and `LiquidGlassConfirmationDialog`. Gate haptics through `MotionEnvironment.hapticsEnabled`. Confirmation uses item-binding dialogs with warning and destructive variants. Finish with `BUILD_REQUEST.md`.

### Lane M-D - Per-Surface Choreography

Own `Features/**/Motion/**`. Compose primitives only.

Wire required animations into each real surface. Use native iOS 27 mechanisms such as swipe-on-any-view for session removal, numeric text content transitions for storage, `phaseAnimator` for Trusted Contact onboarding, and reorderable containers only where approved. Bible study and prayer journal stay quiet with `spring.gentle`.

### Lane M-E - Accessibility And Final Audit

Own `Accessibility/**`.

Build the adaptive snapshot harness and run the section 13 audit. Fix dead animations, broken transitions, missing dismiss behavior, bad blur contrast, excessive motion, and missing accessibility fallbacks. Produce `MOTION_AUDIT.md` and `MOTION_ACCEPTANCE.md`. Finish with `BUILD_REQUEST.md`.

## 8. Required Animations And API Mapping

| # | Animation | Primitive | SwiftUI mechanism |
|---|---|---|---|
| 1 | Settings sheet expands from tapped row | `LiquidGlassSheet` | `glassEffectID` + `GlassEffectContainer`, `spring.standard` |
| 2 | Modal background blurs/dims with progressive depth | `LiquidGlassBackground` | layered `.glassEffect()`, scrim opacity, `.visualEffect` |
| 3 | Cards soft spring entry 0.96 to 1.0 | `LiquidGlassCard` | `.scrollTransition`, scale plus opacity transition |
| 4 | Close shrinks/fades into source | `LiquidGlassSheet` | inverse of #1 |
| 5 | Picker menus as anchored glass popovers | `LiquidGlassPopover` | popover plus `.presentationCompactAdaptation` |
| 6 | Toggle color morph plus haptic | `LiquidGlassToggle` | `.contentTransition`, `.sensoryFeedback(.selection)` |
| 7 | Session/device row collapse and fade | `LiquidGlassCard` | `.swipeActions`, `.swipeActionsContainer()`, collapse transition |
| 8 | Storage bars 0 to actual | `LiquidGlassProgressBar` | animate value on appear, `.contentTransition(.numericText())` |
| 9 | Notification rows crossfade Off/Push/Email/Digest | surface | `.contentTransition` symbol interpolate |
| 10 | Report Issue bottom-expand with blurred backdrop | `LiquidGlassSheet` | bottom detent plus scrim |
| 11 | Screenshot preview slides as glass thumbnail | `LiquidGlassCard` | move from bottom plus opacity transition, `AsyncImage` cache |
| 12 | Trusted Contact step cards | `LiquidGlassCard` | `.phaseAnimator` |
| 13 | Parental family cards stack/expand | `LiquidGlassCard` | stack and expand, `.reorderable()` when approved |
| 14 | AI controls segmented glass pills | `LiquidGlassSegmentedControl` | selected pill `glassEffectID` morph |
| 15 | Accent picker dot selection | surface | `matchedGeometryEffect` ring, `.symbolEffect` |
| 16 | Appearance preview crossfade | surface | `.contentTransition(.interpolate)` |
| 17 | Lockdown stronger confirm | `LiquidGlassConfirmationDialog` | item-binding confirmation dialog, warning glass, warning haptic |
| 18 | Destructive slower confirm | `LiquidGlassConfirmationDialog` | `amenWineRed`, `spring.destructive`, double confirm |

## 9. AMEN / Berean Surfaces

- Settings root
- Account
- Security
- Trusted Contact flow
- Parental Controls
- Notifications
- Storage
- Report Issue
- Berean AI controls
- Bible study mode
- Prayer journal
- Church/group settings
- Profile
- Creator dashboard
- Moderation/admin queue

Faith surfaces use quiet motion. Bible study and prayer journal favor gentle fades and `spring.gentle`; no flourish. Hero screens enforce MA3 scrims so verse and title text stay legible over media.

## 10. Acceptance Matrix

Lane M-E owns `MOTION_ACCEPTANCE.md`. All items are required:

- Every animation in section 8 is present on its real screen, correct, and interruptible.
- Every animation has a reduce-motion crossfade alternate.
- Every glass surface collapses to solid token-backed fill across the transparency spectrum.
- AA contrast passes for every accent token in light and dark.
- Open and close are inverses, and sheets return into source.
- No decorative idle or looping motion.
- Haptics fire only on semantic events and honor both system and app settings.
- No jank on iPhone 13-era target; static glass caches.

## 11. Test Plan

- Preview-snapshot every primitive and surface across reduce-motion, transparency, accent, and light/dark.
- Unit-test `MotionEnvironment` composition so the app never amplifies above the system setting.
- Interaction-test tap-during-animation, swipe-to-remove plus confirmation, and item-binding dialogs.

## 12. Accessibility

Reduce Motion maps to fade or crossfade. Transparency spectrum maps to solid adaptive surfaces. All glass must meet WCAG AA. No light text over uncontrolled blurred media. All motion is interruptible and non-blocking. Haptics honor both system and app Haptic Feedback settings.

## 13. Final Audit

Audit every screen in section 9 for:

- Dead animations
- Broken or mismatched transitions
- Missing dismiss behavior
- Bad blur contrast
- Excessive motion
- Unhandled accessibility fallbacks

Produce `MOTION_AUDIT.md` with per-screen pass/fail and the fix commit for each failure. No screen ships with an open item.

## 14. Human-Gated Decisions

1. Reorder affordance: do guardians reorder family cards and do creators reorder dashboard tiles?
2. Prominent tab: which action, if any, gets `Tab(role: .prominent)`?
3. App intensity versus system slider copy: confirm the Settings to Appearance slider says it reduces within the system setting.
4. Export Apple's agent skills: confirm `xcrun agent skills export` output is committed to `docs/agent-skills/`.

## 15. Kickoff Prompts

All lanes first read `DesignSystem/LiquidGlass/Tokens/**`, `DesignSystem/LiquidGlass/Environment/**`, section 3 invariants, section 4 protocol, and Apple's exported SwiftUI agent skills in `docs/agent-skills/`.

### M0

You are the Wave 0 coordinator for AMEN's Liquid Glass Motion module on iOS 27. Produce only section 6: motion tokens, `MotionEnvironment` with composed `glassIntensity` using `min(systemPreference, appPreference)`, glass namespace registry, the 12 component API contracts, haptic catalog, and ownership map. End with a compiling stub. Respect section 3. Mind the iOS 27 `@State` macro lazy-init rule. Finish with `BUILD_REQUEST.md` and stop for human freeze.

### M-A

Own `Primitives/**`. Build `LiquidGlassBackground`, `LiquidGlassCard`, `LiquidGlassButton`, `LiquidGlassProgressBar`, the material/intensity engine, and depth layering. Read `MotionEnvironment`. Honor MA1, MA2, MA3, and MA8. Ship a Preview gallery covering the full matrix. Finish with `BUILD_REQUEST.md`.

### M-B

Own `Containers/**`. Build `LiquidGlassSheet` with source-to-sheet morph via `glassEffectID` and `GlassEffectContainer`, `LiquidGlassPopover`, `LiquidGlassNavBar`, and `LiquidGlassTabBar`. Every sheet has working X, drag, and back dismissal. Reduce Motion uses a positional-free crossfade. Finish with `BUILD_REQUEST.md`.

### M-C

Own `Controls/**`. Build `LiquidGlassToggle`, `LiquidGlassPicker`, `LiquidGlassSegmentedControl`, and `LiquidGlassConfirmationDialog` on item-binding confirmation dialogs. Gate all haptics through `MotionEnvironment.hapticsEnabled`. Finish with `BUILD_REQUEST.md`.

### M-D

Own `Features/**/Motion/**`. Compose primitives only. Wire every animation in section 8 onto real surfaces in section 9 using iOS 27-native mechanisms. Faith surfaces stay quiet with `spring.gentle` and no flourish. Finish with `BUILD_REQUEST.md`.

### M-E

Own `Accessibility/**`. Build the adaptive snapshot harness and run the section 13 audit on every surface in section 9. Fix dead animations, broken transitions, missing dismiss, bad blur contrast, excessive motion, and unhandled fallbacks. Produce `MOTION_AUDIT.md` and complete `MOTION_ACCEPTANCE.md`. Finish with `BUILD_REQUEST.md`.

End of spec. Section 3 invariants and section 6 contracts are frozen. Propose changes via `CONTRACT_CHANGE_REQUEST.md`; human re-freezes before lanes resume.
