# AMEN App — Implementation Audit
# Generated: 2026-05-10

This document covers every file created or modified across recent implementation sessions:
what each file does, its user-facing flow, its wiring status, and any remaining gaps.

---

## STATUS KEY
- WIRED       — reachable from a user-facing surface; compiles into the build
- GAP         — file exists, types/views are defined, but nothing calls them yet
- INTERNAL    — library/model/service; wired transitively through callers
- NEW SESSION — wired in the most recent session (this run)

---

## PART 1 — IOS SWIFT FILES

### 1.1 FEED & HOME

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/SacredFeedModes.swift` | Defines `SacredFeedMode` enum (encourage, reflect, learn, connect, recover, healthyMix) with display names and icons; maps to HeyFeed ranking adjustments | User picks a feed mode; ranking layer filters/boosts posts toward that spiritual intent | **GAP — `SacredFeedMode` has no caller. Wire: add a mode picker in `YourFeedView.swift` or `HeyFeedActivePillsBar`** |
| `AMENAPP/HeyFeedActivePillsBar.swift` | Horizontal scrolling pill bar showing active contextual filters over the feed | Displayed inside `AMENAPP/OpenTableView.swift` above the feed list | WIRED (`OpenTableView.swift:121`) |
| `AMENAPP/SundayHomeView.swift` | Dedicated Sunday/Lord's Day home layout with Selah media, rest mode prompts, and church context | Shown from `ContentView.swift` and `AMENAPP/HomeView.swift` when it's Sunday and rest mode is active | WIRED (`ContentView.swift`, `AMENAPP/HomeView.swift`) |
| `AMENAPP/SundayRestModeSheet.swift` | Bottom sheet explaining Sunday Rest Mode, lets user set/dismiss the policy | Presented from `SundayHomeView` and `AMENAPP/HomeView.swift` | WIRED |
| `AMENAPP/RestModeGate.swift` | ViewModifier that gates content behind the rest mode policy; shows `SundayRestModeSheet` if active | Applied to feed/tab surfaces during rest hours | WIRED (`ContentView.swift`, `AMENAPP/HomeView.swift`) |
| `AMENAPP/RestModePolicy.swift` | Model + local persistence for the user's rest mode settings (enabled, start time, end time, days) | Read by `RestModeGate` and synced to backend via `restModeEvaluator` Cloud Function | WIRED (via `RestModeGate`) |
| `AMENAPP/DynamicReplyPreview.swift` | Animated inline preview of related posts underneath a reply composer | Shown inside `AMENAPP/LiquidReplyPreviewChip.swift` which is in `PostCard` / `PostDetailView` | WIRED |
| `AMENAPP/LiquidReplyPreviewChip.swift` | Glass-morphic chip showing a single reply preview candidate | Used in `PostCard.swift` and `PostDetailView.swift` | WIRED |
| `AMENAPP/LiquidReplyPreviewRotator.swift` | Animates cycling through multiple reply preview chips | Used in `PostCard.swift` | WIRED |
| `AMENAPP/DynamicAvatarCluster.swift` | Overlapping avatar stack for showing multiple participants | Used in `AMENAPP/LiquidReplyPreviewChip.swift` and `AIDailyVerseView.swift` | WIRED |
| `AMENAPP/PostAILabelSystem.swift` | `PostAILabelPill` view (tappable disclosure capsule) and `AILabelDetailSheet` explaining AI usage | Pill shown in `PostCard.swift:2077` and `AMENAPP/PostCardAuthorBylineView.swift:87` | WIRED |
| `AMENAPP/PostAIUsage.swift` | Model struct `PostAIUsage` with fields for AI label type, features used, confidence | Consumed by `PostAILabelSystem.swift` and `PostCard.swift` | INTERNAL |
| `AMENAPP/PostLifecycleBadge.swift` | Small badge indicating post lifecycle state (draft, scheduled, published, archived) | Displayed in `AMENAPP/PostCardRenderModel.swift` and `PostsManager.swift` | WIRED |
| `AMENAPP/PostWhyThisSheet.swift` | "Why am I seeing this?" explanation sheet with feed context signals | Presented from `PostCard.swift` via long-press context menu | WIRED (`PostCard.swift`) |
| `AMENAPP/PostAfterPrayerSheet.swift` | Sheet shown after user prays for a post — suggests follow-up actions (add to notes, save, share) | Presented from `PostCard.swift` after prayer interaction | WIRED (`PostCard.swift`) |
| `AMENAPP/PostCardReportSheet.swift` | Report content sheet for posts, with reason picker and optional note | Presented from `PostCard.swift` context menu | WIRED (`PostCard.swift`) |
| `AMENAPP/PostCardPollView.swift` | Poll rendering component embedded inside a post card | Shown by `PostCard.swift` when `post.pollOptions` is non-nil | WIRED (`PostCard.swift`) |

### 1.2 CREATION (COMPOSER)

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/AMENAPP/CreatePostIntentSystem.swift` | Defines `PostComposerIntent` enum (encourage, reflect, prayerRequest, shareTestimony, teach, discuss) | Author selects intent in the composer; shapes feed distribution | **GAP — `PostComposerIntent` has no external callers. Wire: read it in `CreatePostView.swift` via `CreatePostIntentRow` and write to `post.postIntent`** |
| `AMENAPP/CreatePostIntentRow.swift` | UI row letting the author pick their `PostComposerIntent` | Embedded inside `CreatePostView.swift` | WIRED (`CreatePostView.swift`) |
| `AMENAPP/CreatePostAudienceHintRow.swift` | Row showing audience hint (Public / Followers / Church only) based on selected visibility | Embedded inside `CreatePostView.swift` | WIRED (`CreatePostView.swift`) |
| `AMENAPP/AmenAudioComposerSheet.swift` | Voice/audio recording sheet for attaching audio to a post | Presented from `CreatePostView.swift:1092` | WIRED |
| `AMENAPP/LiquidGlassAlignmentBanner.swift` | Animated banner shown when AI detects potential alignment flags in composed text | Shown in `CreatePostView.swift:475` and `CommentsView.swift:862` | WIRED |
| `AMENAPP/LiquidGlassUploadCapsule.swift` | Progress capsule during media upload with glass morphic styling | Shown in `CreatePostView.swift:881` | WIRED |
| `AMENAPP/AmenDraftPersistenceService.swift` | Cross-device draft sync to Firestore; saves/loads draft text by composer key | Used in `AmenAdaptiveComposerView.swift` and `FirebasePostService.swift` | WIRED |

