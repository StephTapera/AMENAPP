# FINDINGS — Overnight Audit 2026-05-30

Format: `[DOMAIN-NN] Severity | File:Line | Description | Root cause | Proposed fix`

---

---
## Domain: Design System / Accessibility (Agent D — completed)

### DS-A01 | LOW | TipSheetView.swift:29-32
Hard-coded hex colors `Color(hex: "6B48FF")`, `Color(hex: "C084FC")`, `Color(hex: "F59E0B")`, `Color(hex: "0A0A0F")` bypass AMEN token system. Should use `amenPurple`, `amenGold`, `amenBlack`.

### DS-A02 | LOW | BereanLandingView.swift:14-22
Local `Color(red:...)` extension defines bereanBackground/bereanCard/etc. — should reference AmenTheme tokens rather than raw RGB values.

### DS-A03 | LOW | AMENResourcesHubView.swift:104,119,134
Hard-coded `Color(red: 0.52, green: 0.18, blue: 0.80)` etc. in accentColors array. No AMEN token mapping.

### DS-A04 | LOW | ResourcesView.swift:766,778,790
Hard-coded RGB in accentColor params. Semantic colors not centralized.

### DS-A05 | MEDIUM | ComponentsSharedUIComponents.swift:46,169,222
Three `.animation(.easeInOut(...).repeatForever(...))` calls with NO `@Environment(\.accessibilityReduceMotion)` guard. Repeating animations are the highest-impact category for users with vestibular disorders.

### DS-A06 | MEDIUM | BereanLandingView.swift:116,340,403,500,531,572,621,688,804,446,893
Has `@Environment(\.accessibilityReduceMotion) private var reduceMotion` at line 70 but ZERO of 11+ animation calls respect it.

### DS-A07 | MEDIUM | StarRatingRow.swift:60
`.animation(.spring(response: 0.3, dampingFraction: 0.6), value: rating)` — bare spring, no reduce-motion guard.

### DS-A08 | MEDIUM | MentorCardView.swift:142,157
Two bare spring `.animation()` calls, no reduce-motion guard.

### DS-A09 | MEDIUM | AmenTranslationComparisonCard.swift:181
`.animation(.easeInOut(duration: 0.2), value: selectedTranslation)` — bare, no guard.

### DS-A10 | MEDIUM | TipSheetView.swift (6 instances), TipView.swift (4), MovementWellnessView.swift (4), FindChurchView.swift (5)
`withAnimation {}` calls with no reduceMotion env var at all. 19 instances across 4 files.

### DS-A11 | MEDIUM | WellnessRiskLayer.swift:1266,1277 | VerseAttachmentViewModel.swift:282,297 | VergeCreatorStudioView.swift | VergeCreateRoomSheet.swift:272,295 | SmartChurchNotifications.swift:186,197 | SelahScriptureReaderView.swift | ProfilePhotoEditView.swift:447,495 | PersonalizedGreetingView.swift | GivingInAppSheet.swift:275,288 | EmailVerificationGateView.swift:190,205 | CrisisSupportCard.swift:292,296 | CarPlay/BereanDriveSetupView.swift | ChurchLiveModeView.swift:501 | ContactSearchView.swift | DisasterAlertCard.swift | BreathingExerciseView.swift:393 | BereanChurchNotesBridge.swift:337 | AmenSyncStudioView.swift:97 | GroupChatCreationView.swift:354 | LegacyStudioView.swift:317 | PrayerView.swift:1605 | SavedPostsQuickAccessButton.swift:82
Unguarded `withAnimation {}` calls — 41+ instances across 22 files. All need reduce-motion wrap.

---
## Domain: Feature Flags / Firestore / Navigation (Agent C — completed)

### FLAG-01 | MEDIUM | AMENAPP/ChurchAssistFeatureFlags.swift
`static var debugForceAllEnabled = true` — This is a DEBUG override that forces all ChurchAssist flags ON. If this ships to production in a non-debug build, it bypasses all ChurchAssist feature gates. Should be wrapped in `#if DEBUG`.

### FLAG-02 | LOW | AMENFeatureFlags.swift + multiple
Several flags (e.g. `spacesDNAGenerationEnabled`, `spacesEphemeralRoomsEnabled`, `spacesCompositionEnabled`) default `true` but appear checked in <5 files. Low usage risk — informational only.

### NAV-01 | MEDIUM | Onboarding/NotificationDeepLinkHandler.swift (or similar)
`NotificationDeepLinkHandler` is marked `@available(*, deprecated)` but is still referenced in multiple files. The `"didReceiveNotificationResponse"` notification it observes is never posted anywhere. Dead code risk: any code path relying on this handler silently no-ops.

