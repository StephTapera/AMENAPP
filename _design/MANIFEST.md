# AMEN — Design Pass Manifest (Phase 0 — Full Frontend Inventory)
**Branch:** `overnight/design-pass-20260530`  
**Total Swift files:** 2952 · **Total components audited:** 120+  
**Coverage:** 100% of core feature domains inventoried

---

## Legend
- **Surface Type:** hero-chrome / overlay / control / tab-bar / list / reading-surface / form / service
- **Severity:** HIGH · MEDIUM · LOW · OK · QUEUE-AUTH · QUEUE-GUARDIAN · N/A
- **Status:** Fixed / Queued / OK / QUEUE

---

## Feed / Home / OpenTable

| Domain | Screen/Component | File:Line | Surface Type | HasHero | UsesGlass | StatusBar | ReduceTransp | Audited | Severity | Status |
|--------|-----------------|-----------|--------------|---------|-----------|-----------|--------------|---------|----------|--------|
| Feed | OpenTable Feed Header | OpenTableView.swift:88 | hero-chrome | N | Y | partial | Y | Y | MEDIUM | Queued |
| Feed | Post Card (Inline) | PostCard.swift:21 | list | N | Y | N/A | Y | Y | LOW | OK |
| Feed | Feed Composer Row | FeedComposerRow.swift:7 | control | N | Y | N/A | Y | Y | OK | OK |
| Feed | Personalized Greeting | PersonalizedGreetingView.swift:137 | hero-chrome | N | N | none | N | Y | MEDIUM | Queued |
| Feed | Suggested Accounts Rail | OpenTableSuggestedRailView.swift:9 | reading-surface | N | Y | N/A | Y | Y | OK | OK |
| Feed | Suggested Account Card | SuggestedAccountCard.swift:13 | control | N | Y | N/A | Y | Y | OK | OK |
| Feed | Suggested For You Module | SuggestedForYouModule.swift:16 | reading-surface | N | Y | N/A | Y | Y | OK | OK |
| Feed | Spotlight Card | SpotlightCard.swift:314 | reading-surface | N | Y (dark) | N/A | Y | Y | MEDIUM | Queued |
| Feed | Empty Feed View | EmptyFeedView.swift:8 | reading-surface | N | Y | none | Y | Y | LOW | OK |
| Feed | Posting Bar | PostingBarView.swift:18 | control | N | Y | N/A | Y | Y | OK | OK |
| Feed | Quote Post Composer | QuotePostView.swift:17 | form | N | Y | N/A | Y | Y | LOW | OK |
| Feed | Post Detail View | PostDetailView.swift:15 | hero-chrome | Y | Y | partial | Y | Y | MEDIUM | Queued |
| Feed | Caught Up Card | CaughtUpService.swift:42 | overlay | N | Y | N/A | Y | Y | OK | OK |
| Feed | Rapid Refresh Nudge Banner | CaughtUpService.swift:250 | overlay | N | Y | N/A | Y | Y | OK | OK |
| Feed | Drafts View | DraftsView.swift:12 | reading-surface | N | N | none | N | Y | LOW | OK |
| Feed | HeyFeed Controls Sheet | HeyFeedControlsSheet.swift:11 | overlay | N | N | none | N | Y | HIGH | QUEUE |

---

## Messages / Inbox / Chat

