# GLASS_AUDIT.md — Liquid Glass Migration, Phase 0
**Date:** 2026-05-31  
**Status:** AUDIT COMPLETE — awaiting human approval before any code changes  
**Deployment target:** iOS 17.0 → all `.glassEffect()` calls must be gated `#available(iOS 26, *)`

---

## Classification Key

| Label | Meaning |
|---|---|
| **MIGRATE** | Replace material/blur with `.glassEffect()` via `amenGlass*` helper |
| **KEEP-FALLBACK** | Material is the correct pre-iOS 26 fallback; already branched or guarded |
| **REMOVE** | Glass-on-glass, or glass behind dense/long text → use solid background |
| **NATIVE-FREEBIE** | TabView / toolbar / sheet / NavigationStack gets Liquid Glass automatically on iOS 26 SDK |
| **Already migrated** | File already uses `.glassEffect()` or `amenGlass*` helpers |

---

## 1. Inventory Table

### Nav / Tab Chrome

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `AMENTabBar.swift` | 42 | `.blur(radius: 0.4)` | Tab bar specular highlight | KEEP-FALLBACK — inside pre-iOS26 else branch |
| `AMENTabBar.swift` | 79, 115, 131 | `.glassEffect(Glass.regular…)` | Tab capsule / orb / selection pill | Already migrated |
| `CompactTopChromeView.swift` | 27 | `.fill(.ultraThinMaterial)` | Compact top chrome bar | MIGRATE → `amenGlassBar` |
| `TipSheetView.swift` | 56 | `.toolbarBackground(.ultraThinMaterial, for: .navigationBar)` | Nav toolbar | NATIVE-FREEBIE |
| `VergeCreatorStudioView.swift` | 58 | `.toolbarBackground(.ultraThinMaterial, for: .navigationBar)` | Nav toolbar | NATIVE-FREEBIE |
| `VergeCreateRoomSheet.swift` | 79 | `.toolbarBackground(.ultraThinMaterial, for: .navigationBar)` | Nav toolbar | NATIVE-FREEBIE |
| `StartCoCreationSheet.swift` | 184 | `.toolbarBackground(.ultraThinMaterial, for: .navigationBar)` | Nav toolbar | NATIVE-FREEBIE |
| `CoCreationSummaryView.swift` | 109 | `.toolbarBackground(.ultraThinMaterial, for: .navigationBar)` | Nav toolbar | NATIVE-FREEBIE |
| `NowPlayingBar.swift` | 83 | `.background(.ultraThinMaterial)` | Mini audio playback bar | MIGRATE → `amenGlassBar` |
| `BereanFloatingTabBar.swift` | 100 | `.fill(.regularMaterial)` | Floating tab bar background | MIGRATE → `amenGlassBar` inside `GlassEffectContainer` |

### HeyFeed / OpenTable

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `OpenTableView.swift` | 216, 459 | `.amenGlassCard(cornerRadius:shadow:)` | Feed cell cards | Already migrated |
| `FeedComposerRow.swift` | 184, 200 | `.fill(.ultraThinMaterial)` | Avatar ring / pill | MIGRATE → `amenGlassCard` |
| `FeedComposerRow.swift` | 73 | `.buttonStyle(.amenGlass(…))` | Compose button | Already migrated |
| `HeyFeedTuningPill.swift` | 74 | `.fill(.thinMaterial)` | Feed tuning pill | MIGRATE → `amenGlassBar` |
| `HeyFeedActivePillsBar.swift` | 82 | `.fill(.thinMaterial)` | Active filter pills | MIGRATE → `amenGlassBar` |
| `HeyFeedNLInputView.swift` | 93 | `.presentationBackground(.regularMaterial)` | NL input sheet | MIGRATE → `amenGlassSheet` |
| `HeyFeedNLInputView.swift` | 283 | `.fill(.thinMaterial)` | Chip in NL input | MIGRATE → `amenGlassBar` |
| `HeyFeedActiveRequestsView.swift` | 108, 179, 367 | `.fill(.ultraThinMaterial)` | Active request cards | MIGRATE → `amenGlassCard` |
| `PostCard.swift` | 6042, 6065, 6078 | `.blur(radius: 14/11/20)` | Image glow / ambient | KEEP — decorative ambient glow |
| `PostCard.swift` | 4888 | `.blur(radius: 3)` | Text shadow | KEEP — typographic |
| `PostDetailView.swift` | 308 | `.background(.regularMaterial, in: RoundedRectangle(…))` | Comment background | MIGRATE → `amenGlassCard` |
| `PostDetailView.swift` | 674 | `.fill(.regularMaterial)` | Separator / chip | MIGRATE → `amenGlassCard` |
| `PostDetailView.swift` | 796, 948, 1242 | `.fill/.background(.ultraThinMaterial)` | Post detail overlays | MIGRATE → `amenGlassCard` |
| `RoleAwareComposerPresetBar.swift` | 16 | `.background(.ultraThinMaterial)` | Preset bar container | MIGRATE → `amenGlassBar` |
| `ReplyThreadRowView.swift` | 30 | `.background(.ultraThinMaterial)` | Reply thread row | MIGRATE → `amenGlassCard` |
| `QuotePostView.swift` | 300, 357 | `.background(.regularMaterial, in: Capsule())` | Quote pill / container | MIGRATE → `amenGlassCard` |
| `SavedPostsView.swift` | 217, 236, 260 | `.fill/.background(.regularMaterial)` | Saved posts cells | MIGRATE → `amenGlassCard` |
| `InAppNotificationBanner.swift` | 313 | `.fill(.regularMaterial)` | In-app banner | MIGRATE → `amenGlassCard` |
| `CaughtUpView.swift` | 121, 132 | `.fill(.ultraThinMaterial)` | Caught-up state card | MIGRATE → `amenGlassCard` |
| `CaughtUpView.swift` | 328 | `.fill(.regularMaterial)` | Footer pill | MIGRATE → `amenGlassCard` |
| `ThreadSummaryView.swift` | 72 | `.fill(.ultraThinMaterial)` | Thread summary card | MIGRATE → `amenGlassCard` |
| `RepostQuoteComponents.swift` | 101 | `.fill(.ultraThinMaterial)` | Repost quote bubble | MIGRATE → `amenGlassCard` |
| `ActivityFeedView.swift` | 52, 74 | `.fill/.background(.regularMaterial…)` | Activity feed cells | MIGRATE → `amenGlassCard` |