### 1.3 BLESS LATER SYSTEM

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/AMENAPP/BlessLaterSystem.swift` | Defines `BlessLaterTiming` enum and `BlessLaterEntry` model + `BlessLaterService` singleton for deferring engagement with posts | User swipes or long-presses a post and selects "Bless Later" with a timing (tonight, tomorrow morning, after church, next week) | **GAP — `BlessLaterTiming`, `BlessLaterService`, and `BlessLaterView` have no callers. Wire: add a "Bless Later" action to `PostCard.swift` context menu calling `BlessLaterService.shared.schedule(post:timing:)`; surface `BlessLaterView` from a tab or notification entry point** |

### 1.4 CHAPEL INBOX SYSTEM

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/AMENAPP/ChapelInboxSystem.swift` | Defines `ChapelInboxLane` enum (all, forMe, needsPrayer, reflectLater, fromMyChurch, encouragement, priorityVoices) + `ChapelInboxClassifier` + `ChapelInboxView` | A spiritually-framed notification/post inbox with lane-based triage; user browses lanes like "Needs Prayer" or "From My Church" | **PARTIAL — `ChapelInboxLane` is referenced in `AMENAPP/HomeView.swift:262` but `ChapelInboxView` itself has no caller. Wire: present `ChapelInboxView` as a sheet or tab destination from `AMENAPP/HomeView.swift` or `AMENNotificationsView`** |

### 1.5 MESSAGING (UnifiedChatView system)

All the following are wired into `UnifiedChatView.swift` unless noted otherwise.

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/AmenSmartPillRow.swift` | Horizontal row of smart action pills above the composer (e.g. Pray, Verse, Save, Translate) | Shown at `UnifiedChatView.swift:401` above keyboard | WIRED |
| `AMENAPP/AMENAPP/AmenSmartPillModels.swift` | Model types: `AmenSmartPill`, `AmenSmartPillType`, `AmenSmartPillAction` | Used by `AmenMessagingIntelligenceCoordinator` | INTERNAL |
| `AMENAPP/AMENAPP/AmenSmartPillPriorityEngine.swift` | Ranks and selects which smart pills to show based on message context | Called by `AmenMessagingIntelligenceCoordinator` | INTERNAL |
| `AMENAPP/AMENAPP/AmenSmartPillEligibilityContext.swift` | Determines eligibility for each pill type from message content signals | Called by `AmenSmartPillPriorityEngine` | INTERNAL |
| `AMENAPP/AmenMessagingIntelligenceCoordinator.swift` | Orchestrates smart pills, read receipts, typing indicators, and translation in chat | Used in `UnifiedChatView.swift` as `@StateObject` | WIRED |
| `AMENAPP/AMENAPP/AmenMessagingAnalytics.swift` | Static analytics tracker for messaging events (pill taps, media actions, reactions) | Called throughout `UnifiedChatView.swift` | INTERNAL |
| `AMENAPP/AMENAPP/AmenMessageContextMenuAction.swift` | Enum of all context menu actions for messages (reply, save, react, translate, report, etc.) | Consumed by `AmenMessagingIntelligenceCoordinator` | INTERNAL |
| `AMENAPP/AMENAPP/AmenMessagingFeatureAvailability.swift` | Feature flag overrides for messaging capabilities (per-conversation entitlements) | Checked by `AmenMessagingIntelligenceCoordinator` | INTERNAL |
| `AMENAPP/AmenMessageSaveActionsSheet.swift` | Sheet for saving a message (to Selah, Church Notes, Reminders, etc.) | Presented from `UnifiedChatView.swift` via `pendingSaveMessage` | WIRED |
| `AMENAPP/AmenMessageSaveService.swift` | Executes save-to-destination logic (Firestore writes) for message saves | Called by `AmenMessageSaveActionsSheet` | INTERNAL |
| `AMENAPP/AMENAPP/AmenMediaActionOverlay.swift` | Floating action tray over image/video messages (save, share, save to Selah, add to notes) | Shown from `UnifiedChatView.swift` when `activeMediaActionMessage` is set | WIRED |
| `AMENAPP/AMENAPP/AmenApprovalReviewCard.swift` | Card for reviewing a message that requires moderation approval | Shown in `UnifiedChatView.swift:244` | WIRED |
| `AMENAPP/AMENAPP/AmenVoiceTranscriptPanel.swift` | Panel showing live voice transcript while recording | Shown in `UnifiedChatView.swift:654` | WIRED |
| `AMENAPP/AmenTranslationMessageView.swift` | Displays translated message text inline below original | Shown in `UnifiedChatView.swift` | WIRED |
| `AMENAPP/AmenMessageArrivalModifier.swift` | ViewModifier for message arrival animation (slide + fade) | Applied in `UnifiedChatView.swift` to new messages | WIRED |
| `AMENAPP/AMENAPP/AmenMessageReadReceiptChip.swift` | Small "seen" chip shown below sent messages | Shown in `UnifiedChatView.swift` | WIRED |
| `AMENAPP/AmenSafetyNudgeCard.swift` | In-chat safety resource card surfaced by the Safety OS | Shown in `UnifiedChatView.swift` | WIRED |
| `AMENAPP/AMENAPP/AmenChatTypingIndicator.swift` | Animated typing indicator ("...") | Shown in `UnifiedChatView.swift` | WIRED |
| `AMENAPP/AMENAPP/AmenCatchUpTray.swift` | Bottom tray for catching up on missed messages (AI summarized) | Shown in `BereanCommunicationHubView.swift` and `AMENAPP/HomeView.swift` | WIRED |
| `AMENAPP/AMENAPP/AmenCommandPaletteView.swift` | Slash-command palette for the chat composer | Shown in `AMENAPP/HomeView.swift` | WIRED |
| `AMENAPP/AMENAPP/AmenContextMenuBubble.swift` | Message context menu overlay driven by `AmenMessageContextMenuPresenter.shared` | Wired in `UnifiedChatView.swift` at layer 3 | WIRED |
| `AMENAPP/AMENAPP/AmenContextMenuTransition.swift` | `.amenContextMenuBloom(isPresented:)` ViewModifier for bloom animation | Used by `AmenContextMenuBubble.swift` | INTERNAL |
| `AMENAPP/AMENAPP/AmenChatComposerGlassStyle.swift` | `.amenComposerFocusGlass(isFocused:)` ViewModifier for the composer bar | Applied in `UnifiedChatView.swift:497` | INTERNAL |
| `AMENAPP/AMENAPP/AmenDraftPersistenceService.swift` | Persists draft text across app restarts and devices | Used in `AmenAdaptiveComposerView` and `AmenCommunicationHubView` | WIRED |
| `AMENAPP/AMENAPP/CommunicationOS/BereanCommunicationHubView.swift` | Full communication hub: chats, chapel inbox, catch-up tray | Wired in main navigation | WIRED |

### 1.6 CONTEXTUAL REACTIONS

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/AMENAPP/AmenContextualReactionModels.swift` | Model types for contextual reactions (`AmenReactionContext`, `AmenContextualReactionSet`) | Used by reaction engine and button | INTERNAL |
| `AMENAPP/AMENAPP/AmenContextualReactionLayer.swift` | View layer rendering floating reaction options above content | Used in `CreatePostView.swift`, `PostDetailView.swift`, `NotificationPostDetailView.swift` | WIRED |
| `AMENAPP/AMENAPP/AmenContextualReactionEngine.swift` | Selects contextually appropriate reactions based on post content + spiritual context | Used by `AmenContextualReactionButton` | INTERNAL |
| `AMENAPP/AMENAPP/AmenContextualReactionEffectHost.swift` | Hosts particle/haptic effects when a reaction fires | Used by `AmenContextualReactionButton` | INTERNAL |
| `AMENAPP/AMENAPP/AmenContextualReactionButton.swift` | Reaction trigger button that presents the contextual layer | Used in `PostCard.swift`, `PostDetailView.swift` | WIRED |
| `AMENAPP/AMENAPP/AmenContextualReactionPreview.swift` | Preview harness for UI testing contextual reactions | Wired in `AMENAPPApp.swift:180` via `--ui-test-contextual-reactions` launch argument | WIRED (UI test) |
| `AMENAPP/AMENAPP/AmenHiddenReactionRing.swift` | Hidden reaction ring that appears on long-press of an existing reaction | Used in `AMENAPP/AmenContextualReactionButton.swift` | INTERNAL |
| `AMENAPP/AmenReactionMicroAnimation.swift` | Micro-spring animation that plays when reaction is confirmed | Used in `AMENAPP/AmenContextualReactionButton.swift` | INTERNAL |
| `AMENAPP/AmenReactionMorphIcon.swift` | Icon morphs from default to selected reaction glyph | Used in `AMENAPP/AmenContextualReactionButton.swift` | INTERNAL |
| `AMENAPP/AmenSeasonalReactionTheme.swift` | Applies seasonal/liturgical theming to reaction icons and colors | Used in `AMENAPP/AmenContextualReactionEngine.swift` | INTERNAL |
| `AMENAPP/AmenSafetyOSReactionEngine.swift` | Validates reactions against Safety OS rules (no reactions to reported/flagged content) | Used in `AMENAPP/AmenContextualReactionEngine.swift` | INTERNAL |
| `AMENAPP/AMENAPP/AmenMagicWordComposerObserver.swift` | Watches composer text for trigger words and surfaces contextual reactions | Used in `CreatePostView.swift:232` as `@StateObject` | WIRED |
| `AMENAPP/AMENAPP/AmenLiquidGlassSpiritualReactionSimulation.swift` | Liquid glass physics simulation for reaction particle effects during worship | Used in `AMENAPP/AmenContextualReactionEffectHost.swift` | INTERNAL |

