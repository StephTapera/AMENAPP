# §2.1 — GlassButton Contract

**Canonical primitive:** `AmenGlassButtonStyle` (`AMENAPP/AmenGlassButtonSystem.swift`), surfaced as
`.amenGlass(role:size:)`. Every non-Apple interactive control in onboarding/auth uses it.
Delete the duplicated `authLiquidGlassPill` (×2), `AuthPillButtonStyle`, `ScaleButtonStyle`,
`SubtlePressButtonStyle`, `PressableButtonStyle`, `ONBPrimaryButton`, `OnboardingNextButton`
once migrated.

## Shape
Capsule (`Capsule(style: .continuous)`). One radius law app-wide. No `RoundedRectangle(12/14/16/24/26/50)`
on any auth/onboarding control.

## Variants & color law
| Role | Fill | Label | Use |
|------|------|-------|-----|
| `.primary` | brand-accent **tinted glass** | light, AA-verified on tint | Continue, Verify, Get Started |
| `.secondary` | neutral glass | brand-tinted | secondary actions |
| `.tertiary` / `.ghost` | text-only / hairline glass | accent | "Not now", "Use another account" |
| `.destructive` | red-tinted glass | red/light | delete, sign out |
| `.appleSignIn` | **system black/white** | system | **ONLY** permitted black control |

**Hard rule:** any `Color.black` / `.background(.black)` / near-black fill on a non-Apple control
is a violation. Apple uses `SignInWithAppleButton(.signInWithAppleButtonStyle(.black))` (or
`ASAuthorizationAppleIDButton`) clipped to the pill radius — never a hand-rolled `Capsule().fill(.black)`.

## States (all defined here, all glass-consistent)
`default` · `pressed` (scale ≤0.97, no separate color that drops below AA) · `disabled`
(whole-control opacity, label stays AA — never fade label into the failing gray zone) ·
`loading` (inline glass spinner, control disabled, no double-tap) · `success`.
Social/landing buttons MUST gain a loading+disabled state (fixes A-08).

## Sizing / Dynamic Type
- Min target **44pt**. Use `minHeight`, never fixed `.frame(height: 52)` (clips at AX5).
- Label grows → pill grows, never truncates. `.lineLimit(1).minimumScaleFactor(0.85)` permitted as backstop.
- Fonts via `.systemScaled` (UIFontMetrics). No bespoke OpenSans in the auth flow (fixes A-03).

## Glass-on-glass
Stacked glass surfaces are grouped in a single `GlassEffectContainer` (the one in
`GlassEffectModifiers.swift` — delete the `Extensions.swift` duplicate). Inner surfaces that
can't be grouped use a solid/material backing. No un-contained glass-on-glass.

## Accessibility coupling
The style reads `@Environment(\.accessibilityReduceTransparency)` and renders an **opaque**
`Color(.systemBackground)`/tint fill when on (see `AccessibilityFallback.md`). This is the single
fix point for E-01/E-02/G-09 — screens must not hand-roll material fills that bypass it.