### Berean AI

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `BereanChatView.swift` | 1537–3863 (~28 hits) | `.fill(.ultraThinMaterial)` | Chat bubbles, mode chips, suggestion pills, source cards | MIGRATE → `amenGlassCard` (bubbles) / `amenGlassBar` (pills) |
| `BereanDesignSystem.swift` | 81, 145, 175 | `.fill(.ultraThinMaterial)` | GlassShadowCard, PersonalityPill, SuggestionChip backing | MIGRATE — update at design-system level; callers inherit |
| `BereanDesignSystem.swift` | 110 | delegates to `amenGlassInputBar` | Input bar | Already migrated |
| `BereanLandingView.swift` | 162–830 (~10 hits) | `.fill(.ultraThinMaterial)` | Landing cards, section headers, capability chips | MIGRATE → `amenGlassCard` / `amenGlassBar` |
| `BereanMessageMenuView.swift` | 66 | `.background(.ultraThinMaterial, in: RoundedRectangle(…))` | Long-press action menu | MIGRATE → `amenGlassCard` inside `GlassEffectContainer` |
| `BereanMessageTray.swift` | 266, 273 | `AnyShapeStyle(.ultraThinMaterial)` | Message tray background | MIGRATE → `amenGlassCard` |
| `BereanComposerTray.swift` | 132, 373, 472, 553, 586, 635 | `.fill/.AnyShapeStyle(Material.ultraThinMaterial)` | Tray surfaces, handles, mode pickers | MIGRATE → `amenGlassCard` / `amenGlassBar` |
| `BereanComposerBar.swift` | 735 | `.amenGlassEffect(…)` | Composer bar | Already migrated |
| `BereanFocusedComposer.swift` | 112 | `.fill(.ultraThinMaterial)` | Focused composer overlay | MIGRATE → `amenGlassCard` |
| `BereanInteractiveUI.swift` | 371, 852, 875 | `.fill/.AnyShapeStyle(.ultraThinMaterial)` | Interactive overlays, suggestion surfaces | MIGRATE → `amenGlassCard` |
| `BereanInteractiveUI.swift` | 306, 320 | `.blur(radius: 70/65)` | Decorative ambient orbs | KEEP — decorative |
| `BereanInteractiveUI.swift` | 721 | `.blur(radius: isMenuOpen ? 18 : 0)` | Content blur when menu opens | KEEP — intentional context blur |
| `BereanModeControlBar.swift` | 187 | `.fill(.regularMaterial)` | Mode control bar background | MIGRATE → `amenGlassBar` |
| `BereanModeDrawer.swift` | 92 | `.amenGlassEffect(…)` | Mode drawer items | Already migrated |
| `BereanMemoryChip.swift` | 104 | `AnyShapeStyle(.ultraThinMaterial)` | Memory chip capsule | MIGRATE → `amenGlassBar` |
| `BereanThinkingStrip.swift` | 155 | `.fill(.ultraThinMaterial)` | Thinking/reasoning strip | MIGRATE → `amenGlassBar` |
| `BereanThreadCapsule.swift` | 153, 269, 288 | `.fill/.AnyShapeStyle(.ultraThinMaterial)` | Thread capsule containers | MIGRATE → `amenGlassCard` |
| `BereanSafetyOverlayView.swift` | 116–580 (~9 hits) | `.fill(.ultraThinMaterial)` | Safety overlay panels, buttons, pills | MIGRATE → `amenGlassCard` / `amenGlassBar` |
| `BereanContextLensView.swift` | 186 | `.fill(.regularMaterial)` | Context lens panel | MIGRATE → `amenGlassCard` |
| `BereanFactShieldView.swift` | 86 | `.background(.regularMaterial, in: RoundedRectangle(…))` | Fact shield badge | MIGRATE → `amenGlassCard` |
| `BereanFollowUpView.swift` | 35 | `.background(.regularMaterial, in: Capsule())` | Follow-up suggestion chip | MIGRATE → `amenGlassBar` |
| `BereanChatsListView.swift` | 103–367 (~7 hits) | `.background(.ultraThinMaterial, in: RoundedRectangle(…))` | Chat list row cards | MIGRATE → `amenGlassCard` |
| `AnonymousBereanSheet.swift` | 84, 103 | `.background(.regularMaterial, in: RoundedRectangle(…))` | Anonymous Berean panel | MIGRATE → `amenGlassCard` |
| `AskSelahView.swift` | 251 | `.background(.regularMaterial)` | Selah answer panel | MIGRATE → `amenGlassCard` |
| `ReasoningThreadView.swift` | 40, 112 | `.fill(.ultraThinMaterial)` | Reasoning steps | MIGRATE → `amenGlassCard` |
| `AIIntelligence/BereanScriptureContextCardView.swift` | 132 | `AnyShapeStyle(.regularMaterial)` | Scripture context card | MIGRATE → `amenGlassCard` |
| `AIIntelligence/BereanFloatingActionTray.swift` | 58, 64 | `AnyShapeStyle(.regularMaterial/.thinMaterial)` | Floating action tray | MIGRATE → `amenGlassCard` |
| `AIIntelligence/BereanVoiceCompanionView.swift` | 100, 129, 245, 266 | `AnyShapeStyle(.thinMaterial)` / `Capsule().fill(.thinMaterial)` | Voice companion controls | MIGRATE → `amenGlassBar` |
| `AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift` | 24, 153, 246 | `.fill(.ultraThinMaterial)` / `.fill(.regularMaterial)` | AI overlay components | MIGRATE → `amenGlassCard` |
| `AIIntelligence/LiveCaptionOverlay.swift` | 79 | `.fill(.ultraThinMaterial)` | Live caption pill | MIGRATE → `amenGlassBar` |
| `AIIntelligence/BereanLiveTranslationBar.swift` | 52 | `.fill(.ultraThinMaterial)` | Live translation bar | MIGRATE → `amenGlassBar` |
| `AIIntelligence/AmenAIUsageLabel.swift` | 12 | `.background(.thinMaterial, in: Capsule())` | AI usage label pill | MIGRATE → `amenGlassBar` |
| `BereanDynamicIsland.swift` | 251, 271 | `.blur(radius: 28/12)` | Dynamic island glow | KEEP — decorative |
| `BereanVoiceView.swift` | 224, 232 | `.blur(radius: 60/40)` | Voice background orbs | KEEP — decorative |
| `BereanLiquidGlassSystem.swift` | 122 | `.blur(radius: 0.2)` | Specular edge sub-pixel | KEEP — decorative |
| `BereanEnhancedComposerWrapper.swift` | 119 | `.ultraThinMaterial` (raw) | Composer wrapper background | MIGRATE → `amenGlassCard` |
| `ChatIdentityCard.swift` | 213–691 (~9 hits) | `.fill(.ultraThinMaterial)` / `.fill/.background(.regularMaterial)` | Identity card, avatar ring, controls | MIGRATE → `amenGlassCard` |
| `ChatMemorySheetView.swift` | 84–239 | `.regularMaterial/.ultraThinMaterial` | Memory sheet | MIGRATE → `amenGlassCard` |
| `ChatMemoryCapsuleView.swift` | 62 | `.fill(.ultraThinMaterial)` | Memory capsule | MIGRATE → `amenGlassBar` |
| `VoiceMessageComponents.swift` | 321 | `.fill(.ultraThinMaterial)` | Voice message UI | MIGRATE → `amenGlassBar` |

### Church Notes

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `ChurchNotesView.swift` | 232 | `.background(.ultraThinMaterial, in: Capsule())` | Notes mode pill | Already migrated |
| `ChurchNotesView.swift` | 492–6731 (~50+ hits) | `.fill(.thinMaterial)` / `.fill(.ultraThinMaterial)` | Block editor cells, toolbar chips, section headers | MIGRATE → `amenGlassCard` (blocks) / `amenGlassBar` (chips) |
| `ChurchNotesView.swift` | 898, 1843–2416 (~13 hits) | `.glassEffect(GlassEffectStyle.regular…)` | Block action buttons, quick-insert chips | Already migrated |
| `ChurchNotesDesignSystem.swift` | 63, 98, 121 | `.fill(.ultraThinMaterial)` | Design system shared components | MIGRATE → `amenGlassCard` |
| `ChurchNotesQuickStartView.swift` | 218 | `.fill(.ultraThinMaterial)` | Quick-start card | MIGRATE → `amenGlassCard` |
| `ChurchNotesQuickStartView.swift` | 77 | `.amenGlassEffect(…)` | Quick-start selection | Already migrated |
| `ChurchNotesTabSystem.swift` | 188, 696, 838 | `.background/.fill(.ultraThinMaterial)` | Tab system, category chips | MIGRATE → `amenGlassBar` |
| `ChurchNotes/Views/ChurchNotesBottomActionCapsule.swift` | 31 | `.fill(.ultraThinMaterial)` | Bottom action capsule | MIGRATE → `amenGlassBar` |
| `ChurchNotes/Views/ChurchNotesMetadataCard.swift` | 35, 47 | `.fill(.ultraThinMaterial)` | Metadata card rows | MIGRATE → `amenGlassCard` |
| `ChurchNotePreviewCard.swift` | 337, 369, 407, 516 | `.fill(.ultraThinMaterial)` | Preview card surfaces | MIGRATE → `amenGlassCard` |
| `LivingSermonView.swift` | 291–1594 (~25 hits) | `.fill(.ultraThinMaterial)` | Sermon view blocks, controls, section pills | MIGRATE → `amenGlassCard` (blocks) / `amenGlassBar` (pills) |
| `ChurchSermonArchiveModuleView.swift` | 85–284 (~5 hits) | `.background(.ultraThinMaterial)` | Sermon archive rows | MIGRATE → `amenGlassCard` |
| `SermonIntelligenceEngine.swift` | 382, 532 | `.background(.regularMaterial, …)` | AI insight card | MIGRATE → `amenGlassCard` |
| `ChurchNotesAIService.swift` | 648 | `.background(.regularMaterial, …)` | AI suggestion chip | MIGRATE → `amenGlassBar` |

