# A11Y-LABELS — Missing accessibility labels on interactive controls (grouped)

- **Flow:** Onboarding, Auth landing, Feed, Settings, Berean entry
- **Severity:** visual (VoiceOver compliance)
- **Scope:** IN-SCOPE
- **Status:** FIXED (Tier-1) — 10 controls; toggles use `.isSelected` traits (preserve text), AUTH-05 reclassified display-only; build GREEN 2026-06-17; VoiceOver verify still pending

Icon-only / text-only buttons missing `.accessibilityLabel`. Each line is a discrete fix:

| # | File:line | Control | Suggested label |
|---|---|---|---|
| 1 | `OnboardingFlowView.swift:~344` | birth-date toggle button | "Toggle birth date picker" |
| 2 | `OnboardingFlowView.swift:~555` | terms agreement checkbox | "Toggle terms agreement" |
| 3 | `OnboardingFlowView.swift:~762` | privacy/data ack checkbox | "Toggle data collection acknowledgment" |
| 4 | `OnboardingFlowView.swift:~985` | faith-stage option buttons | `stage.label` per option |
| 5 | `OnboardingFlowView.swift:~1115` | "Maybe Later" (notifications) | "Skip notification setup" |
| 6 | `OnboardingFlowView.swift:~1668` | follow/following (suggested users) | "Follow \(displayName)" / "Unfollow \(displayName)" |
| 7 | `AMENAuthLandingView.swift:~369` | remembered-account card | "Sign in as \(rememberedDisplayName)" |
| 8 | `FollowThroughInteractions.swift:~541` | AI sparkle button (feed) | "Ask Berean about this post" |
| 9 | `SettingsView.swift:~604` | `SDToggleRow` toggle (label hidden) | bind `.accessibilityLabel(label)` |
| 10 | `BereanLandingView.swift:~268, ~327` | Berean continuity/continue cards | "Continue previous study" etc. |

**Suspected fix:** Add the labels above; for the hidden-label toggle, attach `.accessibilityLabel(label)` before `.labelsHidden()`.