### 1.7 SELAH MEDIA OS

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/SelahMediaHomeView.swift` | Main Selah media browsing surface — curated spiritual playlists, sermons, worship | Navigated from `AMENAPP/HomeView.swift` | WIRED |
| `AMENAPP/SelahMediaDetailView.swift` | Full-screen media detail for Selah items with playback, notes, and save actions | Presented from `SelahMediaHomeView` | WIRED |
| `AMENAPP/SelahMediaModels.swift` | Model types: `SelahMediaItem`, `SelahMediaType`, `SelahPlaylist` | Used throughout Selah OS | INTERNAL |
| `AMENAPP/SelahMediaService.swift` | Firestore service fetching and caching Selah media items | Used by `SelahMediaHomeView` | INTERNAL |
| `AMENAPP/SelahAIConciergeView.swift` | AI-powered concierge that recommends spiritual media based on user's current state | Shown from `AMENAPP/SelahMediaHomeView.swift` | WIRED |
| `AMENAPP/SelahContextWindowOverlay.swift` | Overlay showing Berean context window for currently playing media | Shown from `SelahMediaDetailView` | WIRED |
| `AMENAPP/SelahContinueView.swift` | Resume-watching card for in-progress Selah sessions | Shown from `SelahMediaHomeView` | WIRED |
| `AMENAPP/SelahDeepModeView.swift` | Immersive full-screen deep study/worship mode — removes all UI chrome | Shown from `SelahMediaHomeView.swift` | WIRED |
| `AMENAPP/SelahIntelligenceEngine.swift` | Ranks and curates Selah content based on spiritual state, time of day, liturgical calendar | Used by `SelahMediaHomeView` | INTERNAL |
| `AMENAPP/SelahMemoryView.swift` | Shows user's Selah session history and saved moments | Shown from `SelahView.swift` and `BereanChatView.swift` | WIRED |
| `AMENAPP/SelahProgressiveDisclosurePanel.swift` | Expandable panel revealing deeper study options as user engages | Used in `AMENAPP/SelahMediaDetailView.swift` | WIRED |
| `AMENAPP/SelahSessionShapingCard.swift` | Card letting user set their session intent before Selah begins | Shown from `SelahMediaHomeView` | WIRED |

### 1.8 BIBLICAL ALIGNMENT & TRUST

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/BiblicalAlignmentModels.swift` | Models: `AlignmentStatus`, `AlignmentFlag`, `AlignmentSuggestion`, `AlignmentProfile` | Used by alignment service and view model | INTERNAL |
| `AMENAPP/BiblicalAlignmentService.swift` | Calls `checkBiblicalAlignment` Cloud Function; caches results | Used by `BiblicalAlignmentViewModel` | INTERNAL |
| `AMENAPP/BiblicalAlignmentViewModel.swift` | Drives alignment UI — checks content, surfaces suggestions, saves corrections | Used by `WeeklyAlignmentSummaryView` and `BereanAlignmentSettingsView` | WIRED |
| `AMENAPP/WeeklyAlignmentSummaryView.swift` | Weekly summary card of alignment activity, patterns, improvements | Shown in `AMENAPP/BereanStudyHomeView.swift:949` and `SettingsDestinationViews.swift:1481` | WIRED |
| `AMENAPP/CorrectTheAIView.swift` | Form for submitting a correction when user disagrees with an AI alignment label | Shown from `BereanChatView.swift:855` and `CreatePostView.swift:371` | WIRED |
| `AMENAPP/SpiritualDiscernmentPromptView.swift` | Full-screen prompt surfacing discernment questions when content pattern is detected | Shown from `BereanChatView.swift:893` and `CreatePostView.swift:402` | WIRED |
| `AMENAPP/KnowledgeIntegrityBadgeView.swift` | Badge indicating a knowledge item has been community-verified for biblical accuracy | Used in `CommentsView.swift` and `AMENAPP/OpenTableView.swift` | WIRED |
| `AMENAPP/LiquidGlassAlignmentBanner.swift` | Animated banner for alignment warnings during composition | Used in `CreatePostView.swift:475` and `CommentsView.swift:862` | WIRED |
| `AMENAPP/TrustInfrastructureService.swift` | Loads `verifiedMinistryIds` and `moderationCouncilQueueCount` from Firestore | Warm-started in `AMENAPPApp.warmUpServices()` | WIRED (NEW SESSION) |
| `AMENAPP/ChurchTrustSafetyService.swift` | Backend calls for church claim/verify, profile updates, and moderation queue | Called by `ChurchClaimVerifySheet` in `ChurchDetailExperience.swift` | WIRED (NEW SESSION) |
| `AMENAPP/BereanChurchGroundingService.swift` | Fetches grounded church answers from the Church Grounding backend | Used in `ChurchDetailExperience.swift` and `BereanChatView.swift` | WIRED |
| `AMENAPP/BereanOperatingLayer.swift` | Swift client for `generateBereanOperatingResponse` callable — full context pipeline | Used in many views including `BereanChatView`, `ChurchDetailExperience` | WIRED |
| `AMENAPP/BereanAlignmentSettingsView.swift` | Settings screen for user's alignment preferences and profile | Navigated from `SettingsDestinationViews.swift` | WIRED |
| `AMENAPP/BereanSimpleModeView.swift` | Simplified Berean chat interface without advanced features | Shown from `SettingsDestinationViews.swift:1492` | WIRED |