### Prayer / ARISE / OUTPOUR / Selah

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `PrayerView.swift` | 205 | `.background(.regularMaterial, in: RoundedRectangle(…))` | Prayer card | MIGRATE → `amenGlassCard` |
| `PrayerView.swift` | 506, 791, 1086 | `.blur(radius: 20/30/30)` | Ambient background orbs | KEEP — decorative |
| `PrayerWallView.swift` | 263 | `.background(.ultraThinMaterial.opacity(0.3))` | Prayer wall overlay | MIGRATE → `amenGlassCard` |
| `PrayerWallView.swift` | 500 | `.blur(radius: 10)` | Ambient glow | KEEP — decorative |
| `ModernPrayerWallView.swift` | 244, 374 | `.fill(.ultraThinMaterial)` | Wall request cards / filter chips | MIGRATE → `amenGlassCard` / `amenGlassBar` |
| `DailyPrayerView.swift` | 94, 437 | `.fill(.ultraThinMaterial)` | Daily prayer cards | MIGRATE → `amenGlassCard` |
| `PrayerSuggestedRailView.swift` | 41 | `.presentationBackground(.ultraThinMaterial)` | Suggested prayers sheet | MIGRATE → `amenGlassSheet` |
| `PrayerFulfillmentInsightView.swift` | 28 | `.fill(.ultraThinMaterial)` | Insight card | MIGRATE → `amenGlassCard` |
| `PrayerToolkitView.swift` | 300 | `.blur(radius: 30)` | Toolkit background orb | KEEP — decorative |
| `BreathingExerciseView.swift` | 324 | `.blur(radius: glowRadius)` | Breathing ring glow | KEEP — dynamic glow animation |
| `SelahView.swift` | 422, 464, 561, 588, 772, 806, 1059, 1173 | `.background(.regularMaterial)` / `.fill(.ultraThinMaterial)` | Verse container, mode chips, section cards | MIGRATE → `amenGlassCard` / `amenGlassBar` |
| `SelahPauseOverlay.swift` | 18 | `.fill(.ultraThinMaterial)` | Pause overlay | MIGRATE → `amenGlassCard` |
| `SelahCalmEnhancements.swift` | 258, 381, 432, 526 | `.fill(.ultraThinMaterial/.regularMaterial)` | Calm enhancement panels | MIGRATE → `amenGlassCard` |
| `SelahScripture/SelahScriptureReaderView.swift` | 452–1053 (~14 hits) | `.fill(.ultraThinMaterial)` / `.background(.regularMaterial, in: Capsule())` | Reader controls, nav buttons, annotation chips | MIGRATE → `amenGlassBar` (controls) / `amenGlassCard` (annotation panels) |
| `SelahScripture/SelahScriptureSearchView.swift` | 110 | `Capsule().fill(.ultraThinMaterial)` | Search capsule | MIGRATE → `amenGlassBar` |
| `SelahScripture/SelahLensBar.swift` | 55 | `.background(.ultraThinMaterial, in: Capsule())` | Lens bar | MIGRATE → `amenGlassBar` |
| `SelahScripture/SelahSafetyBannerView.swift` | 92 | `.fill(.regularMaterial)` | Safety banner | **REMOVE** — dense crisis guidance text; use solid high-contrast background |
| `SelahScripture/SelahAIAccessGate.swift` | 144 | `.fill(.ultraThinMaterial)` | Access gate card | MIGRATE → `amenGlassCard` |
| `SelahScripture/SelahReflectionComposerView.swift` | 79 | `.background(.regularMaterial)` | Reflection composer | MIGRATE → `amenGlassCard` |
| `SelahScripture/BereanStudySheetView.swift` | 53 | `.background(.regularMaterial)` | Study sheet chrome | MIGRATE → `amenGlassSheet` |
| `SelahScripture/GuidedSelahSessionView.swift` | 422 | `.background(.ultraThinMaterial, …)` | Session step card | MIGRATE → `amenGlassCard` |
| `LiquidGlassVerseDrawer.swift` | 251–1118 (~14 hits) | `.fill/.background(.ultraThinMaterial)` | Drawer tabs, action pills, content cards | MIGRATE → wrap in one `GlassEffectContainer`; use `amenGlassCard` / `amenGlassBar` + `glassEffectID` |
| `AIBibleStudyView.swift` | 115–154 | `.blur(radius: 70/60/50)` | Background gradient orbs | KEEP — decorative |
| `AIBibleStudyView.swift` | 969 | `.blur(radius: 8)` | Card edge glow | KEEP — decorative |
| `AIBibleStudyExtensions.swift` | 223–407 (~5 hits) | `.background(.regularMaterial, in: RoundedRectangle(…))` | Bible study section cards | MIGRATE → `amenGlassCard` |
| `LiquidGlassAlignmentBanner.swift` | 71 | `.background(.ultraThinMaterial, in: RoundedRectangle(…))` | Alignment banner | MIGRATE → `amenGlassCard` |
| `ServiceModeOverlay.swift` | 95, 145, 159 | `.fill(.ultraThinMaterial)` | Service mode overlay panels | MIGRATE → `amenGlassCard` |

### Spaces / 242 Hub

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `SpacesDiscoveryView.swift` | 112, 338 | `.fill(.ultraThinMaterial)` | Space discovery cards | MIGRATE → `amenGlassCard` |
| `AmenSpaceBannerRail.swift` | 707 | `.background(.ultraThinMaterial, in: Circle())` | Banner rail icon chip | MIGRATE → `amenGlassBar` |
| `AmenSpaceBannerRail.swift` | 1012 | `AnyShapeStyle(.ultraThinMaterial)` with `reduceTransparency` guard | Banner overlay | KEEP-FALLBACK — already guarded |
| `Spaces/Shell/AmenSpacesOnboardingView.swift` | 204, 265, 347 | `.fill(.regularMaterial/.ultraThinMaterial)` | Onboarding cards | MIGRATE → `amenGlassCard` |
| `Spaces/Shell/SpacesListView.swift` | 163 | `if #available(iOS 26.0, *)` | Spaces list item | KEEP-FALLBACK — already branched |
| `Spaces/Shell/SpaceDetailView.swift` | 168 | `if #available(iOS 26.0, *)` | Space detail hero | KEEP-FALLBACK — already branched |
| `Spaces/DesignSystem/SpacesDesignSystem.swift` | multiple | `.glassEffect(…)` / `GlassEffectContainer` | All Spaces design system | Already migrated — reference implementation |
| `SpaceFeedView.swift` | 130, 347 | `.ultraThinMaterial` / `.fill(.ultraThinMaterial)` | Space feed overlay | MIGRATE → `amenGlassCard` |
| `PostToSpaceSheet.swift` | 189, 287 | `.fill(.ultraThinMaterial)` | Post-to-space sheet cards | MIGRATE → `amenGlassCard` |
| `CreateSpaceSheet.swift` | 106, 285 | `.fill(.ultraThinMaterial)` | Space creation cards | MIGRATE → `amenGlassCard` |
| `TwoFourTwoHub.swift` | 166 | `.blur(radius: 10)` | 242 hub background orb | KEEP — decorative |
| `Spaces/Monetization/SpaceLockedView.swift` | 83, 98 | `.blur(radius: 24/4)` | Locked content blur | KEEP — intentional paywall |
| `Spaces/SharedComponents/LockedPreviewShell.swift` | 129 | `.blur(radius: 28)` | Locked preview shell | KEEP — intentional paywall |
| `Spaces/Wizard/WizardConfirmStep.swift` | 86, 208 | `.amenGlassCard()` | Wizard confirm step | Already migrated |
| `Spaces/Wizard/WizardScaffoldStep.swift` | 95, 253, 290 | `.amenGlassCard()` | Wizard scaffold step | Already migrated |
| `PrivateCommunitiesView.swift` | 157 | `.blur(radius: showOnboarding ? 10 : 0)` | Background blur during onboarding | KEEP — intentional context blur |
| `PrivateCommunitiesView.swift` | 4200–4579 (~4 hits) | `.blur(radius: 8/10)` | Ambient glows | KEEP — decorative |

### Comms OS / Messages

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `LiquidGlassMessagesView.swift` | 204, 389, 584, 626, 741, 788, 863 | `.background(.ultraThinMaterial)` | Message list rows, composer, overlays | MIGRATE → `amenGlassCard` (rows) / `amenGlassBar` (composer) |
| `LiquidGlassMessagesView.swift` | 921 | `.blur(radius: 80)` | Background ambient orb | KEEP — decorative |
| `UnifiedChatView.swift` | 1256–6565 (~25 hits) | `.fill/.background(.ultraThinMaterial/.regularMaterial)` | Chat bubbles, input bar, overlays, reaction chips | MIGRATE → `amenGlassCard` (bubbles) / `amenGlassBar` (composer, chips) |
| `UnifiedChatView.swift` | 1704 | `.background(.regularMaterial, in: Capsule())` | Input bar send button area | MIGRATE → `amenGlassBar` |
| `MessagesView.swift` | 3431, 3497, 5289 | `.blur(radius: 4/8/6)` | Message ambient effects | KEEP — decorative |
| `MessagingFilters/MessagingInboxFilterTray.swift` | 109, 161 | `AnyShapeStyle(.thinMaterial/.regularMaterial)` | Filter tray | MIGRATE → `amenGlassBar` inside `GlassEffectContainer` |
| `MessagingFilters/MessagingThreadSearchView.swift` | 131, 176, 268 | `AnyShapeStyle(.thinMaterial)` | Thread search bar | MIGRATE → `amenGlassBar` |
| `AmenMessagingAttachmentMenu.swift` | 252 | `AnyShapeStyle(.regularMaterial)` | Attachment menu | MIGRATE → `amenGlassCard` |
| `SmartMessageIntelligence/SmartMessageActionTray.swift` | 31, 36 | `AnyShapeStyle(.ultraThinMaterial/.regularMaterial)` | Message action tray | MIGRATE → `amenGlassCard` |
| `SmartMessageIntelligence/SmartMessageActionMenu.swift` | 63, 258 | `AnyShapeStyle(.ultraThinMaterial)` | Action menu background | MIGRATE → `amenGlassCard` |
| `SmartMessageIntelligence/AmenSpaceSemanticSearchView.swift` | 49 | `.background(.thinMaterial)` | Semantic search panel | MIGRATE → `amenGlassCard` |
| `Shared/CommsContracts/CommsGlassSystem.swift` | 48–51, 264 | Material enum switch (ultraThin/thin/regular) | Urgency-based glass system | MIGRATE — replace Material enum with `GlassEffectStyle` urgency mapping (see GlassKit §6) |
| `MessageRequestsView.swift` | 66 | `.background(.regularMaterial, in: RoundedRectangle(…))` | Message request card | MIGRATE → `amenGlassCard` |
| `AMENInbox.swift` | 523 | `.blur(radius: 12)` | Inbox ambient | KEEP — decorative |

