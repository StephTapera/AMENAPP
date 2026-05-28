# Liquid Glass Remediation Plan

**Synthesized:** 2026-05-28  
**Inputs:** liquid-glass-standard.md · button-audit.md · error-surface-audit.md · error-coverage-gaps.md  
**Status:** AWAITING USER APPROVAL before Phase 3 begins

---

## Executive Summary

All four audit docs agree on one critical fact: **every reusable Liquid Glass component already exists.**
The problem is adoption, not creation.

| Audit | Finding |
|-------|---------|
| Standard | `AmenLiquidGlassPillButton`, `AmenLiquidGlassButton`, `.amenAlert()` — all production-ready |
| Buttons | 1,311+ buttons; only 3.4% conform; 68.6% use system styles or solid Color fills |
| Error surfaces | 87 surfaces; 61 missing glass; 58 native `.alert()` calls → must become `.amenAlert()` |
| Coverage gaps | 55 silent failures; 8 CRITICAL (money, data loss, auth); 14 HIGH (streaming, persistence) |

**Phase 3 is entirely integration work. No new components will be created.**

⚠️ A prior agent wrote a remediation plan that incorrectly said `LiquidGlassAlert.swift` needed to be created. It already exists at `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassAlert.swift` with full `.amenAlert()` modifier. This plan supersedes that version.

---

## Canonical Component Reference (use these — invent nothing)

| Need | Component | File |
|------|-----------|------|
| Any glass button | `AmenLiquidGlassPillButton` (capsule) or `AmenLiquidGlassButton(shape:intensity:)` (any shape) | `AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift` |
| Press animation only | `SelahGlassPressButtonStyle` | `SelahScripture/SelahGlassPressButtonStyle.swift` |
| Any modal / alert / confirmation | `.amenAlert(isPresented:config:)` with `LiquidGlassAlertConfig` | `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassAlert.swift` |
| Toast / banner | `ToastNotificationView` / `ErrorBannerView` (already glass-aligned) | existing |
| Filter pill row | `AmenLiquidGlassPillButton` segmented — no new component needed | same |

Design token values → `LiquidGlassTokens.swift` and § 6 of `liquid-glass-standard.md`.

---

## Fix Areas — Ordered Execution

Build must pass with 0 errors after each area before the next begins.

---

### Area 1 — Critical Safety Net

**Why first:** Silent failures where the app either loses user data, charges money,
or leaves auth state inconsistent. Visual polish is irrelevant if these are broken.

| File | Line | Operation | Fix |
|------|------|-----------|-----|
| `AmenCovenantCheckoutService.swift` | 79, 92 | Stripe session creation + ASWebAuth callback not shown on-screen | Add `@Published var checkoutError`; wrap callables in `do/catch`; bind to `.amenAlert()` with "Retry / Contact Support" |
| `AMENAPPApp.swift` | 434 | `try? Auth.auth().signOut()` silently swallows auth errors | Replace `try?` with proper `do/catch`; show `.amenAlert()` "Sign Out Failed" |
| `DeleteAccountView.swift` | 170–180 | Deletion error stored in `@State` but not shown | Bind `deletionError` to `.amenAlert()` with `.destructive` tone + Retry |
| `PhoneVerificationService.swift` | 69–70 | SMS send fails silently; user waits forever for code that never arrives | Add `@Published var showVerificationError`; on `.failed`, show `.amenAlert()` |
| `CloudStorageService.swift` | 58–94 | Upload failure may not reach callback observers; post publishes with broken links | Add explicit `.observe(.failure)` handler → `.amenAlert()` with Retry |
| `CreatePostView.swift` | 5832–5863 | `try await putDataAsync` with no catch updating UI; post publishes with missing media | Wrap all media uploads in `do/catch`; show `.amenAlert()` before allowing publish |

---

### Area 2 — P0 Alert Migrations + Berean Streaming

**Why second:** The app's most-trafficked error paths still use native system `.alert()`.
Migrating them changes what the majority of users see during errors.

**Sub-area 2a — native `.alert()` → `.amenAlert()` (P0 list):**