### NAV-02 | LOW | AmenContextualExperienceDashboardView call sites
`AmenContextualExperienceDashboardView(organizationId: "")` — empty string parameter passed at navigation entry. Dashboard behavior with empty organizationId is undefined / likely no-op / stub. Should be guarded: `if !orgId.isEmpty { navigate }`.

### COL-01 | LOW | Client code (search: `"_noop"`)
`_noop` Firestore collection used for connection testing in client code. This reference should be gated by a `#if DEBUG` or removed; production builds should not make test writes.

### COL-02 | LOW | Various Firestore collection references
Mixed naming convention in collection paths: `daily_verses` and `user_trust` (snake_case) alongside `churchNotes` (camelCase) and `churches` (lowercase). Not a code defect (Firestore paths are frozen), but increases human-error risk in new callers. NOTE: frozen contract — logging only, no fix.

---
## Domain: Cloud Functions ↔ Client Contract (Agent B — completed)

### CF-01 | HIGH → REVIEW-QUEUE | Two-codebase architecture
**297 functions exported** in `functions/index.js`. **449 unique callable names** referenced from iOS. Only **71 match** — the remaining **378 iOS calls target functions that do NOT exist in this repo's `functions/index.js`**. These are served by a separate "Backend/functions TypeScript codebase" noted in comments throughout `index.js` (e.g. `// owned by Backend/functions TS codebase; removed from default to resolve two-codebase conflict`). 

This means: if the Backend TS codebase is deployed to the same Firebase project, the calls work fine. If it is NOT deployed, 378 callable invocations fail with `UNIMPLEMENTED`. **This requires human verification — cannot be fixed client-side.** → REVIEW-QUEUE

Critical missing functions include: `bereanChatProxy`, `bereanGenericProxy`, `processVideoProxy`, `generateThumbnail`, `acceptAccessPass`, `createAccessPass`, `askAmenCompanion`, `createMentorshipSubscription`, `checkCreatorSpaceEntitlement`, `createRealtimeSession` and 368 more.

### CF-02 | LOW | 226 exported functions with no iOS callers
226 exports in `functions/index.js` have no corresponding `httpsCallable(...)` invocation in the iOS codebase. Most are expected: Firestore/RTDB triggers (`onPostCreate`, `onUserFollow`, etc.), scheduled functions (`weeklyCheckin`, `communityDigest`), and functions called inter-CF. A subset may be truly dead exports that could be cleaned up — but this is a backend concern, not fixable client-side.

### CF-03 | MEDIUM → REVIEW-QUEUE | No error-state handling for UNIMPLEMENTED responses
iOS callers to the 378 "Backend/functions TS" callables have no special handling for `FunctionsErrorCode.internal` or `unimplemented` responses in the case where the TS backend is not deployed. Missing error paths could surface unhandled errors silently. Should add user-visible error handling at key call sites (especially `bereanChatProxy`, `acceptAccessPass`, `createAccessPass`). Marking REVIEW because this is architectural — confident in the fix direction but scope is large.

---
## Domain: Views / Interactive Controls (Agent A — completed)

### UI-01 | MEDIUM | AMENAPP/AMENAPP/Spaces/DesignSystem/SpacesDesignSystem.swift:434
"See All ›" button with no action handler (`Button { }`). Users can tap it but nothing happens — dead interaction.

### UI-02 | MEDIUM | AMENAPP/AMENAPP/Spaces/AmenSpacesDiscussionDiscoveryView.swift:115,680
Two `Button { }` instances with empty closures (header icon in search capsule + related feature). Silent dead buttons.

### UI-03 | LOW | MessagingComponents.swift
One `Button { }` instance — empty action. Low impact (likely a placeholder component).

### UI-04 | LOW | CreatePostPhase3.swift
`// TODO: Apply crop transform before dismissing` — crop apply is silently skipped; images are dismissed without transform. Low severity but user-visible data loss for crop edits.

### UI-05 | LOW | SafeConversationView.swift
`// TODO: Show user picker` — "add participant" or similar control has no action. Silent no-op.

### UI-06 | LOW | MediaPostComposerView.swift
`// TODO: wire to TranslateButton / TranslationService` — translation button visually present but disconnected.

### UI-07 | LOW | ShortFormTeachingFeedView.swift
Two TODO stubs: "Open Berean AI sheet contextualised with this clip" and "Present ShareSheet" — both buttons visible in UI, no-op on tap.