### Profiles / People Discovery

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `ProfileView.swift` | 1506, 1760, 2112 | `.fill/.background(.ultraThinMaterial)` | Profile stats overlays, bio card | MIGRATE → `amenGlassCard` |
| `ProfileView.swift` | 3414 | `.background(Circle().fill(.regularMaterial))` | Camera button on avatar | MIGRATE → `amenGlassButton` |
| `ProfileView.swift` | 1827 | `.blur(radius: 22, opaque: true)` | Profile hero image blur | KEEP — intentional image treatment |
| `UserProfileView.swift` | 233, 253, 2573, 2691, 3138, 4515, 4536, 4571 | `.fill(.ultraThinMaterial)` | Profile stats, action buttons, follower chips | MIGRATE → `amenGlassCard` (stats) / `amenGlassBar` (action pills) |
| `UserProfileView.swift` | 2283 | `.blur(radius: 22, opaque: true)` | Hero image blur | KEEP — intentional |
| `ProfileHighlightsView.swift` | 89 | `.fill(.ultraThinMaterial)` | Highlight story ring | MIGRATE → `amenGlassBar` |
| `ProfileBannerView.swift` | 181, 291 | `.amenGlassEffect(…)` | Profile banner chips | Already migrated |
| `SuggestedAccountCard.swift` | 268, 294, 311 | `.fill(.ultraThinMaterial)` | Suggested account card | MIGRATE → `amenGlassCard` |
| `SuggestedAccountPeekSheet.swift` | 327 | `.fill(.ultraThinMaterial)` | Peek sheet | MIGRATE → `amenGlassCard` |
| `SuggestedForYouModule.swift` | 367, 393, 414 | `.fill(.ultraThinMaterial)` | Suggested module rows | MIGRATE → `amenGlassCard` |
| `SuggestedFollowsSheet.swift` | 139, 168 | `.fill(.ultraThinMaterial)` | Follow suggestions | MIGRATE → `amenGlassCard` |
| `SuggestionFollowButton.swift` | 76, 88 | `.fill(.ultraThinMaterial)` | Follow button | MIGRATE → `amenGlassButton` |
| `SuggestedFollowsButton.swift` | 21 | `.fill(.ultraThinMaterial)` | Follow button alt | MIGRATE → `amenGlassButton` |
| `FindYourPeopleFTUEView.swift` | 213, 329 | `.fill(.thinMaterial/.regularMaterial)` | FTUE cards | MIGRATE → `amenGlassCard` |
| `TrustedCircleView.swift` | 66–510 (~7 hits) | `.background(.regularMaterial, in: RoundedRectangle(…))` | Trusted circle member cards | MIGRATE → `amenGlassCard` |
| `FollowRequestsView.swift` | 258 | `.background(.regularMaterial, in: RoundedRectangle(…))` | Follow request card | MIGRATE → `amenGlassCard` |
| `FollowingListView.swift` | 148 | `.background(.regularMaterial, in: RoundedRectangle(…))` | Following list row | MIGRATE → `amenGlassCard` |

### Modals / Sheets

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `AMENBottomSheet.swift` | 279 | `.fill(.ultraThinMaterial)` | Bottom sheet background | MIGRATE → `amenGlassSheet` |
| `ImportReviewSheet.swift` | 52 | `.presentationBackground(.ultraThinMaterial)` | Sheet presentation background | MIGRATE → `amenGlassSheet` |
| `ImportReviewSheet.swift` | 84, 95, 165, 417, 514 | `.background(.thinMaterial, in: …)` | Sheet row cells | MIGRATE → `amenGlassCard` |
| `ImportReviewSheet.swift` | 530 | `.background(.ultraThinMaterial, in: RoundedRectangle(…))` | Sheet summary card | MIGRATE → `amenGlassCard` |
| `ReelComposerView.swift` | 110 | `.presentationBackground(.ultraThinMaterial)` | Reel composer sheet | MIGRATE → `amenGlassSheet` |
| `ReelComposerView.swift` | 295 | `.fill(.ultraThinMaterial)` | Composer control chips | MIGRATE → `amenGlassBar` |
| `ReelComposerView.swift` | 134 | `.blur(radius: 60)` | Background orb | KEEP — decorative |
| `Media/Share/QuickShareSheet.swift` | 67 | `.presentationBackground(.ultraThinMaterial)` | Quick share sheet | MIGRATE → `amenGlassSheet` |
| `Media/Share/QuickShareSheet.swift` | 152 | `.fill(.ultraThinMaterial)` | Share option chip | MIGRATE → `amenGlassBar` |
| `Media/Share/ScheduledSendSheet.swift` | 45 | `.presentationBackground(.regularMaterial)` | Scheduled send sheet | MIGRATE → `amenGlassSheet` |
| `VerseDrawerCoordinator.swift` | 60 | `.presentationBackground(.regularMaterial)` | Verse drawer sheet | MIGRATE → `amenGlassSheet` |
| `Media/Faith/WorshipLyricSheet.swift` | 82 | `.presentationBackground(.regularMaterial)` | Lyric sheet | **REMOVE** — dense scrolling text; use solid background |
| `Media/Faith/VersePicker.swift` | 75, 87 | `.background(.ultraThinMaterial)` / `.presentationBackground(.regularMaterial)` | Verse picker | MIGRATE → `amenGlassSheet` (presentation) / `amenGlassCard` (rows) |
| `GrowthArcSheet.swift` | 35–241 (~5 hits) | `.fill(.ultraThinMaterial)` / `.presentationBackground(.ultraThinMaterial)` | Growth arc sheet | MIGRATE → `amenGlassSheet` + `amenGlassCard` |
| `TestimoniesSuggestedRailView.swift` | 41 | `.presentationBackground(.ultraThinMaterial)` | Suggested testimonies sheet | MIGRATE → `amenGlassSheet` |
| `TestimoniesView.swift` | 455 | `.background(.regularMaterial, in: RoundedRectangle(…))` | Testimony card | MIGRATE → `amenGlassCard` |
| `CommunityGuidelinesPrompt.swift` | 68, 118 | `.fill/.background(.ultraThinMaterial)` | Guidelines prompt | MIGRATE → `amenGlassCard` |
| `AppealView.swift` | 185, 221 | `.fill(.ultraThinMaterial)` | Appeal form sections | MIGRATE → `amenGlassCard` |
| `TipView.swift` | 56, 121, 137 | `AnyShapeStyle(.ultraThinMaterial)` with `reduceTransparency` guard | Tip view | KEEP-FALLBACK — already guarded |
| `TipSheetView.swift` | 332 | `.fill(.ultraThinMaterial)` | Tip sheet row | MIGRATE → `amenGlassCard` |
| `InAppReviewPromptView.swift` | 59 | `.fill(.ultraThinMaterial)` | Review prompt card | MIGRATE → `amenGlassCard` |
| `AmenOrgUpgradeSheet.swift` | 291, 307 | `.fill(.ultraThinMaterial)` | Org upgrade sheet cards | MIGRATE → `amenGlassCard` |
| `PremiumUpgradeView.swift` | 56–102 | `.blur(radius: 80/70/30)` | Premium upgrade background orbs | KEEP — decorative |
| `SessionTimeoutManager.swift` | 464, 494, 614, 750 | `.fill/.blur(.ultraThinMaterial)` | Timeout overlay | MIGRATE → `amenGlassCard` |
| `Sharing/BereanShareSheet.swift` | 158, 212 | `.background(.ultraThinMaterial)` | Share sheet | MIGRATE → `amenGlassCard` / `amenGlassSheet` |