| File | Lines | Key button config |
|------|-------|-------------------|
| `CreatePostView.swift` | 1421, 1507, 1528, 1634, 7465 | Safety check → "Edit & Continue" + "Cancel"; upload error → "Retry"; draft recovery → `.destructive` "Discard"; paywall → `.primary` amenGold "Upgrade" |
| `SignInView.swift` | AlertsModifier | Primary "Try Again", dismiss "Cancel" |
| `CommunityCovenantView.swift` | 233 | Primary "Try Again" |
| `AMENAPPApp.swift` | 196 (version kill switch) | Primary "Update Now" — no cancel (force update) |

**Sub-area 2b — Berean streaming HIGH gaps:**

| File | Line | Fix |
|------|------|-----|
| `BereanPulseViewModel.swift` | 216–223 | Replace `try?` with `do/catch`; set `feedState = .error(...)` |
| `BereanIntegrationService.swift` | 69–82 | Wrap `for await chunk` Task in outer `do/catch` → `@Published var streamError` |
| `BereanLiveTranscriptService.swift` | 24–40 | Pass listener `error` param to `@Published var listenerError` → `.amenAlert()` |
| `BereanRealtimeSessionManager.swift` | 97–106 | On listener error, also set `sessionState = .failed(error)` and show glass modal |

---

### Area 3 — High-Traffic Button Fixes

**Why third:** These appear on every screen. Highest visual impact per line changed.

| File | What | Current | Fix |
|------|------|---------|-----|
| `NotificationBellButton.swift` | 47, 78 — badge pill | `Color.red` Capsule fill | `.ultraThinMaterial` base; red badge overlay only (not pill background) |
| `SavedPostsQuickAccessButton.swift` | 46 — badge | `Color.red` + `Color.blue` icon | `Capsule().fill(.ultraThinMaterial)` + white border per token spec |
| `PrayerView.swift` | 100–103 — filter pills | `Capsule().fill(Color.black)` | `AmenLiquidGlassPillButton` segmented |
| `TestimoniesView.swift` | 100–103 — category filters | Same `Color.black` pattern | Extract shared `LiquidGlassFilterPills` with PrayerView — one component, two callers |
| `SettingsView.swift` | 19–28, 86–100 — nav row panels | Custom `Color(red: 0.12...)` fills | Replace with `LiquidGlassTokens.blurRegular` + overlay |

---

### Area 4 — Core Feature Buttons (High-Volume Views)

**Why fourth:** Three files account for 200+ buttons. Moving them shifts the conformance metric.

| File | Count | Current | Fix |
|------|-------|---------|-----|
| `CreatePostView.swift` | 92+ | `.plain` with no glass | Attachment/action buttons → `AmenLiquidGlassButton(shape: .capsule)` |
| `BereanChatView.swift` | 38+ | `.plain` + Color fills | Apply `SelahGlassPressButtonStyle` + `.ultraThinMaterial` to action tiles; migrate mode selector |
| `ProfileView.swift` | 88+ | Mixed `.bordered` + plain | Follow/message/share → `AmenLiquidGlassPillButton`; edit → `AmenLiquidGlassButton` |

---

### Area 5 — P1 Alert Migrations + HIGH Coverage Gaps

**Sub-area 5a — P1 native alert migrations:**

| File | Lines | Fix |
|------|-------|-----|
| `BereanChatView.swift` | 1146, 1151, 1188 | 3 native alerts → `.amenAlert()`; success uses `.spiritual` tone |
| `ReportContentView.swift` | 132, 139 | Success + error → `.amenAlert()` |
| `GroupChatCreationView.swift` | 134 | "Couldn't Create Group" → `.amenAlert()` with Retry |
| `QuoteComposerView.swift` | 69 | "Unable to Post" → `.amenAlert()` with Retry |
| `AccountLinkingView.swift` | 332, 345 | Unlink → `.destructive`; error → `.amenAlert()` |
| `AmenSpaceBannerRail.swift` | 842 | "Could not save banner size" → `.amenAlert()` |

**Sub-area 5b — HIGH coverage gaps:**