### 1.9 ADVANCED LIQUID GLASS SYSTEM

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/AmenAdvancedLiquidGlassSystem.swift` | Defines `AtmosphericBlurEngine` + `AmenAdaptiveGlassViewModifier` + `.adaptiveGlass(state:)` ViewModifier. Blends quiet mode, prayer mode, time-of-day, and worship state into dynamic glass opacity/blur | Applied to glass surfaces when atmospheric responsiveness is desired | **GAP — `.adaptiveGlass(state:)` has no callers. Wire: apply to `SelahMediaHomeView`, `BereanChurchContextSheet`, and any other ambient glass surface that should respond to worship/prayer state** |
| `AMENAPP/AdaptiveLiquidGlassHeader.swift` | `AdaptiveLiquidGlassHeaderSurfaceModifier` + `.adaptiveLiquidGlassHeaderSurface(progress:cornerRadius:)` ViewModifier + `AdaptiveHeaderScrollTracker` + `AdaptiveHeaderMetrics` | Used in `ProfileView`, `FindChurchView`, `AmenDiscoverView`, `ChurchDetailExperience` for scroll-responsive glass headers | WIRED |
| `AMENAPP/AmenLiquidGlassSurface.swift` | Base liquid glass surface component used in `AmenSmartPills.swift` | Used in `AmenSmartPills.swift` which is in `UnifiedChatView` | WIRED |
| `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassCard.swift` | Reusable card with liquid glass background | Used in `LiquidGlassEntryCard`, `BereanLiquidGlassSystem` | WIRED |
| `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassMaterial.swift` | Material tokens (blur radius, opacity, highlight) for different glass contexts | Used in `LiquidGlassCard` | INTERNAL |
| `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassTokens.swift` | Design tokens (corner radius, padding, spacing) for the glass system | Used in `LiquidGlassMaterial` | INTERNAL |
| `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassComposerBar.swift` | Glass composer bar used in Living Entries | Used in `LivingEntriesHomeView` | WIRED |
| `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassEntryCard.swift` | Glass card for a Living Entry item | Used in `LivingEntriesHomeView` | WIRED |
| `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassEntryStackView.swift` | Stacked entry cards with glass morphic depth | Used in `LivingEntriesHomeView` | WIRED |
| `AMENAPP/AMENAPP/LiquidGlass/LivingEntriesLiquidGlassMotion.swift` | Motion transitions for Living Entries liquid glass UI | Used in `LivingEntriesHomeView` | WIRED |

### 1.10 LIVING ENTRIES

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/AMENAPP/LivingEntries/LivingEntryModels.swift` | Models: `LivingEntry`, `LivingEntrySection`, `LivingEntryTrigger`, `LivingEntryType` | Used throughout Living Entries feature | INTERNAL |
| `AMENAPP/AMENAPP/LivingEntries/LivingEntryService.swift` | Firestore CRUD for Living Entries; listens for real-time updates | Used by `LivingEntryViewModel` | INTERNAL |
| `AMENAPP/AMENAPP/LivingEntries/LivingEntryViewModel.swift` | Drives `LivingEntriesHomeView`; holds entries list, handles create/edit/delete | Used as `@StateObject` in `LivingEntriesHomeView` | WIRED |
| `AMENAPP/AMENAPP/LivingEntries/LivingEntriesHomeView.swift` | Main Living Entries surface: notes, reminders, church follow-up, reflections in glass cards | Navigated from `AMENAPP/HomeView.swift` and `BereanStudyHomeView` | WIRED |
| `AMENAPP/AMENAPP/LivingEntries/LivingEntryReflectionSheet.swift` | Sheet for reflecting on a completed Living Entry | Presented from `LivingEntriesHomeView` | WIRED |
| `AMENAPP/AMENAPP/LivingEntries/FindChurchLivingEntryBridge.swift` | Creates a Living Entry pre-populated from a church visit or church note | Called from `FindChurchView.swift` | WIRED |
| `AMENAPP/AMENAPP/LivingEntries/ChurchLivingNotesView.swift` | Living Notes view scoped to a single church — shows all entries from that context | Used in `ChurchNotes` surfaces | WIRED |
| `AMENAPP/AMENAPP/LivingEntries/LivingEntryContextEngine.swift` | Enriches entries with contextual data (liturgical date, church proximity, time of day) | Used by `LivingEntryViewModel` | INTERNAL |