### Find Church / Church Features

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `FindChurchView.swift` | 2530–6771 (~20 hits) | `.fill(.ultraThinMaterial)` | Church cards, action chips, map overlays | MIGRATE → `amenGlassCard` / `amenGlassBar` |
| `FindChurchView.swift` | 1297, 4248, 4323–4942 | `.glassEffect(…)` | Church filter chips, action buttons | Already migrated |
| `FindChurchView.swift` | 6375 | `.fill(.regularMaterial)` | Church detail panel | MIGRATE → `amenGlassCard` |
| `FindChurchGlassComponents.swift` | 85, 510–876 (~6 hits) | `.glassEffect(.subtle…)` | Church glass components | Already migrated |
| `FindChurchGlassComponents.swift` | 142 | `Rectangle().fill(.ultraThinMaterial)` | Separator bar | **REMOVE** → use `Color.separator` |
| `ChurchPillCard.swift` | 60, 155 | `.glassEffect(.subtle/.regular…)` | Church pill card | Already migrated |
| `EnhancedChurchCard.swift` | 43–246 | `.glassEffect(.subtle…)` | Enhanced church card chips | Already migrated |
| `SmartChurchSearch/ChurchDetailView.swift` | 30, 43, 159 | `.background/.fill(.ultraThinMaterial)` | Church detail info cards | MIGRATE → `amenGlassCard` |
| `SmartChurchSearch/ChurchSearchView.swift` | 88, 202 | `.background(.ultraThinMaterial, in: RoundedRectangle(…))` | Search results | MIGRATE → `amenGlassCard` |
| `SmartChurchSearch/SmartChurchBereanFinderView.swift` | 140–237 | `.background(.ultraThinMaterial)` | Berean finder cards | MIGRATE → `amenGlassCard` |
| `SmartChurchSearch/ChurchGoogleMapsView.swift` | 225 | `.background(.ultraThinMaterial, in: Capsule())` | Map overlay pill | MIGRATE → `amenGlassBar` |
| `SmartCommunitySearch/SmartCommunitySearchBar.swift` | 52 | `AnyShapeStyle(.ultraThinMaterial)` with `reduceTransparency` guard | Search bar | KEEP-FALLBACK — already guarded |
| `SmartCommunitySearch/BereanChurchFinderView.swift` | 243, 343, 378, 406 | `.background(.ultraThinMaterial/.regularMaterial)` | Finder cards and chips | MIGRATE → `amenGlassCard` / `amenGlassBar` |
| `SmartCommunitySearch/SmartCommunitySearchView.swift` | 73 | `.background(.ultraThinMaterial)` | Search view container | MIGRATE → `amenGlassCard` |
| `SmartCommunitySearch/SmartCommunityRefinementChips.swift` | 19 | `.background(.ultraThinMaterial, in: Capsule())` | Refinement chips | MIGRATE → `amenGlassBar` inside `GlassEffectContainer` |
| `ChurchRadarView.swift` | 101, 240 | `.fill(.ultraThinMaterial)` | Radar card | MIGRATE → `amenGlassCard` |
| `ChurchLiveModeView.swift` | 324–599 (~8 hits) | `.fill/.background(.ultraThinMaterial)` with `reduceTransparency` guards | Live mode overlays, controls | KEEP-FALLBACK where guarded; MIGRATE where unguarded |
| `ChurchEditProfileView.swift` | 515, 680 | `.background(.ultraThinMaterial)` | Edit profile panels | MIGRATE → `amenGlassCard` |
| `ChurchAssistSheet.swift` | 47 | `.fill(.ultraThinMaterial)` | Assist sheet card | MIGRATE → `amenGlassCard` |
| `ChurchCapsuleView.swift` | 42 | `.fill(.ultraThinMaterial)` | Church identifier capsule | MIGRATE → `amenGlassBar` |
| `ChurchFirstVisitGuideView.swift` | 148–232 | `.background(.regularMaterial)` | First visit guide cards | MIGRATE → `amenGlassCard` |
| `FirstVisitCompanionCard.swift` | 122 | `.fill(.ultraThinMaterial)` | Companion card | MIGRATE → `amenGlassCard` |
| `VisitMemoryCard.swift` | 105 | `.fill(.ultraThinMaterial)` | Visit memory | MIGRATE → `amenGlassCard` |

### Resources / Studio / Creator

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `ResourcesView.swift` | 408–3562 (~30 hits) | `.fill(.ultraThinMaterial)` / `.background(.regularMaterial)` | Resource cards, category chips, media tiles | MIGRATE → `amenGlassCard` / `amenGlassBar` |
| `AMENResourcesHubView.swift` | 695 | `.fill(.ultraThinMaterial)` | Resources hub card | MIGRATE → `amenGlassCard` |
| `StudioProfileView.swift` | 154–886 (~7 hits) | `.background(.ultraThinMaterial, in: …)` | Studio profile: stat cards, control chips | MIGRATE → `amenGlassCard` / `amenGlassBar` |
| `StudioDiscoveryView.swift` | 456–600 (~4 hits) | `.background(.ultraThinMaterial, in: RoundedRectangle(…))` | Discovery cards | MIGRATE → `amenGlassCard` |
| `StudioJournalView.swift` | 141, 153, 279 | `.background(Circle().fill/.fill(.ultraThinMaterial))` | Journal nav buttons, category pill | MIGRATE → `amenGlassButton` (circles) / `amenGlassBar` (pill) |
| `StudioPaywallView.swift` | 57, 170 | `.fill(.ultraThinMaterial)` | Paywall cards | MIGRATE → `amenGlassCard` |
| `StudioShopView.swift` | 131 | `.background(.ultraThinMaterial, in: RoundedRectangle(…))` | Shop product card | MIGRATE → `amenGlassCard` |
| `LegacyStudioView.swift` | 249, 357, 588, 682 | `AnyShapeStyle(.ultraThinMaterial)` / `.background(.ultraThinMaterial)` | Legacy studio | MIGRATE → `amenGlassCard` |
| `SynapticStudioView.swift` | 302, 377, 641 | `.fill(.ultraThinMaterial)` | Synaptic studio cards | MIGRATE → `amenGlassCard` |
| `VergeCreatorStudioView.swift` | 395 | `AnyShapeStyle(.ultraThinMaterial)` | Creator studio surface | MIGRATE → `amenGlassCard` |
| `VergeCreateRoomSheet.swift` | 339, 346 | `AnyShapeStyle(.ultraThinMaterial/.regularMaterial)` | Room creation sheet | MIGRATE → `amenGlassCard` |
| `AmenSyncStudioView.swift` | 81, 207, 539 | `.fill(.ultraThinMaterial/.regularMaterial)` | Sync studio surfaces | MIGRATE → `amenGlassCard` |
| `AmenSyncHubCard.swift` | 67 | `.fill(.ultraThinMaterial)` | Sync hub card | MIGRATE → `amenGlassCard` |
| `CreatorSubscriptionGateView.swift` | 36, 139, 261 | `.blur(radius: 2)` / `.fill/.background(.ultraThinMaterial)` | Creator gate overlay | KEEP blur (intentional paywall); MIGRATE glass surfaces |
| `Creator/Components/CreatorGlassCard.swift` | 13 | `.amenGlassSurface(…)` | Creator glass card | Already migrated |
| `Creator/Components/CreatorGlassButton.swift` | 16 | `.buttonStyle(.amenGlass(…))` | Creator glass button | Already migrated |