### UI-08 | LOW | BereanAIAssistantView.swift
Multiple TODO markers — buttons present with no handlers. Needs targeted audit.

---
## Domain: HeyFeed + Liturgical + Pastoral (Domain 2 — completed)

### FEED-01 | MEDIUM | HeyFeedNLInputView.swift:88-89
Two `.animation(Motion.adaptive(...))` calls do not check `accessibilityReduceMotion`. Add `reduceMotion` ternary guard.

### FEED-02 | HIGH | HeyFeedNLInputView.swift:94
`.onAppear` calls `nlService.startListening()` with no corresponding `.onDisappear { nlService.stopListening() }`. Listener leak when sheet is dismissed.

### FEED-03 | MEDIUM | HeyFeedActiveRequestsView.swift:88
`withAnimation(Motion.adaptive())` at line 88 without `accessibilityReduceMotion` guard. Fix: wrap with `reduceMotion` conditional.

### FEED-04 | MEDIUM | HeyFeedActivePillsBar.swift:42
`.animation(Motion.adaptive(...), value:)` without `reduceMotion` check.

### FEED-05 | MEDIUM | HeyFeedComposerView.swift:129,161,195,252
Four `withAnimation(Motion.adaptive(...))` calls without `accessibilityReduceMotion` guard.

### FEED-06 | HIGH | HeyFeedComposerView.swift:57
`.task` calls `service.startListening()` but no `.onDisappear { service.stopListening() }`. Listener leak on modal dismiss.

### FEED-07 | HIGH | FeedIntelligenceService.swift:422,469,475,481
Four `withAnimation(Motion.adaptive(...))` calls in `postScrolled()`, `injectReflectionPrompt()`, `dismissReflectionPrompt()`, `dismissPacingPrompt()` — none check `accessibilityReduceMotion`. NOTE: This is a service (non-View), so `@Environment` is unavailable — need to pass `reduceMotion` as a parameter or read via `UIAccessibility.isReduceMotionEnabled`.

### FEED-08 | LOW | HeyFeedService.swift:206
`limit(to: 200)` for resonance tracking — generous. Monitor for memory impact on long sessions.

### FEED-09 | MEDIUM | ActivityFeedView.swift:162
`lazy var db = Firestore.firestore()` declared inside `loadUserChurch()` async function. `lazy var` in function scope behaves unexpectedly — not a true lazy property. Move to class-level.

### FEED-10 | LOW | LiturgicalCalendar.swift
`composerPlaceholder()` has no feature flag gate. Verify if liturgical awareness is behind a flag elsewhere; add guard if needed.

### FEED-11 | MEDIUM | HeyFeedService.swift:316
`recordResonance()` calls `setData(..., merge: false)` but comment says "Idempotent write: use merge so re-submitting is safe." Should be `merge: true`.

### FEED-12 | LOW | HeyFeedService.swift:143-158
`startListening()` checks `listeners.isEmpty` but ensure all call sites call `stopListening()` first. Informational — no change needed if existing pattern is consistently followed.

---
## Domain: Church Notes (Domain 6 — completed)

### NOTES-01 | HIGH | SelahScriptureReaderView.swift:386
`withAnimation { activeMode = .pray }` — unguarded. File HAS `@Environment(\.accessibilityReduceMotion) reduceMotion` at line 149 but this closure doesn't use it.

### NOTES-02 | HIGH | SelahScriptureReaderView.swift:391
`withAnimation { selectedVerseNumber = nil }` — same issue, same file, same root cause.

### NOTES-03 | MEDIUM | BereanChurchNotesBridge.swift:337
`withAnimation(.easeInOut) { didSave = true }` — no `reduceMotion` guard.

**Verified OK:** Draft save (TC-01 fix confirmed), Selah loading states, listener cleanup in ChurchNotesService (deinit + stopListening), no force-unwraps, accessibility labels comprehensive.

---
## Domain: Comms OS + Push Notifications (Domain 10+11 — completed)

### PUSH-01 | MEDIUM | NotificationDeepLinkHandler.swift
Deprecated handler `@available(*, deprecated)` still referenced in `NotificationsView.swift` (via `LegacyNotificationDeepLinkHandler.shared.activeDeepLink`) and `NotificationQuickActions.swift`. The notification it observes is never posted — routing is silently no-opped. Should be fully removed and callers migrated to `NotificationDeepLinkRouter`.