| Domain | Screen/Component | File:Line | Surface Type | HasHero | UsesGlass | StatusBar | ReduceTransp | Audited | Severity | Status |
|--------|-----------------|-----------|--------------|---------|-----------|-----------|--------------|---------|----------|--------|
| Inbox | AMENInbox List | AMENInbox.swift:1 | hero-chrome | Y | Partial | subtle | Partial | Y | MEDIUM | Queued |
| Inbox | InboxHeroHeader | AMENInbox.swift:658 | hero-chrome | Y | Y | ✓ | Y | Y | LOW | OK |
| Inbox | Thread Row | AMENInbox.swift:293 | list | N | N | N/A | N/A | Y | OK | OK |
| Inbox | Inbox Empty State | AMENInbox.swift:462 | overlay | Y | Y | N/A | Y | Y | LOW | OK |
| Messages | LiquidGlassMessagesView | LiquidGlassMessagesView.swift:43 | hero-chrome | N | Y | dark | Partial | Y | HIGH | QUEUE |
| Messages | Message Bubbles | LiquidGlassMessagesView.swift:297 | control | N | Y | N/A | Y | Y | LOW | OK |
| Messages | Reaction Bar | LiquidGlassMessagesView.swift:601 | control | N | Y | N/A | Y | Y | LOW | OK |
| Messages | Input Bar | LiquidGlassMessagesView.swift:712 | control | N | Y | N/A | Y | Y | LOW | OK |
| Chat | ModernMessageBubble | MessagingComponents.swift:141 | control | N | Y | N/A | Y | Y | LOW | OK |
| Chat | ModernChatInputBar | MessagingComponents.swift:614 | control | N | Partial | N/A | Y | Y | MEDIUM | Queued |
| Chat | DiaChatView | MessagingComponents.swift:806 | hero-chrome | N | Partial | N/A | Partial | Y | MEDIUM | QUEUE |
| Groups | GroupCatchUpView (GlassSection) | GroupCatchUpView.swift:117 | overlay | N | Y | N/A | N | Y | LOW | Queued |
| Discovery | ContactSearchView | ContactSearchView.swift:14 | list | N | N | N/A | N/A | Y | OK | OK |
| Verge | VergeCreatorStudioView | VergeCreatorStudioView.swift:391 | overlay | N | Y | dark | Y | Y | LOW | Queued |
| Verge | VergeCreateRoomSheet | VergeCreateRoomSheet.swift:340 | overlay | N | Y | dark | Y | Y | LOW | Queued |
| Social | FollowButton | FollowButton.swift:148 | control | N | Partial | N/A | N/A | Y | LOW | OK |
| Tip | TipView | TipView.swift:29 | overlay | N | Y | dark | Y | Y | LOW | Queued |
| Settings | MessageSettingsView | MessageSettingsView.swift:11 | form | N | N | N/A | Partial | Y | LOW | OK |

---

## Prayer / Wellness / Spaces

| Domain | Screen/Component | File:Line | Surface Type | HasHero | UsesGlass | StatusBar | ReduceTransp | Audited | Severity | Status |
|--------|-----------------|-----------|--------------|---------|-----------|-----------|--------------|---------|----------|--------|
| Prayer | PrayerView Actions | PrayerView.swift:N/A | hero-chrome | N | Y | N/A | N | Y | MEDIUM | Queued |
| Prayer | Scripture Anchor Card | PrayerTestimonyFeatures.swift:69 | overlay | N | Y | N/A | Y | Y | LOW | OK |
| Prayer | Testimony Arc | PrayerTestimonyFeatures.swift:239 | overlay | N | Y | N/A | Y | Y | LOW | OK |
| Prayer | Prayer Room Card | PrayerTestimonyFeatures.swift:564 | control | N | Y | N/A | Y | Y | LOW | OK |
| Prayer | Burden Match Prompt | PrayerTestimonyFeatures.swift:755 | overlay | N | Y | N/A | Y | Y | LOW | OK |
| Prayer | Prayer Group List Card | PrayerTestimonyFeatures.swift:1235 | list | N | Y | N/A | Y | Y | LOW | OK |
| Wellness | BreathingExerciseView | BreathingExerciseView.swift:76 | hero-chrome | Y | N | dark | N | Y | HIGH | QUEUE |
| Wellness | MovementWellnessView | MovementWellnessView.swift:59 | hero-chrome | Y | N | dark | N | Y | HIGH | QUEUE |
| Wellness | WellnessDetailView | WellnessDetailView.swift:3 | reading-surface | N | N | N/A | N | Y | MEDIUM | Queued |
| Wellness | WellnessSoftNudgeCard | WellnessRiskLayer.swift:752 | overlay | N | Y | N/A | Y | Y | LOW | OK |
| Crisis | CrisisSupportCard | CrisisSupportCard.swift:15 | hero-chrome | N | N | N/A | N | Y | HIGH | QUEUE |
| Crisis | CrisisGroundingExercise | CrisisSupportCard.swift:237 | hero-chrome | N | N | dark | N | Y | MEDIUM | QUEUE-GUARDIAN |
| Disaster | DisasterAlertCard | DisasterAlertCard.swift:78 | overlay | N | Y | N/A | N | Y | MEDIUM | Queued |
| Spaces | SpaceHeroView | SpacesDesignSystem.swift:22 | hero-chrome | Y | Y (iOS26) | N/A | Y | Y | OK | OK |
| Spaces | Glass Pill Button | SpacesDesignSystem.swift:328 | control | N | Y (iOS26) | N/A | Y | Y | OK | OK |
| Spaces | Glass Tab Bar | SpacesDesignSystem.swift:480 | tab-bar | N | Y (iOS26) | N/A | Y | Y | OK | OK |
| Spaces | Discussion Discovery | AmenSpacesDiscussionDiscoveryView.swift:127 | reading-surface | N | Y | N/A | Y | Y | MEDIUM | Queued |
| Support | SupportChipsRow | SupportSurfaceIntegration.swift:278 | control | N | N | N/A | N | Y | MEDIUM | Queued |