| File | Line | Fix |
|------|------|-----|
| `ModernPrayerWallView.swift` | 645, 670, 675 | Wrap Firestore writes in `do/catch`; show `.amenAlert()` on failure |
| `BereanMemoryService.swift` | 49–51, 69, 81, 88 | Listener error → `@Published var observationError` + banner; insight CRUD → `@Published var saveError` + `.amenAlert()` with Retry |
| `AmenSpaceBannerRail.swift` | 525, 533 | Replace `try?` on pref save → `.amenAlert()` on failure |
| `MentorshipService.swift` | 50, 82, 98 | Wrap sync Firestore throws in `do/catch` or convert to `async throws` |

---

### Area 6 — Premium / Payments + P2

**Buttons on premium surfaces:**

| File | Fix |
|------|-----|
| `GivingGoalView.swift` | CTA buttons → `AmenLiquidGlassPillButton` with amenGold accent |
| `GivingInAppSheet.swift` | System `.bordered` → glass capsule |
| `JobDetailView.swift` | 23 `.bordered` buttons → `AmenLiquidGlassButton` |
| `BereanShareSheet.swift` | 3× `.borderedProminent` → `AmenLiquidGlassPillButton` |

**P2 alert migrations (batch pass):**

`PrivacyDashboardView.swift:133`, `JobSearchView.swift:82`, `ChurchChemistryService.swift:183`,
`BereanToolbarExtras.swift:90`, `PrayerSuggestedRailView.swift:44`,
`ResourcesView.swift:1987`, `ResourcesView.swift:2089`, `SavedPostsView.swift:130`

**P2 coverage gaps:**

| File | Fix |
|------|-----|
| `BereanRealtimeServices.swift` | 64, 75 — translation pref load/save: catch → show toast on save fail |
| `CreatorVideoProcessingService.swift` | 63, 66 — replace `try?` on video processing callables; add `@Published var processingError` |
| `BereanChatView.swift` | 781, 784 — chat message delete failure → `.amenAlert()` with Retry |
| `PremiumManager.swift` | 83, 182, 211 — product-load + transaction listener errors → bound to `.amenAlert()` |

---

### Area 7 — Systematic Batch (Auth / Onboarding / Wellness / Safety)

Remaining `.bordered`/`.plain` instances. Pattern for all: replace with
`AmenLiquidGlassButton(shape: .capsule, intensity: .light)` for secondary actions,
`AmenLiquidGlassPillButton` for primary CTAs.

Files: `FindChurchView.swift` (79 buttons), `AMENAuthLandingView.swift`,
`AMENAccountTypeOnboardingView.swift`, `EmailVerificationGateView.swift`,
`PhoneVerificationView.swift`, `BreathingExerciseView.swift`,
`WellnessDetailView.swift`, `GraceBasedSafetyUI.swift`,
`SelahScriptureReaderView.swift`, `SelahReflectionListView.swift`

---

## Deferred (design spec required first)

| Item | Reason |
|------|--------|
| `.confirmationDialog()` → glass action sheet (11 calls) | No glass action sheet component exists; needs design spec before any code |
| Empty state standardization (20+ locations) | `CreatorEmptyStateView` pattern exists but needs product decision on canonical pattern |
| LOW coverage gaps (analytics, deep links, suggestions) | Non-user-facing; log-only fixes; low risk; backlog |

---

## Scope at a Glance

| Area | Files | Complexity |
|------|-------|------------|
| 1 — Critical safety net | 6 | Medium — logic + alert wiring |
| 2 — P0 alerts + Berean streaming | 8 | Low-Medium — `.amenAlert()` swap + do/catch |
| 3 — High-traffic buttons | 5 | Low — swap fills + add material |
| 4 — Core feature buttons | 3 (~200 buttons) | Medium — mechanical but systematic |
| 5 — P1 alerts + HIGH gaps | 14 | Low-Medium |
| 6 — Premium + P2 | 12 | Low-Medium |
| 7 — Batch auth/onboarding | 10+ | Low — mechanical replacement |

---

*Awaiting your go-ahead to begin Phase 3 — Area 1.*