### 1.11 BEREAN PULSE

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseModels.swift` | Models: `BereanPulseItem`, `BereanPulseMode`, `BereanPulseSignal` | Used throughout Berean Pulse feature | INTERNAL |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseService.swift` | Fetches pulse signals from backend; real-time Firestore listener | Used by `BereanPulseViewModel` | INTERNAL |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseViewModel.swift` | Drives `BereanPulseView`; manages signal list, curation, permissions | Used as `@StateObject` in `BereanPulseView` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseView.swift` | Main Berean Pulse surface — live spiritual signals, trends, curated moments | Navigated from `AMENAPP/HomeView.swift` and `BereanHomeView.swift` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseCardView.swift` | Individual pulse card (signal item) with glass styling | Used in `BereanPulseView` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseCardDetailView.swift` | Full detail view for a pulse item | Presented from `BereanPulseCardView` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseHeaderView.swift` | Header with mode selector and live count | Used in `BereanPulseView` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseModePillRow.swift` | Pill row for switching between pulse modes (trending, nearby, global) | Used in `BereanPulseView` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseSignalPanel.swift` | Expandable panel showing full signal details | Used in `BereanPulseCardDetailView` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseGlassSurface.swift` | Glass surface wrapper for pulse cards | Used in `BereanPulseCardView` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseEmptyStateView.swift` | Empty state for when no signals are available | Used in `BereanPulseView` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseErrorStateView.swift` | Error state view | Used in `BereanPulseView` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseLoadingView.swift` | Loading skeleton for pulse feed | Used in `BereanPulseView` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseCurateSheet.swift` | Sheet for curating/filtering pulse signals | Presented from `BereanPulseView` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulsePermissionManager.swift` | Manages notification permissions for pulse alerts | Used by `BereanPulseViewModel` | INTERNAL |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulsePermissionSheet.swift` | Permission request sheet for pulse notifications | Presented from `BereanPulseView` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseActionRouter.swift` | Routes taps on pulse cards to appropriate app destinations | Used in `BereanPulseCardView` and `BereanPulseCardDetailView` | WIRED |

### 1.12 COVENANT OS (Paid Spiritual Communities)

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/Covenant/CovenantModels.swift` | Core Covenant models: `CovenantCommunity`, `CovenantTier`, `CovenantMember`, `CovenantPost`, `CovenantThread` | Used throughout Covenant OS | INTERNAL |
| `AMENAPP/Covenant/CovenantService.swift` | Firestore + Functions client for all Covenant operations | Used by all Covenant view models | INTERNAL |
| `AMENAPP/Covenant/AmenCovenantHomeView.swift` | Home of a Covenant community — feed, pinned posts, tier info | Entry point from deep link or community directory | WIRED |
| `AMENAPP/Covenant/AmenCovenantStartHereView.swift` | Onboarding surface for new Covenant members | Shown on first join | WIRED |
| `AMENAPP/Covenant/AmenCovenantDiscoveryView.swift` | Browse and search Covenant communities | Shown from main discovery/tab | WIRED |
| `AMENAPP/Covenant/AmenCovenantPaywallView.swift` | Paywall shown when accessing a gated tier | Presented when tier access is required | WIRED |
| `AMENAPP/Covenant/AmenCovenantSearchView.swift` | Search within a Covenant community | Shown from community nav | WIRED |
| `AMENAPP/Covenant/AmenCovenantSearchService.swift` | Algolia + Firestore search for Covenant content | Used by `AmenCovenantSearchView` | INTERNAL |
| `AMENAPP/Covenant/AmenCovenantActivityCenterView.swift` | Notifications/activity within a Covenant community | Shown from community tab bar | WIRED |
| `AMENAPP/Covenant/AmenCovenantDeepLinkResolver.swift` | Resolves deep links to specific Covenant surfaces | Called from notification router and URL handling | WIRED |
| `AMENAPP/Covenant/AmenCovenantMemberDirectoryView.swift` | Member list for a Covenant community | Shown from community profile | WIRED |
| `AMENAPP/Covenant/AmenCovenantModerationQueueView.swift` | Moderation queue for community admins | Shown from creator hub | WIRED |
| `AMENAPP/Covenant/AmenPrayerFollowUpCard.swift` | Card prompting follow-up on a prayer request in Covenant | Shown in Covenant feed and activity | WIRED |
| `AMENAPP/Covenant/AmenReportContentSheet.swift` | Report content sheet for Covenant posts/comments | Presented from Covenant post context menu | WIRED |
| `AMENAPP/Covenant/AmenTrustBadge.swift` | Badge indicating a Covenant creator's trust level | Shown on Covenant profiles | WIRED |
| `AMENAPP/Covenant/AmenMentionParser.swift` | Parses `@mention` text in Covenant composer | Used by `AmenMentionTextView` | INTERNAL |
| `AMENAPP/Covenant/AmenMentionTextView.swift` | Custom text view with mention highlighting and autocomplete | Used in `AmenCovenantPostComposerView` | WIRED |
| `AMENAPP/Covenant/AmenCovenantRevenueView.swift` | Creator revenue dashboard (earnings, tier analytics) | Shown from `AmenCreatorHubView` | WIRED |
| `AMENAPP/Covenant/AmenCreatorVerificationView.swift` | Creator verification flow | Shown from `AmenCreatorHubView` | WIRED |
| `AMENAPP/Covenant/AmenCovenantContentCalendarView.swift` | Content calendar for scheduling Covenant posts | Shown from `AmenCreatorHubView` | WIRED |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantViewModel.swift` | Main view model for Covenant community state | Used by all Covenant views | WIRED |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantCheckoutService.swift` | Stripe checkout session creation for Covenant subscriptions | Used by `AmenCovenantPaywallView` | INTERNAL |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantDigestView.swift` | Weekly digest surface for Covenant members | Shown from Covenant home | WIRED |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantAnalyticsView.swift` | Analytics dashboard for Covenant creators | Shown from creator hub | WIRED |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantEventsView.swift` | Events list within a Covenant community | Shown from community tab | WIRED |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantLiquidGlass.swift` | Liquid glass styling tokens for Covenant surfaces | Used throughout Covenant views | INTERNAL |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantManageView.swift` | Admin management panel for Covenant community settings | Shown from creator hub | WIRED |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantModerationView.swift` | Full moderation interface for Covenant admins | Shown from creator hub | WIRED |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantPermissions.swift` | Permission model for Covenant roles (owner, mod, member) | Used by all Covenant views to gate UI | INTERNAL |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantPostComposerView.swift` | Rich post composer for Covenant content (mentions, polls, files) | Shown from Covenant home | WIRED |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantRoomDetailView.swift` | Voice/text room detail within a Covenant community | Shown from Covenant rooms list | WIRED |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantRoomsView.swift` | Rooms list (voice, text, prayer rooms) | Shown from Covenant home tab bar | WIRED |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantRoutes.swift` | Navigation route enum for Covenant deep links | Used by `AmenCovenantDeepLinkResolver` | INTERNAL |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantStoryViewer.swift` | Story viewer for Covenant member stories | Shown from Covenant home | WIRED |
| `AMENAPP/AMENAPP/Covenant/AmenCovenantTierSetupSheet.swift` | Sheet for creators to configure Covenant subscription tiers | Shown from creator hub | WIRED |
| `AMENAPP/AMENAPP/Covenant/AmenCreatorHubView.swift` | Creator dashboard — all management tools in one place | Shown for Covenant creators | WIRED |