**Verified OK:** 
- `UnifiedChatView.swift:960-961` — age-gate fix `88665b5` confirmed
- `BadgeCountManager.swift:615` — `stopListening()` fix `5793d38` confirmed
- `BereanConversationService` — listener swap-guard correct
- `GroupChatCreationView.swift:354` — withAnimation IS properly guarded (DS-A11 finding was incorrect for this file — removing from fix queue)
- Push notification router handles 10+ types with graceful fallback
- Badge sync protected by caching, debounce, lock pattern

---
## Domain: Auth & Onboarding (Domain 1 — completed)

### AUTH-01 | MEDIUM | OnboardingQuizView.swift:92
`userId` falls back to `"demo_user"` if `Auth.auth().currentUser` is nil during init. An unauthenticated user could trigger quiz-completion Firestore writes with a hardcoded ID. Fix: guard and early-return if `uid` is nil.

### AUTH-06 | HIGH → REVIEW-QUEUE | AuthenticationViewModel.swift:337-381
Deactivation check reads `userData["isDeactivated"]` client-side BEFORE calling `getIDTokenResult(forcingRefresh: true)`. A patched client can skip the server-side claim check entirely. Fix requires always calling `getIDTokenResult(forcingRefresh: true)` on every auth state change and checking custom claim `deactivated` — touches frozen auth contract → REVIEW-QUEUE.

### AUTH-07 | MEDIUM → REVIEW-QUEUE | MinimalAuthenticationView.swift:776-781
Age verification (DOB) collected but never validated before `handleAuthentication()` call. COPPA compliance gap — no 13+ check enforced. → REVIEW-QUEUE.

### AUTH-08 | LOW | EmailVerificationGateView.swift:45-49
If `Auth.auth().currentUser?.email` is nil, verification gate shows no email hint. Add fallback text.

**Verified OK:** App Check configuration, Apple/Google Sign-In nonce flows, 2FA implementation, auth state listener, email verification gate logic, ContentView routing.

---
## Domain: Berean AI (Domain 3 — completed)

### BEREAN-01 through BEREAN-08 | HIGH | BereanLandingView.swift (multiple nested components)
8 nested components (`BereanContinuityCard`, `BereanContinueCard`, `BereanActionCard`, `BereanInputBar` x3, `BereanInsightCard`) have bare `.animation(.spring(...), value:)` calls with no `@Environment(\.accessibilityReduceMotion)` guard. Lines: 116, 340, 403, 500, 531, 572, 621, 804. All being addressed by reduce-motion fix agents.

### BEREAN-12 | MEDIUM | BereanLandingView.swift (parent or AIBibleStudyView)
`BereanLandingView` renders AI-enabled UI without explicitly checking `AmenAIConsentStore`. While `BereanVoiceCompanionView:305` correctly gates consent, the landing view itself does not. Add consent check before enabling user input.

**Verified OK:** No hardcoded API keys anywhere; all AI routed through `bereanChatProxy`/`bereanGenericProxy` Cloud Functions. WebSocket streaming has exponential backoff (maxRetries=4). `addTurn()` force-unwrap fix `ffe02f7` confirmed. Voice consent gate confirmed (`BereanVoiceCompanionView:305`).

---
## Domain: Berean Notebooks / Studio (Domain 4 — completed)

### STUDIO-08 | HIGH | StudioAICreationView.swift:131-144
No retry count on `studioGenerateContent` calls — user can tap "Regenerate" indefinitely, risking quota exhaustion. Add `@State private var retryCount = 0`, cap at 3 failures per 60s.

### STUDIO-09 | MEDIUM → REVIEW-QUEUE | StudioWriteView.swift:800-853
Client passes `"system_override"` parameter to `studioGenerateContent` CF. If backend doesn't whitelist overrides, custom prompts could bypass content policies. → REVIEW-QUEUE.

### STUDIO-01 | MEDIUM | StudioAICreationView.swift:569-719
Error card shows generic message only — no retry guidance for specific error types (network vs quota vs service unavailable). Architectural change → REVIEW-QUEUE.

### STUDIO-03 | MEDIUM | StudioAICreationView.swift:703-719
No cancel button during AI generation (`isGenerating = true` but no way to abort). Add cancel button that sets `isGenerating = false` and cancels the Task.

### STUDIO-04 | MEDIUM → REVIEW-QUEUE | StudioDraft.swift
SwiftData-only draft persistence — no cloud backup. Device reset = data loss for all drafts. Backend architecture change → REVIEW-QUEUE.

