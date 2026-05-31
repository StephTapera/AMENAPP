# Review Queue — Items Requiring Human Decision

> HIGH-impact design changes, GUARDIAN-critical screens, auth/payment surfaces, or items <90% confidence.
> Format: ID · Screen · File · Proposed change · Risk · Confidence

---

## QUEUE-GUARDIAN (Do not touch without safety review)

### RQ-G1 | WellnessCrisisSheet | WellnessRiskLayer.swift:952
**Surface:** GUARDIAN crisis path shown to users in acute mental health distress.
**Issue:** Partial glass; missing `accessibilityReduceTransparency` fallback. Background is flat dark fill — not `.regularMaterial`.
**Proposed change:** Add `@Environment(\.accessibilityReduceTransparency)` fallback. Replace dark fill with `.regularMaterial` per sheet spec. Corner radius 24.
**Risk:** HIGH — any visual regression on this screen during a crisis moment could degrade trust. Needs QA pass with crisis scenario script before applying.
**Decision needed:** Safety team review + QA sign-off before applying.

### RQ-G2 | WellnessSupportSheet | WellnessRiskLayer.swift:895
**Surface:** Pre-crisis / support nudge sheet — shown when risk layer fires.
**Issue:** Partial glass; no `accessibilityReduceTransparency` fallback.
**Proposed change:** Same pattern as RQ-G1.
**Risk:** MEDIUM-HIGH — not GUARDIAN-critical path itself but adjacent.
**Decision needed:** Safety team review before applying.

### RQ-G3 | CrisisSupportCard | CrisisSupportCard.swift:15
**Surface:** Crisis card shown in feed and prayer when sentiment triggers.
**Issue:** No glass at all — flat `Color(.systemGray6)` fills throughout. Spec calls for `.regularMaterial` overlay.
**Proposed change:** Replace flat fills with `.regularMaterial`; add reduce-transparency fallback.
**Risk:** HIGH — card copy and actions are GUARDIAN-owned. Visual change needs product + safety team sign-off.
**Decision needed:** Safety team approval.

### RQ-G4 | CrisisGroundingExercise | CrisisSupportCard.swift:237
**Surface:** In-card grounding exercise (breathing / focus exercises during crisis).
**Issue:** Dark opaque backgrounds; no glass; no accessibility fallback.
**Proposed change:** `.ultraThinMaterial` for interactive controls, solid fallback for reduce-transparency.
**Risk:** HIGH — exercise timing UX is critical; any animation or visual disruption is harmful.
**Decision needed:** Safety + accessibility review before applying.

---

## QUEUE-AUTH (Do not touch without auth/payments review)

### RQ-A1 | GivingInAppSheet | GivingInAppSheet.swift:61
**Surface:** Payment / donation form.
**Issue:** No glass anywhere — flat white form. Spec would call for `.regularMaterial` sheet background.
**Proposed change:** Apply `.regularMaterial` background to form container.
**Risk:** MEDIUM — payment UX regressions (layout shifts, contrast changes) can directly impact conversion and compliance signals. Needs QA on all payment states.
**Decision needed:** Payments owner review.

### RQ-A2 | EmailVerificationGateView | EmailVerificationGateView.swift:22
**Surface:** Auth gate — shown between signup and email verification.
**Issue:** No glass; flat light background.
**Proposed change:** `.ultraThinMaterial` card for the verification prompt panel.
**Risk:** LOW-MEDIUM — auth flow visual regressions could confuse users mid-onboarding.
**Decision needed:** Auth flow QA pass.

---

## HIGH — Design Breakage (Human review before applying)

### RQ-H1 | HeyFeedControlsSheet | HeyFeedControlsSheet.swift:11
**Surface:** Full-screen HeyFeed NL input overlay.
**Issue:** Flat `Color(.systemBackground)` fill — not `.regularMaterial`. No glass at all on a full-screen overlay. This is the most visible departure from the Liquid Glass standard in the feed domain.
**Proposed change:**
```swift
.background {
    ZStack {
        RoundedRectangle(cornerRadius: 24).fill(.regularMaterial)
        RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.08), lineWidth: 0.75)
    }
    .ignoresSafeArea()
}
// reduce-transparency fallback:
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
// → if reduceTransparency: AmenTheme.Colors.backgroundElevated
```
**Risk:** MEDIUM — HeyFeed is a high-traffic interaction point. Regression if material clips content.
**Decision needed:** Visual QA on dark + light mode before merging.

