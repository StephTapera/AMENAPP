Now I'll write the full report:

# AMEN Quality Audit Report — 2026-06-12

---

## P0 FINDINGS — IMMEDIATE ATTENTION REQUIRED

All ten P0 findings must be resolved before the next build wave ships to TestFlight or production. Sorted by effort (S before M before L).

---

### P0-01 — "We Miss You" Guilt Notification Violates Internal Tone Contract
**ID (merged):** A1-001 / A8-002
**Severity:** P0
**Location:** `functions/engagementNotifications.js:99`
**Evidence:** `title: 'We miss you', body: '${displayName}, your community is praying for you. Come back and share what God is doing.'` — the file `aiProactiveFeatures.js:260` explicitly bans "we miss you" and "come back" as manipulative re-engagement phrases. This is a direct internal-policy violation in the same codebase.
**User impact:** Users who have stepped away receive a guilt-framed notification that contradicts the app's stated non-manipulation promise and its own AI tone contract.
**Suggested fix:** Replace title with `"Your community is here"` and rewrite the body to surface specific content rather than the user's absence. Remove the `Come back` call to action.
**Effort:** S

---

### P0-02 — Onboarding CTA Crashes on iOS 17/18: Bare `.glassEffect()` Without Availability Guard
**ID:** A10-003
**Severity:** P0
**Location:** `AMENAPP/AMENOnboardingSystem.swift:230–233`
**Evidence:** `.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: ONB.ctaRadius, style: .continuous))` — no `#available(iOS 26, *)` guard. The canonical shims (`amenGlassEffect`, `amenInteractiveGlassEffect`) in `LiquidGlassModifiers.swift` exist for exactly this use case and are bypassed here.
**User impact:** All new users completing onboarding on iOS 17 or iOS 18 devices encounter a crash at the CTA button, blocking first-run entirely.
**Suggested fix:** Replace `.glassEffect(.regular.interactive(), in: shape)` with `.amenInteractiveGlassEffect(in: shape)`.
**Effort:** S

---

### P0-03 — Remote Config Setup Race on Cold Launch
**ID:** A11-001
**Severity:** P0
**Location:** `AMENAPP/AMENAPPApp.swift:118–120`
**Evidence:** `Task { Self.setupRemoteConfig() }` runs in `App.init()`. `setupRemoteConfig()` guards on `FirebaseApp.app() != nil`, which may not be true until `AppDelegate.didFinishLaunchingWithOptions` returns. On a fresh install the Task may bail silently, leaving all Remote Config feature gates (AI kill switches, safety flags) on compiled-in defaults for the entire first session.
**User impact:** On first cold launch post-install, Remote Config AI keys and feature flags may not be fetched, breaking any feature gate that requires a Remote Config value (including Berean constitutional pipeline enable flag).
**Suggested fix:** Move `setupRemoteConfig()` to `AppDelegate.didFinishLaunchingWithOptions` after `FirebaseApp.configure()`, or defer the call to a `.task` modifier in `WindowGroup` body where Firebase is guaranteed to be configured.
**Effort:** S

---

### P0-04 — Prayer-Content Memory Soft-Delete Only: User Data Persists After User-Initiated Delete
**ID:** A13-002
**Severity:** P0
**Location:** `functions/berean/memoryStore.ts:265–325`
**Evidence:** `deleteMemory()` sets `isDeleted: true` — it never calls `.delete()` on the document. The iOS info-sheet copy states "You can delete any entry at any time." Prayer-category entries remain in Firestore with full plaintext content field readable by admin-privileged processes. `deleteAllUserMemory()` at line 389 also only sets `isDeleted: true` in a batch update — confirmed at line 424.
**User impact:** Users who delete a prayer memory entry believe the content is gone; the full text remains at `users/{uid}/bereanMemory/{entryId}` indefinitely.
**Suggested fix:** Change `deleteMemory()` to `ref.delete()` rather than an update. Change `deleteAllUserMemory()` to batch-delete documents. Preserve audit-log writes but strip the `content` field from any prayer-category audit entry.
**Effort:** S

---

### P0-05 — Account Deletion Does Not Cascade to Berean AI-Derived Data Stores
**ID:** A13-001
**Severity:** P0
**Location:** `functions/accountDeletion.js:59–65` (USER_SUBCOLLECTIONS list) + `functions/bereanFunctions.js:1017–1070`
**Evidence:** `USER_SUBCOLLECTIONS` array does not include `bereanMemory`, `bereanPipelineTraces`, `bereanModelLogs`, or `bereanFeedback`. `memoryStore.deleteAllUserMemory()` exists and works as a callable but is never invoked from either server-side deletion path.
**User impact:** A user who deletes their account retains all AI-inferred spiritual memory (prayer topics, beliefs, study preferences), pipeline trace records, model call logs, and feedback text — the GDPR right-to-erasure promise is broken.
**Suggested fix:** In `processAccountDeletion` (or `bereanFunctions.deleteAccount`), after Pinecone cleanup, call `deleteAllUserMemory(uid, db)` and batch-delete `bereanPipelineTraces` (where `userId==uid`), `bereanFeedback` (where `userId==uid`), and associated `bereanModelLogs`.
**Effort:** M

---

### P0-06 — Constitutional Pipeline Falls Back to Unreviewed Legacy Path on Any Error
**ID:** A6-001
**Severity:** P0
**Location:** `functions/berean/constitutionalPipeline.ts:309–318`
**Evidence:** `if (flags["constitutionalPipeline"] !== true) { return legacyPipelineCall(input, db); }` and in the catch block: `return legacyPipelineCall(input, db)`. The legacy path comment reads "Legacy path — constitutional review not applied." Any Firestore flag-read failure (network error, cold-start timeout, permission error) silently routes all queries — including crisis queries — through zero constitutional checks.
**User impact:** A user sending a crisis query ("I don't want to live anymore") while the flag document is temporarily unavailable receives a raw unchecked LLM response with no crisis resource injection and no safety gates.
**Suggested fix:** Replace the catch-block `legacyPipelineCall` with `return errorPipelineOutput(trace, "Flag read failed — cannot proceed safely.")`. Accept that the pipeline returns a safe error message rather than an unreviewed response.
**Effort:** S

---

### P0-07 — Prayer Posts With Restricted Visibility Indexed as `isPublic: true` in Algolia
**ID:** A9-001
**Severity:** P0
**Location:** `AMENAPP/CreatePostView.swift:4748`
**Evidence:** `"isPublic": true` is hardcoded in `syncPostToAlgolia(_:)` regardless of `post.visibility` or `post.category`. Called unconditionally at line 4614 for every post including `.prayer` category with `.followers` or `.community` visibility.
**User impact:** A user who posts a followers-only prayer request has their full prayer text indexed as public in Algolia and discoverable by any caller with Algolia read access.
**Suggested fix:** Pass `isPublic: post.visibility == .everyone && post.category != .prayer` in the sync helper. Skip Algolia sync entirely for `.followers` and `.community` visibility posts.
**Effort:** S

---

### P0-08 — DM Video Attachments Have Zero Content Moderation Coverage
**ID:** A12-001
**Severity:** P0
**Location:** `AMENAPP/VideoAttachmentHandler.swift:141–173` + `functions/imageModeration.js:55`
**Evidence:** `VideoAttachmentHandler` uploads to `chat_videos/{conversationId}/` with `contentType: "video/mp4"`. The `moderateUploadedImage` Storage trigger at line 55 of imageModeration.js exits immediately: `if (!contentType || !contentType.startsWith("image/")) { return null; }`. No separate video moderation trigger exists for the `chat_videos/` path.
**User impact:** A user can send a video in a DM that bypasses all CSAM/NCMEC reporting pipelines, including to minor recipients.
**Suggested fix:** Add an `onObjectFinalized` trigger for `chat_videos/**` that performs frame-extraction and Cloud Vision scanning (or routes to the existing video pipeline in moderateUGC.js) with fail-closed behavior that blocks the Firestore message document if screening errors.
**Effort:** M

---

### P0-09 — SSO (Google/Apple) Sign-In Bypasses Date-of-Birth Collection Gate
**ID:** A12-002
**Severity:** P0
**Location:** `AMENAPP/SignInView.swift:1132–1178` (handleGoogleSignIn), `AMENAPP/AMENAccountTypeOnboardingView.swift:1–631`
**Evidence:** `handleGoogleSignIn()` sets `viewModel.isAuthenticated = true` and `viewModel.needsOnboarding = true` without triggering `showDOBCollection = true`. The DOB gate at line 730 is only reached in the email/password sign-up path. `AMENAccountTypeOnboardingView.vm.confirm()` writes only `accountType` and `accountTypeOnboardingComplete` — no `birthYear` write and no age gate.
**User impact:** A child under 13 completing sign-up via Apple or Google SSO bypasses the COPPA DOB gate and can access messaging, AI chat, and media posting. If `birthYear` is absent, `ageTier` defaults to absent rather than `blocked`.
**Suggested fix:** Enforce DOB collection as a mandatory gate on ALL sign-in paths (including SSO) before the account becomes usable. Block app access until `ageTier` is written by the server and is not `blocked`.
**Effort:** M

---

### P0-10 — Bulk Algolia Post Backfill Has No Privacy Filter
**ID:** A9-002
**Severity:** P0
**Location:** `AMENAPP/AlgoliaSyncService.swift:311–313`
**Evidence:** `bulkSyncPosts` queries `db.collection("posts").limit(to: limit).getDocuments()` with no visibility or category filter. All prayer posts and restricted-visibility posts in Firestore are bulk-indexed to the third-party Algolia index.
**User impact:** Historical followers-only prayer requests are discoverable via Algolia search by unauthenticated callers who obtain the read API key.
**Suggested fix:** Add `.whereField("visibility", isEqualTo: "Everyone")` to the Firestore query, and additionally exclude `category == "prayer"` from bulk sync.
**Effort:** S

---

## Executive Summary

**Total deduplicated findings:** 10 P0 | 37 P1 | 33 P2 | 19 P3 | 18 RG = **117 total** (13 raw findings discarded as evidence-free or merged)