### Settings / Onboarding / Utility

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `SettingsView.swift` | 216, 421, 444, 480 | `AnyShapeStyle(.ultraThinMaterial/.thinMaterial)` | Settings header, section toggles | MIGRATE → `amenGlassCard` |
| `AccountSettingsView.swift` | 321–1252 (~15 hits) | `.background(.regularMaterial, in: RoundedRectangle(…))` | Settings list rows (dense text) | **REMOVE** — use system grouped list background |
| `PrivacyControlsSettingsView.swift` | 94–231 (~4 hits) | `.background(.regularMaterial)` | Privacy settings rows (dense text) | **REMOVE** — solid card |
| `HelpSupportView.swift` | 71–270 (~4 hits) | `.background(.regularMaterial)` | Help FAQ rows (multi-line) | **REMOVE** — solid card |
| `AboutAmenView.swift` | 74–728 (~9 hits) | `.background(.regularMaterial)` | About / policy rows (long-form text) | **REMOVE** — solid card |
| `SecurityCenterView.swift` | 216–363 (~3 hits) | `.background(.regularMaterial)` | Security action rows (dense text) | **REMOVE** — solid card |
| `ActiveSessionsView.swift` | 135, 223 | `.background(.regularMaterial)` | Session rows | **REMOVE** — solid card |
| `ScrollBudgetSettingsView.swift` | 36–180 (~5 hits) | `.background(.regularMaterial)` | Scroll budget rows | **REMOVE** — solid card |
| `AccountLinkingView.swift` | 49, 262, 311 | `.background(.regularMaterial)` | Account linking action cards | MIGRATE → `amenGlassCard` (these are action cards, not dense text) |
| `AMENOnboardingSystem.swift` | 83–546 (~8 hits) | `.fill(.thinMaterial/.regularMaterial/.ultraThinMaterial)` | Onboarding cards, pearl card, step indicators | MIGRATE → `amenGlassCard` |
| `WelcomeToAMENView.swift` | 574 | `.fill(.ultraThinMaterial)` | Welcome card | MIGRATE → `amenGlassCard` |
| `AMENAccountTypeOnboardingView.swift` | 309, 417, 443 | `.fill(.ultraThinMaterial)` | Onboarding type selection | MIGRATE → `amenGlassCard` |
| `SignInView.swift` | 636 | `.blur(radius: 1)` | Background subtle | KEEP — decorative |
| `AgeVerificationOnboardingView.swift` | 30, 37 | `.blur(radius: 80/60)` | Onboarding background orbs | KEEP — decorative |
| `AmenConnectProfileSetup.swift` | 380 | `.blur(radius: isEmailVerified ? 0 : 20)` | Email verification gate | KEEP — intentional gating |
| `MinimalAuthenticationView.swift` | 315 | `.fill(.ultraThinMaterial)` | Auth form panel | MIGRATE → `amenGlassCard` |
| `PhoneVerificationView.swift` | 55, 64, 108 | `.background(.regularMaterial)` | OTP input boxes | **REMOVE** — input fields must have solid backgrounds |
| `ProfileImageSetupView.swift` | 276 | `AnyShapeStyle(.regularMaterial)` with `reduceTransparency` guard | Profile setup panel | KEEP-FALLBACK — guarded |
| `ProfileImageSetupView.swift` | 363, 545 | `AnyShapeStyle(.regularMaterial)` | Profile setup panel (unguarded) | MIGRATE → `amenGlassCard` |
| `KoraRootView.swift` | 250 | `.background(.ultraThinMaterial)` | Kora root panel | MIGRATE → `amenGlassCard` |
| `KoraCheckInDetailView.swift` | 199, 281 | `.background(.ultraThinMaterial)` | Check-in detail cards | MIGRATE → `amenGlassCard` |
| `AutoLoginSplashView.swift` | 43–81 | `.blur(radius: 70/60)` + `.fill(.ultraThinMaterial)` | Splash bg orbs / card | KEEP blur; MIGRATE glass card |
| `DesignSystem/AdaptiveInterface/AmenAdaptiveInterfaceSystem.swift` | 129, 239–246 | `AnyShapeStyle(.ultraThinMaterial/.regularMaterial/.thinMaterial)` | Adaptive interface system | KEEP-FALLBACK — progressive material selector; evolve toward `GlassEffectStyle` variants |
| `DesignSystem/Prompts/AmenSmartPromptBanner.swift` | 121 | `.background(.regularMaterial)` | Prompt banner | MIGRATE → `amenGlassCard` |
| `SmartPrompts/AmenContextualPromptCard.swift` | 142 | `.background(.ultraThinMaterial)` | Contextual prompt card | MIGRATE → `amenGlassCard` |
| `NotificationSettingsView.swift` | 158–549 | `.glassEffect(GlassEffectStyle.regular…)` | Notification settings rows | Already migrated |
| `WellbeingDashboardView.swift` | 77–158 (~4 hits) | `.background(.regularMaterial)` | Wellbeing metric cards | MIGRATE → `amenGlassCard` |
| `Wellness/WellnessCrisisSurfaceCard.swift` | 109 | `.fill(.ultraThinMaterial)` | Crisis surface card | **REMOVE** — crisis text must be on high-contrast solid background |

### Scroll-Reactive / UIKit Bridge

| File | Line(s) | Current Modifier | UI Element | Classification |
|---|---|---|---|---|
| `ScrollReactiveGlass.swift` | 58–68 | `UIVisualEffectView(effect: UIBlurEffect(style:))` | Scroll-reactive blur bridge | KEEP-FALLBACK — GPU-composited backdrop; evaluate `scrollEdgeEffectStyle` on iOS 26 |
| `EnhancedUIComponents.swift` | 227–234 | `UIVisualEffectView / UIBlurEffect(.systemMaterialDark)` | Dark material bridge | KEEP-FALLBACK — explicit dark media UI; annotate `// pre-iOS26 fallback` |
| `GlassEffectModifiers.swift` | 330–366 | `UIVisualEffectView / UIBlurEffect` | Top-edge blur bridge | KEEP-FALLBACK — edge fade; evaluate `scrollEdgeEffectStyle` on iOS 26 |
| `AdaptiveLiquidGlassHeader.swift` | 44, 85, 90 | `.fill(.ultraThinMaterial)` / `.blur(radius: 0.8/8)` | Adaptive header glass | MIGRATE → `amenGlassBar`; blurs are decorative |
| `LiquidGlassCapsuleBackground.swift` | 20, 71 | `.fill(.ultraThinMaterial)` / `.blur(radius: 0.4)` | Capsule background + specular | MIGRATE → `amenGlassBar`; micro-blur is specular |
| `LiquidGlassAdaptiveSurface.swift` | 13 | `.fill(.ultraThinMaterial)` | Adaptive glass surface primitive | MIGRATE → `amenGlassCard` |
| `LiquidGlassUploadCapsule.swift` | 243, 259 | `.blur(radius: 0.4/0.8)` | Upload capsule specular | KEEP — sub-pixel decorative |
| `LiquidGlassAnimations.swift` | 20, 199 | `.blur(radius: 8/4)` | Merge animation transition | KEEP — animation state blur |
| `LiquidGlassMotion.swift` | 123, 128, 191 | `.glassEffect(…)` / `.glassEffectID(…)` | Motion system | Already migrated |
| `LiquidGlassMediaComponents.swift` | 115–312 (~4 hits) | `.fill(.ultraThinMaterial)` | Media player controls | MIGRATE → `amenGlassBar` |
| `LiquidGlassButtons.swift` | 54, 90 | `.fill(.ultraThinMaterial)` | Glass button surfaces | MIGRATE → `amenGlassButton` |

---

## 2. Native Freebies

**Deployment target: iOS 17.0** — `#available(iOS 26, *)` gates required on all `.glassEffect()` calls.

| Surface | Current Code | Notes |
|---|---|---|
| `NavigationStack` chrome | All `NavigationStack` usage | Nav bar adopts Liquid Glass automatically on iOS 26 |
| `.sheet` / `.fullScreenCover` chrome | All sheet presentations | Gripper + chrome auto-glassed on iOS 26 |
| `Menu { }` | Any `Menu {}` | Menus auto-adopt Liquid Glass on iOS 26 |
| `.confirmationDialog` | Any `.confirmationDialog(…)` | Action sheets auto-adopt Liquid Glass on iOS 26 |
| `.toolbarBackground(.ultraThinMaterial, for: .navigationBar)` | `TipSheetView.swift:56`, `VergeCreatorStudioView.swift:58`, `VergeCreateRoomSheet.swift:79`, `StartCoCreationSheet.swift:184`, `CoCreationSummaryView.swift:109` | 5 calls become redundant on iOS 26; wrap in `#unavailable(iOS 26)` guard |
| `.presentationBackground(.ultraThinMaterial/.regularMaterial)` | `PrayerSuggestedRailView:41`, `TestimoniesSuggestedRailView:41`, `ReelComposerView:110`, `ImportReviewSheet:52`, `GrowthArcSheet:107` | Sheet backgrounds get system Liquid Glass — explicit `presentationBackground` may override; evaluate per-case |

> **AMENTabBar is NOT a freebie** — it is fully custom and must be manually migrated. The iOS 26 `TabView` freebie does not apply.

---

## 3. Risk List

### Glass-on-Glass Stacks (must use `GlassEffectContainer` or remove inner glass)

1. **`Wellness/WellnessInsightSection.swift:40–60`** — `WellnessRhythmCard` puts `.background(.ultraThinMaterial)` on an inner card nested inside an outer `.background(.regularMaterial)` container. Two separate glass layers stack without `GlassEffectContainer`. → Remove inner glass; use solid `AmenTheme.Colors.backgroundGroupedRow` for inner card.

2. **`BereanChatView.swift` (multiple sites)** — Suggestion chips (`.fill(.ultraThinMaterial)`) render inside a message tray that itself uses `.fill(.ultraThinMaterial)`. Glass inside glass. → Wrap chip row in `GlassEffectContainer(spacing: 8)`, or use solid chip backgrounds.