### RQ-H2 | LiquidGlassMessagesView | LiquidGlassMessagesView.swift:43
**Surface:** Full-screen DM view — primary messaging surface.
**Issue:** Navigation bar glass present; but message input bar and hero toolbar missing `accessibilityReduceTransparency`. On older devices with poor GPU, material compositing on every message bubble can cause scroll lag.
**Proposed change:** Add reduce-transparency fallback to toolbar and input bar. Consider moving message bubbles to `.thinMaterial` only on glass-capable devices (check `ProcessInfo` displayGamut).
**Risk:** HIGH — messaging is tier-1 feature. Performance regression on A14 and below.
**Decision needed:** Performance test on iPhone 12 / A14 before applying material changes to bubbles.

### RQ-H3 | BreathingExerciseView | BreathingExerciseView.swift:76
**Surface:** Full-screen wellness breathing exercise — animated hero.
**Issue:** No glass chrome. Status bar not controlled. Reduce-transparency and reduce-motion fallbacks absent.
**Proposed change:** Add floating glass circle for dismiss/back. Force `.lightContent` status bar. Add `@Environment(\.accessibilityReduceMotion)` guard on breathing animation loop (lines 393+).
**Risk:** HIGH — accessibility failure on breathing animations can trigger vestibular issues. Must verify all 5 animation states (inhale/hold/exhale/rest/intro) respect reduce-motion before shipping.
**Decision needed:** Accessibility + wellness UX review.

### RQ-H4 | MovementWellnessView | MovementWellnessView.swift:59
**Surface:** Movement / exercise guided view.
**Issue:** Same pattern as RQ-H3 — no glass chrome, no status bar, no accessibility fallbacks.
**Proposed change:** Same as RQ-H3 pattern.
**Risk:** HIGH — same vestibular concern.
**Decision needed:** Accessibility + wellness UX review.

---

## REVIEW-QUEUE — Architecture / Scope Too Large for Surgical Fix

### RQ-S1 | Two-codebase CF architecture | functions/index.js + iOS callers
**Issue:** 378 iOS callable invocations target functions in a separate "Backend/functions TS codebase" not present in this repo. If TS backend is not deployed to the same Firebase project, all 378 calls fail silently.
**Decision needed:** Confirm Backend/functions TS is deployed to production Firebase project. If not, prioritize deploys: `bereanChatProxy`, `acceptAccessPass`, `createAccessPass`, `studioGenerateContent` are highest-traffic.

### RQ-S2 | AuthenticationViewModel deactivation check | AuthenticationViewModel.swift:337-381
**Issue:** Client-side deactivation check reads Firestore field before server-side token claim verification. A patched client can bypass.
**Decision needed:** Auth owner must add `getIDTokenResult(forcingRefresh: true)` check on every auth state change to validate `deactivated` custom claim server-side.

### RQ-S3 | COPPA age gate | MinimalAuthenticationView.swift:776-781
**Issue:** DOB collected but no 13+ validation enforced before `handleAuthentication()`. COPPA compliance gap.
**Decision needed:** Legal/compliance team review. Add server-side age validation in auth CF.

### RQ-S4 | Amazon Associates tag in binary | AffiliateLinkBuilder.swift:19
**Issue:** Hardcoded `"amenapp-20"` tag visible in compiled binary. Tag rotation requires app update.
**Decision needed:** Move tag to Remote Config. Add FTC disclosure UI before affiliate link clicks.

### RQ-S5 | StudioAI system_override parameter | StudioWriteView.swift:800-853
**Issue:** Client passes `"system_override"` to `studioGenerateContent` CF. If backend does not whitelist this parameter, custom prompts could bypass content policies.
**Decision needed:** Backend owner to confirm CF validates/strips `system_override` before forwarding to Vertex AI.

### RQ-S6 | StudioDraft SwiftData-only persistence | StudioDraft.swift
**Issue:** All studio drafts stored in SwiftData only. Device reset = data loss.
**Decision needed:** Backend owner to confirm if cloud backup is planned; add user-visible "drafts are local only" warning in the interim.