**Top themes by frequency:**
1. **Child safety / COPPA gaps** (P0-07 through P0-10, A5-002, A12-001 through A12-009): SSO DOB bypass, video DM moderation absence, prayer room age-interaction gap, and Apple Communication Safety API absent. These are the most severe cluster.
2. **AI data retention / GDPR erasure** (P0-05, P0-04, A13-001 through A13-007): Berean memory soft-delete, account deletion cascade missing AI stores, HuggingFace undisclosed processor.
3. **Design system fragmentation** (A2-007, A7-005, A10-001 through A10-007): 904 Color(hex:) usages bypassing adaptive color, 7 forked glass container implementations, 245 hardcoded corner radii.
4. **Accessibility regressions** (A2-002, A2-006, A2-021, A3-001 through A3-014): Infinite shimmer animations without reduce-motion guard, 201 hardcoded font sizes blocking Dynamic Type, sub-44pt touch targets throughout.
5. **Manipulation / engagement ethics** (P0-01, A1-002 through A1-010, A8-008): "We miss you" notification, streak displays on spiritual content, badge count inflation.

**Go/no-go signal:** **NO-GO** for TestFlight or App Store submission. P0-02 (onboarding crash on iOS 17/18) blocks all users on prior OS versions from completing onboarding. P0-07 through P0-10 constitute App Store rule 5.1.1 (privacy) and COPPA violations that would trigger rejection or regulatory action. P0-06 (constitutional pipeline bypass) means a safety-critical AI path can fail open on any cold-start error. All ten P0s must be resolved and verified before the next build wave is distributed.

---

## P1 Findings

| ID | Location | Violation | Effort | Suggested Fix |
|----|----------|-----------|--------|---------------|
| A1-002 | `functions/messages_features.js:257–272` | Streak silently reset to 0 after one missed weekly check-in; no grace period, no opt-out | M | Add a one-week grace period (set to -1/"grace" state before 0); never include numeric streak in notification copy |
| A1-003 | `AMENAPP/AMENAPP/HealthyModeService.swift:157–158` | `autoplayEnabled = true` and `infiniteScrollEnabled = true` are the default on-state; Healthy Mode is opt-in so the vast majority of users experience engagement-maximizing defaults | M | Invert default: start with `infiniteScrollEnabled = false`; require explicit opt-out rather than opt-in for protections |
| A2-001 | `AMENAPP/AMENAPP/BereanConversationView.swift:410–415` | 6 AI response-type colors hardcoded as `Color(red:)` with zero dark-mode adaptation | M | Promote to `AmenTheme.Colors.bereanScripture` etc. using `UIColor { traitCollection in }` adaptive definitions |
| A2-003 | `AMENAPP/AMENAPP/BereanConversationView.swift:100, 290, 505` | Hardcoded `.foregroundColor(.black)` on glass background; invisible in dark mode | S | Replace with `AmenTheme.Colors.textPrimary` |
| A2-004 | `AmenActionTray.swift:254–259`, `StewardshipDashboardView.swift:513–516` | `amenSnappy` animation token duplicated in two private extensions instead of living in the global `Motion` enum; drift risk | S | Add `amenSnappy` as a public static on `Motion` enum in `AMENAPP/Motion.swift`; delete both private extensions |
| A2-005 | `AMENAPP/AMENAPP/AmenSafetyOSReactionEngine.swift:982` | 1.2-second ease animation in `PeaceCheckPrompt` without `accessibilityReduceMotion` guard — fires at an emotionally sensitive safety moment | S | Pass `reduceMotion: Bool` into `PeaceCheckPrompt`; wrap: `withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.2))` |
| A2-006 | `AMENAPP/AMENAPP/BereanVoiceView.swift:251, 261` | Infinite 4.5-second breathing orb animation bypasses the existing reduce-motion guard — guard only applies to tap-spring at line 130 | S | Change to `withAnimation(reduceMotion ? nil : .easeInOut(duration: 4.5).repeatForever…, value: orbBreath)` |
| A2-008 | `AMENAPP/AMENAPP/ConnectSpaces/AmenSpaceDetailView.swift:79, 103, 137, 191, 394–547` | Hardcoded `.foregroundStyle(.white)` on 11 text labels; no high-contrast adaptation | S | Replace with `AmenTheme.Colors.textInverse` |
| A2-009 | `AMENAPP/AMENAPP/FeedCardViews.swift:31, 36, 202, 208, 308, 353, 359, 766, 772` | 9 feed animation calls bypass `Motion.adaptive`; fire as easing animations for Reduce Motion users on the most-used surface | M | Replace with `withAnimation(Motion.adaptive(Motion.springPress))` / `springRelease` |
| A2-010 | `Giving/Views/` — 7 files | Entire Giving module bypasses `Motion.adaptive`; no reduce-motion handling in the financial/donation flow | M | Route all Giving module animations through `Motion.adaptive(…)` |
| A2-011 | `ConnectSpaces/Monetization/AmenStripeOnboardingService.swift:76–77` | `UIColor(red:)` hardcoded navigation bar color in UIKit layer; no trait-collection adaptation | S | Replace with `UIColor { traits in … }` adaptive initializer |
| A2-013 | `AMENAPP/AMENAPP/PinnedPostGlassSystem.swift:567–579` | Hand-rolled glass shell with hardcoded `.white.opacity(0.68)` instead of `GlassMaterial.glassSurface(cornerRadius:)` | M | Replace `shellBackground` with `.glassSurface(cornerRadius: 28)` |
| A3-001 | `AMENAPP/AMENAPP/HomeView.swift:897–1012` | Primary Berean AI entry point (`SearchButton`) has no `.accessibilityLabel`; VoiceOver reads asset name | S | Add `.accessibilityLabel("Open Berean AI").accessibilityHint("Long press for quick actions").accessibilityAddTraits(.isButton)` |
| A3-002 | `AMENAPP/AMENAPP/HomeView.swift:760–782` | Feed mode toggle button (icon-only) has no `.accessibilityLabel`; VoiceOver reads raw SF Symbol name | S | Add `.accessibilityLabel("Feed mode: \(selectedMode.rawValue), tap to change")` |
| A3-003 | `AMENAPP/AMENAPP/HolidayReflectionSheet.swift:29–234` | 14 `.font(.custom(…, size: N))` calls with no `.relativeTo:` scaling; text does not grow at accessibility sizes | M | Replace with `.font(.custom("OpenSans-Regular", size: 17, relativeTo: .body))` pattern for each style |
| A3-005 | `AMENAPP/AMENAPP/CreatePostMediaViews.swift:46–60` | "Remove photo" button touch target is 28×28pt (HIG minimum: 44×44pt) | S | Add `.frame(minWidth: 44, minHeight: 44).contentShape(Circle())` on the button |
| A3-006 | `AMENAPP/AMENAPP/CreatePostMediaViews.swift:172–183` | "Remove photo" button on single-image composer is 30×30pt; `.padding(8)` is applied to overlay ZStack, not the button's hit region | S | Move `.padding(8)` inside the button label or add `.frame(minWidth: 44, minHeight: 44).contentShape(Circle())` directly on Button |
| A4-001 | `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantRoomDetailView.swift:211–212` | Covenant Room message deletion fires immediately from context menu with no confirmation dialog | S | Add `@State private var showDeleteConfirm = false` and `.confirmationDialog` before calling `onDelete()` |
| A4-002 | `AMENAPP/PostDetailView.swift:1625–1629, 1647–1651` | Comment and reply deletion in PostDetailView context menus fire immediately — unlike everywhere else in the app | S | Route through `@State private var pendingDeleteComment` + `.confirmationDialog` |
| A4-003 | `AMENAPP/CreatePostView.swift:5267–5288` | `autoSaveDraft()` only saves text/category/tag/linkURL; poll state, attached images, scripture attachment, visibility, and comment permissions are silently lost on backgrounding | M | Delegate full state to `CreatePostDraftStore` on every meaningful change, or add images/poll/visibility fields to the UserDefaults snapshot |
| A5-001 | `AMENAPP/AppDelegate.swift:184–188` | ATT prompt fires 1 second after cold launch with a generic usage description before the user has any context | S | Show an in-app "Why we ask" pre-prompt before `requestTrackingAuthorization`; defer the OS dialog until after onboarding completion |
| A5-002 | `CommunityOS/Prayer/PrayerRoomView.swift` + `functions/moderateUGC.js:368–430` | `moderatePrayerRequest` runs content moderation but does NOT call `checkAdultMinorInteraction`; `detectGroomingRisk` is absent from the prayer request flow — only DMs are covered | M | Add `checkAdultMinorInteraction(db, authorId, prayerOwnerId, "reply")` at top of `moderatePrayerRequest`; wire `detectGroomingRisk` to the prayer collection |
| A5-003 | `AMENAPP/PrivacyInfo.xcprivacy` | `NSPrivacyAccessedAPITypes` declares only 4 categories; CoreLocation, Camera, Microphone, Speech, MediaLibrary, HealthKit, Contacts are all used but undeclared | S | Add all missing required-reason API category entries to `NSPrivacyAccessedAPITypes` |
| A6-002 | `AMENAPP/AMENAPP/AIIntelligence/BereanMemoryView.swift:95, 113, 125, 160` | iOS client passes `userId` in callable data payload; backend correctly ignores it, but the pattern is a latent IDOR risk that could corrupt any future callable that does not discard `data.userId` | S | Remove `userId` from all client callable payloads; add code comment that backend derives uid from `request.auth.uid` exclusively |
| A6-003 | `AMENAPP/AIIntelligence/BereanSelectionOverlay.swift:55–84` | High-impact context actions (`.createPost`, `.saveToChurchNotes`, `.createCarousel`, `.turnIntoSermonOutline`) have no Approve/Reject confirmation step | M | Wire `AmenAIReviewActionsView` into `BereanContextResultSheet` for all `highImpactActions`; require `state == .approved` before dismissing |
| A6-004 | `AMENAPP/AIIntelligence/` — all Berean UI surfaces | No persistent UI-level disclaimer stating that Berean is a study companion, not pastoral authority or professional counseling | S | Add one-line disclaimer to `BereanContextResultSheet` and `BereanResponseFooter` below the TrustBadgeRow |
| A7-001 | `AMENAPP/AMENAPP/SpiritualOS/Hub/AmenHubSectionView.swift:318` | `heart.fill` used as "pin" icon on Hub — same symbol means "pray" in the swipe gesture on the same screen; dual semantics | S | Replace with `pin` / `pin.fill` SF Symbol; update `accessibilityLabel` to "Pin" / "Unpin" |
| A7-002 | `AMENAPP/AMENAPP/AMENAPP/ObjectHub/AmenMentorChannelView.swift:679` | `bookmark.fill` used for "Follow Journey" — bookmark means save-for-later at 20+ other callsites in the app | S | Replace with `person.badge.plus` / `person.badge.minus` |
| A7-003 | `AMENAPP/AMENAPP/AMENAPP/Pulse/PulsePrefsView.swift:110` | `heart.fill` used as icon for "Following" feed-source toggle — conflicts with like/prayer metaphor | S | Replace with `person.2.fill` |
| A7-004 | `AMENAPP/AMENAPP/CommunityOS/HeroExperience/AmenCollapsibleHeroContainer.swift:582` | Preview block uses `star` as Follow icon, establishing a wrong pattern template | S | Change preview to `person.badge.plus`; add code comment blocking `star` as follow icon |
| A8-001 | `AMENAPP/AMENAPP/PostCard.swift:1455–1459` | Primary Share action only accessible through ellipsis overflow menu; never shown in the visible action bar | S | Add `square.and.arrow.up` share button to the `interactionButtons` HStack alongside Amen/Comment/Repost |
| A9-003 | `AMENAPP/AMENAppIntents.swift:234–240` | `PostPrayerRequestIntent.perform()` posts `amen.openPrayerComposer` notification with no observer registered anywhere in the codebase; prayer text is silently lost | S | Add `.onReceive(NotificationCenter.default.publisher(for: .amenOpenPrayerComposer))` observer in ContentView; pre-populate composer and clear UserDefaults key |
| A9-004 | `AMENAPP/AMENAppIntents.swift:253–258` | `ShareTestimonyIntent.perform()` has same dead-notification pattern; testimony dictated via Siri is silently dropped | S | Mirror fix for A9-003: add observer for `.amenOpenTestimonyComposer` in ContentView |
| A10-001 | `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassMaterial.swift:1–55` | Core `LiquidGlassMaterial` modifier has no `@Environment(\.accessibilityReduceTransparency)` read; unconditionally applies translucent materials for all users | S | Add `@Environment(\.accessibilityReduceTransparency)` and branch to `Color(.systemBackground).opacity(0.97)` when true |
| A10-002 | `LiquidGlassCard.swift:1–29`, `LiquidGlassComposerBar.swift:88–97` | Both high-usage components inherit the RT gap from `LiquidGlassMaterial`; global composer bar has no opaque fallback | S | Propagate the RT guard from `LivingEntryLiquidGlassCard` into both components |
| A11-002 | `AMENAPP/AIIntelligence/BereanRealtimeWebSocketTransport.swift:151–181` | Entire `@MainActor` class parses JSON and mutates `@Published` array on every WebSocket frame during streaming voice sessions; continuous main-thread pressure | M | Decode JSON on a background actor; push only complete turn events to `@MainActor`; decouple `receivedEvents` from SwiftUI observation |
| A12-003 | `AMENAPP/MessageSettingsService.swift:310` | `checkIfMinor()` compares `ageTier` against `"13-17"` and `"under13"` — neither string exists in the canonical vocabulary (`blocked/tierB/tierC/tierD`); always returns `false`; minor messaging restrictions are silently bypassed | S | Replace literal comparison with `AgeCategory.resolving(ageTier).isMinor` |
| A12-004 | `AMENAPP/MinorSafetyGate.swift:21–30` | `BereanAgeGateService` reads client-supplied `birthYear` field from the public user document rather than the server-authoritative `ageTier`; under-13 users can self-alter `birthYear` to bypass the Berean AI COPPA block | S | Replace `birthYear` read with `AmenChildSafetyService.shared.checkIsMinor(userId:)` which reads the server-authoritative `ageTier` |

