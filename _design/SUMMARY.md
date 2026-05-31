# AMEN — Overnight Design Audit · Morning Report
**Branch:** `overnight/perf-pass-20260531`  
**Date:** 2026-05-31  
**Build:** ✅ 0 errors · 0 new warnings  
**Read time:** ~2 min

---

## Coverage

| Domain | Components | HIGH | MED | LOW | OK | QUEUE |
|--------|-----------|------|-----|-----|----|-------|
| Feed / Home | 16 | 1 | 4 | 3 | 8 | 1 |
| Messages / Inbox | 18 | 1 | 3 | 7 | 5 | 2 |
| Prayer / Wellness / Spaces | 18 | 3 | 8 | 4 | 10 | 2 |
| Berean / Church Notes | 19 | 0 | 7 | 9 | 9 | 0 |
| Profile / Auth | 14 | 0 | 4 | 6 | 2 | 2 |
| Find Church / Giving / GUARDIAN | 17 | 2 | 8 | 4 | 3 | 4 |
| Shared / Tab Bar / Design System | 15 | 0 | 4 | 2 | 9 | 0 |
| **TOTAL** | **117 / 117** | **7** | **38** | **35** | **46** | **11** |

Coverage: **100%** of core feature domains.  
Compliance before this session: **39%** (46/117 fully compliant).  
Compliance after safe fixes applied: **~47%** (55/117 — 9 components upgraded to compliant this session).

---

## Fixes Applied This Session (Phase 2 safe)

All items below are ≥90% confidence, build-verified, and build-passing.

| # | ID | Domain | File | Change | SHA |
|---|----|--------|------|--------|-----|
| 1 | SHR-01 | Glass Kit | `AmenGlassSurface` | + `accessibilityReduceTransparency` solid fallback | `5684e02` |
| 2 | SHR-02 | Glass Kit | `AmenGlassIconButton` | + reduce-transparency fallback | `5684e02` |
| 3 | SHR-03 | Glass Kit | `BereanActionChip` | + reduce-transparency fallback | `5684e02` |
| 4 | SHR-04 | Glass Kit | `BereanModePill` | + reduce-transparency fallback | `5684e02` |
| 5 | SHR-05 | Glass Kit | `BereanMicButton` | + reduce-transparency fallback | `5684e02` |
| 6 | SHR-06 | Glass Kit | `AmenGlassSurfaceLayer` | + reduce-transparency in `AmenGlassButtonSystem.swift` | `5684e02` |
| 7 | FCG-06 | Find Church | `FeatureCard` (ChurchNotesOnboardingView) | `.white` → `.ultraThinMaterial` + dark-mode foreground fix | `5684e02` |
| 8 | DIS-01 | Feed | `DisasterAlertCard` | + reduce-transparency + reduce-motion guard on pulse ring | `5684e02` |

---

## Fixes Applied in Prior Overnight Commits (on this branch)

| # | ID | Domain | File | Change | SHA |
|---|----|--------|------|--------|-----|
| 9 | DS-A01 | Design System | `TipSheetView.swift` | Hardcoded hex → `amenPurple`/`amenGold`/`amenBlack` tokens | `66ec354` |
| 10 | AUTH-01 | Auth | `OnboardingQuizView.swift` | Guard userId nil → no unauthenticated Firestore write | `1c7e480` |
| 11 | AUTH-08 | Auth | `EmailVerificationGateView.swift` | Nil email → fallback "your email address" | `eaa22df` |
| 12 | FEED-02 | Feed | `HeyFeedNLInputView.swift` | Add `onDisappear { nlService.stopListening() }` — listener leak | `1febfa6` |
| 13 | FEED-04 | Feed | `HeyFeedActiveRequestsView.swift` | Add `reduceMotion` guard on `withAnimation` | `ee24292` |
| 14 | FEED-05 | Feed | `HeyFeedActivePillsBar.swift` | Add `reduceMotion` guard on `.animation` | `2f9c826` |
| 15 | FEED-06 | Feed | `HeyFeedComposerView.swift` | Add `onDisappear stopListening` + reduce-motion guards | `582e6c9` |
| 16 | FEED-07 | Feed | `FeedIntelligenceService.swift` | Gate `withAnimation` on `UIAccessibility.isReduceMotionEnabled` | `3e0fc3a` |
| 17 | FEED-09 | Feed | `ActivityFeedView.swift` | Remove `lazy var` from async function scope | `b9f3be2` |
| 18 | FEED-11 | Feed | `HeyFeedService.swift` | `setData(merge: false)` → `merge: true` for idempotent resonance | `d84b2e3` |
| 19 | HUB-01 | 242 Hub | `TwoFourTwoHub.swift` | Tier fetch with loading/error state (silent .free default removed) | `e22b586` |
| 20 | BEREAN-12 | Berean AI | `BereanLandingView.swift` | Gate input behind `AmenAIConsentStore` — AI without consent blocked | `b9f3be2` |
| 21 | STUDIO-03 | Studio | `StudioAICreationView.swift` | Cancel button for in-flight AI generation | `10b8c9d` |
| 22 | STUDIO-08 | Studio | `StudioAICreationView.swift` | 3-per-60s rate limit on Regenerate taps | `8f997e5` |
| 23 | STUDIO-19 | Studio | `StudioAICreationView.swift` | Entitlement check before `studioGenerateContent` CF call | `26794f5` |
| 24 | MEDIA-07 | Media | `AmenMediaUploadFlowView.swift` | Content preflight before video publish | `9efdb72` |
| 25 | UI-fix | Shared | `AMENPillNav.swift` | Fixed-width tab items (prevents layout compression) | `1062310` |

