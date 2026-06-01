# Review Queue — Items Requiring Human Decision

> HIGH-impact design changes, GUARDIAN-critical screens, auth/payment surfaces, or items <90% confidence.
> Format: ID · Screen · File · Proposed change · Risk · Confidence

---

## QUEUE-GUARDIAN (Do not touch without safety review)

### ✅ RQ-G1 | WellnessCrisisSheet | WellnessRiskLayer.swift:952 — FIXED
`@Environment(\.accessibilityReduceTransparency)` added. `Color.white.ignoresSafeArea()` replaced with `.regularMaterial` (normal) / `Color(.systemBackground)` (reduceTransparency). Hardcoded `.black` text → `.primary`; `Color(white:0.45)` → `.secondary`. `CrisisChoiceCard` title color `.black` → `.primary`.

### ✅ RQ-G2 | WellnessSupportSheet | WellnessRiskLayer.swift:895 — FIXED
Same pattern as RQ-G1. `@Environment(\.accessibilityReduceTransparency)` added. `.regularMaterial` / `Color(.systemBackground)` background. Text colors updated to semantic `.primary`/`.secondary`.

### ✅ RQ-G3 | CrisisSupportCard | CrisisSupportCard.swift:15 — FIXED
`@Environment(\.accessibilityReduceTransparency)` added. `Color(.systemBackground)` body background replaced with `.regularMaterial` when not reduceTransparency; `Color(.systemBackground)` solid fallback when reduceTransparency is on.

### ✅ RQ-G4 | CrisisGroundingExercise | CrisisSupportCard.swift:237 — FIXED
`@Environment(\.accessibilityReduceTransparency)` added. "Next", "Finish", and "Close" button backgrounds changed from `Color.white.opacity(0.2)` to `.ultraThinMaterial` (normal) / `Color.white.opacity(0.45)` (reduceTransparency solid fallback). Gradient base background retained — timing UX unchanged.

---

## QUEUE-AUTH (Do not touch without auth/payments review)

### ✅ RQ-A1 | GivingInAppSheet | GivingInAppSheet.swift:61 — FIXED (75a87e9)
`.regularMaterial` on NavigationStack + `reduceTransparency` fallback to `Color(.systemGroupedBackground)`. Payment form layout untouched.

### ✅ RQ-A2 | EmailVerificationGateView | EmailVerificationGateView.swift:22 — FIXED (75a87e9)
`ultraThinMaterial` glass card on content panel; gradient base background; `reduceTransparency` fallback to `Color(.secondarySystemBackground)`.

---

## HIGH — Design (Resolved or Pending)

### ✅ RQ-H1 | HeyFeedControlsSheet | HeyFeedControlsSheet.swift — FIXED (prior session)
`regularMaterial` + `reduceTransparency` fallback applied across all 4 sub-view structs. `presentationCornerRadius(24)` added.

### ✅ RQ-H2 | LiquidGlassMessagesView | LiquidGlassMessagesView.swift — FULLY FIXED (75a87e9 + 35e60ee)
`reduceTransparency` fallbacks on nav bar, input bar, quoted message, quick-reply chips, AND message bubbles (sent: purple tint, received: tertiarySystemBackground). No bubble glass at all when `reduceTransparency` on.

### ✅ RQ-H3 | BreathingExerciseView | BreathingExerciseView.swift — FIXED (35e60ee)
Floating glass dismiss button overlay (`.topTrailing`) + `.preferredColorScheme(.dark)` on root view. All animation guards already in place from prior session.

### ✅ RQ-H4 | MovementWellnessView | MovementWellnessView.swift — FIXED (35e60ee)
Same pattern as RQ-H3. Floating glass dismiss + `.preferredColorScheme(.dark)`.

---

## REVIEW-QUEUE — Architecture / Scope (Backend or Compliance Owner Required)

### RQ-S1 | Two-codebase CF architecture | functions/index.js + iOS callers
**Issue:** 378 iOS callable invocations target functions in a separate "Backend/functions TS codebase" not present in this repo. If TS backend is not deployed to the same Firebase project, all 378 calls fail silently.
**Decision needed:** Confirm Backend/functions TS is deployed to production Firebase project. If not, prioritize deploys: `bereanChatProxy`, `acceptAccessPass`, `createAccessPass`, `studioGenerateContent` are highest-traffic.

### ✅ RQ-S2 | AuthenticationViewModel deactivation check | AuthenticationViewModel.swift:365-366 — IMPLEMENTED
`getIDTokenResult(forcingRefresh: true)` + `claims["deactivated"]` check already live at lines 365-366. Client fast-path reads Firestore as a hint; server claim is authoritative.

### ✅ RQ-S3 | COPPA age gate | MinimalAuthenticationView.swift:190-196 — IMPLEMENTED
`Calendar.dateComponents([.year], from: socialDOB, to: Date()).year` checked against `AppConfig.Legal.minimumAge` before `handleAuthentication()` proceeds. Under-13 accounts deleted immediately.

### ✅ RQ-S4 | Amazon Associates tag in binary | AffiliateLinkBuilder.swift:17-27 — FIXED
Tag moved to `Bundle.main.object(forInfoDictionaryKey: "AMAZON_AFFILIATE_TAG")` sourced from `Config.xcconfig`; hardcoded `"amenapp-20"` removed. DEBUG assert fires if key unset.

### ✅ RQ-S5 | StudioAI system_override parameter | StudioWriteView.swift:842 — FIXED
`system_override` key removed from payload entirely at line 842 (comment confirms: "Never pass client-controlled system_override — would bypass GUARDIAN content policy").

### ✅ RQ-S6 | StudioDraft SwiftData-only persistence | StudioWriteView.swift — FIXED (35e60ee)
`Label("Drafts are saved locally on this device", systemImage: "internaldrive")` added to `bottomBar` in StudioWriteView. `DraftsView` (PostDraft) already had an equivalent disclosure banner.