---

## P2 Findings

| ID | Location | Violation | Effort | Suggested Fix |
|----|----------|-----------|--------|---------------|
| A1-004 | `AMENAPP/AMENAPP/WalkWithChristFeatures.swift:1103–1106` | Consecutive-day streak count displayed on every commitment plan row; no opt-in gate | S | Rename to "days active"; add `isFormationTrackingOptedIn` guard; remove count from default row |
| A1-005 | `SmartActivityCopyGenerator.swift:98–99` | Third-party `activeStreak` count assembled into social activity copy; latent display path | S | Remove `activeStreak` fragment from `makeSubtext`; third-party streak data should never appear in social copy |
| A1-006 | `functions/aiModeration.js:822` | `badge: 1` hardcoded in APNS payload on every notification dispatch regardless of actual unread count | S | Replace with actual unread count or omit badge key; manage badge state from client on open |
| A1-007 | `functions/bereanFeaturesFunctions.js:55` | Same `badge: 1` inflation in Berean notification helper; always sets icon badge to 1 | S | Remove `badge: 1` from Berean push helper |
| A1-008 | `AmenMentorChannelView.swift:729` | Follower count ("mentees") displayed as a vanity stat on mentor channel profiles; violates "no popularity ranks shown" directive in `Catalog/FollowKnowledgeView.swift:6` | S | Remove `followerCount` cell from the stats row |
| A2-012 | `LiquidGlassHeader.swift:195, 209, 223` | Hardcoded `Color(red: 0.971…)` near-white in preview backgrounds; engineers see wrong surface color in dark mode, masking glass contrast issues | S | Replace with `AmenTheme.Colors.backgroundPrimary.ignoresSafeArea()` |
| A2-014 | `AMENAPP/AMENAPP/AMENAPP/Pulse/PulseHeroStyle.swift:30–86` | 25 `Color(hex:)` literals in a quasi-token enum; all fixed appearance, no dark adaptation | M | Migrate to `UIColor { traitCollection in }` adaptive colors or derive dark variants |
| A2-015 | `AMENAPP/AMENAPP/BereanPulseCard.swift:61` | Raw spring animation on Berean pulse card expand/collapse without reduce-motion guard | S | Wrap with `Motion.adaptive(…)` |
| A2-016 | `AMENAPP/AMENAPP/PinnedPostGlassSystem.swift:483, 531, 622, 632` | 4 raw spring calls on primary feed interaction (lightbulb toggle, card drag) without reduce-motion wrapping | S | Replace with `Motion.adaptive(.spring(…))` |
| A2-017 | `Intelligence/IntelligenceCardView.swift:148` | Hand-rolled `.blur(radius: 4)` for content-sensitivity blur; does not check `accessibilityReduceTransparency` | M | Use `AILEmotionalSafetyFilter` or a `contentBlurRadius` property that respects `accessibilityReduceTransparency` |
| A2-019 | `ObjectHub/AmenObjectHubHeader.swift:87` | 36px blur radius with no reduce-transparency guard; heavy GPU cost on older devices | S | Guard with `@Environment(\.accessibilityReduceTransparency)` and replace with solid color fallback |
| A2-020 | `AMENAPP/AMENAPP/WalkWithChristFeatures.swift:128, 811` | 2 raw spring calls on WalkWithChrist interaction without reduce-motion guard | S | Route through `Motion.adaptive` |
| A3-007 | `PinnedProfileHeroSurface.swift:124–137` | Ellipsis overflow button on pinned profile hero surface (34×34pt glass circle) has no `accessibilityLabel` | S | Add `.accessibilityLabel("Pinned post options")` |
| A3-008 | `MediaDetailView.swift:108–117` | Dismiss button labeled "Close" rendered at 32×32pt; below HIG 44×44pt minimum | S | Add `.frame(minWidth: 44, minHeight: 44).contentShape(Circle())` |
| A3-009 | `GetReadyView.swift:191–203` | Close button 30×30pt on Sunday Morning Prep modal | S | Add `.frame(minWidth: 44, minHeight: 44).contentShape(Circle())` or `.padding(7)` |
| A3-010 | `AmenMediaSessionView.swift:321–333` | Session dismiss button 36×36pt; glass effect wraps icon frame, not the Button hit area | S | Add `.frame(minWidth: 44, minHeight: 44).contentShape(Circle())` |
| A3-011 | `WalkWithChristFeatures.swift:756–762` | Close button in FaithCommitmentSheet is 30×30pt with no `accessibilityLabel` | S | Add `.accessibilityLabel("Dismiss").frame(minWidth: 44, minHeight: 44).contentShape(Circle())` |
| A3-012 | `ChurchNoteSemanticEditorView.swift:941–979` | Three toolbar action buttons (callout add actions) are 36×36pt; frequent note-taking context makes precision harder | S | Add `.frame(minWidth: 44, minHeight: 44).contentShape(Circle())` on each |
| A3-013 | `ScriptureImmersionView.swift:110` | Primary scripture body text uses `.font(.custom("Georgia", size: 16))` with no scaling | S | Replace with `.font(.custom("Georgia", size: 16, relativeTo: .body))` |
| A3-014 | `HomeView.swift:1339–1350` | "Join community" capsule button approximately 29–32pt height due to `.padding(.vertical, 6)` | S | Change to `.padding(.vertical, 12)` or wrap in `.frame(minHeight: 44)` |
| A4-004 | `AMENAPP/CreatePostView.swift:783` | "Discard Post" confirmation dialog has blank title string with `titleVisibility: .hidden` | S | Change to `titleVisibility: .visible` with title `"Discard this post?"` |
| A4-005 | `AMENAPP/UnifiedChatView.swift:4306–4328` | "Decline" message request permanently deletes the conversation with no confirmation; unlike "Block" which has a `confirmationDialog` | S | Add `.confirmationDialog` or `.alert` before `declineMessageRequest()` |
| A5-004 | `AMENAPP/AMENAPP/BereanVoiceView.swift:134` | Speech recognition + microphone permissions requested on view appearance before user taps mic | S | Move `speechService.requestPermissions()` into the microphone button's tap handler |
| A5-005 | `BereanPulsePermissionManager.swift:88–109` | Contacts permission grants access to all contact fields; only phone numbers are needed for hashing | S | Use `CNContactFetchRequest(keysToFetch: [CNContactPhoneNumbersKey])` and update usage description |
| A5-006 | `IntegrationOS/Health/HealthProviderAdapter.swift:23` | PrivacyInfo declares `NSPrivacyCollectedDataTypeHealth` and `NSPrivacyCollectedDataTypeFitness` while usage description says "No health data is stored" — conflicting signals | S | Remove health/fitness from `NSPrivacyCollectedDataTypes` if truly not stored, or add `PurposePersonalization` and remove the "not stored" claim |
| A5-007 | `BereanCommunicationHubView.swift:280` + `WalkWithChristFeatures.swift:680` | Notification permission request inside `scheduleLocalReminder()` silences errors via `try?`; usage description scope is too narrow (only church services, not messaging/follow-through uses) | S | Update `NSUserNotificationsUsageDescription` to cover all uses; show in-app explanation before OS prompt |
| A6-005 | `functions/berean/constitutionalPipeline.ts:651–678` | Non-high-risk queries that fail ALL 3 constitutional checks still receive a "degraded" response, giving false legitimacy to constitutionally-failed output | M | Apply hard gate to any query where all constitutional checks fail regardless of `isHighRisk` classification |
| A6-006 | `AMENAPP/AIIntelligence/BereanConstitutionalIntelligence.swift:216–218` | Medical guardrail check blocks the action with a developer-facing error message rather than auto-applying the guardrail; users see "could not process" for mental-health queries | S | Auto-apply the medical guardrail inside `BereanConstitutionalReviewGate.review()` when medical keywords are detected |
| A6-007 | `BereanConstitutionalIntelligence.swift:221–276` | Medical check in `reviewStudyCall` is advisory only ("consider adding") while the main `review()` path blocks; inconsistency allows medical-topic study queries through without disclaimer | S | Make `reviewStudyCall` medical check blocking (or auto-append guardrailNote) to match `review()` |
| A6-008 | `AMENAPP/AIIntelligence/AmenSafetyModerationProvider.swift:170–178` | `textModerationEnabled` kill-switch reads from client-writable UserDefaults; a user can disable all content moderation locally | M | Replace UserDefaults read with a RemoteConfig or Firestore server-authoritative flag |
| A7-005 | `LiquidGlass/` — 7 files | Seven forked glass container implementations with incompatible blur/fill/shadow parameters instead of a single design-token-backed component | L | Consolidate to `AmenGlassCard` wrapping canonical `livingGlassMaterial`; deprecate six variants with migration warning |
| A7-006 | `AmenHeroCard.swift`, `AmenUniversalHeroCard.swift`, `AmenProgressiveHeroView.swift` | Three hero card types produce three different tap outcomes (push, expand-in-place, full-screen overlay) from the same gesture | M | Document in `AmenHeroCardVariant` enum; add `accessibilityHint` to differentiate for VoiceOver users |
| A7-008 | `AmenFeedContextLabelSystem.swift:58` | `bookmark` icon used for "Gentle Follow-Up" system-generated label; users may believe they saved the post | S | Replace with `clock.arrow.circlepath` or `bell` to distinguish system nudges from user saves |
| A8-004 | `ConnectSpaces/AmenConnectPreferencesView.swift:504` | "Clear Image Cache" / "Cache Cleared" — developer jargon in user-facing Settings | S | Replace with "Free up photo storage" / "Photo storage freed" |
| A8-005 | `ScriptureGraphExplorerView.swift:217, 226` | "hermeneutical traditions" (unexplained jargon) and "X edges" (graph database term) in user-facing UI | S | Rewrite: "time-honored Bible study traditions" and "X connections" |
| A8-006 | `ConnectSpaces/Connect/AmenConnectContextBeforeWatchingView.swift:110` | "exegesis of the original text" — unexplained academic jargon in a pre-watch context card visible to all users including new believers | S | Replace with "a close reading of the original Bible text" |
| A8-010 | `AMENAPP/AMENAPP/AmenMediaDetailView.swift:562–598` | Post media player (AmenVideoPlayerSurface) has no time-remaining or duration indicator; users cannot make time-investment decisions | M | Add time overlay (currentTime / duration) matching `AmenConnectGlassControlsView` pattern |
| A9-005 | `AMENAPP/AMENAppIntents.swift:14–75` | Five core intents ignore the user's "Disable Siri Integration" preference setting while the v2 intents correctly gate on it | S | Add `guard await siriEnabled() else { return .result(dialog: siriDisabledDialog) }` to all five ungated intents |
| A9-007 | `AMENAPP/Info.plist:54–57` | `NSUserActivityTypes` array does not include `app.amen.selah.read.scripture`; Selah Handoff is entirely dead in production | S | Add `app.amen.selah.read.scripture` to `NSUserActivityTypes`; confirm Handoff capability enabled |
| A9-008 | `AMENAPP/Info.plist` (absent) | `NSSiriUsageDescription` key is absent; App Store submission requires it when the Siri entitlement is present | S | Add `<key>NSSiriUsageDescription</key>` with an appropriate purpose string |
| A10-004 | `SuggestedAccountCard.swift:312–334`, `SuggestedForYouModule.swift:415–434` | Social discovery cards use `.ultraThinMaterial` + `Color.white.opacity(0.62)` with no RT fallback | S | Add `@Environment(\.accessibilityReduceTransparency)` opaque fallback in both `glassBackground` computed properties |
| A10-005 | `AMENAPP/AMENProfileAdaptiveModules.swift:16–60` | `ProfileGlassCard` and `GlassCapsule` unconditionally apply `.ultraThinMaterial` + `Color.white.opacity(0.55)` over user-uploaded cover photos; no RT pathway | S | Inject RT environment and switch to `.regularMaterial` or `Color(.systemBackground)` when enabled |
| A10-006 | Distributed across 90+ files | 245 hardcoded `cornerRadius(N)` values; `LiquidGlassTokens` defines only 3 canonical values; `CommunicationOSGlassKit` has its own divergent `CommGlassTokens` | L | Migrate to `LiquidGlassTokens.cornerRadius{Small|Medium|Large}`; reconcile `CommGlassTokens` to reference shared system |
| A11-003 | `AmenContextOrchestrator.swift:119` | CMMotion callback delivered to `.main` queue with redundant `Task { @MainActor }` hop; `start()` called on every foreground transition without verifying prior state | S | Pass dedicated background `OperationQueue` to `startActivityUpdates`; add `isStarted` guard that calls `stop()` first |
| A11-004 | `CachedAsyncImage.swift:26` + 20+ callers | Default decode size 600×600 is 8–20× larger than required for avatar/thumbnail callers; cost-per-entry exceeds per-slot budget, defeating the cache | M | Remove 600×600 default; require callers to pass explicit `size:` matching their `.frame()` |
| A11-005 | `WorshipMusicService.swift:177` | Live Activity update rate every 5 seconds (~720/hour) vastly exceeds Apple's ~15/hour ActivityKit budget; Dynamic Island timer will freeze/skip | S | Change to 60-second update interval or adopt push-based `pushType: .token` updates |
| A12-005 | `BereanCommunicationHubView.swift:154` | `PhotosPicker` in DM hub has no `onChange` handler; photos silently disappear with no moderation or delivery — creates a future moderation bypass risk when wired | M | Either implement full moderation-then-upload path (`ImageModerationService` before upload) or remove camera/photo options until pipeline is wired |
| A12-006 | `AgeAssuranceModels.swift`, `ageTier.js`, `AmenChildSafetyModels.swift` | Three parallel age tier vocabularies coexist; one service may classify a user as minor while another classifies them as adult | L | Consolidate on backend `ageTier` vocabulary as single source of truth; deprecate `AgeAssuranceService` private subcollection tier |
| A12-007 | `SelahMediaService.swift:128–210` | Selah media photo upload has no client-side moderation pre-check; relies entirely on async Storage trigger; content is briefly accessible after upload before scan completes | S | Add `ImageModerationService.shared.moderateImage` call before `putData` in `uploadPhoto()` |
| A13-003 | `functions/berean/modelRouter.ts:138–216` | No provider data-governance flag is set on Gemini API calls; prayer content may be used for model training without user consent | M | Use Vertex AI Gemini endpoint (contractual data governance under GCP TOS §3) instead of public `google/generative-ai` SDK |
| A13-004 | `functions/semanticEmbeddings.js:270–327`, `pineconeCleanupFunctions.js:229–274` | OpenAI embedding cache document at `embeddings/{cacheKey}` for prayer-partner matching is not deleted in account deletion cascade | S | Delete `embeddings/prayerpartner_user_{uid}` and related prayer cache entries in deletion cascade |
| A13-005 | `functions/semanticEmbeddings.js:482–592`, `mlPrayerIntelligence.js:140–258` | `intercessorMatches` collection (requesterId, matchedUserIds) not in deletion cascade; HuggingFace is an undisclosed external data processor for prayer content | M | Add `intercessorMatches` deletion to cascade; document HuggingFace as sub-processor in privacy manifest |
| A13-006 | `functions/berean/constitutionalPipeline.ts:360–375` | `bereanPipelineTraces` and `bereanModelLogs` have no defined retention TTL and are not cleared on account deletion | M | Add deletion for both collections in account deletion cascade; set 90-day scheduled purge |
| A13-007 | `functions/berean/feedbackCapture.ts:109–155` | `bereanFeedback` collection (including free-text user comments) not in account deletion cascade | S | Add `deleteDocsWhere('bereanFeedback', 'userId', uid)` to deletion cascade |