3. **`LiquidGlassVerseDrawer.swift` (~14 material sites)** — Root drawer has `.fill(.ultraThinMaterial)` and inner action Capsules / RoundedRectangles each also use `.fill(.ultraThinMaterial)`. Full glass-on-glass stack. → Migrate entire drawer into one `GlassEffectContainer`; give each action element a `glassEffectID` for morph animations.

4. **`ChurchNotesView.swift`** — Block editor nests `.fill(.thinMaterial)` cells inside `.background(.ultraThinMaterial)` section containers. → Move all block glass into a single `GlassEffectContainer` per section; blocks use `glassEffectID`.

5. **`ResourcesView.swift`** — 30+ material hits inside a scroll view that itself uses `.background(.ultraThinMaterial)` scroll edges. → Scroll view background should be `.background(.clear)`; cards use `GlassEffectContainer` per horizontal row group.

6. **`UnifiedChatView.swift` input bar area (lines 6089–6497)** — Multiple `.background(.ultraThinMaterial)` elements composing the input bar area with sub-components also using `.fill(.ultraThinMaterial)`. → Consolidate entire input bar into one `GlassEffectContainer`.

7. **`AMENOnboardingSystem.swift:240`** — `.fill(.regularMaterial)` step indicator inside `.fill(.thinMaterial)` outer card container. → Use solid fill for inner step indicator.

### Glass Behind Dense / Long Text (must be solid)

1. **`AccountSettingsView.swift`** — 15 settings rows use `.regularMaterial`. Dense 1–2 line labels with disclosure chevrons. → Use system grouped list background: `.listRowBackground(Color(.secondarySystemBackground))`.

2. **`AboutAmenView.swift`** — 9 informational / legal text rows using `.regularMaterial`. Long-form text. → Solid card.

3. **`HelpSupportView.swift`** — 4 FAQ-style multi-line answer cards using `.regularMaterial`. → Solid card.

4. **`SecurityCenterView.swift`** — Security action rows with dense text on `.regularMaterial`. → Solid card.

5. **`PrivacyControlsSettingsView.swift`** — Long privacy toggle descriptions on `.regularMaterial`. → Solid card.

6. **`Media/Faith/WorshipLyricSheet.swift:82`** — Full lyric sheet with `.presentationBackground(.regularMaterial)`. Lyrics = dense scrolling text. → Solid background (dark `Color(.systemBackground)` in dark mode, warm cream in light mode consistent with Selah reading surfaces).

7. **`SelahScripture/SelahSafetyBannerView.swift:92`** — Safety banner with dense crisis guidance text on `.fill(.regularMaterial)`. → High-contrast solid background; safety messaging must never appear on glass.

8. **`PhoneVerificationView.swift:55/64/108`** — OTP input boxes on `.regularMaterial`. Input fields need solid backgrounds for legibility and tap area clarity. → `Color(.secondarySystemBackground)`.

9. **`Wellness/WellnessCrisisSurfaceCard.swift:109`** — Crisis surface card using `.fill(.ultraThinMaterial)`. → Solid background; same rule as SelahSafetyBanner.

### Clusters Needing `GlassEffectContainer`

| Location | Elements to group | Spacing |
|---|---|---|
| `AMENTabBar.swift` | Tab item capsules + orbs + selection pill | `spacing: 0` for liquid morph between tabs |
| `BereanComposerTray.swift` | Handle, mode chips, input bar sub-components | `spacing: 4` |
| `SmartCommunitySearch/SmartCommunityRefinementChips.swift` | Filter chip row | `spacing: 8` |
| `FindChurchView.swift:4323–4466` | Filter chip row (uses `.glassEffect` but no container) | `spacing: 8` |
| `LiquidGlassVerseDrawer.swift` | Entire drawer as one logical glass surface | `spacing: 0` |
| `MessagingFilters/MessagingInboxFilterTray.swift` | Filter tray pill group | `spacing: 8` |
| `BereanMessageMenuView.swift` | Long-press action menu items | `spacing: 4` |

---

## 4. Already Migrated

| File | Pattern | Notes |
|---|---|---|
| `LiquidGlass/AmenGlassKit.swift` | `amenGlassEffect(tint:in:)` wrappers | Central kit — definitive reference |
| `GlassEffectModifiers.swift` | `GlassEffectContainer`, `glassEffectID`, `glassEffect(_:in:)` | Polyfill shim |
| `AMENTabBar.swift` | Triple-branch: reduceTransparency → solid / `#available(iOS 26)` → glassEffect / else → .ultraThinMaterial | Model branching pattern |
| `Spaces/DesignSystem/SpacesDesignSystem.swift` | `GlassEffectContainer`, `glassEffect(.regular.tint(…))`, `glassEffectID` | Most complete iOS 26 integration in app |
| `ChurchNotesView.swift` | `glassEffect(GlassEffectStyle.regular…)` on block action buttons (13 sites) | Partial — block containers still need migration |
| `FindChurchView.swift` | `.glassEffect(.subtle/regular…)` (10 sites) | Partial — many cards still on `.ultraThinMaterial` |
| `FindChurchGlassComponents.swift` | `.glassEffect(.subtle…)` | Fully migrated |
| `EnhancedChurchCard.swift` | `.glassEffect(.subtle…)` | Fully migrated |
| `ChurchPillCard.swift` | `.glassEffect(.subtle/.regular…)` | Fully migrated |
| `NotificationSettingsView.swift` | `GlassEffectStyle.regular` / `.interactive()` | Fully migrated |
| `LiquidGlassMotion.swift` | `.glassEffect(…)` / `.glassEffectID(…)` | Motion system fully migrated |
| `LiquidGlass/AMENCategoryChips.swift` | Triple-branch with `#available(iOS 26)` | Model for chip migration |
| `LiquidGlass/AMENActionRail.swift` | Triple-branch with `#available(iOS 26)` | Model for circular button migration |
| `LiquidGlass/AMENActionSheet.swift` | `#available(iOS 26)` branch | Fully migrated |
| `AMENAPP/PinnedPostGlassSystem.swift` | `.amenGlassEffect(…)` / `.glassEffectID(…)` | Fully migrated |
| `AMENAPP/PinnedProfileHeroSurface.swift` | `.amenGlassEffect(…)` / `.glassEffectID(…)` | Fully migrated |
| `AMENAPP/AmenTheme.swift` | `amenGlassCard`, `amenGlassInputBar` modifier definitions | Helpers defined but use raw material internally — upgrade needed |
| `FeedComposerRow.swift` | `.buttonStyle(.amenGlass(…))` | Button migrated |
| `Creator/` (entire subdirectory) | `.amenGlassSurface(…)`, `.buttonStyle(.amenGlass(…))` | Creator OS fully migrated |
| `CreatorSpaces/` | `.amenGlassEffect(…)` / `.amenGlassSurface(…)` | Fully migrated |
| `ProfileBannerView.swift` | `.amenGlassEffect(…)` | Fully migrated |
| `WellnessRiskLayer.swift` | `.amenGlassCard(cornerRadius:)` | Fully migrated |
| `CustomFeeds/CustomFeedsView.swift` | `.amenGlassCard()` | Fully migrated |
| `OpenTableView.swift` | `.amenGlassCard(…)` | Feed cells fully migrated |
| `ContextualExperiences/AmenContextualExperienceViews.swift` | `.glassEffect(interactive:…)` with `#available` gate | Fully migrated |
| `LongitudinalSelfView.swift` | `.glassEffect(GlassEffectStyle.regular.tint(…).interactive(), in: RoundedRectangle(…))` | Fully migrated |
| `AMENAPP/TrendingViews.swift` | `GlassEffectContainer { }` | Fully migrated |
| `Composer/ComposerStickerPicker.swift` | `.amenGlassInputBar(…)` | Fully migrated |
| `Composer/ComposerMediaGIFPicker.swift` | `.amenGlassCard()` / `.amenGlassInputBar()` | Fully migrated |
| `Composer/ComposerCommunityPicker.swift` | `.amenGlassInputBar(…)` | Fully migrated |
| `Composer/ComposerMusicPicker.swift` | `.amenGlassCard(…)` / `.amenGlassInputBar()` | Fully migrated |

---

## 5. Summary Counts

| Classification | Count |
|---|---|
| **MIGRATE** | ~430 unique line-level sites across ~130 files |
| **KEEP-FALLBACK** | ~25 sites |
| **REMOVE** | ~60 sites (dense-text settings rows + safety/crisis surfaces + OTP inputs) |
| **NATIVE-FREEBIE** | 5 `.toolbarBackground` calls + all `.sheet` / `NavigationStack` chrome |
| **Already migrated** | ~35 files / ~250 call sites |
| **UIKit bridges** | 4 sites in 3 files (`ScrollReactiveGlass`, `EnhancedUIComponents`, `GlassEffectModifiers`) |
| **Total faux-glass sites** (MIGRATE + KEEP-FALLBACK + REMOVE) | ~515 |

