# §2.4 — Accessibility-Fallback Contract

Accessibility is first-class. Every auth/onboarding screen satisfies all of the following;
the canonical `GlassButton` and a shared glass card are the single fix points so screens
cannot hand-roll material that bypasses these.

## Reduce Transparency
`@Environment(\.accessibilityReduceTransparency)` → glass collapses to an **opaque** material
(`Color(.systemBackground)` / solid tint). No bespoke `.ultraThinMaterial` / `.regularMaterial`
without this branch (fixes E-01, E-02, E-07, E-08, G-09). The correct pattern already exists in
`AmenPhoneAuthView` — promote it into the shared primitive.

## Reduce Motion
`@Environment(\.accessibilityReduceMotion)` (or `Motion.adaptive`) → no glass morph / spring /
`repeatForever` animations; use cross-fades or static. Covers entrance springs and the looping
border/glow on onboarding slides (fixes E-05, E-06, G-09).

## Increase Contrast
`@Environment(\.colorSchemeContrast)`: when `.increased`, labels on glass meet **WCAG AA** —
including pressed/disabled. No `Color(white: 0.48)` label on a translucent pill; fade via control
opacity, not by sinking the label into the sub-AA gray zone (fixes E-04). "or" dividers darkened or
`.accessibilityHidden(true)` (E-11).

## Color scheme (§7.4 — full semantic dark support)
Replace literal `Color.black` / `Color.white` / `Color(white: 0.xx)` with semantic
`Color.primary` / `.secondary` / `Color(.systemBackground)` / `Color(.label)` across all 5
auth/onboarding implementations so the surface adapts to dark mode (fixes G-01). Tinted-glass
labels are verified against the tint, not defaulted to black.

## Dynamic Type
Layout to **AX5** with no clipping. `minHeight` not fixed height on text-bearing pills/fields
(fixes E-10, G-08). Fonts via UIFontMetrics/`.systemScaled`.

## VoiceOver
Labels, traits, and order on **every** control including:
- OTP field → `.accessibilityLabel("Verification code")` + hint; phone field labeled (fixes E-03, E-07).
- Mode tabs grouped as a segmented control; selected state announced (E-09).
- Interest chips / faith rows → `.accessibilityAddTraits(.isSelected)`; ≥44pt targets (E-12).
- Account switcher rows labeled.
- Post a `UIAccessibility.announcement` on under-age rejection and on OTP-field appearance (E-07, E-08).

## Targets
Minimum **44×44pt** on every interactive control (chips, Follow buttons included — E-12).