---

## P3 Findings

| ID | Location | Violation | Effort | Suggested Fix |
|----|----------|-----------|--------|---------------|
| A1-009 | `AMENAPP/AMENAPP/CaughtUpService.swift:135` | Deep-scroll nudge fires at 120 posts; no hard absolute ceiling after session extensions are exhausted — users can continue indefinitely | M | Disable `loadMorePosts` after 2 session extensions rather than only showing a soft banner |
| A1-010 | `SelahMediaHomeView.swift:496`, `SelahMediaDetailView.swift:172` | Like counts rendered in Selah media views despite platform-wide intent to suppress engagement counts on contemplative surfaces | S | Remove `likeCount` from Selah home grid; replace detail action bar count label with non-numeric heart icon |
| A2-022 | `AmenCovenantLiquidGlass.swift:462` | `UIColor(red:)` amber hardcode in private extension instead of `AmenTheme.Colors.amenGold` | S | Replace with `AmenTheme.Colors.amenGold` converted to UIColor |
| A2-023 | `BereanVoiceView.swift:244–262` | 60px + 40px blurs with infinite animation; no `accessibilityReduceTransparency` guard; continuous GPU load on A12 and earlier | S | Wrap blur circles in `if !reduceTransparency`; replace infinite animation with static glow |
| A2-024 | `GivingModels.swift:100–107`, `GivingComponents.swift:463–464` | 8 accreditation badge colors as `Color(red:)` in the model layer; no dark-mode adaptation | M | Move badge colors to `GivingTheme.Colors` token file with UIColor adaptive initializers |
| A3-015 | `SacredFeedModes.swift:325–330` | "Clear all feed filters" dismiss uses `.onTapGesture` instead of `Button`; ~10pt tap target | S | Wrap in `Button("Dismiss", action: clearAll)` instead of `.onTapGesture`; add padding |
| A3-016 | `AMENAPP/AMENAPP/BereanSpiritualViewModel.swift:14–34` | Berean conversation history is in-memory only; switching apps mid-conversation loses entire context | L | Persist messages to Firestore under `users/{uid}/bereanConversations/{conversationId}/messages`; load on init |
| A3-017 | `AMENAPP/AMENAPP/FeedCardViews.swift:782–801` | Format toggle buttons (bold/italic toolbar) have no `accessibilityLabel`; VoiceOver reads raw SF Symbol names | S | Add `.accessibilityLabel(isActive ? "\(iconName), selected" : iconName)` |
| A4-006 | `NotificationSettingsView.swift:62–69` | Destructive `.alert` confirmation required for resetting which educational banners have been dismissed — a reversible, low-stakes action | S | Remove the `.alert`; execute `resetSeen()` on button tap directly, or downgrade button from `.destructive` role |
| A4-007 | `ChurchNotesView.swift:~1434, ~5645, ~6787` | All three note-deletion call sites use `try?` silently swallowing errors; note may appear deleted locally but persist remotely | S | Replace `try?` with `do { } catch { showError = error.localizedDescription }` |
| A4-008 | `AMENAPP/OnboardingOnboardingView.swift:175–188` | "Skip" button on step 3 (personalization/terms) calls `advance(by: 1)` unconditionally, bypassing `hasAgreedToTerms` gate | S | In `advance(by:)`, when `step == 3 && delta > 0`, require `hasAgreedToTerms == true` or re-validate server-side |
| A5-008 | `AMENAPP/AppDelegate.swift:181–188` | ATT `requestTrackingAuthorization` at app launch (1s delay) gives no contextual value before user has seen content | S | Move ATT request to after user has completed onboarding and seen first personalized feed |
| A5-009 | `AmenContextOrchestrator.swift:106` | Location permission requested immediately post-login regardless of whether user has navigated to any location feature | S | Move `requestWhenInUseAuthorization()` to first open of `ChurchDiscoveryView` or proximity-based feature |
| A5-010 | `PrivacyInfo.xcprivacy` | `NSPrivacyCollectedDataTypeContacts` declared as `Linked: false` but contact-match output (displayName, avatarURL) is linked to the authenticated user's social graph | S | Change `Linked` to `true` for contacts data type |
| A6-009 | `functions/berean/feedbackCapture.ts:57–69` | If the feature-flags Firestore document is absent, `isFeedbackCaptureEnabled` returns false; "unsafe"/"misleading" user feedback silently never reaches `guardianReviewQueue` | S | Change flag-not-found case to return `true` (default enabled) for the feedback capture gate |
| A6-010 | `AMENAPP/AIIntelligence/BereanConstitutionalPipeline.swift` | iOS kill-switch reads cached RemoteConfig without ensuring a prior fetch; offline-onboarded users may receive legacy unchecked responses for their entire first session | S | Add one-time RemoteConfig fetch-and-activate before first Berean query; confirm console default is `true` |
| A7-010 | `AmenSpacesHeroCardSection.swift:162` | `heart.fill` as prayer count icon on Spaces dashboard; `hands.sparkles` is the dominant prayer symbol elsewhere on the same dashboard — two competing icons for prayer | S | Replace with `hands.sparkles` to match established convention |
| A7-011 | `AmenChurchHubView.swift:113` | Custom glass back button at top-leading not connected to NavigationStack; conflicts with native swipe-back gesture | S | Replace with `.navigationBarBackButtonHidden + ToolbarItem(.navigationBarLeading)` or add `navigationBarBackButtonHidden(true)` |
| A7-012 | `AdaptiveComposer/DockedCreationRail.swift:166` | Docked rail toggle uses `xmark` for "collapse" state; imports cancel semantics into an expand/collapse affordance | S | Replace collapsed `xmark` with `chevron.down`; reserve `xmark` for dismiss/cancel only |
| A8-007 | `FeedCardViews.swift:437` | "Hermeneutics" rendered as a filter chip in the Scripture topic hub without explanation | S | Rename to "How to Study the Bible" or add subtitle |
| A8-008 | `WalkWithChristFeatures.swift:1105` | Streak counter on devotional commitment cards uses accent color; other surfaces (ReflectionSaveSheet, GivingComponents) explicitly note "no streaks" | S | Remove streak display; replace with non-numerical phrase like "Active this week" |
| A8-009 | `SmartActivityCopyGenerator.swift:99` | Streak count in social graph activity copy creates comparative pressure | S | Remove streak from activity copy generator; use connection-positive signals only |
| A8-011 | `functions/messages_features.js:547` | "Prayer Answered!" with exclamation mark in push notification title; inconsistent with calm notification voice | S | Change to "Prayer Answered" (remove exclamation mark) |
| A9-009 | `AMENAPP/AMENAppIntents.swift:37–44` | Siri/Shortcuts-injected Berean prompt bypasses `AmenContentSafetyService.checkBeforePost` GUARDIAN pipeline | M | Run prompt text through `AmenContentSafetyService.shared.checkBeforePost` before forwarding to Berean session |
| A10-007 | `AMENAPP/FullscreenMediaViewer.swift:233–250` | Background scrim layer has near-zero opacity (0.04 effective); chrome elements (close button, counter) become illegible on bright user imagery | M | Increase scrim to minimum effective opacity or apply luminance-adaptive gradient |
| A11-006 | 15+ files across Creator, SearchViewComponents, PrayerArcCard, BookDetailView | `AsyncImage` used directly instead of `CachedAsyncImage` in scrollable/reusable views; causes repeated network fetches for same profile photos | M | Replace `AsyncImage` with `CachedAsyncImage` (passing appropriate `size:`) at all 15+ non-trivial call sites |
| A12-008 | `AMENAPP.xcodeproj/project.pbxproj:1705, 1761` | Single `social-networking` app category prevents Screen Time from distinguishing faith education (Selah) from entertainment (OUTPOUR) for parental controls | L | Implement `DeviceActivityReport` extension using `FamilyControls` to report Selah/Prayer time separately |
| A13-008 | `functions/berean/index.ts:81–94`, `BereanMemoryView.swift:95` | Client sends `userId` in callable data payload; backend ignores it without documentation; latent IDOR risk for future callables | S | Remove `userId` from iOS callable payloads; add code comment in index.ts that data.userId is intentionally disregarded |