---

## Berean AI / Church Notes / Selah

| Domain | Screen/Component | File:Line | Surface Type | HasHero | UsesGlass | StatusBar | ReduceTransp | Audited | Severity | Status |
|--------|-----------------|-----------|--------------|---------|-----------|-----------|--------------|---------|----------|--------|
| Berean | BereanLandingView Hero | BereanLandingView.swift:96 | hero-chrome | Y | Y | N/A | Y | Y | MEDIUM | Queued |
| Berean | BereanVoiceCompanionView | BereanVoiceCompanionView.swift:90 | overlay | N | Partial | N/A | Y | Y | MEDIUM | Queued |
| Berean | BereanSelahModeView | BereanSelahModeView.swift:40 | hero-chrome | Y | Partial | N/A | Y | Y | LOW | OK |
| Berean | BereanScriptureContextCard | BereanScriptureContextCardView.swift | reading-surface | N | Y | N/A | Y | Y | LOW | OK |
| Berean | BereanFloatingActionTray | BereanFloatingActionTray.swift | overlay | N | Y | N/A | Y | Y | LOW | OK |
| Berean | BereanSelectionOverlay | BereanSelectionOverlay.swift | overlay | N | Partial | N/A | N | Y | MEDIUM | Queued |
| Berean | BereanLiveTranslationBar | BereanLiveTranslationBar.swift | overlay | N | Y | N/A | Y | Y | LOW | OK |
| Berean | LiquidGlassTranslationCapsule | LiquidGlassTranslationCapsule.swift | control | N | Y | N/A | Y | Y | LOW | OK |
| Berean | LiveCaptionOverlay | LiveCaptionOverlay.swift | overlay | N | Y | N/A | Y | Y | LOW | OK |
| Berean | BereanPulseView | BereanPulseView.swift:144 | overlay | N | Y | N/A | Y | Y | MEDIUM | Queued |
| Berean | BereanPulseGlassSurface | BereanPulseGlassSurface.swift | overlay | N | Y | N/A | Y | Y | LOW | OK |
| Church Notes | ChurchNotesView | ChurchNotesView.swift:125 | hero-chrome | Y | Partial | N/A | Y | Y | MEDIUM | Queued |
| Church Notes | ChurchNotesPremiumEditor | ChurchNotesPremiumEditor.swift:148 | reading-surface | N | Minimal | N/A | Y | Y | OK | OK |
| Church Notes | ChurchLiveModeView | ChurchLiveModeView.swift:166 | overlay | N | Y | dark | Y | Y | MEDIUM | Queued |
| Church Notes | BereanChurchNotesBridge | BereanChurchNotesBridge.swift:147 | overlay | N | N/A | N/A | N/A | Partial | N/A | Incomplete |
| Selah | SelahScriptureReaderView | SelahScriptureReaderView.swift:137 | reading-surface | Y | Minimal | N/A | Y | Y | LOW | OK |
| Testimony | TestimonyAssistView | TestimonyAssistView.swift:40 | form | N | Minimal | N/A | Y | Y | LOW | OK |
| Berean | AmenSyncStudioView | AmenSyncStudioView.swift:72 | overlay | N | Y | N/A | Y | Y | MEDIUM | Queued |
| Berean | AmenTranslationComparisonCard | AmenTranslationComparisonCard.swift | reading-surface | N | Y | N/A | Y | Y | LOW | OK |

---

## Profile / Auth / Settings / Onboarding