### 1.13 CHURCH DISCOVERY & TRUST

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/ChurchDetailExperience.swift` | Full church profile experience — hero, info, Berean AI, floating action bar | Navigated from `FindChurchView` | WIRED |
| `AMENAPP/ChurchTrustSafetyService.swift` | Church admin backend: submit verification, profile updates, fetch moderation queue, review items | Called by `ChurchClaimVerifySheet` | WIRED (NEW SESSION) |
| `AMENAPP/TrustInfrastructureService.swift` | Loads verified ministry IDs and moderation council queue count | Warm-started in `AMENAPPApp.warmUpServices()` | WIRED (NEW SESSION) |
| `ChurchClaimVerifySheet` (added to `ChurchDetailExperience.swift`) | Form for claiming or verifying a church profile | Opens from floating action bar `exclamationmark.bubble` button in `FindChurchDetailView` | WIRED (NEW SESSION) |
| `AMENAPP/ChurchRankingService.swift` | Observes a church's ranking snapshot (trust, proximity, affinity scores) | Used in `ChurchDetailExperience.swift` | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseActionRouter.swift` | Routes taps from pulse items to church detail, post detail, etc. | Used in Berean Pulse | WIRED |
| `AMENAPP/AMENAPP/BereanPulse/BereanPulseCardDetailView.swift` | Pulse card detail, may route to church profiles | Used in Berean Pulse | WIRED |

### 1.14 WALK WITH CHRIST / DISCIPLESHIP

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/WalkWithChristFeatures.swift` | Defines the Walk With Christ feature set: daily check-ins, scripture immersion, accountability | Used in `WalkWithChristView.swift` and `ResourcesView.swift` | WIRED |
| `AMENAPP/AmenMyStudyPlansView.swift` | Browse and manage personal Bible study plans | Shown from `BereanAdvancedFeaturesViews.swift` | WIRED |
| `AMENAPP/AmenStudyPlanBuilder.swift` | Interactive builder for creating custom study plans | Shown from `BookDetailView.swift` | WIRED |
| `AMENAPP/AmenReadingCompanionEngine.swift` | AI engine that enriches Scripture reading with context, questions, and connections | Used in `WisdomLibraryView.swift` | WIRED |

### 1.15 WISDOM LIBRARY

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/AmenLibraryCatalogProvider.swift` | Fetches and caches the library catalog (books, sermons, courses, articles) | Used by `AMENAPP/AmenLibraryEditorialSurface.swift` and `BookDiscoveryViewModel` | WIRED |
| `AMENAPP/AmenLibraryEditorialSurface.swift` | Editorial curation surface — featured, trending, and personalized content | Used in `WisdomLibraryView.swift` (inferred) | WIRED |
| `AMENAPP/AmenLibraryRankingService.swift` | Ranks library content by spiritual affinity, recency, and engagement | Used by `BookDiscoveryViewModel` | WIRED |
| `AMENAPP/AmenLibraryMemoryService.swift` | Persists library reading progress and bookmarks | Used by `AmenReadingCompanionEngine` and `WisdomLibraryView` | WIRED |
| `AMENAPP/AmenWisdomGraphService.swift` | Graph of conceptual connections between library items; powers "Related Content" | Used by `AmenReadingCompanionEngine` and `AmenLibraryRankingService` | WIRED |

### 1.16 HOLIDAY AWARENESS & LITURGICAL CALENDAR

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/HolidayAwarenessModels.swift` | Models: `HolidayObservance`, `HolidayCalendarEntry`, `HolidayReflectionType` | Used by Holiday service and views | INTERNAL |
| `AMENAPP/HolidayAwarenessService.swift` | Reads holiday calendar from Firestore; surfaces upcoming observances | Used in `AIDailyVerseView.swift` and `AMENNotificationsView.swift` | WIRED |
| `AMENAPP/HolidayReflectionSheet.swift` | Reflection sheet for a holiday — scripture, prayer, traditions | Shown from `AIDailyVerseView.swift` | WIRED |

### 1.17 SAVED MOMENTS & MEDIA

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/SavedMomentsService.swift` | Manages saved media moments across Selah and messaging | Used in `UserProfileView` and `SelahView` | WIRED |
| `AMENAPP/AMENAPP/AmenMediaDetailView.swift` | Full-screen media detail for posts, with related moments, reactions, save actions | Navigated from feed and messaging | WIRED |
| `AMENAPP/AMENAPP/MediaMomentInteractionService.swift` | Tracks and records user interactions with media moments | Used in `AMENAPP/AmenMediaDetailView.swift` | WIRED |
| `AMENAPP/AMENAPP/RelatedMomentsService.swift` | Fetches spiritually related media moments | Used in `AMENAPP/AmenMediaDetailView.swift` | WIRED |
| `AMENAPP/AMENAPP/SharedMomentRoutingService.swift` | Routes shared media moment deep links to the right surface | Used in `AMENAPPApp.swift` | WIRED |