---

## Platform Readiness Gaps (RG)

| ID | Surface | Gap Description | User Value | Effort | Product Decision Needed? |
|----|---------|-----------------|------------|--------|--------------------------|
| A2-021 | All surfaces — 201 `.font(.system(size:))` call sites | Fixed font sizes throughout the composer and attachment cards block Dynamic Type scaling | High: users who need large text cannot read post composer | L | No — this is a compliance fix; prioritize high-traffic surfaces first |
| A7-007 | ConnectSpaces `AmenSpaceDiscoveryView`, `AmenConnectSpacesHubView` | Three Space card representations with divergent materials and tap behaviors; no unified `AmenSpaceRowCard` | Medium: inconsistent navigation model reduces trust | M | Yes — product must decide canonical card behavior (navigate vs. expand vs. sheet) |
| A9-006 | `AMENAPP.release.entitlements` | `com.apple.developer.siri` entitlement absent from release build; all App Shortcuts non-functional in TestFlight/App Store | High: all Siri/Shortcuts features dead in production | S | No — deploy fix; confirm with provisioning portal |
| A9-011 | App Intents | No "Find a Church" intent; "Find a church near me" is the most natural voice query for AMEN's core purpose | High: core feature unreachable via voice | S | Yes — decide whether to expose church finder in Shortcuts gallery |
| A9-012 | App Intents + SelahHandoff | No "Resume Bible Reading" intent; `SelahHandoff.makeReadingActivity()` has zero call sites | High: seamless reading handoff and voice navigation absent | M | No — implement; wire existing infrastructure |
| A9-013 | App Intents | No "Open Church Notes" / "Search sermon notes" intent | Medium: power users cannot voice-access notes | S | Yes — decide on Shortcuts Gallery prominence |
| A9-014 | WidgetKit | `SelahVerseWidget` infrastructure (payload + publisher + app group) is complete but WidgetKit Extension target absent; daily verse widget cannot be added from widget gallery | High: daily scripture on Lock Screen is a flagship faith feature | L | No — implement; add Widget Extension target in Xcode |
| A9-015 | SpotlightIndexingService | On-device Spotlight index exists (`SpotlightIndexingService`) but has zero call sites; Algolia (off-device, privacy risk) is used while private Spotlight is ignored | Medium: users cannot find personal AMEN content in iOS Search | M | No — wire `SpotlightIndexingService` for public posts and shareable notes; safer than Algolia for personal content |
| A10-008 | Adaptive Colors Settings | No user control for glass clarity/opacity independent of content-color tinting; both dimensions collapsed in Adaptive Colors setting | Low-medium: power users cannot tune glass independently | M | Yes — product must decide whether to expose glass clarity control to end users |
| A10-009 | App Icon asset catalog | No layered icon asset (foreground/background/specular) for iOS 26 Liquid Glass refractive icon treatment; tinted variant entry has empty filename | Medium: AMEN icon renders as flat image inside generic glass pill on iOS 26 | M | No — design deliverable; provide layered icon assets |
| A10-010 | iPad / Mac layout | No `NavigationSplitView`; phone-sized tab bar on iPad; glass chrome uses phone proportions that look oversized on larger screens | High on iPad: second-class user experience | L | Yes — product must decide scope of iPad/Mac investment for v1 |
| A10-011 | LiquidGlassMaterial over UGC imagery | 70%-opacity white specular highlight in light mode washes out content detail in LivingEntry cards over church/media imagery | Medium: church thumbnails obscured by over-bright glass | S | No — cap specular highlight at 0.30 over imagery; add `hasComplexBackground` parameter |
| A10-012 | AmenGlassActionSheet, AmenLiquidGlassBottomSheet | `.prominent` glass tier never used in production; all sheet surfaces use `.ultraThinMaterial` — layering hierarchy visually flat | Low: visual polish concern | S | No — apply `amenProminentGlassEffect` to sheet chrome backgrounds |
| A11-007 | Resources tab — DailyVerseGenkitService | Today's verse not prefetched at launch; cold-fetch latency (~1–3 s) visible on Resources tab open | Medium: first impression on a core spiritual feature is a spinner | S | No — add low-priority prefetch in `warmUpServices()` when user is authenticated |
| A11-008 | HomeView — FirebasePostService | Firestore cache-only preload has no network fallback; first-ever launch shows blank feed until listener fires | High: blank feed on first launch | S | No — fall back to `.default` source on cache miss, capped to 10 posts |
| A11-009 | BereanRealtimeWebSocketTransport | `URLSession.shared` used for WebSocket; lacks `waitsForConnectivity`; fails fast on marginal networks instead of waiting | Medium: Berean voice sessions drop on weak networks | S | No — create dedicated URLSession with `waitsForConnectivity = true` |
| A11-010 | AmenContextOrchestrator + ChurchProximityEngine | Two independent `CMMotionActivityManager` instances both deliver to `.main` queue | Low: minor continuous main-thread pressure | S | No — share one background OperationQueue across both managers |
| A12-009 | DM image/video display | Apple Communication Safety (`SensitiveContentAnalysis`) not integrated; no on-device nudity pre-scan before incoming DM image/video renders | Critical for minor accounts: Apple requires this for apps targeting minors with image messaging | M | No — required compliance; add `com.apple.developer.sensitivecontentanalysis` entitlement and wrap DM image display |
| A13-001-RG | Berean intent classification | Stage 2 intent classification sends all query text to Gemini for an 8-class closed-set task; could run on-device via NaturalLanguage keyword matching | Privacy: every Berean query triggers a cloud call for a simple classification | M | Yes — product must decide acceptable latency tradeoff for on-device classification |
| A13-002-RG | Prayer embedding (HuggingFace) | all-MiniLM-L6-v2 model (22M params) available as Core ML; prayer content sent to HuggingFace hosted inference could be computed entirely on-device | Privacy: prayer text sent to undisclosed third-party for embedding | L | Yes — significant engineering investment; product must prioritize |
| A13-003-RG | Berean memory extraction | Memory extraction from spiritual conversations uses Gemini cloud call; Apple FoundationModels API (iOS 18.1+) supports this task on-device | Privacy: conversation content sent to additional cloud provider | M | Yes — requires Apple Intelligence availability check; product decides fallback strategy |