### STUDIO-19 | MEDIUM | StudioAICreationView.swift, StudioWriteView.swift
No subscription entitlement check before calling `studioGenerateContent`. `EntitlementBanner` in `StudioHubView` gates entry, but not the CF call itself. Add guard in `generate()`.

### STUDIO-13 | LOW | StudioHubView.swift:118-139
`DarkGlassBlueprintCard`, `DarkGlassCollabCard`, `DarkGlassChallengeCard` have no navigation targets. Add feature flag gate or mark as coming soon.

**Verified OK:** No Pinecone keys on device. All embedding/Pinecone via server-side CF. Animations in StudioHubView/WriteView correctly guarded. Pinecone key security confirmed.

---
## Domain: ARISE/OUTPOUR + Anti-addiction (Domain 5 — completed)

### MEDIA-04 | HIGH | AmenMediaSessionView.swift:24-25
`@Published error` and `isLoading` declared in ViewModel but never surfaced in UI. Users see no error state if session fails to load.

### MEDIA-07 | HIGH | AmenMediaUploadFlowView.swift
Video upload flow does not call `AmenContentPreflightService.runFinalPreflight` before publish. `CreatePostView:4182` uses this pattern correctly — upload flow should match.

### MEDIA-08 | MEDIUM | MediaSessionCoordinator.swift:40-78
`mediaFiniteSessionsEnabled` flag checked at presentation but no behavioral enforcement if disabled via Remote Config. Backend should independently enforce session limits.

### MEDIA-09 | MEDIUM | AmenMediaSessionView.swift:76-82
Rapid-skip guard only active when `mediaDoomScrollGuardEnabled=true`. No hard fallback if flag disabled.

### MEDIA-01 | MEDIUM | ShortFormTeachingFeedView.swift:213
"Ask Berean" button action empty (TODO stub) — confirmed at line 213.

### MEDIA-02 | MEDIUM | ShortFormTeachingFeedView.swift:364
Share button action empty (TODO stub) — confirmed at line 364.

### MEDIA-03 | MEDIUM | MediaPostComposerView.swift:396
Translate chip wired to nothing (TODO stub) — confirmed at line 396.

**Verified OK:** Safety preflight guards (image/video/content) correctly integrated. Media session lifecycle (beginSession/endSession) correct in both fullscreen and Liquid Glass viewers. Most animations properly guarded.

---
## Domain: SmartLink + 242 Hub (Domain 12+9 — completed)

### SMART-01 | CRITICAL → REVIEW-QUEUE | AffiliateLinkBuilder.swift:19
Hardcoded Amazon Associates tag fallback `"amenapp-20"` in Swift source. Visible in compiled binary. Should fail loudly if plist key missing; tag rotation requires app update. → REVIEW-QUEUE.

### SMART-02 | MEDIUM → REVIEW-QUEUE | EnhancedLinkPreviewCard.swift
No affiliate disclosure UI in main feed preview cards. FTC requires "clear and conspicuous" disclosure before the user clicks. → REVIEW-QUEUE (legal/compliance decision).

### HUB-01 | LOW | TwoFourTwoHub.swift + TwoFourTwoSubscriptionView.swift
No loading/error states for tier fetch. Defaults silently to `.free` if Firestore fails.

### HUB-02 | INFO | functions/242hub.js
`reviewCovenantApp` and `matchKingdomCommerce` CF callables have no iOS callers. Features exist in UI (FeatureDetailSheet) but `dismiss()` is called instead of navigation. Phased rollout accepted, but should have explicit `isComingSoon: true` flags.

**Verified OK:** URL parsing uses safe optional chaining throughout. Tap attribution logged. Crisis detection in 242hub.js is comprehensive (keyword scan + AI review + FCM pastor alert + 988 protocol). Auth checks on all callable CFs. No Pinecone keys on device.

---
## Domain: FLAG/COL/NAV fixes (Fix agent a9d1b5461c9a9f6a7 — completed)

**FLAG-01:** `ChurchAssistFeatureFlags.debugForceAllEnabled` already correctly wrapped in `#if DEBUG` — no change needed. Finding was moot.

**COL-01:** `_noop` collection in `AmenObjectHubViewModel.swift:138-148` — fix applied: entire `loadMembership` body wrapped in `#if DEBUG`.

**NAV-01:** `NotificationDeepLinkHandler` deprecated calls found in `NotificationsView.swift:625` (inside a comment, not code) and `NotificationQuickActions.swift` (uses `LegacyNotificationDeepLinkHandler` — separate class). No active call sites to annotate.

<!-- Phase 1+2 agents still running -->
