# Onboarding & Auth Contracts

Frozen contracts for the onboarding/authentication remediation (see `AUDIT.md`).
**No SwiftUI lands until the relevant contract here is confirmed.** All remediation
ships behind `ff_onboarding_v2` (default OFF), one contract → one PR, green build per wave.

## Locked product decisions (§7)

| # | Decision | Resolution |
|---|----------|------------|
| 7.1 | Session model | **Biometric re-auth on resume.** "Continue as {name}" shows face+name; tapping requires Face ID (fallback OTP). `rememberedSessionRef` stores **only the hint**, never a live token. |
| 7.2 | E2EE recovery | **All layers.** Recovery phrase (E2EE-preserving default) + iCloud Keychain escrow + server-escrowed fallback, offered in that priority order. |
| 7.3 | Email auth | **Both.** Magic link primary, password fallback. Both lanes maintained + tested. |
| 7.4 | Color scheme | **Full semantic dark support.** Replace literal `Color.black`/`.white`/`Color(white:0.xx)` with semantic colors across all surfaces. |

## Files
- `GlassButton.md` — §2.1 canonical pill, variants, states, color law.
- `AuthStateMachine.md` — §2.2 single continuous flow, nodes, transitions.
- `IdentityHint.md` — §2.3 Keychain hint, returning-user, E2EE recovery handoff.
- `AccessibilityFallback.md` — §2.4 Reduce Transparency/Motion, contrast, Dynamic Type, VoiceOver.

## GlassKit reuse
`AmenGlassButtonStyle` (`AmenGlassButtonSystem.swift`) is the chosen canonical primitive.
The 13+ competing button styles and the duplicate `GlassEffectContainer` are to be
consolidated, not extended. Do not invent a new glass primitive — raise a contract change.