---

## Per-Lane Coverage Map

| Lane | Status | Primary Surfaces Scanned | P0 | P1 | P2 | P3 | RG | Discarded |
|------|--------|--------------------------|----|----|----|----|----|----|
| A1 | Complete | functions/engagementNotifications.js, aiProactiveFeatures.js, aiModeration.js, bereanFeaturesFunctions.js, WalkWithChristFeatures.swift, HealthyModeService.swift, CaughtUpService.swift, SmartActivityCopyGenerator.swift | 0* | 3 | 4 | 3 | 0 | 0 |
| A2 | Complete | All 1,036 Swift files; AmenTheme.swift, GlassMaterial.swift, LiquidGlassTokens.swift, Motion.swift | 2 | 11 | 9 | 3 | 0 | 0 |
| A3 | Complete | All 1,036 Swift files — full a11y audit | 0 | 5 | 8 | 4 | 0 | 0 |
| A4 | Complete | CreatePostView.swift, PostDetailView.swift, CovenantRoomDetailView.swift, UnifiedChatView.swift, ChurchNotesView.swift, OnboardingOnboardingView.swift | 0 | 3 | 3 | 2 | 0 | 0 |
| A5 | Complete | PrivacyInfo.xcprivacy, Info.plist, AppDelegate.swift, BereanVoiceView.swift, CommunityOS/Prayer/, AmenContextOrchestrator.swift, functions/minorProtection.js, functions/moderateUGC.js | 0 | 3 | 4 | 3 | 0 | 0 |
| A6 | Complete | AMENAPP/AIIntelligence/ (49 files), AMENAPP/AMENAPP/AIIntelligence/ (3 files), functions/berean/ (11 files), functions/ail/ (2 files) | 1 | 3 | 4 | 2 | 0 | 0 |
| A7 | Complete | All 1,036 Swift files — iconography + interaction consistency audit | 0 | 4 | 5 | 3 | 0 | 0 |
| A8 | Complete | PostCard.swift, FeedCardViews.swift, WalkWithChristFeatures.swift, Intelligence/ (5 files), functions/engagementNotifications.js, functions/messages_features.js | 1* | 3 | 4 | 3 | 0 | 0 |
| A9 | Complete | AMENAppIntents.swift, SpotlightIndexingService.swift, AlgoliaSyncService.swift, CreatePostView.swift (Algolia call site), SelahHandoff.swift, AMENAPP.entitlements, Info.plist | 1 | 3 | 3 | 2 | 5 | 0 |
| A10 | Complete | All LiquidGlass/ files (12), DesignSystem/Ambient/, FullscreenMediaViewer.swift, SuggestedAccountCard.swift, AMENOnboardingSystem.swift, AMENProfileAdaptiveModules.swift, Assets.xcassets | 1 | 3 | 4 | 0 | 5 | 0 |
| A11 | Complete | AMENAPPApp.swift, AppDelegate.swift, CachedAsyncImage.swift, ImageCache.swift, BereanRealtimeWebSocketTransport.swift, WorshipMusicService.swift, FirebasePostService.swift, AmenContextOrchestrator.swift | 1 | 2 | 2 | 1 | 4 | 0 |
| A12 | Complete | VideoAttachmentHandler.swift, AMENAccountTypeOnboardingView.swift, SignInView.swift, MessageSettingsService.swift, MinorSafetyGate.swift, BereanCommunicationHubView.swift, AgeAssuranceModels.swift, functions/ageTier.js, functions/minorProtection.js, functions/imageModeration.js | 2 | 3 | 3 | 0 | 2 | 0 |
| A13 | Complete | AMENAPP/AIIntelligence/ (49 files), AMENAPP/AMENAPP/AIIntelligence/ (3 files), functions/berean/ (11 files), functions/accountDeletion.js, functions/semanticEmbeddings.js, functions/mlPrayerIntelligence.js, functions/pineconeCleanupFunctions.js | 2 | 3 | 2 | 1 | 3 | 0 |

*A1-001 and A8-002 are the same finding; A8-002 absorbed into A1-001 / merged as P0-01 in this report.

---

## Deduplication Log

| Merged Finding | Source IDs | Kept Severity | Reason |
|----------------|------------|---------------|--------|
| P0-01 — "We Miss You" Notification | A1-001 (Lane A1) + A8-002 (Lane A8) | P0 | Identical evidence: `functions/engagementNotifications.js:99`; both cite the same line and the same aiProactiveFeatures.js internal policy violation. A8-002 absorbed into A1-001. |
| P0-01 context note | A1-001 has a cross-lane handoff about `aiProactiveFeatures.js:289` (popularity-ranked re-engagement content selector) | Preserved as P3-adjacent backlog note | Separate concern from the notification copy itself; not a duplicate but not a standalone finding with immediate user impact |
| A2-002 / A2-006 reduce-motion | A2-002 (WhatNeedsAttentionView shimmer), A2-006 (BereanVoice orb) | Both kept as separate P1 findings — different files, different symptoms, both confirmed by evidence | Different locations, different fix paths; no merge |
| A1-004 streak (WalkWithChrist) / A8-008 streak (WalkWithChrist) | A1-004 and A8-008 both cite `WalkWithChristFeatures.swift:1103–1106` | Consolidated into single P2 entry (A1-004); A8-008 streak text variant merged | Same line, same violation, same fix. A1-004 kept as canonical; A8-008 details about "no streaks" directive added to it |
| A1-005 activeStreak social / A8-009 activeStreak | A1-005 and A8-009 both cite `SmartActivityCopyGenerator.swift:98–99` | Consolidated into single P2 entry (A1-005) | Exact same file, line, and violation. |
| A2-007 ConnectSpaces hex colors / A10 glass tokens | A2-007 (904 `Color(hex:)` usages) and A10 (RT guards) | Kept separate | A2 is about color adaptation (dark mode); A10 is about transparency/RT guards; different defects even though both involve glass surfaces |
| A5 privacy findings / A13 privacy findings | A5 covers PrivacyInfo.xcprivacy manifest + permissions timing; A13 covers AI data processor disclosure and deletion cascade | Kept separate | Different scope: A5 is iOS privacy manifest; A13 is GDPR data lifecycle. Both lanes cover "privacy" but at different layers |
| A6-001 constitutional bypass / A9-009 Siri intent Aegis bypass | Different code paths: A6-001 is backend pipeline flag-read failure; A9-009 is a client-side intent handler that bypasses the iOS Aegis pre-flight check | Kept separate | Two distinct bypass mechanisms; A6-001 is backend, A9-009 is iOS client |
| A6 AI safety / A12 youth/AI safety | A6 covers constitutional pipeline and study call guardrails; A12 covers COPPA age gates and minor messaging | Kept separate | Different domains: A6 is AI output safety; A12 is age-verification and child protection |

**Total discarded (evidence-free):** 0 — all 117 deduplicated findings have confirmed file/line evidence.
**Total merged:** 3 pairs merged → net reduction of 3 raw findings.
**Raw findings before dedup:** 120 across 13 lanes. **Final deduplicated count:** 117.