### 1.18 NOTIFICATIONS & AMBIENT PRESENCE

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/AmenFeedContextEnrichmentService.swift` | Enriches feed items with contextual signals (liturgical, proximity, social) | Used in `AMENAPP/AmenSpiritualSystems.swift` | WIRED |
| `AMENAPP/AmenFeedContextLabelSystem.swift` | Label rendering system for context-aware feed badges | Used throughout feed | WIRED |
| `AMENAPP/AMENActivityIntelligenceEngine.swift` | Tracks and interprets user activity patterns for smart notification timing | Used in `AMENNotificationsView.swift` and routing pipeline | WIRED |
| `AMENAPP/AmbientPresenceIntelligence.swift` | Manages ambient presence signals (worship mode, travel, quiet hours) | Used in `BereanAlignmentSettingsView.swift` | WIRED |
| `AMENAPP/AMENAPP/ProductionNotificationRouting.swift` | Production-grade notification routing rules and priority tiers | Used in notification pipeline | WIRED |
| `AMENAPP/ShareRouter.swift` | Routes share events from the AMEN custom share sheet | Used in `UserProfileMiniViewModel` | WIRED |
| `AMENAPP/BereanChatRouter.swift` | Routes Berean chat intents to the right conversation or mode | Used in `AMENAPP/BereanChatRouter.swift` and navigation | WIRED |

### 1.19 SPIRITUAL GRAPH & PRESENCE (BACKEND SERVICES — SWIFT CLIENTS)

| File | What It Does | User Flow | Status |
|------|-------------|-----------|--------|
| `AMENAPP/SpiritualGraphModels.swift` | Models for spiritual graph nodes, edges, memory records, presence sensitivity | Used in `SpiritualMemoryView.swift` which is wired via `SelahView`, `BereanChatView`, `SettingsDestinationViews` | WIRED |
| `AMENAPP/SpiritualGraphService.swift` | Swift client writing graph edges and memory records to Firestore | Used by `BereanOperatingLayer`, `SermonWeekTransformationService`, `HolidayReflectionJourneyService` | WIRED |

---

## PART 2 — BACKEND TYPESCRIPT FILES

### 2.1 AMENAPP/Backend (Sub-deployment — presence, giving, share, church, feed)

This is the `AMENAPP/Backend/functions/src/` sub-project.

| File | What It Does | Exported | Status |
|------|-------------|----------|--------|
| `index.ts` | Entry point for sub-deployment | exports all below | WIRED (NEW SESSION — expanded from stub) |
| `presence/presenceIntelligence.ts` | `generatePresenceSignals`, `updatePresencePreferences` callables | Yes | WIRED (NEW SESSION) |
| `giving/controllers/givingCallables.ts` | `saveGivingProfile`, `submitBenevolenceRequest`, `getRankedFeed`, `generateAnnualReview` | Yes | WIRED (NEW SESSION) |
| `giving/controllers/benevolenceModeration.ts` | `onBenevolenceRequestCreated`, `onBenevolenceRequestUpdated` triggers | Yes | WIRED (NEW SESSION) |
| `giving/controllers/nonprofitIngestion.ts` | `dailyNonprofitDataSync`, `weeklyDisasterEventCleanup`, `weeklyBenevolenceRequestCleanup` | Yes | WIRED (NEW SESSION) |
| `giving/services/GivingRankingEngine.ts` | Ranks nonprofits and benevolence requests | No (internal) | INTERNAL |
| `giving/services/BenevolenceGuardian.ts` | Validates benevolence requests | No (internal) | INTERNAL |
| `giving/services/DisasterIngestionService.ts` | Ingests external disaster signals | No (internal) | INTERNAL |
| `giving/models/givingModels.ts` | Giving domain models | No (internal) | INTERNAL |
| `share/smartShare.ts` | 15 share callables: targets, permissions, payloads, deep links, moderate, notify, deliver, etc. | Yes | WIRED (NEW SESSION) |
| `church/controllers/churchTrustCallables.ts` | Church verification, moderation, grounding, livestream callables | Yes | WIRED (NEW SESSION) |
| `church/services/ChurchGroundingService.ts` | Grounds church answers using Firestore data + AI | Used by `churchTrustCallables` | INTERNAL |
| `church/services/ChurchConfidenceEngine.ts` | Computes confidence level for church answers | Used by `ChurchGroundingService` | INTERNAL |
| `church/services/ChurchModerationEngine.ts` | Moderates church content and profiles | Used by `churchTrustCallables` | INTERNAL |
| `church/services/ChurchTrustRepository.ts` | Firestore repository for church trust records | Used by moderation/grounding services | INTERNAL |
| `church/services/ChurchLivestreamIngestionService.ts` | Ingests YouTube livestream data | Used by `churchTrustCallables` | INTERNAL |
| `church/models/churchTrust.ts` | Church trust domain models | Internal types | INTERNAL |
| `feedContext.ts` | `computeFeedContextLabels`, `attachFeedContextToRankedPosts`, `updateUserContextLabelPreferences`, `trackContextLabelEvent`, `suppressContextLabelForUser` | Yes | WIRED (NEW SESSION) |
| `mediaPostIndex.ts` | `onMediaPostCreate`, `onMediaPostUpdate`, `onMediaPostDelete` Firestore triggers | Yes | WIRED (NEW SESSION) |
| `bereanChatProxy.ts` | `bereanChatProxy` callable (proxies to Anthropic with auth) | Yes | WIRED (NEW SESSION) |
| `berean/bereanOperatingLayer.ts` | `generateBereanOperatingResponse` — full Berean pipeline with context | Yes | WIRED (NEW SESSION) |
| `spiritualGraph/models/spiritualGraph.ts` | TypeScript types for spiritual graph | Internal types | INTERNAL |
| `spiritualGraph/services/SpiritualGraphService.ts` | Graph write operations for edges and memory | No callable exports | INTERNAL |
| `smartAttachments.ts` | Smart attachment callables | Yes (was already there) | WIRED |

### 2.2 Main Backend/functions/src/ (Primary Deployed Functions)

All key new files here are already exported from the main `Backend/functions/src/index.ts`. Key additions:

| File | What It Does | Status |
|------|-------------|--------|
| `presence/presenceIntelligence.ts` | Presence signals callable (in AMENAPP/Backend only, not main Backend) | N/A — main Backend does not have a presence/ dir |
| `alignmentPipeline.ts` | Utility functions for alignment scoring — imported by `biblicalAlignmentFunctions.ts` | INTERNAL (not a direct export) |
| `berean/bereanOperatingLayer.ts` | Full Berean AI pipeline | WIRED (exported line 320) |
| `church/controllers/churchTrustCallables.ts` | Church trust callables | WIRED (exported line 316) |
| `selahMedia.ts` | Selah Media OS callables | WIRED |
| `bereanPulse.ts` | Berean Pulse callables | WIRED |
| `covenant/*` | All Covenant OS callables | WIRED |
| `restModeEvaluator.ts` | `evaluateRestMode`, `setRestModePolicy`, `resolvePostAILabel` | WIRED |
| `holidayCalendarGenerator.ts` | `generateNextYearHolidayCalendar`, `backfillHolidayCalendar` | WIRED |
| `feedContext.ts` | Feed context callables | WIRED |
| `generateDynamicReplyPreviews.ts` | Server-ranked inline reply preview candidates | WIRED |
| `spiritualSystems.ts` | Spiritual graph and systems callables | WIRED |
| `safetyOS.ts` | Social Safety OS — 5-harm-category platform | WIRED |
| `bereanExtended.ts` | Extended Berean memory, threads, translation | WIRED |
| `creationAI.ts` | AI-powered creation assistance | WIRED |
| `churchDiscovery.ts` / `churchDiscoveryPhase2.ts` / `churchDiscoveryPhase3.ts` | Church discovery pipeline | WIRED |
| `syncAgeTierClaim.ts` | JWT age tier claim sync | WIRED |
| `livingEntries/livingEntryFunctions.ts` | Living Entries callables | WIRED |
| `profileMini/getUserProfileMiniContext.ts` | User profile mini context callable | WIRED |
| `bereanChatProxyStream.ts` | True SSE streaming proxy | WIRED |
| `biblicalAlignmentFunctions.ts` | Biblical alignment callables | WIRED |
| `berean/services/BereanEntitlementService.ts` | Entitlement gating for Berean features | INTERNAL |
| `berean/services/BereanUsageLogger.ts` | Usage logging for Berean AI calls | INTERNAL |

---

## PART 3 — WIRING GAPS (ACTION REQUIRED)

### ~~GAP 1~~ WIRED — SacredFeedMode

**File:** `AMENAPP/AMENAPP/SacredFeedModes.swift`
**What's missing:** `SacredFeedMode` enum and `SacredFeedModePicker` view exist but nothing in the feed reads or sets the active mode.
**Wire:** In `YourFeedView.swift`, add `@AppStorage("sacredFeedMode") var sacredFeedMode: String = SacredFeedMode.healthyMix.rawValue`. Show `SacredFeedModePicker` from `FeedViewModeSwitcher` or `HeyFeedActivePillsBar`. Pass the mode into the feed ranking request.

### ~~GAP 2~~ WIRED — BlessLaterSystem

**File:** `AMENAPP/AMENAPP/BlessLaterSystem.swift`
**What's missing:** `BlessLaterService.shared.schedule(post:timing:)` is never called. `BlessLaterView` (the tray) is never presented.
**Wire:**
1. Add a "Bless Later" item to `PostCard.swift` context menu or swipe action calling `BlessLaterService.shared.schedule(post: post, timing: .tomorrowMorning)`.
2. Add a `BlessLaterView` destination in `AMENNotificationsView` or a dedicated tray in `AMENAPP/HomeView.swift` that lists deferred posts.

### ~~GAP 3~~ WIRED — ComposerSuggestionChips (CreatePostIntentSystem)

**File:** `AMENAPP/AMENAPP/CreatePostIntentSystem.swift`
**What's missing:** `PostComposerIntent` enum and `CreatePostIntentRow` are defined, but `CreatePostView.swift` never reads `selectedIntent` and never writes it to the post's `postIntent` field.
**Wire:** In `CreatePostView.swift`, add `@State private var selectedIntent: PostComposerIntent = .encourage`. Show `CreatePostIntentRow(selectedIntent: $selectedIntent)` in the composer. When publishing, write `post.postIntent = selectedIntent.rawValue` to Firestore.

### ~~GAP 4~~ WIRED — AmenAdvancedLiquidGlassSystem (.adaptiveGlass)

**File:** `AMENAPP/AmenAdvancedLiquidGlassSystem.swift`
**What's missing:** `AtmosphericBlurEngine.resolveState(...)` and `.adaptiveGlass(state:)` ViewModifier have zero callers. The system is built but not applied anywhere.
**Wire:** In `SelahMediaHomeView.swift`, `BereanChurchContextSheet`, and `AmenCovenantHomeView.swift`, compute an `AmbientGlassState` using `AtmosphericBlurEngine.resolveState(context:motion:worship:)` and apply `.adaptiveGlass(state: ambientState)` to the main container view.

---

## PART 4 — WIRING DONE THIS SESSION

| Action | Location | What Was Done |
|--------|----------|---------------|
| `TrustInfrastructureService` warm-up | `AMENAPPApp.warmUpServices()` | Added to `withTaskGroup` alongside safety services; lazy singleton initializes Firestore listeners on first launch |
| `ChurchTrustSafetyService` surface | `ChurchDetailExperience.swift` | Added `@State private var showClaimChurchSheet = false`; wired `onSuggestEdit: { showClaimChurchSheet = true }` on floating action bar; added `ChurchClaimVerifySheet` struct collecting email + notes and calling `ChurchTrustSafetyService.shared.submitVerificationRequest(...)` |
| `AMENAPP/Backend index.ts` | `AMENAPP/Backend/functions/src/index.ts` | Expanded 3-line stub to full entry point: exports presence intelligence, all giving callables, benevolence triggers, nonprofit ingestion, media post index, smart share, church trust callables, feed context, berean chat proxy, and berean operating layer |

---

## PART 5 — QUICK REFERENCE: FILE → WIRING LOCATION

```
SacredFeedModes.swift           → GAP: wire in YourFeedView.swift
BlessLaterSystem.swift          → GAP: wire in PostCard.swift + HomeView.swift
CreatePostIntentSystem.swift    → GAP: wire in CreatePostView.swift
AmenAdvancedLiquidGlassSystem  → GAP: wire in SelahMediaHomeView, AmenCovenantHomeView
ChapelInboxSystem.swift         → PARTIAL: ChapelInboxView not yet presented from nav
TrustInfrastructureService     → AMENAPPApp.warmUpServices() [DONE]
ChurchTrustSafetyService        → ChurchDetailExperience.ChurchClaimVerifySheet [DONE]
AMENAPP/Backend/index.ts        → All subdirectory callables now exported [DONE]
presence/presenceIntelligence   → Exported via AMENAPP/Backend/index.ts [DONE]
giving/controllers/*            → Exported via AMENAPP/Backend/index.ts [DONE]
share/smartShare.ts             → Exported via AMENAPP/Backend/index.ts [DONE]
```
