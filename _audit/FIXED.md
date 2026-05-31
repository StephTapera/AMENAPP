# FIXED — Overnight Audit 2026-05-30 / 2026-05-31
**Branch:** `overnight/perf-pass-20260531` (all commits since `5fe4fba`)

---

## Summary: 20 discrete fixes, 21 commits, 0 build errors

| Commit | Finding | Domain | File(s) |
|--------|---------|--------|---------|
| `6623cd7` | COL-01 | Infra | AmenObjectHubViewModel.swift |
| `6d58e7b` | DS-A05→A11, UI-01/02/03, NOTES-01/02 | A11y/DS/UI | 39 files |
| `9c908dd` | MEDIA-04 | Media | AmenMediaSessionView.swift |
| `8f997e5` | STUDIO-08 | Studio | StudioAICreationView.swift |
| `9efdb72` | MEDIA-07 | Media | AmenMediaUploadFlowView.swift |
| `10b8c9d` | STUDIO-03 | Studio | StudioAICreationView.swift |
| `1c7e480` | AUTH-01 | Auth | OnboardingQuizView.swift |
| `eaa22df` | AUTH-08 | Auth | EmailVerificationGateView.swift |
| `1febfa6` | FEED-02, FEED-01/03 | HeyFeed | HeyFeedNLInputView.swift |
| `66ec354` | DS-A01 | Design | TipSheetView.swift |
| `582e6c9` | FEED-06, FEED-05 | HeyFeed | HeyFeedComposerView.swift |
| `e22b586` | HUB-01 | 242Hub | TwoFourTwoHub.swift |
| `26794f5` | STUDIO-19 | Studio | StudioAICreationView.swift |
| `3e0fc3a` | FEED-07, FEED-09 | HeyFeed | FeedIntelligenceService.swift |
| `b9f3be2` | BEREAN-12 | Berean AI | BereanLandingView.swift |
| `ee24292` | FEED-04 | HeyFeed | HeyFeedActiveRequestsView.swift |
| `2f9c826` | FEED-05 (pills) | HeyFeed | HeyFeedActivePillsBar.swift |
| `b3b707e` | FEED-09 (lazy) | HeyFeed | ActivityFeedView.swift |
| `d84b2e3` | FEED-11 | HeyFeed | HeyFeedService.swift |
| `1062310` | UI-PillNav | UI | AMENPillNav.swift |

---

## Detail

### COL-01 — `6623cd7`
`AmenObjectHubViewModel.loadMembership()` read from `_noop` Firestore collection in production builds. Wrapped in `#if DEBUG`.

### DS-A05 → DS-A11 + NOTES-01/02 + UI-01/02/03 — `6d58e7b`
Batch R24: 39 Swift files, ~90 instances of unguarded motion.
- `ComponentsSharedUIComponents`: 3 `.repeatForever` + 1 spring (highest vestibular impact)
- `BereanLandingView`: 11 nested structs, all spring calls guarded
- `TipSheetView`/`TipView`/`MovementWellnessView`/`FindChurchView`: 19 bare `withAnimation`
- 22 additional DS-A11 files: 41+ bare `withAnimation` calls
- `SelahScriptureReaderView`: 2 unguarded calls in `.pray`/`selectedVerseNumber` closures (NOTES-01/02)
- `SpacesDesignSystem` "See All" wired with optional callback + `.disabled(onSeeAll==nil)` (UI-01)
- `AmenSpacesDiscussionDiscoveryView` "View" button wired with optional callback (UI-02)
- `MessagingComponents` demo button marked `.disabled(true)` + `.accessibilityHidden(true)` (UI-03)

### MEDIA-04 — `9c908dd`
`AmenMediaSessionView` had `vm.isLoading` and `vm.error` declared in ViewModel but never shown in UI. Added `ProgressView` branch for loading and error banner branch for failures.

### STUDIO-08 — `8f997e5`
`StudioAICreationViewModel.generate()` had no rate limit. Added 3-calls-per-60s guard with `generateAttemptCount` + `generateLastResetDate` state. Shows `"Please wait a moment before generating again."` on excess.