---

## Cross-Lane Handoff Resolution

| Handoff Origin | Claim | Verified? | Resolution Domain |
|----------------|-------|-----------|-------------------|
| A1 → Backend: `aiProactiveFeatures.js:289` popularity-ranked re-engagement | Popularity-sorted posts pushed to dormant users may be an attention-bait loop | Partially confirmed (line exists); designated as P3 backlog note | Backend CF / engagement ethics |
| A1 → Minor Safety: `HealthyModeService.swift:178` async minor detection window | Autoplay may fire before `isMinor` resolves on slow connection at launch | Confirmed: `detectMinorStatus()` fires async post-launch | A12 minor safety lane; note added to A12-002 context |
| A1 → Backend: `sendWeeklyAccountabilityCheckIn` unbounded Firestore read | Could notify inactive thread members; cost risk at scale | Confirmed: `db.collection('accountabilityThreads').get()` with no filter | Backend CF performance; backlog item |
| A2 → A3 Accessibility: A2-002, A2-005, A2-006, A2-021 as accessibility blockers | Lane A3 should flag these | Confirmed overlap; A2 and A3 findings are in both P1 tables as separate entries with cross-references | Accessibility engineering |
| A2 → A4 Performance: 36px/60px blur GPU cost | GPU profiling needed | Captured as P3 findings A2-019, A2-023 with reduce-transparency recommendation | Performance / design systems |
| A3 → A1 Security: Berean session persistence (A3-016) privacy review needed | Persisting conversations to Firestore requires access rules review | Noted: captured as A3-016 P3; Firestore rules team should add `users/{uid}/bereanConversations` rules with UID-scoped read | Backend security / Firestore rules |
| A4 → A1 Auth/Security: A4-008 ToS bypass via skip | Legal/compliance implications | Confirmed: skip on step 3 allows proceeding without ToS agreement | Onboarding engineering / legal |
| A5 → A4 Backend: A5-002 prayer room adult-minor gap | Needs backend fix in moderateUGC.js | Confirmed: moderatePrayerRequest does not call checkAdultMinorInteraction | A12 child safety + backend CF |
| A5 → A6 Privacy: Health data "not stored" claim vs. PrivacyInfo declaration | Policy alignment needed | Captured as A5-006 P2 | Privacy policy / legal |
| A6 → Firestore rules: legacy pipeline trace writes for high-risk queries | Rules team should reject bereanPipelineTraces with reviewVerdict="legacy" for high-risk | Not yet confirmed in Firestore rules file; designated as open action item | Firestore security rules |
| A6 → Auth/Session: userId passthrough in callables | Check all callable invocation sites for data.userId pattern | Confirmed pattern at 4 BereanMemoryView callsites; captured as A6-002 P1; full codebase grep recommended | iOS engineering |
| A6 → Remote Config: berean_constitutional_pipeline_enabled default value | Confirm default is `true` in Firebase console | Cannot confirm from source code alone; designated as deployment verification step | Firebase operator |
| A7 → A8 Design Tokens: seven-way glass fork requires token audit | Needs LiquidGlassTokens.swift reference | Captured as A7-005 P2 (L effort); cross-references A10-006 corner radius fragmentation | Design systems |
| A7 → A6 Accessibility: heart=pin vs heart=pray dual semantics needs accessibilityHint | Captured as A7-001 P1 | Confirmed | Accessibility engineering |
| A9 → Algolia: defense-in-depth via Algolia dashboard index rules | Confirm isPublic filter rules at Algolia dashboard | Cannot confirm from source; designated as deployment verification step | Algolia operator / backend |
| A9 → GUARDIAN: A9-009 Siri Berean intent bypasses Aegis | Needs Berean AI safety pipeline owner to add check | Confirmed: AMENAPPApp.swift:886 forwards intent prompt to Berean without safety check | iOS AI safety engineering |
| A9 → Release/Build: A9-006 release entitlements + A9-008 missing NSSiriUsageDescription | Must be resolved before App Store submission | Both confirmed in entitlements and Info.plist files | Build/release engineering |
| A10 → Crash/stability: A10-003 bare glassEffect in AMENOnboardingSystem.swift | May be missed by lanes not scanning onboarding | Confirmed as P0-02; elevated to P0 | iOS engineering (P0) |
| A10 → Assets/Design: A10-009 missing layered icon; tinted variant has empty filename | Xcode build warning possible | Confirmed: tinted variant entry has no filename in Contents.json | Design / Xcode build |
| A11 → Berean AI: A11-002 main-thread JSON parsing | Fix requires background actor extraction | Captured as A11-002 P1 | Berean AI / iOS performance |
| A12 → Auth/Onboarding: A12-002 SSO DOB bypass | SSO paths confirmed to not trigger showDOBCollection | Confirmed as P0-09; elevated to P0 | iOS auth engineering (P0) |
| A12 → CF deploy: A12-001 chat_videos moderation, A12-005 DM photo pipeline | New CF + Storage trigger required | Confirmed gaps; both in P0/P2 findings | Cloud Functions engineering |
| A12 → Firestore rules: verify birthYear not client-writable (would drop A12-004 to P2) | Cannot confirm rule without reading firestore.rules | Designated as open action: read `firestore.rules` to check `users/{uid}/birthYear` write rules | Firestore security rules |
| A13 → Firestore rules: bereanMemory soft-delete visibility | Rules should gate on isDeleted==false | Confirmed via memoryStore.ts queries; captured as P0-04 note | Firestore security rules |
| A13 → PrivacyInfo.xcprivacy: HuggingFace must be declared as third-party processor | HuggingFace endpoint used in mlPrayerIntelligence.js | Confirmed; captured as A13-005 P2 | Privacy manifest / legal |
| A13 → CF deploy: bereanDeleteAllMemory must be called from server-side deletion | Not in deletion cascade | Confirmed as P0-05; elevated to P0 | Cloud Functions engineering (P0) |

---

## Remediation Wave Plan

### Wave A — Parallel, No Contested Files
All items in Wave A can be worked in parallel by different engineers or sub-teams. No two items touch the same file.

- **P0-01**: `functions/engagementNotifications.js:99` — rewrite notification copy
- **P0-03**: `AMENAPP/AMENAPPApp.swift:118–120` — move `setupRemoteConfig()` to AppDelegate
- **P0-04**: `functions/berean/memoryStore.ts` — hard-delete implementation
- **P0-06**: `functions/berean/constitutionalPipeline.ts:318` — replace catch-block `legacyPipelineCall` with error output
- **P0-07**: `AMENAPP/CreatePostView.swift:4748` — fix `isPublic: true` hardcode
- **P0-10**: `AMENAPP/AlgoliaSyncService.swift:311–313` — add privacy filter to bulk sync
- **A1-006, A1-007**: `functions/aiModeration.js:822`, `functions/bereanFeaturesFunctions.js:55` — remove `badge: 1` hardcodes
- **A2-003, A2-008**: `BereanConversationView.swift`, `AmenSpaceDetailView.swift` — replace hardcoded `.black` / `.white` foreground colors
- **A2-004**: `AmenActionTray.swift`, `StewardshipDashboardView.swift` — consolidate `amenSnappy` into `Motion` enum
- **A2-005**: `AmenSafetyOSReactionEngine.swift:982` — add reduce-motion guard to PeaceCheckPrompt
- **A2-006**: `BereanVoiceView.swift:251, 261` — extend existing reduce-motion guard to orb animations
- **A2-011**: `AmenStripeOnboardingService.swift:76–77` — adaptive UIColor initializer
- **A2-012**: `LiquidGlassHeader.swift` preview blocks — replace hardcoded background
- **A2-015, A2-016, A2-020**: PulseCard, PinnedPostGlassSystem, WalkWithChrist — route raw springs through `Motion.adaptive`
- **A2-019, A2-023**: ObjectHub header blur, BereanVoice ambient blurs — add `accessibilityReduceTransparency` guard
- **A2-022**: `AmenCovenantLiquidGlass.swift:462` — UIColor amber → `AmenTheme.Colors.amenGold`
- **A3-001, A3-002**: `HomeView.swift` — add accessibility labels to SearchButton and FeedModeNavButton
- **A3-004**: `CommentsViews.swift` — Dynamic Type scaling for comment author names
- **A3-005, A3-006**: `CreatePostMediaViews.swift` — expand remove-photo button touch targets
- **A3-007 through A3-012**: PinnedProfileHeroSurface, MediaDetailView, GetReadyView, AmenMediaSessionView, WalkWithChrist FaithCommitmentSheet, ChurchNoteSemanticEditorView — expand close/dismiss/toolbar button touch targets
- **A3-013**: `ScriptureImmersionView.swift:110` — add `.relativeTo: .body` to Georgia font
- **A3-014**: `HomeView.swift:1339` — increase Join button padding
- **A3-015**: `SacredFeedModes.swift:325` — replace `.onTapGesture` with `Button`
- **A3-017**: `FeedCardViews.swift:782` — add `accessibilityLabel` to format buttons
- **A4-001**: `AmenCovenantRoomDetailView.swift` — add confirmationDialog before message delete
- **A4-002**: `PostDetailView.swift:1625, 1647` — add confirmationDialog before comment/reply delete
- **A4-004**: `CreatePostView.swift:783` — add "Discard this post?" title to confirmation dialog
- **A4-005**: `UnifiedChatView.swift:4306` — add confirmationDialog before Decline message request
- **A4-006**: `NotificationSettingsView.swift:62` — remove destructive alert for reversible reset
- **A4-007**: `ChurchNotesView.swift` (3 sites) — replace `try?` with error-display pattern
- **A4-008**: `OnboardingOnboardingView.swift:175` — gate Skip on step 3 behind `hasAgreedToTerms`
- **A5-001, A5-008**: `AppDelegate.swift` — defer ATT prompt to post-onboarding
- **A5-003**: `PrivacyInfo.xcprivacy` — add missing required-reason API category entries
- **A5-004**: `BereanVoiceView.swift:134` — move permission request to mic button tap handler
- **A5-005**: `BereanPulsePermissionManager.swift` — scope contacts fetch to phone numbers only
- **A5-006**: `PrivacyInfo.xcprivacy` — reconcile health data declaration with usage description
- **A5-007**: Info.plist NSUserNotificationsUsageDescription — broaden scope string
- **A5-009**: `AmenContextOrchestrator.swift:106` — defer location permission to first feature use
- **A5-010**: `PrivacyInfo.xcprivacy` — change contacts `Linked` to `true`
- **A6-002**: `BereanMemoryView.swift` — remove userId from callable payloads
- **A6-004**: BereanContextResultSheet — add "study companion, not pastoral authority" disclaimer
- **A6-006, A6-007**: `BereanConstitutionalIntelligence.swift` — auto-apply medical guardrail; make study-call check blocking
- **A6-009**: `feedbackCapture.ts:57` — change flag-not-found to return `true`
- **A6-010**: `BereanConstitutionalPipeline.swift` — add RemoteConfig fetch before first Berean query
- **A7-001, A7-002, A7-003, A7-004**: Icon metaphor fixes — hub pin, mentor follow, pulse following, hero card preview
- **A7-008**: `AmenFeedContextLabelSystem.swift:58` — replace bookmark with clock icon for follow-up label
- **A7-010, A7-011, A7-012**: hands.sparkles for prayer count, church hub back button, docked rail chevron
- **A8-001**: `PostCard.swift` — surface Share button in action bar
- **A8-004, A8-005, A8-006, A8-007, A8-011**: Plain-language rewrites across ConnectPreferencesView, ScriptureGraphExplorerView, AmenConnectContextBeforeWatchingView, FeedCardViews, messages_features.js
- **A8-008, A8-009**: Remove streak displays from WalkWithChristFeatures, SmartActivityCopyGenerator
- **A9-003, A9-004**: `AMENAPPApp.swift` / ContentView — add observers for Siri intent notifications
- **A9-005**: `AMENAppIntents.swift` — add `siriEnabled()` gate to 5 ungated intents
- **A9-007, A9-008**: `Info.plist` — add Selah activity type and `NSSiriUsageDescription`
- **A10-001, A10-002**: `LiquidGlassMaterial.swift`, `LiquidGlassComposerBar.swift` — add RT guard
- **A10-004, A10-005**: `SuggestedAccountCard.swift`, `SuggestedForYouModule.swift`, `AMENProfileAdaptiveModules.swift` — add RT fallback
- **A10-011**: `LiquidGlassMaterial.swift` — cap specular highlight at 0.30 over imagery; add `hasComplexBackground` parameter
- **A10-012**: `AmenGlassActionSheet`, `AmenLiquidGlassBottomSheet` — apply `amenProminentGlassEffect` to sheet chrome
- **A11-003**: `AmenContextOrchestrator.swift:119` — background OperationQueue for CMMotion
- **A11-005**: `WorshipMusicService.swift:177` — change Live Activity update interval to 60 seconds
- **A11-007, A11-008, A11-009, A11-010**: DailyVerse prefetch, Firestore cold-launch fallback, WebSocket URLSession config, shared CMMotion queue
- **A12-003**: `MessageSettingsService.swift:310` — fix dead minor gate string comparison
- **A12-004**: `MinorSafetyGate.swift:21` — replace birthYear read with server-authoritative ageTier check
- **A12-007**: `SelahMediaService.swift` — add client-side ImageModerationService pre-check before upload
- **A13-004**: `pineconeCleanupFunctions.js` — add prayer embedding cache deletion
- **A13-007**: `bereanFunctions.js` / `accountDeletion.js` — add bereanFeedback to deletion cascade
- **A13-008**: `BereanMemoryView.swift` + `index.ts` — remove userId from callable payloads; add comment