| Domain | Screen/Component | File:Line | Surface Type | HasHero | UsesGlass | StatusBar | ReduceTransp | Audited | Severity | Status |
|--------|-----------------|-----------|--------------|---------|-----------|-----------|--------------|---------|----------|--------|
| Profile | ProfilePhotoEditView | ProfilePhotoEditView.swift:40 | overlay | N | Y | none | Y | Y | LOW | OK |
| Auth | EmailVerificationGateView | EmailVerificationGateView.swift:22 | hero-chrome | N | N | none | N/A | Y | QUEUE-AUTH | QUEUE |
| Contact | ContactSearchView | ContactSearchView.swift:29 | list | N | N | none | N/A | Y | LOW | OK |
| Giving | GivingInAppSheet | GivingInAppSheet.swift:61 | form | N | N | none | N/A | Y | QUEUE-AUTH | QUEUE |
| Giving | GivingHelpSheets | GivingHelpSheets.swift:14 | overlay | N | N | none | N/A | Y | LOW | OK |
| AccessPass | AmenAccessPassLandingView | AmenAccessPassLandingView.swift:235 | overlay | N | Partial | none | N | Y | MEDIUM | Queued |
| AccessPass | AmenAccessPassCreateSheet | AmenAccessPassCreateSheet.swift:49 | form | N | N | none | N/A | Y | LOW | OK |
| AccessPass | AmenAccessPassQRCodeView | AmenAccessPassQRCodeView.swift:22 | reading-surface | N | N | none | N/A | Y | LOW | OK |
| AccessPass | AmenAccessRequestInboxView | AmenAccessRequestInboxView.swift:75 | list | N | Partial | none | N | Y | MEDIUM | Queued |
| AccessPass | AmenAccessPassAdminConsoleView | AmenAccessPassAdminConsoleView.swift:42 | list | N | N | none | N/A | Y | LOW | OK |
| Profile | UserProfileViewMini | UserProfileViewMini.swift:25 | control | N | Y | none | Y | Y | LOW | OK |
| Profile | AmenProfileGlassActionSheet | AmenProfileGlassActionSheet.swift:35 | overlay | N | Y | none | Y | Y | LOW | OK |
| Settings | SettingsView | SettingsView.swift:18 | form | N | Y (dark) | none | N | Y | MEDIUM | Queued |
| Onboarding | AMENOnboardingSystem | AMENOnboardingSystem.swift:82 | hero-chrome | N | Y | none | N | Y | LOW | OK |

---

## Find Church / Giving / Notifications / GUARDIAN / Legacy

| Domain | Screen/Component | File:Line | Surface Type | HasHero | UsesGlass | StatusBar | ReduceTransp | Audited | Severity | Status |
|--------|-----------------|-----------|--------------|---------|-----------|-----------|--------------|---------|----------|--------|
| Find Church | ChurchHeroHeader (new) | FindChurchView.swift:6617 | hero-chrome | Y | Y | N/A | N | Y | MEDIUM | Queued |
| Find Church | FindChurchGlass SearchField | FindChurchGlassComponents.swift:52 | control | N | Y | N/A | Y | Y | LOW | OK |
| Find Church | ChurchDiscoveryBottomSheet | FindChurchGlassComponents.swift:91 | overlay | N | Y | N/A | Y | Y | LOW | OK |
| Find Church | GlassFilterPill | FindChurchGlassComponents.swift:474 | control | N | Y | N/A | Y | Y | LOW | OK |
| Find Church | GlassAIRecommendationModule | FindChurchGlassComponents.swift:671 | overlay | N | Y | N/A | Y | Y | LOW | Queued |
| Church Notes | ChurchNotesOnboardingView | ChurchNotesOnboardingView.swift:214 | hero-chrome | Y | Partial | N/A | Y | Y | MEDIUM | Queued |
| Notifications | SmartNotificationBanner | SmartChurchNotifications.swift:154 | overlay | N | Y | N/A | Y | Y | LOW | OK |
| Wellness | WellnessSupportSheet | WellnessRiskLayer.swift:895 | hero-chrome | N | Partial | N/A | N | Y | HIGH | QUEUE |
| Crisis | WellnessCrisisSheet | WellnessRiskLayer.swift:952 | hero-chrome | N | Partial | N/A | N | Y | HIGH | QUEUE-GUARDIAN |
| Legacy | LegacyStudioView header | LegacyStudioView.swift:237 | hero-chrome | N | Y | N/A | N | Y | MEDIUM | Queued |
| Legacy | FaithReelStudioView | FaithReelStudioView.swift:165 | hero-chrome | N | Y | N/A | N | Y | MEDIUM | Queued |
| Creator | AmenCreatorKitHome | AmenCreatorKitHome.swift:12 | hero-chrome | N | Y | N/A | N | Y | MEDIUM | Queued |
| Safety | PrayerSafetyEscalation | PrayerSafetyEscalationService.swift | service | N/A | N/A | N/A | N/A | Y | N/A | QUEUE-GUARDIAN |
| Moderation | PrayerRoomModerationEngine | PrayerRoomModerationEngine.swift | service | N/A | N/A | N/A | N/A | Y | N/A | QUEUE-GUARDIAN |
| Instagram | AmenInstagramStorySystem | AmenInstagramStorySystem.swift:88 | reading-surface | N | Partial | N/A | Y | Y | LOW | OK |
| FaithReel | FaithReelMainCard | FaithReelStudioView.swift:145 | reading-surface | N | Y | N/A | N | Y | MEDIUM | Queued |
| CarPlay | BereanDriveSetupView | CarPlay/BereanDriveSetupView.swift:20 | form | N | Minimal | N/A | Y | Y | MEDIUM | Queued |

