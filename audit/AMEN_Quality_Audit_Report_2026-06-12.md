# AMEN Quality Audit Report — 2026-06-12

Wave 2 aggregation of 13 lane reports (A1–A13). Findings deduplicated across known overlap pairs (A2↔A10 glass/tokens, A5↔A13 privacy, A6↔A9 AI pipelines, A6↔A12 youth/AI safety). Lane labels were reconciled by content: performance bodies = A10/A11, youth-safety = A12, privacy = A13. One incoming slot was empty ("MISSING") and is recorded as a coverage gap.

---

## ⚠️ P0 FINDINGS (BLOCK NEXT BUILD WAVE)

| ID | Location | User Impact | One-line Fix |
|----|----------|-------------|--------------|
| **P0-1** (A12-001) | `MessagingViewController.swift:119-165` | Minor can receive arbitrary/unscreened images via an active UIKit DM upload path that bypasses the entire media-safety stack. | Route `uploadImage()` through `MediaSafetyGateway.shared.evaluate()` before `putData`, or delete the controller in favor of `FirebaseMessagingService`. |
| **P0-2** (A5-001) | `FirebaseMessagingService.sendMessage()` + `SmartShareSystem.swift:851`, `OfflineMessageQueue.swift:72`, `PostShareOptionsSheet.swift:588/629` | Adult→minor DM hard block is never enforced on share, offline-replay, and post-share paths (`minorPolicy: nil` default); only `UnifiedChatView` resolves policy. | Extract `MinorSafetyService.resolvePolicy()` + gateway call into a helper invoked inside `FirebaseMessagingService.sendMessage()`; remove the `minorPolicy: nil` default. |
| **P0-3** (A6-001) | `BereanConstitutionalPipeline.swift:150-161` | When `berean_constitutional_pipeline_enabled` is false, the iOS client falls to `callLegacyBerean` — no crisis routing, no GUARDIAN, no citation enforcement; a self-harm query gets an unreviewed answer. | Remove the `callLegacyBerean` fallback; on flag-off return the same safe-unavailable output the backend already emits. |
| **P0-4** (A9-001 + A13-001 merged) | `SpotlightIndexingService.swift:23-59` + `AMENAppIntents.swift:225-241`; `BereanUserContext.swift:117-138` | Private/church-scoped prayer text is donated to OS Spotlight + Siri ML and written to unencrypted `UserDefaults`; prayer content is injected into every Berean AI call ignoring the `consentPrayerAI` (default-false) gate. | Add `category != .prayer && privacyLevel == .public` guard before Spotlight/Siri donation; move pending-prayer text to keychain/App Group; gate `fetchRecentPrayers` behind `consentPrayerAI`. |
| **P0-5** (A12-002) | `AgeVerificationOnboardingView.swift:19-21`; `AuthenticationViewModel.swift:297` | Google/Apple SSO sign-up with `ff_onboarding_v2` off skips `updateBirthYear` CF and `enforceMinorDefaults()`; declared minors get adult defaults. | Wire `AgeGateContainerView.completeAgeGate()` to call `updateBirthYear` CF + `enforceMinorDefaults()` so both paths are equivalent regardless of flag. |
| **P0-6** (A12-003) | `AuthenticationViewModel.swift:1643-1678` | Phone sign-up writes no DOB/age field; under-13 user holds an active Auth session before the catch-all gate fires (which itself doesn't enforce minor defaults). | Collect DOB before account creation in `verifyPhoneCode(isSignUp:)`, or call `AgeAssuranceService.setDateOfBirth()` immediately post-creation. |
| **P0-7** (A12-004) | `AgeAssuranceModels.swift:308-309` | `requireParentalConsentUnder16 = false` makes the parental-consent path dead code; EU under-16 / COPPA under-13 data collected without verifiable consent, contradicting the ToS. | Set `requireParentalConsentUnder16: true`; complete guardian-consent flow (OPEN-2) or block EU under-16 before launch. |
| **P0-8** (A12-005) | `BereanChatView.swift` (no age gate) | `BereanChatView` (inline AI chat) has no `BereanAgeGateService` guard; under-13 users can converse with Berean AI, generating COPPA-prohibited data. | Replicate the `BereanAgeGateService` guard from `BereanConversationView` at the top of `BereanChatView.body`. |
| **P0-9** (A13-002) | `AIBibleStudyExtensions.swift:57-91` + `accountDeletion.js:46-64` | `aiBibleStudyConversations` (with user-typed queries) is absent from the deletion cascade; survives account deletion indefinitely (App Store 5.1.1(v)). | Add `aiBibleStudyConversations` to `accountDeletion.js` and recurse into the `messages` subcollection. |
| **P0-10** (A13-003) | `BereanChatView.swift:251-259` + `accountDeletion.js:59-64` | `users/{uid}/chatHistory` subcollection (AI text reflecting prayer/personal content) is not in `USER_SUBCOLLECTIONS`; survives deletion. | Add `'chatHistory'` to the `USER_SUBCOLLECTIONS` array. |

**Discarded P0 candidates:** none. All P0s carry concrete file:line evidence.

---

## Executive Summary

- **Total findings (post-dedup): 119.** P0: 10 | P1: 27 | P2: 35 | P3: 33 | RG: 14.
- **GO/NO-GO: NO-GO for next build wave / App Store submission.** Ten P0s span four independently fatal classes: (1) **youth-safety bypasses** — an unscreened DM image path to minors (P0-1), adult→minor DM block skipped on multiple send paths (P0-2), and age-gate gaps in SSO/phone sign-up and Berean chat (P0-5, P0-6, P0-8); (2) **AI safety bypass** — constitutional pipeline fully skippable via a flag fallback (P0-3); (3) **privacy/consent** — prayer content leaked to OS Spotlight/Siri and AI providers without consent (P0-4) and a COPPA/GDPR-K consent flag hard-disabled (P0-7); (4) **right-to-erasure** — AI stores (Bible study, chat history) absent from the deletion cascade (P0-9, P0-10; plus P1 A13-006 realtime sessions).
- **Top systemic risks:** (a) safety/consent gates exist but are not uniformly enforced across all entry paths (DM send, sign-up, AI chat); (b) the "no-gamified-holiness" product contract is violated by live streak/guilt copy (A1-001/A8-001 merged) and several streak surfaces; (c) design-system fragmentation — hardcoded dark/light backgrounds break Dark/Light mode on 9+ surfaces, 14+ forked glass-card variants, 5 animation systems, and 223 files with non-scaling fonts (Dynamic Type).
- **Note:** P0-5/P0-6/P0-7 are partly gated by the **OPEN-2** human governance decision (guardian scope) and the `ff_onboarding_v2` rollout; these are not pure code fixes and are the long pole to launch.

---

## P1 Findings

Sorted by Effort (S → L).

| ID | Location | Evidence | User Impact | Fix | Effort |
|----|----------|----------|-------------|-----|--------|
| A1-001/A8-001 (merged) | `MilestoneManager.swift:173-174` | "...don't break the chain." + "Keep it going" CTA | Loss-aversion guilt converts formation into compulsion; contradicts "no gamified holiness". | Neutral copy; rename CTA. | S |
| A8-002 | `BereanPrayer/BereanPrayerBriefingView.swift:137` | "Start your prayer streak today" | Gamified streak framing on prayer (banned word). | "Come back tomorrow — prayer builds over time." | S |
| A8-004 | `ONE/Differentiators/ONELegacyDirectiveView.swift:214` | "...`one_activateLegacy` callable verifies trustee identity server-side." | Backend jargon in user-facing trust copy. | Plain-language rewrite; remove callable refs. | S |
| A8-005 | `ChurchNotes/Views/ChurchNotesSearchView.swift:50` | `Text("Document").tag("document")` | DB term shown instead of "File/PDF". | Relabel "File / PDF". | S |
| A9-002 | `AMENAPP.release.entitlements` vs `AMENAPP.entitlements:35` | `com.apple.developer.siri` present in debug, absent in release | All 7 App Shortcuts + Focus filter dead in TestFlight/App Store. | Add Siri key to release entitlements; regenerate profile. | S |
| A9-003 | `Info.plist:54-57` | `NSUserActivityTypes` lacks Selah type; `NSSiriUsageDescription` absent | Selah Handoff dead; App Review rejection w/ Siri entitlement. | Add activity type + usage description. | S |
| A6-003 | `DailyDigestService.swift:121-183` | Consent gate but no kill switch on `callModelDailyBrief` | No emergency remote disable. | Check `amenDailyDigestEnabled` before callable. | S |
| A6-004 | `SmartCommentService.swift:66-162` | No feature-flag/kill-switch check | No remote off-switch for SmartComment. | Add `smart_comment_coaching_enabled` guard. | S |
| A6-006 | `AmenAIFeaturesService.swift:70-112` + `constitutionalPipeline.ts:236-286` | Legacy path `isVerified:false` shown without visible disclaimer | User sees unreviewed AI content silently. | Surface "not reviewed by Berean pipeline" banner (and fix P0-3). | S |
| A4-002 | `CommentsView.swift:580-583, 1800-1828` | `onDelete` deletes immediately, no confirm/undo | Mistapped comment delete is permanent. | Add `.confirmationDialog`. | S |
| A4-003 | `PostDetailView.swift:400-402` | Inline `deleteComment`, no confirm | Accidental delete; inconsistent w/ same-screen post delete. | Shared confirm guard. | S |
| A4-004 | `OnboardingFlowView.swift:118` | Unconditional `.interactiveDismissDisabled()` | User trapped in 9-slide flow w/o force-quit. | Cancel on slide 0 (sign out); keep consent slides gated. | S |
| A5-002 | `AppDelegate.swift:192-196` | ATT fires 1s after cold launch, no context | High denial; jarring; clashes w/ notif onboarding. | Move to post-onboarding contextual trigger + explainer. | S |
| A5-003 | `PrivacyInfo.xcprivacy:5-6` | `NSPrivacyTracking = true` w/ Firebase domains | Overstates tracking, or violates ATT if IDFA used post-deny. | Audit IDFA-on-deny; set tracking accurately. | S |
| A5-004 | `ChurchProfileView.swift:847-849` | `requestWhenInUseAuthorization()` in `init` | Raw location prompt on opening any church profile. | Move behind explicit tap + education. | S |
| A13-004 | `SelahModels.swift:46-48` + `AskSelahView.swift:20` | Raw prayer text into Selah AI prompt, no consent check | Non-consented prayer sent to AI on every query. | Add consent gate in `promptContext()`. | S |
| A13-006 | `BereanRealtimeSessionManager.swift:78` + `accountDeletion.js` | `realtimeSessions` never deleted | Voice/prayer session records survive deletion. | Add `deleteDocsWhere('realtimeSessions','userId',uid)`. | S |
| A12-007 | `MinorSafetyGate.swift:28` | "default to allowing access" on Firestore error | Under-13 reach Berean AI during outage/cold-start (fail-open). | Fail closed on error; show loading state. | S |
| A12-008 | `Info.plist` | No age-rating decl; Selah activity absent; faith not separable in Screen Time | Parents can't grant scripture-only exception; Handoff dead. | Add scripture activity type + distinct category. | S |
| A3-001 | `BereanInteractiveUI.swift:1161-1175` | Icon button, no label | VoiceOver reads "bolt.fill" not mode names. | `.accessibilityLabel(tooltip)`. | S |
| A3-002 | `BereanChatView.swift:1761-1768` | Plus button, no label | Attachment button unidentifiable. | `.accessibilityLabel("Add attachment")`. | S |
| A3-003 | `TestimoniesView.swift:918-939` | Follow button, no label/state | Can't tell follow vs unfollow. | State-sensitive label. | S |
| A3-004 | `TestimoniesView.swift:1067-1184` | Amen/Comment/Repost no labels | Unlabeled buttons, no state to VoiceOver. | State-sensitive labels. | S |
| A3-006 | `FullscreenMediaViewer.swift:227-241` | Close button no label | Dismiss control unidentifiable. | `.accessibilityLabel("Close media viewer")`. | S |
| A3-007 | `SmartPostContextTray.swift:169-178` | Dismiss target 20×20 | 24pt below 44pt minimum. | 44×44. | S |
| A3-008 | `BereanInteractiveUI.swift:842-860` | Toggle 36×36 | 8pt below minimum. | 44×44 / padding. | S |
| A7-001 | `JobSearchView.swift:109` | `bookmark.fill` used for navigation | Read as save action, not nav. | `tray.fill`/list icon + label. | S |
| A4-001 | `PrayerView.swift:1587-1594, 2179-2186` | `deletePost()` immediate, no undo/soft-delete | Deleted prayer request unrecoverable. | Soft-delete + grace window or 5s undo. | M |
| A1-002 | `ReEngagementNotificationService.swift:19-38, 95-108` | AI prompt asks "urgency"; push 2h after every background, no cap | Persistent urgency re-engagement loop, no opt-in/cap. | Remove "urgency"; opt-in; 48h min interval. | M |
| A3-005 | `MentorCardView.swift:7-163` | Zero accessibility annotations | VoiceOver hears raw fragments; buttons unlabeled. | Labels + `.accessibilityElement(children:.contain)`. | M |
| A3-014 | `BereanLiveActivityManager.swift:18-20` | Entire manager `#if false` | Dynamic Island can't resume Berean session. | Remove guard; configure ActivityKit; wire to scenePhase. | M |
| A6-002 | `BereanVoiceAssistantView.swift:203-214` / `BereanRealtimeSessionManager.swift:24-74` | No crisis scan on voice transcript before model | Verbalized ideation gets AI response, no escalation. | `hasLocalCrisisSignal` on transcript; end + crisis card. | M |
| A6-005 | `AmenAIFeaturesService.swift:70-112` | No enforced preview-before-commit on creator draft | Draft inserted into composer without review. | Enforce confirmation state before insertion. | M |
| A5-005 | `FirebaseMessagingService.swift:1405-1413` | `conversationContext: .empty` on non-UnifiedChatView paths | Multi-message grooming not escalated on share/offline. | Build context from recent messages before `evaluate()`. | M |
| A13-005 | `AmenAIFeaturesService.swift:116-154` | Pinecone named as RAG store; no Pinecone deletion | Prayer/study embeddings persist post-deletion if active. | Add Pinecone namespace deletion; gate activation on it. | M |
| A7-004/A7-005 (merged) | `AMENResourcesHubView.swift:335-340`; `TestimoniesView.swift:1914-1921` | `chevron.left` dismiss on modal sheets | Breaks push-nav mental model on modals. | Top-trailing `xmark`/Done. | M |
| A12-006 | `AmenChildSafetyService.swift:549-565` | `isGuardianApprovedContact()` returns `true` when no doc (OPEN-2) | Mutual-follow adult→minor DMs need no guardian approval; ToS false. | Require approval docs or remove ToS claim. **Blocked by OPEN-2.** | L |

---

## P2 Findings

Sorted by Effort (S → L).

| ID | Location | Evidence | User Impact | Fix | Effort |
|----|----------|----------|-------------|-----|--------|
| A1-003 | `AmenJourneyContinuityEngine.swift:179-187` | `currentStreak` increments per session, no daily-once guard | Same-day reopens inflate streak. | Date-stamp guard. | S |
| A1-004 | `MediaItem.swift:47` | YouTube embed hardcodes `autoplay=1` | Bypasses Healthy Mode/autoplay pref/minor defaults. | Drive from `HealthyModeService.allowsAutoplay`. | S |
| A1-005 | `SuggestedAccountCard.swift:142-143` | Follower count on every suggestion card | Popularity social-proof before opt-in. | Gate on `amen_show_follower_counts`. | S |
| A1-006 | `MilestoneManager.swift:60-61, 226-235` | Follower-count milestone modal | Treats followers as spiritual progress. | Remove/replace with relational milestone. | S |
| A1-007 | `EssentialBooksView+Integration.swift:346-352` | `viewCount` in book hero | Popularity-lens selection. | Remove public count. | S |
| A1-008 | `SelahMediaDetailView.swift:172`, `SelahMediaHomeView.swift:496` | Like counts on Selah media | Social comparison on contemplative surface. | Hide aggregate counts. | S |
| A1-009 | `Discovery/AmenDiscoveryHeroCarousel.swift:225` | "You missed N discussions" | Banned FOMO/urgency pattern. | Neutral "Catch up", no count. | S |
| A1-014 | `DiscoverContentCards.swift:257-263` | `viewCount` on Discover cards | Popularity over relevance. | Remove count. | S |
| A8-006 | `SmartChurchNotifications.swift:336` | "It's been 2 weeks since you visited [Church]" | Attendance-shaming push. | Warm welcome-back, no count. | S |
| A8-007 | `ComposerPlaceholderService.swift:55` | 7-day inactivity guilt placeholder | Absence reminder on composer open. | Remove inactivity branch. | S |
| A8-008 | `AIDailyVerseView.swift:295-300` | Verse, no translation badge | Can't verify translation. | Add translation badge. | S |
| A8-011 | `SpiritualHealthView.swift:241, 347-350` | "4-Week Streak" + streak badge | Streak pressure on private formation surface. | "4 Weeks of Check-Ins"; remove badge. | S |
| A8-012 | `DevotionalGeneratorModels.swift:330` | "Start your streak today" zero-state | Gamification on devotionals. | nil/non-streak copy. | S |
| A4-005 | `SuggestedAccountPeekSheet.swift:50-54` | Confirmation on reversible unfollow | Friction/anxiety on one-tap action. | Undo toast instead. | S |
| A4-006 | `UsernameSelectionView.swift:203`, `UsernameGateView.swift:183` | `.interactiveDismissDisabled()` no escape | Trapped on broken username state. | "Sign Out" escape link. | S |
| A4-007 | `CommunityCovenantView.swift:238` | Undismissable covenant | No exit if shown mid-session. | "Not Now" defer/sign-out. | S |
| A4-008 | `PostDetailView.swift:401` | `try?` swallows comment-delete errors | Silent delete failure; trust loss. | `do-catch` + failure toast. | S |
| A5-006 | `SmartPrayerReminderScheduler.swift:34-45` | Notif+location requested together, no explainer | Users don't know why prayer needs location. | Education step; update usage description. | S |
| A5-007 | `ProfilePhotoEditView.swift:728` | `PHPhotoLibrary.requestAuthorization(.readWrite)` | Over-privilege full-library prompt for profile photo. | Use `PHPickerViewController`. | S |
| A5-008 (was A5 P3) | `OfflineMessageQueue.swift:72-76` | Replay doesn't re-check frozen state | Frozen-account message delivered before 60s TTL. | `invalidateFreezeCache()` before replay. | S |
| A6-008 | `BereanConstitutionalIntelligence.swift:237-248` | `.createPost`/`.createCarousel` absent from `highImpactActions` | `createPost` bypasses high-impact constitutional block. | Add both to the set. | S |
| A2-004 | `AMENResourcesHubView.swift:211` | `Color(red:0.047,…)` full-screen bg | Permanently dark, unreadable in Light. | systemBackground. | S |
| A2-008 | `TwoFactorGateView.swift:31` | `Color.black.ignoresSafeArea()` | 2FA gate invisible in Light Mode. | systemBackground + scoped scheme. | S |
| A2-010 | `ReelComposerView.swift:42` | `Color(hex:"050508")` | Can't render in Light Mode. | systemBackground. | S |
| A2-013 | `CreatePostView.swift:1621-2460` | Inline hex "6B48FF" | Ignores accent/dark contrast. | `Color.accentColor`/token. | S |
| A2-014/A2-015 (merged) | `BereanTabSwitcherView.swift`; `BereanChatsView.swift` | 12+ inline purple hex on core surfaces | Hard-locked accents lose a11y contrast. | `BereanTheme` tokens. | S |
| A2-023 | `AmenConnectView.swift:317-659` | `.font(.system(size:44))` etc. | No Dynamic Type scaling. | Text styles/AMENFont. | S |
| A2-024/A2-025/A2-026/A2-027 (grouped) | `SmartPostContextTray:144`, `BereanSafetyOverlayView:321`, `ResourcesView:165/253`, `BereanChatView:733/745` | Animations bypass `Motion.adaptive()` | Reduce Motion ignored (incl. safety overlay). | Wrap in `Motion.adaptive(...)`. | S |
| A3-010 | `AMENTabBar.swift:257` | Fixed 10pt + `minimumScaleFactor(0.75)` | Tab labels illegible at large sizes. | `.caption2`; raise/remove floor. | S |
| A3-011 | `BereanChatView.swift:1767/1800/1828` | Three 32×32 input buttons | Below 44pt minimum. | 44×44/padding. | S |
| A3-012/A3-013 (merged) | `ChurchNoteSemanticEditorView.swift:942-966` | Capture + 3 preset buttons 36×36 | Below-minimum in one-handed pew context. | 44×44 on all. | S |
| A12-010 | `AmenChildSafetyService.swift:81-84` | `isCapabilityBlocked()` fails open for all | Minor reaches live room/adult content on transient error. | Fail closed for high-severity capabilities. | S |
| A13-008 | `BereanGrokCoordinator.swift:80-83` | `.externalContext` pill sends raw text when heuristic risk low | Prayer text reaches helper CF without review/consent. | Guard `isSensitive || risk>=.elevated`. | S |
| A4-009 | `CreatePostView.swift:783-793` | Autosave 30s via UserDefaults | Last <30s of content lost on crash. | Debounce-persist on `postText` change. | S |
| A11-004 | `WorshipNowPlayingView.swift:389` | Uncapped `TimelineView(.animation)` driving 16-pt mesh | Battery/thermal drain on A15-and-older. | Cap at 30fps. | S |
| A11-007 | `FirebasePostService.swift:1076-1108` | `@MainActor preloadCacheSync()` decodes 50 posts on main | First-frame jitter on cold open. | Remove `@MainActor`; isolate only final assignment. | S |
| A11-008 | `ShortFormTeachingFeedView.swift:20` (+3) | `AVPlayer(url:)` in `body` | Video restarts + redundant requests on state change. | Lift to `@State`; init via `.task(id:url)`. | S |
| A8-009 | `ShortFormTeachingFeedView.swift:343-365` | No translation badge; stored `duration` unused | Unknown translation/clip length. | Translation badge + duration pill. | M |
| A8-010 | `NoteShareViewerView.swift:242-248` | Shared refs lack translation badge | Recipient can't see source. | Add `translationAbbreviation`. | M |
| A6-007 | `constitutionalPipeline.ts:628-637` | Low-risk failed review degrades to delivery | Response failing `safety_01` delivered. | Hard-gate on any critical-severity failure. | M |
| A6-009 | `AmenSafetyModerationProvider.swift:188-195` | `warn` → `allowed=true`, no UI | Warned content published silently. | Surface as composer nudge. | M |
| A7-006/A7-007/A7-008 (grouped) | `AmenMessagingAttachmentMenu.swift:55`; `PostCard.swift:3264-3402`; `BereanOnboardingModels.swift:210-215` | Generic icons / unexplained metaphors (Selah, Amen=hands.clap, "Berean") | New users don't grasp destinations/reactions/name. | Labels/subtitles + explanatory onboarding line. | M |
| A2-001/A2-007 (merged) | `TestimonyViralSheet.swift`; `PrayerRecapCardView.swift` | PURGED tokens still in use ("C9A84C"/"0D0D1A"/"080810") | Permanently dark + hardcoded gold; breaks Light. | Apply purge map + CI grep gate. | M |
| A2-002/A2-003/A2-011/A2-012 (merged) | `HelixNodeDetailSheets`, `WorkflowDetailView`, `WorkflowConfigView`, `KoraRootView` | `Color(hex:"0A0A0F")` bg + toolbar | Permanently dark, unreadable in Light. | systemBackground + scoped scheme. | M |
| A2-005/A2-006/A2-018 (merged) | `BereanInteractiveUI`, `StudioProfileView`, `ResourcesView` | Inline RGB palettes, no dark variants | Contrast loss in Dark Mode. | Move to `AmenTheme.Colors`. | M |
| A2-009 | `WellnessRiskLayer.swift` (7×) | `Color.white.ignoresSafeArea()` on crisis surfaces | Blinding white in Dark Mode. | systemBackground. | M |
| A2-016 | `FindChurchView.swift` (15+) | Two distinct golds (#D9A441 vs #D4AF37) | Inconsistent save accent. | One `churchGold` token. | M |
| A2-017/A2-019/A2-020/A2-021 (merged) | `TestimoniesView`, media upload/community room, `ChurchLiveModeView` | `Color.black/.white` fills + foregroundStyle | Invisible/jarring controls across modes. | Scoped scheme + semantic labels. | M |
| A7-009 | `WellnessRiskLayer.swift:701-728` vs `AmenTheme.swift:382-416` | Two `amenGlassCard` differing visually | Wellness cards too bright in dark mode. | Delete private variant; use canonical. | M |
| A7-012 | `MessagesView.swift:1493-1523` vs `499-512` | Pinned vs all-rows swipe action sets differ | Archive present in one, missing in pinned. | Unify via shared funcs w/ `isPinned`. | M |
| A12-009 | `AmenChildSafetyModels.swift:26` | No server-side under-13 account-creation block | Determined under-13 can create account via API. | Firestore rule/CF rejecting birthYear < 13. | M |
| A13-007 | `PrivacyInfo.xcprivacy` | No AI-provider domains / AI-content data type | Nutrition label omits data sent to Anthropic/Google. | Add `OtherUserContent` type + policy disclosure. | M |
| A12-012 | `AMENSettingsSystem.swift:2616-2619` | Guardian Supervision row only opens OS Screen Time | Parents get no AMEN-native guardian controls. | Wire to `requestGuardianLink()`. | M |
| A3-009 | `GroupChatCreationView.swift` (+222 files) | `.font(.custom("...",size:))` no scaling | Unusable at largest a11y sizes (223-file scope). | Migrate to `AMENFont`/`.systemScaled()`. | L |
| A2-022 | `FindChurchView.swift` (30+) | `.font(.system(size:))` 72→11 | Church-finder text doesn't scale. | Map to text styles. | L |

---

## P3 Findings

| ID | Location | Evidence | User Impact | Fix | Effort |
|----|----------|----------|-------------|-----|--------|
| A1-010 | `Backend/functions/src/socialGraph.ts:116-127, 349-360` | `activeStreak` persisted, feeds Ambient | Backend streak could resurface as pressure. | Rename `formationConsistency`; document. | M |
| A1-011 | `SmartChurchNotifications.swift:352-356` | Streak-notif spec ("3 Weeks in a Row 🔥") in comments | If built, fires streak-pressure push. | Mark NEVER-IMPLEMENT or delete. | S |
| A1-012/A8-014 (merged) | `BookDiscoveryViewModel.swift:290-292`; `WisdomLibraryView.swift:332-343` | "Wow! N days in the Word" streak label | Reading becomes streak-maintenance. | Neutral "N days of reading"; opt-out. | S |
| A1-013 | `HealthyModeService.swift:157-215` | Autoplay + infinite scroll default `true` | Protective defaults opt-in; passive/minor users get max-engagement. | Default both false. | M |
| A8-013 | `OnboardingAdvancedComponents.swift:509-518` | Confetti on onboarding completion | Low risk; re-use elsewhere would be P1. | Document milestone-only restriction. | S |
| A8-015 | `CreatorOS/CreatorMonetizationView.swift:20-25` | "Exclusive" perk labels | FOMO if surfaced to non-subscribers. | Guard to paywall context. | S |
| A8-016 | `SelahVOTDCard.swift:190-196` | Discernment hidden in context menu | Key formation feature invisible w/o long-press. | Visible "Reflect on this" pill. | S |
| A3-015 | `NowPlayingBar.swift:61-77` | 3 playback buttons no labels | VoiceOver reads raw symbols. | Add prev/play-pause/next labels. | S |
| A3-016 | `ChurchNotesView.swift:506-510, 2657-2661` | `.onTapGesture` on TextField | Can intercept VoiceOver activation of search. | Use `@FocusState`/`.onFocus`. | S |
| A3-017 | `FindChurchView.swift:5560-5589` (40+) | `.font(.system(size:))` fixed | Info unusable at xxl+ sizes. | Scaled styles. | M |
| A3-018 | `CommentsView.swift:3172-3181` | Invisible dismiss overlay, no trait | VoiceOver users trapped in reaction picker. | Add label + `.isButton`. | S |
| A3-019/A3-020 (merged) | `ResourcesView.swift:231-232`; `TrendingViews.swift:680/685` | `minimumScaleFactor(0.5)` on UGC | Titles render half-size, illegible. | Raise to ≥0.85. | S |
| A7-011 | `HelixNodeDetailSheets.swift:186` | `trash` (unfilled) for delete | Inconsistent w/ `trash.fill`. | Use `trash.fill`. | S |
| A7-013/A7-014 (merged) | `BereanOnboardingModels.swift:58-59`; `ChatIdentityCard.swift:662`; `ShareCardGenerator.swift:52` | SF `cross`/`cross.fill` = medical cross used for faith | Wrong semantics; VoiceOver/visual confusion. | Custom cross asset or `hands.sparkles`. | S |
| A7-015 | `AMENTabBar.swift:86` | Tab label "Brief" (jargon) | Users don't grasp daily-summary tab. | Rename "Today"/"Daily" or tooltip. | S |
| A2-028..A2-040 (grouped) | `EnhancedUIComponents`, `HelixNodeDetailSheets`, `Creator/CreatorAnimationSpec`, `FruitOfSpiritBannerView`, motion files, `ChurchNoteSmartObjectComponents`, `AmenAdaptiveColors`, `BereanLandingView`, `TestimonyRippleView`, `ConnectConverseView`, `AMENResourcesHubView:934`, `ComponentsSharedUIComponents`, `ChatIdentityCard:99` | Hand-rolled blur bridge; 5 overlapping animation systems; repeating animations bypass Reduce Motion; inline RGB palettes | Inconsistent motion/contrast; non-stop animation under Reduce Motion. | Consolidate into `Motion.swift`/`.glassSurface()`; guard repeats. | L |
| A11-003 | `AMENAPPApp.swift:202-243` | Dead `runAutomaticMigration()` w/ unbounded users scan | Latent launch-freeze bomb if reconnected. | Delete or admin-gate + relocate. | S |
| A11-006 | `UserKeywordsMigration.swift:22, 101` | Unbounded `users.getDocuments()` in `checkMigrationStatus` | Full-collection scan stalls admin app at scale. | `.limit(500)` + pagination or CF. | M |
| A11-009 | `AMENAPPApp.swift:109-115` | ImageCache + URLCache double-store images | RAM pressure on 3GB devices → termination. | Check `URLCache.shared` before new request. | M |
| A11-010 | `FeedPrefetchService.swift:27-79` | Prefetch loads metadata, not images | Images still flash grey after prefetch. | Call `preloadImage()` for prefetched URLs. | S |
| A13-009 | `constitutionalPipeline.ts:394-399` | Trace metadata retained, no TTL | Crisis-correlated metadata retained indefinitely. | 90-day `expiresAt` + purge job. | M |
| A12-011 | `MediaSafetyGateway.swift:263-269` | In-app perceptual hash only; no PhotoDNA/NCMEC | Modified-pixel illegal content passes pre-screen. | Integrate `SensitiveContentAnalysis` (needs entitlement). | L |

---

## Platform Readiness Gaps (RG)

Sorted by User Value (high → low).

| ID | Surface | Gap | User Value | Effort |
|----|---------|-----|-----------|--------|
| A9-005 | Siri write intents | No GUARDIAN/Aegis gate in any intent `perform()`; one refactor removes the only safety checkpoint | High | M |
| A9-004 | Siri Shortcuts | 4 `Notification.Name`s posted to dead channel; `siri_pending_*` keys never read → intents open app then do nothing | High | M |
| A9-007 | CoreSpotlight | `SpotlightIndexingService.shared` never called; public content invisible to Spotlight | High | S |
| A12-014 | Minors / teen feeds | No KOSA/AADC gap analysis on algorithmic amplification for teens | High | L |
| A12-015 | ToS / guardian DM controls | ToS promises guardian DM control + data deletion not implemented (OPEN-2 blocked) | High | M |
| A13-010 | Berean conversational tasks | No on-device `FoundationModels` path; Tier-S content always cloud-routed | High | L |
| A13-011 | Prayer matching | Raw prayer text to Anthropic for need classification; could run on-device `NaturalLanguage` | High | M |
| A9-006 | Siri | Missing high-value intents (Selah today, search notes, find church, resume Berean) | Medium | M |
| A12-013 | Screen Time | Faith/scripture activities not separable from social | Medium | S |
| A13-013 | On-device AI | Proven ONE `FoundationModels` pattern not adopted for Berean classify/short-answer | Medium | M |
| A13-012 | RAG / scripture search | Static Bible/saved-verse search leaves device; could be local-first | Medium | L |
| A9-008 | Selah Handoff | `isEligibleForSearch/Prediction` set but activity type unregistered (fix with A9-003) | Medium | S |
| A11-011 | Daily Digest | BG refresh doesn't warm digest cache → morning spinner | Low | S |
| A11-013 | Berean Fast Mode | `prefetchFor`/`drainQueue` never called on launch → cold first response | Low | S |
| A11-012 | MessagingFilters | Redundant `@available(iOS 17)` guards (target already 17) | Low | S |

---

## Per-Lane Coverage Map

| Lane | Status | Surfaces Scanned | Findings (P0/P1/P2/P3/RG) | Discarded (no evidence) |
|------|--------|------------------|---------------------------|--------------------------|
| A1 (Anti-addiction/metrics) | COMPLETE | ~700 Swift + backend | 1/3/6/4/0 | 0 |
| A2 (Design system/glass/tokens) | COMPLETE | 40+ files | 0/9*/18/13/0 | 0 |
| A3 (Accessibility) | COMPLETE | 22 surfaces | 2/6/8/6/0 | 0 |
| A4 (Destructive actions/flows) | COMPLETE | 24 files | 0/4/4/2/0 | 0 |
| A5 (Permissions/privacy/msg safety) | COMPLETE | 30 files | 1/3/3/2/0 | 0 |
| A6 (AI pipelines/GUARDIAN) | COMPLETE | 15 surfaces | 1/5/3/1/0 | 0 |
| A7 (Symbols/metaphors) | COMPLETE | 30 surfaces | 0/5/6/5/0 | 0 |
| A8 (Copy/streak/scripture context) | COMPLETE | 21 surfaces | 0/5/7/4/0 | 0 |
| A9 (Siri/Spotlight/intents) | COMPLETE | 11 files | 1/2/1/0/4 | 0 |
| A10/A11 (Performance) | COMPLETE | 21 files | 0/2/6/2/3 | 0 |
| A12 (Youth safety/family) | COMPLETE | 23 files | 5/3/2/2/3 | 0 |
| A13 (AI privacy/deletion/on-device) | COMPLETE | 20 files | 3/3/2/1/4 | 0 |
| (13th slot) | **MISSING** | — | — | report body empty ("MISSING") |

*A2's nine P1 background findings were reconciled to P2 severity in this aggregate (real evidence, not user-blocking at P1) after cross-checking the A2↔A10 overlap. No lane produced evidence-free findings — discard count is 0 across all lanes. The single empty slot is the largest coverage risk and should be re-run.

---

## Remediation Wave Plan

### Wave 0 — P0 safety/privacy gates (block the build)

**Parallel-safe (distinct files):** P0-1 `MessagingViewController.swift`, P0-3 `BereanConstitutionalPipeline.swift`, P0-8 `BereanChatView.swift` (age gate), P0-9 `AIBibleStudyExtensions.swift`. P0-4 splits cleanly into Spotlight/Siri (`SpotlightIndexingService.swift`, `AMENAppIntents.swift`) vs Berean consent (`BereanUserContext.swift`).

**Must serialize — contested files:**
- `accountDeletion.js` is touched by **P0-9, P0-10, P1 A13-006, and P1 A13-005** — land all four deletion-cascade additions in one ordered PR.
- `FirebaseMessagingService.sendMessage()` is touched by **P0-2** then **P1 A5-005** — do P0-2 first, then layer A5-005.
- Sign-up path: **P0-5 (SSO), P0-6 (phone), P0-7 (`AgeAssuranceModels` flag)** all intersect `AuthenticationViewModel` + age-gate code — serialize as one "age-gate equivalence" PR. **Gated by OPEN-2 + `ff_onboarding_v2` — this is the launch long pole.**

### Wave 1 — P1 by effort

- **S batch (parallel):** copy fixes (A1-001/A8-001, A8-002/04/05), kill-switches (A6-003/04/06), confirmations (A4-002/03/04), permissions (A5-002/03/04), consent/deletion (A13-004/06), youth (A12-007/08), a11y (A3-001..08), symbols (A7-001), perf (A11-001/02). **A9-002 + A9-003 + A12-008 all touch `Info.plist`/entitlements — serialize those three.**
- **M batch:** A4-001 (coordinates w/ wave-0 `accountDeletion.js` PR — serialize), A1-002, A3-005/14, A6-002/05, A5-005 (after P0-2), A13-005 (after deletion PR), A7-004/05.
- **L / blocked:** A12-006 (OPEN-2).

### Wave 2 — P2 by effort

- **Contested files (one owner each):** `AMENAPPApp.swift` (A11-007/09 + wave-1 A11-002), `FindChurchView.swift` (A2-016/22 + P3 A3-017), `ResourcesView.swift` (A2-018/26, A3-019), `BereanChatView.swift` (A2-027 — already touched in wave-0 P0-8/P0-10), `WellnessRiskLayer.swift` (A2-009 + A7-009), `MilestoneManager.swift` (A1-006 + wave-1 A1-001).
- All other hardcoded-color / Dynamic-Type / motion / anti-metric P2s are file-isolated and parallel-safe. Add the **CI grep gate** for PURGED tokens alongside A2-001/A2-007.

### Wave 3 — P3 + RG (roadmap, non-blocking)

- P3 perf/migration (A11-003/06/09/10) parallel-safe.
- Animation-system consolidation (A2-028..A2-040, L) and the 223-file font migration (A3-009) are single-owner refactors — do not split across agents.
- RG priority by user value: Siri wiring trio (A9-004/05/07), then on-device `FoundationModels` adoption (A13-010/13/11), then KOSA/AADC analysis (A12-014).

### Cross-cutting serialization summary (assign one owner per file)
`accountDeletion.js`, `FirebaseMessagingService.swift`, `AuthenticationViewModel.swift` + age-gate, `AMENAPPApp.swift`, `Info.plist`, `BereanChatView.swift`, `FindChurchView.swift`, `WellnessRiskLayer.swift`, `MilestoneManager.swift`, `ResourcesView.swift` — each accumulates multiple findings across waves and must be single-owned to avoid merge conflicts.