### Wave B — Serialized (Contested Files or Architecture Decisions Required First)

Wave B items touch shared infrastructure or require a prior architecture decision. Work these sequentially or in small coordinated pairs.

1. **P0-02**: `AMENOnboardingSystem.swift:230` — fix bare `.glassEffect()` call. **Contested file:** onboarding system; must coordinate with any concurrent onboarding A/B work.
2. **P0-05 + A13-001 + A13-006**: Account deletion cascade (`accountDeletion.js`, `bereanFunctions.js`, `memoryStore.ts`) — all modify the same deletion pipeline. Work together in one PR.
3. **P0-08**: `functions/imageModeration.js` + new `chat_videos` Storage trigger — new CF; must not break existing image trigger.
4. **P0-09 + A4-008 (ToS gate)**: `SignInView.swift` SSO paths + `OnboardingOnboardingView.swift` — two onboarding files; work together to ensure DOB gate covers all sign-in paths consistently.
5. **A1-002**: `functions/messages_features.js:257` — streak grace period; contested: changes accountability thread behavior app-wide.
6. **A1-003**: `HealthyModeService.swift` — default inversion (infiniteScrollEnabled = false); high-risk behavior change; requires product sign-off and feature flag gate before deploy.
7. **A2-001, A2-014, A2-024**: Adaptive color migrations (BereanConversationView, PulseHeroStyle, GivingModels) — all require new UIColor adaptive initializers; design token review required first.
8. **A2-009, A2-010**: FeedCardViews + Giving module reduce-motion — touch core feed interaction; require QA pass on interaction feel.
9. **A2-013**: `PinnedPostGlassSystem.swift` — replace hand-rolled glass with `GlassMaterial.glassSurface`; visual regression risk on pinned posts.
10. **A2-017**: `IntelligenceCardView.swift` — content blur uses `AILEmotionalSafetyFilter`; requires AIL availability on this branch.
11. **A3-003, A3-013**: HolidayReflectionSheet + ScriptureImmersionView custom font scaling — requires design review to preserve aesthetic while achieving Dynamic Type compliance.
12. **A4-003**: `CreatePostView.swift` autosave gap — touches the 5,500-line CreatePostView; isolate in a small targeted PR.
13. **A6-001** (P0-06): `constitutionalPipeline.ts` catch block — must be deployed before constitutional pipeline is enabled in production; verify `errorPipelineOutput` function exists and returns a graceful user-facing message.
14. **A6-003**: `BereanSelectionOverlay.swift` — wire `AmenAIReviewActionsView` for high-impact context actions; touches AI review state machine.
15. **A6-005**: `constitutionalPipeline.ts:651` — hard gate for all-fail queries; touches the same file as A6-001; batch with it.
16. **A6-008**: `AmenSafetyModerationProvider.swift:170` — replace UserDefaults kill-switch with RemoteConfig; requires Remote Config console change to be coordinated.
17. **A9-006**: `AMENAPP.release.entitlements` — add Siri entitlement; requires provisioning profile regeneration; coordinate with Apple Developer account holder.
18. **A11-002**: `BereanRealtimeWebSocketTransport.swift` — background actor extraction; touches streaming voice infrastructure; requires careful concurrency audit.
19. **A11-004**: `CachedAsyncImage.swift` default size — breaking API change to init signature; all 20+ callers must be updated in the same PR to avoid compile errors.
20. **A12-002 (P0-09 companion)**: `AMENAccountTypeOnboardingView.swift` — add server-side `ageTier` validation block; must coordinate with backend to ensure `ageTier` is reliably written by `onUserDocCreated` before the app gate checks it.
21. **A12-005**: `BereanCommunicationHubView.swift` — either remove photo attachment UI or wire full moderation pipeline; product decision required first.
22. **A12-006**: Age tier vocabulary unification — `AgeAssuranceModels.swift`, `ageTier.js`, `AmenChildSafetyModels.swift`, `MessageSettingsService.swift`, `AMENSecureMessagingService.swift` — large cross-cutting refactor; own sprint.
23. **A13-002 (P0-04 companion)**: `memoryStore.ts` `deleteAllUserMemory()` — change batch-update to batch-delete; must be tested with A13-001 deletion cascade in the same test run.
24. **A13-003**: `modelRouter.ts` — migrate from public Gemini SDK to Vertex AI endpoint; requires GCP project config change.
25. **A13-005**: `mlPrayerIntelligence.js` — intercessorMatches deletion + HuggingFace disclosure; requires legal review of DPA before deployment.

### Wave C — Platform Readiness (Product Decisions Required First)

These items are enhancements or compliance investments that require a product or legal decision before engineering begins. Assign a decision owner and expected date before scheduling.

- **A2-021** (201 fixed font sizes / Dynamic Type): Engineering can start a phased migration, but a typography token system (AmenTheme.Typography) must be designed first. Decision: approve token system design.
- **A9-011, A9-013** (Find a Church intent, Church Notes intent): Decision: which intents to include in Shortcuts Gallery for v1.
- **A9-012** (Selah Bible Reading intent + Handoff): No product decision needed; wire existing infrastructure. Schedule as Wave B candidate once A9-006 entitlement fix is deployed.
- **A9-014** (WidgetKit Extension target): Decision: commit to Widget Extension target in Xcode for v1 App Store submission.
- **A9-015** (SpotlightIndexingService wiring): No product decision; engineering can wire immediately after A9-001/A9-002 privacy fixes ensure only public posts are indexed.
- **A10-006** (245 hardcoded corner radii): Engineering migration; design systems decision on canonical token names needed first.
- **A10-007** (FullscreenMediaViewer scrim): Engineering fix; no product decision.
- **A10-008** (glass clarity user control): Decision: expose glass clarity slider to users or keep internal.
- **A10-009** (layered app icon for iOS 26): Design deliverable (layered icon assets); no code change required beyond asset catalog update.
- **A10-010** (iPad NavigationSplitView): Decision: scope of iPad/Mac investment for v1 vs. post-launch.
- **A11-006** (15+ AsyncImage → CachedAsyncImage): Engineering fix; no product decision.
- **A12-008** (Screen Time DeviceActivityReport): Decision: invest in FamilyControls extension for v1 or post-launch.
- **A12-009** (Apple Communication Safety): No product decision — required compliance for apps targeting minors with image messaging. Schedule immediately in Wave B.
- **A13-RG-001** (on-device Berean intent classification): Decision: acceptable latency tradeoff for on-device NLTagger vs. cloud Gemini classification.
- **A13-RG-002** (Core ML embedding for prayer matching): Decision: investment in Core ML model conversion and bundling for v1.
- **A13-RG-003** (FoundationModels for memory extraction): Decision: Apple Intelligence availability requirement and Gemini fallback strategy.