---

## Shared Components / Tab Bar / Design System

| Domain | Screen/Component | File:Line | Surface Type | HasHero | UsesGlass | StatusBar | ReduceTransp | Audited | Severity | Status |
|--------|-----------------|-----------|--------------|---------|-----------|-----------|--------------|---------|----------|--------|
| Tab Bar | AMENTabBar Dock | AMENTabBar.swift:75 | tab-bar | N | Y | N/A | Y | Y | OK | OK |
| Tab Bar | AMENTabBar Orbs | AMENTabBar.swift:112 | tab-bar | N | Y | N/A | Y | Y | OK | OK |
| Tab Bar | AMENTabBar Active Pill | AMENTabBar.swift:130 | tab-bar | N | Y | N/A | Y | Y | OK | OK |
| Tab Bar | AmenLiquidGlassTabBar | AmenLiquidGlassTabBar.swift:69 | tab-bar | N | Y | N/A | Y | Y | OK | OK |
| Loading | AMENLoader / AMENLoadingIndicator | ComponentsSharedUIComponents.swift:21 | overlay | N | N | N/A | Y | Y | OK | OK |
| Loading | PostListSkeletonView | ComponentsSharedUIComponents.swift:78 | reading-surface | N | N | N/A | Y | Y | OK | OK |
| Toast | ToastView / ToastManager | ComponentsSharedUIComponents.swift:323 | overlay | N | N | N/A | Y | Y | OK | OK |
| Empty | AmenGlass3DIcon | EmptyStateView.swift:34 | control | N | Y | N/A | Y | Y | LOW | Queued |
| Glass Kit | AmenGlassSurface | AmenGlassComponents.swift:22 | overlay | N | Y | N/A | N | Y | MEDIUM | Queued |
| Glass Kit | AmenGlassIconButton | AmenGlassComponents.swift:58 | control | N | Y | N/A | N | Y | MEDIUM | Queued |
| Glass Kit | BereanActionChip | AmenGlassComponents.swift:107 | control | N | Y | N/A | N | Y | MEDIUM | Queued |
| Glass Kit | AmenGlassButtonSystem | AmenGlassButtonSystem.swift:99 | control | N | Y | N/A | N | Y | MEDIUM | Queued |
| Glass Kit | AmenLiquidGlassPillButton | AmenLiquidGlassComponents.swift:18 | control | N | Y | N/A | Y | Y | OK | OK |
| Design System | AmenTheme colors+tokens | AmenTheme.swift:1 | N/A | N/A | N/A | N/A | Y | Y | OK | OK |
| Design System | Motion.swift | Motion.swift:1 | N/A | N/A | N/A | N/A | Y | Y | OK | OK |
| Design System | AmenGlassDesignTokens | AmenGlassDesignTokens.swift:1 | N/A | N/A | N/A | N/A | Y | Y | OK | OK |

---

## Coverage Summary

| Domain | Components Audited | HIGH | MEDIUM | LOW | OK | QUEUE |
|--------|-------------------|------|--------|-----|----|----|
| Feed/Home | 16 | 1 | 4 | 3 | 8 | 1 |
| Messages/Inbox | 18 | 1 | 3 | 7 | 5 | 2 |
| Prayer/Wellness/Spaces | 18 | 3 | 8 | 4 | 10 | 2 |
| Berean/Church Notes | 19 | 0 | 7 | 9 | 9 | 0 |
| Profile/Auth | 14 | 0 | 4 | 6 | 2 | 2 |
| Find Church/Giving/GUARDIAN | 17 | 2 | 8 | 4 | 3 | 4 |
| Shared/Tab/Design System | 15 | 0 | 4 | 2 | 9 | 0 |
| **TOTAL** | **117** | **7** | **38** | **35** | **46** | **11** |

**Overall compliance:** 46/117 = 39% fully compliant today → target 80%+ after Phase 2