### By Feature Area (MIGRATE count only)

| Feature | MIGRATE sites |
|---|---|
| Church Notes (`ChurchNotesView` alone) | ~70 |
| Berean AI (`BereanChatView` + design system) | ~60 |
| Living Sermon / Sermon Archive | ~35 |
| Resources View | ~30 |
| Selah / Prayer / ARISE | ~40 |
| Unified Chat / Messages | ~35 |
| Find Church (partial — many already done) | ~20 |
| Profiles / People Discovery | ~25 |
| Settings rows (REMOVE, not MIGRATE) | ~60 |
| Spaces | ~15 |
| Studio / Creator | ~25 |
| Modals / Sheets | ~30 |
| Onboarding / Auth | ~15 |
| Other | ~20 |

---

## 6. GlassKit.swift — Required Helpers

All should live in `LiquidGlass/AmenGlassKit.swift` (or expand the existing file). Internal branching:
```
if #available(iOS 26, *) {
    if reduceTransparency { solid fallback } else { .glassEffect(…) }
} else {
    .ultraThinMaterial  // genuine pre-iOS26 fallback
}
```

### `amenGlassCard(cornerRadius:tint:shadow:)`
**Used for:** Feed cells, Berean chat panels, Church Notes block containers, verse drawer content, Selah session step cards, resource cards, testimony cards, Spaces content cards, studio discovery cards, profile stat panels, growth arc cards.  
Any standalone card-shaped container that floats above a scroll view or hero background.  
**iOS 26:** `Glass.regular.tint(tint)`  
**Note:** Currently exists in `AmenTheme.swift` using raw `.ultraThinMaterial` — must be upgraded.

### `amenGlassBar(cornerRadius:tint:)` *(new helper — does not yet exist)*
**Used for:** Tab pill chrome (`CompactTopChromeView`), `NowPlayingBar`, `BereanFloatingTabBar`, `RoleAwareComposerPresetBar`, HeyFeed filter pills, mode-control bars, translation bars, search bars, live caption pills, AI usage labels, filter chips, suggestion chips, church capsule, bottom action capsules.  
Any horizontal pill/capsule/bar element that floats over content.  
**iOS 26:** `Glass.regular` (or `.subtle` for de-emphasized chips)

### `amenGlassButton(shape:tint:)` *(new helper — does not yet exist)*
**Used for:** Profile camera overlay buttons (circular on avatar), `StudioJournalView` nav circles, `SuggestionFollowButton`, `LiquidGlassButtons`, standalone icon-button chips.  
Any circle or small rounded-rect tappable glass button.  
**iOS 26:** `Glass.regular.interactive()`

### `amenGlassSheet(tint:)` *(extract from `SpacesDesignSystem` to app-wide GlassKit)*
**Used for:** `presentationBackground` on `PrayerSuggestedRailView`, `TestimoniesSuggestedRailView`, `GrowthArcSheet`, `QuickShareSheet`, `ImportReviewSheet`, `VerseDrawerCoordinator`, `BereanStudySheetView`, `SelahReflectionComposerView`.  
Currently exists only in `SpacesDesignSystem.swift` — must be promoted to GlassKit.

### `amenGlassInputBar(cornerRadius:)` *(upgrade existing)*
**Used for:** Composer bars in `BereanComposerTray`, `BereanChatView` input, `UnifiedChatView` input, `MessagingInboxFilterTray`, all `Composer/*` pickers.  
Already implemented in `AmenTheme.swift` and `BereanDesignSystem.swift` using raw `.ultraThinMaterial` — must be upgraded behind `#available(iOS 26, *)`.

### `AmenGlassUrgencyStyle` → `GlassEffectStyle` mapping *(new)*
Replace the `CommsGlassSystem.swift` urgency-to-`Material` switch:
```swift
// Replace:  urgency -> Material.ultraThinMaterial / .thinMaterial / .regularMaterial
// With:     urgency -> GlassEffectStyle
.low      → .subtle
.medium   → .regular
.high     → .regular.tint(amenOrange.opacity(0.12))
.critical → .regular.tint(amenRed.opacity(0.16))
```
Centralise this mapping in GlassKit so `CommsGlassSystem.swift` calls it instead of branching on Material internally.

---

## 7. Open Questions for Steph

These are design decisions that should be confirmed before Phase 1 implementation begins:

1. **`amenGlassInputBar` upgrade path:** `AmenGlassInputBarModifier` in both `AmenTheme.swift` and `BereanDesignSystem.swift` currently uses raw `.ultraThinMaterial`. On iOS 26, `Glass.regular` provides its own backdrop — should the existing `.ultraThinMaterial` fill be removed inside the `#available` branch, or kept as a visual fallback layer? The `AmenGlassKit.swift` pattern (lines 508–545) shows the correct triple-branch approach — confirm that's the target for all three modifier definitions.

2. **ChurchNotesView transitional state:** The file has 50+ unmigrated material sites mixed with 13 already-migrated `.glassEffect(GlassEffectStyle.regular…)` sites on the same screen. Is a transitional state acceptable (some blocks iOS-26-native, some material-based), or should the entire screen migrate atomically in one phase?

3. **WorshipLyricSheet solid background color:** Classified REMOVE (dense scrolling lyric text). Confirm: should the replacement be dark `Color(.systemBackground)` in dark mode and a warm cream in light mode, consistent with AMEN's Selah reading surfaces?

4. **Settings rows pattern:** `AccountSettingsView`, `AboutAmenView`, `HelpSupportView`, `SecurityCenterView`, `PrivacyControlsSettingsView` — all REMOVE. Confirm: native `List` with `.listRowBackground(Color(.secondarySystemBackground))`, or the existing `AmenFlatCardModifier`?

5. **`GlassEffectModifiers.swift` shim deprecation:** The file ships a hand-rolled `GlassEffectContainer` shim (lines 15–28) that adds padding only — not true CABackdropLayer union semantics. On iOS 26, the system `GlassEffectContainer` merges glass shapes properly. Should the shim be deprecated with all call sites gated `#available(iOS 26, *)`? Or is a visual-only approximation acceptable as the pre-iOS26 fallback?

---

## Proposed Phase Order (after Steph approves)

| Phase | Feature Area | Files | Estimated sites |
|---|---|---|---|
| 1 | GlassKit.swift — add `amenGlassBar`, `amenGlassButton`, promote `amenGlassSheet`, upgrade `amenGlassInputBar` | `LiquidGlass/AmenGlassKit.swift`, `AmenTheme.swift`, `BereanDesignSystem.swift` | 0 (infrastructure only) |
| 2 | Nav / Tab Chrome | `CompactTopChromeView`, `NowPlayingBar`, `BereanFloatingTabBar`, UIKit bridges | ~15 |
| 3 | HeyFeed / OpenTable remaining | `FeedComposerRow`, `HeyFeedTuningPill`, `PostDetailView`, `ActivityFeedView`, etc. | ~30 |
| 4 | Berean AI | `BereanDesignSystem`, `BereanChatView`, `BereanLandingView`, tray + capsule + companion files | ~60 |
| 5 | Church Notes | `ChurchNotesView` (large), `ChurchNotesDesignSystem`, `LivingSermonView` | ~80 |
| 6 | Prayer / Selah / ARISE | `SelahView`, `PrayerView`, `SelahScripture/*`, `LiquidGlassVerseDrawer` | ~45 |
| 7 | Comms OS / Messages | `UnifiedChatView`, `LiquidGlassMessagesView`, `MessagingFilters/*`, `CommsGlassSystem` | ~40 |
| 8 | Find Church remaining | `SmartChurchSearch/*`, `SmartCommunitySearch/*`, `ChurchLiveModeView` | ~25 |
| 9 | Profiles / People Discovery | `UserProfileView`, `ProfileView`, suggested-* files | ~30 |
| 10 | Spaces remaining | `SpacesDiscoveryView`, `SpaceFeedView`, `PostToSpaceSheet` | ~15 |
| 11 | Studio / Creator remaining | `ResourcesView`, `StudioProfileView`, `LegacyStudioView`, etc. | ~35 |
| 12 | Modals / Sheets / Onboarding | `AMENBottomSheet`, `AMENOnboardingSystem`, `ImportReviewSheet`, etc. | ~40 |
| 13 | Settings REMOVE pass | `AccountSettingsView`, `AboutAmenView`, `HelpSupportView`, etc. | ~60 REMOVE |
| 14 | Glass-on-glass fix pass | `BereanChatView` chips, `LiquidGlassVerseDrawer`, `UnifiedChatView` input bar, `ResourcesView` | Risk list items |

**Build must pass green after each phase before the next begins.**

---

*PHASE 0 COMPLETE — no code has been changed. Awaiting approval to proceed to Phase 1.*