### MEDIA-07 — `9efdb72`
`AmenMediaUploadFlowView.PublishStep` bypassed content preflight before publishing. Added `AmenContentPreflightService.shared.runFinalPreflight()` call matching the `CreatePostView:4182` pattern. Blocked posts show an error banner.

### STUDIO-03 — `10b8c9d`
No way to abort generation once started (`isGenerating=true`, no cancel). Added stored `generateTask: Task?`, `cancelGeneration()` method, and Cancel button in the progress overlay.

### AUTH-01 — `1c7e480`
`OnboardingQuizView` used `userId = Auth.auth().currentUser?.uid ?? "demo_user"` — unauthenticated users could write to Firestore under a hardcoded ID. Changed to `userId: String?` with a `guard let userId else { return }` in `saveToFirestore()`.

### AUTH-08 — `eaa22df`
`EmailVerificationGateView` showed blank when email was nil. Added `?? "your email address"` fallback.

### FEED-02 + FEED-01/03 — `1febfa6`
`HeyFeedNLInputView`: listener started in `.onAppear` with no `.onDisappear` cleanup (leak). Added `.onDisappear { nlService.stopListening() }`. Also guarded 2 `.animation(Motion.adaptive(...))` calls with `reduceMotion` ternary.

### DS-A01 — `66ec354`
`TipSheetView` had 5 `Color(hex:...)` literals. Replaced with `AmenTheme.Colors.amenPurple`, `amenPurple.opacity(0.65)`, `amenGold`, `amenBlack`.

### FEED-06 + FEED-05 — `582e6c9`
`HeyFeedComposerView`: listener started in `.task` with no `.onDisappear` cleanup (leak). Added cleanup. Also guarded 2 `withAnimation(Motion.adaptive(...))` calls.

### HUB-01 — `e22b586`
`TwoFourTwoHub` silently defaulted to `.free` tier if Firestore fetch failed. Added async `loadUserTier()` with `@State private var tierLoadError` and inline error banner.

### STUDIO-19 — `26794f5`
`StudioAICreationViewModel.generate()` called `studioGenerateContent` without checking entitlement. Added `guard !subscriptionService.requiresUpgrade(for: .create) else { ... }` at function entry.

### FEED-07 + FEED-09 — `3e0fc3a`
`FeedIntelligenceService` (a `@MainActor` service, not a View — `@Environment` unavailable): 4 `withAnimation(Motion.adaptive(...))` calls now gated on `UIAccessibility.isReduceMotionEnabled`. Also removed `lazy var` from a function-scoped Firestore instance.

### BEREAN-12 — `b9f3be2`
`BereanLandingView` rendered AI input controls without checking `AmenAIConsentStore`. Added consent check via `hasConsent(for: .bereanQuickAnswer)`. Shows consent banner and disables input bar + chips when consent is missing.

### FEED-04 — `ee24292`
`HeyFeedActiveRequestsView`: added `@Environment(\.accessibilityReduceMotion)` and guarded `withAnimation(Motion.adaptive(...))` in `filterPill()`.

### FEED-05 — `2f9c826`
`HeyFeedActivePillsBar`: added `reduceMotion` env var and guarded `.animation(Motion.adaptive(...), value:)`.

### FEED-09 — `b3b707e`
`ActivityFeedView`: removed spurious `lazy` keyword from function-scoped `let db = Firestore.firestore()`.

### FEED-11 — `d84b2e3`
`HeyFeedService.recordResonance()`: changed `setData(..., merge: false)` → `merge: true`. Comment said idempotent but implementation was destructive.

### UI-PillNav — `1062310`
`AMENPillNav`: `frame(maxWidth:.infinity)` caused tab buttons to spread across full device width. Changed to `frame(width:46)` per tab with `spacing: 0`, matching the `AMENTabBar` center-capsule fix.

---

## False Positives (findings confirmed already correct)

| Finding | Reason |
|---------|--------|
| FLAG-01 `debugForceAllEnabled` | Already in `#if DEBUG / #else` block |
| NAV-01 deprecated handler | Only appears inside a code comment; no live call sites |
| FEED-09 lazy var (FeedIntelligenceService) | Already fixed in same commit as FEED-07 |
| GroupChatCreationView DS-A11 entry | Entire struct body is commented out — dead code |
