# FIXED — Overnight Audit 2026-05-30

Items confirmed fixed this audit session (branch `overnight/design-pass-20260530`).

---

## Batch R24 — DS-A05 through DS-A11 (reduce-motion rollout)
**Commit:** `6d58e7b` | `fix(a11y): DS-01 reduce-motion rollout — batch R24 (39 files, ~90 instances)`

| # | Finding | File | What Changed |
|---|---------|------|-------------|
| DS-A05 | Repeating animations unguarded | ComponentsSharedUIComponents.swift | Added env var; guarded 3 `.repeatForever` + 1 bare spring |
| DS-A06 | BereanLandingView env var unused | BereanLandingView.swift | 11 nested structs now read `reduceMotion`; 10 spring calls guarded |
| DS-A07 | StarRatingRow bare spring | StarRatingRow.swift | env var + `.animation` guarded |
| DS-A08 | MentorCardView bare springs | MentorCardView.swift | 2 `.animation` calls guarded |
| DS-A09 | AmenTranslationComparisonCard | AmenTranslationComparisonCard.swift | env var + `.animation` guarded |
| DS-A10 | 19 bare withAnimation (4 files) | TipSheetView, TipView, MovementWellnessView, FindChurchView | reduceMotion env var + all `withAnimation` guarded |
| DS-A11 | 41+ bare withAnimation (22 files) | WellnessRiskLayer, ProfilePhotoEditView, GivingInAppSheet, EmailVerificationGateView, CrisisSupportCard, CarPlay/BereanDriveSetupView, ChurchLiveModeView, ContactSearchView, DisasterAlertCard, BreathingExerciseView, BereanChurchNotesBridge, AmenSyncStudioView, LegacyStudioView, PrayerView, SavedPostsQuickAccessButton, SelahScriptureReaderView, SmartChurchNotifications, VergeCreateRoomSheet, VergeCreatorStudioView, ChurchNotesPremiumEditor, ChurchNotesView, ContentView, FollowButton, UserProfileView, SupportSurfaceIntegration, WellnessDetailView, SpacesDesignSystem, AmenSpacesDiscussionDiscoveryView, MessagingComponents | All `withAnimation {}` guarded; `@Environment(\.accessibilityReduceMotion)` added where missing |
| UI-01 | SpaceRailView "See All" dead button | SpacesDesignSystem.swift | Added `onSeeAll: (() -> Void)?`; wired button with `.disabled(onSeeAll == nil)` |
| UI-02 | AmenSpacesDiscovery dead buttons | AmenSpacesDiscussionDiscoveryView.swift | Added `onView: (() -> Void)?` to spotlight; wired "View" button |
| UI-03 | MessagingComponents demo button | MessagingComponents.swift | Added `.disabled(true)` + `.accessibilityHidden(true)` on placeholder |
| NOTES-01 | SelahScriptureReaderView withAnimation | SelahScriptureReaderView.swift | Guarded 2 `withAnimation` calls (lines 386, 391) |
| NOTES-02 | BereanChurchNotesBridge withAnimation | BereanChurchNotesBridge.swift | Guarded `withAnimation(.easeInOut)` at line 337 |

---

## COL-01 — _noop collection in production
**Commit:** `6623cd7` | `fix(infra): gate _noop test collection behind #if DEBUG [AmenObjectHubViewModel.swift]`

| # | Finding | File | What Changed |
|---|---------|------|-------------|
| COL-01 | `_noop` Firestore read in production | AmenObjectHubViewModel.swift | `loadMembership()` body wrapped in `#if DEBUG` |

---

## Pre-existing fixes (confirmed by domain audits, applied in prior sessions)

| Finding | File | Confirmed Fix |
|---------|------|--------------|
| FEED-02 | HeyFeedNLInputView.swift | `.onDisappear { nlService.stopListening() }` at line 95 |
| FEED-06 | HeyFeedComposerView.swift | `.onDisappear { service.stopListening() }` at line 61 |
| FEED-07 | FeedIntelligenceService.swift | All 4 `withAnimation` calls guarded with `UIAccessibility.isReduceMotionEnabled` |
| FEED-11 | HeyFeedService.swift:316 | `merge: true` already in place |
| AUTH-01 | OnboardingQuizView.swift:144 | `guard let userId else { return }` in place |
| AUTH-08 | EmailVerificationGateView.swift:48 | `?? "your email address"` fallback in place |
| STUDIO-03 | StudioAICreationView.swift | Cancel button + `generateTask?.cancel()` implemented |
| STUDIO-08 | StudioAICreationView.swift | Per-minute retry rate limit (max 3 / 60 s) implemented |
| STUDIO-19 | StudioAICreationView.swift | Entitlement gate before `generate()` at line 131 |
| MEDIA-04 | AmenMediaSessionView.swift | `vm.isLoading` and `vm.error` surfaced in UI at lines 269-276 |
| BEREAN-12 | BereanLandingView.swift | `AmenAIConsentStore.shared.hasConsent(for: .bereanQuickAnswer)` at line 232 |
| FLAG-01 | ChurchAssistFeatureFlags.swift | `debugForceAllEnabled` already `#if DEBUG` guarded — finding was moot |
| NAV-01 | NotificationDeepLinkHandler deprecated | No active call sites found — finding was moot |

---

## False Positives / Already Correct

| Finding | Reason |
|---------|--------|
| GroupChatCreationView.swift COMMS-02 | Entire file body (lines 12–769) is inside a block comment — dead code |
| FLAG-01 ChurchAssistFeatureFlags.debugForceAllEnabled | Already correctly wrapped `#if DEBUG / #else` |
| NAV-01 deprecated handler call sites | Only reference is inside a code comment; `LegacyNotificationDeepLinkHandler` is a separate class |
| FEED-11 merge:false | Already `merge: true` — prior session fix |
| FEED-09 lazy var | `Firestore.firestore()` is a singleton — functionally safe, no change needed |