---

## Review Queue — Blocked Items (human sign-off required)

Sorted by impact. See full detail: `_design/REVIEW-QUEUE.md`

| Priority | ID | Screen | Why Blocked |
|----------|----|--------|-------------|
| 🔴 P0 | RQ-G1 | WellnessCrisisSheet | GUARDIAN-critical path — safety team sign-off required |
| 🔴 P0 | RQ-G3 | CrisisSupportCard | GUARDIAN-owned card — product + safety team approval |
| 🔴 P0 | RQ-S2 | AuthenticationViewModel | Client-side deactivation bypass — auth owner fix |
| 🔴 P0 | RQ-S3 | MinimalAuthenticationView | COPPA age gate not enforced — legal review |
| 🟠 P1 | RQ-G2 | WellnessSupportSheet | Adjacent to GUARDIAN — safety review |
| 🟠 P1 | RQ-H1 | HeyFeedControlsSheet | Flat opaque overlay — visual QA before applying |
| 🟠 P1 | RQ-H2 | LiquidGlassMessagesView | Performance concern on A14 — test before glass on bubbles |
| 🟠 P1 | RQ-H3 | BreathingExerciseView | Vestibular risk — accessibility + wellness UX review |
| 🟠 P1 | RQ-H4 | MovementWellnessView | Same as RQ-H3 |
| 🟡 P2 | RQ-S1 | Backend CF deployment | 378 iOS callables hit TS backend — confirm deployed |
| 🟡 P2 | RQ-S4 | AffiliateLinkBuilder | Associates tag in binary — move to Remote Config |
| 🟡 P2 | RQ-A1 | GivingInAppSheet | Payment form — payments owner QA pass |

---

## Accessibility Gate Vetoes

The following items were **NOT auto-fixed** because they touch surfaces with active user harm potential:

- **BreathingExerciseView / MovementWellnessView** — 5+ animation states (inhale/hold/exhale) must ALL be verified with `reduceMotion` before any visual change ships. Wellness UX review required.
- **CrisisSupportCard / WellnessCrisisSheet** — Refused to apply glass changes to GUARDIAN path without safety team sign-off. Applied fix in `DisasterAlertCard` (adjacent, lower risk).
- **LiquidGlassMessagesView** — Refused material changes to message bubbles without performance testing on A14, per audit contract (no performance regressions on tier-1 features).

---

## Blockers

1. **Backend TS functions not confirmed deployed** (RQ-S1): 378 iOS callables (`bereanChatProxy`, `acceptAccessPass`, `studioGenerateContent`, etc.) depend on a separate TypeScript codebase. If not deployed to the Firebase project, these silently fail. **Needs backend team confirmation.**

2. **COPPA / age gate** (RQ-S3): DOB collected but 13+ not validated server-side before auth completes. **Needs legal review before shipping to minors.**

3. **Amazon tag in binary** (RQ-S4): `"amenapp-20"` visible in compiled output. **Needs Remote Config migration.**

---

## Resources

| File | Purpose |
|------|---------|
| `_design/DESIGN-STANDARD.md` | Canonical Liquid Glass spec — materials, radii, hero, sheet, tab bar, motion |
| `_design/reference.html` | Interactive demo of all 5 canonical patterns + palette swatches |
| `_design/MANIFEST.md` | 117-component coverage matrix with severity per domain |
| `_design/FINDINGS.md` | Full per-component finding table |
| `_design/REVIEW-QUEUE.md` | Detailed queue entries with proposed diffs and risk ratings |
| `_audit/FINDINGS.md` | Functional/CF/auth/media findings (separate from design audit) |

---

## What's Next

**Highest-impact pending safe fixes** (no review needed, ≥90% confidence):
1. `PersonalizedGreetingView.swift` — replace `Color(.systemGray6)` with `.ultraThinMaterial` + reduce-transparency
2. `ModernChatInputBar` in `MessagingComponents.swift` — replace opaque `systemGray6` background with glass capsule per spec
3. `SupportSurfaceIntegration.swift` — `SupportChipsRow` flat chips → `.ultraThinMaterial` capsule
4. DS-A06: `BereanLandingView.swift` — wire existing `reduceMotion` env var into 11 animation call sites (it's declared but unused)
5. FEED-03: `HeyFeedNLInputView.swift` — two remaining unguarded `Motion.adaptive()` calls

**Path to 80% compliance:** ~25 more MEDIUM surgical fixes across the remaining Queued rows in MANIFEST.md, primarily reduce-transparency fallbacks on glass surfaces.
